using System.Collections;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using PhotoTrail.Windows;

static partial class Program
{
 static TabItem? SettingsTab(DependencyObject node,string header){if(node is TabItem item&&item.Header?.ToString()==header)return item;foreach(var child in LogicalTreeHelper.GetChildren(node).OfType<DependencyObject>())if(SettingsTab(child,header)is{} found)return found;return null;}
 static void SelectMetadataTab(string header){var tab=SettingsTab(window,header)!;((TabControl)LogicalTreeHelper.GetParent(tab)).SelectedItem=tab;}
 static string[] RowNames()=>Control<ListBox>("Photos").Items.Cast<object>().Select(r=>Path.GetFileName(Doc(r).FilePath)).ToArray();
 static async Task RunSettings(bool restore)
 {
  while((bool)Field("busy")!)await Task.Delay(10);
  var list=Control<ListBox>("Photos");Check(list.Items.Count==3,"settings-real-three-imports");
  var prefs=Environment.GetEnvironmentVariable("PHOTOTRAIL_SETTINGS_FILE")!;var history=Environment.GetEnvironmentVariable("PHOTOTRAIL_SEARCH_HISTORY_FILE")!;
  var dpi=VisualTreeHelper.GetDpi(window);evidence.Add(new{name="actual-dpi",dpi.DpiScaleX,dpi.DpiScaleY,systemFont=window.FontSize});
  if(restore){
   Check(Control<ComboBox>("MetadataTextSize").SelectedIndex==2&&Control<ComboBox>("MetadataSpacing").SelectedIndex==0&&Control<CheckBox>("FullTagNames").IsChecked==false&&Control<ComboBox>("PhotoSort").SelectedIndex==3,"fresh-process-display-and-sort-restored");
   Check(Control<CheckBox>("RecordMapSearches").IsChecked==true&&MapSearchHistory.Read(history).SequenceEqual(new[]{"KYOTO","Osaka","Tokyo"}),"fresh-process-history-restored");
   var sorts=CollectionViewSource.GetDefaultView(Field("photos")!).SortDescriptions;Check(sorts.Count==3&&sorts[0].PropertyName=="Captured"&&sorts[1].PropertyName=="Name"&&sorts[2].PropertyName=="Imported","fresh-process-comparator-sequence-unknown-skipped-stable-tie");
  }else{
   Check(Control<ComboBox>("MetadataTextSize").SelectedIndex==1&&Control<ComboBox>("MetadataSpacing").SelectedIndex==1&&Control<CheckBox>("FullTagNames").IsChecked==true&&Control<ComboBox>("PhotoSort").SelectedIndex==0,"four-defaults-in-real-controls");
   list.SelectedItem=list.Items[0];Control<TextBox>("TitleValue").Text="unapplied kept";
   var selected=list.SelectedItems.Cast<object>().ToArray();Control<ComboBox>("MetadataTextSize").SelectedIndex=2;Control<ComboBox>("MetadataSpacing").SelectedIndex=0;Control<CheckBox>("FullTagNames").IsChecked=false;
   Check(Control<TextBox>("TitleValue").Text=="unapplied kept"&&Control<CheckBox>("TitleApply").IsChecked==true&&list.SelectedItems.Cast<object>().SequenceEqual(selected),"settings-keep-unapplied-input-and-selection");
   Check(Math.Abs(Control<TextBox>("TitleValue").FontSize-window.FontSize-8d/3)<1e-8&&Control<TextBox>("TitleValue").Padding.Top==2&&Control<TextBox>("TitleValue").MinHeight==30,"real-font-pt-dip-and-density-independent");
   Check(!Control<CheckBox>("DateApply").Content.ToString()!.Contains("DateTimeOriginal")&&Control<CheckBox>("DateApply").Content.ToString()!.Contains("XMP-exif")&&Control<CheckBox>("DateApply").ToolTip.ToString()=="XMP-exif:DateTimeOriginal"&&System.Windows.Automation.AutomationProperties.GetName(Control<CheckBox>("DateApply")).Contains("DateTimeOriginal"),"hidden-display-complete-tooltip-and-accessibility");
   Action("ApplyDraft");SelectMetadataTab("原始字段");Control<TextBox>("MetadataSearch").Text="XMP-exif:DateTimeOriginal";
   var grid=Control<DataGrid>("MetadataGrid");Check(grid.IsReadOnly&&grid.Items.Count==1,"hidden-full-key-search-readonly");grid.SelectedItem=grid.Items[0];Action("CopyMetadataTag");Check(Clipboard.GetText().Contains("XMP-exif:DateTimeOriginal"),"copy-full-tag-after-hide");
   grid.SelectAllCells();System.Windows.Input.ApplicationCommands.Copy.Execute(null,grid);Check(Clipboard.GetText().Contains("XMP-exif:DateTimeOriginal"),"native-grid-copy-preserves-full-name");
   list.SelectAll();var docs=list.SelectedItems.Cast<object>().Select(Doc).ToArray();SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=0;Control<TextBox>("DateSeconds").Text="1";Action("PreviewDates");await Idle();Check(Control<Button>("DatePlanApplyButton").IsEnabled&&Status.Contains("跳过1"),"accepted-offset-path-after-settings");Action("ApplyDates");await Idle();
   Check(docs.Count(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal"))==2&&docs.Any(d=>d.Draft.Values.Contains("unapplied kept")),"date-and-title-drafts-not-lost");
   var copies=Path.Combine(folder,"settings-copies");Directory.CreateDirectory(copies);Control<TextBox>("OutputFolder").Text=copies;Action("SaveCopies");while((bool)Field("busy")!)await Task.Delay(10);
   Check(Status.Contains("副本成功 2，失败 0"),"settings-regression-copy-save");var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
   foreach(var doc in docs){await doc.EnsureUnchangedAsync();if(doc.Draft.Count>0){var read=await PhotoDocument.LoadAsync(client,Path.Combine(copies,Path.GetFileName(doc.FilePath)));Check(read.Value("XMP-exif:DateTimeOriginal")==doc.Value("XMP-exif:DateTimeOriginal")&&read.Value("XMP-dc:Title")==doc.Value("XMP-dc:Title"),"copy-date-title-readback");}}
   Action("UndoDraft");Check(docs.All(d=>d.Draft.Count==0),"regression-undo-with-source-protection");
   var selection=list.SelectedItems.Cast<object>().ToArray();var renameOrder=((IEnumerable)typeof(MainWindow).GetMethod("RenameSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null)!).Cast<object>().ToArray();
   Action("FreezeRename");while((bool)Field("busy")!)await Task.Delay(10);var frozen=Field("frozenRenamePlan");Check(frozen is not null,"existing-rename-plan-frozen");
   Control<ComboBox>("PhotoSort").SelectedIndex=1;Check(RowNames().SequenceEqual(RowNames().OrderDescending(StringComparer.CurrentCulture))&&list.SelectedItems.Cast<object>().SequenceEqual(selection),"name-sort-selection-order-preserved");
   var after=((IEnumerable)typeof(MainWindow).GetMethod("RenameSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null)!).Cast<object>().ToArray();Check(after.SequenceEqual(renameOrder)&&ReferenceEquals(frozen,Field("frozenRenamePlan")),"photo-sort-independent-frozen-rename-numbering");
   Control<ComboBox>("PhotoSort").SelectedIndex=3;Check(SettingsPreference.Read(prefs).PhotoSort.SequenceEqual(new[]{new PhotoSortPreference("captured",true)}),"captured-sort-persisted");
   Control<ComboBox>("ThemeChoice").SelectedIndex=1;window.UpdateLayout();Check(window.IsVisible&&Control<TextBox>("TitleValue").FontSize>0,"light-settings-layout");Control<ComboBox>("ThemeChoice").SelectedIndex=2;window.UpdateLayout();Check(window.IsVisible&&Control<ComboBox>("MetadataTextSize").IsEnabled,"dark-settings-layout");
   await SetupLocalSearch();
   async Task Search(string term){Control<TextBox>("MapSearchQuery").Text=term;Action("SearchPlace");for(int i=0;i<300&&(bool)Field("placePending")!;i++)await Task.Delay(10);Check(!(bool)Field("placePending")!&&Control<TextBlock>("PlacePreview").Text.Contains("地区预览"),"controlled-existing-google-query-result-"+term);}
   foreach(var term in new[]{"Kyoto","Tokyo","Osaka","  KYOTO  "})await Search(term);Check(MapSearchHistory.Read(history).SequenceEqual(new[]{"KYOTO","Osaka","Tokyo"})&&Control<ListBox>("RecentMapSearches").Items.Count==3,"history-dedup-three-visible-native-items");
   Control<ListBox>("RecentMapSearches").SelectedIndex=1;Check(MapSearchHistory.Read(history)[0]=="Osaka"&&Control<TextBox>("MapSearchQuery").Text=="Osaka"&&!(bool)Field("placePending")!,"recent-term-promoted-filled-without-new-online-request");
   var historyBytes=File.ReadAllBytes(history);Control<CheckBox>("RecordMapSearches").IsChecked=false;await Search("not recorded");Check(Control<ListBox>("RecentMapSearches").Visibility==Visibility.Collapsed&&historyBytes.SequenceEqual(File.ReadAllBytes(history)),"off-hidden-no-add-existing-query-still-works");
   Control<CheckBox>("RecordMapSearches").IsChecked=true;Check(Control<ListBox>("RecentMapSearches").Items.Count==3,"reenabled-restores-three");
   var currentQuery=Control<TextBox>("MapSearchQuery").Text;var provider=Field("currentMapPage");Action("ResetSettings");Check(historyBytes.SequenceEqual(File.ReadAllBytes(history))&&Control<TextBox>("MapSearchQuery").Text==currentQuery&&Equals(Field("currentMapPage"),provider),"reset-default-keeps-history-query-provider");
   var settingsBytes=File.ReadAllBytes(prefs);Action("ClearSearchHistory");Check(MapSearchHistory.Read(history).Length==0&&settingsBytes.SequenceEqual(File.ReadAllBytes(prefs))&&Control<TextBox>("MapSearchQuery").Text==currentQuery&&Equals(Field("currentMapPage"),provider),"clear-only-history-no-query-settings-provider-change");
   foreach(var term in new[]{"Tokyo","Osaka","KYOTO"})await Search(term);
   var readonlyFolder=Path.Combine(folder,"readonly");Directory.CreateDirectory(readonlyFolder);var png=Path.Combine(readonlyFolder,"sample.png");
   var bitmap=System.Windows.Media.Imaging.BitmapSource.Create(1,1,96,96,PixelFormats.Bgra32,null,new byte[]{0,0,0,255},4);var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder();encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));using(var stream=File.Create(png))encoder.Save(stream);
   var readOnly=await PhotoDocument.LoadAsync(client,png);var rowType=list.Items[0].GetType();var readOnlyRow=Activator.CreateInstance(rowType,readOnly)!;((IList)Field("photos")!).Add(readOnlyRow);list.SelectedItem=readOnlyRow;
   Control<ComboBox>("MetadataTextSize").SelectedIndex=0;Check(!Control<StackPanel>("Editor").IsEnabled&&!Control<TextBox>("TitleValue").IsEnabled&&Control<DataGrid>("MetadataGrid").IsReadOnly,"readonly-png-stays-readonly-after-font-change");await readOnly.EnsureUnchangedAsync();
   Control<ComboBox>("MetadataTextSize").SelectedIndex=2;Control<ComboBox>("MetadataSpacing").SelectedIndex=0;Control<CheckBox>("FullTagNames").IsChecked=false;Control<ComboBox>("PhotoSort").SelectedIndex=3;
  }
  int passed=evidence.Count(item=>item.GetType().GetProperty("passed")?.GetValue(item)is true);
  File.WriteAllText(Path.Combine(folder,restore?"settings-restored-results.json":"settings-ui-results.json"),JsonSerializer.Serialize(new{passed,evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("SETTINGS_WPF_CHECKS="+passed);window.Close();
 }
 static async Task SetupLocalSearch()
 {
  var view=Control<WebView2>("MapView");
  typeof(MainWindow).GetField("currentMapPage",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,MapMessage.GooglePage);
  var htmlPath=Path.Combine(AppContext.BaseDirectory,"Web","google.html");var original=File.ReadAllBytes(htmlPath);
  var script=File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Web","google.js"));var marker="post({type:'google-bootstrap'});";if(!script.Contains(marker))throw new Exception("bootstrap fixture point changed");script=script.Replace(marker,"window.initGoogle();");
  var stub="class Data{setStyle(){}addListener(){}forEach(){}remove(){}addGeoJson(){}}; class Marker{setMap(){}addListener(){}}; window.google={maps:{Map:class{addListener(){}fitBounds(){}setCenter(){}setZoom(){}},Data,Marker,SymbolPath:{CIRCLE:1},LatLngBounds:class{extend(){}},Geocoder:class{geocode(request,callback){queueMicrotask(()=>callback([{address_components:[{types:['locality'],long_name:request.address||'Local result'}],geometry:{location:{lng:()=>135.77,lat:()=>35.01}}}],'OK'));}}}};";
  // Virtual-host files bypass WebResourceRequested; replace only this isolated checker output and restore it.
  File.WriteAllText(htmlPath,"<!doctype html><html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'\"></head><body><div id='map'></div><div id='message'>Local SDK substitute: no online service</div><script>"+stub+script+"</script></body></html>");
  try {
  Control<TabControl>("WorkspaceTabs").SelectedIndex=1;
  for(int i=0;i<1500&&!(bool)Field("mapReady")!;i++)await Task.Delay(10);
  Check((bool)Field("mapReady")!,"local-sdk-native-webview-ready-no-real-key-or-network");
  }finally{File.WriteAllBytes(htmlPath,original);}
 }
}
