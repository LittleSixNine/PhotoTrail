using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace PhotoTrail.Windows;
internal sealed record RenameCounterSnapshot(string Revision,IReadOnlyDictionary<int,long> Values);
internal sealed record RenameCounterUse(RenameCounterSnapshot Snapshot,IReadOnlyDictionary<int,long> Advances);
internal static class RenameCounters
{
    internal static string DefaultPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_RENAME_COUNTERS")??Path.Combine(Path.GetDirectoryName(RenameSchemeLibrary.DefaultPath)!,"rename-counters-v1.json");
    sealed record State(string Format,int Version,Dictionary<int,long> Values);
    sealed record Pending(string Id,RenameFile[] Files,Dictionary<int,long> Advances,RenameCounterSnapshot Snapshot);
    static readonly JsonSerializerOptions Json=new(){PropertyNamingPolicy=JsonNamingPolicy.CamelCase};
    static string Revision(string path)=>File.Exists(path)?Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))):"missing";
    static void PlainFile(string path){InplaceNative.RequireLocalVolume(path);if(!File.Exists(path))return;if(new FileInfo(path).Length>RenameSchemeLibrary.MaximumBytes||(File.GetAttributes(path)&(FileAttributes.ReparsePoint|FileAttributes.ReadOnly))!=0)throw new IOException("计数文件过大、只读或链接；原记录保留。");using var file=WindowsRename.Open(path);_=WindowsRename.Properties(file,path);}
    static RenameCounterSnapshot ReadState(string path) {
        PlainFile(path);if(!File.Exists(path))return new("missing",Enumerable.Range(1,10).ToDictionary(i=>i,_=>1L));
        var bytes=File.ReadAllBytes(path);using var document=JsonDocument.Parse(bytes);
        var fields=document.RootElement.GetProperty("values");if(fields.ValueKind!=JsonValueKind.Object||fields.EnumerateObject().Any(p=>!int.TryParse(p.Name,out var i)||i is <1 or >10||p.Name!=i.ToString(System.Globalization.CultureInfo.InvariantCulture)))throw new InvalidDataException("计数器槽位格式无效。");
        var state=RenameSchemeLibrary.Decode<State>(System.Text.Encoding.UTF8.GetString(bytes));if(state.Format!="phototrail-windows-rename-counters"||state.Version!=1||state.Values.Count!=10||state.Values.Any(p=>p.Key is <1 or >10||p.Value<0))throw new InvalidDataException("计数状态无效，不重置或推断。");
        return new(Convert.ToHexString(SHA256.HashData(bytes)),state.Values);
    }
    internal static RenameCounterSnapshot Read(string path){if(File.Exists(path+".pending"))throw new IOException("持续计数有未确认执行，先按实际记录恢复/核对；不重用未知编号。");return ReadState(path);}
    static Pending ReadPending(string path){InplaceNative.RequireLocalVolume(path);if((File.GetAttributes(path+".pending")&FileAttributes.ReparsePoint)!=0)throw new IOException("计数执行记录为链接。");using var file=new FileStream(path+".pending",FileMode.Open,FileAccess.Read,FileShare.ReadWrite);if(file.Length>RenameSchemeLibrary.MaximumBytes)throw new InvalidDataException("计数执行记录过大。");_=WindowsRename.Properties(file,path+".pending");using var reader=new StreamReader(file,new System.Text.UTF8Encoding(false,true),false);var pending=RenameSchemeLibrary.Decode<Pending>(reader.ReadToEnd());if(!Guid.TryParseExact(pending.Id,"N",out _)||pending.Files.Length is <1 or >6000||pending.Files.Any(f=>f is null||f.Hash.Length!=64||f.Hash.Any(c=>!char.IsAsciiHexDigit(c))||Path.GetFullPath(f.Source)!=f.Source||Path.GetDirectoryName(f.Source)!=Path.GetDirectoryName(f.Target))||pending.Snapshot.Values.Count!=10)throw new InvalidDataException("未知计数执行记录结构无效，未清理。");return pending;}
    internal static void RequireClear(IEnumerable<string> paths,string? ownedReservation=null){var path=DefaultPath;if(!File.Exists(path+".pending"))return;var pending=ReadPending(path);if(pending.Id==ownedReservation)return;var scope=paths.ToHashSet(StringComparer.OrdinalIgnoreCase);if(pending.Files.Any(f=>scope.Contains(f.Source)||scope.Contains(f.Target)))throw new IOException("来源涉及未确认计数执行；先显式恢复/核对，不能继续写入或更名。");}
    static FileStream Guard(string path){Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);PlainFile(path+".guard");return new(path+".guard",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
    static void Save(string path,RenameCounterSnapshot expected,IReadOnlyDictionary<int,long> values){if(Revision(path)!=expected.Revision)throw new IOException("执行期间计数文件改变；保留未知记录，未覆写。");SettingsPreference.WriteJson(path,JsonSerializer.SerializeToElement(new State("phototrail-windows-rename-counters",1,values.ToDictionary()),Json));}
    internal static void Reset(string path,IReadOnlyList<RenameRule> rules){using var gate=Guard(path);var snapshot=Read(path);var used=rules.Where(r=>r.Enabled&&r.Counter>0).ToArray();if(used.Select(r=>r.Counter).Distinct().Count()!=used.Length||used.Any(r=>r.Start<0))throw new ArgumentException("计数器重设参数无效。");var values=snapshot.Values.ToDictionary();foreach(var rule in used)values[rule.Counter]=rule.Start;Save(path,snapshot,values);}
    internal static async Task<RenameResult> ExecuteAsync(RenamePlan plan,RenameCounterUse use,string path,string history,CancellationToken token,Action<int,int>? progress=null) {
        using var parents=SavePaths.LockParents(path,false);using var gate=Guard(path);var current=Read(path);
        if(current.Revision!=use.Snapshot.Revision||use.Advances.Keys.Any(i=>current.Values.GetValueOrDefault(i)!=use.Snapshot.Values.GetValueOrDefault(i)))throw new IOException("计数器已变化，请重新冻结；未执行。");
        var ticket=new Pending(Guid.NewGuid().ToString("N"),plan.Files.ToArray(),use.Advances.ToDictionary(),current);
        var bytes=JsonSerializer.SerializeToUtf8Bytes(ticket,Json);if(bytes.Length>RenameSchemeLibrary.MaximumBytes)throw new ArgumentException("计数执行范围超过1MiB，未执行。");
        string pending=path+".pending";RenameResult? result=null;
        try {
            using(var record=new FileStream(pending,FileMode.CreateNew,FileAccess.Write,FileShare.Read)){
                record.Write(bytes);record.Flush(true);
                // Other app instances share the file lock across Windows sessions; a crash leaves the durable marker.
                result=await RenameExecutor.ExecuteCoreAsync(plan,history,token,progress,ticket.Id);
                if(!result.Complete)return result;
                var next=current.Values.ToDictionary();if(result.Files.Count>0)foreach(var value in use.Advances)next[value.Key]=value.Value;
                Save(path,current,next);
            }
            File.Delete(pending);return result;
        }catch(Exception error)when(result is not null&&error is IOException or UnauthorizedAccessException){return result with{Complete=false,Error="文件结果保留，计数提交未确认："+error.Message};}
    }
    internal static FileStream? GuardRestore(RenameResult original,out string? reservation) {
        reservation=null;var path=DefaultPath;if(!File.Exists(path+".pending"))return null;var gate=Guard(path);
        try{var pending=ReadPending(path);var scope=original.Files.SelectMany(f=>new[]{f.Source,f.Target,f.Current}).ToHashSet(StringComparer.OrdinalIgnoreCase);if(!pending.Files.Any(f=>scope.Contains(f.Source)||scope.Contains(f.Target))){gate.Dispose();return null;}
            var changed=pending.Files.Where(f=>f.Source!=f.Target).ToArray();if(changed.Length!=original.Files.Count||original.Files.Any(f=>!changed.Any(p=>p.Source==f.Source&&p.Target==f.Target&&p.Hash==f.Hash)))throw new IOException("恢复记录不是该计数执行范围；未知计数保持。");reservation=pending.Id;return gate;
        }catch{gate.Dispose();throw;}
    }
    internal static async Task ResolveAfterRestoreLockedAsync(string reservation,RenameResult restored,CancellationToken token) {
        var path=DefaultPath;if(!restored.Complete)return;var pending=ReadPending(path);if(pending.Id!=reservation)throw new IOException("计数恢复身份改变，未清理。");
        foreach(var file in pending.Files){token.ThrowIfCancellationRequested();if(!File.Exists(file.Source)||await PhotoDocument.HashAsync(file.Source,token)!=file.Hash)throw new IOException("计数执行源未全部恢复且核对，未知编号保持。");}
        var current=ReadState(path);var expected=pending.Snapshot.Values.ToDictionary();var advanced=expected.ToDictionary();foreach(var value in pending.Advances)advanced[value.Key]=value.Value;
        bool Matches(IReadOnlyDictionary<int,long> values)=>values.Count==current.Values.Count&&values.All(p=>current.Values.GetValueOrDefault(p.Key)==p.Value);if(!Matches(expected)&&!Matches(advanced))throw new IOException("计数状态被外部改变，恢复文件后仍需人工核对，不重用编号。");
        File.Delete(path+".pending");
    }
}
