using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task SharedScale() {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R01_COUNT")!);string chain=Environment.GetEnvironmentVariable("PHOTOTRAIL_R01B_CHAIN")??"single";var rows=await DateCoreRows(count);var docs=rows.Select(Doc).ToArray();Control<ListBox>("Photos").SelectAll();
  var values=chain=="multi"?SharedChanges("2024:02:29 11:22:33.123456789-00:00"):new Dictionary<string,string>{{SharedTags[0],"2024:02:29 11:22:33.123456789-00:00"}};
  foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","earlier rights"}});var before=Drafts(rows);var clock=Stopwatch.StartNew();await SharedInput(chain=="csv"?"csv":"fields",docs,values);double validationApplyMs=clock.Elapsed.TotalMilliseconds;
  Check(docs.All(doc=>values.All(pair=>doc.Value(pair.Key)==pair.Value)),"scale-"+chain+"-date-texts");var timings=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);int requests=(int)Field("batchHostRequests")!;
  Action("UndoLastApply");Check(SameDrafts(rows,before),"scale-"+chain+"-complete-undo");await SharedInput(chain=="csv"?"csv":"fields",docs,values);
  string output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);clock.Restart();Action("SaveCopies");await BatchWait();double saveMs=clock.Elapsed.TotalMilliseconds;Check(Status.Contains("副本成功 "+count+"，失败 0"),"scale-"+chain+"-save");
  var saveTimings=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);clock.Restart();
  foreach(var doc in docs){var data=await client.ReadAsync(Path.Combine(output,Path.GetFileName(doc.FilePath)));Check(values.All(pair=>data.TryGetProperty(pair.Key,out var value)&&PhotoDocument.Text(value)==pair.Value),"scale-"+chain+"-readback");Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"scale-"+chain+"-source-hash");}
  double verifyMs=clock.Elapsed.TotalMilliseconds;Action("UndoDraft");
  File.WriteAllText(Path.Combine(folder,"r01b-scale-results.json"),JsonSerializer.Serialize(new{count,chain,fields=values.Count,dateCandidates=count*values.Count,hostRequests=requests,validationApplyMs,timings,saveMs,saveHostRequests=saveTimings.GetValueOrDefault("saveHostRequests"),verifyMs,passed=evidence.Count,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location)))},new JsonSerializerOptions{WriteIndented=true}));
 }
}
