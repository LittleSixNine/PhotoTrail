using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 static readonly string[] SharedTags={"XMP-exif:DateTimeOriginal","XMP-exif:DateTimeDigitized","XMP-xmp:CreateDate","XMP-xmp:ModifyDate"};
 static Dictionary<string,string> SharedChanges(string value)=>SharedTags.ToDictionary(tag=>tag,_=>value);
 static void EditedFields(Dictionary<string,string> changes)=>Invoke("FillEditor",changes);
 static async Task SharedInput(string entry,PhotoDocument[] docs,Dictionary<string,string> changes) {
  if(entry=="fields"){EditedFields(changes);await Apply("ApplyDraft");}
  else if(entry=="csv"){
   var records=MetadataCsv.Snapshot(docs).Select(record=>record with{Cells=new Dictionary<string,string>(record.Cells).Concat(changes.Where(pair=>!record.Cells.ContainsKey(pair.Key)).Select(pair=>new KeyValuePair<string,string>(pair.Key,JsonSerializer.Serialize(pair.Value)))).ToDictionary(pair=>pair.Key,pair=>pair.Value)}).ToArray();
   records=records.Select(record=>record with{Cells=record.Cells.ToDictionary(pair=>pair.Key,pair=>changes.TryGetValue(pair.Key,out var value)?JsonSerializer.Serialize(value):pair.Value)}).ToArray();
   string path=Path.Combine(folder,"input-"+Guid.NewGuid().ToString("N")+".csv");MetadataCsv.WriteNew(path,MetadataCsv.Export(records,false));Input("CsvPath",path);await Apply("ApplyCsv");
  }else if(entry=="clipboard"){
   EditedFields(changes);Clipboard.SetText(changes[SharedTags[0]]);Action("PasteFields");await BatchWait();await Apply("ApplyDraft");
  }else if(entry=="xmp"){
   var exif="";var xmp="";foreach(var pair in changes.Where(p=>SharedTags.Contains(p.Key))){var element=pair.Key.Split(':')[1];var xmlDate=pair.Value[..4]+"-"+pair.Value[5..7]+"-"+pair.Value[8..10]+"T"+pair.Value[11..];if(pair.Key.StartsWith("XMP-exif"))exif+="<exif:"+element+">"+xmlDate+"</exif:"+element+">";else xmp+="<xmp:"+element+">"+xmlDate+"</xmp:"+element+">";}
   string path=Path.Combine(folder,"input-"+Guid.NewGuid().ToString("N")+".xmp");File.WriteAllText(path,"<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description rdf:about='' xmlns:exif='http://ns.adobe.com/exif/1.0/' xmlns:xmp='http://ns.adobe.com/xap/1.0/'>"+exif+xmp+"</rdf:Description></rdf:RDF></x:xmpmeta>");Input("XmpPath",path);Action("ImportXmp");await BatchWait();Check(Status.Contains("已载入编辑区"),"shared-XMP-input-import-valid-ISO-lexical");await Apply("ApplyDraft");
  }else {Invoke("SetPresetChain",MetadataPreset.Create("共享日期"+entry,changes));await Apply("ApplyPreset");}
 }
 static async Task SharedFault() {
  var all=await DateCoreRows(4);var rows=all.Where(r=>!Doc(r).FilePath.EndsWith("-raw.xmp",StringComparison.OrdinalIgnoreCase)).ToArray();var docs=rows.Select(Doc).ToArray();var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","keep before failure"}});var before=Drafts(rows);
  EditedFields(new(){{SharedTags[0],"2024:02:29 11:22:33.123456789Z"},{"XMP-dc:Title","must not partially apply"}});await Apply("ApplyDraft");Check(SameDrafts(rows,before)&&!Status.Contains("应用完成"),"shared-host-failure-refuses-whole-batch");
  EditedFields(new(){{"XMP-dc:Title","unrelated title permitted"}});await Apply("ApplyDraft");Check(docs.All(doc=>doc.Value("XMP-dc:Title")=="unrelated title permitted"),"shared-host-failure-does-not-block-unrelated-title");Action("UndoLastApply");Check(SameDrafts(rows,before),"shared-host-failure-unrelated-title-undo");Action("UndoDraft");DateCoreResult("r01b-fault-results.json");
 }
 static async Task SharedEntries() {
  var all=await DateCoreRows(4);var rows=all.Where(r=>!Doc(r).FilePath.EndsWith("-raw.xmp",StringComparison.OrdinalIgnoreCase)).ToArray();var docs=rows.Select(Doc).ToArray();var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  const string modern="2024:02:29 11:22:33.123456789-00:00";var changes=SharedChanges(modern);
  foreach(string entry in new[]{"fields","csv","clipboard","xmp","preset"}) {
   foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","earlier rights"}});var before=Drafts(rows);
   await SharedInput(entry,docs,changes);Check(docs.All(doc=>SharedTags.All(tag=>doc.Value(tag)==modern))&&Status.Contains("修改3张"),"shared-"+entry+"-four-fields-statistics");Check(docs.All(doc=>doc.Value("XMP-dc:Rights")=="earlier rights"),"shared-"+entry+"-earlier-draft");
   Action("UndoLastApply");Check(SameDrafts(rows,before),"shared-"+entry+"-complete-undo");await SharedInput(entry,docs,changes);
   string output=Path.Combine(folder,"copies-"+entry);Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");await BatchWait();Check(Status.Contains("副本成功 3，失败 0"),"shared-"+entry+"-explicit-copy");
   var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
   foreach(var doc in docs){var copy=await PhotoDocument.LoadAsync(client,Path.Combine(output,Path.GetFileName(doc.FilePath)));Check(SharedTags.All(tag=>copy.Value(tag)==modern)&&copy.Value("XMP-dc:Rights")=="earlier rights","shared-"+entry+"-date-text-readback-"+doc.FileType);Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash&&(doc.SidecarPath is null||await PhotoDocument.HashAsync(doc.SidecarPath)==doc.SidecarHash),"shared-"+entry+"-source-sidecar");
    var original=doc.Sidecar??doc.Embedded;var saved=copy.Sidecar??copy.Embedded;foreach(var field in original.EnumerateObject()){if(doc.Draft.ContainsKey(field.Name)||field.Name.StartsWith("File:")||field.Name.StartsWith("System:")||field.Name.StartsWith("ExifTool:")||field.Name.StartsWith("Composite:")||field.Name is "SourceFile" or "XMP-x:XMPToolkit" or "XMP-xmpNote:HasExtendedXMP")continue;Check(saved.TryGetProperty(field.Name,out var value)&&value.GetRawText()==field.Value.GetRawText(),"shared-"+entry+"-nontarget-"+field.Name);}
    if(doc.SidecarPath is not null)Check(await PhotoDocument.HashAsync(copy.FilePath)==doc.SourceHash,"shared-"+entry+"-RAW-bytes");else if(doc.FileType=="JPEG")Check(await MetadataCopy.JpegPixelsAsync(copy.FilePath)==await MetadataCopy.JpegPixelsAsync(doc.FilePath),"shared-"+entry+"-JPEG-pixels");
   }Action("UndoDraft");
  }
  foreach(var invalid in new[]{"1582:10:05 00:00:00","2023:02:29 00:00:00","2024:01:01 00:00:00+14:01"," 2024:01:01 00:00:00","2024:01:01 00:00:00.1234567890"}) {
   foreach(string entry in new[]{"fields","csv","preset"}){var before=Drafts(rows);var bad=SharedChanges(invalid);bad["XMP-dc:Title"]="must not apply";await SharedInput(entry,docs,bad);Check(SameDrafts(rows,before),"shared-"+entry+"-invalid-entire-batch-"+invalid);EditedFields(new());}
  }
  foreach(var historical in new[]{"1582:10:04 00:00:00","1582:10:15 00:00:00","1500:02:29 00:00:00"}){await SharedInput("fields",docs,SharedChanges(historical));Check(docs.All(doc=>doc.Value(SharedTags[0])==historical),"shared-history-accepted-"+historical);Action("UndoLastApply");}
  foreach(var tag in SharedTags){await SharedInput("fields",docs,new(){{tag,""}});Check(docs.All(doc=>doc.Value(tag)==""),"shared-explicit-clear-"+tag);Action("UndoLastApply");}
  Invoke("SetPresetChain",MetadataPreset.Create("有序日期复制",new[]{new MetadataOperation("XMP-dc:Title","setText",modern),new MetadataOperation(SharedTags[0],"copy","XMP-dc:Title"),new MetadataOperation(SharedTags[1],"copy",SharedTags[0]),new MetadataOperation(SharedTags[2],"copy",SharedTags[1]),new MetadataOperation(SharedTags[3],"copy",SharedTags[2]),new MetadataOperation("XMP-dc:Title","setText","after date copy")}));await Apply("ApplyPreset");Check(docs.All(doc=>SharedTags.All(tag=>doc.Value(tag)==modern)&&doc.Value("XMP-dc:Title")=="after date copy"),"shared-copy-consumes-previous-step-multiple-recipients");Action("UndoLastApply");
  Invoke("SetPresetChain",MetadataPreset.Create("固定先验",new[]{new MetadataOperation(SharedTags[0],"fillMissingText","1582:10:05 00:00:00")}));var noChange=Drafts(rows);await Apply("ApplyPreset");Check(SameDrafts(rows,noChange)&&Status.Contains("未应用"),"shared-fixed-invalid-param-not-bypassed-when-filled");
  Invoke("SetPresetChain",MetadataPreset.Create("非法动态复制",new[]{new MetadataOperation("XMP-dc:Title","setText","not a date"),new MetadataOperation(SharedTags[0],"copy","XMP-dc:Title"),new MetadataOperation(SharedTags[0],"setText",modern)}));await Apply("ApplyPreset");Check(SameDrafts(rows,noChange)&&Status.Contains("未应用"),"shared-invalid-intermediate-copy-not-erased-by-later-valid-set");
  EditedFields(new());Invoke("SetPresetChain",new MetadataPreset("新预设",Array.Empty<MetadataOperation>()));Action("UndoDraft");DateCoreResult("r01b-entry-results.json");
 }
}
