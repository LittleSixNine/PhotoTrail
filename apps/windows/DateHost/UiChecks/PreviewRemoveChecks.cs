using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task RemoveSettled(){for(int i=0;i<1600&&(bool)Field("busy")!;i++)await Task.Delay(25);Check(!(bool)Field("busy")!,"remove-undo-settled");}
 static async Task R06bChecks()
 {
  await ImportDone();var seed=R06Rows().Single(r=>Path.GetFileName(Doc(r).FilePath)=="embedded.jpg");
  var root=Path.Combine(folder,"preview-remove");Directory.CreateDirectory(root);
  var pairJpeg=Path.Combine(root,"pair.jpg");var pairRaw=Path.Combine(root,"pair.DNG");File.Copy(Doc(seed).FilePath,pairJpeg);File.Copy(Path.Combine(folder,"inputs","raw.DNG"),pairRaw);
  var png=Path.Combine(root,"real.png");using(var stream=File.Create(png)){var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(PixelsImage(128,64)));encoder.Save(stream);}
  var tiff=Path.Combine(root,"real.tiff");using(var stream=File.Create(tiff)){var encoder=new TiffBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(PixelsImage(128,64)));encoder.Save(stream);}
  var disguised=Path.Combine(root,"png.jpg");File.Copy(png,disguised);
  await ImportMore(pairJpeg,pairRaw,png,tiff,disguised);var rows=R06Rows();var list=Control<ListBox>("Photos");
  var jpeg=rows.Single(r=>Doc(r).FilePath==pairJpeg);var raw=rows.Single(r=>Doc(r).FilePath==pairRaw);
  Check(rows.Any(r=>Doc(r).FilePath==disguised&&Doc(r).FileType=="PNG"),"actual-content-not-extension-selects-decoder");
  foreach(var row in rows.Where(r=>new[]{pairJpeg,pairRaw,png,tiff,disguised}.Contains(Doc(r).FilePath)))
  {
   var doc=Doc(row);var hash=await PhotoDocument.HashAsync(doc.FilePath);var times=SourceTimes.Read(doc.FilePath);
   foreach(var size in new[]{80,1024}){var image=await window.LoadThumbnailAsync(doc,size,1,size==1024,CancellationToken.None);Check(image.IsFrozen&&Math.Max(image.PixelWidth,image.PixelHeight)<=size,"small-large-decode-"+doc.FileType+"-"+size);}
   Check(await PhotoDocument.HashAsync(doc.FilePath)==hash&&SourceTimes.Read(doc.FilePath)==times,"preview-no-file-write-"+doc.FileType);
  }
  Doc(jpeg).SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","kept JPEG"}});Doc(raw).SelectSidecarEditing(true);Doc(raw).SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","kept RAW"}});
  var revisions=new[]{Doc(jpeg).DraftRevision,Doc(raw).DraftRevision};var before=R06Rows();list.SelectedItems.Clear();list.SelectedItems.Add(jpeg);await Task.Delay(100);
  Input("TitleValue","unapplied");Action("RemovePhotos");Check(R06Rows().Length==before.Length&&Control<TextBox>("TitleValue").Text=="unapplied","unapplied-input-blocks-remove");
  typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
  typeof(MainWindow).GetField("busy",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,true);Action("RemovePhotos");Check(R06Rows().Length==before.Length,"save-busy-blocks-remove");typeof(MainWindow).GetField("busy",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,false);
  Action("RemovePhotos");Check(!R06Rows().Contains(jpeg)&&!R06Rows().Contains(raw)&&Doc(raw).Draft.Count==1&&Doc(jpeg).Draft.Count==1,"paired-remove-preserves-actual-drafts");
  Check(!Control<ListBox>("PhotoStrip").Items.Cast<object>().Contains(jpeg)&&!window.ThumbnailConsumerCurrent(Doc(jpeg)),"removed-members-not-visible-or-thumbnail-consumers");
  Action("UndoRemovePhotos");await RemoveSettled();Check(R06Rows().SequenceEqual(before)&&revisions.SequenceEqual(new[]{Doc(jpeg).DraftRevision,Doc(raw).DraftRevision})&&list.SelectedItems.Contains(jpeg),"undo-restores-order-selection-revisions-and-pair-objects");
  foreach(var row in new[]{jpeg,raw})Check(await PhotoDocument.HashAsync(Doc(row).FilePath)==Doc(row).SourceHash,"remove-undo-source-hash-unchanged");
  list.SelectedItems.Clear();list.SelectedItems.Add(seed);await Task.Delay(100);typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);Action("RemovePhotos");
  await ImportMore(Doc(seed).FilePath);await Task.Delay(100);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);int count=R06Rows().Length;Action("UndoRemovePhotos");await RemoveSettled();Check(R06Rows().Length==count&&!R06Rows().Contains(seed)&&Status.Contains("重复"),"reimport-refuses-duplicate-writable-identity");
  var current=R06Rows().Single(r=>Doc(r).FilePath==png);list.SelectedItems.Clear();list.SelectedItems.Add(current);await Task.Delay(100);Action("RemovePhotos");var moved=png+".away";File.Move(png,moved);
  try{Action("UndoRemovePhotos");await RemoveSettled();Check(R06Rows().Contains(current)&&Doc(current).InspectionError.Contains("过期")&&!Doc(current).CanStage,"missing-source-restores-stale-readonly-snapshot");}finally{File.Move(moved,png);}
  list.SelectedItems.Clear();list.SelectedItems.Add(jpeg);await Task.Delay(100);typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);Action("RemovePhotos");File.SetLastWriteTimeUtc(pairJpeg,File.GetLastWriteTimeUtc(pairJpeg).AddSeconds(5));Action("UndoRemovePhotos");await RemoveSettled();Check(Doc(jpeg).InspectionError.Contains("过期")&&!Doc(jpeg).CanStage&&Doc(jpeg).Draft.Count==1,"changed-system-version-restores-draft-but-disables-write");
  var ordered=R06Rows();var later=new[]{ordered.Single(r=>Doc(r).FilePath==tiff),ordered.Single(r=>Doc(r).FilePath==disguised)};
  foreach(var row in later){list.SelectedItems.Clear();list.SelectedItems.Add(row);await Task.Delay(100);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);Action("RemovePhotos");}
  Action("UndoRemovePhotos");await RemoveSettled();Action("UndoRemovePhotos");await RemoveSettled();Check(R06Rows().SequenceEqual(ordered),"consecutive-removals-retain-separate-undo-entries");
  await ThumbnailChecks();
  foreach(var row in R06Rows())Doc(row).ClearDraft();typeof(MainWindow).GetMethod("FillEditor",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
  File.WriteAllText(Path.Combine(folder,"r06b-checks.json"),JsonSerializer.Serialize(new{checks=evidence,buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),cache=((ThumbnailLoader)Field("thumbnailLoader")!).Statistics},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("R06B="+evidence.Count);
 }
 static async Task R06bScale()
 {
  await R06Scale();var rows=R06Rows();var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);await Task.Delay(100);
  typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
  var clock=System.Diagnostics.Stopwatch.StartNew();Action("RemovePhotos");var removeMs=clock.Elapsed.TotalMilliseconds;Check(AllImported.Count==0,"scale-remove-all-members");clock.Restart();Action("UndoRemovePhotos");await RemoveSettled();var undoMs=clock.Elapsed.TotalMilliseconds;Check(R06Rows().SequenceEqual(rows),"scale-undo-all-identities-order");
  File.WriteAllText(Path.Combine(folder,"r06b-remove-scale.json"),JsonSerializer.Serialize(new{count=rows.Length,removeMs,undoMs,checks=evidence,buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location)},new JsonSerializerOptions{WriteIndented=true}));
 }

}
