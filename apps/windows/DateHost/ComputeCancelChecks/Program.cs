using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;

// Observes existing real-host stderr marker and the actual adapter stdout task, without slowing either.
static class ComputeCancelProbe
{
 internal static string Folder="";
 static readonly Stopwatch clock=Stopwatch.StartNew();
 static readonly object gate=new();
 static readonly Dictionary<string,(Process Child,Task<string> Output)> active=[];
 internal static string LatestId="";
 internal static Action? AfterStarted;
 internal static readonly List<object> Events=[];
 internal static void Record(string phase,object detail) {
  lock(gate){Events.Add(new{phase,utc=DateTimeOffset.UtcNow,elapsedMs=clock.Elapsed.TotalMilliseconds,detail});
   File.WriteAllText(Path.Combine(Folder,"phase-events.json"),JsonSerializer.Serialize(Events,new JsonSerializerOptions{WriteIndented=true}));}
 }
 internal static void Started(Process child,Task<string> output,string id,int items) {
  lock(gate){active[id]=(child,output);LatestId=id;}
  Record("first_item_computed",new{id,pid=child.Id,items,hasExited=child.HasExited,stdoutCompleted=output.IsCompleted,stdoutStatus=output.Status.ToString()});
  AfterStarted?.Invoke();
 }
 internal static bool BeforeCancel() {
  var id=LatestId;bool inFlight=false;
  if(active.TryGetValue(id,out var state)){
   try {
   bool hasExited=state.Child.HasExited,stdoutCompleted=state.Output.IsCompleted;
   inFlight=!hasExited&&!stdoutCompleted;
   Record("cancel_before_token",new{id,pid=state.Child.Id,hasExited,stdoutCompleted,stdoutStatus=state.Output.Status.ToString(),inFlight});
   }catch(InvalidOperationException){Record("cancel_after_child_disposed",new{id,inFlight=false});}
  }else Record("cancel_before_marker",new{id});
  return inFlight;
 }
 internal static void Exited(Process child,Task<string> output,string id,int accepted,int published) => Record("child_exited",new{id,pid=child.Id,hasExited=child.HasExited,stdoutStatus=output.Status.ToString(),accepted,published});
}

