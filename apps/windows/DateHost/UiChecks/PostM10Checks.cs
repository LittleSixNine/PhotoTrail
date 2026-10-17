using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PostM10Checks(){
  await ImportDone();var tool=(ExifToolClient)M3Call("Tool")!;var rows=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).ToArray();
  var results=new List<object>();
  foreach(var input in rows){
   var doc=await PhotoDocument.LoadAsync(tool,input.FilePath,inspect:true);var hash=await PhotoDocument.HashAsync(doc.FilePath);var properties=PostProperties(doc.FilePath);
   var output=Path.Combine(folder,"format-"+Path.GetFileName(doc.FilePath));Directory.CreateDirectory(output);
   if(doc.CanEdit){doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","POSTM9 合法 format"}});await doc.SetDraftAsync(new Dictionary<string,string>{{doc.MainDateTag,"2024:02:03 04:05:06.123456+08:00"}});var saved=await MetadataCopy.SaveAsync(tool,doc,output);var reopened=await PhotoDocument.LoadAsync(tool,saved,inspect:true);Check(reopened.Value("XMP-dc:Title")=="POSTM9 合法 format"&&reopened.Value(doc.MainDateTag).Contains("123456",StringComparison.Ordinal),"M10-format-copy-and-reopen-"+Path.GetFileName(doc.FilePath));
    if(doc.SidecarPath is not null)Check(await PhotoDocument.HashAsync(saved)==hash,"M10-paired-copy-preserves-image-bytes-"+doc.FileType);
    results.Add(new{sample=Path.GetFileName(doc.FilePath),doc.FileType,read=true,copy=true,actualTarget=doc.SidecarPath is null?"embedded":"sidecar",sourcePreserved=true});
   }else{Check(!doc.CanEdit,"M10-unqualified-embedded-write-remains-closed-"+doc.FileType);results.Add(new{sample=Path.GetFileName(doc.FilePath),doc.FileType,read=true,copy=false,reason="qualification guard"});}
   Check(await PhotoDocument.HashAsync(doc.FilePath)==hash&&WindowsRename.SameProperties(properties,PostProperties(doc.FilePath)),"M10-source-SHA-identity-times-attributes-ACL-"+Path.GetFileName(doc.FilePath));
  }
  var xmp=rows.First(d=>d.FileType=="XMP");var location=await PhotoDocument.LoadAsync(tool,xmp.FilePath,inspect:true);location.SetDraft(PhotoDocument.PositionChanges(new(12,52),null,"MANUAL"));var positioned=Path.Combine(folder,"xmp-positioned");Directory.CreateDirectory(positioned);var positionedPath=await MetadataCopy.SaveAsync(tool,location,positioned);var clear=await PhotoDocument.LoadAsync(tool,positionedPath,inspect:true);var originalDate=clear.Value(clear.MainDateTag);clear.StageLocationClear();Check(clear.ClearLocationRequested&&clear.Draft.Count>0,"M10-standalone-XMP-explicit-clear-intent");var clearOutput=Path.Combine(folder,"xmp-cleared");Directory.CreateDirectory(clearOutput);var clearPath=await MetadataCopy.SaveAsync(tool,clear,clearOutput);var cleared=await PhotoDocument.LoadAsync(tool,clearPath,inspect:true);Check(cleared.Position()is null&&cleared.Value(cleared.MainDateTag)==originalDate,"M10-standalone-XMP-clear-save-reopen-no-fallback-date-preserved");
  var jpeg=rows.First(d=>d.FileType=="JPEG"&&d.SidecarPath is null);
  var deep=Path.Combine(folder,"deep");while(deep.Length<310)deep=Path.Combine(deep,"directory-1234567890");Directory.CreateDirectory(deep);
  var source=Path.Combine(deep,"deep.jpg");File.Copy(jpeg.FilePath,source);var loaded=await PhotoDocument.LoadAsync(tool,source,inspect:true);loaded.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","deep-path-safe"}});
  var deepOutput=Path.Combine(deep,"out");Directory.CreateDirectory(deepOutput);var copied=await MetadataCopy.SaveAsync(tool,loaded,deepOutput);Check((await PhotoDocument.LoadAsync(tool,copied)).Value("XMP-dc:Title")=="deep-path-safe","M10-real-over-MAX_PATH-copy-reopens");
  var backup=Path.Combine(deep,"backup");Directory.CreateDirectory(backup);var plan=SavePlan.Prepare([loaded],SaveMode.Inplace,SaveScope.All,"",[loaded]);var proof=await VerifiedMetadataDates.CreateAsync(loaded.Draft,CancellationToken.None);var inplace=await InplaceSave.SaveAsync(tool,plan.Items.Single(),backup,proof,CancellationToken.None);Check(inplace.Document is not null,"M10-real-deep-TxF-inplace-readback");
  var record=InplaceHistory.ReadAll().Single(r=>r.Id==inplace.RecordId);InplaceHistory.Append(record with{Phase="saved"});await InplaceHistory.RestoreAsync(tool,record,CancellationToken.None);SelectRecovery(record.Id);Action("CheckInplaceRecord");await BatchWait();Check(await PhotoDocument.HashAsync(source)==loaded.SourceHash,"M10-real-deep-TxF-restore-original-SHA");
  File.WriteAllText(Path.Combine(folder,"postm10-results.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),formats=results,evidence},new JsonSerializerOptions{WriteIndented=true}));
 }
}
