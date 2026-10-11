using System.Collections;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

// Real production window/controls/events on its Dispatcher, synthetic XMP only; no UI logic substitutes.
static partial class Program
{
 static readonly List<object> evidence=[];
 static MainWindow window=null!;
 static string folder="";
 static T Control<T>(string name)where T:class=>(T)window.FindName(name);
 static string Status=>Control<TextBlock>("Status").Text;
 static object? Field(string name)=>typeof(MainWindow).GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(window);
 static void Action(string method)=>typeof(MainWindow).GetMethod(method,BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[window,new RoutedEventArgs()]);
 static void Check(bool value,string name){if(!value)throw new Exception(name+": "+Status);evidence.Add(new{name,passed=true,status=Status});}
 static async Task Idle(){for(int i=0;i<1600&&(int)Field("datePending")!>0;i++)await Task.Delay(25);Check((int)Field("datePending")! ==0,"request-settled");}
 static PhotoDocument Doc(object row)=>(PhotoDocument)row.GetType().GetProperty("Document")!.GetValue(row)!;
 static TabItem? DatesTab(DependencyObject node) {
  if(node is TabItem item && item.Header?.ToString()=="批量日期")return item;
  foreach(var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())if(DatesTab(child)is{} found)return found;
  return null;
 }
 [STAThread]static void Main(string[] args)
 {
  folder=Path.GetFullPath(args[0]);Directory.CreateDirectory(folder);
  var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};
  window=new MainWindow{Title="PhotoTrail 日期页 · 独立自动交互验证"};
  window.Loaded+=async(_,_)=>{try{await Task.Delay(300);if(args.Contains("--track-batch-checks"))await RunTrackBatch();else if(args.Contains("--track-batch-performance"))await RunTrackBatchPerformance();else if(args.Contains("--track-batch-cancel"))await RunTrackBatchCancel();else if(args.Contains("--field-performance-checks"))await RunFieldPerformance(false);else if(args.Contains("--batch-late-checks"))await RunBatchLate();else if(args.Contains("--batch-direct-checks"))await RunBatchDirect();else if(args.Contains("--batch-cancel-checks"))await RunBatchCancel();else if(args.Contains("--batch-performance-checks"))await RunBatchPerformance(true);else if(args.Contains("--track-late-failure-checks"))await RunTrackLateFailures();else if(args.Contains("--track-adjustment-checks"))await RunTrackAdjustment(false);else if(args.Contains("--track-restore-checks"))await RunTrackAdjustment(true);else if(args.Contains("--batch-missing-checks"))await RunMissingDirect();else if(args.Contains("--rename-order-checks"))await RunRenameOrder();else if(args.Contains("--settings-checks"))await RunSettings(false);else if(args.Contains("--settings-restore-checks"))await RunSettings(true);else if(args.Contains("--offset-skip-checks"))await RunMissingDirect();else await RunBatchDirect();app.Shutdown(0);}catch(Exception error){File.WriteAllText(Path.Combine(folder,"ui-failure.txt"),error.ToString());Console.Error.WriteLine(error);foreach(var row in Control<ListBox>("Photos").Items.Cast<object>())Doc(row).ClearDraft();typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);app.Shutdown(1);}};
  app.Run(window);
 }
}
