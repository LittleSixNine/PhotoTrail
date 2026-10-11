using System.IO;
using System.Collections;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task RunBatchMissing()
 {
  for(int i=0;i<1200&&(bool)Field("busy")!;i++)await Task.Delay(25);
  var list=Control<ListBox>("Photos");Check(list.Items.Count==3,"batch-import-Mac-XMP-three");list.SelectAll();
  var rows=list.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();var missing=docs.Single(d=>d.Value("XMP-exif:DateTimeOriginal").Length==0);
  var tab=DatesTab(window)!;((TabControl)LogicalTreeHelper.GetParent(tab)).SelectedItem=tab;
  Control<ComboBox>("DateMode").SelectedIndex=2;Control<TextBox>("DateReplaceHour").Text="12";
  missing.SetDraft(new Dictionary<string,string>(){["XMP-dc:Title"]="keep title"});
  Action("PreviewDates");await Idle();Check(Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("可应用2，跳过1")&&Status.Contains("缺失时间1"),"Mode2-mixed-count-button");
  Check(Control<TextBlock>("DatePlanPreview").Text.Contains("缺失时间，已跳过"),"Mode2-mixed-explicit-hint");
  Action("ApplyDates");await Idle();Check(missing.Draft.Count==1&&docs.Count(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal"))==2,"Mode2-apply-no-partial-missing-overwrite");
  Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("无变化2")&&Control<TextBlock>("DatePlanPreview").Text.Contains("无变化，保留原草稿"),"same-components-old-drafts-disabled-distinct-hints");
  Control<ComboBox>("DateMode").SelectedIndex=0;Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("无变化2"),"zero-offset-with-date-drafts-disabled");
  string copies=Path.Combine(folder,"copies");Directory.CreateDirectory(copies);Control<TextBox>("OutputFolder").Text=copies;Action("SaveCopies");
  for(int i=0;i<1200&&(bool)Field("busy")!;i++)await Task.Delay(25);Check(Status.Contains("副本成功 3，失败 0"),"batch-real-WPF-copy-save");
  var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
  foreach(var doc in docs){var read=await PhotoDocument.LoadAsync(client,Path.Combine(copies,Path.GetFileName(doc.FilePath)));Check(read.Value("XMP-exif:DateTimeOriginal")==doc.Value("XMP-exif:DateTimeOriginal")&&read.Value("XMP-dc:Title")==doc.Value("XMP-dc:Title")&&await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"batch-copy-read-nontarget-and-source-hash");}
  Action("UndoDraft");foreach(var doc in docs)doc.ClearDraft();
  list.SelectedItems.Clear();list.SelectedItem=rows.Single(r=>Doc(r)==missing);Control<ComboBox>("DateMode").SelectedIndex=2;
  missing.SetDraft(new Dictionary<string,string>(){["XMP-dc:Title"]="prior title"});Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("可应用0，跳过1")&&missing.Draft.Count==1,"all-missing-old-other-draft-disabled");
  Control<TextBox>("DateReplaceHour").Text="24";Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("超出"),"all-missing-invalid-parameter-still-rejected");Control<TextBox>("DateReplaceHour").Text="12";
  foreach(var doc in docs)doc.ClearDraft();list.SelectAll();
  foreach(var target in new[]{missing,docs.First(d=>d!=missing)}) {
   Control<TextBox>("DateReplaceHour").Text=target==missing?"12":target.Value("XMP-exif:DateTimeOriginal").Substring(11,2);
   Action("PreviewDates");await Idle();var bytes=File.ReadAllBytes(target.FilePath);File.AppendAllText(target.FilePath," ");Action("ApplyDates");await Idle();
   Check(Status.Contains("未应用")&&docs.All(d=>d.Draft.Count==0),"missing-or-unchanged-source-at-apply-atomic-reject");
   Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("已改变"),"full-selection-source-at-preview-reject");File.WriteAllBytes(target.FilePath,bytes);
  }
  Control<TextBox>("DateReplaceHour").Text="12";Action("PreviewDates");await Idle();Control<TextBox>("DateReplaceMinute").Text="1";Action("ApplyDates");Check(docs.All(d=>d.Draft.Count==0)&&!Control<Button>("DatePlanApplyButton").IsEnabled,"parameter-change-invalidates-qualification");Control<TextBox>("DateReplaceMinute").Text="";
  Action("PreviewDates");await Idle();list.SelectedItems.Remove(rows[0]);Action("ApplyDates");Check(docs.All(d=>d.Draft.Count==0),"selection-change-invalidates");list.SelectAll();
  Action("PreviewDates");await Idle();list.SelectedItems.Clear();foreach(var row in rows.Reverse())list.SelectedItems.Add(row);Action("ApplyDates");Check(docs.All(d=>d.Draft.Count==0)&&!Control<Button>("DatePlanApplyButton").IsEnabled,"original-selection-order-change-invalidates");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  Action("PreviewDates");await Idle();missing.SetDraft(new Dictionary<string,string>(){["XMP-dc:Title"]="revision changed"});Action("ApplyDates");Check(docs.Count(d=>d.Draft.Count>0)==1&&!Control<Button>("DatePlanApplyButton").IsEnabled,"missing-draft-revision-invalidates");missing.ClearDraft();
  Action("PreviewDates");await Idle();var memory=missing.Embedded;
  var backing=typeof(PhotoDocument).GetField("<Embedded>k__BackingField",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!;
  backing.SetValue(missing,JsonSerializer.SerializeToElement(new Dictionary<string,object>{["File:FileType"]="XMP",["XMP-exif:DateTimeOriginal"]=42}));
  Action("ApplyDates");await Idle();Check(Status.Contains("未应用")&&docs.All(d=>d.Draft.Count==0),"missing-in-memory-type-change-rejected-atomically");backing.SetValue(missing,memory);
  Action("PreviewDates");Action("CancelRead");Control<TextBox>("DateReplaceHour").Text="13";Action("PreviewDates");await Idle();
  Check(Control<Button>("DatePlanApplyButton").IsEnabled&&Control<TextBlock>("DatePlanPreview").Text.Contains("13:20:30")&&docs.All(d=>d.Draft.Count==0),"cancel-no-partial-new-request-isolates-old-result");
  var dated=docs.First(d=>d!=missing);dated.SetDraft(new Dictionary<string,string>(){["XMP-exif:DateTimeOriginal"]="",["XMP-dc:Title"]="keep clear"});Action("PreviewDates");await Idle();Check(Status.Contains("缺失时间2"),"explicit-clear-prior-draft-missing");Action("ApplyDates");await Idle();Check(dated.Draft["XMP-exif:DateTimeOriginal"]==""&&dated.Draft["XMP-dc:Title"]=="keep clear","WPF-clear-and-nontarget-preserved");foreach(var doc in docs)doc.ClearDraft();Action("CancelRead");
  // Existing production settings and rename entry points, without replaying their historical suites.
  var prefs=Control<System.Windows.Controls.ComboBox>("MetadataTextSize");int saved=prefs.SelectedIndex;prefs.SelectedIndex=(saved+1)%3;prefs.SelectedIndex=saved;
  Check(docs.All(d=>d.Draft.Count==0),"settings-roundtrip-preserves-drafts");foreach(var doc in docs)Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"settings-source-hash");
  Check(SettingsPreference.Read(Environment.GetEnvironmentVariable("PHOTOTRAIL_SETTINGS_FILE")!).TextSize==saved-1,"settings-persistence-regression");
  SelectMetadataTab("重命名");Action("RefreshRenameOrder");await RenameWait();Check(Groups().Length==3,"rename-logical-group-regression");
  Control<TextBox>("RenameRules").Text="set|batch_\nsequence|1|1|3";var identities=Groups().Select(g=>g.Id).ToArray();SelectGroups(Groups()[1].Name);Action("RenameMoveUp");var manual=((string[])Field("manualRenameOrder")!).ToArray();
  Action("FreezeRename");await RenameWait();var plan=(RenamePlan?)Field("frozenRenamePlan");Check(plan is not null&&plan.Files.Count==3,"rename-freeze-after-date-checks");
  prefs.SelectedIndex=(saved+1)%3;prefs.SelectedIndex=saved;Check(ReferenceEquals(plan,Field("frozenRenamePlan"))&&((string[])Field("manualRenameOrder")!).SequenceEqual(manual)&&Groups().Select(g=>g.Id).Order().SequenceEqual(identities.Order()),"settings-preserve-rename-freeze-order-identities");
  File.WriteAllText(Path.Combine(folder,"batch-ui-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("BATCH_WPF_CHECKS="+evidence.Count);
 }
}
