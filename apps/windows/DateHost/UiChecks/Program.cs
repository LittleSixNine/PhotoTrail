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
 static bool explicitSavePlanChecks;
 static void Action(string method) {
  typeof(MainWindow).GetMethod(method,BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[window,new RoutedEventArgs()]);
  // Legacy copy checks still exercise an explicit production confirmation after its summary.
  if(method=="SaveCopies"&&!explicitSavePlanChecks)typeof(MainWindow).GetMethod("ExecuteSavePlan",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[window,new RoutedEventArgs()]);
 }
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
  explicitSavePlanChecks=args.Contains("--r05-checks")||args.Contains("--r05-scale")||args.Contains("--r04c-checks")||args.Contains("--r04c-scale")||args.Contains("--r04b-checks")||args.Contains("--r04b-scale")||args.Contains("--r04a-checks")||args.Contains("--r04a-scale")||args.Contains("--inplace-fault-checks")||args.Contains("--inplace-restart-checks")||args.Contains("--inplace-checks")||args.Contains("--inplace-scale")||args.Contains("--save-target-checks")||args.Contains("--save-target-scale");
  folder=Path.GetFullPath(args[0]);Directory.CreateDirectory(folder);
  var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};
  window=new MainWindow{StartupPaths=args.Skip(2).Where(a=>!a.StartsWith("--")).ToArray(),Title="PhotoTrail 日期页 · 独立自动交互验证"};
  window.Loaded+=async(_,_)=>{try{if(args.Contains("--inspector-scale-checks"))ObserveInspectorImport();await Task.Delay(300);if(args.Contains("--r06b-scale"))await R06bScale();else if(args.Contains("--r06b-checks"))await R06bChecks();else if(args.Contains("--r06a-checks"))await R06Checks();else if(args.Contains("--r06a-scale"))await R06Scale();else if(args.Contains("--r05-restart"))await R05Restart();else if(args.Contains("--r05-scale"))await R05Scale();else if(args.Contains("--r05-checks"))await R05Checks();else if(args.Contains("--r04c-restart"))await R04cRestart();else if(args.Contains("--r04c-checks"))await R04cChecks();else if(args.Contains("--r04c-scale"))await R04cScale();else if(args.Contains("--r04b-checks"))await R04bChecks();else if(args.Contains("--r04b-scale"))await R04bScale();else if(args.Contains("--r04a-checks"))await R04aChecks();else if(args.Contains("--r04a-scale"))await R04aScale();else if(args.Contains("--inplace-fault-checks"))await InplaceFaultChecks();else if(args.Contains("--inplace-restart-checks"))await InplaceRestartChecks();else if(args.Contains("--inplace-checks"))await InplaceChecks();else if(args.Contains("--inplace-scale"))await InplaceScale();else if(args.Contains("--save-target-checks"))await SaveTargetChecks();else if(args.Contains("--save-target-scale"))await SaveTargetScale();else if(args.Contains("--inspector-flow-checks"))await InspectorFlow();else if(args.Contains("--inspector-late-checks"))await InspectorLate();else if(args.Contains("--inspector-scale-checks"))await InspectorScale();else if(args.Contains("--inspector-empty-restart-checks"))await InspectorEmptyRestart();else if(args.Contains("--projection-page-scale-checks"))await ProjectionPageScale();else if(args.Contains("--projection-workflow-checks"))await ProjectionWorkflow();else if(args.Contains("--r01b-protection-checks"))await SharedProtection();else if(args.Contains("--r01b-library-checks"))await SharedLibrary();else if(args.Contains("--r01b-rename-checks"))await SharedRename();else if(args.Contains("--r01b-fault-checks"))await SharedFault();else if(args.Contains("--r01b-scale-checks"))await SharedScale();else if(args.Contains("--r01b-entry-checks"))await SharedEntries();else if(args.Contains("--date-core-copy-checks"))await DateCoreCopies();else if(args.Contains("--date-core-scale-checks"))await DateCoreScale();else if(args.Contains("--date-core-mismatch-checks"))await DateCoreMismatch();else if(args.Contains("--library-terminal-checks"))await RunLibraryTerminal();else if(args.Contains("--preset-library-checks"))await RunPresetLibrary();else if(args.Contains("--library-restore-checks"))RunLibraryRestore();else if(args.Contains("--ordered-copy-checks"))await RunOrderedCopies();else if(args.Contains("--ordered-preset-checks"))await RunOrderedPresets();else if(args.Contains("--scheme-model-checks"))RunSchemeModels();else if(args.Contains("--scheme-library-checks"))await RunSchemeLibrary();else if(args.Contains("--track-batch-checks"))await RunTrackBatch();else if(args.Contains("--track-batch-performance"))await RunTrackBatchPerformance();else if(args.Contains("--track-batch-cancel"))await RunTrackBatchCancel();else if(args.Contains("--field-performance-checks"))await RunFieldPerformance(false);else if(args.Contains("--batch-late-checks"))await RunBatchLate();else if(args.Contains("--batch-direct-checks"))await RunBatchDirect();else if(args.Contains("--batch-cancel-checks"))await RunBatchCancel();else if(args.Contains("--batch-performance-checks"))await RunBatchPerformance(true);else if(args.Contains("--track-late-failure-checks"))await RunTrackLateFailures();else if(args.Contains("--track-adjustment-checks"))await RunTrackAdjustment(false);else if(args.Contains("--track-restore-checks"))await RunTrackAdjustment(true);else if(args.Contains("--batch-missing-checks"))await RunMissingDirect();else if(args.Contains("--rename-order-checks"))await RunRenameOrder();else if(args.Contains("--settings-checks"))await RunSettings(false);else if(args.Contains("--settings-restore-checks"))await RunSettings(true);else if(args.Contains("--offset-skip-checks"))await RunMissingDirect();else await RunBatchDirect();app.Shutdown(0);}catch(Exception error){File.WriteAllText(Path.Combine(folder,"ui-failure.txt"),error.ToString());Console.Error.WriteLine(error);File.WriteAllText(Path.Combine(folder,"failed-draft-snapshot.local.json"),JsonSerializer.Serialize(Control<ListBox>("Photos").Items.Cast<object>().Select(r=>new{file=Doc(r).FilePath,draft=Doc(r).Draft}),new JsonSerializerOptions{WriteIndented=true}));foreach(var row in Control<ListBox>("Photos").Items.Cast<object>())Doc(row).ClearDraft();typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);typeof(MainWindow).GetMethod("SetPresetChain",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new MetadataPreset("新预设",Array.Empty<MetadataOperation>())]);app.Shutdown(1);}};
  app.Run(window);
 }
}
