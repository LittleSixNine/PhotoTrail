using System.Collections;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

// Real production window/controls/events on its Dispatcher, synthetic XMP only; no UI logic substitutes.
static class Program
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
 static async Task Run()
 {
  for(int i=0;i<1200&&(bool)Field("busy")!;i++)await Task.Delay(25);
  var list=Control<ListBox>("Photos");Check(list.Items.Count==4,"real-import-four-xmp");
  list.SelectAll();var rows=list.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();
  // Select the real dates tab, keeping the application's own selection/import/session logic.
  var tabs=Control<TabControl>("WorkspaceTabs");tabs.SelectedIndex=0;
  var dateTab=DatesTab(window)!;((TabControl)LogicalTreeHelper.GetParent(dateTab)).SelectedItem=dateTab;
  foreach(int mode in new[]{0,1,2,3,4}) {
   Control<ComboBox>("DateMode").SelectedIndex=mode;
   Control<TextBox>("DateDays").Text="1";
   Control<TextBox>("DateStart").Text="2024:01:01 00:00:00.123456789Z";
   Control<TextBox>("DateEnd").Text="2024:01:01 00:00:05.123456789Z";
   Control<TextBox>("DateReplaceYear").Text="2025";Control<TextBox>("DateReplaceDay").Text="28";
   Control<TextBox>("DateFilenameTemplate").Text="$1:$2:$3 15:$5:$6";
   Action("PreviewDates");await Idle();Check(Control<Button>("DatePlanApplyButton").IsEnabled,"preview-mode-"+mode);
   Check(docs.All(d=>d.Draft.Count==0),"preview-no-draft-"+mode);
   Action("ApplyDates");await Idle();Check(docs.All(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal")),"real-apply-mode-"+mode);
   var copies=Path.Combine(folder,"ui-mode-"+mode);Directory.CreateDirectory(copies);Control<TextBox>("OutputFolder").Text=copies;
   Action("SaveCopies");for(int i=0;i<1200&&(bool)Field("busy")!;i++)await Task.Delay(25);
   Check(Status.Contains("副本成功 4，失败 0"),"real-save-mode-"+mode);
   var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
   foreach(var doc in docs){var read=await PhotoDocument.LoadAsync(client,Path.Combine(copies,Path.GetFileName(doc.FilePath)));Check(read.Value("XMP-exif:DateTimeOriginal")==doc.Value("XMP-exif:DateTimeOriginal")&&await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"real-copy-read-source-"+mode);}
   Action("UndoDraft");
  }
  Control<ComboBox>("DateMode").SelectedIndex=0;
  Action("PreviewDates");Control<TextBox>("DateDays").Text="2";await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&docs.All(d=>d.Draft.Count==0),"parameter-change-during-preview");
  Action("PreviewDates");Control<ComboBox>("DateMode").SelectedIndex=2;await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"mode-change-during-preview");Control<ComboBox>("DateMode").SelectedIndex=0;
  Action("PreviewDates");list.SelectedItems.Clear();list.SelectedItems.Add(rows[0]);await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"selection-change-during-preview");list.SelectAll();
  Action("PreviewDates");Control<CheckBox>("DateApply").IsChecked=true;await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"target-field-check-during-preview");Control<CheckBox>("DateApply").IsChecked=false;
  Action("PreviewDates");docs[^1].SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","changed"}});await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"other-entry-draft-during-preview");Action("UndoDraft");
  Action("PreviewDates");await Idle();Control<TextBox>("DateHours").Text="1";Action("ApplyDates");Check(docs.All(d=>d.Draft.Count==0),"changed-before-apply-no-draft");
  Action("PreviewDates");Control<TextBox>("DateDays").Text="3";Action("PreviewDates");await Idle();await Task.Delay(100);
  Check(Control<Button>("DatePlanApplyButton").IsEnabled&&Control<TextBlock>("DatePlanPreview").Text.Contains("2024:03:03"),"continuous-preview-old-cannot-overwrite");
  Action("CancelRead");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&docs.All(d=>d.Draft.Count==0),"real-cancel-no-draft");
  Control<ComboBox>("DateMode").SelectedIndex=1;Control<TextBox>("DateStart").Text="1582:10:10 00:00:00";Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"gap-rejected-in-real-window");
  Control<TextBox>("DateStart").Text="2024:01:01 00:00:00\n";Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled,"LF-rejected-in-real-window");
  Control<TextBox>("DateStart").Text="1500:02:29 00:00:00";Action("PreviewDates");await Idle();Action("ApplyDates");await Idle();Check(docs[0].Value("XMP-exif:DateTimeOriginal")=="1500:02:29 00:00:00","historical-qualified-real-draft");Action("UndoDraft");
  Control<ComboBox>("DateMode").SelectedIndex=0;Action("PreviewDates");await Idle();
  var original=File.ReadAllBytes(docs[^1].FilePath);File.AppendAllText(docs[^1].FilePath," ");Action("ApplyDates");await Idle();
  Check(docs.All(d=>d.Draft.Count==0)&&Status.Contains("未应用"),"disk-source-change-whole-batch-no-draft");File.WriteAllBytes(docs[^1].FilePath,original);
  string host=Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe");File.Move(host,host+".hold");
  try{
   Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("不可用"),"real-missing-host-fail-closed");
   // Explicit check-only path, never a production host override.
   string checker=Environment.GetEnvironmentVariable("PHOTOTRAIL_DATE_CHECKER")??throw new Exception("Set PHOTOTRAIL_DATE_CHECKER to the checks output");
   foreach(string name in new[]{"Caller.dll","Caller.deps.json","Caller.runtimeconfig.json"})File.Copy(Path.Combine(checker,name),Path.Combine(Path.GetDirectoryName(host)!,name),true);
   File.Copy(Path.Combine(checker,"Caller.exe"),host);
   Action("PreviewDates");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("协议"),"real-malformed-response-no-draft");
   string marker=Path.Combine(Path.GetDirectoryName(host)!,"fixture-hang");File.WriteAllText(marker,"");Action("PreviewDates");await Idle();File.Delete(marker);
   Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("超时")&&docs.All(d=>d.Draft.Count==0),"real-timeout-no-draft");
  }finally{if(File.Exists(host))File.Delete(host);File.Move(host+".hold",host);}
  // 100/3000 real selected rows, constructed from identical synthetic files and the verified imported baseline.
  var collection=(IList)Field("photos")!;var rowType=rows[0].GetType();var ctor=typeof(PhotoDocument).GetConstructors(BindingFlags.NonPublic|BindingFlags.Instance).Single();
  foreach(int count in new[]{1,100,3000}) {
   list.SelectedItems.Clear();collection.Clear();
   for(int i=0;i<count;i++){
    string path=Path.Combine(folder,$"stress-{i}.xmp");File.Copy(docs[0].FilePath,path,true);
    var doc=(PhotoDocument)ctor.Invoke([path,null,docs[0].Embedded,null,docs[0].SourceHash,null]);
    collection.Add(Activator.CreateInstance(rowType,doc)!);
   }
   list.SelectAll();Control<ComboBox>("DateMode").SelectedIndex=1;Control<TextBox>("DateStart").Text="2024:01:01 00:00:00.123456789-00:00";Control<TextBox>("DateStep").Text="1";
   Action("PreviewDates");await Idle();Check(Control<Button>("DatePlanApplyButton").IsEnabled,"real-global-preview-"+count);
   Action("ApplyDates");await Idle();Check(Doc(collection[^1]!).Value("XMP-exif:DateTimeOriginal").EndsWith(".123456789-00:00"),"real-global-apply-"+count);Action("UndoDraft");
   if(count==3000){Action("PreviewDates");await Task.Delay(100);Action("CancelRead");await Idle();Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&collection.Cast<object>().All(r=>Doc(r).Draft.Count==0),"real-3000-cancel");}
  }
  Action("PreviewDates");window.Close();Check(window.IsVisible,"closing-awaits-request-cleanup");await Idle();
  File.WriteAllText(Path.Combine(folder,"ui-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));
  Console.WriteLine("WPF_CHECKS="+evidence.Count);window.Close();
 }
 [STAThread]static void Main(string[] args)
 {
  folder=Path.GetFullPath(args[0]);Directory.CreateDirectory(folder);
  var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown};
  window=new MainWindow{Title="PhotoTrail 日期页 · 独立自动交互验证"};
  window.Loaded+=async(_,_)=>{try{await Task.Delay(300);await Run();app.Shutdown(0);}catch(Exception error){File.WriteAllText(Path.Combine(folder,"ui-failure.txt"),error.ToString());Console.Error.WriteLine(error);app.Shutdown(1);}};
  app.Run(window);
 }
}
