using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task SessionBatchCancelChecks(){
  await ImportDone();var docs=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).ToArray();Check(docs.Length==20,"R2-cancel20-real-owned-inputs");var originals=docs.ToDictionary(d=>d.FilePath,d=>d.SourceHash);foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","R2 cancellable save"}});
  string backup=Path.Combine(folder,"backups");Directory.CreateDirectory(backup);Input("BackupFolder",backup);Control<ComboBox>("SaveModeChoice").SelectedIndex=2;Action("PrepareSaveAll");Action("ExecuteSavePlan");
  for(int i=0;i<1200&&((List<SidecarResult>)Field("saveResults")!).Count<2;i++)await Task.Delay(25);
  int finishedBefore=((List<SidecarResult>)Field("saveResults")!).Count;Check(finishedBefore>=2&&finishedBefore<20&&(bool)Field("busy")!,"R2-real-partial-success-before-cancel");var clock=Stopwatch.StartNew();Action("CancelRead");await BatchWait();double cancelMs=clock.Elapsed.TotalMilliseconds;
  var results=((List<SidecarResult>)Field("saveResults")!).ToArray();Check(results.Length==20&&results.Any(r=>r.State=="取消")&&results.Any(r=>r.State=="成功"),"R2-cancel-preserves-success-and-unstarted-results");
  Check(await RetainCheckerInput("cancelled-partial-save-before-recovery"),"R2-cancelled-input-roundtrip-snapshot-retained");var records=InplaceHistory.ReadAll();
  int incompleteBackups=await RecoverSessionRecords(records);
  Check(!InplaceHistory.ReadAll().Any(InplaceHistory.Pending),"R2-no-pending-after-explicit-cancel-recovery");foreach(var pair in originals)Check(await PhotoDocument.HashAsync(pair.Key)==pair.Value,"R2-cancel-all20-original-SHA-restored");foreach(var row in Control<ListBox>("Photos").Items.Cast<object>())Doc(row).ClearDraft();
  File.WriteAllText(Path.Combine(folder,"session-cancel-results.json"),JsonSerializer.Serialize(new{buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),cancelMs,finishedBefore,records=records.Length,incompleteBackups,checks=evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
 static async Task<int> RecoverSessionRecords(InplaceRecord[] records){
  int incomplete=0;
  foreach(var r in records){
   if(r.Phase is "failed" or "cancelled"){
    await InplaceHistory.VerifyCurrent(r,r.OriginalHash,r.Original.Identity,default);Check(true,"R2-cancel-before-commit-original-identity-properties-SHA-confirmed");
    if(!File.Exists(r.Backup)||await PhotoDocument.HashAsync(r.Backup)!=r.OriginalHash)incomplete++;
    continue;
   }
   Check(await PhotoDocument.HashAsync(r.Backup)==r.OriginalHash,"R2-committed-file-has-full-original-backup");
   if(r.Phase=="restored")continue;
   var list=Control<ComboBox>("InplaceRecords");list.SelectedItem=list.Items.Cast<object>().Single(x=>((InplaceRecord)x.GetType().GetProperty("Record")!.GetValue(x)!).Id==r.Id);Action("ShowInplaceRecord");Action("RestoreInplaceRecord");await BatchWait();Check(InplaceHistory.Read(InplaceHistory.PathFor(r.Id)).Phase=="restored","R2-explicit-recovery-after-session-cancel");
  }
  return incomplete;
 }
 static async Task SessionCancelRecoveryChecks(){
  await ImportDone();var records=InplaceHistory.ReadAll();Check(records.Length>0&&records.Select(r=>r.OriginalHash).Distinct().Count()==1,"R2-owned-cancel-run-one-known-synthetic-source");int incompleteBackups=await RecoverSessionRecords(records);
  foreach(var row in Control<ListBox>("Photos").Items.Cast<object>())Check(await PhotoDocument.HashAsync(Doc(row).FilePath)==records[0].OriginalHash,"R2-failed-checker-run-all-source-SHA-restored");Check(!InplaceHistory.ReadAll().Any(InplaceHistory.Pending),"R2-failed-checker-run-no-pending");
  File.WriteAllText(Path.Combine(folder,"session-cancel-recovery-results.json"),JsonSerializer.Serialize(new{buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),incompleteBackups,checks=evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
