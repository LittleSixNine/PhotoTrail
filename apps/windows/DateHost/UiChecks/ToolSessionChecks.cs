using System.IO;
using System.Text.Json;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task ToolSessionChecks(string[] args){
  string output=Path.GetFullPath(args[0]);Directory.CreateDirectory(output);string source=Path.GetFullPath(args[2]),copy=Path.Combine(output,"中文-session.jpg");File.Copy(source,copy);
  var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var checks=new List<object>();
  void Assert(bool ok,string name){if(!ok)throw new Exception(name);checks.Add(new{name,passed=true});}
  string before=await PhotoDocument.HashAsync(source);long starts=ExifToolClient.StartedProcesses;
  await using(var session=client.KeepAlive()){
   var first=await client.ReadAsync(copy);await client.RunAsync(["-overwrite_original","-XMP-dc:Title=中文 {ready123} literal","--",copy]);var next=await client.ReadAsync(copy);
   Assert(first.GetProperty("File:FileType").GetString()=="JPEG"&&next.GetProperty("XMP-dc:Title").GetString()=="中文 {ready123} literal","real-read-write-read-Unicode-same-worker");
   Assert(ExifToolClient.StartedProcesses-starts==1,"three-requests-one-process");
   bool failed=false;try{await client.RunAsync(["--",Path.Combine(output,"missing.jpg")]);}catch(IOException){failed=true;}Assert(failed,"real-nonzero-exit-status-propagated");
   next=await client.ReadAsync(copy);Assert(next.GetProperty("XMP-dc:Title").GetString()=="中文 {ready123} literal","failed-worker-replaced-no-stale-response");
   bool warning=false;try{await client.RunAsync(["-PhotoTrailUnknownTag=bad","--",copy],rejectWarnings:true);}catch(IOException){warning=true;}Assert(warning,"actual-warning-refuses-delivery");
   bool invalid=false;try{await client.RunAsync(["-ver\n-execute"]);}catch(ArgumentException){invalid=true;}Assert(invalid,"argfile-line-injection-refused");
   invalid=false;try{await client.RunAsync(["--","-execute123"]);}catch(ArgumentException){invalid=true;}Assert(invalid,"relative-option-shaped-file-refused");
   invalid=false;try{await client.RunAsync(["-stay_open","False"]);}catch(ArgumentException){invalid=true;}Assert(invalid,"caller-cannot-change-session-protocol");
   bool timeout=false;try{await client.RunAsync(["-j","--",copy],timeout:TimeSpan.FromTicks(1));}catch(TimeoutException){timeout=true;}Assert(timeout,"deadline-never-publishes-incomplete-response");
   next=await client.ReadAsync(copy);Assert(next.GetProperty("File:FileType").GetString()=="JPEG","deadline-worker-replaced");
   using var cancelled=new CancellationTokenSource();cancelled.Cancel();bool canceled=false;try{await client.ReadAsync(copy,cancelled.Token);}catch(OperationCanceledException){canceled=true;}Assert(canceled,"cancel-before-request-preserves-worker-protocol");
  }
  var last=await client.ReadAsync(copy);Assert(last.GetProperty("XMP-dc:Title").GetString()=="中文 {ready123} literal","dispose-restores-normal-one-shot-client");Assert(await PhotoDocument.HashAsync(source)==before,"original-source-SHA-unchanged");
  File.WriteAllText(Path.Combine(output,"tool-session-results.json"),JsonSerializer.Serialize(new{buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),checks,requests=ExifToolClient.RequestCount,processes=ExifToolClient.StartedProcesses},new JsonSerializerOptions{WriteIndented=true}));
  Console.WriteLine("ToolSession checks "+checks.Count);
 }
}
