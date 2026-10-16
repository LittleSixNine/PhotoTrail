using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace PhotoTrail.Windows;
public partial class MainWindow
{
    sealed record TrackBatch(PhotoRow[] Rows,PhotoDocument[] Frozen,long[] Revisions,TrackSnapshot[] Tracks,bool Overwrite,bool CurrentOnly,BatchTrackResult[] Results){public double GapMinutes{get;init;}=120;}
    TrackBatch? trackBatch;
    int batchTrackRevision;
    CancellationTokenSource? batchTrackRequest;
    bool batchTrackViewing;
    internal volatile bool batchTrackComputing,batchTrackSourceChecking;
    internal int batchTrackCompleted;
    internal long batchTrackStartedTicks,batchTrackEndedTicks,batchTrackCancelTicks;
    internal readonly Dictionary<string,double> batchTrackTimings=[];
    internal int batchTrackRequests;
    TrackSnapshot[] ParticipatingTracks() => (BatchCurrentOnly.IsChecked==true ? tracks.Where(r=>ReferenceEquals(r,TrackList.SelectedItem)) : tracks).Where(r=>!r.SourceUnavailable&&r.Data.Segments.Any(s=>s.Any(p=>p.Time is not null))).Select(r=>r.Snapshot).ToArray();
    void InvalidateBatchTrack() {
        batchTrackRevision++;batchTrackRequest?.Cancel();
        if(trackBatch is {} batch)foreach(var row in batch.Rows)row.Document.DraftChanged-=InvalidateBatchTrack;
        trackBatch=null;
        if(BatchTrackApply is not null){BatchTrackApply.IsEnabled=false;BatchTrackResults.ItemsSource=null;BatchTrackStatus.Text=L10n.Message(L10n.Text("结果已失效，请重新计算；草稿未改变。"));}
        if(batchTrackViewing){batchTrackViewing=false;currentPreview=null;previewAltitude=null;UpdateGpsButton();PostPreview();}
    }
    void BatchTrackOptionsChanged(object sender,RoutedEventArgs e){if(IsLoaded)InvalidateBatchTrack();}
    void RefreshBatchTrackControls() {
        if(BatchTrackCompute is null)return;
        var sources=ParticipatingTracks();BatchTrackSources.Text=L10n.Format("参与轨迹 {0} 条：",sources.Length)+string.Join("；",sources.Select(s=>Path.GetFileName(s.Path)))+L10n.Text("。只使用操作区已加载有效轨迹，历史路径不参与。");
        BatchTrackCompute.IsEnabled=!busy&&!checkingEnvironment&&!renameRecoveryRequired&&Selected.Length>0&&sources.Length>0;
        BatchTrackApply.IsEnabled=!busy&&!checkingEnvironment&&!renameRecoveryRequired&&trackBatch is {} b&&TrackBatchCurrent(b)&&b.Results.Any(r=>r.Point is not null);
        BatchOverwrite.IsEnabled=BatchCurrentOnly.IsEnabled=!busy;
    }
    bool TrackBatchCurrent(TrackBatch batch) => !renameRecoveryRequired&&!checkingEnvironment&&ui.MatchGapMinutes==batch.GapMinutes&&Selected.SequenceEqual(batch.Rows)&&batch.Overwrite==(BatchOverwrite.IsChecked==true)&&batch.CurrentOnly==(BatchCurrentOnly.IsChecked==true)&&ParticipatingTracks().SequenceEqual(batch.Tracks)&&batch.Rows.Select((r,i)=>photos.Contains(r)&&r.Document.DraftRevision==batch.Revisions[i]&&r.Document.CanStage==batch.Frozen[i].CanStage).All(x=>x);
    static async Task CheckTrackBatchSources(TrackBatch batch,List<FileStream> guards,CancellationToken token) {
        foreach(var path in batch.Rows.SelectMany(r=>r.Document.SidecarPath is {} sidecar?new[]{r.Document.FilePath,sidecar}:new[]{r.Document.FilePath}).Concat(batch.Tracks.Select(t=>t.Path)).Distinct(StringComparer.OrdinalIgnoreCase)) {
            token.ThrowIfCancellationRequested();guards.Add(new(path,FileMode.Open,FileAccess.Read,FileShare.Read));
        }
        foreach(var row in batch.Rows)await row.Document.EnsureUnchangedAsync(token);
        foreach(var source in batch.Tracks)await TrackSnapshots.EnsureSourceAsync(source,token);
    }
    private async void ComputeBatchTrack(object sender,RoutedEventArgs e) {
        if(busy||checkingEnvironment||renameRecoveryRequired)return;
        if(Fields.Any(f=>f.Apply.IsChecked==true)){BatchTrackStatus.Text=L10n.Message(L10n.Text("请先应用或撤销编辑区输入；未改变输入或草稿。"));return;}
        ClearMatchMarker();var rows=Selected;var sources=ParticipatingTracks();
        if(rows.Length is <1 or >3000||sources.Length==0||rows.Select(r=>r.Document.SidecarPath??r.Document.FilePath).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=rows.Length){BatchTrackStatus.Text=L10n.Message(L10n.Text("请选择1至3000个不同目标，并加载带逐点时间的轨迹。"));return;}
        BeginOperation();var request=operation!;batchTrackRequest=request;var revision=batchTrackRevision;
        var frozen=rows.Select(r=>r.Document.BatchSnapshot()).ToArray();var batch=new TrackBatch(rows,frozen,frozen.Select(d=>d.DraftRevision).ToArray(),sources,BatchOverwrite.IsChecked==true,BatchCurrentOnly.IsChecked==true,[]){GapMinutes=ui.MatchGapMinutes};
        batchTrackTimings.Clear();batchTrackRequests=0;batchTrackCompleted=0;batchTrackStartedTicks=batchTrackEndedTicks=batchTrackCancelTicks=0;
        var guards=new List<FileStream>();
        bool Current()=>ReferenceEquals(operation,request)&&revision==batchTrackRevision&&!request.IsCancellationRequested;
        try {
            BatchTrackStatus.Text=L10n.Message(L10n.Text("正在逐照片计算匹配；0／")+rows.Length+L10n.Text("，可取消。"));
            var progress=new Progress<int>(count=>{if(Current())BatchTrackStatus.Text=L10n.Message(L10n.Format("正在逐照片计算匹配；{0}／{1}，可取消。",count,rows.Length));});
            var clock=Stopwatch.StartNew();batchTrackRequests++;
            var results=await Task.Run(()=>{
                batchTrackStartedTicks=Stopwatch.GetTimestamp();batchTrackComputing=true;
                try {
                    var output=new BatchTrackResult[rows.Length];
                    for(int i=0;i<output.Length;i++){request.Token.ThrowIfCancellationRequested();output[i]=BatchTrackMatch.Calculate(frozen[i],sources,batch.Overwrite,request.Token,TimeSpan.FromMinutes(batch.GapMinutes));Volatile.Write(ref batchTrackCompleted,i+1);((IProgress<int>)progress).Report(i+1);}
                    return output;
                } finally {batchTrackComputing=false;batchTrackEndedTicks=Stopwatch.GetTimestamp();}
            },request.Token);
            if(!Current())return;batchTrackTimings["matchMs"]=clock.Elapsed.TotalMilliseconds;
            if(!TrackBatchCurrent(batch))throw new InvalidOperationException(L10n.Text("选择、草稿、选项或轨迹已变化。"));
            BatchTrackStatus.Text=L10n.Message(L10n.Text("正在复核全部照片及参与轨迹来源，包括跳过项…"));clock.Restart();batchTrackRequests++;batchTrackSourceChecking=true;
            await Task.Run(()=>CheckTrackBatchSources(batch,guards,request.Token),request.Token);
            batchTrackSourceChecking=false;if(!Current())return;batchTrackTimings["previewSourceMs"]=clock.Elapsed.TotalMilliseconds;
            if(!TrackBatchCurrent(batch))throw new InvalidOperationException(L10n.Text("选择、草稿、选项或轨迹已变化。"));
            trackBatch=batch with{Results=results};foreach(var row in rows)row.Document.DraftChanged+=InvalidateBatchTrack;
            BatchTrackResults.ItemsSource=results.Where(r=>BatchUnsuccessful.IsChecked!=true||r.Status!="成功").ToArray();
            BatchTrackStatus.Text=L10n.Message(L10n.Format("计算完成：成功{0}／{1}；",results.Count(r=>r.Status=="成功"),rows.Length)+string.Join("，",results.Where(r=>r.Status!=L10n.Text("成功")).GroupBy(r=>r.Status).Select(g=>$"{g.Key}{g.Count()}"))+L10n.Text("。仅结果预览，尚未加入草稿。"));
        }catch(Exception error){if(Current()){InvalidateBatchTrack();BatchTrackStatus.Text=L10n.Message(L10n.Text("匹配未执行：")+L10n.Message(error.Message));}}
        finally {
            batchTrackSourceChecking=false;foreach(var guard in guards)guard.Dispose();if(ReferenceEquals(batchTrackRequest,request))batchTrackRequest=null;
            if(ReferenceEquals(operation,request)){if(request.IsCancellationRequested&&revision==batchTrackRevision)BatchTrackStatus.Text=L10n.Message(L10n.Text("匹配已取消，草稿未改变。"));EndOperation();}
        }
    }
    private void BatchTrackFilterChanged(object sender,RoutedEventArgs e) {
        if(trackBatch is {} batch)BatchTrackResults.ItemsSource=batch.Results.Where(r=>BatchUnsuccessful.IsChecked!=true||r.Status!="成功").ToArray();
    }
    private void ViewBatchTrackResult(object sender,SelectionChangedEventArgs e) {
        if(busy||trackBatch is not {} batch||!TrackBatchCurrent(batch)||BatchTrackResults.SelectedItem is not BatchTrackResult{Point:{} point})return;
        ClearPlacePreview();clipboardGpsPreview=false;matchedTrackSource=null;trackMatchRevision++;batchTrackViewing=true;currentPreview=new(point.Longitude,point.Latitude);previewAltitude=point.Elevation;previewMethod="GPS";UpdateGpsButton();PostPreview();
    }
    private async void ApplyBatchTrack(object sender,RoutedEventArgs e) {
        if(busy||checkingEnvironment||renameRecoveryRequired||trackBatch is not {} batch)return;
        if(Fields.Any(f=>f.Apply.IsChecked==true)){BatchTrackStatus.Text=L10n.Message(L10n.Text("请先处理编辑区输入，匹配结果未应用。"));return;}
        if(!TrackBatchCurrent(batch)){InvalidateBatchTrack();return;}
        BeginOperation();var request=operation!;batchTrackRequest=request;int revision=batchTrackRevision;var guards=new List<FileStream>();
        bool Current()=>ReferenceEquals(operation,request)&&revision==batchTrackRevision&&!request.IsCancellationRequested;
        try {
            BatchTrackStatus.Text=L10n.Message(L10n.Text("正在复核全部照片和轨迹来源，尚未加入草稿…"));var clock=Stopwatch.StartNew();batchTrackRequests++;
            await Task.Run(()=>CheckTrackBatchSources(batch,guards,request.Token),request.Token);
            if(!Current())return;batchTrackTimings["applySourceMs"]=clock.Elapsed.TotalMilliseconds;
            if(!TrackBatchCurrent(batch))throw new InvalidOperationException(L10n.Text("选择、草稿、选项或轨迹已变化，整批未应用。"));
            var before=batch.Frozen.Select(d=>new Dictionary<string,string>(d.Draft)).ToArray();var drafts=new Dictionary<string,string>[batch.Rows.Length];
            for(int i=0;i<drafts.Length;i++) {
                var copy=batch.Frozen[i].BatchSnapshot();if(batch.Results[i].Point is {} point)copy.SetDraft(PhotoDocument.PositionChanges(new(point.Longitude,point.Latitude),point.Elevation,"GPS"));drafts[i]=new(copy.Draft);
            }
            var changed=Enumerable.Range(0,drafts.Length).Where(i=>!SameDraft(before[i],drafts[i])).ToArray();request.Token.ThrowIfCancellationRequested();
            clock.Restart();CommitBatchDrafts(batch.Rows,before,drafts,changed);batchTrackTimings["commitMs"]=clock.Elapsed.TotalMilliseconds;
            clock.Restart();if(changed.Length>0){RefreshPhotoRows();RefreshMatchTime();ClearMatchMarker();_=PostPhotosAsync();}batchTrackTimings["refreshMs"]=clock.Elapsed.TotalMilliseconds;
            BatchTrackStatus.Text=L10n.Message(L10n.Format("匹配应用完成：修改{0}张，成功但无变化{1}张，其他保持{2}张。可撤销最近一次应用；保存副本才写文件。",changed.Length,batch.Results.Count(r=>r.Point is not null)-changed.Length,batch.Results.Count(r=>r.Point is null)));
        }catch(Exception error){if(Current())BatchTrackStatus.Text=L10n.Message(L10n.Text("匹配未应用：")+L10n.Message(error.Message));}
        finally {foreach(var guard in guards)guard.Dispose();if(ReferenceEquals(batchTrackRequest,request))batchTrackRequest=null;if(ReferenceEquals(operation,request))EndOperation();}
    }
}
