using System.IO;
using System.Windows;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    sealed record RemovedPhotos((PhotoRow Row,int Index,ImportSource? Version)[] Rows,PhotoRow[] Selection);
    readonly Stack<RemovedPhotos> removedPhotos=[];

    private void RemovePhotos(object sender,RoutedEventArgs e)
    {
        if(busy||importRunning||renameRecoveryRequired)return;
        if(InspectorHasInput()){Status.Text=L10n.Message(L10n.Text("请先将输入加入草稿；移除不会放弃未应用输入。"));return;}
        var selection=Selected;
        var groups=selection.Select(r=>r.DisplayGroup.Id).ToHashSet();
        ImportSource? Version(PhotoRow row){try{return ImportSource.Read(row.Document.FilePath);}catch(Exception error)when(error is IOException or UnauthorizedAccessException){return null;}}
        var rows=photos.Select((row,index)=>(Row:row,Index:index)).Where(r=>groups.Contains(r.Row.DisplayGroup.Id)).Select(r=>(r.Row,r.Index,Version:Version(r.Row))).ToArray();
        if(rows.Length==0)return;
        // Keep the actual objects: revisions, paired members and all source snapshots survive undo.
        removedPhotos.Push(new(rows,selection));
        fillingEditor=true;
        try{foreach(var item in rows)photos.Remove(item.Row);}
        finally{fillingEditor=false;}
        PhotoMembershipChanged();
        Status.Text=L10n.Message(L10n.Format("已移除{0}项（含配对成员）；草稿保留，可撤销。磁盘文件未删除。",rows.Length));
    }

    private async void UndoRemovePhotos(object sender,RoutedEventArgs e)
    {
        if(busy||importRunning||renameRecoveryRequired||!removedPhotos.TryPeek(out var saved))return;
        if(InspectorHasInput()){Status.Text=L10n.Message(L10n.Text("请先将输入加入草稿，再撤销移除。"));return;}
        if(saved.Rows.Any(item=>photos.Any(row=>row.Document.FilePath.Equals(item.Row.Document.FilePath,StringComparison.OrdinalIgnoreCase)||
            item.Row.PhysicalIdentity is {} identity&&row.PhysicalIdentity==identity))){Status.Text=L10n.Message(L10n.Text("移除成员已重新导入；拒绝创建重复可写身份，撤销记录与草稿保留。"));return;}
        BeginOperation();
        try
        {
            foreach(var item in saved.Rows)
            {
                try
                {
                    if(item.Version is null)throw new IOException(L10n.Text("移除时来源失联，需重新读取。"));
                    item.Version.RequireCurrent();
                    await item.Row.Document.EnsureUnchangedAsync(operation!.Token);
                    if(item.Row.PhysicalIdentity is {} identity&&ImportSource.Read(item.Row.Document.FilePath).Identity!=identity)
                        throw new IOException(L10n.Text("物理来源身份改变。"));
                }
                catch(Exception error)when(error is IOException or UnauthorizedAccessException)
                {item.Row.Document.InspectionError="过期快照：撤销恢复来源失联或改变，请重新读取；"+error.Message;}
            }
            operation!.Token.ThrowIfCancellationRequested();
            fillingEditor=true;
            try
            {
                foreach(var item in saved.Rows)photos.Insert(Math.Min(item.Index,photos.Count),item.Row);
                Photos.SelectedItems.Clear();foreach(var row in saved.Selection)if(Photos.Items.Contains(row))Photos.SelectedItems.Add(row);
            }
            finally{fillingEditor=false;}
            removedPhotos.Pop();PhotoMembershipChanged();
            Status.Text=L10n.Message(L10n.Text("移除成员、来源快照与完整草稿已恢复；过期来源禁止编辑，文件未修改。"));
        }
        catch(OperationCanceledException){Status.Text=L10n.Message(L10n.Text("撤销已取消；移除记录和草稿保留。"));}
        catch(Exception error){Status.Text=L10n.Message(L10n.Text("撤销未完成，移除记录和草稿保留：")+L10n.Message(error.Message));}
        finally{EndOperation();}
    }

    void PhotoMembershipChanged()
    {
        InvalidateDates();InvalidateBatchTrack();previousSelection=Selected;
        photoPreviewRequest?.Cancel();photoPreviewRevision++;previewDocument=null;PhotoPreviewImage.Source=null;
        RenameRulesChanged(this,new RoutedEventArgs());RefreshPhotoRows();RefreshSelection();SyncPhotoStrip();RefreshMatchPhoto();_=PostPhotosAsync();
    }
}