static class Program
{
 static MainWindow window=null!;
 static Application app=null!;
 static PhotoDocument[] docs=[];
 static string draftSnapshot="";
 static bool stageConfirmed,sharedEntry;
 static T Control<T>(string name)where T:class=>(T)window.FindName(name);
 static object? Field(string name)=>typeof(MainWindow).GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.GetValue(window);
 static string Drafts()=>JsonSerializer.Serialize(docs.Select(d=>d.Draft));
 static void Check(bool ok,string label){ComputeCancelProbe.Record(label,new{passed=ok});if(!ok)throw new Exception(label);}
 static TabItem? DatesTab(DependencyObject node){if(node is TabItem item&&item.Header?.ToString()=="批量日期")return item;foreach(var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())if(DatesTab(child)is{} found)return found;return null;}
 static async Task Adapter()
 {
  var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
  using var cancel=new CancellationTokenSource();
  Action onStarted=()=>{stageConfirmed=ComputeCancelProbe.BeforeCancel();cancel.Cancel();};adapter.CalculationStarted+=onStarted;
  var jobs=Enumerable.Range(0,3000).Select(i=>new DateJob(new(i.ToString(),"offset","2024:01:01 00:00:00.123456789-00:00",Years:1,Months:1,Days:1,Hours:1,Minutes:1,Seconds:1))).ToArray();
  try{await adapter.ComputeAsync(jobs,1,()=>1,cancel.Token);throw new Exception("Cancellation not observed");}catch(DateFailure error){Check(error.Code=="canceled","adapter-canceled");}
  Check(stageConfirmed&&adapter.AcceptedFrames==0&&adapter.PublishedCalls==0,"real-compute-marker-before-output-no-publication");
  Check(adapter.LastChildExited,"adapter-child-reaped");
  adapter.CalculationStarted-=onStarted;
  foreach(int pid in adapter.Pids){try{using var child=Process.GetProcessById(pid);Check(child.HasExited,"adapter-pid-exited");}catch(ArgumentException){Check(true,"adapter-pid-gone");}}
  var next=await adapter.ComputeAsync([new(new("next","offset","2024:01:01 00:00:00.123456789-00:00",Seconds:2))],2,()=>2);
  Check(next[0].Values![0]=="2024:01:01 00:00:02.123456789-00:00"&&adapter.LastChildExited,"adapter-next-preview-and-cleanup");
  var baseline=await adapter.ComputeAsync(jobs,3,()=>3);
  Check(baseline.Length==3000&&baseline.All(r=>r.Error is null),"legal-3000-full-computation-baseline");
  ComputeCancelProbe.Record("baseline_measurement",adapter.Measurements.Last());
 }
 static async Task PrepareWindow(bool automatic)
 {
  while((bool)Field("busy")!)await Task.Delay(10);
  var list=Control<ListBox>("Photos");Check(list.Items.Count==1,"one-real-import-synthetic-xmp");
  var first=(PhotoDocument)list.Items[0].GetType().GetProperty("Document")!.GetValue(list.Items[0])!;
  var collection=(IList)Field("photos")!;var rowType=list.Items[0].GetType();var ctor=typeof(PhotoDocument).GetConstructors(BindingFlags.NonPublic|BindingFlags.Instance).Single();
  var data=Path.Combine(ComputeCancelProbe.Folder,"data");Directory.CreateDirectory(data);collection.Clear();docs=new PhotoDocument[3000];
  for(int i=0;i<docs.Length;i++){var path=Path.Combine(data,$"sample-{i:D4}.xmp");File.Copy(first.FilePath,path);docs[i]=(PhotoDocument)ctor.Invoke([path,null,first.Embedded,null,first.SourceHash,null]);collection.Add(Activator.CreateInstance(rowType,docs[i])!);}
  docs[100].SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","existing synthetic title"}});
  await docs[1].SetDraftAsync(new Dictionary<string,string>{{docs[1].MainDateTag,"2026:01:01 00:00:00.123Z"}});
  draftSnapshot=Drafts();list.SelectAll();var dateTab=DatesTab(window)!;((TabControl)LogicalTreeHelper.GetParent(dateTab)).SelectedItem=dateTab;Control<ComboBox>("DateMode").SelectedIndex=0;
  foreach(var name in new[]{"DateYears","DateMonths","DateDays","DateHours","DateMinutes","DateSeconds"})Control<TextBox>(name).Text="1";
  if(sharedEntry){
   var rows=MetadataCsv.Snapshot(docs).Select((row,index)=>row with{Cells=new Dictionary<string,string>(row.Cells){{"XMP-exif:DateTimeDigitized",JsonSerializer.Serialize("2024:01:01 00:00:00."+index.ToString("D9")+"-00:00")}}}).ToArray();
   var csv=Path.Combine(ComputeCancelProbe.Folder,"shared-input.csv");MetadataCsv.WriteNew(csv,MetadataCsv.Export(rows,false));Control<TextBox>("CsvPath").Text=csv;Control<TabControl>("WorkspaceTabs").SelectedIndex=4;
  }
  var cancel=FindButton(window,sharedEntry?"取消任务":"取消应用")!;var apply=Control<Button>(sharedEntry?"CsvApplyButton":"DatePlanApplyButton");
  cancel.PreviewMouseLeftButtonDown+=(_,_)=>stageConfirmed=ComputeCancelProbe.BeforeCancel();
  cancel.Click+=async(_,_)=>{try{
   ComputeCancelProbe.Record("wpf_cancel_click_handler",new{stageConfirmed,status=Control<TextBlock>("Status").Text,busy=(bool)Field("busy")!});
   Check(stageConfirmed,"wpf-real-computation-stage-confirmed");
   var limit=Stopwatch.StartNew();while((bool)Field("busy")!&&limit.Elapsed<TimeSpan.FromSeconds(45))await Task.Delay(10);
   Check(!(bool)Field("busy")!&&Drafts()==draftSnapshot,"cancel-entire-batch-no-partial-drafts");
   Check(Control<TextBlock>("Status").Text.Contains("已取消或失效"),"cancel-terminal-notice");
   ComputeCancelProbe.Record("canceled-request-settled",new{draftsPreserved=true});
   Control<TextBox>("DateSeconds").Text="2";apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
   limit.Restart();while((bool)Field("busy")!&&limit.Elapsed<TimeSpan.FromSeconds(45))await Task.Delay(10);
   Check(!(bool)Field("busy")!&&(sharedEntry?docs.Select((d,i)=>d.Value("XMP-exif:DateTimeDigitized")=="2024:01:01 00:00:00."+i.ToString("D9")+"-00:00").All(x=>x):docs[0].Value(docs[0].MainDateTag)=="2025:02:02 01:01:02.123456789-00:00"&&docs.All(d=>d.Draft.ContainsKey(d.MainDateTag))),"new-direct-request-after-cancel-correct");
   typeof(MainWindow).GetMethod("UndoLastApply",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[window,new RoutedEventArgs()]);
   Check(Drafts()==draftSnapshot,"new-complete-undo-restores-earlier-drafts");
   foreach(var doc in docs)await doc.EnsureUnchangedAsync();Check(true,"all-3000-synthetic-sources-unchanged");
   ComputeCancelProbe.Record("wpf_complete",new{input="marker-triggered production cancel Button.Click; not mouse/user input",existingDraftFiles=docs.Count(d=>d.Draft.Count>0)});
   foreach(var doc in docs)doc.ClearDraft();window.Close();app.Shutdown(0);
  }catch(Exception error){Fail(error);}};
  if(automatic){ComputeCancelProbe.AfterStarted=()=>{ComputeCancelProbe.AfterStarted=null;window.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Send,new Action(()=>{
   stageConfirmed=ComputeCancelProbe.BeforeCancel();ComputeCancelProbe.Record("actual_wpf_cancel_button_event",new{input="real-marker-triggered current production Button.Click; not mouse/user input"});cancel.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
  }));};apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));}
  File.WriteAllText(Path.Combine(ComputeCancelProbe.Folder,"ready.json"),JsonSerializer.Serialize(new{window=window.Title,count=docs.Length,mode=sharedEntry?"shared CSV date validation":"six-component offset direct application",sourceHash=first.SourceHash,existingDraftFiles=2}));
  ComputeCancelProbe.Record("wpf_ready",new{count=docs.Length});
 }
 static Button? FindButton(DependencyObject node,string text){if(node is Button button&&button.Content?.ToString()==text)return button;foreach(var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())if(FindButton(child,text)is{} found)return found;return null;}
 static async void Fail(Exception error){
  File.WriteAllText(Path.Combine(ComputeCancelProbe.Folder,"failure.txt"),error.ToString());ComputeCancelProbe.Record("failed",new{error=error.Message});
  var limit=Stopwatch.StartNew();while((bool)Field("busy")!&&limit.Elapsed<TimeSpan.FromSeconds(45))await Task.Delay(10);
  app.Shutdown(1);
 }
 [STAThread]static int Main(string[] args)
 {
  sharedEntry=args.Contains("--r01b-csv");ComputeCancelProbe.Folder=Path.GetFullPath(args[0]);Directory.CreateDirectory(ComputeCancelProbe.Folder);
  if(args.Contains("--adapter")){try{Adapter().GetAwaiter().GetResult();return 0;}catch(Exception error){File.WriteAllText(Path.Combine(ComputeCancelProbe.Folder,"failure.txt"),error.ToString());return 1;}}
  System.Windows.Media.RenderOptions.ProcessRenderMode=System.Windows.Interop.RenderMode.SoftwareOnly;
  app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};window=new MainWindow{Title="PhotoTrail 实宿主计算取消 · 独立验证"};
  window.Loaded+=async(_,_)=>{try{await PrepareWindow(args.Contains("--auto"));}catch(Exception error){Fail(error);}};
  return app.Run(window);
 }
}
