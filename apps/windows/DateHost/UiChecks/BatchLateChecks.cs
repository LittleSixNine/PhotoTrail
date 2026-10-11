using System.Collections;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task RunBatchLate()
 {
  var list=Control<ListBox>("Photos");for(int i=0;i<1200&&(list.Items.Count<3||(bool)Field("busy")!);i++)await Task.Delay(10);Check(list.Items.Count==3,"late-three-real-XMP-import");list.SelectAll();var rows=list.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();SelectMetadataTab("批量日期");
  foreach(bool failing in new[]{false,true}){
   Control<ComboBox>("DateMode").SelectedIndex=1;Input("DateStart",failing?"2024:02:30 00:00:00":"2024:02:01 00:00:00");var owner=SynchronizationContext.Current!;var gate=new HeldContext(owner);
   try{SynchronizationContext.SetSynchronizationContext(gate);Action("ApplyDates");}finally{SynchronizationContext.SetSynchronizationContext(owner);}await gate.Posted.Task.WaitAsync(TimeSpan.FromSeconds(15));
   Check(docs.All(d=>d.Draft.Count==0),"old-real-compute-not-yet-committed-"+failing);Action("CancelRead");
   // Resume a new real request while the old UI continuation is deliberately still held.
   typeof(MainWindow).GetField("busy",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,false);Input("DateStart","2024:03:01 00:00:00");await Apply("ApplyDates");var after=Drafts(rows);var notice=Status;var summary=Control<TextBlock>("DatePlanPreview").Text;
   gate.Release();await Idle();Check(SameDrafts(rows,after)&&Status==notice&&Control<TextBlock>("DatePlanPreview").Text==summary&&Control<Button>("UndoLastApplyButton").IsEnabled,"late-real-success-or-failure-does-not-overwrite-new-state-"+failing);Action("UndoLastApply");Check(docs.All(d=>d.Draft.Count==0),"new-request-undo-after-old-settles-"+failing);
  }
  // Invalid metadata shapes use synthetic production documents; no fake date host or calculation.
  var collection=(IList)Field("photos")!;var ctor=typeof(PhotoDocument).GetConstructors(BindingFlags.NonPublic|BindingFlags.Instance).Single();var rowType=rows[0].GetType();
  foreach(var shape in new[]{"empty","type","illegal","readonly"}){
   var fields=JsonSerializer.Deserialize<Dictionary<string,JsonElement>>(docs[0].Embedded.GetRawText())!;
   fields[shape=="readonly"?"File:FileType":"XMP-exif:DateTimeOriginal"]=JsonSerializer.SerializeToElement(shape switch{"empty"=>"","illegal"=>"2024:02:30 10:20:30","readonly"=>"TIFF",_=>null});if(shape=="type")fields["XMP-exif:DateTimeOriginal"]=JsonSerializer.SerializeToElement(true);
   var doc=(PhotoDocument)ctor.Invoke([docs[0].FilePath,null,JsonSerializer.SerializeToElement(fields),null,docs[0].SourceHash,null]);var row=Activator.CreateInstance(rowType,doc)!;list.SelectedItems.Clear();collection.Clear();collection.Add(row);foreach(var original in rows.Skip(1))collection.Add(original);list.SelectAll();Control<ComboBox>("DateMode").SelectedIndex=0;Input("DateSeconds","1");await Apply("ApplyDates");
   Check(doc.Draft.Count==0&&docs.Skip(1).All(d=>d.Draft.Count==0)&&!Status.Contains("应用完成"),"invalid-source-not-missing-skip-"+shape);
  }
  list.SelectedItems.Clear();collection.Clear();foreach(var row in rows)collection.Add(row);list.SelectAll();
  bool atomic=true;Action changed=()=>atomic&=docs.All(d=>d.Value("XMP-dc:Title")=="atomic title");var evt=typeof(PhotoDocument).GetEvent("DraftChanged",BindingFlags.NonPublic|BindingFlags.Instance)!;foreach(var d in docs)evt.GetAddMethod(true)!.Invoke(d,[changed]);
  Input("TitleValue","atomic title");await Apply("ApplyDraft");foreach(var d in docs)evt.GetRemoveMethod(true)!.Invoke(d,[changed]);Check(atomic,"every-draft-observer-sees-complete-batch");
  docs[0].SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","later edit"}});var later=Drafts(rows);Action("UndoLastApply");Check(SameDrafts(rows,later),"expired-undo-does-not-remove-later-edit");Action("UndoDraft");
  // No-op target is still source-checked for ordinary fields, with earlier undo untouched.
  Input("TitleValue","valid undo");await Apply("ApplyDraft");var preview=new MapPoint(11,22);typeof(MainWindow).GetField("currentPreview",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,preview);Input("TitleValue","valid undo");Control<CheckBox>("TitleApply").IsChecked=true;await Apply("ApplyDraft");Check(ReferenceEquals(Field("currentPreview"),preview),"no-op-does-not-clear-location-preview");var existing=Drafts(rows);var bytes=File.ReadAllBytes(docs[1].FilePath);File.AppendAllText(docs[1].FilePath," ");Input("TitleValue","valid undo");Control<CheckBox>("TitleApply").IsChecked=true;await Apply("ApplyDraft");Check(SameDrafts(rows,existing)&&Status.Contains("改变")&&Control<CheckBox>("TitleApply").IsChecked==true&&Control<TextBox>("TitleValue").Text=="valid undo","ordinary-noop-source-change-rejects-all-keeps-input");File.WriteAllBytes(docs[1].FilePath,bytes);Action("UndoLastApply");Check(docs.All(d=>d.Draft.Count==0),"failed-source-check-keeps-valid-undo");
  foreach(var d in docs)Check(await PhotoDocument.HashAsync(d.FilePath)==d.SourceHash,"late-check-source-hash");
  File.WriteAllText(Path.Combine(folder,"batch-late-results.json"),JsonSerializer.Serialize(new{evidence,passed=evidence.Count},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("BATCH_LATE_WPF="+evidence.Count);
 }
}
