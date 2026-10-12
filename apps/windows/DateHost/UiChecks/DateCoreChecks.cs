using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task<object[]> DateCoreRows(int count)
 {
  var clock=Stopwatch.StartNew();
  var list=Control<ListBox>("Photos");
  for(int i=0;i<12000&&(list.Items.Count<count||(bool)Field("busy")!);i++)await Task.Delay(10);
  Check(list.Items.Count==count,"date-core-real-import-"+count);
  evidence.Add(new{importReadyMs=clock.Elapsed.TotalMilliseconds,scope="loaded-event observation, excludes pre-event import time"});
  return list.Items.Cast<object>().ToArray();
 }
 static async Task DateCoreCopies()
 {
  var all=await DateCoreRows(4);var list=Control<ListBox>("Photos");
  var rows=all.Where(r=>!Doc(r).FilePath.EndsWith("-raw.xmp",StringComparison.OrdinalIgnoreCase)).ToArray();
  Check(rows.Length==3,"JPEG-existing-DNG-sidecar-XMP-chain");
  list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  var docs=rows.Select(Doc).ToArray();
  SelectMetadataTab("批量日期");
  foreach(int mode in Enumerable.Range(0,5)) {
   foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","earlier title"},{"XMP-dc:Rights","earlier rights"}});
   var before=Drafts(rows);Control<ComboBox>("DateMode").SelectedIndex=mode;
   foreach(string field in new[]{"DateYears","DateMonths","DateDays","DateHours","DateMinutes"})Input(field,"0");
   Input("DateSeconds","1");Input("DateStart","2024:01:01 00:00:00.123456789-00:00");
   Input("DateEnd","2024:01:01 00:00:05.123456789-00:00");Input("DateStep","2");Input("DateReplaceHour","13");
   await Apply("ApplyDates");Check(docs.All(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal"))&&Status.Contains("修改3张"),"five-mode-apply-statistics-"+mode);
   Check(docs.All(d=>d.Value("XMP-dc:Rights")=="earlier rights"),"five-mode-other-draft-kept-"+mode);
   var applied=docs.Select(d=>d.Value("XMP-exif:DateTimeOriginal")).ToArray();
   Action("UndoLastApply");Check(SameDrafts(rows,before),"five-mode-complete-undo-"+mode);
   await Apply("ApplyDates");Check(docs.Select(d=>d.Value("XMP-exif:DateTimeOriginal")).SequenceEqual(applied),"five-mode-reapply-"+mode);
   string output=Path.Combine(folder,"copies-"+mode);Directory.CreateDirectory(output);Input("OutputFolder",output);
   var save=Stopwatch.StartNew();Action("SaveCopies");await BatchWait();double saveMs=save.Elapsed.TotalMilliseconds;
   Check(Status.Contains("副本成功 3，失败 0"),"five-mode-explicit-save-"+mode);
   var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var verify=Stopwatch.StartNew();
   for(int i=0;i<docs.Length;i++) {
    var d=docs[i];string copy=Path.Combine(output,Path.GetFileName(d.FilePath));
    var read=await PhotoDocument.LoadAsync(client,copy);
    Check(read.Value("XMP-exif:DateTimeOriginal")==applied[i]&&read.Value("XMP-dc:Title")=="earlier title"&&read.Value("XMP-dc:Rights")=="earlier rights","five-mode-ExifTool-readback-"+mode+"-"+d.FileType);
    Check(await PhotoDocument.HashAsync(d.FilePath)==d.SourceHash&&(d.SidecarPath is null||await PhotoDocument.HashAsync(d.SidecarPath)==d.SidecarHash),"five-mode-source-and-sidecar-"+mode+"-"+d.FileType);
    var original=d.Sidecar??d.Embedded;var result=read.Sidecar??read.Embedded;
    foreach(var field in original.EnumerateObject()) {
     if(d.Draft.ContainsKey(field.Name)||field.Name.StartsWith("File:")||field.Name.StartsWith("System:")||field.Name.StartsWith("ExifTool:")||field.Name.StartsWith("Composite:")||field.Name is "SourceFile" or "XMP-x:XMPToolkit" or "XMP-xmpNote:HasExtendedXMP")continue;
     Check(result.TryGetProperty(field.Name,out var retained)&&field.Value.GetRawText()==retained.GetRawText(),"five-mode-nontarget-"+mode+"-"+d.FileType+"-"+field.Name);
    }
    Check(result.TryGetProperty("XMP-dc:Title-fr",out var french)&&french.GetString()=="titre francais","five-mode-other-language-"+mode+"-"+d.FileType);
    if(d.SidecarPath is not null)Check(await PhotoDocument.HashAsync(copy)==d.SourceHash,"five-mode-RAW-copy-bytes-"+mode);
    else if(d.FileType=="JPEG")Check(await MetadataCopy.JpegPixelsAsync(copy)==await MetadataCopy.JpegPixelsAsync(d.FilePath),"five-mode-JPEG-pixels-"+mode);
   }
   evidence.Add(new{mode,saveMs,verifyMs=verify.Elapsed.TotalMilliseconds,phases=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!)});
   Action("UndoDraft");
  }
  DateCoreResult("date-core-copy-results.json");
 }
 static async Task DateCoreScale()
 {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R01_COUNT")!);var rows=await DateCoreRows(count);var docs=rows.Select(Doc).ToArray();
  var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var readClock=Stopwatch.StartNew();
  var reread=new List<PhotoReadResult>();
  foreach(var chunk in docs.Select(d=>d.FilePath).Chunk(32))reread.AddRange(await PhotoDocument.LoadBatchAsync(client,chunk));
  Check(reread.All(r=>r.Document is not null),"scale-measured-ExifTool-batch-read");
  double readMs=readClock.Elapsed.TotalMilliseconds;
  Control<ListBox>("Photos").SelectAll();SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=0;Input("DateSeconds","1");
  foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","scale earlier rights"}});
  var before=Drafts(rows);var applyClock=Stopwatch.StartNew();await Apply("ApplyDates");double applyMs=applyClock.Elapsed.TotalMilliseconds;
  Check(docs.All(d=>d.Draft.ContainsKey("XMP-exif:DateTimeOriginal")),"scale-full-apply");var phases=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);
  Action("UndoLastApply");Check(SameDrafts(rows,before),"scale-complete-undo");await Apply("ApplyDates");
  string output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);var saveClock=Stopwatch.StartNew();Action("SaveCopies");await BatchWait();double saveMs=saveClock.Elapsed.TotalMilliseconds;
  Check(Status.Contains("副本成功 "+count+"，失败 0"),"scale-save-all");var verify=Stopwatch.StartNew();
  foreach(var d in docs){var read=await PhotoDocument.LoadAsync(client,Path.Combine(output,Path.GetFileName(d.FilePath)));Check(read.Value("XMP-exif:DateTimeOriginal")==d.Value("XMP-exif:DateTimeOriginal")&&read.Value("XMP-dc:Rights")=="scale earlier rights"&&await PhotoDocument.HashAsync(d.FilePath)==d.SourceHash,"scale-copy-source-readback");}
  evidence.Add(new{count,readMs,applyMs,phases,saveMs,verifyMs=verify.Elapsed.TotalMilliseconds,readScope="separate exact-count ExifTool batch reread; UI startup/import observed separately",pollMilliseconds=25});
  Action("UndoDraft");DateCoreResult("date-core-scale-results.json");
 }
 static async Task DateCoreMismatch()
 {
  var rows=await DateCoreRows(3);Control<ListBox>("Photos").SelectAll();var docs=rows.Select(Doc).ToArray();
  foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","preserved mismatch draft"}});
  var before=Drafts(rows);string host=Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe");
  var original=File.ReadAllBytes(host);
  try{File.Copy(Environment.GetEnvironmentVariable("PHOTOTRAIL_R01_WRONG_HOST")!,host,true);SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=0;Input("DateSeconds","1");await Apply("ApplyDates");
   Check(Status.Contains("sourceMismatch")&&SameDrafts(rows,before),"production-source-mismatch-no-partial-drafts");
  }finally{File.WriteAllBytes(host,original);}
  foreach(var d in docs)Check(await PhotoDocument.HashAsync(d.FilePath)==d.SourceHash,"mismatch-source-unchanged");
  Action("UndoDraft");DateCoreResult("date-core-mismatch-results.json");
 }
 static void DateCoreResult(string name)
 {
  File.WriteAllText(Path.Combine(folder,name),JsonSerializer.Serialize(new{passed=evidence.Count,evidence,
   source=typeof(MainWindow).Assembly.GetType("PhotoTrail.Windows.DatePagePreview")!.GetField("Source",BindingFlags.NonPublic|BindingFlags.Static)!.GetValue(null),
   buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location)))},new JsonSerializerOptions{WriteIndented=true}));
  Console.WriteLine("DATE_CORE_WPF="+evidence.Count);
 }
}
