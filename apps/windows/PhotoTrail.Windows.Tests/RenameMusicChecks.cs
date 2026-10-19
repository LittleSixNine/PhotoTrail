using PhotoTrail.Windows;
using System.Text.Json;

static class RenameMusicChecks
{
 internal static async Task RunAsync()
 {
  var output=Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")!;
  var root=Path.Combine(output,"music-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  var file=Path.Combine(root,"old.jpg");File.Copy(Directory.GetFiles(Environment.GetEnvironmentVariable("PHOTOTRAIL_FIXTURES")!,"*.jpg")[0],file);
  var tool=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
  await tool.RunAsync(["-overwrite_original","-XMP-xmpDM:Artist=Synthetic Artist","-XMP-xmpDM:Album=Synthetic Album","-XMP-xmpDM:TrackNumber=3","-XMP-dc:Title=Synthetic Song","--",file],rejectWarnings:true);
  var data=await tool.ReadAsync(file);var input=new RenameInput(file,data.EnumerateObject().ToDictionary(p=>p.Name,p=>PhotoDocument.Text(p.Value)));
  var checks=new List<object>();void Check(bool ok,string name){checks.Add(new{name,passed=ok});if(!ok)throw new Exception(name);}
  Check(input.Tag("Artist")=="Synthetic Artist"&&input.Tag("Album")=="Synthetic Album"&&input.Tag("Song")=="Synthetic Song"&&input.Tag("0TrackNum")=="03","real-JPEG-XMP-read-aliases");
  var aliases=new RenameInput(file,new Dictionary<string,string>{{"ID3:Track","7/20"},{"ID3:DiscNumber","2/4"},{"XMP-dc:Creator","Creator"},{"ID3:Band","Band"}});
  Check(aliases.Tag("TrackNum")=="7"&&aliases.Tag("NumTracks")=="20"&&aliases.Tag("CDNum")=="2"&&aliases.Tag("numCds")=="4"&&aliases.Tag("0TrackNum")=="07"&&aliases.Tag("Artist")=="Creator"&&aliases.Tag("AlbumArtist")=="Band","raw-alias-and-disc-fallback-vectors");
  Check(input.Tag("Artist_Upper")=="SYNTHETIC ARTIST"&&input.Tag("Artist_Lower")=="synthetic artist"&&input.Tag("Song_Capitalized")=="Synthetic Song"&&input.Tag("Song_sentence_case")=="Synthetic song","derived-ASCII-music-case-tokens");
  Check(aliases.Tag("0Track")=="07"&&aliases.Tag("Album_Artist_sentence_case")=="Band","zero-track-and-alternate-album-artist-token");
  foreach(var (raw,seconds,minutes,hours) in new[]{("65.5","65.5","01_05","00_01_05"),("1:05","65.0","01_05","00_01_05"),("1:02:03.9","3723.9","62_03","01_02_03"),("0 s","0.0","00_00","00_00_00")}){
   var duration=new RenameInput(file,new Dictionary<string,string>{{"QuickTime:Duration",raw}});
   Check(duration.Tag("DurationInSeconds")==seconds&&duration.Tag("Duration_MM_SS")==minutes&&duration.Tag("Duration_HH_MM_SS")==hours,"duration-format-"+raw);
  }
  foreach(var raw in new[]{"NaN","Infinity","-1","1000000000","1:bad","1: 2"})Check(new RenameInput(file,new Dictionary<string,string>{{"QuickTime:Duration",raw}}).Tag("DurationInSeconds")is null,"invalid-duration-preserves-missing-"+raw);
  Check(new RenameInput(file,new Dictionary<string,string>{{"QuickTime:Duration"," 65 s"}}).Tag("DurationInSeconds")=="65.0"&&new RenameInput(file,new Dictionary<string,string>{{"QuickTime:Duration","1::2"}}).Tag("DurationInSeconds")=="62.0"&&new RenameInput(file,new Dictionary<string,string>{{"QuickTime:Duration","1e-7"}}).Tag("DurationInSeconds")=="1e-07","duration-tokenization-and-exponent-source-vectors");
  var actions=new[]{"music-set","music-end","music-begin","music-before","music-after","music-position"};
  var text="Synthetic Artist_Synthetic Album_03_Synthetic Song";
  var expected=new[]{text+".jpg","old"+text+".jpg",text+"old.jpg",text+"old.jpg","old"+text+".jpg","o"+text+"ld.jpg"};
  var hash=await PhotoDocument.HashAsync(file);
  foreach(var (action,index) in actions.Select((a,i)=>(a,i)))
  {
   var rule=new RenameRule("action","<Artist>_<Album>_<0TrackNum>_<Song>"){Action=action,Anchor="old",Position=1};
   var result=RenamePlan.Apply("old.jpg",[rule],0,input.Tag);Check(result==expected[index],action+"-fixed-Mac-source-mode-map");
   var scheme=new RenameScheme(Guid.NewGuid(),action,JsonSerializer.Serialize(rule),new(),"");
   var imported=RenameSchemeLibrary.Import(MacRenamePreset.Export(scheme),action);
   Check(RenamePlan.Apply("old.jpg",RenamePlan.ParseRules(imported.Rules),0,input.Tag)==result,action+"-v1-roundtrip-parameters");
   var plan=await RenamePlan.BuildTargetsAsync([(file,result)]);var executed=await RenameExecutor.ExecuteAsync(plan,Path.Combine(root,"journals"));
   Check(executed.Complete&&await PhotoDocument.HashAsync(Path.Combine(root,result))==hash,action+"-real-file-execute-independent-SHA");
   Check((await RenameExecutor.RestoreAsync(executed.Journal,Path.Combine(root,"journals"))).Complete&&await PhotoDocument.HashAsync(file)==hash,action+"-record-restore-SHA");
   var missing=rule with{Text="<MissingMusicTag>"};Check(RenamePlan.Apply("old.jpg",[missing],0,input.Tag)=="old.jpg",action+"-missing-tag-preserves-original");
  }
  Check(RenamePlan.Apply("old.jpg",[new RenameRule("action","ignored"){Action="music-set",Enabled=false}],0,input.Tag)=="old.jpg","disabled-music-rule-does-not-execute");
  File.WriteAllText(Path.Combine(root,"music-results.json"),JsonSerializer.Serialize(new{checks,source="real synthetic JPEG XMP; expected modes from fixed Mac source, not a Mac runtime measurement"},new JsonSerializerOptions{WriteIndented=true}));
  Console.WriteLine(checks.Count+" music template checks passed; "+root);
 }
}
