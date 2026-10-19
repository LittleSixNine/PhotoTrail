using System.IO;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task SelectRecovery(string id) {
  await (Task)typeof(MainWindow).GetMethod("LoadInplaceRecords",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,null)!;
  var choice=Control<ComboBox>("InplaceRecords");choice.SelectedItem=choice.Items.Cast<object>().Single(x=>((InplaceRecord)x.GetType().GetProperty("Record")!.GetValue(x)!).Id==id);Action("ShowInplaceRecord");
 }
 static async Task InplaceFaultChecks() {
  var rows=await DateCoreRows(5);var photo=rows.Select(Doc).Single(d=>Path.GetFileName(d.FilePath)=="embedded.jpg");var original=File.ReadAllBytes(photo.FilePath);var fault=Environment.GetEnvironmentVariable("PHOTOTRAIL_R03B_TEST_FAILURE")!;
  var backup=Path.Combine(folder,"backups");Directory.CreateDirectory(backup);Input("BackupFolder",backup);Control<ComboBox>("SaveModeChoice").SelectedIndex=2;
  photo.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","isolated fault title"}});
  if(fault=="partial-ui")rows.Select(Doc).Single(d=>Path.GetFileName(d.FilePath)=="paired.jpg").SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","partial success title"}});
  Control<ListBox>("Photos").SelectedItems.Clear();Action("PrepareSaveAll");await BatchWait();Action("ExecuteSavePlan");await BatchWait();File.WriteAllText(Path.Combine(folder,"fault-save-summary.txt"),Control<TextBox>("SaveSummary").Text+"\n"+Status);var results=((List<SidecarResult>)Field("saveResults")!).ToArray();var result=results.Single(r=>r.Path==photo.FilePath);var record=InplaceHistory.Read(InplaceHistory.PathFor(result.RecordId!));
  var current=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).Single(d=>d.FilePath==photo.FilePath);
  if(fault.StartsWith("restore-")) {
   Check(result.State=="成功","fault-setup-save-real-source-and-UI-success");await SelectRecovery(record.Id);Action("RestoreInplaceRecord");await BatchWait();record=InplaceHistory.Read(InplaceHistory.PathFor(record.Id));
   Check(InplaceHistory.Pending(record)&&File.Exists(record.Backup),"restore-failure-persisted-stage-original-backup-kept");
   if(fault=="restore-readback")Check(File.ReadAllBytes(photo.FilePath).SequenceEqual(original)&&record.RestoreIdentity is not null,"restore-postcommit-failure-keeps-known-restored-bytes");
   else Check(await PhotoDocument.HashAsync(photo.FilePath)==record.NewHash,"restore-beforecommit-failure-preserves-saved-version");
   Check(Directory.GetFiles(Path.GetDirectoryName(record.Backup)! ,"before-restore-*.backup").Length>0||fault=="restore-backup","restore-current-version-retained");
  }else if(fault is "post-cancel" or "readback" or "log" or "ui" or "ui-log" or "partial-ui") {
   Check(result.State=="结果未知"&&InplaceHistory.Pending(record)&&await PhotoDocument.HashAsync(photo.FilePath)==record.NewHash,"postcommit-fault-known-disk-new-bytes-persistent-unknown");
   Check(ReferenceEquals(current,photo)&&photo.Draft.ContainsKey("XMP-dc:Title")&&current.SourceHash==record.OriginalHash,"postcommit-failure-retains-old-source-draft-no-new-SHA-binding");
   PlanFailure(()=>SavePlan.Prepare([photo],SaveMode.Inplace,SaveScope.All,"",[photo]),"unknown-forbids-blind-retry");
   await ExpectFailure(()=>RenameExecutor.ExecuteAsync(new(Array.AsReadOnly(new[]{new RenameFile(photo.FilePath,photo.FilePath+".renamed",photo.SourceHash)})),Path.Combine(folder,"rename-denied")),"unknown-forbids-rename");
   if(fault=="partial-ui")Check(results.Length==2&&results.Count(r=>r.State=="成功")==1&&results.Count(r=>r.State=="结果未知")==1,"partial-success-preserved-with-unknown-first-file");
  }else {
   Check(result.State is "失败" or "取消"&&!InplaceHistory.Pending(record),"precommit-fault-classified-without-target-commit");
   Check(photo.Draft.ContainsKey("XMP-dc:Title"),"precommit-fault-retains-draft");
   if(fault=="source-between-locks")Check(File.ReadAllBytes(photo.FilePath).Length>original.Length&&record.Phase=="failed","lock-transition-external-change-refused-and-retained");
   else Check(File.ReadAllBytes(photo.FilePath).SequenceEqual(original),"precommit-fault-original-exact-bytes");
   if(fault=="revision")Check(photo.Draft.ContainsKey("XMP-dc:Rights"),"later-revision-draft-not-discarded");
  }
  Check(File.Exists(InplaceHistory.PathFor(record.Id)),"fault-record-retained");SaveResult("inplace-fault-checks.json",new{fault,result.State,record.Phase,record.Id,backupExists=File.Exists(record.Backup)});
  // Only close this isolated test process after assertions; records and all disk versions remain.
  foreach(var row in Control<ListBox>("Photos").Items.Cast<object>())Doc(row).ClearDraft();
 }
 static async Task InplaceRestartChecks() {
  var rows=await DateCoreRows(5);var records=InplaceHistory.ReadAll();var pending=records.Single(InplaceHistory.Pending);var before=await PhotoDocument.HashAsync(pending.Target);
  Check(before==pending.NewHash&&File.Exists(pending.Backup),"restart-discovers-postcommit-persistent-record-and-actual-new-bytes");
  Check(Control<TextBlock>("InplaceStatus").Text.Contains("待核对／恢复1"),"startup-discovery-does-not-auto-write");
  InplaceHistory.RequireClear(rows.Select(Doc).Where(d=>d.FilePath!=pending.Photo).Select(d=>d.FilePath));Check(true,"unrelated-safe-targets-remain-readable");
  bool blocked=false;try{InplaceHistory.RequireClear([pending.Target]);}catch(IOException){blocked=true;}Check(blocked,"restart-pending-same-target-blocked");
  await SelectRecovery(pending.Id);Action("CheckInplaceRecord");await BatchWait();Check(InplaceHistory.Read(InplaceHistory.PathFor(pending.Id)).Phase=="saved"&&await PhotoDocument.HashAsync(pending.Target)==before,"restart-explicit-reconciliation-readback-no-blind-write");
  await SelectRecovery(pending.Id);Action("RestoreInplaceRecord");await BatchWait();var restored=InplaceHistory.Read(InplaceHistory.PathFor(pending.Id));Check(restored.Phase=="restored"&&await PhotoDocument.HashAsync(restored.Target)==restored.OriginalHash,"restart-record-restore-real-original-bytes-and-UI");
  SaveResult("inplace-restart-checks.json",new{pending.Id,restored.Phase});
 }
}
