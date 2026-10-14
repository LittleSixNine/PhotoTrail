using PhotoTrail.Windows;
using System.Text.Json;
using System.Diagnostics;
static class RenameRuleChecks
{
 public static async Task RunAsync()
 {
  int count=0;void Check(bool value,string why){if(!value)throw new Exception("R08a: "+why);count++;}
  RenameRule Rule(string action,string text="",string replacement="")=>new("action",text,replacement){Action=action};
  string Name(string name,RenameRule rule)=>RenamePlan.ApplyVerified(name,[rule],0,null,null);
  void Expect(string action,string input,string expected,string text="",string replacement="",Func<RenameRule,RenameRule>? edit=null){var rule=Rule(action,text,replacement);if(edit is not null)rule=edit(rule);Check(Name(input,rule)==expected,action+" expected "+expected);}
  void Reject(Action action,string why){try{action();throw new Exception("accepted: "+why);}catch(ArgumentException){Check(true,why);}}
  Expect("add-begin","cat.jpg","Xcat.jpg","X");Expect("add-end","cat.jpg","catX.jpg","X");
  Expect("add-before","a_a.jpg","Xa_Xa.jpg","X",edit:r=>r with{Anchor="a"});Expect("add-after","a_a.jpg","aX_aX.jpg","X",edit:r=>r with{Anchor="a"});
  Expect("add-position","👩‍👩‍👧‍👦e\u0301中.jpg","👩‍👩‍👧‍👦Xe\u0301中.jpg","X",edit:r=>r with{Position=1});
  Expect("remove-begin","a_a.jpg","_a.jpg","a");Expect("remove-end","a_a.jpg","a_.jpg","a");Expect("remove-text","a_a.jpg","_.jpg","a");
  Expect("replace-begin","a_a.jpg","X_a.jpg","a","X");Expect("replace-end","a_a.jpg","a_X.jpg","a","X");Expect("replace-text","a_a.jpg","X_X.jpg","a","X");
  foreach(var (occurrence,number,expected) in new[]{("all",1,"X_X_X.jpg"),("first",1,"X_a_a.jpg"),("last",1,"a_a_X.jpg"),("nth",2,"a_X_a.jpg"),("nth",4,"a_a_a.jpg")})Expect("replace-text","a_a_a.jpg",expected,"a","X",r=>r with{Occurrence=occurrence,MatchNumber=number});
  Expect("replace-text","aA.jpg","XX.jpg","a","X",r=>r with{CaseSensitive=false});
  Expect("move-front","xa_y.jpg","ax_y.jpg","a");Expect("move-end","xa_y.jpg","x_ya.jpg","a");Expect("move-position","xa_y.jpg","x_ay.jpg","a",edit:r=>r with{Position=2});
  Expect("move-before","xa_y.jpg","x_ay.jpg","a",edit:r=>r with{Anchor="y"});Expect("move-after","xa_y.jpg","x_ya.jpg","a",edit:r=>r with{Anchor="y"});
  Expect("replace-characters","👨‍👩‍👧‍👦e\u0301中.jpg","XX中.jpg","👨‍👩‍👧‍👦e\u0301","X");Expect("remove-characters","cat.jpg","ct.jpg","a");Expect("keep-characters","cat.jpg","at.jpg","at");
  Expect("trim-begin","  cat.jpg","cat.jpg");Expect("trim-end","cat  .jpg","cat.jpg");Expect("remove-vowels","Aa猫e.jpg","猫.jpg");
  Expect("drop-begin","👩‍👩‍👧‍👦e\u0301中.jpg","e\u0301中.jpg");Expect("drop-end","👩‍👩‍👧‍👦e\u0301中.jpg","👩‍👩‍👧‍👦e\u0301.jpg");
  Expect("remove-range","👩‍👩‍👧‍👦e\u0301中.jpg","👩‍👩‍👧‍👦中.jpg",edit:r=>r with{Position=1});Expect("move-range","👩‍👩‍👧‍👦e\u0301中.jpg","e\u0301中👩‍👩‍👧‍👦.jpg",edit:r=>r with{Start=2});
  Expect("lower","Cat.JPG","cat.JPG");Expect("upper","Cat.jpg","CAT.jpg");Expect("sentence","cAT.jpg","Cat.jpg");Expect("title","cat dog.jpg","Cat Dog.jpg");
  Expect("percent-decode","%E4%B8%AD.jpg","中.jpg");Expect("percent-decode","%zz.jpg","%zz.jpg");Expect("camel-expand","XMLPhoto2Test.jpg","XML Photo2 Test.jpg");
  Expect("mac9-name","cat.jpg","cat.jpg");Expect("windows-name","CON.jpg","_CON.jpg");Expect("truncate","👩‍👩‍👧‍👦e\u0301中.jpg","👩‍👩‍👧‍👦.jpg");
  Expect("dos83-name","abcdefghijkl.jpeg","ABCDEFGH.jpeg",edit:r=>r with{Part="stem"});Expect("dos83-name","abcdefghijkl.jpeg","ABCDEFGH.JPE",edit:r=>r with{Part="entire"});
  Expect("regex-replace","cat12_cat34.jpg","12CAT_34CAT.jpg","(cat)([0-9]+)","$2\\U$1\\E");Expect("regex-rearrange","cat12.jpg","12cat.jpg","(cat)([0-9]+)","$2$1",r=>r with{FullMatch=true});
  Expect("regex-rearrange","xcat12.jpg","xcat12.jpg","(cat)([0-9]+)","$2$1",r=>r with{FullMatch=true});
  Expect("set","old.jpg","new.jpg","new");Expect("set","old.jpg","new.png","new.png",edit:r=>r with{Part="entire"});
  Expect("replace-text","a.jpg","a.png","jpg","png",r=>r with{Part="extensionOnly"});Expect("replace-text","a.jpg","a.PNG",".jpg",".PNG",r=>r with{Part="dottedExtension"});
  Expect("upper","a.jpg","A.JPG",edit:r=>r with{Part="entire"});Expect("set",".hidden","new","new");
  Check(Name("e\u0301.jpg",Rule("set","bad/name") with{Enabled=false})=="e\u0301.jpg","disabled no normalization");
  Check(RenameGroup.Key(@"C:\safe\é.jpg")!=RenameGroup.Key(@"C:\safe\é.jpg"),"NTFS NFC/NFD not merged");
  var steps=new List<string>();var chain=RenamePlan.ApplyVerified("a.jpg",[Rule("add-begin","X"),Rule("replace-text","Xa","cat")],0,null,null,null,steps);Check(chain=="cat.jpg"&&steps.SequenceEqual(new[]{"Xa.jpg","cat.jpg"}),"real intermediate order");
  foreach(var invalid in new[]{Rule("unknown"),Rule("add-position") with{Position=10},Rule("remove-range") with{Length=100},Rule("replace-characters","abc","xy"),Rule("upper") with{Part="bad"},Rule("upper") with{Occurrence="bad"},Rule("date-set") with{DateSource="invalid"},Rule("date-set") with{NightHour=24},Rule("date-set") with{TimeZone="invalid-zone"}})Reject(()=>Name("a.jpg",invalid),"invalid parameters");
  foreach(var pattern in new[]{"[","\\X","\\p{L}","(?<name>a)","[a-z&&[^a]]","\\Qcat\\E"})Reject(()=>Name("a.jpg",Rule("regex-replace",pattern,"X")),"invalid/ICU regex");
  foreach(var replacement in new[]{"$&","${name}","$9","\\z"})Reject(()=>Name("a.jpg",Rule("regex-replace","(a)",replacement)),"capture validation");
  Reject(()=>Name("é.jpg",Rule("regex-replace","(e)","X")),"grapheme match boundary");Reject(()=>Name("👩.jpg",Rule("regex-replace","(.)", "$1")),"surrogate match boundary");
  Reject(()=>Name("a.jpg",Rule("set","CON")),"reserved name");Reject(()=>Name("a.jpg",Rule("set","x.") with{Part="entire"}),"trailing dot intermediate final name");
  Reject(()=>RenamePlan.ParseRules("{\"Kind\":\"action\",\"Action\":\"upper\",\"Typo\":1}"),"unknown JSON member");Reject(()=>RenamePlan.ParseRules("{\"Kind\":\"action\",\"Action\":\"upper\",\"Action\":\"lower\"}"),"duplicate JSON member");Reject(()=>RenamePlan.ParseRules("{\"Kind\":\"action\",\"Action\":31}"),"numeric Mac action rejected");Reject(()=>RenamePlan.ParseRules("{\"Kind\":\"action\",\"Text\":null}"),"null rejected");
  var round=RenamePlan.ParseRules(JsonSerializer.Serialize(Rule("replace-text","a","b") with{Part="entire",Occurrence="last"}));Check(Name("aa.jpg",round[0])=="ab.jpg","JSON precise roundtrip");
  var fields=new Dictionary<string,string>{{"CameraModel","CAM"},{"IPTCCity","城"},{"ImageWidth","42"},{"ImageHeight","24"},{"ParentFolderName","parent"},{"FilePath",@"C:\grand\parent\photo.jpg"},{"XMP-dc:Title","TITLE"}};
  foreach(var (action,expected) in new[]{("device-set","CAM.jpg"),("device-begin","CAMphoto.jpg"),("device-end","photoCAM.jpg"),("device-position","CAMphoto.jpg"),("device-before","CAMphoto.jpg"),("device-after","photoCAM.jpg"),("location-set","城.jpg"),("location-begin","城photo.jpg"),("location-end","photo城.jpg"),("location-position","城photo.jpg"),("location-before","城photo.jpg"),("location-after","photo城.jpg"),("size-end","photo42x24.jpg"),("size-begin","42x24photo.jpg"),("size-set","42x24.jpg"),("size-before","42x24photo.jpg"),("size-after","photo42x24.jpg"),("size-position","42x24photo.jpg"),("parent-begin","parentphoto.jpg"),("parent-end","photoparent.jpg"),("parent-before","parentphoto.jpg"),("parent-after","photoparent.jpg"),("parent-position","parentphoto.jpg"),("path-begin","parentphoto.jpg"),("path-end","photoparent.jpg"),("path-before","parentphoto.jpg"),("path-after","photoparent.jpg"),("path-position","parentphoto.jpg"),("template-set","TITLE.jpg"),("template-begin","TITLEphoto.jpg"),("template-end","photoTITLE.jpg"),("template-position","TITLEphoto.jpg"),("template-before","TITLEphoto.jpg"),("template-after","photoTITLE.jpg")}){var rule=Rule(action,action.StartsWith("template")?"<XMP-dc:Title>":"") with{Anchor="photo"};Check(RenamePlan.Apply("photo.jpg",[rule],0,k=>fields.GetValueOrDefault(k))==expected,action);}
  Check(RenamePlan.Apply("photo.jpg",[Rule("add-begin","X"),Rule("device-set")],0,_=>null)=="photo.jpg","missing metadata resets whole chain");
  Reject(()=>RenamePlan.Apply("photo.jpg",[Rule("size-set")],0,k=>k=="ImageWidth"?"-1":"12"),"illegal dimensions");
  Expect("remove-emoji","A1©👩‍👩‍👧‍👦é1️⃣中.jpg","A1é中.jpg");Expect("remove-diacritics","café_é_한.jpg","cafe_e_한.jpg");
  var raw="2024:02:29 23:07:08.123456789+09:00";var dates=await VerifiedPhotoDate.InspectAsync([raw,"2023:02:29 00:00:00","1582:10:04 00:00:00","1582:10:15 00:00:00"]);
  var date=dates[raw];Check(date is not null&&date.Fraction==".123456789","fixed DateHost proof");
  foreach(var (action,expected) in new[]{("date-set","20240229_230708.jpg"),("date-begin","20240229_230708photo.jpg"),("date-end","photo20240229_230708.jpg"),("date-before","20240229_230708photo.jpg"),("date-after","photo20240229_230708.jpg"),("date-position","20240229_230708photo.jpg")})Check(RenamePlan.ApplyVerified("photo.jpg",[Rule(action) with{Anchor="photo"}],0,k=>k=="captured"?raw:null,date,dates)==expected,action);
  Check(RenamePlan.ApplyVerified("photo.jpg",[Rule("date-set") with{DateFormat="yyyy-MM-dd_HH-mm-ss_SSS"}],0,_=>raw,date,dates)=="2024-02-29_23-07-08_123.jpg","source wall clock no tick loss");
  Check(RenamePlan.ApplyVerified("photo.jpg",[Rule("date-set")],0,_=>"2023:02:29 00:00:00",null,dates)=="photo.jpg","invalid date missing no now fallback");
  Reject(()=>RenamePlan.ApplyVerified("photo.jpg",[Rule("date-set") with{DateFormat="YYYY"}],0,_=>raw,date,dates),"unmapped date format");
  var midnight="2024:03:01 00:07:08+09:00";var night=Rule("date-set") with{NightHour=2};var projected=await RenameTransform.PrepareDatesAsync([midnight],[night],default);Check(RenamePlan.ApplyVerified("photo.jpg",[night],0,_=>midnight,null,projected)=="20240229_000708.jpg","night previous day fixed DateHost");
  var utc=Rule("date-set") with{TimeZone="UTC"};projected=await RenameTransform.PrepareDatesAsync([midnight],[utc],default);Check(RenamePlan.ApplyVerified("photo.jpg",[utc],0,_=>midnight,null,projected)=="20240229_150708.jpg","explicit zone from fixed instant");
  projected=await RenameTransform.PrepareDatesAsync([raw],[utc],default);Check(RenamePlan.ApplyVerified("photo.jpg",[utc],0,_=>raw,null,projected)=="photo.jpg","nanosecond native projection refused without truncation");
  projected=await RenameTransform.PrepareDatesAsync(["1582:10:04 00:00:00+00:00"],[utc],default);Check(RenamePlan.ApplyVerified("photo.jpg",[utc],0,_=>"1582:10:04 00:00:00+00:00",null,projected)=="photo.jpg","historical native zone projection refused");
  Check(RenamePlan.ApplyVerified("photo.jpg",[Rule("date-set") with{DateSource="now"}],0,k=>k=="captured"?raw:null,date,dates)=="photo.jpg","explicit now requires frozen reference no fallback");
  var output=Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??throw new Exception("Missing output");var folder=Path.Combine(output,"rename-rule-files");Directory.CreateDirectory(folder);var path=Path.Combine(folder,"a.jpg");File.WriteAllText(path,"synthetic-boundary");
  var plan=await RenamePlan.BuildTargetsAsync([(path,"b.jpg")]);var time=File.GetLastWriteTimeUtc(path);File.SetLastWriteTimeUtc(path,time.AddSeconds(1));
  try{await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,"history"));throw new Exception("sameSHA property change accepted");}catch(IOException){Check(File.Exists(path)&&!File.Exists(Path.Combine(folder,"b.jpg")),"frozen System mutation refused");}
  File.SetLastWriteTimeUtc(path,time);var valid=await RenamePlan.BuildTargetsAsync([(path,"b.jpg")]);var result=await RenameExecutor.ExecuteAsync(valid,Path.Combine(folder,"history"));Check(result.Complete&&File.Exists(Path.Combine(folder,"b.jpg")),"execute property readback");var restored=await RenameExecutor.RestoreAsync(result.Journal,Path.Combine(folder,"history"));Check(restored.Complete&&File.Exists(path)&&await PhotoDocument.HashAsync(path)==plan.Files[0].Hash,"restore content proof");
  var watch=Stopwatch.StartNew();Reject(()=>Name(new string('a',240)+"!.jpg",Rule("regex-replace","(a+)+$","X")),"bounded catastrophic regex");Check(watch.ElapsedMilliseconds<2000,"regex finite timeout");
  Console.WriteLine($"{count} R08a rule/source/property assertions passed.");
 }
}
