using System.Reflection;
using System.Text.Json;
using PhotoTrail.Windows;
static class InspectorChecks
{
 public static async Task ReadAsync()
 {
  var directory=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")!,"inspection-wire-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
  string[] files=[Path.Combine(directory,"a.jpg"),Path.Combine(directory,"b.jpg")];foreach(string file in files)File.WriteAllText(file,"synthetic fake-wire identity only");
  string executable=Path.Combine(AppContext.BaseDirectory,"PhotoTrail.Windows.Tests.exe");int passed=0;
  var valid=await new ExifToolClient(executable,"--fake-batch-reversed").ReadInspectionAsync(files,default);if(valid.Count!=2||files.Any(f=>!valid.ContainsKey(f)))throw new Exception("reordered inspection identities");passed++;
  foreach(string mode in new[]{"--fake-batch-unknown","--fake-batch-duplicate","--fake-batch-missing","--fake-invalid"})try{await new ExifToolClient(executable,mode).ReadInspectionAsync(files,default);throw new Exception("bad inspection accepted "+mode);}catch(Exception error)when(error is InvalidDataException or JsonException){passed++;}
  try{await new ExifToolClient(executable,"--fake-batch-reversed").ReadInspectionAsync([files[0],files[0]],default);throw new Exception("duplicate request accepted");}catch(ArgumentException){passed++;}
  Console.WriteLine($"INSPECTOR_WIRE={passed}; synthetic process-response fault checks only, not ExifTool or WPF evidence");
 }
 public static void Run()
 {
  int passed=0;void Check(bool value,string name){if(!value)throw new Exception(name);passed++;Console.WriteLine("PASS "+name);}
  using var json=JsonDocument.Parse("""{"File:FileType":"JPEG","XMP-dc:Title":"original"}""");
  var ctor=typeof(PhotoDocument).GetConstructors(BindingFlags.NonPublic|BindingFlags.Instance).Single();
  PhotoDocument Doc()=> (PhotoDocument)ctor.Invoke(["synthetic.jpg",null,json.RootElement.Clone(),null,"sha",null]);
  var doc=Doc();doc.Inspection=[new("原图","IFD0:Make","camera"),new("原图","IFD0:Copy1:Make","copy"),new("原图","XMP-tiff:Make","xmp"),new("旁车XMP","XMP-tiff:Make","sidecar"),new("原图","XMP-dc:Title","original"),new("原图","XMP-acme:Title","unknown"),new("原图","XMP-acme:Empty",""),new("原图","System:FileName","synthetic.jpg"),new("原图","Composite:SubSecDateTimeOriginal","2001:01:01 00:00:00")];
  var common=MetadataInspector.DefaultCommon.ToHashSet();var rows=MetadataInspector.Rows([doc],common);
  Check(MetadataInspector.Standard.Length==73&&MetadataInspector.Standard.Select(f=>f.Section).Distinct().Count()==11,"fixed-11-groups-73-directory");
  Check(common.Count==24,"fixed-default-24");
  foreach(string tag in common)Check(rows.Any(r=>r.IsCommon&&((r.Tag.Contains(" / ")&&MetadataInspector.Matches(tag,r.Tag.Split(" / ")[1]))||r.Tag==tag)),"common-map-"+tag);
  Check(rows.Count(r=>r.Tag.EndsWith(":Make"))==4,"namespace-role-copy-not-merged");
  Check(rows.Single(r=>r.Tag.Contains("Copy1:Make")).CanEdit==false,"copy-is-readonly");
  Check(!rows.Single(r=>r.Tag.Contains("XMP-acme:Title")).CanEdit&&rows.Single(r=>r.Tag=="原图 / XMP-dc:Title").CanEdit,"exact-write-whitelist");
  Check(rows.Single(r=>r.Tag.Contains("XMP-acme:Empty")).State=="空值","empty-distinct-from-missing");
  Check(rows.Single(r=>r.Tag=="File:MDItemUserTags").State.Contains("平台例外"),"Finder-body-approved-exception");
  Check(MetadataInspector.Counts([doc]).Contains("原标签7")&&MetadataInspector.Counts([doc]).Contains("净草稿字段0"),"raw-count-physical-instances-no-derived-file");
  doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","edited"}});Check(MetadataInspector.Counts([doc]).Contains("净草稿字段1"),"net-edit-count");
  doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","original"}});Check(MetadataInspector.Counts([doc]).Contains("净草稿字段0"),"restored-original-removes-net-count");
  doc.InspectionError="read failed";Check(MetadataInspector.Counts([doc]).Contains("原标签7")&&MetadataInspector.Counts([doc]).Contains("失败/过期1"),"stale-retains-old-count");
  var unread=Doc();unread.InspectionError="failed";Check(MetadataInspector.Counts([unread]).Contains("未知"),"failed-never-zero-tags");
  doc.InspectionError="";var other=Doc();other.Inspection=[new("原图","IFD0:Make","other")];Check(MetadataInspector.Rows([doc,other],common).Single(r=>r.Tag=="原图 / IFD0:Make").State=="混合值","mixed-values-explicit");
  using var duplicate=JsonDocument.Parse("""{"IFD0:Make":"one","IFD0:Make":"two"}""");try{MetadataInspector.Parse(duplicate.RootElement,"原图");throw new Exception("duplicate lost");}catch(InvalidDataException){passed++;}
  using var unique=JsonDocument.Parse("""{"IFD0:Make":"one","IFD0:Copy1:Make":"two","XMP-tiff:Make":"three"}""");Check(MetadataInspector.Parse(unique.RootElement,"原图").Length==3,"identified-duplicates-kept");
  string dir=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??Path.GetTempPath(),"phototrail-r02-settings-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);string file=Path.Combine(dir,"settings.json");
  Check(SettingsPreference.Read(file).CommonTags.SequenceEqual(MetadataInspector.DefaultCommon),"missing-config-defaults");
  SettingsPreference.Save(file,new(CommonOnly:false,CommonFields:[]));Check(!SettingsPreference.Read(file).CommonOnly&&SettingsPreference.Read(file).CommonTags.Length==0,"explicit-empty-and-view-restart");
  SettingsPreference.Save(file,new(CommonFields:["XMP-acme:Title","IFD0:Make"]));Check(SettingsPreference.Read(file).CommonTags.SequenceEqual(new[]{"XMP-acme:Title","IFD0:Make"}),"unknown-readonly-selection-persists");
  File.WriteAllText(file,"{bad");Check(SettingsPreference.Read(file).CommonTags.SequenceEqual(MetadataInspector.DefaultCommon),"corrupt-config-defaults");
  File.WriteAllText(file,"""{"version":1,"PhotoTrailMetadataCommonFields.v1":[true]}""");Check(SettingsPreference.Read(file).CommonTags.SequenceEqual(MetadataInspector.DefaultCommon),"wrong-type-defaults");
  SettingsPreference.Save(file,new());Check(SettingsPreference.Read(file).CommonTags.SequenceEqual(MetadataInspector.DefaultCommon),"restore-defaults-restart");
  Console.WriteLine($"INSPECTOR_MODEL={passed}");
 }
}
