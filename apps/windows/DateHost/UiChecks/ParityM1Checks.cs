using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task M1Checks()
 {
  explicitSavePlanChecks=true;
  for(int i=0;i<1200&&((bool)Field("importRunning")!||(bool)Field("busy")!);i++)await Task.Delay(25);
  var photos=Control<ListBox>("Photos");Check(photos.Items.Count==3,"m1-three-current-Mac-synthetic-inputs");
  var originals=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>File.ReadAllBytes(d.FilePath));
  var docs=photos.Items.Cast<object>().Select(Doc).ToArray();
  Check(Control<TabControl>("WorkspaceTabs").Items.Count==3&&Control<TabControl>("WorkspaceTabs").Items.Cast<TabItem>().Select(t=>t.Header).SequenceEqual(new[]{"元数据编辑","地图定位","重命名"}),"m1-only-three-workspaces-in-Mac-order");
  Check(photos is ListView {View:GridView view}&&view.Columns.Count==5,"m1-real-photo-table-five-columns");
  Check(window.FindName("M1MetadataLayout") is Grid layout&&Math.Abs(layout.ColumnDefinitions[0].ActualWidth-layout.ColumnDefinitions[2].ActualWidth)<20,"m1-default-balanced-two-columns");
  Check(Control<FrameworkElement>("M1PhotoSidebar").Visibility==Visibility.Collapsed,"m1-photo-actions-closed-by-default");
  photos.SelectAll();await Responsive();
  Check(InspectorRows().Any(r=>r.State=="混合值")&&InspectorRows().Any(r=>r.State=="缺失"),"m1-mixed-and-missing-distinct");
  Check(InspectorRows().Where(r=>r.Tag.Contains("FileName")||r.Tag.Contains("FilePath")).All(r=>!r.CanEdit),"m1-file-fields-remain-readonly");
  var capture=InspectorRows().First(r=>r.EditTag=="Composite:SubSecDateTimeOriginal");
  Check(capture.CanEdit,"m1-multiselect-exact-source-real-editor-eligibility");
  Control<ComboBox>("InspectorView").SelectedIndex=1;Input("MetadataSearch","XMP-dc:Title");
  Check(InspectorRows().Length>0&&photos.SelectedItems.Count==3,"m1-full-field-search-preserves-selection");Input("MetadataSearch","");
  typeof(MainWindow).GetMethod("OpenM1Field",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[capture]);await Responsive();
  Check(window.OwnedWindows.Cast<Window>().Any(w=>w.IsVisible)&&SettingsTab(window,"编辑草稿")?.IsSelected==true,"m1-field-opens-live-owned-editor");
  typeof(MainWindow).GetField("metadataClosing",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,true);
  try { FindButton((Window)Field("metadataWindow")!,"关闭").RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Check(((Window)Field("metadataWindow")!).IsVisible,"m1-repeated-footer-close-ignored-during-close-confirmation"); }
  finally { typeof(MainWindow).GetField("metadataClosing",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,false); }
  EditedFields(new(){{"Composite:SubSecDateTimeOriginal","2024:01:15 10:20:31.123456+01:00"}});await Apply("ApplyDraft");
  Check(docs.All(d=>MetadataInspector.PendingFields(d)==1)&&Control<TextBlock>("M1DraftCount").Text.Contains("3张 / 3项"),"m1-three-drafts-count-and-footer");
  Check(Control<Button>("SaveButton").IsEnabled&&InspectorRows().Any(r=>r.HasDraft),"m1-save-and-inspector-show-actual-drafts");
  foreach(int index in new[]{1,2,0}){Control<TabControl>("WorkspaceTabs").SelectedIndex=index;await Responsive();Check(photos.SelectedItems.Count==3&&docs.All(d=>d.Draft.Count>0),"m1-workspace-keeps-real-drafts-"+index);}
  Action("UndoLastApply");await Responsive();
  Check(docs.All(d=>d.Draft.Count==0)&&!Control<Button>("SaveButton").IsEnabled&&Control<TextBlock>("M1DraftCount").Text=="无待保存修改","m1-undo-current-drafts-counts-and-save-consistent");
  Check(!Control<TextBlock>("DatePlanPreview").Text.Contains("应用完成")&&Control<TextBlock>("DatePlanPreview").Text.Contains("已撤销"),"m1-UX01-stale-success-message-fixed");
  Input("TitleValue","cancel this input");Control<CheckBox>("TitleApply").IsChecked=true;
  var editor=(Window)Field("metadataWindow")!;
  Button FindButton(DependencyObject element,string label){if(element is Button b&&Equals(b.Content,label))return b;foreach(var child in LogicalTreeHelper.GetChildren(element).OfType<DependencyObject>()){var found=FindButtonOrNull(child,label);if(found is not null)return found;}throw new Exception(label);}
  Button? FindButtonOrNull(DependencyObject element,string label){if(element is Button b&&Equals(b.Content,label))return b;foreach(var child in LogicalTreeHelper.GetChildren(element).OfType<DependencyObject>()){var found=FindButtonOrNull(child,label);if(found is not null)return found;}return null;}
  FindButton(editor,"取消本次未应用输入").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));await Responsive();
  Check(docs.All(d=>d.Draft.Count==0)&&Field("metadataWindow") is null,"m1-cancel-editor-no-draft-or-file-write");
  foreach(int index in new[]{1,2,0}){Control<TabControl>("WorkspaceTabs").SelectedIndex=index;await Responsive();Check(photos.SelectedItems.Count==3&&docs.All(d=>d.Draft.Count==0),"m1-workspace-preserves-selection-"+index);}
  Action("M1OpenSettings");await Responsive();Check(Field("settingsWindow") is Window {IsVisible:true}&&Control<TabControl>("WorkspaceTabs").Items.Count==3,"m1-settings-owned-independent-window");
  int oldTheme=Control<ComboBox>("ThemeChoice").SelectedIndex;Control<ComboBox>("ThemeChoice").SelectedIndex=(oldTheme+1)%3;
