using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task M6Checks()
 {
  explicitSavePlanChecks=true;await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();await Responsive();
  var rows=photos.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();Check(docs.Length==3,"M6-three-authorized-synthetic-JPEG-inputs");
  var source=docs.ToDictionary(d=>d.FilePath,d=>new{hash=d.SourceHash,created=File.GetCreationTimeUtc(d.FilePath).Ticks,written=File.GetLastWriteTimeUtc(d.FilePath).Ticks,attributes=File.GetAttributes(d.FilePath),acl=new FileInfo(d.FilePath).GetAccessControl().GetSecurityDescriptorSddlForm(AccessControlSections.Access)});
  Control<ComboBox>("InspectorView").SelectedIndex=1;await Responsive();M2Invoke("OpenWorkflowFields",(object)InspectorRows().Where(r=>r.EditTag is "XMP-dc:Title" or "XMP-dc:Description").ToArray());await Responsive();
  var timings=new Dictionary<string,double>();var watch=Stopwatch.StartNew();
  M2Invoke("SetPresetChain",MetadataPreset.Create("M6 cross-workspace",new[]{new MetadataOperation("XMP-dc:Title","setText","M6 synthetic title"),new MetadataOperation("XMP-dc:Description","setText","M6 synthetic description")}));
  M2Invoke("ApplyWorkflow");await BatchWait();timings["applyTwoFieldsThreePhotosMs"]=watch.Elapsed.TotalMilliseconds;
  Check(docs.All(d=>d.Draft.Count==2),"M6-two-fields-all-three-real-drafts");
  var tabs=Control<TabControl>("WorkspaceTabs");watch.Restart();tabs.SelectedIndex=1;await Responsive();
  Check(Control<ListBox>("PhotoStrip").SelectedItems.Count==3&&docs.All(d=>d.Draft.Count==2),"M6-map-shares-full-selection-and-drafts");timings["enterMapAndSelectionMs"]=watch.Elapsed.TotalMilliseconds;
  tabs.SelectedIndex=2;await Responsive();Check(photos.SelectedItems.Count==3&&docs.All(d=>d.Draft.Count==2),"M6-rename-navigation-keeps-metadata-drafts");
  tabs.SelectedIndex=0;Action("M1OpenSettings");await Responsive();var pages=Control<TabControl>("SettingsPages");var settings=window.OwnedWindows.Cast<Window>().Single(w=>ReferenceEquals(w.Content,pages));
  pages.SelectedIndex=5;await Responsive();settings.Close();Check(tabs.SelectedIndex==0&&photos.SelectedItems.Count==3&&docs.All(d=>d.Draft.Count==2),"M6-independent-settings-return-keeps-workspace-selection-and-drafts");
  Action("UndoLastApply");await Responsive();Check(docs.All(d=>d.Draft.Count==0)&&!Control<Button>("SaveButton").IsEnabled,"M6-one-undo-after-cross-workspace-navigation");
  M2Invoke("ApplyWorkflow");await BatchWait();var output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);
  Action("SaveCopies");Check(Field("preparedSave")is not null,"M6-copy-plan-explicitly-frozen");Action("CancelSavePlan");
  Check(!Directory.EnumerateFiles(output).Any()&&docs.All(d=>d.Draft.Count==2)&&Field("preparedSave")is null,"M6-cancel-freeze-writes-nothing-retains-all-drafts");
  Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();Check(Directory.EnumerateFiles(output).Count()==3&&docs.All(d=>d.Draft.Count==2),"M6-explicit-copy-save-three-files-retains-session-drafts");
  foreach(var doc in docs){var copy=await PhotoDocument.LoadAsync(InspectorTool(),Path.Combine(output,Path.GetFileName(doc.FilePath)));Check(copy.Value("XMP-dc:Title")=="M6 synthetic title"&&copy.Value("XMP-dc:Description")=="M6 synthetic description","M6-copy-reload-both-fields-"+Path.GetFileName(doc.FilePath));}
  Action("UndoLastApply");Check(docs.All(d=>d.Draft.Count==2),"M6-file-save-expires-old-apply-undo-without-clearing-drafts");
  Action("UndoDraft");M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));Check(docs.All(d=>d.Draft.Count==0)&&Directory.EnumerateFiles(output).Count()==3,"M6-clear-session-does-not-delete-saved-copies");
  ((Window)Field("metadataWindow")!).Close();tabs.SelectedIndex=2;Input("RenameRules","prefix|M6_\nsuffix|_checked");Action("RefreshRenameOrder");await RenameWait();
  Check(Control<DataGrid>("RenamePreview").Items.Count==3,"M6-real-two-action-preview-all-three");Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan p&&p.Files.Count==3,"M6-freeze-entire-selected-set");
  Input("RenameRules","prefix|M6_\nsuffix|_revised");Check(Field("frozenRenamePlan")is null&&source.Keys.All(File.Exists),"M6-parameter-change-invalidates-freeze-without-writing");
  Action("FreezeRename");await RenameWait();Action("ExecuteRename");await RenameWait();var record=RenameExecutor.ReadJournal(Control<TextBox>("RenameJournalPath").Text);
  Check(record.Complete&&record.Files.Count==3&&record.Files.All(f=>File.Exists(f.Current)&&!File.Exists(f.Source)),"M6-explicit-production-rename-and-journal");
  foreach(var file in record.Files)Check(await PhotoDocument.HashAsync(file.Current)==source[file.Source].hash,"M6-renamed-content-identical-"+Path.GetFileName(file.Source));
  Action("RestoreRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("恢复完成"),"M6-explicit-production-record-restore");
  foreach(var pair in source){var f=pair.Key;var s=pair.Value;Check(File.Exists(f)&&await PhotoDocument.HashAsync(f)==s.hash&&File.GetCreationTimeUtc(f).Ticks==s.created&&File.GetLastWriteTimeUtc(f).Ticks==s.written&&File.GetAttributes(f)==s.attributes&&new FileInfo(f).GetAccessControl().GetSecurityDescriptorSddlForm(AccessControlSections.Access)==s.acl,"M6-original-SHA-100ns-times-attributes-ACL-"+Path.GetFileName(f));}
  tabs.SelectedIndex=0;photos.SelectAll();await Responsive();Check(photos.SelectedItems.Count==3&&photos.Items.Cast<object>().All(r=>Doc(r).Draft.Count==0),"M6-return-metadata-final-selection-clean-drafts");
  File.WriteAllText(Path.Combine(folder,"m6-cross-workspace-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),evidence,timings},new JsonSerializerOptions{WriteIndented=true}));
 }
}
