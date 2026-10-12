using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static async Task RunOrderedCopies()
 {
  var list=Control<ListBox>("Photos");for(int i=0;i<1200&&(list.Items.Count<4||(bool)Field("busy")!);i++)await Task.Delay(10);Check(list.Items.Count==4,"ordered-copy-JPEG-DNG-sidecar-XMP-import");var rows=list.Items.Cast<object>().Where(r=>Path.GetFileName(Doc(r).FilePath)!="raw.xmp").ToArray();foreach(var row in rows)list.SelectedItems.Add(row);var docs=rows.Select(Doc).ToArray();var before=Drafts(rows);const string title="XMP-dc:Title",description="XMP-dc:Description";
  var preset=MetadataPreset.Create("副本多步",new MetadataOperation[]{new(title,"copy",description),new(title,"appendText","·追加"),new(description,"copy",title),new("XMP-dc:Creator","replaceAuthors","A\nA\nB"),new("XMP-dc:Subject","replaceKeywords","A\na"),new("XMP-dc:Subject","appendKeywords","A\né\né"),new("XMP-dc:Subject","removeKeywords","a")});
  typeof(MainWindow).GetMethod("SetUnsavedPreset",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,[preset]);Action("SaveNewMetadataPreset");var unchanged=Drafts(rows);Action("CopyMetadataPreset");Input("PresetLibraryRenameName","副本多步改名");Action("RenameMetadataPreset");Action("UpdateMetadataPreset");Check(SameDrafts(rows,unchanged)&&docs.All(d=>File.Exists(d.FilePath)),"full-library-management-keeps-photo-drafts");var libraryList=Control<ListBox>("MetadataPresetList");libraryList.SelectedIndex=-1;libraryList.SelectedIndex=0;Check(Library()[0].Preset.Operations.SequenceEqual(preset.Operations)&&docs.All(d=>d.Draft.Count==0),"library-save-load-no-drafts");var expected=docs.ToDictionary(d=>d.FilePath,d=>d.Value(description)+"·追加");await Apply("ApplyPreset");Check(docs.All(d=>d.Value(title)==expected[d.FilePath]&&d.Value(description)==expected[d.FilePath]&&d.Value("XMP-dc:Creator")=="A\nA\nB"&&d.Value("XMP-dc:Subject")=="A\né\né"),"production-multi-step-list-copy-effective-drafts");
  Action("UndoLastApply");Check(SameDrafts(rows,before),"production-copy-full-undo-before-save");await Apply("ApplyPreset");
  var sources=new List<object>();var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);string output=Path.Combine(folder,"output");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");await BatchWait();Check(Status.Contains("副本成功 3，失败 0"),"explicit-production-save-three-independent-copies");
  foreach(var doc in docs){string copy=Path.Combine(output,Path.GetFileName(doc.FilePath));var read=await PhotoDocument.LoadAsync(client,copy);Check(read.Value(title)==expected[doc.FilePath]&&read.Value(description)==expected[doc.FilePath]&&read.Value("XMP-dc:Creator")=="A\nA\nB"&&read.Value("XMP-dc:Subject")=="A\né\né","ExifTool-readback-targets-"+doc.FileType);Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash&&(doc.SidecarPath is null||await PhotoDocument.HashAsync(doc.SidecarPath)==doc.SidecarHash),"original-and-sidecar-hashes-"+doc.FileType);
   var original=doc.Sidecar??doc.Embedded;var result=read.Sidecar??read.Embedded;foreach(var field in original.EnumerateObject()){if(doc.Draft.ContainsKey(field.Name)||field.Name.StartsWith("File:")||field.Name.StartsWith("System:")||field.Name.StartsWith("ExifTool:")||field.Name.StartsWith("Composite:")||field.Name is "SourceFile" or "XMP-x:XMPToolkit" or "XMP-xmpNote:HasExtendedXMP")continue;Check(result.TryGetProperty(field.Name,out var retained)&&field.Value.GetRawText()==retained.GetRawText(),"non-target-preserved-"+doc.FileType+"-"+field.Name);}
   Check(result.TryGetProperty("XMP-dc:Title-fr",out var french)&&french.GetString()=="titre francais","other-language-x-default-boundary-"+doc.FileType);
   if(doc.SidecarPath is not null)Check(await PhotoDocument.HashAsync(copy)==doc.SourceHash,"RAW-original-copy-byte-identical");else if(doc.FileType=="JPEG")Check(await MetadataCopy.JpegPixelsAsync(copy)==await MetadataCopy.JpegPixelsAsync(doc.FilePath),"JPEG-pixel-payload-identical");
   sources.Add(new{file=Path.GetFileName(doc.FilePath),sourceHash=doc.SourceHash,sidecarHash=doc.SidecarHash,outputHash=await PhotoDocument.HashAsync(copy),copy});
  }
  Check(!Control<Button>("UndoLastApplyButton").IsEnabled,"saving-expired-undo");Action("UndoDraft");
  File.WriteAllText(Path.Combine(folder,"ordered-copy-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence,sources,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location)))},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("ORDERED_COPY_WPF="+evidence.Count);
 }
}
