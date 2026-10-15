using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;

static partial class Program
{
 static long InspectorHostRequests()=>(long)typeof(PhotoDocument).Assembly.GetType("PhotoTrail.Windows.DateAdapter")!.GetField("StartedProcesses",BindingFlags.NonPublic|BindingFlags.Static)!.GetValue(null)!;
 static DispatcherTimer? inspectorImportTimer;
 static Stopwatch inspectorImportClock=new();
 static int inspectorImportTicks;
 static double inspectorImportMaxGap,inspectorImportLast;
 static void ObserveInspectorImport(){inspectorImportClock.Start();inspectorImportTimer=new DispatcherTimer(DispatcherPriority.Background){Interval=TimeSpan.FromMilliseconds(20)};inspectorImportTimer.Tick+=(_,_)=>{double now=inspectorImportClock.Elapsed.TotalMilliseconds;inspectorImportMaxGap=Math.Max(inspectorImportMaxGap,now-inspectorImportLast);inspectorImportLast=now;inspectorImportTicks++;};inspectorImportTimer.Start();}
 static ExifToolClient InspectorTool()=>new(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);
 static object InspectorSelected=>Control<ListBox>("Photos").SelectedItems[0]!;
 static InspectorRow[] InspectorRows()=>Control<DataGrid>("MetadataGrid").Items.Cast<InspectorRow>().ToArray();
 static void InspectorSelect(string name){var list=Control<ListBox>("Photos");list.SelectedItems.Clear();list.SelectedItem=list.Items.Cast<object>().Single(r=>Path.GetFileName(Doc(r).FilePath)==name);}
 static async Task InspectorRefresh(){Action("RereadPhotos");await BatchWait();}
 static void InspectorResult(string name)=>DateCoreResult(name);
 static async Task InspectorEmptyRestart()
 {
  await DateCoreRows(4);SelectMetadataTab("原始字段");
  Check(Control<ComboBox>("InspectorView").SelectedIndex==0&&InspectorRows().Length==0,"restart-explicit-empty-common-view");
  Check(SettingsPreference.Read(Environment.GetEnvironmentVariable("PHOTOTRAIL_SETTINGS_FILE")!).CommonTags.Length==0,"restart-empty-file-not-defaulted");
  Action("RestoreCommonFields");Check(InspectorRows().Length>0,"restart-restore-default24");InspectorResult("inspector-restart-results.json");
 }
 static async Task InspectorFlow()
 {
  var rows=await DateCoreRows(4);var list=Control<ListBox>("Photos");var client=InspectorTool();
  var paths=rows.SelectMany(r=>Doc(r).SidecarPath is {} side?new[]{Doc(r).FilePath,side}:new[]{Doc(r).FilePath}).Distinct().ToArray();
  var bytes=paths.ToDictionary(p=>p,File.ReadAllBytes);
  try {
   InspectorSelect("embedded.jpg");SelectMetadataTab("原始字段");
   Check(rows.All(r=>Doc(r).Inspection is not null&&Doc(r).InspectionError==""),"four-source-forms-complete-read");
   Check(System.Windows.Automation.AutomationProperties.GetName(Control<TextBlock>("InspectorCounts"))==Control<TextBlock>("InspectorCounts").Text,"live-count-accessibility-name-includes-current-values");
   var mappings=MetadataInspector.DefaultCommon.Select(tag=>new{tag,actual=InspectorRows().Where(r=>r.Tag.Contains(" / ")&&MetadataInspector.Matches(tag,r.Tag.Split(" / ")[1])).Select(r=>new{r.Tag,r.State,r.Permission}).ToArray()}).ToArray();
   Check(mappings.All(x=>x.actual.Length>0),"default24-real-source-mappings-present");
   File.WriteAllText(Path.Combine(folder,"common24-actual-map.json"),JsonSerializer.Serialize(mappings,new JsonSerializerOptions{WriteIndented=true}));
   var embedded=Doc(InspectorSelected);int initialCount=embedded.Inspection!.Count(v=>v.Counted);
   Check(embedded.Inspection!.Any(v=>v.IsCopy),"real-ExifTool-copy-identity-kept");
   InspectorSelect("paired.jpg");Control<ComboBox>("InspectorView").SelectedIndex=1;
   Check(InspectorRows().Any(r=>r.Tag=="原图 / IFD0:Make")&&InspectorRows().Any(r=>r.Tag.StartsWith("原图 / XMP-tiff:")&&r.Tag.EndsWith(":Make"))&&InspectorRows().Any(r=>r.Tag=="旁车XMP / XMP-tiff:Make"),"sidecar-does-not-hide-original-EXIF-or-XMP");
   Check(InspectorRows().Where(r=>r.Tag.Contains(":Copy")||r.Tag.Contains("XMP-acme:")).All(r=>!r.CanEdit),"family-copy-unknown-readonly");
   Control<ComboBox>("InspectorView").SelectedIndex=0;Input("MetadataSearch","acme");
   Check(InspectorRows().Any(r=>r.Tag.Contains("XMP-acme:")&&r.Tag.EndsWith(":Title")),"search-full-read-fields-while-common");
   var grid=Control<DataGrid>("MetadataGrid");grid.SelectedItem=InspectorRows().First(r=>r.Tag.Contains("XMP-acme:")&&r.Tag.EndsWith(":Title"));
   var oldClipboard=Clipboard.ContainsText()?Clipboard.GetText():null;
   try{Action("CopyMetadataTag");Check(Clipboard.GetText()==((InspectorRow)grid.SelectedItem).Tag,"copy-full-source-and-tag");}finally{if(oldClipboard is not null)Clipboard.SetText(oldClipboard);}
   Input("MetadataSearch","");Input("TitleValue","unapplied retained");
   Control<ComboBox>("InspectorView").SelectedIndex=1;Action("ClearCommonFields");Action("RestoreCommonFields");
   Check(Control<TextBox>("TitleValue").Text=="unapplied retained","display-and-common-settings-preserve-unapplied-text");
   var before=Doc(InspectorSelected);await InspectorRefresh();Check(ReferenceEquals(before,Doc(InspectorSelected))&&Status.Contains("未应用输入"),"reread-skips-unapplied-even-unchecked-input");
   Invoke("RefreshSelection");Control<ComboBox>("InspectorView").SelectedIndex=1;
   grid.SelectedItem=InspectorRows().Single(r=>r.Tag=="旁车XMP / XMP-dc:Title");Action("EditInspectorField");
   await Responsive();Check(SettingsTab(window,"编辑草稿")!.IsSelected,"exact-existing-editor-navigation");Check(Control<TextBox>("TitleValue").IsKeyboardFocusWithin,"existing-editor-keyboard-focus");
   EditedFields(new(){{"XMP-dc:Title","edited sidecar title"}});await Apply("ApplyDraft");
   Check(MetadataInspector.PendingFields(Doc(InspectorSelected))==1&&Control<TextBlock>("InspectorCounts").Text.Contains("净草稿字段1"),"edit-net-count-not-source-rows");
   var draft=Drafts([InspectorSelected]);await InspectorRefresh();Check(SameDrafts([InspectorSelected],draft)&&Status.Contains("有草稿"),"reread-skips-draft-keeps-source-baseline");
   var baseline=Doc(InspectorSelected);var sideBytes=File.ReadAllBytes(baseline.SidecarPath!);File.AppendAllText(baseline.SidecarPath!," ");
   await InspectorRefresh();Check(ReferenceEquals(baseline,Doc(InspectorSelected))&&baseline.SidecarHash==before.SidecarHash&&SameDrafts([InspectorSelected],draft),"draft-external-change-does-not-rebase-old-source-hash");
   try{await baseline.EnsureUnchangedAsync();throw new Exception("external source accepted");}catch(IOException){Check(true,"old-draft-source-protection-still-rejects-external-change");}finally{File.WriteAllBytes(baseline.SidecarPath!,sideBytes);}
   list.SelectedItems.Add(list.Items.Cast<object>().Single(r=>Path.GetFileName(Doc(r).FilePath)=="embedded.jpg"));await InspectorRefresh();Check(baseline.Draft.Count==1&&Control<Button>("UndoLastApplyButton").IsEnabled&&Status.Contains("草稿跳过1"),"mixed-reread-clean-only-retains-valid-unrelated-undo");
   Action("UndoLastApply");Check(baseline.Draft.Count==0,"complete-undo-count-zero");
   InspectorSelect("embedded.jpg");embedded=Doc(InspectorSelected);
   embedded.SetDraft(PhotoDocument.PositionChanges(new MapPoint(121,31),null,"MANUAL"));Invoke("RefreshSelection");
   Check(MetadataInspector.PendingFields(embedded)==1,"GPS-composite-one-logical-field");Action("UndoDraft");
   await client.RunAsync(["-overwrite_original","-XMP-dc:Title=external title","--",embedded.FilePath]);
   await InspectorRefresh();Check(!ReferenceEquals(embedded,Doc(InspectorSelected))&&Doc(InspectorSelected).Value("XMP-dc:Title")=="external title","stable-external-change-adopts-new-snapshot");
   embedded=Doc(InspectorSelected);string sidecar=Path.ChangeExtension(embedded.FilePath,".xmp");
   File.WriteAllBytes(sidecar,bytes[paths.Single(p=>Path.GetFileName(p)=="standalone.xmp")]);
   await InspectorRefresh();Check(Doc(InspectorSelected).SidecarPath==sidecar&&Status.Contains("旁车新增1"),"new-sidecar-explicit-new-relationship");
   File.Delete(sidecar);await InspectorRefresh();Check(Doc(InspectorSelected).SidecarPath is null&&Status.Contains("消失1"),"vanished-sidecar-explicit-new-relationship");
   embedded=Doc(InspectorSelected);string hidden=embedded.FilePath+".temporarily-missing";File.Move(embedded.FilePath,hidden);
   try{await InspectorRefresh();Check(ReferenceEquals(embedded,Doc(InspectorSelected))&&embedded.InspectionError.Length>0&&embedded.Inspection!.Count(v=>v.Counted)>0,"missing-file-retains-stale-count-and-snapshot");}finally{File.Move(hidden,embedded.FilePath);}
   await InspectorRefresh();Check(Doc(InspectorSelected).InspectionError=="","successful-reread-clears-stale-state");
   string tool=Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!;before=Doc(InspectorSelected);
   try{Environment.SetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL",Path.Combine(folder,"nonexistent-tool.exe"));await InspectorRefresh();Check(ReferenceEquals(before,Doc(InspectorSelected))&&before.InspectionError.Length>0,"read-failure-keeps-old-snapshot");}finally{Environment.SetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL",tool);}
   await InspectorRefresh();
   list.SelectAll();await Responsive();SelectMetadataTab("原始字段");
   Check(InspectorRows().Any(r=>r.State=="混合值"),"selected-mixed-value-not-missing");
   long requests=ToolRequests(),hostRequests=InspectorHostRequests();foreach(var row in list.Items.Cast<object>())for(int i=0;i<20;i++){_=row.GetType().GetProperty("Summary")!.GetValue(row);_=row.GetType().GetProperty("Captured")!.GetValue(row);_=MetadataInspector.Counts([Doc(row)]);}
   Check(ToolRequests()==requests&&InspectorHostRequests()==hostRequests,"getters-count-and-view-never-start-ExifTool-or-DateHost");
   // Production save runs while a reread entry is attempted. Original drafts remain because these are explicit copies.
   EditedFields(new(){{"XMP-dc:Title","R02 final copy title"}});await Apply("ApplyDraft");var originals=list.SelectedItems.Cast<object>().Select(Doc).ToArray();
   var hashes=originals.ToDictionary(d=>d.FilePath,d=>d.SourceHash);string output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);
   Action("SaveCopies");var saveStatus=Status;Action("RereadPhotos");Check((bool)Field("busy")!&&Status==saveStatus,"reread-prohibited-during-copy-transaction");await BatchWait();
   Check(Status.Contains("副本成功 4，失败 0"),"four-form-final-explicit-copies");
   foreach(var d in originals){var read=await PhotoDocument.LoadAsync(client,Path.Combine(output,Path.GetFileName(d.FilePath)),inspect:true);Check(read.Value("XMP-dc:Title")=="R02 final copy title"&&read.Draft.Count==0,"copy-ExifTool-baseline-zero-"+d.FileType);Check(await PhotoDocument.HashAsync(d.FilePath)==hashes[d.FilePath]&&(d.SidecarPath is null||await PhotoDocument.HashAsync(d.SidecarPath)==d.SidecarHash),"copy-source-sidecar-SHA-"+d.FileType);if(d.SidecarPath is not null)Check(await PhotoDocument.HashAsync(read.FilePath)==d.SourceHash,"copy-raw-primary-byte-protection");else if(d.FileType=="JPEG")Check(await MetadataCopy.JpegPixelsAsync(read.FilePath)==await MetadataCopy.JpegPixelsAsync(d.FilePath),"copy-JPEG-pixel-protection");}
   Check(originals.All(d=>MetadataInspector.PendingFields(d)==1),"copy-success-preserves-original-session-draft-baseline");Action("UndoDraft");Check(originals.All(d=>MetadataInspector.PendingFields(d)==0),"explicit-clear-count-zero");
   // Actual date proofs and the affected production date sort/filter/matching invalidation.
   InspectorSelect("standalone.xmp");var old=Doc(InspectorSelected);SelectMetadataTab("重命名");Input("RenameRules","prefix|r02_");Action("RefreshRenameOrder");await RenameWait();
   await client.RunAsync(["-overwrite_original","-XMP-xmp:CreateDate=1970:01:01 00:00:00.000000001Z","--",old.FilePath]);await InspectorRefresh();
   var modern=Doc(InspectorSelected);Check(modern.VerifiedCaptureDate!.SortProjection is {Seconds:0,Nanoseconds:1},"reread-v2-exact-second-nanosecond-proof");
   Control<ComboBox>("PhotoSort").SelectedIndex=2;Check(Path.GetFileName(Doc(list.Items[0]).FilePath)=="standalone.xmp","reread-photo-date-sort-updated");
   InspectorSelect("standalone.xmp");SelectMetadataTab("重命名");Input("RenameDateFrom","1970:01:01 00:00:00.000000001Z");Input("RenameDateTo","1970:01:01 00:00:00.000000001Z");Action("RefreshRenameOrder");await RenameWait();
   Check(GroupNames().SequenceEqual(new[]{"standalone.xmp"}),"reread-rename-date-inclusive-filter-updated");
   Input("RenameDateFrom","");Input("RenameDateTo","");
   string gpx=Path.Combine(folder,"epoch.gpx");File.WriteAllText(gpx,"""<gpx version="1.1" creator="R02" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg><trkpt lat="30" lon="120"><time>1970-01-01T00:00:00Z</time></trkpt><trkpt lat="31" lon="121"><time>1970-01-01T00:00:02Z</time></trkpt></trkseg></trk></gpx>""");
   await (Task)typeof(MainWindow).GetMethod("ImportTracksAsync",BindingFlags.Instance|BindingFlags.NonPublic)!.Invoke(window,[new[]{gpx},false])!;
   SelectMetadataTab("批量日期");await TrackBatchCompute();Check(Results().Single().Status=="精度不足","reread-track-uses-exact-v2-domain");
   Check(Field("trackBatch") is not null,"reread-track-result-present-before-refresh");await InspectorRefresh();Check(Field("trackBatch") is null&&Field("currentPreview") is null,"reread-invalidates-track-match-and-map-preview");
   InspectorSelect("paired.jpg");SelectMetadataTab("重命名");Input("RenameRules","prefix|r02_");Action("RefreshRenameOrder");await RenameWait();Action("FreezeRename");await RenameWait();Action("ExecuteRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("更名及内容核验完成"),"inspector-paired-real-rename");Check(Doc(InspectorSelected).Inspection is not null,"rename-reload-complete-inspector");Action("RestoreRename");await RenameWait();Check(Control<TextBlock>("RenameStatus").Text.Contains("恢复完成"),"inspector-paired-real-restore");
   SelectMetadataTab("原始字段");Control<ComboBox>("InspectorView").SelectedIndex=0;Action("ClearCommonFields");Check(InspectorRows().Length==0,"explicit-empty-common-rows");
   InspectorResult("inspector-flow-results.json");
  } finally{foreach(var item in bytes)File.WriteAllBytes(item.Key,item.Value);foreach(var row in list.Items.Cast<object>())Doc(row).ClearDraft();Invoke("RefreshSelection");}
 }
 static async Task InspectorLate()
 {
  var all=await DateCoreRows(4);var list=Control<ListBox>("Photos");var collection=(IList)Field("photos")!;
  foreach(string change in new[]{"selection","draft","input","remove","source","sidecar","cancel","new-request"}){
   InspectorSelect("embedded.jpg");Invoke("RefreshSelection");var row=InspectorSelected;var doc=Doc(row);byte[] bytes=File.ReadAllBytes(doc.FilePath);string side=Path.ChangeExtension(doc.FilePath,".xmp");
   var owner=SynchronizationContext.Current!;var gate=new HeldContext(owner);
   try{SynchronizationContext.SetSynchronizationContext(gate);Action("RereadPhotos");}finally{SynchronizationContext.SetSynchronizationContext(owner);}
   await gate.Posted.Task.WaitAsync(TimeSpan.FromSeconds(30));Check(ReferenceEquals(doc,Doc(row)),"reread-prepared-not-yet-swapped-"+change);
   string? notice=null;PhotoDocument? latest=null;
   switch(change){
    case "selection":list.SelectedItems.Clear();list.SelectedItem=all[3];break;
    case "draft":doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","new draft"}});break;
    case "input":Input("TitleValue","new unapplied text");break;
    case "remove":collection.Remove(row);break;
    case "source":File.AppendAllText(doc.FilePath," ");break;
    case "sidecar":File.WriteAllBytes(side,File.ReadAllBytes(Doc(all[3]).FilePath));break;
    case "cancel":Action("CancelRead");break;
    case "new-request":Action("CancelRead");typeof(MainWindow).GetField("busy",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,false);await InspectorRefresh();latest=Doc(InspectorSelected);notice=Status;break;
   }
   gate.Release();await BatchWait();await Task.Delay(100);
   if(change=="new-request")Check(ReferenceEquals(latest,Doc(InspectorSelected))&&Status==notice,"old-refresh-cannot-overwrite-new-refresh");
   else Check(change=="remove"?!collection.Contains(row):collection.Contains(row)&&ReferenceEquals(Doc(collection.Cast<object>().Single(r=>Doc(r).FilePath==doc.FilePath)),doc),"reread-rejected-old-snapshot-"+change);
   if(change=="draft")Check(doc.Value("XMP-dc:Title")=="new draft","late-refresh-retains-new-draft");
   if(change=="input")Check(Control<TextBox>("TitleValue").Text=="new unapplied text","late-refresh-retains-new-unapplied-text");
   if(change is "source" or "sidecar")Check(doc.InspectionError.Length>0,"read-in-progress-change-marks-stale-"+change);
   File.WriteAllBytes(doc.FilePath,bytes);if(File.Exists(side))File.Delete(side);doc.ClearDraft();
   if(change=="remove")collection.Add(row);Invoke("RefreshSelection");
  }
  InspectorSelect("embedded.jpg");typeof(MainWindow).GetField("renameRecoveryRequired",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,true);long before=ToolRequests();Action("RereadPhotos");Check(ToolRequests()==before,"recovery-state-no-conflict-reread");typeof(MainWindow).GetField("renameRecoveryRequired",BindingFlags.Instance|BindingFlags.NonPublic)!.SetValue(window,false);
  InspectorResult("inspector-late-results.json");
 }
 static async Task InspectorScale()
 {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R02_COUNT")!);var rows=await DateCoreRows(count);inspectorImportTimer?.Stop();var list=Control<ListBox>("Photos");list.SelectAll();
  long requests=ToolRequests();double maxGap=0;int ticks=0;var clock=Stopwatch.StartNew();double last=0;
  var timer=new DispatcherTimer(DispatcherPriority.Background){Interval=TimeSpan.FromMilliseconds(20)};timer.Tick+=(_,_)=>{double now=clock.Elapsed.TotalMilliseconds;maxGap=Math.Max(maxGap,now-last);last=now;ticks++;};timer.Start();
  await InspectorRefresh();timer.Stop();double elapsed=clock.Elapsed.TotalMilliseconds;
  Check(Control<ListBox>("Photos").SelectedItems.Cast<object>().All(r=>Doc(r).Inspection is not null&&Doc(r).InspectionError==""),"scale-complete-all-sources-"+count);
  Check(ToolRequests()-requests==2*Math.Ceiling(count/32d),"scale-two-grouped-ExifTool-requests-per32-"+count);
  Check(ticks>0,"scale-Dispatcher-responded-during-background-read-"+count);
  evidence.Add(new{count,refreshMs=elapsed,refreshRequests=ToolRequests()-requests,importMs=(double)Field("importMilliseconds")!,totalImportRequests=(long)Field("importExifToolRequests")!,importDateHostRequests=(long)Field("importDateHostRequests")!,importDispatcherTicks=inspectorImportTicks,importMaxDispatcherGapMs=inspectorImportMaxGap,importObservationScope="second Loaded handler through ready; excludes pre-Loaded setup",dispatcherTicks=ticks,maxDispatcherGapMs=maxGap,phases=new Dictionary<string,double>((Dictionary<string,double>)Field("rereadTimings")!),scope="real production WPF import and reread; synthetic XMP; UI polling 25ms"});
  InspectorResult("inspector-scale-results.json");
 }
}
