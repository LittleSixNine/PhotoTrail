using System.Collections;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task M6FilterChecks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;Input("RenameRules","prefix|M6_");Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count==3,"filters-empty-three-groups");
  Exception? focusError=null;var focusVisit=window.Dispatcher.BeginInvoke(()=>{Window? dialog=null;try{dialog=window.OwnedWindows.Cast<Window>().Single(w=>M2Children(w).Contains(Control<Grid>("M6RenameFilters")));dialog.Activate();var from=Control<TextBox>("RenameDateFrom");var to=Control<TextBox>("RenameDateTo");Check(from.Focus()&&from.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Next))&&to.IsKeyboardFocusWithin,"filters-real-modal-forward-focus-date-from-to");Check(to.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.Previous))&&from.IsKeyboardFocusWithin,"filters-real-modal-reverse-focus-date-to-from");from.Text="2024-01-01";to.Text="2025-01-01";dialog.Close();}catch(Exception e){focusError=e;dialog?.Close();}});M3Call("M3InputSettings");await focusVisit;if(focusError is not null)throw focusError;Check(Control<TextBox>("RenameDateFrom").Text=="2024-01-01"&&Control<TextBox>("RenameDateTo").Text=="2025-01-01","filters-closing-borrowed-dialog-retains-unapplied-date-input");
  Input("RenameDateFrom","2024-01-01");Input("RenameDateTo","2025-01-01");Input("RenameInputType","jpg");Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count==2,"filters-distinct-date-bounds-and-type-real-two-dated-groups");
  Input("RenameInputQuery","01-Synthetic");Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count==1,"filters-name-and-date-intersection-one-group");
  Input("RenameDateFrom","2025-01-01");Input("RenameDateTo","2024-01-01");Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null&&Control<TextBox>("RenameDateFrom").Text=="2025-01-01"&&Control<TextBox>("RenameDateTo").Text=="2024-01-01","filters-reversed-range-refused-input-retained");
  Input("RenameDateFrom","invalid-date");Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null&&Control<TextBox>("RenameDateFrom").Text=="invalid-date","filters-invalid-range-retained-no-freeze");
  var closeVisit=window.Dispatcher.BeginInvoke(()=>window.OwnedWindows.Cast<Window>().Single(w=>M2Children(w).Contains(Control<Grid>("M6RenameFilters"))).Close());M3Call("M3InputSettings");await closeVisit;Check(Control<TextBox>("RenameDateFrom").Text=="invalid-date"&&Field("frozenRenamePlan")is null,"filters-close-invalid-input-retains-value-and-refused-freeze");
  Input("RenameDateFrom","");Input("RenameDateTo","");Input("RenameInputType","");Input("RenameInputQuery","");Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count==3,"filters-cleared-range-restores-three-groups");
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m6-filter-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
 static async Task M6InteropChecks()
 {
  await ImportDone();var hashes=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  Input("RenameRules","prefix|unsaved-closeout_");var editing=Control<TextBox>("RenameRules").Text;var library=File.ReadAllBytes(RenameSchemeLibrary.DefaultPath);var counter=Environment.GetEnvironmentVariable("PHOTOTRAIL_RENAME_COUNTERS")!;var counterBefore=File.Exists(counter)?File.ReadAllBytes(counter):null;
  var rules=new[]{new RenameRule("action","M6_"){Action="add-begin",CaseSensitive=true},new RenameRule("action"){Action="number-end",Start=7,Step=2,Padding=4,Counter=0}};
  var scheme=new RenameScheme(Guid.NewGuid(),"M6 mapped synthetic",string.Join("\n",rules.Select(r=>JsonSerializer.Serialize(r))),new("name",true),"M6_sample0011.jpg");
  var export=typeof(MainWindow).Assembly.GetType("PhotoTrail.Windows.MacRenamePreset")!.GetMethod("Export",BindingFlags.Static|BindingFlags.NonPublic)!;
  var mac=(string)export.Invoke(null,[scheme])!;File.WriteAllText(Path.Combine(folder,"windows-to-mac-v1-synthetic.json"),mac);
  var imported=RenameSchemeLibrary.Import(mac,"synthetic Mac schema");File.WriteAllText(Path.Combine(folder,"mac-schema-imported-windows.json"),RenameSchemeLibrary.Export(imported));
  Check(imported.Id!=scheme.Id&&imported.Order==scheme.Order&&JsonSerializer.Serialize(RenamePlan.ParseRules(imported.Rules))==JsonSerializer.Serialize(rules),"interop-mapped-rule-parameters-and-order-preserved-new-identity");
  Check(RenamePlan.Apply("sample.jpg",RenamePlan.ParseRules(imported.Rules),2)=="M6_sample0011.jpg","interop-supported-Mac-v1-schema-real-import-result");
  var json=JsonNode.Parse(mac)!;Check(json["version"]!.GetValue<int>()==1&&json["rules"]!.AsArray().Count==2&&json["settings"]!["pair"]!.GetValue<bool>()&&json["rules"]![1]!["counter"]!.GetValue<int>()==0,"interop-Windows-Mac-export-static-schema-default-pair-no-counter-values");
  foreach(var mutation in new[]{"version","targetExtensions","sourceExtensions"}){var bad=JsonNode.Parse(mac)!;if(mutation=="version")bad[mutation]=2;else bad["settings"]![mutation]="unsupported synthetic override";File.WriteAllText(Path.Combine(folder,"rejected-mac-"+mutation+".json"),bad.ToJsonString());bool refused=false;try{RenameSchemeLibrary.Import(bad.ToJsonString(),"reject");}catch(InvalidDataException){refused=true;}Check(refused,"interop-unsupported-"+mutation+"-whole-preset-refused");Check(Control<TextBox>("RenameRules").Text==editing&&library.SequenceEqual(File.ReadAllBytes(RenameSchemeLibrary.DefaultPath)),"interop-refusal-keeps-unsaved-editor-and-library-"+mutation);}
  Check(counterBefore is null?!File.Exists(counter):counterBefore.SequenceEqual(File.ReadAllBytes(counter)),"interop-never-advances-or-copies-persistent-counter-state");foreach(var h in hashes)Check(await PhotoDocument.HashAsync(h.Key)==h.Value,"interop-import-export-never-writes-photo");
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m6-interop-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),passed=evidence.Count,realMacExecution="NOT_TESTED",evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
 static async Task M6CloseoutChecks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();await Responsive();
  var docs=photos.Items.Cast<object>().Select(Doc).ToArray();var hashes=docs.ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  Check(L10n.Language==(Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_LANGUAGE")??"zh-Hans"),"closeout-runtime-language");
  Control<TabControl>("WorkspaceTabs").SelectedIndex=2;Input("RenameRules","sequence|1|1|3\nsequence-prefix|1|1|3|X_");await Responsive();
  var cards=(IList)Field("m3Cards")!;
  Expander Editor(object c)=>(Expander)c.GetType().GetField("Editor",BindingFlags.Instance|BindingFlags.NonPublic)!.GetValue(c)!;
  TextBox Param(object c,string id)=>M2Children(Editor(c)).OfType<TextBox>().Single(t=>AutomationProperties.GetAutomationId(t)=="M6RenameParam."+id);
  string Errors()=>((TextBlock)Field("m3CardError")!).Text;
  Check(cards.Count==2&&cards.Cast<object>().All(c=>!Editor(c).IsExpanded),"closeout-default-two-cards-compact");
  var first=cards[0]!;var second=cards[1]!;M3Call("M3EditCard",first);Param(first,"Step").Text="bad-step";M3Call("M3EditCard",second);Param(second,"Padding").Text="bad-padding";await Responsive();
  Check(!Editor(first).IsExpanded&&Editor(second).IsExpanded&&Errors().Contains("bad-step")&&Errors().Contains("bad-padding"),"closeout-switch-card-retains-two-errors");
  Check(Errors().Contains(L10n.Format("第 {0} 条 · {1}：{2}",1,(string)window.FindResource("M3Legacysequence"),""))&&Errors().Contains(L10n.Text("步长")),"closeout-error-current-index-name-field");
  Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is null,"closeout-invalid-freeze-refused");
  bool refused=false;try{M3Call("EditedScheme",Guid.NewGuid(),null);}catch(TargetInvocationException e){refused=e.InnerException is ArgumentException;}Check(refused,"closeout-invalid-scheme-save-refused");
  M3Call("M3MoveCard",second,-1);await Responsive();Check(ReferenceEquals(cards[0],second)&&Param(first,"Step").Text=="bad-step"&&Param(second,"Padding").Text=="bad-padding","closeout-reorder-retains-raw-input");
  Check(Errors().IndexOf("bad-padding",StringComparison.Ordinal)<Errors().IndexOf("bad-step",StringComparison.Ordinal),"closeout-error-order-follows-rules");
  Editor(second).IsExpanded=false;M3Call("M3LocateProblem");Check(Editor(second).IsExpanded&&!Editor(first).IsExpanded,"closeout-locator-expands-first-collapsed-error");
  Param(second,"Padding").Text="4";await Responsive();Check(!Errors().Contains("bad-padding")&&Errors().Contains("bad-step"),"closeout-repair-one-keeps-other-error");
  M3Call("M3LocateProblem");Param(first,"Step").Text="2";await Responsive();Check(Errors().Length==0&&RenamePlan.ParseRules(Control<TextBox>("RenameRules").Text)[1].Step==2,"closeout-repair-all-real-model");
  var savedRules=Control<TextBox>("RenameRules").Text;foreach(var size in new[]{(720d,736d),(720d,480d),(1400d,800d)}){window.Width=size.Item1;window.Height=size.Item2;await Responsive();Check(Control<TextBox>("RenameRules").Text==savedRules&&Param(first,"Step").Text=="2","closeout-resize-retains-input-"+size);}
  window.Width=1194;window.Height=736;await Responsive();
  Exception? modalError=null;var visit=window.Dispatcher.BeginInvoke(()=>{Window? dialog=null;try{dialog=window.OwnedWindows.Cast<Window>().Single(w=>M2Children(w).Contains(Control<Grid>("M6RenameFilters")));var grid=Control<Grid>("M6RenameFilters");grid.UpdateLayout();Check(grid.RowDefinitions.Count==9&&grid.Children.Cast<FrameworkElement>().GroupBy(Grid.GetRow).All(g=>g.Count()==2&&g.Select(Grid.GetColumn).Order().SequenceEqual(new[]{0,1})),"closeout-nine-label-control-pairs");Check(new[]{"RenameInputQuery","RenameInputType","RenameInputFolder","RenameInputCamera","RenameDateFrom","RenameDateTo","RenameInputTag"}.All(n=>AutomationProperties.GetName(Control<TextBox>(n)).Length>0),"closeout-task-input-accessible-names");dialog.Width=440;dialog.FontSize=20;dialog.UpdateLayout();Check(grid.Children.OfType<TextBox>().All(t=>t.ActualWidth>=100&&t.ActualHeight>0),"closeout-large-narrow-form-inputs-measured");dialog.Close();}catch(Exception e){modalError=e;dialog?.Close();}});M3Call("M3InputSettings");await visit;if(modalError is not null)throw modalError;
  Action("RefreshRenameOrder");await RenameWait();Check(Control<DataGrid>("RenamePreview").Items.Count==3,"closeout-repaired-real-three-file-preview");Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan,"closeout-valid-freeze-restored");
  Control<TabControl>("WorkspaceTabs").SelectedIndex=1;await Responsive();var selection=photos.SelectedItems.Cast<object>().ToArray();var preview=Field("currentPreview");
  var measurements=new List<object>();
  foreach(var size in new[]{(1194d,736d),(720d,736d),(720d,480d)}){window.Width=size.Item1;window.Height=size.Item2;await Responsive();var map=Control<Microsoft.Web.WebView2.Wpf.WebView2>("MapView");measurements.Add(new{width=window.ActualWidth,height=window.ActualHeight,mapWidth=map.ActualWidth,mapHeight=map.ActualHeight});Check(map.ActualHeight>=150&&map.ActualWidth>=400,"closeout-map-usable-viewport-"+size);}
  Check(Control<DockPanel>("M4Strip").Visibility==Visibility.Collapsed&&((Button)Field("m4Tools")!).Visibility==Visibility.Visible,"closeout-minimum-tools-menu-strip-reachable");
  ((Button)Field("m4StripToggle")!).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Responsive();Check(Control<DockPanel>("M4Strip").Visibility==Visibility.Visible,"closeout-strip-can-reopen-at-minimum");
  ((Button)Field("m4Toggle")!).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Responsive();Check(((ScrollViewer)Field("m4Sidebar")!).Visibility==Visibility.Collapsed&&photos.SelectedItems.Cast<object>().SequenceEqual(selection)&&Equals(preview,Field("currentPreview")),"closeout-sidebar-layout-keeps-selection-preview");
  ((Button)Field("m4Toggle")!).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));((Button)Field("m4StripToggle")!).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));window.Width=1194;window.Height=736;await Responsive();
  foreach(var c in new[]{"定位首个错误","规则操作","照片条","显示或收起照片条","地图工具","照片面板","定位筛选","字段值筛选"}){var translated=L10n.Text(c);Check(translated.Length>0&&(L10n.Language is "zh-Hans" or "zh-Hant" or "ja"||!System.Text.RegularExpressions.Regex.IsMatch(translated,"[\\u4e00-\\u9fff]")),"closeout-changed-runtime-label-"+c);}
  Check(((Button)Field("m4StripToggle")!).Content?.ToString()==L10n.Text("照片条")&&AutomationProperties.GetName((Button)Field("m4Tools")!)==L10n.Text("地图工具"),"closeout-real-map-controls-localized");
  foreach(var hash in hashes)Check(await PhotoDocument.HashAsync(hash.Key)==hash.Value,"closeout-no-photo-write");
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
  File.WriteAllText(Path.Combine(folder,"m6-closeout-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),language=L10n.Language,passed=evidence.Count,measurements,evidence},new JsonSerializerOptions{WriteIndented=true}));
  Console.WriteLine("M6_CLOSEOUT_WPF_CHECKS="+evidence.Count);
 }
}
