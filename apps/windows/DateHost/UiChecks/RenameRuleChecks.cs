using System.IO;
using System.Diagnostics;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static string R08Rule(string action,string text="",string replacement="",string part="stem")=>JsonSerializer.Serialize(new RenameRule("action",text,replacement){Action=action,Part=part});
 static async Task R08Preview(){Action("RefreshRenameOrder");await RenameWait();await Task.Delay(100);}
 static async Task R08aChecks()
 {
  await ImportDone();var originals=R06Rows();var seed=originals.Single(r=>Path.GetFileName(Doc(r).FilePath)=="embedded.jpg");
  var root=Path.Combine(folder,"rules");Directory.CreateDirectory(root);for(int i=0;i<100;i++)File.Copy(Doc(seed).FilePath,Path.Combine(root,$"rename-{i:D3}.jpg"));await ImportMore(root);
  var rows=R06Rows().Where(r=>Path.GetFileName(Doc(r).FilePath).StartsWith("rename-",StringComparison.Ordinal)).ToArray();Check(rows.Length==100,"R08a-all-100-imported");
  var hashes=R06Rows().ToDictionary(r=>Doc(r).FilePath,r=>Doc(r).SourceHash);var physical=originals.SelectMany(r=>new[]{Doc(r).FilePath,Doc(r).SidecarPath}).Where(p=>p is not null).Cast<string>().Distinct().ToDictionary(p=>p,p=>new FileInfo(p).LastWriteTimeUtc);
  SelectMetadataTab("重命名");var performance=new List<object>();var chain=R08Rule("add-begin","测试_")+"\n"+R08Rule("regex-replace","(rename)-([0-9]+)","$2_$1")+"\n"+R08Rule("replace-text","jpg","JPG","extensionOnly");
  foreach(var count in new[]{1,20,100}) {
   RefreshCompareSelection(rows.Take(count).ToArray());Control<TextBox>("RenameRules").Text=chain;var clock=Stopwatch.StartNew();await R08Preview();var preview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();var previewMs=clock.Elapsed.TotalMilliseconds;
   Check(preview.Length==count&&preview.All(p=>p.NewName.StartsWith("测试_",StringComparison.Ordinal)&&p.NewName.EndsWith("_rename.JPG",StringComparison.Ordinal)&&p.Steps.Contains("3: ")),"R08a-entire-chain-extensions-intermediates-"+count);
   clock.Restart();Action("FreezeRename");await RenameWait();var freezeMs=clock.Elapsed.TotalMilliseconds;var frozen=(RenamePlan?)Field("frozenRenamePlan");Check(frozen?.Files.Count==count&&frozen.Files.All(f=>f.NewName.EndsWith(".JPG",StringComparison.Ordinal)),"R08a-freeze-same-calculation-"+count);
   Control<TextBox>("RenameRules").Text=R08Rule("add-begin","cancel_");Check(Field("frozenRenamePlan")is null&&rows.Take(count).All(r=>File.Exists(Doc(r).FilePath)),"R08a-cancel-rule-change-no-disk-write-"+count);performance.Add(new{count,previewMs,freezeMs,includesPreviewWaitMs=100});
  }
  RefreshCompareSelection(originals);Control<TextBox>("RenameRules").Text=R08Rule("add-begin","pair_");await R08Preview();var pairPreview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();Check(pairPreview.Length==7&&pairPreview.Any(p=>p.NewName=="pair_raw.xmp")&&pairPreview.Any(p=>p.NewName=="pair_raw.DNG"),"R08a-preview-real-RAW-sidecars");
  Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan,"R08a-group-freeze-ready");
  var mutate=Doc(seed).FilePath;var before=File.GetLastWriteTimeUtc(mutate);File.SetLastWriteTimeUtc(mutate,before.AddSeconds(1));Action("ExecuteRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("System")&&File.Exists(mutate),"R08a-sameSHA-System-change-before-moves-rejected");File.SetLastWriteTimeUtc(mutate,before);
  Action("FreezeRename");await RenameWait();Action("ExecuteRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("更名及内容核验完成"),"R08a-real-paired-execution-complete");var journal=Control<TextBox>("RenameJournalPath").Text;var result=RenameExecutor.ReadJournal(journal);Check(result.Complete&&result.Files.Count==7,"R08a-version2-journal-readback");foreach(var file in result.Files){Check(File.Exists(file.Current)&&await PhotoDocument.HashAsync(file.Current)==file.Hash,"R08a-executed-source-content");Check(File.GetLastWriteTimeUtc(file.Current)==physical[file.Source],"R08a-executed-System-written");}
  Action("RestoreRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("恢复完成"),"R08a-production-restore-original-name");foreach(var file in result.Files)Check(File.Exists(file.Source)&&await PhotoDocument.HashAsync(file.Source)==file.Hash,"R08a-restored-content");
  seed=R06Rows().Single(r=>Doc(r).FilePath==mutate);RefreshCompareSelection([seed]);Control<TextBox>("RenameRules").Text=R08Rule("date-set");await R08Preview();var datePreview=Control<DataGrid>("RenamePreview").Items.Cast<RenameFile>().ToArray();Check(datePreview.Length==1&&System.Text.RegularExpressions.Regex.IsMatch(datePreview[0].NewName,@"^[0-9]{8}_[0-9]{6}\.jpg$"),"R08a-current-main-time-shared-proof");
  Doc(seed).SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","guard draft"}});Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null&&Doc(seed).Draft.Count==1,"R08a-draft-gate-preserves-input");Doc(seed).ClearDraft();
  Control<TextBox>("RenameRules").Text=R08Rule("device-set");await R08Preview();Check(Control<DataGrid>("RenamePreview").Items.Count==1,"R08a-metadata-missing-or-real-visible");
  Control<TextBox>("RenameRules").Text=R08Rule("regex-replace","[","X");await Task.Delay(150);Check(Field("frozenRenamePlan")is null&&Control<TextBlock>("RenameStatus").Text.Contains("非法正则"),"R08a-invalid-regex-visible-no-literal-fallback");
  foreach(var pair in hashes)Check(await PhotoDocument.HashAsync(pair.Key)==pair.Value,"R08a-all-original-source-SHA-protected");
  File.WriteAllText(Path.Combine(folder,"r08a-ui-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence,performance},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("R08A_WPF_CHECKS="+evidence.Count);window.Close();
 }
}
