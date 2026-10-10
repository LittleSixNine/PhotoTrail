using PhotoTrail.Windows;
static class RenameChecks
{
 public static async Task RunAsync()
 {
  var count=0;void Check(bool value){if(!value)throw new Exception("Rename preview assertion failed");count++;}
  foreach(var name in new[]{"", ".", "..", "CON", "con.JPG", "NUL.xmp", "COM1.jpg", "LPT9.png", "COM¹.jpg", "LPT².xmp", "file.", "file ", "bad/name.jpg", "bad:name.jpg", "bad?.jpg", "bad\ud800.jpg", new string('x',256)})Check(!RenamePlan.ValidName(name));
  foreach(var name in new[]{"照片 空格.jpg","COM10.jpg","a.JPG",".hidden","two.parts.jpg", "照片😀.jpg"})Check(RenamePlan.ValidName(name));
  Check(RenamePlan.Apply("a.JPG",[new("prefix","旅_"),new("suffix","_end"),new("sequence",Start:7,Padding:3)],2)=="旅_a_end009.JPG");
  Check(RenamePlan.Apply("a.jpg",[new("prefix","b"),new("replace","ba","c")],0)=="c.jpg");
  Check(RenamePlan.Apply("a.jpg",[new("replace","ba","c"),new("prefix","b")],0)=="ba.jpg");
  foreach(var rule in new[]{new RenameRule("unknown"),new RenameRule("replace"),new RenameRule("sequence",Step:0),new RenameRule("set","CON")})
  {try{RenamePlan.Apply("a.jpg",[rule],0);throw new Exception("Invalid rule accepted");}catch(ArgumentException){Check(true);}}
  var output=Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??throw new Exception("Missing private test output");
  var folder=Path.Combine(output,"rename-preview-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
  var a=Path.Combine(folder,"a.jpg");var b=Path.Combine(folder,"b.jpg");File.WriteAllText(a,"synthetic-a");File.WriteAllText(b,"synthetic-b");File.WriteAllText(Path.ChangeExtension(a,".xmp"),"synthetic-sidecar");
  var plan=await RenamePlan.BuildAsync([b,a],[new("prefix","new_"),new("sequence")],true);
  Check(plan.Files.Count==3);Check(plan.Files[0].OriginalName=="a.jpg"&&plan.Files[0].NewName=="new_a001.jpg");Check(plan.Files[1].NewName=="new_a001.xmp");
  Check(File.Exists(a)&&!File.Exists(plan.Files[0].Target));Check(plan.Files[0].Hash==await PhotoDocument.HashAsync(a));
  var swap=await RenamePlan.BuildTargetsAsync([(a,"b.jpg"),(b,"a.jpg")]);Check(swap.Files.Count==3);
  var casing=await RenamePlan.BuildTargetsAsync([(a,"A.jpg")]);Check(casing.Files[0].NewName=="A.jpg");
  async Task Reject(Func<Task<RenamePlan>> action){try{await action();throw new Exception("Conflict accepted");}catch(IOException){Check(true);}}
  await Reject(()=>RenamePlan.BuildTargetsAsync([(a,"same.jpg"),(b,"SAME.jpg")]));
  File.WriteAllText(Path.Combine(folder,"occupied.jpg"),"external");await Reject(()=>RenamePlan.BuildTargetsAsync([(a,"occupied.jpg")]));
  await Reject(()=>RenamePlan.BuildAsync([a,Path.ChangeExtension(a,".xmp")],[],false));
  using(var cancelled=new CancellationTokenSource()){cancelled.Cancel();try{await RenamePlan.BuildAsync([a],[],false,cancelled.Token);throw new Exception("Cancellation ignored");}catch(OperationCanceledException){Check(true);}}
  var bulk=Path.Combine(folder,"bulk");Directory.CreateDirectory(bulk);var paths=new string[3000];
  for(var i=0;i<paths.Length;i++){paths[i]=Path.Combine(bulk,$"{i:0000}.jpg");File.WriteAllText(paths[i],"small-synthetic-file");}
  var clock=System.Diagnostics.Stopwatch.StartNew();var large=await RenamePlan.BuildAsync(paths,[new("prefix","p_"),new("sequence")],false);clock.Stop();
  Check(large.Files.Count==3000);Check(large.Files.Select(f=>f.Target).Distinct(StringComparer.OrdinalIgnoreCase).Count()==3000);Check(Directory.GetFiles(bulk).Length==3000);
  Console.WriteLine($"{count} rename preview/boundary assertions passed; 3000 small-file plan in {clock.Elapsed.TotalSeconds:F3}s. No input file renamed.");
 }
}
