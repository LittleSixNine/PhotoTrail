using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PreReleaseKeyboardChecks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();await Responsive();
  var hashes=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  var opener=Control<Button>("M1MoreButton");
  async Task Exercise(Window editor,ComboBox picker,string label)
  {
   editor.Activate();picker.Focus();picker.IsDropDownOpen=true;await Responsive();
   void Escape()=>editor.RaiseEvent(new KeyEventArgs(Keyboard.PrimaryDevice,PresentationSource.FromVisual(editor),0,Key.Escape){RoutedEvent=Keyboard.PreviewKeyDownEvent});
   Escape();await Responsive();Check(editor.IsVisible&&!picker.IsDropDownOpen,label+"-escape-dismisses-picker-keeps-window");
   Check(picker.IsKeyboardFocusWithin,label+"-picker-focus-retained");
   CancelEventHandler guard=(_,e)=>e.Cancel=true;editor.Closing+=guard;Escape();await Responsive();
   Check(editor.IsVisible,label+"-second-escape-honors-close-veto");editor.Closing-=guard;
   Escape();await Responsive();Check(!editor.IsVisible,label+"-next-escape-closes");
   Check(opener.IsKeyboardFocusWithin,label+"-focus-returns-to-opening-control");
  }
  opener.Focus();Action("M1OpenSettings");await Responsive();
  var settings=(Window)Field("settingsWindow")!;
  await Exercise(settings,M2Children(settings).OfType<ComboBox>().First(c=>c.IsVisible),"settings");
  M2Invoke("SetPresetChain",MetadataPreset.Create("keyboard",[new MetadataOperation("XMP-dc:Title","setText","keyboard")]));
  M3Set("metadataPresetBaseline",MetadataPreset.Create("keyboard",[new MetadataOperation("XMP-dc:Title","setText","keyboard")]));
  opener.Focus();M2Invoke("OpenWorkflow",false);await Responsive();var metadata=(Window)Field("metadataWindow")!;
  await Exercise(metadata,M2Children(metadata).OfType<ComboBox>().First(c=>c.IsVisible),"metadata");
  M2Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));
  opener.Focus();M2Invoke("OpenWorkflowDates",(TabItem)Control<TabControl>("MetadataToolsTabs").Items[3]);await Responsive();
  await Exercise((Window)Field("dateEditorWindow")!,Control<ComboBox>("DateTarget"),"date");
  opener.Focus();var renamePicker=new ComboBox{ItemsSource=new[]{"one","two"},SelectedIndex=0};
  var rename=(Window)M3Call("M3Dialog","Settings",renamePicker,600d,500d)!;rename.Show();await Responsive();
  await Exercise(rename,renamePicker,"rename");
  foreach(var item in hashes)Check(await PhotoDocument.HashAsync(item.Key)==item.Value,"keyboard-source-SHA-unchanged");
  Check(photos.Items.Cast<object>().All(r=>Doc(r).Draft.Count==0),"keyboard-no-staged-photo-changes");
  SaveResult("pre-release-keyboard.json",new{kind="production WPF routed events and focus; not native input"});
 }
}
