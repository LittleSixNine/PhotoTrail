using System.IO;
using System.Reflection;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task ProjectionPageScale()
 {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R01_COUNT")!);var rows=await DateCoreRows(count);var docs=rows.Select(Doc).ToArray();Control<ListBox>("Photos").SelectAll();SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=0;Input("DateSeconds","1");
  foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","retained"}});var before=Drafts(rows);await Apply("ApplyDates");
  var timings=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);
  Check(docs.All(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal")),"page-scale-all-changed");
  Check(timings["projectionRequests"]==1&&(int)Field("batchHostRequests")! ==2,"page-scale-one-compute-one-grouped-project");
  Action("UndoLastApply");Check(SameDrafts(rows,before),"page-scale-full-undo");foreach(var doc in docs)Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"page-scale-source-sha");Action("UndoDraft");
  evidence.Add(new{count,timings});DateCoreResult("projection-page-scale-results.json");
 }
 static async Task ProjectionWorkflow()
 {
  await WaitTrackInput(8);var rows=await DateCoreRows(8);var list=Control<ListBox>("Photos");
  string Name(object row)=>Path.GetFileName(Doc(row).FilePath);
  var byName=rows.ToDictionary(Name);const string tag="XMP-exif:DateTimeOriginal";
  void Sort(bool descending){typeof(MainWindow).GetField("settings",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,new SettingsPreference(Sorts:[new("captured",descending)]));Invoke("ApplyPhotoView");}
  Sort(false);Check(list.Items.Cast<object>().Select(Name).SequenceEqual(new[]{"f.xmp","a.xmp","e.xmp","b.xmp","c.xmp","d.xmp","g.xmp","h.xmp"}),"photo-exact-historical-1ns-stable-missing-last");
  Sort(true);Check(list.Items.Cast<object>().TakeLast(2).Select(Name).SequenceEqual(new[]{"g.xmp","h.xmp"}),"photo-descending-missing-last");
  typeof(MainWindow).GetField("settings",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,new SettingsPreference(Sorts:[new("name",true)]));Invoke("ApplyPhotoView");Check(list.Items.Cast<object>().Select(Name).SequenceEqual(new[]{"h.xmp","g.xmp","f.xmp","e.xmp","d.xmp","c.xmp","b.xmp","a.xmp"}),"photo-return-to-name-sort");
  var docs=rows.Select(Doc).ToArray();var original=docs.ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  list.SelectedItems.Clear();list.SelectedItem=byName["b.xmp"];
  EditedFields(new(){{tag,"1400:01:01 00:00:00Z"}});await Apply("ApplyDraft");Sort(false);Check(Name(list.Items[1])=="b.xmp","photo-edit-refresh-historical-coordinate");Action("UndoLastApply");Sort(false);Check(Name(list.Items[3])=="b.xmp","photo-undo-refresh-exact-original");
  // Repeated getters use the existing proof; no host calls are possible from these properties.
  for(int i=0;i<100;i++)foreach(var row in rows)_=row.GetType().GetProperty("Captured")!.GetValue(row);
  Check(Doc(byName["f.xmp"]).VerifiedDate(tag)!.InstantLimitation=="平台范围不足","year-one-valid-sort-but-platform-range");
  Check(Doc(byName["e.xmp"]).VerifiedDate(tag)!.InstantLimitation=="时区不足","wall-retains-domain");
  Check(Doc(byName["b.xmp"]).VerifiedDate(tag)!.InstantLimitation=="精度不足","nanosecond-not-rounded");
  list.SelectAll();SelectMetadataTab("重命名");Input("RenameRules","prefix|checked_");
  Control<ComboBox>("RenameProcessingSort").SelectedIndex=Array.IndexOf(RenameOrderSettings.Sorts,"shooting");
  Action("RefreshRenameOrder");await RenameWait();
  Check(GroupNames().Take(6).SequenceEqual(new[]{"f.xmp","a.xmp","e.xmp","b.xmp","c.xmp","d.xmp"}),"rename-historical-exact-stable-sorting");
  Input("RenameDateFrom","1500:02:29 00:00:00Z");Input("RenameDateTo","1970:01:01 00:00:00.000000001Z");Action("RefreshRenameOrder");await RenameWait();
  Check(GroupNames().SequenceEqual(new[]{"a.xmp","e.xmp","b.xmp"}),"rename-historical-and-nanosecond-inclusive-filter");
  var expected=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToDictionary(x=>x.Source,x=>x.Target);
  Action("FreezeRename");await RenameWait();var plan=(RenamePlan?)Field("frozenRenamePlan");Check(plan is not null&&plan.Files.All(x=>expected[x.Source]==x.Target),"projection-filter-preview-frozen-identical");
  Action("ExecuteRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("更名及内容核验完成"),"projection-rename-execute");
  Action("RestoreRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("恢复完成"),"projection-rename-restore");
  foreach(var file in original)Check(File.Exists(file.Key)&&await PhotoDocument.HashAsync(file.Key)==file.Value,"projection-rename-source-sha");
  Input("RenameDateFrom","");Input("RenameDateTo","");
  // Rename reloads documents. Select current rows, never reuse stale request identities.
  var current=list.Items.Cast<object>().ToDictionary(Name);list.SelectedItems.Clear();list.SelectedItem=current["a.xmp"];
  var historical=Doc(current["a.xmp"]);historical.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","keep earlier draft"}});var before=Drafts([current["a.xmp"]]);
  SelectMetadataTab("批量日期");await TrackBatchCompute();Check(Results().Single().Status=="成功","historical-shared-instant-to-real-GPX");Check(SameDrafts([current["a.xmp"]],before),"historical-track-preview-no-draft");
  await TrackBatchApply();Check(historical.Position() is {Latitude:30,Longitude:120},"historical-track-apply-position");Action("UndoLastApply");Check(SameDrafts([current["a.xmp"]],before),"historical-track-complete-undo");
  await TrackBatchCompute();await TrackBatchApply();string output=Path.Combine(folder,"historical-copy");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");await BatchWait();
  var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var copy=await PhotoDocument.LoadAsync(client,Path.Combine(output,"a.xmp"));
  Check(copy.Value(tag)=="1500:02:29 00:00:00Z"&&copy.Position() is {Latitude:30,Longitude:120}&&copy.Value("XMP-dc:Rights")=="keep earlier draft","historical-copy-ExifTool-original-label-kept");Action("UndoDraft");
  foreach(var (name,status) in new[]{("b.xmp","精度不足"),("e.xmp","时区不足"),("f.xmp","平台范围不足"),("g.xmp","缺失时间"),("h.xmp","非法时间")}) {
   list.SelectedItems.Clear();list.SelectedItem=current[name];await TrackBatchCompute();Check(Results().Single().Status==status,"track-domain-rejection-"+name);
  }
  list.SelectedItems.Clear();list.SelectedItem=current["a.xmp"];await TrackBatchCompute();historical.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","changed"}});Check(Field("trackBatch") is null,"projection-track-draft-invalidates-preview");Action("UndoDraft");
  foreach(var file in original)Check(await PhotoDocument.HashAsync(file.Key)==file.Value,"projection-all-source-sha-retained");
  DateCoreResult("projection-workflow-results.json");
 }
}
