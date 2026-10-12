using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task RunMissingDirect(){
  var list=Control<ListBox>("Photos");for(int i=0;i<1200&&(list.Items.Count<3||(bool)Field("busy")!);i++)await Task.Delay(10);Check(list.Items.Count==3,"missing-three-real-files");var rows=list.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();var missing=rows.Single(r=>Doc(r).Value("XMP-exif:DateTimeOriginal")=="");list.SelectAll();SelectMetadataTab("批量日期");
  foreach(int mode in new[]{0,2}){
   Control<ComboBox>("DateMode").SelectedIndex=mode;Input("DateSeconds","1");Input("DateReplaceHour","12");Doc(missing).SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","earlier"}});var before=Drafts(rows);await Apply("ApplyDates");Check(Status.Contains("修改2张")&&Status.Contains("缺失时间跳过1项")&&Doc(missing).Draft.Count==1,"missing-mixed-direct-"+mode);Action("UndoLastApply");Check(SameDrafts(rows,before),"missing-whole-batch-undo-"+mode);Action("UndoDraft");
   list.SelectedItems.Clear();list.SelectedItem=missing;await Apply("ApplyDates");Check(Status.Contains("修改0张")&&Status.Contains("缺失时间跳过1项")&&Doc(missing).Draft.Count==0,"missing-all-direct-"+mode);list.SelectAll();
  }
  list.SelectedItems.Clear();list.SelectedItem=missing;Control<ComboBox>("DateMode").SelectedIndex=0;
  var allMissingBefore=Drafts(rows);
  foreach(var boundary in new[]{("DateYears","10000"),("DateMonths","120001"),("DateDays","3660001"),("DateHours","87840001"),("DateMinutes","2147483648"),("DateSeconds","316224000001")}) {
   foreach(string name in new[]{"DateYears","DateMonths","DateDays","DateHours","DateMinutes","DateSeconds"})Input(name,"0");
   Input(boundary.Item1,boundary.Item2);await Apply("ApplyDates");
   Check(SameDrafts(rows,allMissingBefore)&&Status.Contains(boundary.Item1=="DateMinutes"?"整数":"超出"),"all-missing-six-component-bound-"+boundary.Item1);
  }
  foreach(string name in new[]{"DateYears","DateMonths","DateDays","DateHours","DateMinutes","DateSeconds"})Input(name,"0");
  await Apply("ApplyDates");Check(SameDrafts(rows,allMissingBefore)&&Status.Contains("缺失时间跳过1项"),"all-missing-zero-no-op");
  File.WriteAllText(Path.Combine(folder,"missing-direct-results.json"),JsonSerializer.Serialize(new{evidence,passed=evidence.Count}));Console.WriteLine("MISSING_DIRECT_WPF="+evidence.Count);
 }
}
