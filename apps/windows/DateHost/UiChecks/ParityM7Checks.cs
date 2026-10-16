using System.ComponentModel;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using PhotoTrail.Windows;

static partial class Program
{
 [System.Runtime.InteropServices.DllImport("user32.dll")]static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hwnd);
 [System.Runtime.InteropServices.DllImport("user32.dll")]static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
 static async Task M7Checks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");var tabs=Control<TabControl>("WorkspaceTabs");var originals=photos.Items.Cast<object>().ToDictionary(r=>Doc(r).FilePath,r=>Doc(r).SourceHash);
  Check(originals.Count==3,"M7-three-isolated-synthetic-JPEG");
  string Peer(FrameworkElement element)=>UIElementAutomationPeer.CreatePeerForElement(element)!.GetName();
  static IEnumerable<DependencyObject> Visuals(DependencyObject root){yield return root;for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++)foreach(var child in Visuals(VisualTreeHelper.GetChild(root,i)))yield return child;}
  async Task RowNames(ListBox list,string label){foreach(var item in list.Items.Cast<object>()){list.ScrollIntoView(item);await Responsive();var row=(FrameworkElement)list.ItemContainerGenerator.ContainerFromItem(item);Check(Peer(row)==Path.GetFileName(Doc(item).FilePath),"M7-"+label+"-actual-peer-name-is-filename");}}
  M3Call("OpenMetadataTool",Control<TabItem>("SaveTargetTab"));await Responsive();var initialSummary=Control<TextBox>("SaveSummary");var summaryValue=(System.Windows.Automation.Provider.IValueProvider)UIElementAutomationPeer.CreatePeerForElement(initialSummary)!.GetPattern(PatternInterface.Value);Check(summaryValue.IsReadOnly&&summaryValue.Value==L10n.Text("尚未准备保存计划。默认副本；原位必须先备份。")&&(L10n.Language=="zh-Hans"||summaryValue.Value!="尚未准备保存计划。默认副本；原位必须先备份。"),"M7-real-readonly-initial-save-summary-automation-value-localized");((Window)Field("advancedWindow")!).Close();
  await RowNames(photos,"photo-table");Check(Peer(Control<DataGrid>("MetadataGrid"))==(string)window.FindResource("M1.Metadata"),"M7-inspector-peer-has-localized-name");
  var entry=new MetadataPresetEntry(Guid.NewGuid(),MetadataPreset.Create("已更名 · preview 演示",new[]{new MetadataOperation("XMP-dc:Title","setText","原始值")}));var serialized=JsonSerializer.Serialize(entry);var library=Control<ListBox>("MetadataPresetList");library.ItemsSource=new[]{entry};M3Call("OpenWorkflow",false);await Responsive();
  var item=(ListBoxItem)library.ItemContainerGenerator.ContainerFromItem(entry);var expected=L10n.Format("{0} · {1} 条操作",entry.Preset.Name,1);var label=Visuals(item).OfType<TextBlock>().Single(t=>t.Text==expected);
  Check(label.Text==expected&&Peer(item)==expected&&(L10n.Language=="zh-Hans"||!label.Text.EndsWith("条操作",StringComparison.Ordinal)),"M7-real-preset-library-item-text-and-peer-localized");Check(entry.Preset.Name=="已更名 · preview 演示"&&serialized==JsonSerializer.Serialize(entry)&&entry.ToString().EndsWith("1 条操作",StringComparison.Ordinal),"M7-generated-count-display-preserves-user-name-model-and-serialization");((Window)Field("metadataWindow")!).Close();
  photos.SelectAll();var drafts=originals.Keys.ToDictionary(p=>p,p=>Doc(photos.Items.Cast<object>().Single(r=>Doc(r).FilePath==p)).Draft.Count);
  foreach(int workspace in new[]{0,1,2}){
   tabs.SelectedIndex=workspace;await Responsive();if(workspace==1)await RowNames(Control<ListBox>("PhotoStrip"),"map-strip");if(workspace==2)Check(Peer(Control<DataGrid>("RenamePreview"))==(string)window.FindResource("M3Results"),"M7-rename-result-peer-has-localized-name");
   var opener=Control<Button>("M1MoreButton");opener.Focus();Action("M1OpenSettings");await Responsive();var settings=(Window)Field("settingsWindow")!;var pages=Control<TabControl>("SettingsPages");
   Check(ReferenceEquals(settings.Owner,window)&&pages.IsKeyboardFocusWithin,"M7-settings-initial-keyboard-focus-from-workspace-"+workspace);
   void Escape()=>settings.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(settings),0,Key.Escape){RoutedEvent=Keyboard.PreviewKeyDownEvent});
   CancelEventHandler guard=(_,e)=>e.Cancel=true;settings.Closing+=guard;Escape();await Responsive();Check(settings.IsVisible&&ReferenceEquals(Field("settingsWindow"),settings),"M7-escape-honors-existing-closing-veto-"+workspace);settings.Closing-=guard;
   Escape();await Responsive();Check(Field("settingsWindow")is null&&!settings.IsVisible&&opener.IsKeyboardFocusWithin,"M7-escape-closes-settings-and-restores-opener-focus-"+workspace);
   Check(tabs.SelectedIndex==workspace&&photos.SelectedItems.Count==3&&photos.Items.Cast<object>().All(r=>Doc(r).Draft.Count==drafts[Doc(r).FilePath]),"M7-settings-roundtrip-keeps-workspace-selection-drafts-"+workspace);
  }
  tabs.SelectedIndex=0;photos.SelectedItems.Clear();photos.SelectedItem=photos.Items[1];await Responsive();await RowNames(photos,"selection-refresh");Check(photos.SelectedItems.Count==1,"M7-peer-check-does-not-change-selection");
  foreach(var pair in originals)Check(await PhotoDocument.HashAsync(pair.Key)==pair.Value,"M7-no-source-content-write");
  var dpi=VisualTreeHelper.GetDpi(window);var awareness=GetAwarenessFromDpiAwarenessContext(GetWindowDpiAwarenessContext(new System.Windows.Interop.WindowInteropHelper(window).Handle));var environment=new{dpiScaleX=dpi.DpiScaleX,dpiScaleY=dpi.DpiScaleY,pixelsPerInch=dpi.PixelsPerInchX,nativeDpiAwareness=awareness,nativeDpiAwarenessMeaning="0=unaware,1=system-aware,2=per-monitor-aware",windowOuterDIP=new[]{window.ActualWidth,window.ActualHeight},contentDIP=new[]{((FrameworkElement)window.Content).ActualWidth,((FrameworkElement)window.Content).ActualHeight},workAreaDIP=new[]{SystemParameters.WorkArea.Width,SystemParameters.WorkArea.Height},virtualDesktopDIP=new[]{SystemParameters.VirtualScreenWidth,SystemParameters.VirtualScreenHeight},systemHighContrast=SystemParameters.HighContrast,language=L10n.Language,scope="WPF production peers/routed key regression; not native input, audible Narrator, simulated DPI or real multi-monitor evidence"};
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m7-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),environment,passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
