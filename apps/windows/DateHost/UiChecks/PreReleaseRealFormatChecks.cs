using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using PhotoTrail.Windows;

static partial class Program
{
 static async Task PreReleaseRealFormatChecks()
 {
  await ImportDone();var tool=InspectorTool();var documents=Control<ListBox>("Photos").Items.Cast<object>().Select(Doc).ToArray();
  var results=new List<object>();
  foreach(var doc in documents)
  {
   var hash=await PhotoDocument.HashAsync(doc.FilePath);
   // Initial asynchronous thumbnail extraction legitimately holds a read handle.
   for(int attempt=0;;attempt++){try{_ = PostProperties(doc.FilePath);break;}catch(IOException)when(attempt<50){await Task.Delay(100);}}
   var before=PostProperties(doc.FilePath);
   Check(doc.FileType=="DNG"&&doc.InspectionError.Length==0,"real-camera-DNG-read-not-extension-only");
   bool preview=false;string previewReason="";try{var bitmap=await PhotoPreview.LoadDngAsync(tool,doc.FilePath,hash,1);preview=bitmap.PixelWidth>0;}catch(Exception error){previewReason=error.GetType().Name+": "+error.Message;}
   bool rawWic=false;string wicReason="";try{using var f=File.OpenRead(doc.FilePath);var bitmap=BitmapDecoder.Create(f,BitmapCreateOptions.None,BitmapCacheOption.OnLoad);rawWic=bitmap.Frames[0].PixelWidth>0;}catch(Exception error){wicReason=error.GetType().Name+": "+error.Message;}
   if(doc.SidecarPath is null)
   {
    Check(!doc.CanEdit&&!doc.CanStage&&doc.CanCreateSidecar,"real-DNG-embedded-write-closed-new-sidecar-explicit");
    doc.SelectSidecarEditing(true);doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","Synthetic real DNG sidecar"}});
    var item=SavePlan.Prepare([doc],SaveMode.NewSidecar,SaveScope.Metadata,"",[doc]).Items.Single();
    var saved=await SavePlan.CreateAsync(tool,item,await VerifiedMetadataDates.CreateAsync(item.Fields),CancellationToken.None);
    var reloaded=await PhotoDocument.LoadAsync(tool,doc.FilePath,inspect:true);
    Check(File.Exists(item.Target)&&reloaded.Value("XMP-dc:Title")=="Synthetic real DNG sidecar","real-DNG-new-sidecar-independent-reload");
    doc.ClearDraft();
   }
   else
   {
    Check(doc.CanEdit&&doc.CanStage,"real-DNG-existing-sidecar-edit-qualified");
    doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","Synthetic paired real DNG"}});
    string output=Path.Combine(folder,"paired-copy");Directory.CreateDirectory(output);var target=await MetadataCopy.SaveAsync(tool,doc,output);
    var copy=await PhotoDocument.LoadAsync(tool,target,inspect:true);
    Check(copy.Value("XMP-dc:Title")=="Synthetic paired real DNG"&&await PhotoDocument.HashAsync(target)==hash,"real-DNG-sidecar-copy-keeps-raw-SHA");
    var plan=SavePlan.Prepare([doc],SaveMode.Inplace,SaveScope.Metadata,"",documents);var backup=Path.Combine(folder,"real-DNG-backups");Directory.CreateDirectory(backup);
    var saved=await InplaceSave.SaveAsync(tool,plan.Items.Single(),backup,await VerifiedMetadataDates.CreateAsync(doc.Draft),CancellationToken.None);
    Check(saved.Document is not null&&saved.RecordId is not null,"real-DNG-sidecar-inplace-independent-adoption");
    var record=InplaceHistory.Read(InplaceHistory.PathFor(saved.RecordId!));await InplaceHistory.RestoreAsync(tool,record,CancellationToken.None);
    var current=InplaceHistory.Read(InplaceHistory.PathFor(record.Id));var restored=await PhotoDocument.LoadAsync(tool,doc.FilePath,inspect:true);
    Check(restored.Value("XMP-dc:Title")=="Synthetic paired title"&&await PhotoDocument.HashAsync(current.Target)==current.OriginalHash,"real-DNG-sidecar-restore-independent-readback");
    InplaceHistory.Append(current with{Phase="restored"});doc.ClearDraft();
   }
   bool clearRefused=false;try{var clean=await PhotoDocument.LoadAsync(tool,doc.FilePath,inspect:true);clean.StageLocationClear();}catch(InvalidOperationException){clearRefused=true;}
   Check(clearRefused,"real-DNG-location-clear-unqualified-remains-refused");
   Check(await PhotoDocument.HashAsync(doc.FilePath)==hash&&WindowsRename.SameProperties(before,PostProperties(doc.FilePath)),"real-DNG-source-bytes-and-properties-preserved");
   results.Add(new{file=Path.GetFileName(doc.FilePath),doc.FileType,preview,previewReason,rawWic,wicReason,decoderNote="embedded JPEG preview and optional OS WIC decode are separate from raw demosaic support"});
  }
  SaveResult("pre-release-real-formats.json",results);
 }
}
