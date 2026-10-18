using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

static partial class Program
{
 static bool checkerAbort,checkerSnapshotBusy;
 static string? checkerSnapshotPath;
 static void WaitCheckerPreparation(){
  if(!(bool)Field("busy")!)return;var clock=Stopwatch.StartNew();var frame=new DispatcherFrame();var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(20)};
  timer.Tick+=(_,_)=>{if(!(bool)Field("busy")!||clock.Elapsed>TimeSpan.FromMinutes(5))frame.Continue=false;};timer.Start();try{Dispatcher.PushFrame(frame);}finally{timer.Stop();}
  if((bool)Field("busy")!)throw new TimeoutException("Save preparation did not settle; preserve input and cancel at the existing safe boundary.");
 }
 static async Task<bool> RetainCheckerInput(string reason){
  var rows=Control<ListBox>("Photos").Items.Cast<object>().ToArray();string root=Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder))+Path.DirectorySeparatorChar;
  if(rows.Any(r=>!Path.GetFullPath(Doc(r).FilePath).StartsWith(root,StringComparison.OrdinalIgnoreCase)))return false;
  var docs=rows.Select(Doc).ToArray();var snapshot=docs.Select(d=>new{file=d.FilePath,sidecar=d.SidecarPath,sourceHash=d.SourceHash,sidecarHash=d.SidecarHash,draft=d.Draft,context=d.Context,newSidecar=d.NewSidecarEditing,zone=d.SessionZoneId}).ToArray();
  var elements=M2Children(window).Concat(window.OwnedWindows.Cast<Window>().SelectMany(M2Children)).ToArray();
  var controls=elements.OfType<TextBox>().Select(t=>new{name=t.Name,automation=AutomationProperties.GetName(t),text=t.Text}).ToArray();
  var choices=elements.OfType<ComboBox>().Select(t=>new{name=t.Name,index=t.SelectedIndex,text=t.Text}).ToArray();
  var toggles=elements.OfType<System.Windows.Controls.Primitives.ToggleButton>().Select(t=>new{name=t.Name,automation=AutomationProperties.GetAutomationId(t),value=t.IsChecked}).ToArray();
  string text=JsonSerializer.Serialize(new{reason,buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),photos=snapshot,controls,choices,toggles,selection=Control<ListBox>("Photos").SelectedItems.Cast<object>().Select(r=>Doc(r).FilePath),workspace=Control<TabControl>("WorkspaceTabs").SelectedIndex,ui=Field("ui")},new JsonSerializerOptions{WriteIndented=true});
  string path=Path.Combine(folder,"retained-input-"+Guid.NewGuid().ToString("N")+".local.json");File.WriteAllText(path,text);
  using var read=JsonDocument.Parse(File.ReadAllText(path));var photos=read.RootElement.GetProperty("photos").EnumerateArray().ToArray();if(photos.Length!=docs.Length)return false;
  for(int i=0;i<docs.Length;i++){
   var draft=photos[i].GetProperty("draft").Deserialize<Dictionary<string,string>>()!;var context=photos[i].GetProperty("context").Deserialize<DraftContext>()!;
   if(!draft.OrderBy(v=>v.Key).SequenceEqual(docs[i].Draft.OrderBy(v=>v.Key))||context.ClearLocation!=docs[i].ClearLocationRequested||!context.MapFields.SequenceEqual(docs[i].Context.MapFields)||photos[i].GetProperty("file").GetString()!=docs[i].FilePath||photos[i].GetProperty("sourceHash").GetString()!=docs[i].SourceHash)return false;
  }
  if(!JsonElement.DeepEquals(read.RootElement.GetProperty("controls"),JsonSerializer.SerializeToElement(controls))||!JsonElement.DeepEquals(read.RootElement.GetProperty("choices"),JsonSerializer.SerializeToElement(choices))||!JsonElement.DeepEquals(read.RootElement.GetProperty("toggles"),JsonSerializer.SerializeToElement(toggles)))return false;
  checkerSnapshotPath=path;return true;
 }
 static void StartCheckerModalGuard(){
  if(Environment.GetEnvironmentVariable("PHOTOTRAIL_EVIDENCE_STEPS")is not null)return;
  Window? observed=null;var waiting=Stopwatch.StartNew();var timer=new DispatcherTimer{Interval=TimeSpan.FromSeconds(1)};
  timer.Tick+=async(_,_)=>{
   if(checkerSnapshotBusy||checkerAbort)return;
   var dialog=window.OwnedWindows.Cast<Window>().FirstOrDefault(w=>w.IsVisible&&M2Children(w).OfType<Button>().Any(b=>AutomationProperties.GetAutomationId(b)=="M9ScopeCancel"));
   if(dialog is null){observed=null;return;}if(dialog!=observed){observed=dialog;waiting.Restart();return;}if(waiting.Elapsed<TimeSpan.FromSeconds(8))return;
   checkerSnapshotBusy=true;
   try{if(!await RetainCheckerInput("unexpected-save-scope-modal"))return;checkerAbort=true;var cancel=M2Children(dialog).OfType<Button>().Single(b=>AutomationProperties.GetAutomationId(b)=="M9ScopeCancel");cancel.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));}
   catch(Exception e){File.WriteAllText(Path.Combine(folder,"modal-retained.local.txt"),e.ToString());}
   finally{checkerSnapshotBusy=false;}
  };timer.Start();window.Closed+=(_,_)=>timer.Stop();
 }
 static async Task LifecycleModalChecks(){
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectedIndex=0;var doc=Doc(photos.SelectedItem);doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","recoverable 中文"},{"ExifIFD:UserComment",""}});doc.StageLocationClear();M3Call("RefreshSelection");
  M3Call("SaveUi",((UiPreference)Field("ui")!)with{SkipSaveScopePrompt=false,SaveCurrentPage=false});
  Action("SaveCopies");throw new Exception("Expected modal guard to abort before any continuation.");
 }
 static async Task SnapshotReplayChecks(string path){
  await ImportDone();using var read=JsonDocument.Parse(File.ReadAllText(path));var photos=read.RootElement.GetProperty("photos").EnumerateArray().ToArray();var actual=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).ToArray();
  foreach(var item in photos){var doc=actual.Single(d=>d.FilePath==item.GetProperty("file").GetString());if(doc.SourceHash!=item.GetProperty("sourceHash").GetString()||doc.SidecarHash!=item.GetProperty("sidecarHash").GetString())throw new IOException("Snapshot source binding changed.");var draft=item.GetProperty("draft").Deserialize<Dictionary<string,string>>()!;doc.SelectSidecarEditing(item.GetProperty("newSidecar").GetBoolean());await doc.SetDraftValidatedAsync(draft,await VerifiedMetadataDates.CreateAsync(draft),doc.DraftRevision,default);doc.RestoreContext(item.GetProperty("context").Deserialize<DraftContext>()!);doc.SetSessionZone(item.GetProperty("zone").GetString()!);Check(doc.Draft.OrderBy(p=>p.Key).SequenceEqual(draft.OrderBy(p=>p.Key))&&doc.ClearLocationRequested==item.GetProperty("context").GetProperty("ClearLocation").GetBoolean(),"second-process-snapshot-restores-empty-values-clear-intent-and-source-binding");doc.ClearDraft();}
  File.WriteAllText(Path.Combine(folder,"snapshot-replay-results.json"),JsonSerializer.Serialize(new{buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),checks=evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
