using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Controls;
using System.Windows.Threading;
using PhotoTrail.Windows;
static partial class Program
{
 static void R04Refusal(Action action,string name){try{action();throw new Exception("accepted invalid input: "+name);}catch(Exception e)when(e is ArgumentException or InvalidOperationException or IOException or InvalidDataException){Check(true,name);}}
 static async Task R04aChecks() {
  var rows=await DateCoreRows(5);var client=InspectorTool();var all=rows.Select(Doc).ToArray();
  var jpeg=all.Single(d=>Path.GetFileName(d.FilePath)=="embedded.jpg");var paired=all.Single(d=>Path.GetFileName(d.FilePath)=="paired.jpg");var raw=all.Single(d=>Path.GetFileName(d.FilePath)=="unpaired.DNG");var standalone=all.Single(d=>d.FileType=="XMP");
  var list=Control<ListBox>("Photos");list.SelectedItems.Clear();list.SelectedItems.Add(rows.Single(r=>ReferenceEquals(Doc(r),jpeg)));
  Check(Control<CheckBox>("ExifArtistApply").IsEnabled,"JPEG-exact-EXIF-control-enabled");
  list.SelectedItems.Clear();list.SelectedItems.Add(rows.Single(r=>ReferenceEquals(Doc(r),paired)));
  Check(!Control<CheckBox>("ExifArtistApply").IsEnabled,"paired-EXIF-reference-readonly");
  foreach(var doc in new[]{paired,raw,standalone})R04Refusal(()=>doc.SetDraft(new Dictionary<string,string>{{"IFD0:Artist","refused"}}),"EXIF-source-refused-"+doc.FileType);
  var original=await PhotoDocument.HashAsync(jpeg.FilePath);var pixels=await MetadataCopy.JpegPixelsAsync(jpeg.FilePath);
  Check(paired.MainDateTag=="XMP-xmp:CreateDate"&&jpeg.MainDateTag=="Composite:SubSecDateTimeOriginal","main-date-source-mapping");
  string[] words=["one, two","中文\nsecond line","日本語","[literal]"];
  string listText=MetadataFields.FormatList(words);Check(MetadataFields.List(listText).SequenceEqual(words),"list-elements-comma-newline-Unicode-boundaries");
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"XMP-dc:Creator","[null]"}}),"null-list-rejected");
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"ExifIFD:ISO","100"}}),"R04b-numeric-EXIF-not-open");
  foreach(var bad in new[]{"2026:02:30 00:00:00","2026:01:01 24:00:00","2026:01:01 00:00:00+25:00"}) {
   var rev=jpeg.DraftRevision;try{await jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,bad}});throw new Exception("accepted invalid date");}catch(ArgumentException){}
   Check(jpeg.DraftRevision==rev,"invalid-grouped-date-keeps-revision");
  }
  foreach(var text in new[]{"1500:02:29 23:59:59.123456789+05:30","1600:02:29 00:00:00","2026:01:31 23:59:59Z"}) {
   await jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,text}});Check(jpeg.VerifiedCaptureDate is not null,"Swift-historical-nanosecond-validated");
   Check(BatchTrackMatch.Capture(jpeg)==text,"main-draft-projects-immediately");
  }
  jpeg.ClearDraft();
  var copyFolder=Path.Combine(folder,"group-copies");Directory.CreateDirectory(copyFolder);
  foreach(var (tag,index) in MetadataFields.DateGroups.Keys.Select((t,i)=>(t,i))) {
   var path=Path.Combine(folder,"group-"+index+".jpg");File.Copy(jpeg.FilePath,path);
   var doc=await PhotoDocument.LoadAsync(client,path);
   await doc.SetDraftAsync(new Dictionary<string,string>{{tag,"1600:02:29 01:02:03.123456789+05:30"}});
   var output=await MetadataCopy.SaveAsync(client,doc,copyFolder);var loaded=await PhotoDocument.LoadAsync(client,output);
   Check(loaded.Value(tag)=="1600:02:29 01:02:03.123456789+05:30","three-groups-exact-component-save-"+index);
   Check(await MetadataCopy.JpegPixelsAsync(output)==pixels,"group-save-pixels-"+index);
   var noComp=Path.Combine(folder,"no-comp-"+index);Directory.CreateDirectory(noComp);await loaded.SetDraftAsync(new Dictionary<string,string>{{tag,"2026:01:02 03:04:05"}});var nextPath=await MetadataCopy.SaveAsync(client,loaded,noComp);var next=await PhotoDocument.LoadAsync(client,nextPath);
   var components=MetadataFields.DateGroups[tag];Check(!next.Embedded.TryGetProperty(components[1],out _)&&!next.Embedded.TryGetProperty(components[2],out _),"old-subsec-offset-removed-"+index);
   var clear=Path.Combine(folder,"clear-"+index);Directory.CreateDirectory(clear);next.SetDraft(new Dictionary<string,string>{{tag,""}});var cleared=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,next,clear));
   Check(components.All(t=>!cleared.Embedded.TryGetProperty(t,out _)),"whole-date-group-cleared-"+index);
   if(index==0)Check(BatchTrackMatch.Capture(cleared) is null&&cleared.VerifiedCaptureDate is null,"JPEG-clear-no-old-XMP-fallback-after-reopen");
  }
  var unicode=new Dictionary<string,string>();foreach(var tag in MetadataFields.ExifText)unicode[tag]="中文 Français 日本語 "+tag.Split(':')[1];unicode["ExifIFD:UserComment"]="中文\nFrançais 日本語 😀";unicode["ExifIFD:SerialNumber"]="000012345";
  unicode["XMP-dc:Creator"]=listText;unicode["XMP-dc:Subject"]=listText;unicode["XMP-dc:Title"]="中文 default";
  list.SelectedItems.Clear();list.SelectedItems.Add(rows.Single(r=>ReferenceEquals(Doc(r),jpeg)));typeof(MainWindow).GetMethod("FillEditor",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,[unicode]);Action("ApplyDraft");await BatchWait();
  Check(unicode.All(p=>jpeg.Draft.ContainsKey(p.Key)),"production-controls-typed-EXIF-XMP-apply");Check(MetadataInspector.PendingFields(jpeg)==unicode.Count,"logical-draft-count");
  Action("UndoLastApply");Check(jpeg.Draft.Count==0,"production-undo-complete");typeof(MainWindow).GetMethod("FillEditor",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,[unicode]);Action("ApplyDraft");await BatchWait();
  var outputFolder=Path.Combine(folder,"unicode-copy");Directory.CreateDirectory(outputFolder);Input("OutputFolder",outputFolder);Action("SaveCopies");Action("CancelSavePlan");Check(!Directory.EnumerateFiles(outputFolder).Any()&&await PhotoDocument.HashAsync(jpeg.FilePath)==original,"production-summary-cancel-no-write");
  Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();Check(File.Exists(Path.Combine(outputFolder,"embedded.jpg")),"production-JPEG-copy-delivered");
  var saved=await PhotoDocument.LoadAsync(client,Path.Combine(outputFolder,"embedded.jpg"));foreach(var tag in MetadataFields.ExifText)Check(saved.Value(tag)==unicode[tag],"Unicode-EXIF-readback-"+tag);
  Check(MetadataFields.List(saved.Value("XMP-dc:Creator")).SequenceEqual(words)&&MetadataFields.List(saved.Value("XMP-dc:Subject")).SequenceEqual(words),"literal-list-write-roundtrip");
  Check(jpeg.Draft.Count==unicode.Count&&await PhotoDocument.HashAsync(jpeg.FilePath)==original&&await MetadataCopy.JpegPixelsAsync(saved.FilePath)==pixels,"copy-keeps-draft-source-pixels");
  jpeg.ClearDraft();
  var boundaryPath=Path.Combine(folder,"boundary-text.jpg");File.Copy(jpeg.FilePath,boundaryPath);var boundary=await PhotoDocument.LoadAsync(client,boundaryPath);var limitText=new string('字',8192);boundary.SetDraft(new Dictionary<string,string>{{"IFD0:Artist",limitText},{"ExifIFD:UserComment",limitText}});var boundaryOut=Path.Combine(folder,"boundary-copy");Directory.CreateDirectory(boundaryOut);var boundaryRead=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,boundary,boundaryOut));Check(boundaryRead.Value("IFD0:Artist")==limitText&&boundaryRead.Value("ExifIFD:UserComment")==limitText,"合法8192字符Unicode边界真实回读");
  var sideOriginal=await PhotoDocument.HashAsync(paired.FilePath);var sideTime="1500:02:29 04:05:06.987654321+09:00";
  await paired.SetDraftAsync(new Dictionary<string,string>{{"XMP-xmp:CreateDate",sideTime},{"XMP-exif:DateTimeOriginal","1600:01:01 00:00:00+00:00"},{"XMP-exif:DateTimeDigitized","1700:01:01 00:00:00+00:00"},{"XMP-xmp:ModifyDate","1800:01:01 00:00:00+00:00"},{"XMP-dc:Subject",listText}});
  Check(BatchTrackMatch.Capture(paired)==sideTime&&paired.VerifiedCaptureDate is not null,"sidecar-main-conflict-projects-CreateDate");
  var sideOut=Path.Combine(folder,"paired-copy");Directory.CreateDirectory(sideOut);var sideSaved=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,paired,sideOut));
  Check(await PhotoDocument.HashAsync(sideSaved.FilePath)==sideOriginal,"sidecar-copy-image-byte-protection");Check(sideSaved.Value("XMP-exif:DateTimeOriginal")!=sideSaved.Value("XMP-xmp:CreateDate"),"four-XMP-dates-remain-independent");
  var beforePacket=File.ReadAllText(paired.SidecarPath!);var afterPacket=File.ReadAllText(sideSaved.SidecarPath!);Check(!beforePacket.Contains("titre francais")||afterPacket.Contains("titre francais"),"other-language-retained");
  var defaultClear=await PhotoDocument.LoadAsync(client,sideSaved.FilePath);defaultClear.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title",""}});var languageOut=Path.Combine(folder,"language-clear");Directory.CreateDirectory(languageOut);var languageRead=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,defaultClear,languageOut));Check(languageRead.Value("XMP-dc:Title")==""&&(!afterPacket.Contains("titre francais")||File.ReadAllText(languageRead.SidecarPath!).Contains("titre francais")),"x-default清除保留其他语言");
  sideSaved.SetDraft(new Dictionary<string,string>{{"XMP-xmp:CreateDate",""}});Check(BatchTrackMatch.Capture(sideSaved) is null,"sidecar-clear-immediate-no-fallback");var sideClear=Path.Combine(folder,"paired-clear");Directory.CreateDirectory(sideClear);var reopened=await PhotoDocument.LoadAsync(client,await MetadataCopy.SaveAsync(client,sideSaved,sideClear));
  Check(BatchTrackMatch.Capture(reopened) is null&&reopened.Value("XMP-exif:DateTimeOriginal").Length>0,"sidecar-clear-reopen-other-date-retained");
  var csv=MetadataCsv.Export(MetadataCsv.Snapshot([saved]));var round=MetadataCsv.Load(csv,MetadataCsv.Snapshot([saved]));Check(round.Changes.Count==0,"CSV-list-boundaries-unchanged-roundtrip");
  var preset=MetadataPreset.Create("R04a",new Dictionary<string,string>{{"XMP-dc:Creator",listText},{"Composite:SubSecCreateDate","1500:02:29 01:02:03.123456789Z"}});var decoded=MetadataPreset.Decode(preset.Encode());Check(MetadataFields.List(decoded.Operations[0].Value).SequenceEqual(words),"legacy-version-one-preset-list-boundaries");await decoded.ApplyAsync(jpeg);Check(jpeg.VerifiedDate("Composite:SubSecCreateDate") is not null,"preset-grouped-date-host-validated");jpeg.ClearDraft();
  foreach(var target in MetadataFields.DateGroups.Keys.Concat(new[]{"XMP-exif:DateTimeOriginal","XMP-exif:DateTimeDigitized","XMP-xmp:CreateDate","XMP-xmp:ModifyDate"})) {
   var plan=await DatePagePreview.CreateAsync([jpeg],new(1,Start:"2026:01:02 03:04:05.123456789Z",Seconds:0,Target:target),0,()=>0,default);plan.Apply();Check(jpeg.Draft.ContainsKey(target),"日期五模式精确目标-"+target);jpeg.ClearDraft();
  }
  try{await DatePagePreview.CreateAsync([paired],new(1,Start:"2026:01:02 03:04:05",Target:"Composite:SubSecCreateDate"),0,()=>0,default);throw new Exception("sidecar EXIF date accepted");}catch(InvalidOperationException){}Check(true,"旁车五模式EXIF资格拒绝");
  var datePlan=await DatePagePreview.CreateAsync([jpeg,paired],new(1,Start:"1600:01:02 03:04:05.123456789+05:30",Seconds:1),0,()=>0,default);datePlan.Apply();Check(jpeg.Draft.ContainsKey("Composite:SubSecDateTimeOriginal")&&paired.Draft.ContainsKey("XMP-xmp:CreateDate")&&!jpeg.Draft.ContainsKey("XMP-exif:DateTimeOriginal"),"five-mode-pipeline-routes-per-source");jpeg.ClearDraft();paired.ClearDraft();
  var lateBefore=jpeg.Value(jpeg.MainDateTag);var late=jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,"2026:01:01 00:00:00"}});jpeg.SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","later revision"}});try{await late;throw new Exception("late validation accepted");}catch(InvalidOperationException){}Check(jpeg.Value(jpeg.MainDateTag)==lateBefore&&jpeg.Value("XMP-dc:Title")=="later revision","日期验证迟到不覆盖后来草稿");jpeg.ClearDraft();
  var sourceCopy=Path.Combine(folder,"changed-source.jpg");File.Copy(jpeg.FilePath,sourceCopy);var changed=await PhotoDocument.LoadAsync(client,sourceCopy);changed.SetDraft(new Dictionary<string,string>{{"IFD0:Artist","frozen"}});var freeze=SavePlan.Prepare([changed],SaveMode.Copy,SaveScope.All,copyFolder,[changed]).Items.Single();changed.SetDraft(new Dictionary<string,string>{{"IFD0:Software","later"}});R04Refusal(()=>SavePlan.Require(freeze),"冻结revision失效拒绝");File.AppendAllText(sourceCopy,"synthetic external change");try{await MetadataCopy.SaveAsync(client,changed,copyFolder);throw new Exception("changed source accepted");}catch(IOException){}Check(changed.Draft.Count==2&&!File.Exists(Path.Combine(copyFolder,"changed-source.jpg")),"来源变化拒绝且保留草稿");
  var revBefore=jpeg.DraftRevision;using(var cancel=new CancellationTokenSource()){cancel.Cancel();try{await jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,"2026:01:01 00:00:00"}},cancel.Token);}catch(OperationCanceledException){}}Check(jpeg.DraftRevision==revBefore,"cancelled-date-keeps-draft");
  await jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,"1600:02:29 01:02:03.123456789+05:30"}});
  typeof(MainWindow).GetMethod("RefreshPhotoRows",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,null);list.SelectedItems.Clear();list.SelectedItems.Add(rows.Single(r=>ReferenceEquals(Doc(r),jpeg)));Control<ComboBox>("SaveModeChoice").SelectedIndex=2;var backup=Path.Combine(folder,"backups");Directory.CreateDirectory(backup);Input("BackupFolder",backup);Action("PrepareSaveAll");Action("ExecuteSavePlan");await BatchWait();
  var result=((List<SidecarResult>)Field("saveResults")!).Single();Check(result.State=="成功"&&result.Document!.Draft.Count==0,"production-grouped-inplace-UI-adoption");var record=InplaceHistory.Read(InplaceHistory.PathFor(result.RecordId!));Check(record.Phase=="saved"&&await PhotoDocument.HashAsync(record.Backup)==original,"forced-backup-actual-byte-SHA");
  Check(result.Document!.Value(jpeg.MainDateTag)=="1600:02:29 01:02:03.123456789+05:30","real-target-grouped-inplace-readback");
  Control<ComboBox>("InplaceRecords").SelectedIndex=0;Action("ShowInplaceRecord");Action("RestoreInplaceRecord");await BatchWait();Check(await PhotoDocument.HashAsync(jpeg.FilePath)==original&&await MetadataCopy.JpegPixelsAsync(jpeg.FilePath)==pixels,"production-record-restore-original-SHA-pixels");Check(InplaceHistory.Read(InplaceHistory.PathFor(record.Id)).Phase=="restored","persistent-restored-phase");
  // Pending/corrupt rejection uses isolated existing regression cases; never the historical records.
  Check(all.All(d=>d.SourceHash==awaitHash(d.FilePath)||d==jpeg),"other-imported-sources-preserved");
  static string awaitHash(string path)=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)));
  await R04aConsumers(client,jpeg.FilePath,paired.FilePath);
  File.WriteAllText(Path.Combine(folder,"r04a-results.json"),JsonSerializer.Serialize(evidence,new JsonSerializerOptions{WriteIndented=true}));
 }
 static async Task R04aConsumers(ExifToolClient client,string jpegPath,string sidePath) {
  var list=Control<ListBox>("Photos");var jr=list.Items.Cast<object>().Single(r=>Doc(r).FilePath==jpegPath);var sr=list.Items.Cast<object>().Single(r=>Doc(r).FilePath==sidePath);var jpeg=Doc(jr);var side=Doc(sr);
  await jpeg.SetDraftAsync(new Dictionary<string,string>{{jpeg.MainDateTag,"2026:01:01 00:00:01+00:00"},{"XMP-exif:DateTimeOriginal","1800:01:01 00:00:00+00:00"}});
  await side.SetDraftAsync(new Dictionary<string,string>{{side.MainDateTag,"2026:01:01 00:00:02+00:00"},{"XMP-exif:DateTimeOriginal","1700:01:01 00:00:00+00:00"}});
  var jtime=jpeg.VerifiedCaptureDate!.SortProjection;var stime=side.VerifiedCaptureDate!.SortProjection;
  Check(jtime.Seconds+1==stime.Seconds,"主时间排序与冲突同义值独立");
  Check((ValueTuple<long,int>?)jr.GetType().GetProperty("Captured")!.GetValue(jr)==jtime,"列表主时间getter一致");
  list.SelectedItems.Clear();list.SelectedItems.Add(sr);typeof(MainWindow).GetMethod("RefreshMatchPhoto",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,null);
  Check(Control<TextBox>("MatchTimeValue").Text.StartsWith("2026-01-01T00:00:02"),"地图时间消费旁车主日期");
  side.SetDraft(new Dictionary<string,string>{{side.MainDateTag,""}});typeof(MainWindow).GetMethod("RefreshMatchPhoto",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,null);
  Check(Control<TextBox>("MatchTimeValue").Text==""&&side.VerifiedCaptureDate is null,"清除主日期地图与投影缺失");
  Check(BatchTrackMatch.Calculate(side,[],true,default).Status=="缺失时间","轨迹匹配不回退旧同义日期");
  await side.SetDraftAsync(new Dictionary<string,string>{{side.MainDateTag,"2026:01:01 00:00:02"}});Check(side.VerifiedCaptureDate!.InstantLimitation is not null,"无偏移不猜UTC");
  R04Refusal(()=>MetadataPreset.Decode("{\"version\":99}"),"未知JSON版本拒绝");R04Refusal(()=>MetadataPreset.Create("bad",new Dictionary<string,string>{{"MakerNotes:OwnerName","x"}}),"非白名单JSON目标拒绝");
  R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IFD0:Artist",new string('x',8193)}}),"文字长度边界拒绝");R04Refusal(()=>PhotoDocument.ValidateChanges(new Dictionary<string,string>{{"IFD0:Artist","a\0b"}}),"文字NUL拒绝");
  R04Refusal(()=>MetadataPreset.Validate(new("IFD0:Artist","copy","XMP-dc:Title")),"本批不开放跨来源复制编排");
  var inspection=jpeg.Inspection;var failure=jpeg.InspectionError;long gettersBefore=DateAdapter.StartedProcesses;for(int i=0;i<100;i++){_=jpeg.VerifiedCaptureDate;_=side.VerifiedCaptureDate;_=jpeg.Value(jpeg.MainDateTag);}Check(DateAdapter.StartedProcesses==gettersBefore,"日期getter不启动进程");
  jpeg.Inspection=[new("原图","IFD0:Artist","a"),new("原图","IFD0:Copy1:Artist","b")];R04Refusal(()=>jpeg.SetDraft(new Dictionary<string,string>{{"IFD0:Artist","new"}}),"真正重复family拒绝");jpeg.Inspection=inspection;jpeg.InspectionError="synthetic read failure";R04Refusal(()=>jpeg.SetDraft(new Dictionary<string,string>{{"IFD0:Artist","new"}}),"读取失败不当缺失");jpeg.InspectionError=failure;
  var csv=MetadataCsv.Export(MetadataCsv.Snapshot([jpeg]));R04Refusal(()=>MetadataCsv.Load(csv.Replace("IFD0:Artist","MakerNotes:OwnerName"),MetadataCsv.Snapshot([jpeg])),"CSV未知标签整批拒绝");
  foreach(var mode in new[]{0,2,3,4}) {
   var options=mode switch {0=>new DatePageOptions(0,Seconds:1),2=>new DatePageOptions(2,Components:new(){["second"]=3}),3=>new DatePageOptions(3,Start:"2026:01:01 00:00:01",End:"2026:01:01 00:00:02"),_=>new DatePageOptions(4,Pattern:@"(embedded)",Template:"2026:01:01 00:00:03")};
   try{var preview=await DatePagePreview.CreateAsync([jpeg],options,0,()=>0,default);Check(preview.Values.Count==1,"日期模式定向-"+mode);}catch(ArgumentException)when(mode==4){Check(true,"文件名模式沿既有捕获模板校验");}
  }
  jpeg.ClearDraft();side.ClearDraft();list.SelectedItems.Clear();list.SelectedItems.Add(jr);list.SelectedItems.Add(sr);
  Control<ComboBox>("RenameProcessingSort").SelectedIndex=3;Action("RefreshRenameOrder");await BatchWait();await Task.Delay(100);
  var groups=(RenameGroup[])Field("renameGroups")!;Check(groups.Length==2&&groups.All(g=>g.Members.All(m=>m.CaptureKnown)),"重命名排序明确主来源");
  Check(groups.Single(g=>g.Leader.Path==jpegPath).Leader.MainCapture==BatchTrackMatch.Capture(jpeg),"重命名与列表同一主日期");
  jpeg.SetDraft(new Dictionary<string,string>{{jpeg.MainDateTag,""}});Action("RefreshRenameOrder");await BatchWait();await Task.Delay(100);groups=(RenameGroup[])Field("renameGroups")!;
  Check(groups.Single(g=>g.Leader.Path==jpegPath).Leader.Shooting is null,"重命名主日期清除不回退");jpeg.ClearDraft();
  // XMP exchange preserves list elements and never imports EXIF targets.
  var packet=Path.Combine(folder,"exchange.xmp");var exchange=await PhotoDocument.LoadAsync(client,jpegPath);exchange.SetDraft(new Dictionary<string,string>{{"XMP-dc:Creator",MetadataFields.FormatList(["a,b","line1\nline2"])}});await MetadataXmp.ExportAsync(client,exchange,packet);var imported=await MetadataXmp.ImportAsync(client,packet);
  Check(MetadataFields.List(imported.Changes["XMP-dc:Creator"]).SequenceEqual(new[]{"a,b","line1\nline2"})&&imported.Changes.Keys.All(t=>t.StartsWith("XMP-",StringComparison.Ordinal)),"XMP交换列表边界及来源隔离");
  foreach(var row in list.Items.Cast<object>())Doc(row).ClearDraft();typeof(MainWindow).GetMethod("FillEditor",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);
 }
 static async Task R04aScale() {
  int count=int.Parse(Environment.GetEnvironmentVariable("PHOTOTRAIL_R02_COUNT")!);var rows=await DateCoreRows(count);var list=Control<ListBox>("Photos");list.SelectedItems.Clear();foreach(var row in rows)list.SelectedItems.Add(row);
  long requests=ExifToolClient.RequestCount,hosts=DateAdapter.StartedProcesses;var clock=Stopwatch.StartNew();double maxGap=0;var last=Stopwatch.GetTimestamp();var timer=new DispatcherTimer(TimeSpan.FromMilliseconds(10),DispatcherPriority.Normal,(_,_)=>{var now=Stopwatch.GetTimestamp();maxGap=Math.Max(maxGap,Stopwatch.GetElapsedTime(last,now).TotalMilliseconds);last=now;},window.Dispatcher);timer.Start();
  Input("ExifCaptureValue","1600:02:29 01:02:03.123456789+05:30");Input("ExifArtistValue","R04a 合成");Action("ApplyDraft");await BatchWait();var editMs=clock.Elapsed.TotalMilliseconds;var editDetails=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTimings")!);var editExif=ExifToolClient.RequestCount-requests;var editHosts=DateAdapter.StartedProcesses-hosts;
  Check(rows.All(r=>Doc(r).Draft.Count==2&&Doc(r).VerifiedCaptureDate is not null),"scale-edit-and-project-"+count);
  var output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");Action("ExecuteSavePlan");await BatchWait();await Task.Delay(50);timer.Stop();
  Check(Directory.GetFiles(output,"*.jpg").Length==count,"scale-representative-save-"+count);
  File.WriteAllText(Path.Combine(folder,"r04a-scale.json"),JsonSerializer.Serialize(new{count,editMs,editDetails,editExifToolRequests=editExif,editDateHostRequests=editHosts,saveMs=clock.Elapsed.TotalMilliseconds-editMs,totalMs=clock.Elapsed.TotalMilliseconds,exifToolRequests=ExifToolClient.RequestCount-requests,dateHostRequests=DateAdapter.StartedProcesses-hosts,maxDispatcherGapMs=maxGap,evidence},new JsonSerializerOptions{WriteIndented=true}));
  foreach(var row in rows)Doc(row).ClearDraft();typeof(MainWindow).GetMethod("FillEditor",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance)!.Invoke(window,[new Dictionary<string,string>()]);
 }
}
