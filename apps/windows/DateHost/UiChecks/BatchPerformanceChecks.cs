using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

static partial class Program
{
 static long ToolRequests()=>(long)typeof(ExifToolClient).GetField("RequestCount",BindingFlags.NonPublic|BindingFlags.Static)!.GetValue(null)!;
 static async Task Responsive()=>await window.Dispatcher.InvokeAsync(()=>{},DispatcherPriority.ApplicationIdle);
 static async Task BatchWait(){for(int i=0;i<12000&&(bool)Field("busy")!;i++)await Task.Delay(25);Check(!(bool)Field("busy")!,"batch-settled");}
 static async Task RunBatchPerformance(bool optimized)
 {
  var list=Control<ListBox>("Photos");for(int i=0;i<12000&&(list.Items.Count<530||(bool)Field("busy")!);i++)await Task.Delay(10);
  Check(list.Items.Count==530,"real-independent-530-import");var all=list.Items.Cast<object>().ToArray();var collection=(IList)Field("photos")!;var results=new List<object>();bool offset=Environment.GetCommandLineArgs().Contains("--offset");
  foreach(int count in new[]{1,20,100,530})for(int round=0;round<(count==530?3:1);round++){
   list.SelectedItems.Clear();collection.Clear();foreach(var row in all.Take(count))collection.Add(row);await Responsive();if(offset)foreach(var row in all.Take(count))Doc(row).SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal","2024:01:15 10:20:30.123456Z"},{"XMP-dc:Rights","earlier rights"}});
   var tool=ToolRequests();var select=Stopwatch.StartNew();list.SelectAll();double selectReturn=select.Elapsed.TotalMilliseconds;await Responsive();double selectResponsive=select.Elapsed.TotalMilliseconds;
   var editor=Stopwatch.StartNew();SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=offset?0:1;Control<TextBox>("DateSeconds").Text="1";Control<TextBox>("DateStart").Text="2024:01:01 00:00:00.123456Z";Control<TextBox>("DateStep").Text="1";await Responsive();double editorMs=editor.Elapsed.TotalMilliseconds;
   var total=Stopwatch.StartNew();Action("ApplyDates");await BatchWait();await Responsive();
   var phases=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);phases["selectReturnMs"]=selectReturn;phases["selectResponsiveMs"]=selectResponsive;phases["editorMs"]=editorMs;phases["totalApplyMs"]=total.Elapsed.TotalMilliseconds;
   Check(list.SelectedItems.Cast<object>().Select(Doc).All(d=>d.Draft.ContainsKey(d.MainDateTag)),"real-batch-drafts-"+count+"-"+round);
   int host=(int)Field("batchHostRequests")!;
   results.Add(new{count,round,phases,exifToolRequests=ToolRequests()-tool,dateHostRequests=host});
   Action("UndoLastApply");await Responsive();
  }
  File.WriteAllText(Path.Combine(folder,offset?(optimized?"performance-offset-after.json":"performance-offset-before.json"):(optimized?"performance-after.json":"performance-before.json")),JsonSerializer.Serialize(new{optimized,offset,importExifToolRequests=ToolRequests(),pollMilliseconds=25,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),results},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("BATCH_PERFORMANCE_ROUNDS="+results.Count);foreach(var row in all)Doc(row).ClearDraft();
 }
}
