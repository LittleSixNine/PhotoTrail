using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task M6R3Checks()
 {
  await ImportDone();var photos=Control<ListBox>("Photos");photos.SelectAll();Control<TabControl>("WorkspaceTabs").SelectedIndex=2;await Responsive();
  var originals=photos.Items.Cast<object>().Select(Doc).ToDictionary(d=>d.FilePath,d=>d.SourceHash);
  Check(originals.Count==3&&L10n.Language==Environment.GetEnvironmentVariable("PHOTOTRAIL_CHECK_LANGUAGE"),"r3-isolated-three-sources-and-runtime-language");
  var measurements=new List<object>();Exception? modalError=null;
  var visit=window.Dispatcher.BeginInvoke(()=>{Window? dialog=null;try{
   var notice=Control<TextBlock>("RenameDateBoundaryNotice");dialog=window.OwnedWindows.Cast<Window>().Single(w=>M2Children(w).Contains(notice));var scroll=M2Children(dialog).OfType<ScrollViewer>().Single(s=>s.Content is StackPanel);double normal=dialog.FontSize;
   foreach(double width in new[]{760d,440d})foreach(double font in new[]{normal,normal+2*96d/72d}){
    dialog.Width=width;dialog.FontSize=font;dialog.Height=650;dialog.UpdateLayout();notice.BringIntoView();dialog.UpdateLayout();
    var text=new FormattedText(notice.Text,CultureInfo.CurrentUICulture,notice.FlowDirection,new Typeface(notice.FontFamily,notice.FontStyle,notice.FontWeight,notice.FontStretch),notice.FontSize,Brushes.Black,VisualTreeHelper.GetDpi(notice).PixelsPerDip){MaxTextWidth=notice.ActualWidth};
    var tail=notice.ContentEnd.GetCharacterRect(System.Windows.Documents.LogicalDirection.Backward);var bounds=notice.TransformToAncestor(scroll).TransformBounds(new Rect(notice.RenderSize));
    Check(notice.Text==L10n.Text("日期用完整时间或日期（仅日期=午夜）；输入成员命中则整组参与。")&&notice.ActualHeight+.75>=text.Height&&tail.Bottom<=notice.ActualHeight+.75,"r3-complete-notice-line-layout-"+width+"-"+font);
    Check(bounds.Left>=-.75&&bounds.Right<=scroll.ActualWidth+.75&&bounds.Top>=-.75&&bounds.Bottom<=scroll.ActualHeight+.75,"r3-entire-notice-visible-in-task-viewport-"+width+"-"+font);
    measurements.Add(new{width=dialog.ActualWidth,height=dialog.ActualHeight,font,clientWidth=((FrameworkElement)dialog.Content).ActualWidth,clientHeight=((FrameworkElement)dialog.Content).ActualHeight,noticeWidth=notice.ActualWidth,noticeHeight=notice.ActualHeight,formattedHeight=text.Height,tailBottom=tail.Bottom,viewportWidth=scroll.ViewportWidth,viewportHeight=scroll.ViewportHeight});
   }
   dialog.Height=330;dialog.UpdateLayout();notice.BringIntoView();dialog.UpdateLayout();var last=notice.TransformToAncestor(scroll).TransformBounds(notice.ContentEnd.GetCharacterRect(System.Windows.Documents.LogicalDirection.Backward));Check(scroll.ScrollableHeight>0&&last.Bottom<=scroll.ActualHeight+.75&&last.Top>=-.75,"r3-short-dialog-final-clause-reachable-by-existing-vertical-scroll");
   dialog.Activate();var from=Control<TextBox>("RenameDateFrom");var to=Control<TextBox>("RenameDateTo");Check(from.Focus()&&from.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next))&&to.IsKeyboardFocusWithin,"r3-forward-focus-date-from-to");Check(to.MoveFocus(new TraversalRequest(FocusNavigationDirection.Previous))&&from.IsKeyboardFocusWithin,"r3-reverse-focus-date-to-from");dialog.Close();
  }catch(Exception e){modalError=e;dialog?.Close();}});M3Call("M3InputSettings");await visit;if(modalError is not null)throw modalError;
  var grid=Control<DataGrid>("RenamePreview");
  async Task Cells(string raw,string phase){await Responsive();var rows=grid.Items.Cast<object>().ToArray();Check(rows.Length>0,"r3-"+phase+"-real-result-rows");foreach(var row in rows){grid.ScrollIntoView(row,grid.Columns[3]);grid.UpdateLayout();await Responsive();var cell=grid.Columns[3].GetCellContent(row) as TextBlock;var status=row.GetType().GetProperty("Status")!.GetValue(row)?.ToString();Check(status==raw&&cell?.Text==L10n.Text(raw)&&(L10n.Language=="zh-Hans"||cell.Text!=raw),"r3-"+phase+"-rendered-cell-translated-model-original");}if(L10n.Language=="en")Check(((TextBlock)grid.Columns[3].GetCellContent(rows[0])).Text==raw switch{"预览；尚未执行"=>"Preview; not executed","无需更名"=>"No rename needed","已更名"=>"Renamed","未执行"=>"Not executed",_=>"Awaiting restore"},"r3-"+phase+"-english-exact-status");}
  Input("RenameRules","replace|__absent_r3__|__other_r3__");Action("RefreshRenameOrder");await RenameWait();await Cells("无需更名","no-change-preview");
  Input("RenameRules","prefix|M6R3_");Action("RefreshRenameOrder");await RenameWait();await Cells("预览；尚未执行","preview");
  var preview=grid.Items.Cast<RenameFile>().ToArray();Check(preview.All(f=>f.NewName=="M6R3_"+f.OriginalName),"r3-filenames-not-translated");
  Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan p&&p.Files.Count==3,"r3-real-three-source-freeze");Action("ExecuteRename");await RenameWait();await Cells("已更名","execution");
  var journal=Control<TextBox>("RenameJournalPath").Text;var record=RenameExecutor.ReadJournal(journal);Check(record.Complete&&record.Files.Count==3&&record.Files.All(f=>f.State=="已更名"&&f.Status=="已更名"),"r3-real-journal-model-states-remain-original");
  Action("RestoreRename");await RenameWait();await Cells("已更名","record-restore");foreach(var pair in originals)Check(File.Exists(pair.Key)&&await PhotoDocument.HashAsync(pair.Key)==pair.Value,"r3-source-name-and-full-sha-restored");
  // Render-only fixtures cover safe-to-display partial states without causing interrupted disk writes.
  foreach(var raw in new[]{"未执行","待恢复"}){var row=new RenameOutcome(Path.Combine(folder,"已更名.jpg"),Path.Combine(folder,"预览；尚未执行.jpg"),Path.Combine(folder,"待恢复.jpg"),new string('0',64),raw);var serialized=JsonSerializer.Serialize(row);grid.ItemsSource=new[]{row};await Cells(raw,"render-only-"+raw);Check(row.OriginalName=="已更名.jpg"&&row.NewName=="待恢复.jpg"&&serialized==JsonSerializer.Serialize(row),"r3-display-does-not-translate-user-filenames-or-serialized-state");}
  M3Set("renameSchemeBaseline",M3Call("EditedScheme",Guid.NewGuid(),null));File.WriteAllText(Path.Combine(folder,"m6-r3-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),language=L10n.Language,passed=evidence.Count,measurements,evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
