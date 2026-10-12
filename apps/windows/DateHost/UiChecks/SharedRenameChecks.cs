using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task SharedRename() {
  var rows=await DateCoreRows(4);var list=Control<ListBox>("Photos");list.SelectAll();SelectMetadataTab("重命名");Input("RenameRules","date-prefix|_");Action("RefreshRenameOrder");await RenameWait();
  var hashes=Groups().SelectMany(g=>g.Members).ToDictionary(member=>member.Path,member=>member.Hash);Check(hashes.Count==4,"shared-rename-real-paired-four-files");
  var expected=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToDictionary(file=>file.Source,file=>file.Target);Check(expected.Count==4&&expected.Values.All(path=>Path.GetFileName(path).Length>20),"shared-rename-validated-date-name-preview");
  Action("FreezeRename");await RenameWait();var plan=(RenamePlan?)Field("frozenRenamePlan");Check(plan is not null&&plan.Files.All(file=>expected[file.Source]==file.Target),"shared-rename-preview-freeze-identical");
  Action("ExecuteRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("更名及内容核验完成"),"shared-rename-production-execute");var result=RenameExecutor.ReadJournal(Control<TextBox>("RenameJournalPath").Text);
  foreach(var file in result.Files)Check(await PhotoDocument.HashAsync(file.Current)==hashes[file.Source],"shared-rename-content-hash");Action("RestoreRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("恢复完成"),"shared-rename-production-recovery");foreach(var file in hashes)Check(File.Exists(file.Key)&&await PhotoDocument.HashAsync(file.Key)==file.Value,"shared-rename-original-path-hash");
  Input("RenameRules","date-set");Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan") is null,"shared-rename-date-set-paired-collision-rejected");
  DateCoreResult("r01b-rename-results.json");
 }
}
