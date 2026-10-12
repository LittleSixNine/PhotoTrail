using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program {
 static async Task SharedProtection() {
  var all=await DateCoreRows(4);var rows=all.Where(r=>!Doc(r).FilePath.EndsWith("-raw.xmp",StringComparison.OrdinalIgnoreCase)).ToArray();var docs=rows.Select(Doc).ToArray();var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  var jpeg=docs.Single(d=>d.FileType=="JPEG");var raw=docs.Single(d=>d.SidecarPath is not null);var original=File.ReadAllBytes(jpeg.FilePath);var side=File.ReadAllBytes(raw.SidecarPath!);var added=Path.ChangeExtension(jpeg.FilePath,".xmp");
  foreach(string change in new[]{"source","sidecar","new-sidecar","draft","selection","parameter","save-state"}) {
   foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","keep before invalidation"}});EditedFields(new(){{SharedTags[0],"2024:02:29 12:00:00.123456789-00:00"},{"XMP-dc:Title","must not apply"}});var owner=SynchronizationContext.Current!;var gate=new HeldContext(owner);
   try{SynchronizationContext.SetSynchronizationContext(gate);Action("ApplyDraft");}finally{SynchronizationContext.SetSynchronizationContext(owner);}await gate.Posted.Task.WaitAsync(TimeSpan.FromSeconds(20));
   if(change=="source")File.AppendAllText(jpeg.FilePath," ");if(change=="sidecar")File.AppendAllText(raw.SidecarPath!," ");if(change=="new-sidecar")File.WriteAllBytes(added,side);if(change=="draft")docs[0].SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","later external edit"}});if(change=="selection")list.SelectedItems.Remove(rows[0]);if(change=="parameter")EditedFields(new(){{SharedTags[0],"2024:03:01 00:00:00"}});if(change=="save-state")typeof(MainWindow).GetField("busy",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,false);
   var before=Drafts(rows);gate.Release();await BatchWait();Check(SameDrafts(rows,before)&&!Status.Contains("应用完成"),"shared-whole-batch-state-rejection-"+change);File.WriteAllBytes(jpeg.FilePath,original);File.WriteAllBytes(raw.SidecarPath!,side);if(change=="new-sidecar")File.Delete(added);EditedFields(new());list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);Action("UndoDraft");
  }
  EditedFields(new(){{SharedTags[0],"2024:01:01 00:00:00"}});Clipboard.SetText("1582:10:05 00:00:00");var editor=Control<TextBox>("DateValue").Text;Action("PasteFields");await BatchWait();Check(Control<TextBox>("DateValue").Text==editor&&docs.All(d=>d.Draft.Count==0),"shared-invalid-clipboard-keeps-editor-drafts");EditedFields(new());
  string bad=Path.Combine(folder,"invalid-input.xmp");File.WriteAllText(bad,"<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description rdf:about='' xmlns:exif='http://ns.adobe.com/exif/1.0/'><exif:DateTimeOriginal>1582-10-05T00:00:00</exif:DateTimeOriginal></rdf:Description></rdf:RDF></x:xmpmeta>");Input("XmpPath",bad);Action("ImportXmp");await BatchWait();Check(docs.All(d=>d.Draft.Count==0)&&!Status.Contains("已载入编辑区"),"shared-invalid-XMP-no-partial-editor-drafts");EditedFields(new());DateCoreResult("r01b-protection-results.json");
 }
}
