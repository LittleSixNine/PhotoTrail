using PhotoTrail.Windows;
static class RenameExecutionChecks
{
 public static async Task RunAsync()
 {
  var passed=0;void Check(bool value){if(!value)throw new Exception("Rename execution assertion failed");passed++;}
  var output=Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??throw new Exception("Missing private output");var folder=Path.Combine(output,"rename-execution-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var journals=Path.Combine(folder,"journals");var a=Path.Combine(folder,"a.jpg");var b=Path.Combine(folder,"b.jpg");var xmp=Path.ChangeExtension(a,".xmp");
  File.WriteAllText(a,"synthetic-A");File.WriteAllText(b,"synthetic-B");File.WriteAllText(xmp,"synthetic-sidecar");
  var lockFile=Path.Combine(folder,"lock.bin");File.WriteAllText(lockFile,"identity-check");
  using(var handle=WindowsRename.Open(lockFile))
  {
   try{File.Move(lockFile,Path.Combine(folder,"external.bin"));throw new Exception("External rename allowed");}catch(IOException){Check(true);}
   try{File.WriteAllText(lockFile,"replacement");throw new Exception("External write allowed");}catch(IOException){Check(true);}
   WindowsRename.Move(handle,Path.Combine(folder,"handle-moved.bin"));Check(File.Exists(Path.Combine(folder,"handle-moved.bin")));
  }
  var aHash=await PhotoDocument.HashAsync(a);var bHash=await PhotoDocument.HashAsync(b);var xHash=await PhotoDocument.HashAsync(xmp);
  var swap=await RenamePlan.BuildTargetsAsync([(a,"b.jpg"),(b,"a.jpg")]);var result=await RenameExecutor.ExecuteAsync(swap,journals);Check(result.Complete);
  Check(await PhotoDocument.HashAsync(a)==bHash&&await PhotoDocument.HashAsync(b)==aHash);Check(await PhotoDocument.HashAsync(Path.ChangeExtension(b,".xmp"))==xHash);
  var record=RenameExecutor.ReadJournal(result.Journal);Check(record.Complete&&record.Files.All(row=>File.Exists(row.Current)));
  var restored=await RenameExecutor.RestoreAsync(result.Journal,journals);Check(restored.Complete);Check(await PhotoDocument.HashAsync(a)==aHash&&await PhotoDocument.HashAsync(b)==bHash&&await PhotoDocument.HashAsync(xmp)==xHash);
  Check(!Directory.GetFiles(folder,".phototrail-rename-*").Any());
  var casing=await RenameExecutor.ExecuteAsync(await RenamePlan.BuildTargetsAsync([(a,"A.JPG")]),journals);Check(casing.Complete);Check(Directory.GetFiles(folder).Any(path=>Path.GetFileName(path)=="A.JPG"));Check((await RenameExecutor.RestoreAsync(casing.Journal,journals)).Complete);
  var stale=await RenamePlan.BuildAsync([a],[new("prefix","new_")],false);File.AppendAllText(a,"external-change");
  try{await RenameExecutor.ExecuteAsync(stale,journals);throw new Exception("Stale source accepted");}catch(IOException){Check(File.Exists(a)&&!File.Exists(Path.Combine(folder,"new_a.jpg")));}
  var occupied=await RenamePlan.BuildAsync([b],[new("prefix","new_")],false);File.WriteAllText(Path.Combine(folder,"new_b.jpg"),"external-target");
  try{await RenameExecutor.ExecuteAsync(occupied,journals);throw new Exception("Late target accepted");}catch(IOException){Check(File.ReadAllText(Path.Combine(folder,"new_b.jpg"))=="external-target");}
  using(var cancel=new CancellationTokenSource()){cancel.Cancel();try{await RenameExecutor.ExecuteAsync(await RenamePlan.BuildAsync([b],[new("prefix","z_")],false),journals,cancel.Token);throw new Exception("Cancel ignored");}catch(OperationCanceledException){Check(File.Exists(b));}}
  File.AppendAllText(casing.Files[0].Source,"new-content");
  try{await RenameExecutor.RestoreAsync(casing.Journal,journals);throw new Exception("Changed recovery accepted");}catch(IOException){Check(true);}
  var partial=Path.Combine(folder,"partial.jpg");File.WriteAllText(partial,"partial-main");File.WriteAllText(Path.ChangeExtension(partial,".xmp"),"partial-sidecar");
  var partialPlan=await RenamePlan.BuildAsync([partial],[new("prefix","p_")],false);
  using(var midCancel=new CancellationTokenSource())
  {
   var interrupted=await RenameExecutor.ExecuteAsync(partialPlan,journals,midCancel.Token,(completed,total)=>{if(completed==1)midCancel.Cancel();});
   Check(!interrupted.Complete&&interrupted.Files.Any(f=>f.State=="待恢复"));Check(!RenameExecutor.ReadJournal(interrupted.Journal).Complete);
   var recovered=await RenameExecutor.RestoreAsync(interrupted.Journal,journals);Check(recovered.Complete&&File.Exists(partial)&&File.Exists(Path.ChangeExtension(partial,".xmp")));
  }
  var late=Path.Combine(folder,"late.jpg");File.WriteAllText(late,"late-original");var latePlan=await RenamePlan.BuildAsync([late],[new("prefix","new_")],false);
  var collision=await RenameExecutor.ExecuteAsync(latePlan,journals,progress:(completed,total)=>{if(completed==1)File.WriteAllText(Path.Combine(folder,"new_late.jpg"),"concurrent-target");});
  Check(!collision.Complete&&File.ReadAllText(Path.Combine(folder,"new_late.jpg"))=="concurrent-target");
  Check((await RenameExecutor.RestoreAsync(collision.Journal,journals)).Complete&&File.ReadAllText(late)=="late-original");
  var torn=Path.Combine(journals,"torn.jsonl");File.Copy(collision.Journal,torn);File.AppendAllText(torn,"{\"Index\":");Check(!RenameExecutor.ReadJournal(torn).Complete);
  var invalid=Path.Combine(journals,"invalid.jsonl");File.Copy(collision.Journal,invalid);File.AppendAllText(invalid,"{\"Index\":0,\"State\":2}\n");
  try{RenameExecutor.ReadJournal(invalid);throw new Exception("Invalid journal order accepted");}catch(InvalidDataException){Check(true);}
  var newSidecar=Path.Combine(folder,"new-sidecar.jpg");File.WriteAllText(newSidecar,"before-sidecar");
  var beforeSidecar=await RenamePlan.BuildAsync([newSidecar],[new("prefix","x_")],false);File.WriteAllText(Path.ChangeExtension(newSidecar,".xmp"),"late-sidecar");
  try{await RenameExecutor.ExecuteAsync(beforeSidecar,journals);throw new Exception("Late sidecar accepted");}catch(IOException){Check(File.Exists(newSidecar)&&File.Exists(Path.ChangeExtension(newSidecar,".xmp")));}
  Console.WriteLine($"{passed} rename execute/journal/readback/restore/stale boundary assertions passed with synthetic files.");
 }
}
