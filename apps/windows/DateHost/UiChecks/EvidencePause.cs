using System.IO;
using System.Text.Json;
using System.Windows;

static partial class Program
{
 static int evidenceStage;
 static async Task PauseEvidence(string name){
  if(Environment.GetEnvironmentVariable("PHOTOTRAIL_EVIDENCE_STEPS") is not {} path)return;
  Directory.CreateDirectory(path);int stage=++evidenceStage;
  File.WriteAllText(Path.Combine(path,"stage.json"),JsonSerializer.Serialize(new{stage,name,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(PhotoTrail.Windows.MainWindow).Assembly.Location)))}));
  while(!File.Exists(Path.Combine(path,$"continue-{stage}")))await Task.Delay(100);
 }
 static async Task EvidenceDialog(string method,string name){
  if(Environment.GetEnvironmentVariable("PHOTOTRAIL_EVIDENCE_STEPS")is null)return;
  Exception? failure=null;
  var visit=window.Dispatcher.BeginInvoke(async()=>{Window? dialog=null;try{dialog=window.OwnedWindows.Cast<Window>().Last(w=>w.IsVisible);await PauseEvidence(name);dialog.Close();}catch(Exception error){failure=error;dialog?.Close();}});
  M3Call(method);await visit;if(failure is not null)throw failure;
 }
}
