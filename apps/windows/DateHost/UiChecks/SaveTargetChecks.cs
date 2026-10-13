using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;
static partial class Program
{
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern uint GetShortPathNameW(string path,StringBuilder output,uint capacity);
 static string SaveBuild=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))).ToLowerInvariant();
 static void SaveResult(string name,object? metrics=null)=>File.WriteAllText(Path.Combine(folder,name),JsonSerializer.Serialize(new{buildSha=SaveBuild,checks=evidence,metrics},new JsonSerializerOptions{WriteIndented=true}));
 static async Task ExpectFailure(Func<Task> action,string name){bool rejected=false;try{await action();}catch(Exception e)when(e is IOException or InvalidOperationException or UnauthorizedAccessException or OperationCanceledException){rejected=true;}Check(rejected,name);}
 static void PlanFailure(Action action,string name){bool rejected=false;try{action();}catch(IOException){rejected=true;}Check(rejected,name);}
 static async Task<PhotoDocument> SidecarDoc(string name,string source,ExifToolClient client) {
  var target=Path.Combine(folder,name);Directory.CreateDirectory(Path.GetDirectoryName(target)!);File.Copy(source,target);
  var doc=await PhotoDocument.LoadAsync(client,target);doc.SelectSidecarEditing(true);doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","R03a new title"}});return doc;
 }
 static SaveItem SidecarItem(PhotoDocument doc,SaveScope scope=SaveScope.All)=>SavePlan.Prepare([doc],SaveMode.NewSidecar,scope,"",[doc]).Items.Single();
 static async Task SaveTargetChecks()
 {
  var rows=await DateCoreRows(5);var list=Control<ListBox>("Photos");var client=InspectorTool();
  var docs=rows.Select(Doc).ToArray();string raw=docs.Single(d=>Path.GetFileName(d.FilePath)=="unpaired.DNG").FilePath;string jpeg=docs.Single(d=>Path.GetFileName(d.FilePath)=="embedded.jpg").FilePath;
  var hashes=docs.SelectMany(d=>d.SidecarPath is {} side?new[]{d.FilePath,side}:new[]{d.FilePath}).Distinct().ToDictionary(x=>x,x=>File.ReadAllBytes(x));
  var pixels=await MetadataCopy.JpegPixelsAsync(jpeg);
  var proof=await VerifiedMetadataDates.CreateAsync(Array.Empty<KeyValuePair<string,string>>());
  // Exact production persistence with independent source copies, including adverse file-system outcomes.
  var core=await SidecarDoc("core/new.DNG",raw,client);Check(!core.CanEdit&&core.CanStage,"explicit-RAW-sidecar-only-edit-capability");
  core.SetDraft(PhotoDocument.PositionChanges(new MapPoint(120,30),12.5,"MANUAL"));
  await core.SetDraftAsync(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal","1600:01:02 03:04:05.123456789+05:30"},{"XMP-dc:Rights","retained draft"}});
  var allProof=await VerifiedMetadataDates.CreateAsync(core.Draft);
  var beforeRev=core.DraftRevision;var oldDate=core.VerifiedDate("XMP-exif:DateTimeOriginal");
  var item=SidecarItem(core,SaveScope.Metadata);var created=await SavePlan.CreateAsync(client,item,allProof,CancellationToken.None);
  Check(created.State=="成功"&&created.Document is not null,"RAW-same-directory-nonoverwrite-created-confirmed");var adopted=created.Document!;
  Check(adopted.SidecarPath==Path.ChangeExtension(core.FilePath,".xmp")&&await PhotoDocument.HashAsync(core.FilePath)==core.SourceHash,"RAW-byte-protection-and-real-pair-path");
  Check(adopted.Draft.Keys.All(SavePlan.IsGps)&&adopted.Draft.Count>0&&MetadataInspector.PendingFields(adopted)==1,"metadata-scope-retains-whole-GPS-draft-and-count");
  Check(adopted.Value("XMP-exif:DateTimeOriginal")=="1600:01:02 03:04:05.123456789+05:30"&&adopted.VerifiedDate("XMP-exif:DateTimeOriginal") is not null,"v2-exact-offset-nanoseconds-after-source-adoption");
  Check(adopted.Inspection!.Any(v=>v.Role=="旁车XMP")&&adopted.Inspection!.Any(v=>v.Role=="原图"),"R02-two-source-inspection-after-create");
  var packet=File.ReadAllText(created.Path);Check(packet.Contains("titre francais")&&packet.Contains("unknown namespace")&&packet.Contains("one")&&packet.Contains("alpha"),"full-XMP-alternate-language-unknown-list-preservation");
  Check(!core.CanCreateSidecar||File.Exists(created.Path),"delivered-target-present");await ExpectFailure(()=>SavePlan.CreateAsync(client,item,allProof,CancellationToken.None),"second-create-refuses-existing-sidecar");
  // Invalidated revision, selection-independent plan, whole-batch target conflicts.
  var changed=await SidecarDoc("core/revision.jpg",jpeg,client);var changedItem=SidecarItem(changed);changed.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","later"}});
  await ExpectFailure(()=>SavePlan.CreateAsync(client,changedItem,proof,CancellationToken.None),"revision-change-before-execute-refused");Check(!File.Exists(changedItem.Target),"revision-refusal-writes-nothing");
  var sourceChanged=await SidecarDoc("core/source.jpg",jpeg,client);var sourceItem=SidecarItem(sourceChanged);File.AppendAllText(sourceChanged.FilePath,"external");await ExpectFailure(()=>SavePlan.CreateAsync(client,sourceItem,proof,CancellationToken.None),"source-SHA-change-refused");
  var same1=await SidecarDoc("conflict/same.jpg",jpeg,client);var same2=await SidecarDoc("conflict/same.DNG",raw,client);
  PlanFailure(()=>SavePlan.Prepare([same1,same2],SaveMode.NewSidecar,SaveScope.All,"",[same1,same2]),"same-subject-different-extension-whole-batch-refused");
  var caseDoc=await PhotoDocument.LoadAsync(client,same1.FilePath.ToUpperInvariant());caseDoc.SelectSidecarEditing(true);caseDoc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","case"}});
  PlanFailure(()=>SavePlan.Prepare([same1,caseDoc],SaveMode.NewSidecar,SaveScope.All,"",[same1,caseDoc]),"case-alias-physical-target-refused");
  var shortName=new StringBuilder(32768);var shortLength=GetShortPathNameW(same1.FilePath,shortName,(uint)shortName.Capacity);
  Check(shortLength>0,"actual-filesystem-short-path-obtained");var alias=await PhotoDocument.LoadAsync(client,shortName.ToString());alias.SelectSidecarEditing(true);alias.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","alias"}});
  PlanFailure(()=>SavePlan.Prepare([same1,alias],SaveMode.NewSidecar,SaveScope.All,"",[same1,alias]),"actual-short-path-directory-alias-target-refused");
  var standalone=docs.Single(d=>d.FileType=="XMP");standalone.SelectSidecarEditing(true);standalone.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","not sidecar"}});
  Check(SavePlan.Prepare([standalone],SaveMode.NewSidecar,SaveScope.All,"",[standalone]).Items.Length==0,"standalone-XMP-no-sidecar-of-itself");standalone.ClearDraft();
  var clear=await SidecarDoc("core/clear.jpg",jpeg,client);clear.SetDraft(PhotoDocument.PositionChanges(new MapPoint(120,30),null,"MANUAL").ToDictionary(p=>p.Key,p=>""));
  Check(SavePlan.Prepare([clear],SaveMode.NewSidecar,SaveScope.Map,"",[clear]).Items.Length==0,"EXIF-GPS-clear-contract-gap-refused-not-silent");
  // Target appeared AFTER preflight. Never remove the other writer's file.
  var race=await SidecarDoc("race/photo.jpg",jpeg,client);var raceItem=SidecarItem(race);var other=System.Text.Encoding.UTF8.GetBytes("other writer");
  using(var watcher=new FileSystemWatcher(Path.GetDirectoryName(race.FilePath)!){EnableRaisingEvents=true}){
   var appeared=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
   watcher.Created+=(_,e)=>{if(Path.GetFileName(e.FullPath).StartsWith(".phototrail-sidecar-")){try{using var f=new FileStream(raceItem.Target,FileMode.CreateNew,FileAccess.Write,FileShare.Read);f.Write(other);appeared.TrySetResult();}catch(IOException){}}};
   await ExpectFailure(()=>SavePlan.CreateAsync(client,raceItem,proof,CancellationToken.None),"target-created-during-staging-race-refused");await appeared.Task.WaitAsync(TimeSpan.FromSeconds(5));
  }Check(File.ReadAllBytes(raceItem.Target).SequenceEqual(other),"race-file-retained-byte-for-byte");
  var cancelled=await SidecarDoc("cancel/photo.jpg",jpeg,client);var cancelItem=SidecarItem(cancelled);using(var token=new CancellationTokenSource()){token.Cancel();await ExpectFailure(()=>SavePlan.CreateAsync(client,cancelItem,proof,token.Token),"cancel-before-write");}Check(!File.Exists(cancelItem.Target)&&cancelled.Draft.Count>0,"cancel-retains-draft-no-target");
  var late=await SidecarDoc("late/photo.jpg",jpeg,client);var lateItem=SidecarItem(late);using(var token=new CancellationTokenSource())using(var watcher=new FileSystemWatcher(Path.GetDirectoryName(late.FilePath)!){EnableRaisingEvents=true}){
   watcher.Renamed+=(_,e)=>{if(e.FullPath.Equals(lateItem.Target,StringComparison.OrdinalIgnoreCase))token.Cancel();};var result=await SavePlan.CreateAsync(client,lateItem,proof,token.Token);
   Check(result.State=="结果未知"&&File.Exists(result.Path)&&late.Draft.Count>0,"cancel-after-delivery-records-existing-unknown-and-draft");
   Check(result.Hash==await PhotoDocument.HashAsync(result.Path),"unknown-actual-disk-identity-recorded");
  }
  var locked=await SidecarDoc("locked/photo.jpg",jpeg,client);var lockedItem=SidecarItem(locked);using(var file=new FileStream(locked.FilePath,FileMode.Open,FileAccess.ReadWrite,FileShare.None))await ExpectFailure(()=>SavePlan.CreateAsync(client,lockedItem,proof,CancellationToken.None),"occupied-source-refused");Check(!File.Exists(lockedItem.Target),"lock-failure-no-target");
  // All existing copy targets and field-scope behavior stay intact.
  foreach(var original in docs.Where(d=>d.CanEdit)) {
   var beforeDraft=new Dictionary<string,string>(original.Draft);original.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","format copy title"},{"XMP-dc:Rights","residual rights"}});
   var destination=Path.Combine(folder,"format-"+Path.GetFileName(original.FilePath));Directory.CreateDirectory(destination);
   var copyPlan=SavePlan.Prepare([original],SaveMode.Copy,SaveScope.Metadata,destination,docs);Check(copyPlan.Items.Length==1,"format-qualified-"+original.FileType+"-"+Path.GetFileName(original.FilePath));
   var copy=await MetadataCopy.SaveValidatedAsync(client,original,destination,copyPlan.Items[0].Fields,proof);
   var read=await PhotoDocument.LoadAsync(client,copy);Check(read.Value("XMP-dc:Title")=="format copy title"&&read.Value("XMP-dc:Rights")=="residual rights","format-copy-actual-readback-"+Path.GetFileName(original.FilePath));
   Check(original.Draft.Count==2,"copy-does-not-rebase-session-"+Path.GetFileName(original.FilePath));original.ReplaceDraft(beforeDraft);original.NotifyDraftChanged();
   if(original.FileType=="JPEG")Check(await MetadataCopy.JpegPixelsAsync(original.FilePath)==await MetadataCopy.JpegPixelsAsync(copy),"copy-JPEG-pixel-payload-"+Path.GetFileName(original.FilePath));
  }
  var gps=await SidecarDoc("gps/new.DNG",raw,client);gps.SetDraft(PhotoDocument.PositionChanges(new MapPoint(120,30),null,"MANUAL"));
  var gpsItem=SidecarItem(gps,SaveScope.Map);Check(gpsItem.Fields.Keys.All(SavePlan.IsGps)&&!gpsItem.Fields.ContainsKey("XMP-dc:Title"),"map-scope-whole-GPS-no-text");
  var gpsResult=await SavePlan.CreateAsync(client,gpsItem,proof,CancellationToken.None);Check(gpsResult.State=="成功"&&gpsResult.Document!.Draft.Count==1&&gpsResult.Document.Draft.ContainsKey("XMP-dc:Title"),"GPS-save-preserves-metadata-residual");
  Check(gpsResult.Document!.Position() is {Latitude:30,Longitude:120}&&gpsResult.Document.Value("XMP-exif:GPSDateTime")==""&&gpsResult.Document.Value("XMP-exif:GPSAltitude")=="","WGS84-measurement-time-altitude-clears");
  var noXmp=await SidecarDoc("empty/new.jpg",jpeg,client);await client.RunAsync(["-overwrite_original","-XMP=","--",noXmp.FilePath]);
  noXmp=await PhotoDocument.LoadAsync(client,noXmp.FilePath);noXmp.SelectSidecarEditing(true);noXmp.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","empty packet title"}});
  var emptyResult=await SavePlan.CreateAsync(client,SidecarItem(noXmp),proof,CancellationToken.None);Check(emptyResult.State=="成功"&&emptyResult.Document!.Value("XMP-dc:Title")=="empty packet title","no-XMP-legal-empty-packet");
  Check(!emptyResult.Document!.Sidecar!.Value.TryGetProperty("XMP-tiff:Make",out _),"no-automatic-EXIF-to-XMP-conversion");
  // Existing directory and separately imported source target collisions.
  var directory=await SidecarDoc("directory/photo.jpg",jpeg,client);Directory.CreateDirectory(Path.ChangeExtension(directory.FilePath,".xmp"));
  PlanFailure(()=>SidecarItem(directory),"target-is-directory-refused");
  var imported=await SidecarDoc("imported/photo.jpg",jpeg,client);File.Copy(docs.Single(d=>d.FileType=="XMP").FilePath,Path.ChangeExtension(imported.FilePath,".xmp"));var importedSide=await PhotoDocument.LoadAsync(client,Path.ChangeExtension(imported.FilePath,".xmp"));
  PlanFailure(()=>SavePlan.Prepare([imported],SaveMode.NewSidecar,SaveScope.All,"",[imported,importedSide]),"target-separately-imported-source-refused");
  // Late UI/source adoption result cannot attach a new hash to an old revision.
  var after=await SidecarDoc("after/photo.jpg",jpeg,client);var afterItem=SidecarItem(after);using(var watcher=new FileSystemWatcher(Path.GetDirectoryName(after.FilePath)!){EnableRaisingEvents=true}){
   var revised=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);watcher.Renamed+=(_,e)=>{if(e.FullPath==afterItem.Target)window.Dispatcher.BeginInvoke(()=>{after.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","new revision"}});revised.TrySetResult();});};
   var result=await SavePlan.CreateAsync(client,afterItem,proof,CancellationToken.None);await revised.Task.WaitAsync(TimeSpan.FromSeconds(5));
   Check(result.State=="结果未知"&&File.Exists(result.Path)&&after.Draft.ContainsKey("XMP-dc:Rights"),"post-create-revision-change-retains-new-draft-unknown");
  }
  var fault=await SidecarDoc("readback-fault/photo.jpg",jpeg,client);var faultItem=SidecarItem(fault);FileStream? held=null;
  using(var watcher=new FileSystemWatcher(Path.GetDirectoryName(fault.FilePath)!){EnableRaisingEvents=true}){
   watcher.Renamed+=(_,e)=>{if(e.FullPath==faultItem.Target)held=new FileStream(e.FullPath,FileMode.Open,FileAccess.ReadWrite,FileShare.None);};
   try{var result=await SavePlan.CreateAsync(client,faultItem,proof,CancellationToken.None);Check(result.State=="结果未知"&&File.Exists(result.Path)&&fault.Draft.Count>0,"post-delivery-readback-lock-failure-retained");}finally{held?.Dispose();}
  }
  var denied=await SidecarDoc("denied/photo.jpg",jpeg,client);var deniedItem=SidecarItem(denied);var deniedFolder=new DirectoryInfo(Path.GetDirectoryName(denied.FilePath)!);var originalAcl=deniedFolder.GetAccessControl();var restricted=deniedFolder.GetAccessControl();
  restricted.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!,FileSystemRights.CreateFiles|FileSystemRights.CreateDirectories,AccessControlType.Deny));
  try{deniedFolder.SetAccessControl(restricted);await ExpectFailure(()=>SavePlan.CreateAsync(client,deniedItem,proof,CancellationToken.None),"directory-create-permission-failure");Check(!File.Exists(deniedItem.Target)&&denied.Draft.Count>0,"permission-failure-retains-draft-no-target");}finally{deniedFolder.SetAccessControl(originalAcl);}
  // Real WPF editor and explicit summary/cancel/execute flow.
  list.SelectedItem=rows.Single(r=>Doc(r).FilePath==raw);Check(!Control<Button>("FieldApplyButton").IsEnabled,"default-RAW-editor-readonly");
  Control<ComboBox>("SaveModeChoice").SelectedIndex=1;Check(Control<Button>("FieldApplyButton").IsEnabled,"explicit-sidecar-mode-opens-existing-whitelist-editor");
  EditedFields(new Dictionary<string,string>{{"XMP-dc:Title","WPF saved title"},{"XMP-exif:DateTimeOriginal","1700:02:03 04:05:06.987654321-03:30"}});await Apply("ApplyDraft");await Idle();
  var rawDoc=Doc(list.SelectedItem!);Check(rawDoc.Draft.Count==2,"WPF-RAW-staging-title-date");
  Control<ComboBox>("SaveModeChoice").SelectedIndex=0;Check(Control<ComboBox>("SaveModeChoice").SelectedIndex==1&&rawDoc.Draft.Count==2,"RAW-existing-draft-cannot-silently-retarget-copy");
  Action("PrepareSaveAll");Check(Control<TextBox>("SaveSummary").Text.Contains(Path.ChangeExtension(raw,".xmp"))&&!File.Exists(Path.ChangeExtension(raw,".xmp")),"summary-lists-real-target-without-creating");
  Action("CancelSavePlan");Check(!File.Exists(Path.ChangeExtension(raw,".xmp"))&&rawDoc.Draft.Count==2,"summary-cancel-no-files-draft-retained");
  // Empty selection / filtered hidden still collect whole library.
  list.SelectedItems.Clear();Input("PhotoSearch","no matching photo");Action("PrepareSaveAll");Check(Control<Button>("ExecuteSaveButton").IsEnabled,"all-pending-hidden-empty-selection-collected");Input("PhotoSearch","");
  Action("ExecuteSavePlan");Action("RereadPhotos");await BatchWait();
  Check(Status.Contains("成功1")&&File.Exists(Path.ChangeExtension(raw,".xmp")),"production-execute-real-sidecar");
  var newRaw=list.Items.Cast<object>().Select(Doc).Single(d=>d.FilePath==raw);Check(newRaw.SidecarPath is not null&&newRaw.Draft.Count==0,"production-adopts-source-clears-confirmed-fields-count");
  Check(Field("lastApply") is null&&Field("trackBatch") is null,"source-change-invalidates-undo-and-track-plan");
  Check(newRaw.VerifiedDate("XMP-exif:DateTimeOriginal") is not null,"new-main-date-v2-read-proof");
  Control<ComboBox>("PhotoSort").SelectedIndex=2;var first=Doc(list.Items[0]);Check(first.FilePath==raw,"source-adoption-v2-main-date-sort");
  list.SelectedItem=list.Items.Cast<object>().Single(r=>Doc(r).FilePath==raw);SelectMetadataTab("重命名");Input("RenameDateFrom","1700-01-01");Input("RenameDateTo","1700-12-31");Action("RefreshRenameOrder");await RenameWait();Check(Groups().Length>=1,"source-adoption-v2-rename-date-filter");Input("RenameDateFrom","");Input("RenameDateTo","");
  SelectMetadataTab("元数据");var mixedRow=list.Items.Cast<object>().Single(r=>Doc(r).FilePath==raw);list.SelectedItem=mixedRow;var mixed=Doc(mixedRow);
  mixed.SetDraft(PhotoDocument.PositionChanges(new MapPoint(121,31),null,"MANUAL"));EditedFields(new Dictionary<string,string>{{"XMP-dc:Rights","workspace rights"}});await Apply("ApplyDraft");
  string scopeOut=Path.Combine(folder,"workspace-copy");Directory.CreateDirectory(scopeOut);Input("OutputFolder",scopeOut);Control<ComboBox>("SaveModeChoice").SelectedIndex=0;
  Action("PrepareSaveWorkspace");Check(((SavePlan)Field("preparedSave")!).Scope==SaveScope.Metadata,"current-metadata-page-non-GPS-scope");Action("CancelSavePlan");
  SelectMetadataTab("地图");Action("PrepareSaveWorkspace");Check(((SavePlan)Field("preparedSave")!).Scope==SaveScope.Map&&((SavePlan)Field("preparedSave")!).Items.Single().Fields.Keys.All(SavePlan.IsGps),"current-map-page-grouped-GPS-scope");Check(Control<TabControl>("WorkspaceTabs").SelectedIndex==0&&Control<TabItem>("SaveTargetTab").IsSelected,"map-summary-actually-visible-in-metadata-page");Action("ExecuteSavePlan");await BatchWait();
  Check(mixed.Draft.ContainsKey("XMP-dc:Rights")&&mixed.Draft.Keys.Any(SavePlan.IsGps),"copy-range-preserves-all-session-drafts");var mapCopy=await PhotoDocument.LoadAsync(client,Path.Combine(scopeOut,"unpaired.DNG"));Check(mapCopy.Position()is{Latitude:31,Longitude:121}&&mapCopy.Value("XMP-dc:Rights")!="workspace rights","only-GPS-fields-saved-other-draft-excluded");
  mixed.ClearDraft();Invoke("RefreshSelection");SelectMetadataTab("元数据");
  // Existing sidecar subsequently goes through COPY only; legacy Ctrl+S remains selected.
  var paired=rows.Single(r=>Path.GetFileName(Doc(r).FilePath)=="paired.jpg");list.SelectedItem=paired;EditedFields(new Dictionary<string,string>{{"XMP-dc:Title","copy title"}});await Apply("ApplyDraft");
  var output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");string frozenFolder=Control<TextBox>("OutputFolder").Text;Input("OutputFolder",frozenFolder+"-changed");Action("ExecuteSavePlan");Check(!Directory.GetFiles(output).Any(),"changed-output-invalidates-old-qualification");Input("OutputFolder",frozenFolder);Action("SaveCopies");Check(Control<TextBox>("SaveSummary").Text.Contains("照片：1"),"legacy-selected-copy-remains-selected-not-library");Action("ExecuteSavePlan");await BatchWait();
  Check(File.Exists(Path.Combine(output,"paired.jpg"))&&File.Exists(Path.Combine(output,"paired.xmp"))&&Doc(paired).Draft.Count==1,"existing-pair-copy-preserves-original-session-draft");
  Check(File.ReadAllBytes(Path.Combine(output,"paired.jpg")).SequenceEqual(hashes[Doc(paired).FilePath]),"pair-copy-image-byte-protection");
  var reread=await PhotoDocument.LoadAsync(client,Path.Combine(output,"paired.jpg"));Check(reread.Value("XMP-dc:Title")=="copy title","actual-copy-ExifTool-readback");
  var embeddedRow=list.Items.Cast<object>().Single(r=>Doc(r).FilePath==jpeg);Doc(embeddedRow).SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","partial one"}});
  string partialOut=Path.Combine(folder,"partial-copy");Directory.CreateDirectory(partialOut);Input("OutputFolder",partialOut);list.SelectedItems.Clear();list.SelectedItems.Add(embeddedRow);list.SelectedItems.Add(paired);Invoke("RefreshSelection");Action("SaveCopies");
  File.AppendAllText(Doc(paired).FilePath,"source changed after frozen summary");Action("ExecuteSavePlan");await BatchWait();
  Check(Status.Replace(" ","").Contains("成功1")&&Status.Replace(" ","").Contains("失败1")&&File.Exists(Path.Combine(partialOut,"embedded.jpg"))&&!File.Exists(Path.Combine(partialOut,"paired.jpg")),"partial-success-one-source-change-failure-preserved");
  Check(Doc(embeddedRow).Draft.Count>0&&Doc(paired).Draft.Count>0,"partial-copy-all-original-session-drafts-retained");
  File.WriteAllBytes(Doc(paired).FilePath,hashes[Doc(paired).FilePath]);
  foreach(var kv in hashes)Check(File.ReadAllBytes(kv.Key).SequenceEqual(kv.Value),"original-SHA-protected-"+Path.GetFileName(kv.Key));Check(await MetadataCopy.JpegPixelsAsync(jpeg)==pixels,"JPEG-pixels-protected");
  SaveResult("save-target-results.json",Field("saveTimings"));
  foreach(var row in list.Items.Cast<object>())Doc(row).ClearDraft();EditedFields(new());
 }
 static async Task SaveTargetScale()
 {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R02_COUNT")!);var rows=await DateCoreRows(count);var docs=rows.Select(Doc).ToArray();
  Control<ComboBox>("SaveModeChoice").SelectedIndex=1;var watch=Stopwatch.StartNew();foreach(var doc in docs)doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","scale saved"}});
  Control<ListBox>("Photos").SelectedItems.Clear();Action("PrepareSaveAll");double prepare=watch.Elapsed.TotalMilliseconds;
  double gap=0;var timerWatch=Stopwatch.StartNew();double previous=0;var timer=new System.Windows.Threading.DispatcherTimer{Interval=TimeSpan.FromMilliseconds(20)};timer.Tick+=(_,_)=>{double now=timerWatch.Elapsed.TotalMilliseconds;gap=Math.Max(gap,now-previous);previous=now;};timer.Start();watch.Restart();Action("ExecuteSavePlan");await BatchWait();timer.Stop();
  Check(Status.Contains("成功"+count)&&Status.Contains("失败0"),"scale-complete-"+count);
  Check(Control<ListBox>("Photos").Items.Cast<object>().All(r=>Doc(r).SidecarPath is not null&&Doc(r).Draft.Count==0),"scale-all-new-baselines-"+count);
  SaveResult("save-target-scale.json",new{count,prepareMs=prepare,saveMs=watch.Elapsed.TotalMilliseconds,maxDispatcherGapMs=gap,stages=Field("saveTimings")});
 }
}