#pragma warning disable WPF0001
  Check(((Window)Field("settingsWindow")!).ThemeMode==window.ThemeMode,"m1-owned-settings-tracks-theme-change");
#pragma warning restore WPF0001
  Control<ComboBox>("ThemeChoice").SelectedIndex=oldTheme;((Window)Field("settingsWindow")!).Close();
  Action("M1TogglePhotoActions");Check(Control<FrameworkElement>("M1PhotoSidebar").Visibility==Visibility.Visible,"m1-photo-actions-real-toggle");Action("M1TogglePhotoActions");
  EditedFields(new(){{"XMP-dc:Title","WIN-M1 synthetic title"}});await Apply("ApplyDraft");
  Check(InspectorRows().Any(r=>r.EditTag=="XMP-dc:Title"&&r.HasDraft&&r.Value=="WIN-M1 synthetic title"&&r.State=="已读"),"m1-previously-missing-field-displays-current-draft-value-and-state");
  string output=Path.Combine(folder,"m1-output");Directory.CreateDirectory(output);Input("OutputFolder",output);
  Action("SaveCopies");Check(Control<TabItem>("SaveTargetTab").IsSelected&&Control<Button>("ExecuteSaveButton").IsEnabled&&!Directory.EnumerateFiles(output).Any(),"m1-save-summary-is-real-and-explicit");
  Action("CancelSavePlan");Check(!Directory.EnumerateFiles(output).Any()&&docs.All(d=>d.Draft.Count>0),"m1-cancel-save-retains-drafts-no-write");
  Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();
  var tool=InspectorTool();foreach(var source in docs){var copy=await PhotoDocument.LoadAsync(tool,Path.Combine(output,Path.GetFileName(source.FilePath)));Check(copy.Value("XMP-dc:Title")=="WIN-M1 synthetic title","m1-copy-independent-metadata-readback-"+Path.GetFileName(source.FilePath));}
  Check(docs.All(d=>d.Draft.Count>0)&&Control<Button>("SaveButton").IsEnabled,"m1-copy-save-keeps-session-drafts");
  Action("UndoDraft");await Responsive();
  Check(docs.All(d=>d.Draft.Count==0)&&Directory.EnumerateFiles(output).Count()==3,"m1-clear-draft-does-not-undo-saved-files");
  if(Field("metadataWindow") is Window open)open.Close();
  Action("RemovePhotos");await Responsive();Check(photos.Items.Count==0,"m1-remove-current-selection-only");Action("UndoRemovePhotos");await Responsive();Check(photos.Items.Count==3,"m1-undo-remove-restores-three");
  photos.SelectedItems.Clear();photos.SelectedItem=photos.Items[0];await Responsive();
  EditedFields(new(){{"XMP-dc:Title",Doc(photos.SelectedItem!).Value("XMP-dc:Title")}});await Apply("ApplyDraft");
  Check(Doc(photos.SelectedItem!).Draft.Count==0&&Status.Contains("没有净改动")&&!Status.Contains("应用完成"),"m1-zero-net-change-not-presented-as-success");
  Input("TitleValue","unchecked input must survive");Action("RemovePhotos");Check(photos.Items.Count==3&&Control<TextBox>("TitleValue").Text=="unchecked input must survive","m1-unchecked-unapplied-input-blocks-remove");
  typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
  var png=Path.Combine(folder,"readonly.png");using(var stream=File.Create(png)){var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder();encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(PixelsImage(32,16)));encoder.Save(stream);}
  await ImportMore(png);photos.SelectedItems.Clear();photos.SelectedItem=photos.Items.Cast<object>().Single(r=>Doc(r).FilePath==png);await Responsive();
  Check(!Doc(photos.SelectedItem!).CanStage&&InspectorRows().All(r=>!r.CanEdit)&&!Control<Button>("FieldApplyButton").IsEnabled,"m1-readonly-format-does-not-gain-write-eligibility");
  File.Move(png,png+".missing");Action("RereadPhotos");await BatchWait();
  Check(Doc(photos.SelectedItem!).InspectionError.Length>0&&InspectorRows().All(r=>!r.CanEdit),"m1-missing-source-retains-stale-readonly-snapshot");File.Move(png+".missing",png);
  Check(originals.All(p=>File.ReadAllBytes(p.Key).SequenceEqual(p.Value)),"m1-original-input-bytes-unchanged");
  SaveResult("m1-wpf-results.json");
 }
}
