using System.Collections;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static IEnumerable<DependencyObject> M2Children(DependencyObject node)
 {
  yield return node;
  foreach(var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())foreach(var descendant in M2Children(child))yield return descendant;
 }
 static void M2Invoke(string name,params object[] args)=>typeof(MainWindow).GetMethod(name,BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,args);
 static void M2FinishOwnTestInput()
 {
  // Evidence is already saved; abandon only this checker's synthetic editor parameters before shutdown.
  typeof(MainWindow).GetField("dateEditorHasInput",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,(Func<bool>)(()=>false));
  M2Invoke("FillEditor",new Dictionary<string,string>());
  M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));
  M3Set("metadataPresetBaseline",new MetadataPreset(Control<TextBox>("PresetName").Text,Array.Empty<MetadataOperation>()));
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));
 }
 static async Task M2Checks()
 {
  explicitSavePlanChecks=true; M3Call("SaveUi",((UiPreference)Field("ui")!) with{SkipSaveScopePrompt=true});
  for(int i=0;i<1200&&((bool)Field("importRunning")!||(bool)Field("busy")!);i++)await Task.Delay(25);
  var photos=Control<ListBox>("Photos");Check(photos.Items.Count==3,"m2-three-synthetic-inputs");photos.SelectAll();await Responsive();
  var docs=photos.Items.Cast<object>().Select(Doc).ToArray();var originals=docs.ToDictionary(d=>d.FilePath,d=>File.ReadAllBytes(d.FilePath));
  Check(MetadataCsv.Tags.Length<=MetadataPreset.MaximumOperations,"m2-full-opened-field-directory-fits-chain-limit");
  var bounded=MetadataPreset.Create("bounded",Enumerable.Repeat(new MetadataOperation("XMP-dc:Title","remove"),MetadataPreset.MaximumOperations).ToArray());
  Check(MetadataPreset.Decode(bounded.Encode()).Operations.Count==MetadataPreset.MaximumOperations,"m2-bounded-chain-preserves-version1-format");
  foreach(string listTarget in new[]{"IPTC:By-line","IPTC:By-lineTitle","IPTC:Contact","IPTC:Keywords","XMP-dc:Subject"})
  {
   var listPlan=MetadataPreset.Create("list",new[]{new MetadataOperation(listTarget,"appendKeywords","A\nA\na")});
   Check(listPlan.Operations.Single().Value=="A\na","m2-Mac-noncreator-list-actions-exact-unique-"+listTarget);
  }
  bool rejected=false;try{MetadataPreset.Create("too many",bounded.Operations.Append(new("XMP-dc:Title","remove")).ToArray());}catch(ArgumentException){rejected=true;}Check(rejected,"m2-chain-count-limit-still-enforced");
  Control<ComboBox>("InspectorView").SelectedIndex=1;Input("MetadataSearch","");await Responsive();
  var rows=InspectorRows();var requested=rows.Where(r=>r.EditTag is "XMP-dc:Title" or "XMP-dc:Description").Concat(rows.Where(r=>r.Tag.Contains("FileName")).Take(1)).ToArray();
  Check(requested.Count(r=>r.CanEdit)==2,"m2-two-writable-fields-plus-readonly-context");
  M2Invoke("OpenWorkflowFields",(object)requested);await Responsive();
  var editor=(Window)Field("metadataWindow")!;var cards=(StackPanel)Field("workflowCards")!;
  Check(editor.IsVisible&&cards.Children.Count==2,"m2-entire-field-set-becomes-real-cards");
  Check(((TextBlock)Field("workflowContext")!).Text.Contains("3 张")&&((TextBlock)Field("workflowContext")!).Text.Contains("FileName"),"m2-frozen-photo-count-exact-sources-and-readonly-exclusions");
  Check(M2Children(editor).Contains(Control<ListBox>("MetadataPresetList")),"m2-existing-real-library-in-editor");
  var first=(Expander)cards.Children[0];var second=(Expander)cards.Children[1];
  TextBox Value(DependencyObject card)=>M2Children(card).OfType<TextBox>().Single(t=>AutomationProperties.GetName(t)=="参数（列表每行一项）");
  Value(first).Text="";
  ComboBox Target(DependencyObject card)=>M2Children(card).OfType<ComboBox>().Single(t=>AutomationProperties.GetName(t)=="目标字段与精确来源");
  Target(first).SelectedValue="XMP-exif:ISO";Value(first).Text="not a number";
  ComboBox Mode(DependencyObject card)=>M2Children(card).OfType<ComboBox>().Single(t=>AutomationProperties.GetName(t)=="字段操作");
  Mode(first).SelectedValue="fillMissingText";Check(Value(first).Text=="not a number","m2-action-switch-keeps-unapplied-shared-parameter");Mode(first).SelectedValue="setText";
  Value(second).Text="WIN-M2 description";M2Invoke("ApplyWorkflow");await Responsive();
  Check(docs.All(d=>d.Draft.Count==0)&&Status.Contains("无效操作"),"m2-invalid-card-prevents-entire-apply");
  M2Children(second).OfType<Button>().Single(b=>Equals(b.Content,"上移")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
  Check(Value(cards.Children[0]).Text=="WIN-M2 description"&&Value(cards.Children[1]).Text=="not a number"&&Equals(Target(cards.Children[1]).SelectedValue,"XMP-exif:ISO"),"m2-invalid-typed-input-and-target-survive-reorder");
  M2Children(cards.Children[1]).OfType<Button>().Single(b=>Equals(b.Content,"上移")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
  first=(Expander)cards.Children[0];second=(Expander)cards.Children[1];Target(first).SelectedValue="XMP-dc:Title";
  Value(first).Text="WIN-M2 title";
  var ops=(IList)Field("presetOperations")!;
  Check(ops.Cast<MetadataOperation>().Select(x=>x.Value).SequenceEqual(new[]{"WIN-M2 title","WIN-M2 description"}),"m2-card-input-connected-to-ordered-production-model");
  var ownerContext=SynchronizationContext.Current!;var held=new HeldContext(ownerContext);
  try{SynchronizationContext.SetSynchronizationContext(held);M2Invoke("ApplyWorkflow");}finally{SynchronizationContext.SetSynchronizationContext(ownerContext);}
  try{await held.Posted.Task.WaitAsync(TimeSpan.FromSeconds(30));Value(first).Text="changed during calculation";}finally{held.Release();}await BatchWait();
  Check(docs.All(d=>d.Draft.Count==0)&&Value(first).Text=="changed during calculation","m2-late-card-input-change-rejects-old-result-and-retains-new-input");
  Value(first).Text="WIN-M2 title";
  M2Invoke("ApplyWorkflow");await BatchWait();
  Check(docs.All(d=>d.Draft.Count==2&&d.Value("XMP-dc:Title")=="WIN-M2 title"&&d.Value("XMP-dc:Description")=="WIN-M2 description"),"m2-multifield-multiphoto-direct-apply");
  Check(Control<TextBlock>("M1DraftCount").Text.Contains("3张 / 6项")&&Control<Button>("SaveButton").IsEnabled,"m2-actual-photo-and-global-draft-counts");
  Action("UndoLastApply");await Responsive();Check(docs.All(d=>d.Draft.Count==0)&&!Control<Button>("SaveButton").IsEnabled,"m2-single-undo-restores-all-field-prior-drafts");
  M2Invoke("ApplyWorkflow");await BatchWait();M2Invoke("ApplyWorkflow");await BatchWait();Check(Status.Contains("没有净改动")&&!Status.Contains("应用完成"),"m2-zero-net-chain-not-success");
  string output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");Action("CancelSavePlan");
  Check(!Directory.EnumerateFiles(output).Any()&&docs.All(d=>d.Draft.Count==2),"m2-cancel-copy-does-not-write-or-clear-draft");
  Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();
  foreach(var doc in docs){var copy=await PhotoDocument.LoadAsync(InspectorTool(),Path.Combine(output,Path.GetFileName(doc.FilePath)));Check(copy.Value("XMP-dc:Title")=="WIN-M2 title"&&copy.Value("XMP-dc:Description")=="WIN-M2 description","m2-independent-copy-readback-"+Path.GetFileName(doc.FilePath));}
  Check(docs.All(d=>d.Draft.Count==2),"m2-saved-copies-keep-session-drafts");Action("UndoDraft");await Responsive();
  M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));editor.Close();await Responsive();
  Check(Field("metadataWindow") is null&&ReferenceEquals(Control<ListBox>("MetadataPresetList").Parent,Control<StackPanel>("PresetControls")),"m2-library-restored-after-editor-close");
  M2Invoke("OpenWorkflowFields",(object)requested);await Responsive();
  cards=(StackPanel)Field("workflowCards")!;Value(cards.Children[0]).Text="selection guard";Value(cards.Children[1]).Text="selection guard description";
  photos.SelectedItems.Clear();photos.SelectedItem=photos.Items[0];await Responsive();M2Invoke("ApplyWorkflow");await Responsive();
  Check(docs.All(d=>d.Draft.Count==0)&&Status.Contains("选择已改变"),"m2-unapplied-cards-do-not-retarget-silently");
  M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));((Window)Field("metadataWindow")!).Close();await Responsive();
  window.Width=720;window.Height=480;await Responsive();Control<RadioButton>("M2NarrowPhotos").IsChecked=true;await Responsive();Check(Control<TextBox>("PhotoSearch").ActualWidth>150&&Control<FrameworkElement>("M2PhotoPane").ActualWidth>600,"m2-minimum-search-remains-readable-in-full-width-photo-pane");
  Control<RadioButton>("M2NarrowFields").IsChecked=true;await Responsive();
  File.WriteAllText(Path.Combine(folder,"minimum-layout.local.json"),System.Text.Json.JsonSerializer.Serialize(new{width=Control<DataGrid>("MetadataGrid").ActualWidth,height=Control<DataGrid>("MetadataGrid").ActualHeight,selected=photos.SelectedItems.Count,paneWidth=Control<FrameworkElement>("M2InspectorPane").ActualWidth,paneHeight=Control<FrameworkElement>("M2InspectorPane").ActualHeight,summaryHeight=Control<TextBlock>("SelectionInfo").ActualHeight,summary=Control<TextBlock>("SelectionInfo").Text,windowWidth=window.ActualWidth,windowHeight=window.ActualHeight}));
  Check(Control<DataGrid>("MetadataGrid").ActualWidth>600&&Control<DataGrid>("MetadataGrid").ActualHeight>90&&photos.SelectedItems.Count==1,"m2-minimum-full-width-inspector-preserves-selection-and-field-viewport");
  window.Width=1193;window.Height=736;await Responsive();Check(Control<FrameworkElement>("M2PhotoPane").Visibility==Visibility.Visible&&Control<FrameworkElement>("M2InspectorPane").Visibility==Visibility.Visible,"m2-widening-restores-two-adjustable-panes");
  var date=new InspectorRow("日期","拍摄时间","Composite:SubSecDateTimeOriginal","2024:01:15 10:20:30.123456+01:00","已读",true,true,"Composite:SubSecDateTimeOriginal");
  Check(date.DisplayPrimary=="2024-01-15 10:20:30"&&date.DisplayDateDetail=="UTC+01:00 · 亚秒 0.123456"&&date.Value=="2024:01:15 10:20:30.123456+01:00","m2-date-display-hierarchy-preserves-exact-value");
  photos.SelectedItems.Clear();photos.SelectedItem=photos.Items[0];await Responsive();
  var displayedDate=InspectorRows().First(r=>r.EditTag=="Composite:SubSecDateTimeOriginal");
  Check(displayedDate.DisplayPrimary==new DateTimeOffset(2024,1,15,10,20,30,TimeSpan.FromHours(1)).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss",System.Globalization.CultureInfo.InvariantCulture)&&displayedDate.Value=="2024:01:15 10:20:30.123456+01:00","m2-local-date-presentation-uses-shared-cached-proof-with-original-value-unchanged");
  M2Invoke("OpenWorkflowDates",(TabItem)Control<TabControl>("MetadataToolsTabs").Items[3]);await Responsive();
  var dateWindow=(Window)Field("dateEditorWindow")!;
  Check(dateWindow.IsVisible&&M2Children(dateWindow).Contains(Control<ComboBox>("DateMode"))&&Control<ComboBox>("DateMode").Items.Count==5,"m2-main-time-entry-reuses-real-five-mode-form-without-old-tab-strip");
  photos.SelectAll();await Responsive();M2Invoke("ApplyDates",window,new RoutedEventArgs());await Responsive();
  Check(!Control<Button>("DatePlanApplyButton").IsEnabled&&docs.All(d=>d.Draft.Count==0)&&Status.Contains("选择已改变"),"m2-date-editor-frozen-selection-not-retargeted");
  M2Invoke("ConfirmWorkflowDateSelection");M2Invoke("ApplyDates",window,new RoutedEventArgs());await BatchWait();
  Check(Control<Button>("DatePlanApplyButton").IsEnabled&&docs.All(d=>d.Draft.Count==0)&&Status.Contains("没有净改动"),"m2-explicit-date-selection-confirmation-keeps-parameters-and-zero-net-semantics");
  dateWindow.Close();
  M2Invoke("SetPresetChain",MetadataPreset.Create("IPTC list",new[]{new MetadataOperation("IPTC:By-line","replaceKeywords","A\nA"),new MetadataOperation("IPTC:By-line","appendKeywords","A\nB")}));await Apply("ApplyPreset");
  Check(docs.All(d=>d.Value("IPTC:By-line")=="A\nB"),"m2-real-JPEG-IPTC-list-chain-preserves-Mac-exact-unique-order");
  string iptcOutput=Path.Combine(folder,"iptc-copies");Directory.CreateDirectory(iptcOutput);Input("OutputFolder",iptcOutput);Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();
  foreach(var doc in docs){var copy=await PhotoDocument.LoadAsync(InspectorTool(),Path.Combine(iptcOutput,Path.GetFileName(doc.FilePath)));Check(copy.Value("IPTC:By-line")=="A\nB","m2-IPTC-list-independent-copy-readback-"+Path.GetFileName(doc.FilePath));}
  Action("UndoDraft");M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));
  Check(originals.All(p=>File.ReadAllBytes(p.Key).SequenceEqual(p.Value)),"m2-input-source-bytes-unchanged");
  SaveResult("m2-wpf-results.json");
 }
}
