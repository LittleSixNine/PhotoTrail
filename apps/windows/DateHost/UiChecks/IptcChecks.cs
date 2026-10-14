using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;
static partial class Program
{
 static byte[] Iim(int record,int id,byte[] value)=>new byte[]{28,(byte)record,(byte)id,(byte)(value.Length>>8),(byte)value.Length}.Concat(value).ToArray();
 static async Task<string> IptcFixture(string source,string name,params byte[][] datasets) {
  var file=Path.Combine(folder,name+".jpg");var bytes=await File.ReadAllBytesAsync(source);var data=datasets.SelectMany(x=>x).ToArray();
  // A synthetic legacy fixture has one Photoshop container; two containers correctly provoke a writer warning.
  var clean=new List<byte>(bytes.Take(2));int cursor=2;
  while(cursor<bytes.Length) {
   int start=cursor;cursor++;int marker=bytes[cursor++];if(marker is 218 or 217){clean.AddRange(bytes.Skip(start));break;}
   int size=bytes[cursor]*256+bytes[cursor+1];cursor+=size;if(marker!=237)clean.AddRange(bytes.Skip(start).Take(cursor-start));
  }
  bytes=clean.ToArray();
  var resource="Photoshop 3.0\0"u8.ToArray().Concat("8BIM"u8.ToArray()).Concat(new byte[]{4,4,0,0,0,0,(byte)(data.Length>>8),(byte)data.Length}).Concat(data).Concat(data.Length%2==0?Array.Empty<byte>():new byte[]{0}).ToArray();
  var app13=new byte[]{255,237,(byte)((resource.Length+2)>>8),(byte)(resource.Length+2)}.Concat(resource);
  await File.WriteAllBytesAsync(file,bytes.Take(2).Concat(app13).Concat(bytes.Skip(2)).ToArray());return file;
 }
 static async Task R04bChecks() {
  var rows=await DateCoreRows(5);var client=InspectorTool();var docs=rows.Select(Doc).ToArray();var jpeg=docs.Single(d=>Path.GetFileName(d.FilePath)=="embedded.jpg");
  var original=jpeg.SourceHash;var pixels=await MetadataCopy.JpegPixelsAsync(jpeg.FilePath);Check(jpeg.Iptc!.Empty,"true-absent-IPTC-raw-source");
  var list=Control<ListBox>("Photos");list.SelectedItems.Clear();list.SelectedItems.Add(rows.Single(r=>ReferenceEquals(Doc(r),jpeg)));
  Check(Control<CheckBox>("IptcHeadlineApply").IsEnabled,"production-IPTC-editor-JPEG-enabled");
  foreach(var pair in MetadataIptc.Fields) {
   var (tag,f)=pair;string text=tag.EndsWith("Code")?"cHn":new string('a',f.Limit);var value=f.List?MetadataFields.FormatList([text]):text;
   PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,value}});Check(true,"UTF8-exact-limit-"+tag);
   R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,text+"a"}}),"UTF8-over-one-byte-"+tag);
   R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,"\0"}}),"NUL-reject-"+tag);
   R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,"\ud800"}}),"invalid-UTF16-UTF8-reject-"+tag);
   if(!tag.EndsWith("Code")) {
    var multi=new string('a',f.Limit-4)+"😀";PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,multi}});Check(true,"emoji-byte-boundary-"+tag);
    R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,multi+"a"}}),"multibyte-over-one-"+tag);
   }
  }
  foreach(var bad in new[]{"12A","US","CHNN","中"})R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IPTC:Country-PrimaryLocationCode",bad}}),"country-ASCII-exact-three-"+bad);
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IPTC:Keywords","[\"a\",\"\"]"}}),"empty-list-element-reject");
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IPTC:Keywords","[]"}}),"empty-IPTC-list-setting-not-implicit-clear");
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IPTC:Keywords",JsonSerializer.Serialize(Enumerable.Repeat("a",257))}}),"list-resource-limit-257");
  var changes=MetadataIptc.Fields.Keys.ToDictionary(t=>t,t=>t.EndsWith("Code")?"cHn":MetadataFields.IsList(t)?MetadataFields.FormatList(["中文,日本é😀","second,element","line1\nline2"]):"中文 日本 é😀 e\u0301\nline");
  jpeg.SetDraft(changes);try{await MetadataXmp.ExportAsync(client,jpeg,Path.Combine(folder,"IPTC-rejected.xmp"));throw new Exception("IPTC exported as XMP");}catch(ArgumentException){}Check(!File.Exists(Path.Combine(folder,"IPTC-rejected.xmp")),"IPTC-draft-XMP-export-refused-no-file");var target=Path.Combine(folder,"copies");Directory.CreateDirectory(target);
  var output=await MetadataCopy.SaveAsync(client,jpeg,target);var saved=await PhotoDocument.LoadAsync(client,output,inspect:true);
  Check(saved.Iptc!.Utf8,"new-IPTC-standard-UTF8-declaration");
  foreach(var tag in changes.Keys)Check(saved.Value(tag)==changes[tag],"real-set-list-order-and-text-"+tag);
  Check(await PhotoDocument.HashAsync(jpeg.FilePath)==original&&jpeg.Draft.Count==12,"copy-source-SHA-unchanged-draft-retained");
  Check(await MetadataCopy.JpegPixelsAsync(output)==pixels,"IPTC-copy-pixel-payload-protected");
  saved.SetDraft(new Dictionary<string,string>{{"IPTC:Caption-Abstract","line1\r\nline2"},{"IPTC:Headline","既有UTF8更新"},{"IPTC:Keywords",MetadataFields.FormatList(["duplicate","duplicate","line\nvalue"])}});var updatedFolder=Path.Combine(folder,"updated");Directory.CreateDirectory(updatedFolder);var updated=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,saved,updatedFolder));Check(updated.Iptc!.Utf8&&updated.Value("IPTC:Headline")=="既有UTF8更新","existing-UTF8-setting-keeps-declaration");Check(MetadataFields.List(updated.Value("IPTC:Keywords")).SequenceEqual(new[]{"duplicate","duplicate","line\nvalue"}),"IPTC-list-duplicate-order-kept");Check(updated.Value("IPTC:Caption-Abstract")=="line1\r\nline2","IPTC-CRLF-exact-byte-readback");saved.ClearDraft();
  var preset=MetadataPreset.Create("IPTC fixed",changes);var decoded=MetadataPreset.Decode(preset.Encode());var fresh=await PhotoDocument.LoadAsync(client,jpeg.FilePath);decoded.Apply(fresh);Check(fresh.Draft.Count==12&&fresh.Value("IPTC:Keywords")==changes["IPTC:Keywords"],"IPTC-preset-v1-list-boundaries-roundtrip");
  var authorized=MetadataCsv.Snapshot([await PhotoDocument.LoadAsync(client,jpeg.FilePath)]);var csv=MetadataCsv.Load(MetadataCsv.Export(MetadataCsv.Snapshot([jpeg])),authorized);Check(csv.Changes.Values.Single()["IPTC:Keywords"]==changes["IPTC:Keywords"],"IPTC-CSV-list-elements-roundtrip");
  R04Refusal(()=>MetadataCsv.Load(MetadataCsv.Export(MetadataCsv.Snapshot([jpeg])).Replace("IPTC:Headline","IPTC:CodedCharacterSet"),authorized),"controlled-encoding-not-open-in-CSV");
  R04Refusal(()=>MetadataPreset.Create("invalid",new Dictionary<string,string>{{"IPTC:City",new string('a',33)}}),"IPTC-preset-over-byte-limit-atomic");
  R04Refusal(()=>MetadataPreset.Validate(new("IPTC:Headline","copy","IFD0:Artist")),"no-new-cross-source-IPTC-EXIF-copy");
  Check(MetadataClipboard.Prepare(changes["IPTC:Keywords"],["IPTC:Keywords"])["IPTC:Keywords"]==changes["IPTC:Keywords"],"IPTC-clipboard-list-boundaries");
  saved.SetDraft(MetadataIptc.Fields.Keys.ToDictionary(t=>t,_=>""));var clearFolder=Path.Combine(folder,"cleared");Directory.CreateDirectory(clearFolder);var cleared=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,saved,clearFolder));
  foreach(var tag in changes.Keys)Check(cleared.Value(tag)=="","real-clear-exact-"+tag);Check(cleared.Iptc!.Utf8,"clear-keeps-declaration");
  var utf8=Iim(1,90,[27,37,71]);var version=Iim(2,0,[0,4]);
  var cases=new Dictionary<string,byte[][]>{["record-version-only"]=[version],["ASCII-undeclared"]=[version,Iim(2,105,"ASCII"u8.ToArray())],["nonASCII-undeclared"]=[version,Iim(2,90,[0xe9,0xe0])],["other-declaration"]=[Iim(1,90,[27,37,47,65]),version],["conflict-declarations"]=[utf8,Iim(1,90,[27,37,47,65]),version]};
  foreach(var (name,data) in cases) {
   var f=await IptcFixture(jpeg.FilePath,name,data);var doc=await PhotoDocument.LoadAsync(client,f);long rev=doc.DraftRevision;
   R04Refusal(()=>doc.SetDraft(new Dictionary<string,string>{{"IPTC:Headline","new"},{"XMP-dc:Title","other"}}),"encoding-reject-whole-apply-"+name);Check(doc.Draft.Count==0&&doc.DraftRevision==rev,"encoding-reject-atomic-"+name);
   R04Refusal(()=>doc.SetDraft(new Dictionary<string,string>{{"IPTC:Headline",""},{"IPTC:Keywords","new"}}),"encoding-reject-mixed-clear-set-"+name);Check(doc.Draft.Count==0,"mixed-clear-set-no-partial-"+name);
   doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","independent"}});Check(doc.Draft.Count==1,"unknown-encoding-independent-XMP-"+name);
  }
  var declaredOnly=await PhotoDocument.LoadAsync(client,await IptcFixture(jpeg.FilePath,"UTF8-only-envelope",utf8));declaredOnly.SetDraft(new Dictionary<string,string>{{"IPTC:Headline","new application"}});var declaredDir=Path.Combine(folder,"declared-copy");Directory.CreateDirectory(declaredDir);var declaredResult=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,declaredOnly,declaredDir));Check(declaredResult.Iptc!.Utf8&&declaredResult.Value("IPTC:Headline")=="new application","existing-UTF8-new-application-version-proved");
  var legacy=await PhotoDocument.LoadAsync(client,await IptcFixture(jpeg.FilePath,"legacy-clear",version,Iim(2,105,"delete me"u8.ToArray()),Iim(2,90,[0xe9,0xe0]),Iim(2,202,[255,128,0,33])));
  legacy.SetDraft(new Dictionary<string,string>{{"IPTC:Headline",""}});var legacyDir=Path.Combine(folder,"legacy-copies");Directory.CreateDirectory(legacyDir);var legacyResult=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,legacy,legacyDir));
  Check(legacyResult.Value("IPTC:Headline")==""&&!legacyResult.Iptc!.Utf8,"undeclared-pure-delete-no-declaration");legacy.Iptc!.Verify(legacyResult.Iptc!,legacy.Draft);Check(true,"legacy-remaining-nonASCII-unknown-datasets-raw-bytes-preserved");
  var duplicate=await PhotoDocument.LoadAsync(client,await IptcFixture(jpeg.FilePath,"duplicate-target",utf8,version,Iim(2,105,"one"u8.ToArray()),Iim(2,105,"two"u8.ToArray())));R04Refusal(()=>duplicate.SetDraft(new Dictionary<string,string>{{"IPTC:Headline","new"}}),"repeated-real-scalar-dataset-readonly");
  var changedPath=Path.Combine(folder,"source-changed.jpg");File.Copy(jpeg.FilePath,changedPath);var changed=await PhotoDocument.LoadAsync(client,changedPath);await client.RunAsync(["-overwrite_original","-IPTC:Headline=external","--",changedPath]);long changedRev=changed.DraftRevision;try{await changed.SetDraftAsync(new Dictionary<string,string>{{"IPTC:Headline","later"}});throw new Exception("changed encoding source accepted");}catch(IOException){}Check(changed.Draft.Count==0&&changed.DraftRevision==changedRev,"source-encoding-change-before-apply-rejected");
  foreach(var d in docs.Where(d=>d.SidecarPath is not null||d.FileType=="XMP"||d.FileType=="DNG"))R04Refusal(()=>d.SetDraft(new Dictionary<string,string>{{"IPTC:Headline","blocked"}}),"sidecar-RAW-IPTC-reference-readonly-"+d.FileType);
  var opaquePath=await IptcFixture(jpeg.FilePath,"opaque-app13",version);var opaqueBytes=await File.ReadAllBytesAsync(opaquePath);int signature=Encoding.ASCII.GetString(opaqueBytes).IndexOf("Photoshop 3.0",StringComparison.Ordinal);opaqueBytes[signature]=(byte)'X';await File.WriteAllBytesAsync(opaquePath,opaqueBytes);var opaque=await PhotoDocument.LoadAsync(client,opaquePath);Check(!MetadataFields.CanEdit(opaque,"IPTC:Headline")&&opaque.Iptc!.Error.Length>0,"opaque-APP13-not-misclassified-as-no-IPTC");opaque.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","independent"}});Check(opaque.Draft.Count==1,"opaque-container-independent-XMP-draft-allowed");
  var latePath=await IptcFixture(jpeg.FilePath,"late-second-IPTC",utf8,version);var lateBytes=await File.ReadAllBytesAsync(latePath);int firstSize=lateBytes[4]*256+lateBytes[5];var segment=lateBytes.Skip(2).Take(firstSize+2).ToArray();await File.WriteAllBytesAsync(latePath,lateBytes.Take(lateBytes.Length-2).Concat(segment).Concat(lateBytes.TakeLast(2)).ToArray());Check((await MetadataIptc.ReadAsync(latePath,default)).Error.Length>0,"IPTC-after-image-scan-second-block-not-ignored");
  var stale=jpeg.BatchSnapshot();stale.InspectionError="synthetic full-source read failure";R04Refusal(()=>stale.StageDraft(new Dictionary<string,string>{{"IPTC:Headline","blocked"}}),"IPTC-complete-source-read-failure-not-missing");
  Directory.CreateDirectory(Path.Combine(folder,"future"));var frozen=SavePlan.Prepare([jpeg],SaveMode.Copy,SaveScope.All,Path.Combine(folder,"future"),[jpeg]).Items.Single();jpeg.SetDraft(new Dictionary<string,string>{{"IFD0:Artist","residual EXIF"}});R04Refusal(()=>SavePlan.Require(frozen),"IPTC-frozen-revision-changed");jpeg.ClearDraft();
  Control<CheckBox>("IptcHeadlineApply").IsChecked=true;Input("IptcHeadlineValue","原生字段中文é😀");Control<CheckBox>("IptcKeywordsApply").IsChecked=true;Input("IptcKeywordsValue","[\"comma,element\",\"line1\\nline2\"]");await Apply("ApplyDraft");Check(jpeg.Draft.Count==2,"production-controls-direct-IPTC-apply");
  Action("UndoLastApply");Check(jpeg.Draft.Count==0,"production-IPTC-undo");Control<CheckBox>("IptcHeadlineApply").IsChecked=true;Input("IptcHeadlineValue","原生字段中文é😀");Control<CheckBox>("IptcKeywordsApply").IsChecked=true;Input("IptcKeywordsValue","[\"comma,element\",\"line1\\nline2\"]");await Apply("ApplyDraft");Check(jpeg.Draft.Count==2,"production-IPTC-reapply");
  var copyUi=Path.Combine(folder,"ui-copies");Directory.CreateDirectory(copyUi);Input("OutputFolder",copyUi);Action("SaveCopies");Check(Control<TextBox>("SaveSummary").Text.Contains("IPTC:Headline")&&Control<TextBox>("SaveSummary").Text.Contains("IPTC UTF8首次声明"),"IPTC-summary-exact-fields-and-controlled-encoding");Action("CancelSavePlan");Check(!Directory.EnumerateFiles(copyUi).Any()&&jpeg.Draft.Count==2,"IPTC-summary-cancel-no-write");
  Control<ComboBox>("SaveModeChoice").SelectedIndex=2;var backup=Path.Combine(folder,"backups");Directory.CreateDirectory(backup);Input("BackupFolder",backup);Action("PrepareSaveAll");Action("ExecuteSavePlan");await BatchWait();var result=((List<SidecarResult>)Field("saveResults")!).Single();Check(result.State=="成功"&&result.Document!.Draft.Count==0,"IPTC-production-inplace-adoption-clears-proved");
  var record=InplaceHistory.Read(InplaceHistory.PathFor(result.RecordId!));Check(await PhotoDocument.HashAsync(record.Backup)==original,"IPTC-inplace-full-backup-original-SHA");result.Document!.SetDraft(PhotoDocument.PositionChanges(new MapPoint(12,34),null,"MANUAL"));Control<CheckBox>("ExifArtistApply").IsChecked=true;Input("ExifArtistValue","later EXIF");Control<CheckBox>("TitleApply").IsChecked=true;Input("TitleValue","later XMP");await Apply("ApplyDraft");Control<ComboBox>("InplaceRecords").SelectedIndex=0;Action("ShowInplaceRecord");Action("RestoreInplaceRecord");await BatchWait();Check(await PhotoDocument.HashAsync(jpeg.FilePath)==original&&await MetadataCopy.JpegPixelsAsync(jpeg.FilePath)==pixels,"IPTC-record-restore-full-original-SHA-pixels");Check(InplaceHistory.Read(InplaceHistory.PathFor(record.Id)).Phase=="restored","IPTC-record-restored-phase");var restored=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).Single(d=>d.FilePath==jpeg.FilePath);Check(restored.Draft.ContainsKey("XMP-exif:GPSLatitude")&&restored.Draft["IFD0:Artist"]=="later EXIF"&&restored.Draft["XMP-dc:Title"]=="later XMP","restore-protects-later-GPS-EXIF-XMP-drafts");File.WriteAllText(Path.Combine(folder,"later-drafts.local.json"),JsonSerializer.Serialize(restored.Draft));Action("UndoDraft");Check(restored.Draft.Count==0,"owned-test-drafts-cleared-after-retained-snapshot");
  File.WriteAllText(Path.Combine(folder,"r04b-results.json"),JsonSerializer.Serialize(new{buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),checks=evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("R04B="+evidence.Count);
 }
 static async Task R04bScale() {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R02_COUNT")!);var rows=await DateCoreRows(count);var list=Control<ListBox>("Photos");foreach(var row in rows)list.SelectedItems.Add(row);
  long ex=ExifToolClient.RequestCount,host=DateAdapter.StartedProcesses;double gap=0;var last=Stopwatch.GetTimestamp();var timer=new DispatcherTimer(TimeSpan.FromMilliseconds(25),DispatcherPriority.Normal,(_,_)=>{var now=Stopwatch.GetTimestamp();gap=Math.Max(gap,Stopwatch.GetElapsedTime(last,now).TotalMilliseconds);last=now;},window.Dispatcher);timer.Start();
  var precheck=Stopwatch.StartNew();foreach(var row in rows)MetadataFields.Require(Doc(row),new Dictionary<string,string>{{"IPTC:Headline","中文 IPTC é😀"},{"IPTC:Keywords","[\"comma,element\",\"line1\\nline2\"]"}});precheck.Stop();
  Control<CheckBox>("IptcHeadlineApply").IsChecked=true;Input("IptcHeadlineValue","中文 IPTC é😀");Control<CheckBox>("IptcKeywordsApply").IsChecked=true;Input("IptcKeywordsValue","[\"comma,element\",\"line1\\nline2\"]");var watch=Stopwatch.StartNew();await Apply("ApplyDraft");var edit=watch.Elapsed.TotalMilliseconds;long editEx=ExifToolClient.RequestCount-ex,editHost=DateAdapter.StartedProcesses-host;
  foreach(var row in rows)for(int i=0;i<100;i++)_ = Doc(row).Value("IPTC:Headline");Check(ExifToolClient.RequestCount-ex==editEx,"IPTC-getter-no-process");
  var output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("PrepareSaveAll");var save=Stopwatch.StartNew();Action("ExecuteSavePlan");await BatchWait();save.Stop();timer.Stop();Check(((List<SidecarResult>)Field("saveResults")!).Count(r=>r.State=="成功")==count,"IPTC-scale-all-copy-success");
  File.WriteAllText(Path.Combine(folder,"r04b-scale.json"),JsonSerializer.Serialize(new{count,encodingPrecheckMs=precheck.Elapsed.TotalMilliseconds,encodingPrecheckScope="cached production encoding/type/source eligibility; excludes initial raw source import and later mandatory repeated checks",editMs=edit,saveMs=save.Elapsed.TotalMilliseconds,editExifToolRequests=editEx,editDateHostRequests=editHost,exifToolRequests=ExifToolClient.RequestCount-ex,dateHostRequests=DateAdapter.StartedProcesses-host,maxDispatcherGapMs=gap,buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),checks=evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("R04B_SCALE="+count);
 }
}
