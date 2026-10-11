using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static string TrackBatchStatus=>Control<TextBlock>("BatchTrackStatus").Text;
 static BatchTrackResult[] Results()=>Control<ListBox>("BatchTrackResults").Items.Cast<BatchTrackResult>().ToArray();
 static async Task TrackBatchCompute(){Action("ComputeBatchTrack");await BatchWait();}
 static async Task TrackBatchApply(){Action("ApplyBatchTrack");await BatchWait();}
 static async Task WaitTrackInput(int count){for(int i=0;i<12000&&(Control<ListBox>("Photos").Items.Count<count||(bool)Field("busy")!||Control<ComboBox>("TrackList").Items.Count==0);i++)await Task.Delay(10);await TrackWait();Check(Control<ListBox>("Photos").Items.Count==count,"synthetic-real-import-"+count);}
 static PhotoDocument Model(PhotoDocument source,Dictionary<string,object> values,string type="XMP") {
  values["File:FileType"]=type;var metadata=JsonSerializer.SerializeToElement(values);
  return (PhotoDocument)typeof(PhotoDocument).GetConstructors(BindingFlags.NonPublic|BindingFlags.Instance).Single().Invoke([source.FilePath,null,metadata,null,source.SourceHash,null]);
 }
 static void TrackModels(PhotoDocument source) {
  var time=DateTimeOffset.Parse("2024-01-15T02:20:30.123456Z");
  TrackSnapshot T(params TrackPoint[][] segments)=>new("model.gpx","synthetic",new TrackData(segments));
  TrackPoint P(double lon,double lat,DateTimeOffset? at,double? ele=12.5)=>new(lon,lat,ele,at);
  var normal=T([P(120,30,time),P(120.01,30.01,time.AddMinutes(1))]);
  PhotoDocument D(string? date="2024:01:15 02:20:30.123456Z",Dictionary<string,object>? extras=null,string type="XMP") {var v=extras??[];if(date is not null)v["XMP-exif:DateTimeOriginal"]=date;return Model(source,v,type);}
  BatchTrackResult M(PhotoDocument doc,params TrackSnapshot[] tracks)=>BatchTrackMatch.Calculate(doc,tracks,false,default);
  Check(M(D(),normal).Method=="recorded","exact-recorded");
  var adjusted=normal with{Data=TrackAdjustment.Adjust(normal.Data,60,100,0),Original=normal.Data};
  Check(M(D("2024:01:15 02:21:30.123456Z"),adjusted).Point!.Longitude!=120,"matching-uses-effective-adjusted-data");
  var unchangedGps=PhotoDocument.PositionChanges(new(120,30),null,"GPS");Check(unchangedGps["XMP-exif:GPSAltitude"]==""&&unchangedGps["XMP-exif:GPSDateTime"]=="","unknown-altitude-and-measurement-time-clear-existing-XMP");
  Check(M(D("2024:01:15 02:21:00.123456Z"),normal).Method=="linear","same-segment-interpolation");
  Check(M(D("2024:01:15 02:21:00.123456Z"),T([P(179,0,time),P(-179,0,time.AddMinutes(1))])).Point!.Longitude==-180,"date-line-interpolation");
  Check(M(D("2024:01:15 02:21:00.123456Z"),T([P(120,30,time)],[P(120,30,time.AddMinutes(1))])).Status=="未匹配","no-cross-segment");
  Check(M(D("2024:01:15 02:21:00.123456Z"),T([P(120,30,time),P(120,30,null),P(120,30,time.AddMinutes(1))])).Status=="未匹配","no-cross-untimed");
  Check(M(D("2024:01:15 02:21:00.123456Z"),T([P(120,30,time),P(120,30,time.AddMinutes(121))])).Status=="未匹配","maximum-gap-120-minutes");
  Check(M(D("2024:01:15 02:21:00.123456Z"),T([P(120,30,time.AddMinutes(1)),P(120,30,time)])).Status=="未匹配","backward-time-no-interpolation");
  Check(M(D(),normal,normal with{Path="second.gpx"}).Status=="成功","multi-track-equivalent");
  Check(BatchTrackMatch.Calculate(D("invalid",new(){{"XMP-exif:GPSLatitude",31},{"XMP-exif:GPSLongitude",121}}),[normal],true,default).Point is null,"overwrite-failure-no-replacement");
  Check(M(D(),normal,T([P(121,30,time)])).Status=="歧义","multi-track-different-over-one-meter");
  Check(M(D(),normal,T([P(120,30,time),P(121,30,time)])).Status=="歧义","any-internal-ambiguity-blocks-batch-photo");
  Check(M(D(),T([P(120,30,null)])).Status=="未匹配","entire-track-untimed");
  Check(M(D(null),normal).Status=="缺失时间","missing-time");
  foreach(string invalid in new[]{"", "wrong", "2024:02:30 00:00:00Z"})Check(M(D(invalid),normal).Status=="非法时间","invalid-time-"+invalid);
  Check(M(D("2024:01:15 02:20:30"),normal).Status=="时区不足","no-local-zone-guess");
  Check(M(D("2024:01:15 02:20:30.123456789Z"),normal).Status=="精度不足","sub-100ns-rejected");
  Check(M(D("2024:01:15 02:20:30.123456000Z"),normal).Status=="成功","exact-representable-nine-digits");
  Check(M(Model(source,new(){{"XMP-exif:DateTimeOriginal",42}}),normal).Status=="非法时间","wrong-date-type");
  var gps=new Dictionary<string,object>{{"XMP-exif:GPSLatitude",30},{"XMP-exif:GPSLongitude",120},{"XMP-exif:GPSMapDatum","WGS-84"}};
  Check(M(D(extras:new(gps)),normal).Status=="已有定位保持","valid-existing-numeric-coordinates-kept");
  Check(BatchTrackMatch.Calculate(D(extras:new(gps)),[normal],true,default).Status=="成功","explicit-overwrite-success");
  foreach(var bad in new[]{new Dictionary<string,object>{{"XMP-exif:GPSLatitude",91},{"XMP-exif:GPSLongitude",120}},new(){{"XMP-exif:GPSLatitude",new[]{1,2}},{"XMP-exif:GPSLongitude",120}},new(){{"XMP-exif:GPSLatitude",30},{"XMP-exif:GPSLongitude",120},{"XMP-exif:GPSMapDatum","GCJ02"}},new(){{"XMP-exif:GPSLatitude",""}}})Check(M(D(extras:bad),normal).Status=="定位无效","malformed-or-unknown-position-not-missing");
  var cleared=D(extras:new(gps));cleared.SetDraft(new Dictionary<string,string>{{"XMP-exif:GPSLatitude",""},{"XMP-exif:GPSLongitude",""}});Check(M(cleared,normal).Status=="成功","explicit-cleared-draft-priority");
  cleared.SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal",""}});Check(M(cleared,normal).Status=="缺失时间","explicit-time-clear-priority");
  Check(M(D(type:"PNG"),normal).Status=="不可编辑","readonly-skipped");
  var exif=Model(source,new(){{"ExifIFD:DateTimeOriginal","2024:01:15 10:20:30"},{"ExifIFD:SubSecTimeOriginal","123456"},{"ExifIFD:OffsetTimeOriginal","+08:00"},{"GPS:GPSLatitude",30},{"GPS:GPSLongitude",120},{"GPS:GPSMapDatum","WGS84"}});
  Check(M(exif,normal).Status=="已有定位保持","embedded-location-priority");
  exif.SetDraft(new Dictionary<string,string>{{"XMP-exif:GPSLatitude",""},{"XMP-exif:GPSLongitude",""}});Check(M(exif,normal).Status=="成功","exif-time-offset-fraction-and-cleared-XMP-override");
 }
 sealed class SourceHeldContext(SynchronizationContext owner):SynchronizationContext {
  public readonly TaskCompletionSource<(SendOrPostCallback,object?)> Posted=new(TaskCreationOptions.RunContinuationsAsynchronously);bool released;
  public override void Post(SendOrPostCallback callback,object? state){
   if(!released && state is not int && (bool)Field("batchTrackSourceChecking")!){Posted.TrySetResult((callback,state));return;}
   owner.Post(_=>{var previous=Current;try{SetSynchronizationContext(this);callback(state);}finally{SetSynchronizationContext(previous);}},null);
  }
  public void Release(){released=true;var (callback,state)=Posted.Task.Result;owner.Post(callback,state);}
 }
 static async Task RunTrackBatch() {
  await WaitTrackInput(3);var list=Control<ListBox>("Photos");var rows=list.Items.Cast<object>().ToArray();var docs=rows.Select(Doc).ToArray();TrackModels(docs[0]);list.SelectAll();
  var source=Snapshot();var trackBytes=File.ReadAllBytes(source.Path);var hashes=docs.Select(d=>d.SourceHash).ToArray();
  foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","earlier rights"}});var before=Drafts(rows);
  await TrackBatchCompute();Check(Results().Select(r=>r.Status).SequenceEqual(new[]{"成功","缺失时间","时区不足"}),"original-selection-order-and-distinct-reasons");Check(SameDrafts(rows,before),"preview-does-not-change-draft");
  Control<CheckBox>("BatchUnsuccessful").IsChecked=true;Check(Results().Length==2&&list.SelectedItems.Count==3,"result-filter-view-only");await TrackBatchApply();Check(docs.Count(d=>d.Draft.ContainsKey("XMP-exif:GPSLatitude"))==1,"apply-successes-despite-unsuccessful-view-filter");Check(docs.All(d=>d.Value("XMP-dc:Rights")=="earlier rights"),"all-earlier-drafts-kept");Action("UndoLastApply");Check(SameDrafts(rows,before),"one-batch-undo-complete-old-drafts");Control<CheckBox>("BatchUnsuccessful").IsChecked=false;
  foreach(var d in docs)d.SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal","2024:01:15 02:20:30.123456Z"}});
  docs[1].SetDraft(PhotoDocument.PositionChanges(new(121,31),8,"MANUAL"));before=Drafts(rows);await TrackBatchCompute();Check(Results()[1].Status=="已有定位保持","WPF-default-keeps-valid-existing");await TrackBatchApply();Check(docs[1].Value("XMP-exif:GPSLongitude")=="121","existing-location-keeps-all-fields");Action("UndoLastApply");Check(SameDrafts(rows,before),"mixed-existing-undo");
  Control<CheckBox>("BatchOverwrite").IsChecked=true;await TrackBatchCompute();Control<ListBox>("BatchTrackResults").SelectedIndex=0;Check(!Control<Button>("GpsDraftButton").IsEnabled,"viewing-one-result-cannot-apply-one-point-to-all");await TrackBatchApply();Check(docs.All(d=>d.Value("XMP-exif:GPSLongitude")=="120"),"explicit-overwrite-success-only");Action("UndoLastApply");
  await TrackBatchCompute();docs[2].SetDraft(new Dictionary<string,string>{{"XMP-dc:Title","changed after preview"}});Check(!Control<Button>("BatchTrackApply").IsEnabled&&Field("trackBatch")is null,"full-draft-revision-invalidation");
  await TrackBatchCompute();Control<CheckBox>("BatchCurrentOnly").IsChecked=true;Check(Field("trackBatch")is null,"participating-option-invalidation");await TrackBatchCompute();Check(Control<TextBlock>("BatchTrackSources").Text.Contains("1 条"),"explicit-current-track-only");
  await TrackBatchCompute();list.SelectedItems.Remove(rows[2]);Check(Field("trackBatch")is null,"selection-invalidation");list.SelectAll();
  docs[2].SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal",""}});await TrackBatchCompute();Check(Results()[2].Status=="缺失时间","skipped-source-is-in-original-snapshot");before=Drafts(rows);File.AppendAllText(docs[2].FilePath," ");await TrackBatchApply();Check(SameDrafts(rows,before)&&TrackBatchStatus.Contains("未应用"),"all-source-recheck-even-previously-skipped");File.WriteAllBytes(docs[2].FilePath,File.ReadAllBytes(Path.Combine(Path.GetDirectoryName(docs[2].FilePath)!,"../original-third.xmp")));
  File.AppendAllText(source.Path," ");await TrackBatchCompute();Check(Field("trackBatch")is null&&TrackBatchStatus.Contains("未执行"),"track-source-change-refuses-preview");File.WriteAllBytes(source.Path,trackBytes);
  File.Move(source.Path,source.Path+".held");await TrackBatchCompute();Check(Field("trackBatch")is null,"track-source-lost-refuses-preview");File.Move(source.Path+".held",source.Path);
  // Hold a real completed background continuation; later success/failure must not update newer state.
  foreach(bool fail in new[]{false,true}) {
   if(fail)File.AppendAllText(source.Path," ");var owner=SynchronizationContext.Current!;var gate=new SourceHeldContext(owner);
   try{SynchronizationContext.SetSynchronizationContext(gate);Action("ComputeBatchTrack");}finally{SynchronizationContext.SetSynchronizationContext(owner);}
   await gate.Posted.Task.WaitAsync(TimeSpan.FromSeconds(15));Check(TrackBatchStatus.Contains("复核全部照片"),"real-source-success-or-failure-continuation-held-"+fail);Action("CancelRead");typeof(MainWindow).GetMethod("EndOperation",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);Control<ComboBox>("TrackList").SelectedIndex=1;
   await TrackBatchCompute();var newer=Field("trackBatch");var message=TrackBatchStatus;gate.Release();await Task.Delay(80);File.WriteAllBytes(source.Path,trackBytes);Check(ReferenceEquals(newer,Field("trackBatch"))&&message==TrackBatchStatus,"late-"+(fail?"failure":"success")+"-cannot-replace-newer-batch");Control<ComboBox>("TrackList").SelectedIndex=0;
  }
  await TrackBatchCompute();await TrackBatchApply();before=Drafts(rows);var undo=Field("lastApply");await TrackBatchCompute();await TrackBatchApply();Check(SameDrafts(rows,before)&&ReferenceEquals(undo,Field("lastApply"))&&TrackBatchStatus.Contains("修改0张"),"zero-net-change-keeps-valid-undo");Action("UndoLastApply");
  list.SelectedItems.Clear();list.SelectedItem=rows[0];Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");await TrackMatch();Check(Control<Button>("GpsDraftButton").IsEnabled,"single-manual-time-match-regression");
  await TrackBatchCompute();await TrackBatchApply();var output=Path.Combine(folder,"saved-copies");Directory.CreateDirectory(output);Input("OutputFolder",output);Action("SaveCopies");await BatchWait();var saved=Directory.GetFiles(output,"*.xmp").Single(f=>!f.Contains("backup"));var client=new ExifToolClient(Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL")!);var reread=await PhotoDocument.LoadAsync(client,saved);Check(reread.Position()is {Latitude:30,Longitude:120}&&reread.Value("XMP-exif:GPSAltitude")=="12.5"&&reread.Value("XMP-dc:Rights")=="earlier rights","copy-save-GPS-elevation-nontarget-readback");Check(Field("lastApply")is null,"save-expires-undo");
  for(int i=0;i<docs.Length;i++)Check(await PhotoDocument.HashAsync(docs[i].FilePath)==hashes[i],"source-hash-unchanged-"+i);
  File.WriteAllText(Path.Combine(folder,"track-batch-results.json"),JsonSerializer.Serialize(evidence,new JsonSerializerOptions{WriteIndented=true}));foreach(var d in docs)d.ClearDraft();Console.WriteLine("TRACK_BATCH_CHECKS="+evidence.Count);
 }
 static async Task RunTrackBatchPerformance() {
  await WaitTrackInput(530);var list=Control<ListBox>("Photos");var all=list.Items.Cast<object>().ToArray();var collection=(IList)Field("photos")!;var output=new List<object>();
  foreach(var row in all)Doc(row).SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal","2024:01:15 02:20:30.123456Z"},{"XMP-dc:Rights","earlier rights"}});
  foreach(int count in new[]{1,100,530})for(int round=0;round<(count==530?3:1);round++) {
   list.SelectedItems.Clear();collection.Clear();foreach(var row in all.Take(count))collection.Add(row);list.SelectAll();await Responsive();var before=Drafts(all.Take(count).ToArray());var exif=ToolRequests();var clock=Stopwatch.StartNew();await TrackBatchCompute();await Responsive();double preview=clock.Elapsed.TotalMilliseconds;Check(Results().Count(r=>r.Status=="成功")==count,"real-match-count-"+count+"-"+round);clock.Restart();await TrackBatchApply();await Responsive();double apply=clock.Elapsed.TotalMilliseconds;
   Check(all.Take(count).All(r=>Doc(r).Position()is{Latitude:30,Longitude:120}),"real-applied-locations-"+count+"-"+round);
   output.Add(new{count,round,previewMs=preview,applyMs=apply,phases=new Dictionary<string,double>((Dictionary<string,double>)Field("batchTrackTimings")!),backgroundRequests=Field("batchTrackRequests"),exifToolRequests=ToolRequests()-exif,dateHostRequests=0,tracks=2,pointsPerTrack=500});Action("UndoLastApply");Check(SameDrafts(all.Take(count).ToArray(),before),"real-complete-undo-"+count+"-"+round);
  }
  File.WriteAllText(Path.Combine(folder,"performance.json"),JsonSerializer.Serialize(new{buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),results=output},new JsonSerializerOptions{WriteIndented=true}));foreach(var row in all)Doc(row).ClearDraft();Console.WriteLine("TRACK_PERFORMANCE_ROUNDS="+output.Count);
 }
 static async Task RunTrackBatchCancel() {
  await WaitTrackInput(530);var list=Control<ListBox>("Photos");var rows=list.Items.Cast<object>().ToArray();foreach(var row in rows)Doc(row).SetDraft(new Dictionary<string,string>{{"XMP-exif:DateTimeOriginal","2024:01:15 02:20:30.123456Z"},{"XMP-dc:Rights","earlier rights"}});list.SelectAll();var before=Drafts(rows);Action("ComputeBatchTrack");
  for(int i=0;i<20000&&(!(bool)Field("batchTrackComputing")!||(int)Field("batchTrackCompleted")!<1);i++)await Task.Yield();
  var active=(bool)Field("batchTrackComputing")!;var completed=(int)Field("batchTrackCompleted")!;var start=(long)Field("batchTrackStartedTicks")!;var cancel=Stopwatch.GetTimestamp();Check(active&&completed>=1&&completed<530,"actual-matching-active-after-completed-photo-before-full-result");Action("CancelRead");await BatchWait();var end=(long)Field("batchTrackEndedTicks")!;
  Check(start<cancel&&cancel<end&&Field("trackBatch")is null&&!Control<Button>("BatchTrackApply").IsEnabled&&SameDrafts(rows,before),"in-computation-cancel-no-preview-no-partial-draft");
  Control<ListBox>("Photos").SelectedItems.Clear();Control<ListBox>("Photos").SelectedItem=rows[0];await TrackBatchCompute();Check(Results().Single().Status=="成功","fresh-preview-after-real-cancel");
  var hashes=new List<object>();foreach(var row in rows){var doc=Doc(row);Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash,"cancel-source-hash");hashes.Add(new{path=Path.GetFileName(doc.FilePath),sha256=doc.SourceHash});}
  File.WriteAllText(Path.Combine(folder,"cancel-stage.json"),JsonSerializer.Serialize(new{start,cancel,end,completedAtCancel=completed,total=530,tracks=1,points=100000,synthetic=true,sourceHashes=hashes,buildSha=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(typeof(MainWindow).Assembly.Location))),evidence},new JsonSerializerOptions{WriteIndented=true}));foreach(var row in rows)Doc(row).ClearDraft();Console.WriteLine("TRACK_REAL_CANCEL="+completed);
 }
}
