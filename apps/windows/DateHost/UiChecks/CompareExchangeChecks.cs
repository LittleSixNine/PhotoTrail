using System.Data;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static void RefreshCompareSelection(object[] rows)
 {
  var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
 }
 static async Task R07Checks()
 {
  await ImportDone();var originals=R06Rows();var seed=originals.Single(r=>Path.GetFileName(Doc(r).FilePath)=="embedded.jpg");
  var root=Path.Combine(folder,"comparison");Directory.CreateDirectory(root);for(int i=0;i<100;i++)File.Copy(Doc(seed).FilePath,Path.Combine(root,$"compare-{i:D3}.jpg"));await ImportMore(root);
  var rows=R06Rows().Where(r=>Path.GetFileName(Doc(r).FilePath).StartsWith("compare-",StringComparison.Ordinal)).ToArray();Check(rows.Length==100,"comparison-all-100-imported");
  Control<TabItem>("ComparisonTab").IsSelected=true;
  var performance=new List<object>();
  foreach(var count in new[]{1,20,21,100})
  {
   var clock=Stopwatch.StartNew();RefreshCompareSelection(rows.Take(count).ToArray());await Task.Delay(150);typeof(MainWindow).GetMethod("RefreshComparison",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
   var compareMs=clock.Elapsed.TotalMilliseconds;var view=(DataView)Control<DataGrid>("ComparisonGrid").ItemsSource;Check(view.Table!.Columns.Count==3+Math.Min(20,count)*2&&((PhotoDocument[])Field("comparisonSelection")!).Length==count,"compare-cap-only-display-entire-freeze-"+count);
   var documents=rows.Take(count).Select(Doc).ToArray();var records=MetadataCsv.Snapshot(documents);Check(MetadataCsv.Load(MetadataCsv.Export(records),records).Changes.Count==0,"full-frozen-CSV-no-op-roundtrip-"+count);
   var changed=records.Select(r=>r with{Cells=new Dictionary<string,string>(r.Cells){["XMP-dc:Title"]=JsonSerializer.Serialize("全部冻结 "+count)}}).ToArray();var path=Path.Combine(folder,"all-"+count+".csv");MetadataCsv.WriteNew(path,MetadataCsv.Export(changed));Control<TextBox>("CsvPath").Text=path;clock.Restart();Action("ApplyCsv");await Idle();var applyMs=clock.Elapsed.TotalMilliseconds;performance.Add(new{count,compareMs,applyMs,displayed=Math.Min(20,count)});
   Check(documents.All(d=>d.Value("XMP-dc:Title")=="全部冻结 "+count),"CSV-apply-does-not-stop-at-displayed-20-"+count);
   typeof(MainWindow).GetMethod("RefreshComparison",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);view=(DataView)Control<DataGrid>("ComparisonGrid").ItemsSource;var title=view.Table!.Rows.Cast<DataRow>().Single(r=>r[0].ToString()=="XMP-dc:Title"&&r[1].ToString()=="原图");Check(title[3].ToString()!=title[4].ToString()&&title[4].ToString()=="全部冻结 "+count,"compare-disk-effective-separated-"+count);
   Action("UndoLastApply");Check(documents.All(d=>d.Draft.Count==0),"CSV-whole-selection-undo-"+count);
  }
  RefreshCompareSelection(rows.Take(2).ToArray());await Task.Delay(150);var pair=rows.Take(2).Select(Doc).ToArray();var authorized=MetadataCsv.Snapshot(pair);string Q(string value)=>"\""+value.Replace("\"","\"\"")+"\"";
  string Csv(params string[][] values)=>string.Join("\r\n",values.Select(v=>string.Join(',',v.Select(Q))))+"\r\n";
  var invalidDate=Csv(["PhotoTrail CSV 1","RelativePath","XMP-dc:Title-x-default","XMP-exif:DateTimeOriginal"],[authorized[0].Id,authorized[0].RelativePath,JsonSerializer.Serialize("no partial title"),JsonSerializer.Serialize("2024:02:30 12:00:00Z")],[authorized[1].Id,authorized[1].RelativePath,JsonSerializer.Serialize("valid peer"),JsonSerializer.Serialize("2024:02:29 12:00:00Z")]);
  var badPath=Path.Combine(folder,"invalid-date-peer.csv");MetadataCsv.WriteNew(badPath,invalidDate);Control<TextBox>("CsvPath").Text=badPath;Action("ApplyCsv");await Idle();Check(pair[0].Draft.Count==0&&pair[1].Value("XMP-dc:Title")=="valid peer"&&Status.Contains("无效值跳过1行"),"shared-date-invalid-row-skips-all-its-fields-valid-peer-applies");Action("UndoLastApply");
  var client=InspectorTool();pair[0].SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","draft differs from disk"}});var disk=Path.Combine(folder,"disk-only.xmp");var effective=Path.Combine(folder,"with-draft.xmp");await MetadataXmp.ExportDiskAsync(client,pair[0],disk);await MetadataXmp.ExportAsync(client,pair[0],effective);Check((await PhotoDocument.LoadAsync(client,disk)).Value("XMP-dc:Title")!="draft differs from disk"&&(await PhotoDocument.LoadAsync(client,effective)).Value("XMP-dc:Title")=="draft differs from disk"&&pair[0].Draft.Count==1,"disk-XMP-and-draft-XMP-distinct-source-and-draft-retained");
  var copies=Path.Combine(folder,"copies");Directory.CreateDirectory(copies);var copy=await MetadataCopy.SaveAsync(client,pair[0],copies);Check((await PhotoDocument.LoadAsync(client,copy)).Value("XMP-dc:Title")==pair[0].Value("XMP-dc:Title")&&await MetadataCopy.JpegPixelsAsync(copy)==await MetadataCopy.JpegPixelsAsync(pair[0].FilePath),"CSV-JPEG-copy-independent-field-and-pixel-readback");pair[0].ClearDraft();
  var side=originals.Select(Doc).Single(d=>Path.GetFileName(d.FilePath)=="paired.jpg");side.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","sidecar exchange"}});var sideCopy=await MetadataCopy.SaveAsync(client,side,copies);Check((await PhotoDocument.LoadAsync(client,sideCopy)).Value("XMP-dc:Title")=="sidecar exchange"&&await PhotoDocument.HashAsync(side.FilePath)==side.SourceHash&&await PhotoDocument.HashAsync(side.SidecarPath!)==side.SidecarHash,"sidecar-copy-readback-main-and-source-sidecar-unchanged");side.ClearDraft();
  await R05Reject(()=>MetadataXmp.ExportDiskAsync(client,pair[0],disk),"XMP-existing-output-collision-refused");
  var deep=Path.Combine(folder,"deep.xmp");File.WriteAllText(deep,"<x>"+string.Concat(Enumerable.Repeat("<a>",66))+string.Concat(Enumerable.Repeat("</a>",66))+"</x>");await R05Reject(()=>MetadataXmp.ImportAsync(client,deep),"XMP-structure-depth-refused-before-tool");
  var custom=Path.Combine(folder,"custom.xmp");File.WriteAllText(custom,"<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:custom=\"urn:phototrail:unknown\"><dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">valid title</rdf:li></rdf:Alt></dc:title><custom:Data>ignored</custom:Data></rdf:Description></rdf:RDF></x:xmpmeta>");var imported=await MetadataXmp.ImportAsync(client,custom);Check(imported.Changes["XMP-dc:Title"]=="valid title"&&imported.IgnoredTags.Any(t=>t.Contains("urn:phototrail:unknown")),"unknown-XML-family-explicitly-ignored-not-imported");
  var cancelled=new CancellationTokenSource();cancelled.Cancel();var cancelledPath=Path.Combine(folder,"cancelled.csv");bool cancel=false;try{MetadataCsv.WriteNew(cancelledPath,"safe",cancelled.Token);}catch(OperationCanceledException){cancel=true;}Check(cancel&&!File.Exists(cancelledPath)&&!Directory.GetFiles(folder,".phototrail-csv-*.tmp").Any(),"cancelled-CSV-only-cleans-owned-output");
  RefreshCompareSelection([rows[0]]);Control<TextBox>("XmpPath").Text=effective;Action("ImportXmp");for(int i=0;i<400&&(bool)Field("busy")!;i++)await Task.Delay(25);Check(Control<TextBlock>("XmpPreview").Text.Contains("冲突")&&Doc(rows[0]).Draft.Count==0,"production-XMP-import-preview-conflict-before-explicit-apply");Action("ApplyDraft");await Idle();Check(Doc(rows[0]).Value("XMP-dc:Title")=="draft differs from disk","production-XMP-explicit-apply");Action("UndoLastApply");
  RefreshCompareSelection(originals);typeof(MainWindow).GetMethod("RefreshComparison",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);var mixedView=(DataView)Control<DataGrid>("ComparisonGrid").ItemsSource;Check(mixedView.Table!.Rows.Cast<DataRow>().Any(row=>row[2].ToString()=="混合（含缺失）")&&mixedView.Table.Rows.Cast<DataRow>().Any(row=>row[2].ToString()=="缺失"),"comparison-distinguishes-mixed-and-missing-with-exact-source-rows");
  var sourceRow=R06Rows().Single(r=>Doc(r).FilePath==pair[0].FilePath);RefreshCompareSelection([sourceRow]);await Task.Delay(150);var held=Doc(sourceRow);var missing=held.FilePath+".away";File.Move(held.FilePath,missing);
  try{Action("RereadPhotos");await BatchWait();typeof(MainWindow).GetMethod("RefreshComparison",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);var failedView=(DataView)Control<DataGrid>("ComparisonGrid").ItemsSource;Check(held.InspectionError.Length>0&&failedView.Table!.Rows.Cast<DataRow>().Any(row=>row[2].ToString()=="含读取失败／过期"),"actual-source-loss-shows-failure-not-empty-comparison");}finally{File.Move(missing,held.FilePath);}
  Action("RereadPhotos");await BatchWait();Check(R06Rows().Single(r=>Doc(r).FilePath==held.FilePath) is {} fresh&&Doc(fresh).InspectionError.Length==0,"restored-source-requires-actual-reread-before-editing");
  var fakeMacId=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("/synthetic/mac/compare-000.jpg"))).ToLowerInvariant();var mapRecords=MetadataCsv.Snapshot([Doc(R06Rows().Single(r=>Doc(r).FilePath==held.FilePath))]);
  var otherPlatform=Csv(["PhotoTrail CSV 1","RelativePath","XMP-dc:Title-x-default"],[fakeMacId,mapRecords[0].RelativePath,JsonSerializer.Serialize("mapped fixture")]);Check(MetadataCsv.Load(otherPlatform,mapRecords) is {IdentitySkippedCount:1,Changes.Count:0},"Mac-style-different-absolute-identity-not-silently-authorized");
  var explicitSyntheticMapping=new Dictionary<string,string>{{fakeMacId,mapRecords[0].Id}};var mapped=Csv(["PhotoTrail CSV 1","RelativePath","XMP-dc:Title-x-default"],[explicitSyntheticMapping[fakeMacId],mapRecords[0].RelativePath,JsonSerializer.Serialize("mapped fixture")]);Check(MetadataCsv.Load(mapped,mapRecords).Changes.Count==1,"explicit-test-only-approved-identity-map-still-validates-authorized-relative-path");
  foreach(var row in R06Rows()){Check(await PhotoDocument.HashAsync(Doc(row).FilePath)==Doc(row).SourceHash,"source-SHA-preserved-after-exchange");Doc(row).ClearDraft();}typeof(MainWindow).GetMethod("RefreshSelection",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);
  File.WriteAllText(Path.Combine(folder,"r07-checks.json"),JsonSerializer.Serialize(new{checks=evidence,buildSha=await PhotoDocument.HashAsync(typeof(MainWindow).Assembly.Location),comparisonLimit=20,performance},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("R07="+evidence.Count);
 }
}
