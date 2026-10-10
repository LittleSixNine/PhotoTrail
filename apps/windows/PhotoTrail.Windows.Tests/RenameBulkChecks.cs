using PhotoTrail.Windows;
static class RenameBulkChecks
{
 public static async Task RunAsync()
 {
  var output=Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??throw new Exception("Missing private output");
  var folder=Path.Combine(output,"rename-bulk-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var paths=new string[3000];for(var index=0;index<paths.Length;index++){paths[index]=Path.Combine(folder,$"sample-{index:0000}.jpg");File.WriteAllText(paths[index],$"distinct synthetic payload {index}");}
  var plan=await RenamePlan.BuildAsync(paths,[new("prefix","批量_"),new("sequence")],false);
  var journals=Path.Combine(folder,"journals");var clock=System.Diagnostics.Stopwatch.StartNew();var result=await RenameExecutor.ExecuteAsync(plan,journals);clock.Stop();
  if(!result.Complete||result.Files.Count!=3000)throw new Exception("Bulk execute failed: "+result.Error);
  foreach(var file in plan.Files)if(File.Exists(file.Source)||await PhotoDocument.HashAsync(file.Target)!=file.Hash)throw new Exception("Bulk name/hash mismatch");
  var executeSeconds=clock.Elapsed.TotalSeconds;clock.Restart();var restored=await RenameExecutor.RestoreAsync(result.Journal,journals);clock.Stop();
  if(!restored.Complete)throw new Exception("Bulk restore failed: "+restored.Error);
  foreach(var file in plan.Files)if(!File.Exists(file.Source)||File.Exists(file.Target)||await PhotoDocument.HashAsync(file.Source)!=file.Hash)throw new Exception("Bulk restoration mismatch");
  if(Directory.GetFiles(folder,".phototrail-rename-*").Length!=0)throw new Exception("Bulk temp residue");
  Console.WriteLine($"3000 distinct synthetic files renamed and restored; every SHA256 verified. Execute {executeSeconds:F3}s; restore {clock.Elapsed.TotalSeconds:F3}s. No RAW/NAS performance claim.");
 }
}
