using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

static partial class Program
{
 static object? M3Call(string name,params object?[] args)=>typeof(MainWindow).GetMethod(name,BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,args);
 static void M3Set(string name,object? value)=>typeof(MainWindow).GetField(name,BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,value);
 static async Task M3Checks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;await Responsive();
  Check(((WrapPanel)Field("m3Narrow")!).Visibility==Visibility.Collapsed,"M3-default-width-shows-two-real-panes");
  string Encode(params RenameRule[] rules)=>(string)typeof(RenamePlan).GetMethod("EncodeEditorRules",BindingFlags.NonPublic|BindingFlags.Static)!.Invoke(null,[rules])!;
  void Refuse(string text,string name){bool refused=false;try{RenamePlan.ParseRules(text);}catch(ArgumentException){refused=true;}Check(refused,name);}
  var old=RenamePlan.ParseRules("prefix|old_\nreplace|a|b\nsequence|1|2|3");var encoded=Encode(old.ToArray());var again=RenamePlan.ParseRules(encoded);Check(RenamePlan.Apply("a.jpg",old,0)==RenamePlan.Apply("a.jpg",again,0),"M3-legacy-typed-roundtrip-exact-semantics");
  var disabled=Encode(new RenameRule("prefix","bad_"){Enabled=false},new RenameRule("suffix","_yes"));Check(RenamePlan.Apply("a.jpg",RenamePlan.ParseRules(disabled),0)=="a_yes.jpg","M3-legacy-disabled-preserved");
  Refuse("{\"Kind\":\"prefix\",\"Unknown\":1}","M3-legacy-unknown-property-refused");Refuse("{\"Kind\":\"prefix\",\"Kind\":\"suffix\"}","M3-legacy-duplicate-property-refused");Refuse("{\"Kind\":\"sequence\",\"Step\":0,\"Enabled\":false}","M3-disabled-invalid-parameter-refused");
  var many=Enumerable.Range(0,64).Select(i=>new RenameRule("action","x"){Action="add-begin"}).ToArray();var compact=Encode(many);Check(compact.Length<32768&&RenamePlan.ParseRules(compact).Count==64,"M3-64-cards-fit-existing-bounded-format");
  var filter=new RenameRule("action"){Action="filter-following",Filters=[new("name","starts","a")]};var suffix=new RenameRule("action","_hit"){Action="add-end"};var chain=RenamePlan.ParseRules(Encode(filter,suffix));Check(RenamePlan.Apply("a.jpg",chain,0)=="a_hit.jpg"&&RenamePlan.Apply("b.jpg",chain,0)=="b.jpg","M3-filter-controls-following-actions");
  var reset=filter with{Filters=[new("fileExtension","equals","jpg")]};Check(RenamePlan.Apply("b.jpg",RenamePlan.ParseRules(Encode(filter,suffix,reset,suffix)),0)=="b_hit.jpg","M3-later-filter-resets-inclusion");
  var insensitive=filter with{CaseSensitive=false,Filters=[new("name","starts","É")]};Check(RenamePlan.Apply("é.jpg",RenamePlan.ParseRules(Encode(insensitive,suffix)),0)=="é_hit.jpg","M3-filter-NFC-casefold");
  var any=filter with{FilterAny=true,Filters=[new("name","starts","a"),new("fileExtension","equals","png")]};Check(RenamePlan.Apply("b.png",RenamePlan.ParseRules(Encode(any,suffix)),0)=="b_hit.png","M3-filter-any-condition");
  Refuse(Encode(filter with{Filters=[]}),"M3-empty-filter-refused");Refuse(Encode(filter with{Filters=[new("unknown","equals","")]}),"M3-unknown-filter-field-refused");
  Input("RenameRules","prefix|card_\nsequence|1|1|3");await Responsive();Check(Control<Grid>("M3RenameWorkspace").Visibility==Visibility.Visible&&Control<Grid>("M3RenameParking").Visibility==Visibility.Collapsed,"M3-real-card-workspace-replaces-legacy-panel");
  var cards=(IList)Field("m3Cards")!;Check(cards.Count==2,"M3-legacy-rules-populate-two-typed-cards");var first=cards[0]!;M3Call("M3MoveCard",first,1);await Responsive();Check(ReferenceEquals(cards[1],first)&&RenamePlan.ParseRules(Control<TextBox>("RenameRules").Text)[0].Kind=="sequence","M3-card-move-updates-real-chain");
  static IEnumerable<DependencyObject> Tree(DependencyObject root){yield return root;for(int i=0;i<System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in Tree(System.Windows.Media.VisualTreeHelper.GetChild(root,i)))yield return child;}
  M3Call("M3EditCard",cards[0]!);window.UpdateLayout();var numeric=Tree(Control<Grid>("M3RenameWorkspace")).OfType<TextBox>().First(t=>System.Windows.Automation.AutomationProperties.GetName(t)=="步长");numeric.Text="invalid";await Responsive();Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null&&numeric.Text=="invalid","M3-invalid-typed-input-retained-and-freeze-refused");bool saveRefused=false;try{M3Call("EditedScheme",Guid.NewGuid(),null);}catch(TargetInvocationException error){saveRefused=error.InnerException is ArgumentException;}Check(saveRefused,"M3-invalid-typed-input-not-silently-saved");numeric.Text="2";await Responsive();Check(RenamePlan.ParseRules(Control<TextBox>("RenameRules").Text)[0].Step==2,"M3-repaired-parameter-reaches-existing-model");
  var hashes=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count>=photos.SelectedItems.Count,"M3-new-preview-reuses-real-pair-groups");Action("FreezeRename");await RenameWait();var plan=Field("frozenRenamePlan") as RenamePlan;Check(plan is not null,"M3-cards-freeze-real-source-protected-plan");var same=plan;Control<ComboBox>("RenameViewOrder").SelectedIndex=2;Check(ReferenceEquals(same,Field("frozenRenamePlan")),"M3-view-sort-does-not-change-execution-set");
  foreach(var hash in hashes)Check(await PhotoDocument.HashAsync(hash.Key)==hash.Value,"M3-preview-no-file-write");
  Exception? searchError=null;var pickerDispatch=window.Dispatcher.BeginInvoke(()=>{Window? picker=null;try{picker=Application.Current.Windows.Cast<Window>().Single(w=>M2Children(w).OfType<TextBox>().Any(t=>System.Windows.Automation.AutomationProperties.GetAutomationId(t)=="M3ActionSearch"));var search=M2Children(picker).OfType<TextBox>().Single(t=>System.Windows.Automation.AutomationProperties.GetAutomationId(t)=="M3ActionSearch");search.Text=(string)window.FindResource("M3Action28");var matches=M2Children(picker).OfType<Button>().Where(b=>System.Windows.Automation.AutomationProperties.GetAutomationId(b).StartsWith("M3AddAction.",StringComparison.Ordinal)).ToArray();Check(matches.Length==1&&System.Windows.Automation.AutomationProperties.GetAutomationId(matches[0])=="M3AddAction.lower","M3-action-search-filters-real-catalog");matches[0].RaiseEvent(new RoutedEventArgs(Button.ClickEvent));}catch(Exception error){searchError=error;picker?.Close();}});M3Call("M3AddAction");await pickerDispatch;if(searchError is not null)throw searchError;Check(cards.Count==3&&RenamePlan.ParseRules(Control<TextBox>("RenameRules").Text)[2].Action=="lower"&&Field("frozenRenamePlan")is null,"M3-add-search-result-wires-real-action-and-invalidates-freeze");
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m3-ui-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("M3_WPF_CHECKS="+evidence.Count);
 }
 static async Task M3Performance()
 {
  for(int i=0;i<2400&&((bool)Field("importRunning")!||(bool)Field("busy")!);i++)await Task.Delay(25);
  var photos=Control<ListBox>("Photos");if(photos.Items.Count!=100)throw new InvalidOperationException("M3 performance requires exactly 100 synthetic photos.");
  var all=photos.Items.Cast<object>().ToArray();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;
  Input("RenameRules","前缀|M3_\n序号|1|1|3");await Responsive();
  var results=new List<object>();var ticks=new List<long>();var clock=Stopwatch.StartNew();
  var pulse=new DispatcherTimer(DispatcherPriority.Input){Interval=TimeSpan.FromMilliseconds(20)};pulse.Tick+=(_,_)=>ticks.Add(clock.ElapsedTicks);pulse.Start();
  async Task<double> Time(Func<Task> action){var watch=Stopwatch.StartNew();await action();return watch.Elapsed.TotalMilliseconds;}
  void Save()=>File.WriteAllText(Path.Combine(folder,"m3-performance.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),samples=results},new JsonSerializerOptions{WriteIndented=true}));
  foreach(int count in new[]{1,20,100})
  {
   M3Set("fillingEditor",true);try{photos.SelectedItems.Clear();foreach(var row in all.Take(count))photos.SelectedItems.Add(row);}finally{M3Set("fillingEditor",false);}
   await Responsive();
   foreach(string repeat in new[]{"first","repeat"})
   {
    ticks.Clear();long start=clock.ElapsedTicks;long requests=ExifToolClient.RequestCount;
    double read=await Time(async()=>await (Task)M3Call("ReadRenameGroupsAsync",CancellationToken.None)!);
    double dates=await Time(async()=>await (Task)M3Call("PrepareRenameDatesAsync",CancellationToken.None)!);
    var groups=M3Call("IncludedRenameGroups")!;var rules=(IReadOnlyList<RenameRule>)M3Call("ReadRenameRules")!;
    object? computed=null;double calculate=await Time(()=>{computed=M3Call("ComputeRenameTargets",groups,rules);return Task.CompletedTask;});
    var files=(RenameFile[])computed!.GetType().GetField("Item1")!.GetValue(computed)!;
    RenamePlan? frozen=null;double freeze=await Time(async()=>frozen=await RenamePlan.BuildTargetsAsync(files.Select(f=>(f.Source,f.NewName)),CancellationToken.None,includeSidecars:false));
    double bind=await Time(async()=>{Control<DataGrid>("RenamePreview").ItemsSource=frozen!.Files;await window.Dispatcher.InvokeAsync(()=>window.UpdateLayout(),DispatcherPriority.Render);await Responsive();});
    var sequence=new[]{start}.Concat(ticks).Append(clock.ElapsedTicks).ToArray();double maxGap=sequence.Zip(sequence.Skip(1),(a,b)=>(b-a)*1000d/Stopwatch.Frequency).DefaultIfEmpty(0).Max();
    results.Add(new{count,repeat,readMs=read,dateMs=dates,calculateMs=calculate,freezeValidationMs=freeze,bindingLayoutMs=bind,toolRequests=ExifToolClient.RequestCount-requests,heartbeatCount=ticks.Count,maxHeartbeatGapMs=maxGap});Save();
   }
  }
  photos.SelectAll();await Responsive();using var cancel=new CancellationTokenSource();var task=(Task)M3Call("ReadRenameGroupsAsync",cancel.Token)!;await Task.Delay(120);var cancellation=Stopwatch.StartNew();cancel.Cancel();bool cancelled=false;try{await task;}catch(OperationCanceledException){cancelled=true;}
  results.Add(new{phase="read-cancellation",cancelled,responseMs=cancellation.Elapsed.TotalMilliseconds});Save();pulse.Stop();
  if(!cancelled)throw new InvalidOperationException("Expected cancellable read.");
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
 }
}
