using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using PhotoTrail.Windows;

static class LaunchScopeChecks
{
    internal static async Task RunAsync()
    {
        var root = Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Select isolated output"), "launch-scope");
        if (Directory.Exists(root)) throw new Exception("Preserve earlier run");
        Directory.CreateDirectory(root);
        Environment.SetEnvironmentVariable("PHOTOTRAIL_RENAME_COUNTERS", Path.Combine(root,"counters.json"));
        Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY", Path.Combine(root,"inplace-history"));
        int count=0;
        void Check(bool value,string name){if(!value)throw new Exception(name);count++;Console.WriteLine("PASS "+name);}
        async Task Block(Func<Task> action,string name){bool refused=false;try{await action();}catch(InvalidOperationException e)when(e.Message.Contains("首发")){refused=true;}catch(System.IO.InvalidDataException e)when(e.Message.Contains("首发")){refused=true;}Check(refused,name);}
        Task Call(Action action){action();return Task.CompletedTask;}
        var source=Path.Combine(root,"photo.jpg");File.WriteAllBytes(source,[1,2,3,4]);var before=SHA256.HashData(File.ReadAllBytes(source));
        var jsonOptions=new JsonSerializerOptions{PropertyNamingPolicy=JsonNamingPolicy.CamelCase};
        var safe=new RenameRule("action","photo"){Action="set",Id=Guid.NewGuid()};
        var baseScheme=new RenameScheme(Guid.NewGuid(),"Photo",RenamePlan.EncodeEditorRules([safe]),new(),"");
        var macBase=MacRenamePreset.Export(baseScheme);
        foreach(var action in RenameTransform.Actions.Where(p=>p.Value is >=72 and <=77))foreach(bool enabled in new[]{true,false})
        {
            var music=new RenameRule("action","<Artist>"){Action=action.Key,Enabled=enabled};var rules=new[]{safe,music};
            string text=RenamePlan.EncodeEditorRules(rules);Check(RenamePlan.ParseRules(text).Count==2,"structural old rules retained "+action.Key+enabled);
            await Block(()=>Call(()=>RenamePlan.Apply("photo.jpg",rules,0)),"whole mixed apply blocked "+action.Key+enabled);
            await Block(async()=>{await RenamePlan.ApplyAsync("photo.jpg",rules,0);},"whole mixed async blocked "+action.Key+enabled);
            await Block(async()=>{await RenamePlan.BuildAsync([source],rules,false);},"freeze API blocked "+action.Key+enabled);
            var scheme=baseScheme with{Rules=text};
            await Block(()=>Call(()=>RenameSchemeLibrary.Export(scheme)),"Windows compatible export blocked "+action.Key+enabled);
            await Block(()=>Call(()=>MacRenamePreset.Export(scheme)),"Mac compatible export blocked "+action.Key+enabled);
            string windows=JsonSerializer.Serialize(new{format="phototrail-windows-rename-scheme",version=3,scheme},jsonOptions);
            await Block(()=>Call(()=>RenameSchemeLibrary.Import(windows,"old")),"Windows whole import blocked "+action.Key+enabled);
            var mac=JsonNode.Parse(macBase)!;mac["rules"]![0]!["action"]=action.Value;mac["rules"]![0]!["enabled"]=enabled;
            await Block(()=>Call(()=>RenameSchemeLibrary.Import(mac.ToJsonString(),"mac")),"Mac whole import blocked "+action.Key+enabled);
            var plan=(await RenamePlan.BuildTargetsAsync([(source,"other.jpg")])) with{SourceRules=rules};
            await Block(async()=>{await RenameExecutor.ExecuteAsync(plan,Path.Combine(root,"blocked-journal"));},"execution API provenance blocked "+action.Key+enabled);
            await Block(()=>Call(()=>RenameTransform.Apply("photo.jpg",music,0,null,null,null)),"direct transform blocked "+action.Key+enabled);
        }
        foreach(var token in new[]{"Song","Album","Artist_Upper","ARTIST","artist","TrackNum","0CDNum","Duration_MM_SS"})
        {
            var rule=new RenameRule("action","<"+token+">"){Action="template-set",Enabled=false};
            await Block(()=>Call(()=>RenamePlan.Apply("photo.jpg",[safe,rule],0)),"music-only generic token blocked "+token);
        }
        foreach(var template in new[]{"<Artist>","<IFD0:Artist>","<XMP-dc:Creator>","<FileName>","literal Artist"})
        {
            string? Tags(string name)=>name is "Artist" or "IFD0:Artist" or "XMP-dc:Creator"?"Photo Author":name=="FileName"?"photo":null;
            Check(RenamePlan.Apply("old.jpg",[new("action",template){Action="template-set"}],0,Tags).Length>0,"ordinary author/photo template retained "+template);
        }
        var deferred=baseScheme with{Id=Guid.NewGuid(),Name="Old music",Rules=RenamePlan.EncodeEditorRules([new("action","<Artist>"){Action="music-set",Enabled=false}])};
        var state=new RenameSchemeState("phototrail-windows-rename-library",2,true,deferred.Id,[deferred,baseScheme]);
        var path=Path.Combine(root,"old-library.json");var bytes=JsonSerializer.SerializeToUtf8Bytes(state,jsonOptions);File.WriteAllBytes(path,bytes);
        var opened=RenameSchemeLibrary.Open(path);Check(opened.State.Schemes[0]==deferred&&File.ReadAllBytes(path).SequenceEqual(bytes),"old library load preserves complete deferred scheme and original bytes");
        var snapshot=RenameSchemeLibrary.Save(path,opened,opened.State with{LastId=baseScheme.Id});Check(snapshot.State.Schemes[0]==deferred,"nonmusic selection preserves old deferred entry");
        await Block(()=>Call(()=>RenameSchemeLibrary.Save(path,snapshot,snapshot.State with{Schemes=[..snapshot.State.Schemes,deferred with{Id=Guid.NewGuid(),Name="new music"}]})),"new music cannot enter library via save API");
        Check(SHA256.HashData(File.ReadAllBytes(source)).SequenceEqual(before)&&!Directory.Exists(Path.Combine(root,"blocked-journal")),"rejection preserves file and creates no journal");
        Check(!File.Exists(Path.Combine(root,"counters.json"))&&!File.Exists(Path.Combine(root,"counters.json.pending")),"rejection neither initializes nor consumes counters");
        Console.WriteLine(count+" non-music launch scope assertions passed");
    }
}
