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
 static async Task M7Checks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");var tabs=Control<TabControl>("WorkspaceTabs");var originals=photos.Items.Cast<object>().ToDictionary(r=>Doc(r).FilePath,r=>Doc(r).SourceHash);
  Check(originals.Count==3,"M7-three-isolated-synthetic-JPEG");
  string Peer(FrameworkElement element)=>UIElementAutomationPeer.CreatePeerForElement(element)!.GetName();
  async Task RowNames(ListBox list,string label){foreach(var item in list.Items.Cast<object>()){list.ScrollIntoView(item);await Responsive();var row=(FrameworkElement)list.ItemContainerGenerator.ContainerFromItem(item);Check(Peer(row)==Path.GetFileName(Doc(item).FilePath),"M7-"+label+"-actual-peer-name-is-filename");}}
  await RowNames(photos,"photo-table");Check(Peer(Control<DataGrid>("MetadataGrid"))==(string)window.FindResource("M1.Metadata"),"M7-inspector-peer-has-localized-name");
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
  var dpi=VisualTreeHelper.GetDpi(window);var environment=new{dpiScaleX=dpi.DpiScaleX,dpiScaleY=dpi.DpiScaleY,pixelsPerInch=dpi.PixelsPerInchX,windowOuterDIP=new[]{window.ActualWidth,window.ActualHeight},contentDIP=new[]{((FrameworkElement)window.Content).ActualWidth,((FrameworkElement)window.Content).ActualHeight},workAreaDIP=new[]{SystemParameters.WorkArea.Width,SystemParameters.WorkArea.Height},virtualDesktopDIP=new[]{SystemParameters.VirtualScreenWidth,SystemParameters.VirtualScreenHeight},systemHighContrast=SystemParameters.HighContrast,language=L10n.Language,scope="WPF production peers/routed key regression; not native input, audible Narrator, simulated DPI or real multi-monitor evidence"};
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m7-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),environment,passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
