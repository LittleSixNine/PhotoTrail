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
  File.WriteAllText(Path.Combine(folder,"missing-direct-results.json"),JsonSerializer.Serialize(new{evidence,passed=evidence.Count}));Console.WriteLine("MISSING_DIRECT_WPF="+evidence.Count);
 }
}
