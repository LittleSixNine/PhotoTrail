using PhotoTrail.Windows;
using System.Text.Json;
using System.Text.Json.Nodes;

static class V1SubsetChecks
{
 internal static async Task RunAsync()
 {
  var root=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")!,"v1-subset");Directory.CreateDirectory(root);
  var evidence=new List<object>();void Check(bool ok,string name){if(!ok)throw new Exception(name);evidence.Add(new{name,passed=true});}
  void Reject(Action call,string name){bool rejected=false;try{call();}catch(Exception e)when(e is ArgumentException or InvalidDataException or InvalidOperationException){rejected=true;}Check(rejected,name);}
  var fixture=File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"fixtures/presets/v1-template-subset.json"));
  JsonNode Source(int action,string text="<XMP-dc:Title>"){var j=JsonNode.Parse(fixture)!;j["rules"]![0]!["action"]=action;j["rules"]![0]!["text"]=text;return j;}
  RenameScheme Import(JsonNode j)=>RenameSchemeLibrary.Import(j.ToJsonString(),"source");
  string Semantic(RenameRule r)=>JsonSerializer.Serialize(r);
  var exports=new List<object>();
  foreach(var action in new[]{1,2,5,24,40,46,66,67,68,69,70,71,95,97}) {
   var j=Source(action,action==95?"old":"X");var raw=j["rules"]![0]!;raw["lexicalCases"]!["Noun"]="upper";
   if(action is 1 or 2 or 5)raw["caseSensitive"]=false;
   if(action==40)raw["dateFormat"]="yyyyMMdd";
   if(action!=40)raw["timeZone"]="Antarctica/Unresolved-legal-carried-zone";
   var scheme=Import(j);var r=RenamePlan.ParseRules(scheme.Rules)[0];
   Check(r.LexicalCases["Noun"]=="upper"&&r.CaseSensitive==raw["caseSensitive"]!.GetValue<bool>()&&r.TimeZone==raw["timeZone"]!.GetValue<string>(),"unused-values-retained-"+action);
   var path=Path.Combine(root,"library-"+action+".json");var opened=RenameSchemeLibrary.Open(path);RenameSchemeLibrary.Save(path,opened,opened.State with{Schemes=[scheme],LastId=scheme.Id});var reloaded=RenameSchemeLibrary.Open(path).State.Schemes.Single();
   Check(Semantic(RenamePlan.ParseRules(reloaded.Rules)[0])==Semantic(r),"local-library-reload-lossless-"+action);
   var encoded=MacRenamePreset.Export(reloaded);var twice=RenameSchemeLibrary.Import(encoded,"round");
   Check(Semantic(RenamePlan.ParseRules(twice.Rules)[0])==Semantic(r),"v1-both-directions-lossless-"+action);
   exports.Add(new{action,json=JsonNode.Parse(encoded)});
  }
  foreach(int action in new[]{3,4,6,7,8,9,10,11,12,13,14,15,16,70,71}){var j=Source(action);j["rules"]![0]!["caseSensitive"]=false;Reject(()=>Import(j),"executing-case-fold-remains-refused-"+action);}
  foreach(var lexical in new[]{new Dictionary<string,string>(),new Dictionary<string,string>{{"custom-unexecuted-key","lower"}}}){var j=Source(1);j["rules"]![0]!["lexicalCases"]=JsonSerializer.SerializeToNode(lexical);var scheme=Import(j);var twice=RenameSchemeLibrary.Import(MacRenamePreset.Export(scheme),"lexical");Check(JsonSerializer.Serialize(RenamePlan.ParseRules(twice.Rules)[0].LexicalCases)==JsonSerializer.Serialize(lexical),"unused-Codable-dictionary-preserved-"+lexical.Count);}
  var dateRaw="2024:02:29 23:07:08.123456789+09:00";var dates=await VerifiedPhotoDate.InspectAsync([dateRaw]);var date=dates[dateRaw];Check(date is not null,"fixed-DateHost-date-proof");
  var source=Path.Combine(root,"old.jpg");File.Copy(Directory.GetFiles(Environment.GetEnvironmentVariable("PHOTOTRAIL_FIXTURES")!,"*.jpg")[0],source);
  var original=await PhotoDocument.HashAsync(source);var fields=new Dictionary<string,string>{{"XMP-dc:Title","TITLE"},{"IFD0:Artist","Author"},{"IFD0:Model","Camera"},{"captured",dateRaw}};
  var input=new RenameInput(source,fields);string? Tag(string t)=>t=="captured"?dateRaw:input.Tag(t);
  foreach(var (action,expected) in new[]{(66,"TITLE.jpg"),(67,"TITLEold.jpg"),(68,"oldTITLE.jpg"),(69,"oTITLEld.jpg"),(70,"TITLEold.jpg"),(71,"oldTITLE.jpg")}) {
   var scheme=Import(Source(action));var rules=RenamePlan.ParseRules(scheme.Rules);var target=RenamePlan.Apply("old.jpg",rules,0,Tag);Check(target==expected,"source-mode-map-"+action);
   var plan=(await RenamePlan.BuildTargetsAsync([(source,target)])) with{SourceRules=rules};
   using(var cancel=new CancellationTokenSource()){cancel.Cancel();try{await RenameExecutor.ExecuteAsync(plan,Path.Combine(root,"journals"),cancel.Token);}catch(OperationCanceledException){}Check(File.Exists(source)&&await PhotoDocument.HashAsync(source)==original,"cancel-no-rename-"+action);}
   var outcome=await RenameExecutor.ExecuteAsync(plan,Path.Combine(root,"journals"));Check(outcome.Complete&&await PhotoDocument.HashAsync(Path.Combine(root,target))==original,"frozen-execute-SHA-"+action);
   Check((await RenameExecutor.RestoreAsync(outcome.Journal,Path.Combine(root,"journals"))).Complete&&await PhotoDocument.HashAsync(source)==original,"restore-original-SHA-"+action);
   var missing=rules[0] with{Text="<IFD0:Absent>"};Check(RenamePlan.Apply("old.jpg",[new("prefix","earlier_"),missing],0,Tag)=="old.jpg","missing-skip-resets-original-"+action);
   Check(RenamePlan.Apply("old.jpg",[new("prefix","earlier_"),missing with{SkipMissing=false}],0,Tag)=="earlier_old.jpg","missing-continue-preserves-current-"+action);
   Check(RenamePlan.Apply("old.jpg",[rules[0] with{Enabled=false}],0,Tag)=="old.jpg","disabled-retained-not-executed-"+action);
  }
  foreach(var (part,selected,left,right) in new[]{("stem","old","",".jpg"),("entire","old.jpg","",""),("dottedExtension",".jpg","old",""),("extensionOnly","jpg","old.","")})foreach(var (action,mode) in new[]{(66,0),(67,1),(68,2),(69,5),(70,3),(71,4)}) {
   var j=Source(action,"T");var raw=j["rules"]![0]!;raw["part"]=part;raw["anchor"]=selected;raw["position"]=1;raw["caseSensitive"]=action>=70;
   var scheme=Import(j);var rule=RenamePlan.ParseRules(RenameSchemeLibrary.Import(MacRenamePreset.Export(scheme),"part").Rules)[0];
   string changed=mode==0?"T":mode is 1 or 3?"T"+selected:mode is 2 or 4?selected+"T":selected[..1]+"T"+selected[1..];
   Check(RenamePlan.Apply("old.jpg",[rule],0,Tag)==left+changed+right,"part-and-mode-"+part+action);
  }
  foreach(var (occurrence,number,expected) in new[]{("all",1,"ToTo.jpg"),("first",1,"Too.jpg"),("last",1,"oTo.jpg"),("nth",2,"oTo.jpg"),("nth",3,"oo.jpg")}){var j=Source(70,"T");var raw=j["rules"]![0]!;raw["anchor"]="o";raw["occurrence"]=occurrence;raw["matchNumber"]=number;Check(RenamePlan.Apply("oo.jpg",RenamePlan.ParseRules(Import(j).Rules),0,Tag)==expected,"anchor-occurrence-"+occurrence+number);}
  Check(RenamePlan.Apply("old.jpg",RenamePlan.ParseRules(Import(Source(67,"<NULL>")).Rules),0,Tag)=="old.jpg","NULL-is-empty-not-missing");
  foreach(var token in new[]{"FileName","FileNameWithoutExtension","FileExtension","ParentFolderName","NULL","Artist","CameraMake","CameraModel","CameraSerialNumber","ImageCaption","ImageKeywords","ImageUserComment","Lens","Aperture","ShutterSpeed","FocalLength35mm","IPTCCity","IPTCProvinceState","IPTCSubLocation","IPTCCountry","ImageWidth","ImageHeight","width","height","IFD0:Artist","XMP-dc:Creator"}) {
   var scheme=Import(Source(67,"<"+token+">"));var rule=RenamePlan.ParseRules(scheme.Rules)[0];Check(MacRenamePreset.Export(scheme).Contains(token),"approved-token-roundtrip-"+token);
   var available=new RenameInput(source,new Dictionary<string,string>{{token,"VALUE"}});Check(RenamePlan.Apply("old.jpg",[rule],0,available.Tag)=="VALUEold.jpg","exact-token-execution-"+token);
  }
  foreach(var prefix in new[]{"ShootingDate","CreationDate","ModificationDate","ModDate"})foreach(var (suffix,expected) in new[]{("4DigitYear","2024"),("2DigitYear","24"),("Month","2"),("0Month","02"),("Day","29"),("0Day","29"),("Hour24","23"),("0Hour24","23"),("Hour12","11"),("0Hour12","11"),("Minute","7"),("0Minute","07"),("Second","8"),("0Second","08"),("SubSecond","12"),("0SubSecond","123"),("am_pm","pm"),("AM_PM","PM")}) {
   var scheme=Import(Source(66,"<"+prefix+suffix+">"));var rules=RenamePlan.ParseRules(scheme.Rules);Check(RenamePlan.ApplyVerified("old.jpg",rules,0,_=>dateRaw,date,dates)==expected+".jpg","date-token-wall-clock-"+prefix+suffix);
   Check(RenamePlan.ParseRules(RenameSchemeLibrary.Import(MacRenamePreset.Export(scheme),"date").Rules)[0].Text==rules[0].Text,"date-token-roundtrip-"+prefix+suffix);
  }
  foreach(var token in new[]{"Unknown","UUID8","FilePath","FILEName","FileName_Upper","0ISO","Song","artist","Album","TrackNum"})foreach(bool enabled in new[]{false,true}) {var j=Source(66,"<"+token+">");j["rules"]![0]!["enabled"]=enabled;Reject(()=>Import(j),"unproven-whole-refusal-"+token+enabled);}
  var bad=Source(1);bad["rules"]![0]!["lexicalCases"]!["Noun"]="bad";Reject(()=>Import(bad),"invalid-unused-enum-rejected");
  bad=Source(40);bad["rules"]![0]!["timeZone"]="Unresolved/zone";Reject(()=>Import(bad),"executing-date-zone-refused");
  bad=Source(32);Reject(()=>Import(bad),"lexical-action-stays-deferred");
  Check(await PhotoDocument.HashAsync(source)==original,"all-tests-original-file-restored");
  var recovery=Environment.GetEnvironmentVariable("PHOTOTRAIL_V1_RECOVERY");
  if(recovery is not null){var tool=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var photo=await PhotoDocument.LoadAsync(tool,Path.Combine(recovery,"inputs/one.jpg"));var lib=MetadataPresetLibrary.Decode(File.ReadAllText(Path.Combine(recovery,"prefs/metadata-presets.json")));foreach(var e in lib)await e.Preset.ApplyAsync(photo);Check(photo.Draft.Count==2&&photo.Draft["IFD0:Artist"]=="ReleaseGate20261023"&&photo.Draft["ExifIFD:ISO"]=="400","preserved-native-author-and-ISO-replayed-exactly");}
  File.WriteAllText(Path.Combine(root,"results.json"),JsonSerializer.Serialize(new{checks=evidence,exports,source="Pinned Mac cbeccc015 source-shaped fixture; Windows execution only; real Mac consumption PENDING"},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine(evidence.Count+" bounded v1 checks passed");
 }
}
