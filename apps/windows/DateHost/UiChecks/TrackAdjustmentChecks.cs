using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows.Controls;
using PhotoTrail.Windows;

static partial class Program
{
 static string TrackStatus=>Control<TextBlock>("TrackAdjustmentStatus").Text;
 static object TrackRow()=>Control<ComboBox>("TrackList").SelectedItem;
 static TrackSnapshot Snapshot()=> (TrackSnapshot)TrackRow().GetType().GetProperty("Snapshot")!.GetValue(TrackRow())!;
 static async Task TrackWait(){for(int i=0;i<1200&&((bool)Field("busy")!||(int)Field("trackMatchPending")!>0);i++)await Task.Delay(10);Check(!(bool)Field("busy")!&&(int)Field("trackMatchPending")! ==0,"track-request-settled");}
 static async Task TrackMatch(){Action("MatchTrack");await TrackWait();}
 static async Task<string> MapAudit(){var raw=await Control<Microsoft.Web.WebView2.Wpf.WebView2>("MapView").ExecuteScriptAsync("JSON.stringify({frames:window.__trackFrames||[],fits:window.__fits||0})");return JsonSerializer.Deserialize<string>(raw)!;}
 static async Task RunTrackAdjustment(bool restore)
 {
  for(int i=0;i<1200&&(Control<ListBox>("Photos").Items.Count<3||Control<ComboBox>("TrackList").Items.Count<1);i++)await Task.Delay(10);await TrackWait();var list=Control<ListBox>("Photos");Check(list.Items.Count==3&&Control<ComboBox>("TrackList").Items.Count==1,"track-real-import-three-XMP-and-GPX");var docs=list.Items.Cast<object>().Select(Doc).ToArray();list.SelectedItem=list.Items.Cast<object>().Single(r=>Doc(r).FilePath.EndsWith("a.xmp"));
  if(restore){
   Check(Snapshot().Original is not null&&!TrackAdjustment.Equal(Snapshot().Data,Snapshot().Original!)&&TrackRow().GetType().GetProperty("Undo")!.GetValue(TrackRow())is null,"fresh-process-effective-original-recovered-no-session-undo");
   var current=Snapshot();Action("ReadRecentTrack");await TrackWait();Check(TrackAdjustment.Equal(Snapshot().Data,current.Data),"fresh-reimport-keeps-applied-adjustment");
   Action("RestoreTrackOriginal");await TrackWait();Check(Snapshot().Original is null&&TrackAdjustment.Equal(Snapshot().Data,current.Original!)&&TrackStatus.Contains("恢复原轨迹"),"fresh-process-explicit-restore");
   File.WriteAllText(Path.Combine(folder,"track-restored-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("TRACK_RESTORE_WPF="+evidence.Count);return;
  }
  // Existing Windows Google renderer with a local SDK substitute: no service or key request.
  var html=Path.Combine(AppContext.BaseDirectory,"Web/google.html");var originalHtml=File.ReadAllBytes(html);
  var script=File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Web/google.js")).Replace("post({type:'google-bootstrap'});","window.initGoogle();");
  var stub="window.__fits=0;window.__trackFrames=[];class Data{setStyle(){}addListener(){}forEach(){}remove(){}addGeoJson(){}};class Marker{setMap(){}addListener(){}};window.google={maps:{Map:class{getDiv(){return document.getElementById('map')}setMapTypeId(){}addListener(){}fitBounds(){window.__fits++}setCenter(){}setZoom(){}},Data,Marker,SymbolPath:{CIRCLE:1},LatLngBounds:class{extend(){}}}};";
  File.WriteAllText(html,"<!doctype html><html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'\"></head><body><div id='map'></div><div id='message'>Local track renderer audit</div><script>"+stub+script+";window.chrome.webview.addEventListener('message',e=>{if(e.data.type.startsWith('tracks'))window.__trackFrames.push(e.data)});</script></body></html>");
  typeof(MainWindow).GetField("currentMapPage",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,MapMessage.GooglePage);Control<TabControl>("WorkspaceTabs").SelectedIndex=1;
  try {
   for(int i=0;i<1200&&!(bool)Field("mapReady")!;i++)await Task.Delay(10);Check((bool)Field("mapReady")!,"local-existing-WebView-map-ready");
   var source=Snapshot();string sourceHash=await PhotoDocument.HashAsync(source.Path);await TrackMatch();Check(Control<Button>("GpsDraftButton").IsEnabled,"original-track-photo-match-preview");
   Control<TextBox>("TrackSeconds").Text="1.5";Action("PreviewTrackAdjustment");await TrackWait();var first=(TrackData)Field("trackAdjustmentPreview")!;Action("PreviewTrackAdjustment");await TrackWait();Check(TrackAdjustment.Equal(first,(TrackData)Field("trackAdjustmentPreview")!),"repeat-preview-does-not-accumulate");
   Check(ReferenceEquals(Snapshot(),source)&&Control<Button>("TrackApplyButton").IsEnabled,"preview-effective-unchanged-and-apply-enabled");
   using(var audit=JsonDocument.Parse(await MapAudit())){var frame=audit.RootElement.GetProperty("frames").EnumerateArray().Last();var features=frame.GetProperty("geojson").GetProperty("features").EnumerateArray();Check(features.Any(f=>f.GetProperty("properties").GetProperty("role").GetString()=="current")&&features.Any(f=>f.GetProperty("properties").GetProperty("role").GetString()=="preview"),"both-preview-lines-one-framing-message");}
   Control<TextBox>("TrackSeconds").Text="2";Check(!Control<Button>("TrackApplyButton").IsEnabled&&Field("trackAdjustmentPreview")is null,"parameter-invalidates-preview");Control<TextBox>("TrackSeconds").Text="1.5";Action("PreviewTrackAdjustment");await TrackWait();
   var cached=TrackRow().GetType().GetProperty("MapPayload")!.GetValue(TrackRow());Action("ApplyTrackAdjustment");await TrackWait();Check(Snapshot().Data.Segments[0][0].Time-source.Data.Segments[0][0].Time==TimeSpan.FromSeconds(1.5)&&!Control<Button>("GpsDraftButton").IsEnabled&&ReferenceEquals(cached,TrackRow().GetType().GetProperty("MapPayload")!.GetValue(TrackRow())),"time-apply-persists-clears-match-keeps-coordinate-cache");
   using(var audit=JsonDocument.Parse(await MapAudit()))Check(audit.RootElement.GetProperty("frames").EnumerateArray().Last().GetProperty("type").GetString()=="tracks-no-fit","time-only-update-does-not-refit");
   await TrackMatch();Check(!Control<Button>("GpsDraftButton").IsEnabled,"old-photo-time-does-not-match-shifted-track");Control<TextBox>("MatchTimeValue").Text=Snapshot().Data.Segments[0][0].Time!.Value.ToString("O");await TrackMatch();Check(Control<Button>("GpsDraftButton").IsEnabled,"new-time-matches-effective-track");
   Action("UndoTrackAdjustment");await TrackWait();Check(TrackAdjustment.Equal(Snapshot().Data,source.Data)&&!Control<Button>("TrackUndoButton").IsEnabled&&!Control<Button>("GpsDraftButton").IsEnabled,"session-undo-distinct-from-restore");
   Control<TextBox>("TrackEast").Text="100";Control<TextBox>("TrackNorth").Text="50";Control<TextBox>("TrackSeconds").Text="0";Action("PreviewTrackAdjustment");await TrackWait();var oldCache=TrackRow().GetType().GetProperty("MapPayload")!.GetValue(TrackRow());Action("ApplyTrackAdjustment");await TrackWait();Check(Snapshot().Data.Segments[0][0].Longitude!=source.Data.Segments[0][0].Longitude&&!ReferenceEquals(oldCache,TrackRow().GetType().GetProperty("MapPayload")!.GetValue(TrackRow())),"spatial-apply-invalidates-coordinate-cache");
   using(var audit=JsonDocument.Parse(await MapAudit()))Check(audit.RootElement.GetProperty("frames").EnumerateArray().Last().GetProperty("type").GetString()=="tracks"&&audit.RootElement.GetProperty("fits").GetInt32()>0,"spatial-map-update-and-framing");
   var spatial=Snapshot();Action("ReadRecentTrack");await TrackWait();Check(TrackAdjustment.Equal(Snapshot().Data,spatial.Data),"same-source-reimport-preserves-effective");
   Directory.CreateDirectory(Path.Combine(folder,"export"));Control<TextBox>("TrackExportPath").Text=Path.Combine(folder,"export","adjusted.gpx");Action("ExportTrack");await TrackWait();Check(TrackStatus.Contains("另存成功")&&TrackAdjustment.Equal(TrackReader.ReadGpx(Path.Combine(folder,"export","adjusted.gpx")),Snapshot().Data)&&await PhotoDocument.HashAsync(source.Path)==sourceHash,"real-WPF-export-readback-source-hash");
   Action("ExportTrack");await TrackWait();Check(TrackStatus.Contains("已有目标"),"WPF-export-occupied-target-rejected");
   var beforeFailure=Snapshot();Control<TextBox>("TrackSeconds").Text="2";Action("PreviewTrackAdjustment");await TrackWait();using(var held=new FileStream(TrackSnapshots.DefaultPath,FileMode.Open,FileAccess.Read,FileShare.Read)){Action("ApplyTrackAdjustment");await TrackWait();Check(ReferenceEquals(Snapshot(),beforeFailure)&&TrackStatus.Contains("未应用"),"WPF-persistence-replace-failure-keeps-old-memory");}
   Action("PreviewTrackAdjustment");Action("CancelTrackAdjustment");await TrackWait();Check(ReferenceEquals(Snapshot(),beforeFailure)&&!Control<Button>("TrackApplyButton").IsEnabled,"cancel-no-effective-change-no-late-preview");
   var bytes=File.ReadAllBytes(source.Path);File.AppendAllText(source.Path," ");Action("PreviewTrackAdjustment");await TrackWait();Check(ReferenceEquals(Snapshot(),beforeFailure)&&!Control<Button>("TrackApplyButton").IsEnabled&&TrackStatus.Contains("变化"),"changed-source-preview-rejected");
   Action("RestoreTrackOriginal");await TrackWait();Check(Snapshot().Original is null&&Snapshot().SourceHash!=sourceHash&&TrackAdjustment.Equal(Snapshot().Data,source.Data),"explicit-restore-rereads-changed-source");
   File.Move(source.Path,source.Path+".hold");try{Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");await TrackMatch();Check(!Control<Button>("GpsDraftButton").IsEnabled&&Snapshot().Data.Segments.Count==2,"lost-source-cannot-match-view-data-kept");}finally{File.Move(source.Path+".hold",source.Path);}
   Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");await TrackMatch();Check(Control<Button>("GpsDraftButton").IsEnabled,"source-return-matches-before-next-loss");File.Move(source.Path,source.Path+".hold");try{Action("AddGpsDraft");await Task.Delay(30);Check(!Control<Button>("GpsDraftButton").IsEnabled&&docs.All(d=>d.Draft.Count==0),"source-lost-after-match-cannot-enter-GPS-drafts");}finally{File.Move(source.Path+".hold",source.Path);}
   File.WriteAllBytes(source.Path,bytes);Action("RestoreTrackOriginal");await TrackWait();
   Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");Action("MatchTrack");Check((int)Field("trackMatchPending")!>0,"matching-request-pending-before-new-preview-state");var manualPoint=new MapPoint(11,22);typeof(MainWindow).GetField("currentPreview",BindingFlags.NonPublic|BindingFlags.Instance)!.SetValue(window,manualPoint);typeof(MainWindow).GetMethod("UpdateGpsButton",BindingFlags.NonPublic|BindingFlags.Instance)!.Invoke(window,null);await TrackWait();Check(ReferenceEquals(Field("currentPreview"),manualPoint),"late-match-does-not-overwrite-new-manual-preview-state");
   Control<TextBox>("MatchTimeValue").Text=source.Data.Segments[0][0].Time!.Value.ToString("O");Action("MatchTrack");Action("RemoveTrack");await TrackWait();Check(Field("currentPreview")is null&&!Control<Button>("GpsDraftButton").IsEnabled,"late-match-cannot-resurrect-removed-track");Action("ReadRecentTrack");await TrackWait();
   // Proportionate checks of accepted date, settings and rename call chains.
   list.SelectAll();SelectMetadataTab("批量日期");Control<ComboBox>("DateMode").SelectedIndex=2;Control<TextBox>("DateReplaceHour").Text="12";Action("ApplyDates");await BatchWait();Check(Status.Contains("修改2张")&&Status.Contains("缺失时间跳过1项"),"accepted-date-missing-direct-regression");Action("UndoLastApply");
   int font=Control<ComboBox>("MetadataTextSize").SelectedIndex;Control<ComboBox>("MetadataTextSize").SelectedIndex=(font+1)%3;Control<ComboBox>("MetadataTextSize").SelectedIndex=font;Check(docs.All(d=>d.Draft.Count==0),"settings-and-track-adjustment-do-not-write-photos");
   SelectMetadataTab("重命名");Control<TextBox>("RenameRules").Text="set|track_\nsequence|1|1|3";Action("RefreshRenameOrder");await RenameWait();Action("FreezeRename");await RenameWait();Check(Field("frozenRenamePlan")is RenamePlan plan&&plan.Files.Count==3,"rename-freeze-identities-after-track-adjustment");
   Control<TextBox>("TrackSeconds").Text="1.5";Control<TextBox>("TrackEast").Text="0";Control<TextBox>("TrackNorth").Text="0";Action("PreviewTrackAdjustment");await TrackWait();Action("ApplyTrackAdjustment");await TrackWait();Check(Snapshot().Original is not null,"leave-persisted-adjustment-for-fresh-process-restore");
   foreach(var doc in docs)Check(await PhotoDocument.HashAsync(doc.FilePath)==doc.SourceHash&&doc.Draft.Count==0,"synthetic-photo-source-and-draft-protection");
   File.WriteAllText(Path.Combine(folder,"track-ui-results.json"),JsonSerializer.Serialize(new{passed=evidence.Count,evidence,mapAudit=JsonDocument.Parse(await MapAudit()).RootElement.Clone(),sourceHash},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("TRACK_WPF_CHECKS="+evidence.Count);
  }finally{File.WriteAllBytes(html,originalHtml);}
 }
}
