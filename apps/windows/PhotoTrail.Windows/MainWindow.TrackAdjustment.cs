using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace PhotoTrail.Windows;
public partial class MainWindow
{
    int trackAdjustmentRevision,trackMatchRevision,trackMatchPending;
    bool trackAdjustmentWorking;
    TrackSnapshot? matchedTrackSource;
    TrackRow? trackAdjustmentRow;
    TrackSnapshot? trackAdjustmentBefore;
    TrackData? trackAdjustmentPreview;
    void InvalidateTrackAdjustment()
    {
        trackAdjustmentRevision++;trackAdjustmentPreview=null;trackAdjustmentRow=null;trackAdjustmentBefore=null;
        if(trackAdjustmentWorking)operation?.Cancel();
        if(TrackApplyButton is not null)TrackApplyButton.IsEnabled=false;
    }
    private void TrackAdjustmentChanged(object sender,RoutedEventArgs e)
    {
        bool hadPreview=trackAdjustmentPreview is not null;InvalidateTrackAdjustment();
        if(hadPreview){TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("参数已改变，请重新预览。"));_=PostTrackAsync(fit:false);}
    }
    private void TrackAdjustmentExpanded(object sender,RoutedEventArgs e)=>RefreshTrackControls();
    void RefreshTrackControls()
    {
        if(TrackPreviewButton is null)return;
        var row=TrackList.SelectedItem as TrackRow;
        TrackPreviewButton.IsEnabled=!busy&&row is not null&&!row.SourceUnavailable;
        TrackApplyButton.IsEnabled=!busy&&trackAdjustmentPreview is not null&&row==trackAdjustmentRow&&!TrackAdjustment.Equal(row!.Data,trackAdjustmentPreview);
        TrackUndoButton.IsEnabled=!busy&&row?.Undo is not null&&!row.SourceUnavailable;
        TrackRestoreButton.IsEnabled=!busy&&row is not null&&(row.Snapshot.Original is not null||row.SourceUnavailable);
        TrackExportButton.IsEnabled=!busy&&row is not null;
        if(row?.SourceUnavailable==true)TrackInfo.Text=L10n.Message(row.Name+L10n.Text("：来源变化或失联，保留查看数据；请恢复原轨迹后调整或匹配。"));
    }
    async Task EnsureTrackSource(TrackRow row,CancellationToken token=default)
    {
        try{await TrackSnapshots.EnsureSourceAsync(row.Snapshot,token);row.SourceUnavailable=false;}
        catch(IOException){row.SourceUnavailable=true;ClearMatchMarker();MatchResult.Text=L10n.Message(L10n.Text("轨迹来源变化或失联，匹配资格已清除。"));RefreshTrackControls();throw;}
    }
    private async void PreviewTrackAdjustment(object sender,RoutedEventArgs e)
    {
        if(busy||TrackList.SelectedItem is not TrackRow row)return;
        InvalidateTrackAdjustment();int revision=trackAdjustmentRevision;var snapshot=row.Snapshot;
        BeginOperation();trackAdjustmentWorking=true;var token=operation!.Token;
        try {
            double Number(TextBox box)=>double.TryParse(box.Text,NumberStyles.Float,CultureInfo.InvariantCulture,out var value)&&double.IsFinite(value)&&value>=0?value:throw new ArgumentException(L10n.Text("轨迹偏移量须为非负有限数字，用方向选择正负。"));
            double seconds=(Number(TrackDays)*86400+Number(TrackHours)*3600+Number(TrackMinutes)*60+Number(TrackSeconds))*(TrackTimeDirection.SelectedIndex==0?1:-1);
            double east=Number(TrackEast)*(TrackEastDirection.SelectedIndex==0?1:-1),north=Number(TrackNorth)*(TrackNorthDirection.SelectedIndex==0?1:-1);
            await EnsureTrackSource(row,token);
            var result=await Task.Run(()=>TrackAdjustment.Adjust(snapshot.Data,seconds,east,north,token),token);
            await EnsureTrackSource(row,token);token.ThrowIfCancellationRequested();
            if(revision!=trackAdjustmentRevision||row!=TrackList.SelectedItem||!ReferenceEquals(snapshot,row.Snapshot))return;
            trackAdjustmentRow=row;trackAdjustmentBefore=snapshot;trackAdjustmentPreview=result;
            var times=result.Segments.SelectMany(s=>s).Where(p=>p.Time is not null).Select(p=>p.Time!.Value).ToArray();
            TrackAdjustmentStatus.Text=L10n.Message(L10n.Format("预览：时间{0:R}秒，东{1:R}米，北{2:R}米；{3}段／{4}点。",seconds,east,north,result.Segments.Count,result.Segments.Sum(s=>s.Count))+(times.Length>0?$" {times.Min():O} → {times.Max():O}。":L10n.Text(" 无时间点保持无时间。"))+(TrackAdjustment.Equal(snapshot.Data,result)?L10n.Text("无变化，不可应用。"):L10n.Text("蓝色当前／橙色预览，同一视野；尚未应用。")));
            await PostTrackAsync();
        }catch(Exception error){if(revision==trackAdjustmentRevision)TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("轨迹未预览：")+(error is OperationCanceledException?L10n.Text("已取消。"):L10n.Message(error.Message)));}
        finally{trackAdjustmentWorking=false;EndOperation();}
    }
    private void CancelTrackAdjustment(object sender,RoutedEventArgs e)
    {InvalidateTrackAdjustment();TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("调整预览已取消，有效轨迹未改变。"));_=PostTrackAsync(fit:false);RefreshTrackControls();}
    private async void ApplyTrackAdjustment(object sender,RoutedEventArgs e)
    {
        if(busy||trackAdjustmentRow is not {} row||trackAdjustmentPreview is not {} data||trackAdjustmentBefore is not {} before||row!=TrackList.SelectedItem||!ReferenceEquals(row.Snapshot,before)||TrackAdjustment.Equal(row.Data,data))return;
        BeginOperation();trackAdjustmentWorking=true;
        try{await CommitTrack(row,new(row.Path,before.SourceHash,data,before.Original??before.Data),before,rememberUndo:true,operation!.Token);TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("轨迹调整已保存并应用；旧匹配已清除，照片未修改。"));}
        catch(Exception error){TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("轨迹未应用，保留旧状态：")+L10n.Message(error.Message));}
        finally{trackAdjustmentWorking=false;InvalidateTrackAdjustment();EndOperation();}
    }
    async Task CommitTrack(TrackRow row,TrackSnapshot updated,TrackSnapshot expected,bool rememberUndo,CancellationToken token)
    {
        if(updated.SourceHash==expected.SourceHash)await EnsureTrackSource(row,token);
        await TrackSnapshots.SaveAsync(TrackSnapshots.DefaultPath,updated,expected,token);
        bool spatial=!TrackAdjustment.SameCoordinates(expected.Data,updated.Data);
        row.Snapshot=updated;row.Undo=rememberUndo?expected.Data:null;row.SourceUnavailable=false;
        if(spatial)row.MapPayload=null;
        InvalidateTrackAdjustment();ClearMatchMarker();MatchResult.Text=L10n.Message(L10n.Text("有效轨迹已更新，请重新预览时间匹配；照片未修改。"));
        TrackInfo.Text=L10n.Message(L10n.Format("{0}：{1}段，{2}点；已保存当前状态。",row.Name,row.Data.Segments.Count,row.Data.Segments.Sum(s=>s.Count)));
        await PostTrackAsync(fit:spatial);
    }
    private async void UndoTrackAdjustment(object sender,RoutedEventArgs e)
    {
        if(busy||TrackList.SelectedItem is not TrackRow row||row.Undo is not {} previous)return;
        var before=row.Snapshot;BeginOperation();
        try{await CommitTrack(row,before with{Data=previous},before,false,operation!.Token);TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("最近一次调整已撤销并保存；不等同恢复源轨迹。"));}
        catch(Exception error){TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("未撤销，保留旧状态：")+L10n.Message(error.Message));}
        finally{EndOperation();}
    }
    private async void RestoreTrackOriginal(object sender,RoutedEventArgs e)
    {
        if(busy||TrackList.SelectedItem is not TrackRow row)return;
        var before=row.Snapshot;BeginOperation();
        try{var source=await TrackSnapshots.ReadSourceAsync(row.Path,operation!.Token);await CommitTrack(row,source,before,false,operation.Token);TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("已重新读取并恢复原轨迹，保存成功；会话撤销已清除。"));}
        catch(Exception error){TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("未恢复，保留有效轨迹：")+L10n.Message(error.Message));}
        finally{EndOperation();}
    }
    private void ChooseTrackExport(object sender,RoutedEventArgs e)
    {if(busy)return;var dialog=new SaveFileDialog{Filter="GPX|*.gpx",DefaultExt=".gpx",OverwritePrompt=false,FileName="adjusted-track.gpx"};if(dialog.ShowDialog(this)==true)TrackExportPath.Text=dialog.FileName;}
    private async void ExportTrack(object sender,RoutedEventArgs e)
    {
        if(busy||TrackList.SelectedItem is not TrackRow row)return;
        if(TrackExportPath.Text.Length==0){ChooseTrackExport(sender,e);if(TrackExportPath.Text.Length==0)return;}
        var snapshot=row.Snapshot;var target=TrackExportPath.Text;BeginOperation();
        try{await TrackAdjustment.ExportAsync(snapshot.Data,row.Path,target,operation!.Token);TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("GPX另存成功，回读一致；源文件及照片未修改。"));}
        catch(Exception error){TrackAdjustmentStatus.Text=L10n.Message(L10n.Text("GPX未导出：")+(error is OperationCanceledException?L10n.Text("已取消，未留下残缺目标。"):L10n.Message(error.Message)));}
        finally{EndOperation();}
    }
}
