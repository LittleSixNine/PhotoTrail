using PhotoTrail.Windows;
using System.Text.Json;

static class SettingsChecks
{
 public static void Run()
 {
  var folder=Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??Path.GetTempPath(),"settings-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var file=Path.Combine(folder,"settings.json");var history=Path.Combine(folder,"history.json");int passed=0;
  void Check(bool ok,string label){if(!ok)throw new Exception(label);passed++;Console.WriteLine("PASS "+label);}
  var defaults=SettingsPreference.Read(file);
  Check(defaults.TextSize==0&&defaults.Spacing==0&&defaults.FullTagNames&&defaults.RecordSearches&&defaults.PhotoSort.SequenceEqual(new[]{new PhotoSortPreference("name",false)})&&!File.Exists(file),"defaults-without-writing");
  foreach(int size in new[]{-1,0,1})foreach(int spacing in new[]{-1,0,1}){
   var value=new SettingsPreference(size,spacing,false,false,[new("captured",true),new("name",false)]);SettingsPreference.Save(file,value);var read=SettingsPreference.Read(file);
   Check(read.TextSize==size&&read.Spacing==spacing&&read.PhotoSort.SequenceEqual(value.PhotoSort)&&!read.FullTagNames&&!read.RecordSearches,"independent-settings-roundtrip");
   Check(Math.Abs(read.FontDelta-size*8d/3)<1e-12&&read.RowPadding==(spacing<0?2:spacing>0?10:6)&&read.MinimumRowHeight==(spacing<0?30:spacing>0?48:40),"pt-dip-padding-row-height");
  }
  File.WriteAllText(file,"{\"version\":1,\"PhotoTrailPhotoSort.v1\":[{\"field\":\"unknown\",\"descending\":false},{\"field\":\"captured\",\"descending\":true},{\"field\":\"name\",\"descending\":\"false\"},{\"field\":\"import\",\"descending\":false}]}");
  Check(SettingsPreference.Read(file).PhotoSort.SequenceEqual(new[]{new PhotoSortPreference("captured",true),new PhotoSortPreference("import",false)}),"unknown-sort-skipped-sequence-preserved");
  foreach(var text in new[]{"{","null","[]","{\"version\":2}","{\"version\":1,\"PhotoTrailPhotoSort.v1\":[{\"field\":\"unknown\",\"descending\":true}]}",new string(' ',16385)}){File.WriteAllText(file,text);Check(SettingsPreference.Read(file).PhotoSort.SequenceEqual(defaults.PhotoSort)&&File.ReadAllText(file)==text,"bad-or-no-valid-sort-fallback-no-automatic-overwrite");}
  SettingsPreference.Save(file,defaults);var before=File.ReadAllBytes(file);try{SettingsPreference.Save(file,new(2));throw new Exception("invalid mode accepted");}catch(ArgumentException){Check(before.SequenceEqual(File.ReadAllBytes(file)),"invalid-setting-no-write");}
  Check(SettingsPreference.TagLabel("内嵌 / EXIF:Model",false)=="内嵌 / EXIF"&&SettingsPreference.TagLabel("旁车 / XMP-tiff:Model",false)=="旁车 / XMP-tiff","family-and-physical-source-not-merged");
  Check(SettingsPreference.TagLabel("XMP-exif:DateTimeOriginal",true)=="XMP-exif:DateTimeOriginal","full-key-unchanged");
  Check(MapSearchHistory.Read(history).Length==0&&!File.Exists(history),"history-default-empty");
  foreach(var term in new[]{"Kyoto","Tokyo","Osaka","  KYOTO  "})MapSearchHistory.Remember(history,term,true);
  Check(MapSearchHistory.Read(history).SequenceEqual(new[]{"KYOTO","Osaka","Tokyo"}),"trim-local-case-dedup-three-most-recent");
  var historyBytes=File.ReadAllBytes(history);Check(MapSearchHistory.Remember(history,"disabled term",false).SequenceEqual(MapSearchHistory.Read(history))&&historyBytes.SequenceEqual(File.ReadAllBytes(history)),"off-preserves-history-no-add-or-write");
  MapSearchHistory.Remember(history," ",true);Check(historyBytes.SequenceEqual(File.ReadAllBytes(history)),"empty-not-recorded");
  SettingsPreference.Save(file,defaults with{RecordSearches=false});Check(!SettingsPreference.Read(file).RecordSearches&&MapSearchHistory.Read(history).Length==3,"off-roundtrip-history-separate");
  SettingsPreference.Save(file,defaults);Check(SettingsPreference.Read(file).RecordSearches&&historyBytes.SequenceEqual(File.ReadAllBytes(history)),"reset-reenables-retains-history");
  var key=Path.Combine(folder,"unrelated-key.txt");File.WriteAllText(key,"synthetic-key-sentinel");var settingBytes=File.ReadAllBytes(file);MapSearchHistory.Clear(history);
  Check(MapSearchHistory.Read(history).Length==0&&settingBytes.SequenceEqual(File.ReadAllBytes(file))&&File.ReadAllText(key)=="synthetic-key-sentinel","clear-only-history");
  File.WriteAllText(history,"broken");try{MapSearchHistory.Remember(history,"term",true);throw new Exception("corrupt history overwritten");}catch(JsonException){Check(File.ReadAllText(history)=="broken","bad-history-kept");}
  var valid=JsonSerializer.Serialize(new{type="place",id=4,point=new MapPoint(135,35),status="OK",fields=new{city="Kyoto"},query="Kyoto"});
  Check(MapPlace.TryRead(MapMessage.GooglePage,valid,out var result)&&result!.MatchesQuery(4,"Kyoto")&&!result.MatchesQuery(3,"Kyoto")&&!result.MatchesQuery(4,"Tokyo")&&!result.Matches(4,new(135,35)),"query-result-bound-to-id-and-term-not-point-request");
  Check(!MapPlace.TryRead(MapMessage.Page,valid,out _)&&!MapPlace.TryRead(MapMessage.GooglePage,valid.Replace("\"query\":\"Kyoto\"","\"query\":42"),out _),"query-origin-and-type-rejected");
  Check(Directory.GetFiles(folder,".settings-*").Length==0,"atomic-write-temp-cleanup");Console.WriteLine($"Settings checks complete: {passed}; {folder}");
 }
}
