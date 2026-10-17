using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task RunFieldPerformance(bool before){
  var list=Control<ListBox>("Photos");for(int i=0;i<12000&&(list.Items.Count<530||(bool)Field("busy")!);i++)await Task.Delay(10);Check(list.Items.Count==530,"fields-real530-import");var rows=list.Items.Cast<object>().ToArray();var collection=(IList)Field("photos")!;long importRequests=ToolRequests();var results=new List<object>();
  foreach(string kind in new[]{"fields","csv"})foreach(int count in new[]{1,20,100,530})for(int round=0;round<(count==530?3:1);round++){
   list.SelectedItems.Clear();collection.Clear();foreach(var row in rows.Take(count))collection.Add(row);await Responsive();var clock=Stopwatch.StartNew();list.SelectAll();double selectReturn=clock.Elapsed.TotalMilliseconds;await Responsive();double selectResponsive=clock.Elapsed.TotalMilliseconds;
   clock.Restart();if(kind=="fields"){SelectMetadataTab("编辑草稿");Input("TitleValue","performance title");Input("RightsValue","performance rights");}else{
    Control<TabControl>("WorkspaceTabs").SelectedIndex=4;var snapshot=MetadataCsv.Snapshot(list.SelectedItems.Cast<object>().Select(Doc).ToArray());var changed=snapshot.Select(r=>r with{Cells=new Dictionary<string,string>(r.Cells){["XMP-dc:Title"]=JsonSerializer.Serialize("performance title")}}).ToArray();string path=Path.Combine(folder,$"{count}-{round}.csv");File.WriteAllText(path,MetadataCsv.Export(changed));Input("CsvPath",path);
   }await Responsive();double editorMs=clock.Elapsed.TotalMilliseconds;long requests=ToolRequests();clock.Restart();if(kind=="fields")Action("ApplyDraft");else{if(before){Action("PreviewCsv");await BatchWait();}Action("ApplyCsv");}await BatchWait();await Responsive();double total=clock.Elapsed.TotalMilliseconds;
   var phases=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);phases["selectReturnMs"]=selectReturn;phases["selectResponsiveMs"]=selectResponsive;phases["editorMs"]=editorMs;phases["totalApplyMs"]=total;
   Check(list.SelectedItems.Cast<object>().Select(Doc).All(d=>d.Value("XMP-dc:Title")=="performance title"),"field-CSV-real-result-"+kind+count+round);results.Add(new{kind,count,round,phases,exifToolRequests=ToolRequests()-requests,dateHostRequests=0});Action(before?"UndoDraft":"UndoLastApply");await Responsive();
  }
  File.WriteAllText(Path.Combine(folder,before?"fields-before.json":"fields-after.json"),JsonSerializer.Serialize(new{before,importRequests,pollMilliseconds=25,processPeakBytes=Process.GetCurrentProcess().PeakWorkingSet64,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),results},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("FIELDS_PERFORMANCE_ROUNDS="+results.Count);
 }
}
