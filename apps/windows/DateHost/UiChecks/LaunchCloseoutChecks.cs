using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task LaunchCloseoutChecks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;
  var hashes=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  string? CounterBytes()=>File.Exists(RenameCounters.DefaultPath)?Convert.ToHexString(File.ReadAllBytes(RenameCounters.DefaultPath)):null;
  var counters=CounterBytes();
  foreach(var action in RenameTransform.Actions.Where(p=>p.Value is >=72 and <=77))foreach(bool enabled in new[]{true,false})
  {
   var rules=new[]{new RenameRule("action","photo"){Action="set"},new RenameRule("action","<Artist>"){Action=action.Key,Enabled=enabled}};
   var scheme=new RenameScheme(Guid.NewGuid(),"Deferred mixed scheme",RenamePlan.EncodeEditorRules(rules),new(),"");
   M3Call("SetSchemeEditor",scheme);await Responsive();
   Check(Control<TextBox>("RenameRules").Text==scheme.Rules,"launch-whole-old-editor-preserved-"+action.Key+enabled);
   Check(Control<TextBlock>("RenameSchemeStatus").Text.Contains("首发"),"launch-old-scheme-visible-unavailable-"+action.Key+enabled);
   Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null,"launch-freeze-blocked-"+action.Key+enabled);
   var doc=Doc(photos.Items[0]);var plan=await RenamePlan.BuildTargetsAsync([(doc.FilePath,"forbidden.jpg")]);
   M3Set("frozenRenamePlan",plan);Action("ExecuteRename");await Responsive();
   Check(Field("frozenRenamePlan")is null&&CounterBytes()==counters&&!File.Exists(Path.Combine(Path.GetDirectoryName(doc.FilePath)!,"forbidden.jpg")),"launch-UI-execute-rechecks-editor-before-any-write-"+action.Key+enabled);
  }
  M3Call("SetSchemeEditor",new RenameScheme(Guid.NewGuid(),"Photo scope",RenamePlan.EncodeEditorRules([new("action","<Artist>"){Action="template-set"}]),new(),""));await Responsive();
  // Inspect actual picker controls, using a dispatcher callback to close only this owned test modal.
  bool inspected=false;
  _=window.Dispatcher.BeginInvoke(async()=>{
   await Task.Delay(100);var picker=Application.Current.Windows.Cast<Window>().Single(w=>w!=window);
   var ids=M2Children(picker).OfType<Button>().Select(b=>System.Windows.Automation.AutomationProperties.GetAutomationId(b)).ToArray();
   Check(!ids.Any(id=>id.StartsWith("M3AddAction.music-",StringComparison.Ordinal)),"launch-normal-action-picker-excludes-all-six-music-actions");
   Check(ids.Contains("M3AddAction.template-set"),"launch-normal-photo-template-action-retained");inspected=true;picker.Close();
  });
  M3Call("M3AddAction");Check(inspected,"launch-picker-inspection-completed");
  foreach(var x in hashes)Check(await PhotoDocument.HashAsync(x.Key)==x.Value,"launch-rejections-original-SHA-unchanged");
  Check(CounterBytes()==counters,"launch-rejections-counter-bytes-unchanged");
  M3Set("frozenRenamePlan",null);M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
  SaveResult("launch-closeout.json",new{kind="production DLL and WPF controls; not native keyboard"});
 }
 static void LaunchHistoryProfile(string output)
 {
  Directory.CreateDirectory(output);var root=Environment.GetEnvironmentVariable("PHOTOTRAIL_HISTORY_FIXTURE")??throw new Exception("Select existing completed history");
  Environment.SetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY",root);
  var records=InplaceHistory.ReadAll();if(records.Any(InplaceHistory.Pending))throw new Exception("Only completed isolated history permitted");
  var before=Directory.GetFiles(root,"inplace-*.jsonl").ToDictionary(p=>p,p=>System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(p)));
  var samples=new List<double>();for(int i=0;i<3;i++){var clock=System.Diagnostics.Stopwatch.StartNew();InplaceHistory.RequireClear([records[0].Target]);samples.Add(clock.Elapsed.TotalMilliseconds);}
  if(before.Any(x=>!System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(x.Key)).SequenceEqual(x.Value)))throw new Exception("Read-only profile modified history");
  File.WriteAllText(Path.Combine(output,"history-profile.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),count=records.Length,samplesMs=samples,historyBytesUnchanged=true,scope="three fresh full RequireClear scans on completed history, warm filesystem; no median or SLA"},new JsonSerializerOptions{WriteIndented=true}));
 }
 static async Task LaunchMakeLegacyMusic()
 {
  await ImportDone();var doc=Doc(Control<ListBox>("Photos").Items[0]);string hash=await PhotoDocument.HashAsync(doc.FilePath);
  var rule=new RenameRule("action","old-music"){Action="music-set"};var target=RenamePlan.Apply(Path.GetFileName(doc.FilePath),[rule],0);
  var path=Path.Combine(folder,"legacy-photo.jpg");File.Copy(doc.FilePath,path);
  var plan=await RenamePlan.BuildTargetsAsync([(path,target)]);var result=await RenameExecutor.ExecuteAsync(plan,Path.Combine(folder,"legacy-music-journal"));
  Check(result.Complete,"legacy-music-created-by-previous-DLL");File.WriteAllText(Path.Combine(folder,"legacy-music.json"),JsonSerializer.Serialize(new{original=path,hash,journal=result.Journal,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location)))}));
 }
 static async Task LaunchRestoreLegacyMusic()
 {
  await ImportDone();using var data=JsonDocument.Parse(File.ReadAllText(Path.Combine(folder,"legacy-music.json")));var root=data.RootElement;
  var result=await RenameExecutor.RestoreAsync(root.GetProperty("journal").GetString()!,Path.Combine(folder,"legacy-restored"));
  Check(result.Complete&&await PhotoDocument.HashAsync(root.GetProperty("original").GetString()!)==root.GetProperty("hash").GetString(),"launch-current-DLL-restores-real-previous-music-journal-original-SHA");
  SaveResult("launch-legacy-restore.json",new{kind="new production DLL restores actual previous production music execution journal; not new music execution"});
 }
}
