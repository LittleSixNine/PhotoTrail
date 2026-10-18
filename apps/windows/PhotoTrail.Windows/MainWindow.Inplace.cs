using System.IO;
using System.Diagnostics;
using System.Windows;
using Microsoft.Win32;
namespace PhotoTrail.Windows;
public partial class MainWindow
{
    sealed record RecoveryRow(InplaceRecord Record){public string Label=>$"{Record.Id[..8]} · {Record.Phase} · {Record.Target}";}
    string? reviewedRecovery;
    internal Dictionary<string,double> restoreTimings=new();
    void ChooseBackup(object sender,RoutedEventArgs e) {
        if(busy)return;var dialog=new OpenFolderDialog{Title=L10n.Text("选择原位保存的隔离备份目录")};if(dialog.ShowDialog(this)!=true)return;
        BackupFolder.Text=dialog.FolderName;BackupChanged(sender,e);
    }
    void BackupChanged(object sender,RoutedEventArgs e){if(!IsLoaded||busy)return;settings=settings with{BackupFolder=BackupFolder.Text};SaveSettings();preparedSave=null;ExecuteSaveButton.IsEnabled=false;}
    void LoadInplaceRecords() {
        try{var selected=(InplaceRecords.SelectedItem as RecoveryRow)?.Record.Id;var records=InplaceHistory.ReadAll();InplaceRecords.ItemsSource=records.Select(r=>new RecoveryRow(r)).ToArray();InplaceRecords.SelectedIndex=selected is null?0:Array.FindIndex(records,r=>r.Id==selected);InplaceStatus.Text=L10n.Message(L10n.Format("记录{0}；待核对／恢复{1}。启动不自动改写文件。",records.Length,records.Count(InplaceHistory.Pending)));}
        catch(Exception error){InplaceRecords.ItemsSource=null;InplaceStatus.Text=L10n.Message(L10n.Text("恢复记录不可读取；不得视为无待处理事务，变更操作将保守拒绝：")+L10n.Message(error.Message));}
    }
    void ShowInplaceRecord(object sender,RoutedEventArgs e) {
        reviewedRecovery=null;if(busy||InplaceRecords.SelectedItem is not RecoveryRow row)return;
        try{var r=InplaceHistory.Read(InplaceHistory.PathFor(row.Record.Id));SaveSummary.Text=$"恢复／核对记录：{r.Id}\n版本：{r.Version}；原创建／修改：{r.Original.Created:O}／{r.Original.Written:O}；保存后：{r.SavedProperties?.Created:O}／{r.SavedProperties?.Written:O}\n阶段：{r.Phase}\n目标：{r.Target}\n备份：{r.Backup}\n原SHA：{r.OriginalHash}\n保存后SHA：{r.NewHash??"unknown"}\n恢复：保留当前版本；仅按身份及已知SHA覆盖。外部变化／缺失／损坏拒绝。\n{r.Detail}";reviewedRecovery=r.Id;}
        catch(Exception error){InplaceStatus.Text=L10n.Message(L10n.Text("记录不能核对：")+L10n.Message(error.Message));}
    }
    async void RestoreInplaceRecord(object sender,RoutedEventArgs e)=>await ResolveInplace(true);
    async void CheckInplaceRecord(object sender,RoutedEventArgs e)=>await ResolveInplace(false);
    async Task ResolveInplace(bool restore) {
        if(busy||renameRecoveryRequired||InplaceRecords.SelectedItem is not RecoveryRow selected)return;
        if(reviewedRecovery!=selected.Record.Id){InplaceStatus.Text=L10n.Message(L10n.Text("先核对记录摘要，再明确恢复或接纳；未写入。"));return;}
        if(InspectorHasInput()){InplaceStatus.Text=L10n.Message(L10n.Text("有未应用输入；保留输入，暂不切换来源。"));return;}
        BeginOperation();++rereadSequence;var request=operation!;
        try {
            var client=Tool();await using var toolSession=client.KeepAlive();
            var record=InplaceHistory.Read(InplaceHistory.PathFor(selected.Record.Id));
            if(restore)restoreTimings=await InplaceHistory.RestoreAsync(client,record,request.Token);
            var refreshClock=Stopwatch.StartNew();
            record=InplaceHistory.Read(InplaceHistory.PathFor(record.Id));
            InplaceNative.Inspect(record.Backup);
            if(await PhotoDocument.HashAsync(record.Backup,request.Token)!=record.OriginalHash)throw new IOException(L10n.Text("备份SHA未确认。"));
            var properties=InplaceNative.Inspect(record.Target);var hash=await PhotoDocument.HashAsync(record.Target,request.Token);
            string phase;
            if(hash==record.OriginalHash&&properties.Identity==record.RestoreIdentity)phase="restored";
            else if(hash==record.NewHash&&properties.Identity==record.NewIdentity)phase="saved";
            else if(hash==record.OriginalHash&&properties.Identity==record.Original.Identity)phase="failed";
            else throw new IOException(L10n.Text("实际目标不符合任何已知身份及SHA，保留材料，拒绝接纳或覆盖。"));
            await InplaceHistory.VerifyCurrent(record,hash,properties.Identity,request.Token);
            using var targetGuard=new FileStream(record.Target,FileMode.Open,FileAccess.Read,FileShare.Read);
            using var imageGuard=record.Photo==record.Target?null:new FileStream(record.Photo,FileMode.Open,FileAccess.Read,FileShare.Read);
            if(record.Photo!=record.Target&&(InplaceNative.Inspect(record.Photo).Identity!=record.SourceIdentity||await PhotoDocument.HashAsync(record.Photo,request.Token)!=record.SourceHash))throw new IOException(L10n.Text("旁车对应原图身份已改变。"));
            var next=await PhotoDocument.LoadAsync(client,record.Photo,request.Token,inspect:true);
            if(next.InspectionError.Length>0)throw new IOException(L10n.Text("完整来源读取失败。"));
            var old=photos.SingleOrDefault(r=>r.Document.FilePath==record.Photo);
            if(old is not null) {
                var draft=new Dictionary<string,string>(old.Document.Draft);
                if(phase=="saved"&&draft.Count>0) {
                    if(old.Document.DraftRevision!=record.Revision||(old.Document.SidecarHash??old.Document.SourceHash)!=record.OriginalHash||record.Fields.Any(p=>!draft.TryGetValue(p.Key,out var value)||value!=p.Value))throw new IOException(L10n.Text("旧草稿身份／revision无法证明；保留草稿，禁止套用新SHA。"));
                    foreach(var tag in record.Fields.Keys)draft.Remove(tag);
                }
                var baseline=old.Document.BatchSnapshot();baseline.ReplaceDraft(new Dictionary<string,string>());
                foreach(var tag in draft.Keys)if(baseline.Value(tag)!=next.Value(tag))throw new IOException(L10n.Text("未完成草稿基准不适用；保留旧快照并待核对：")+tag);
                var dates=await VerifiedMetadataDates.CreateAsync(draft,request.Token);await next.SetDraftValidatedAsync(draft,dates,next.DraftRevision,request.Token);
                await next.EnsureUnchangedAsync(request.Token);
                bool wasSelected=Photos.SelectedItems.Contains(old);var replacement=old.WithDocument(next);int index=photos.IndexOf(old);
                fillingEditor=true;
                try{photos[index]=replacement;if(wasSelected)Photos.SelectedItems.Add(replacement);InplaceHistory.Append(record with{Phase=phase});previousSelection=Selected;}
                catch{photos[index]=old;if(wasSelected)Photos.SelectedItems.Add(old);throw;}
                finally{fillingEditor=false;}
            }else InplaceHistory.Append(record with{Phase=phase});
            restoreTimings["refreshMs"]=refreshClock.Elapsed.TotalMilliseconds;lastApply=null;InvalidateDates();InvalidateBatchTrack();RenameRulesChanged(this,new RoutedEventArgs());RefreshPhotoRows();RefreshMatchPhoto();_=PostPhotosAsync();
            InplaceStatus.Text=L10n.Message(phase=="restored"?L10n.Text("恢复字节、元数据、身份及属性已确认；未完成草稿按原基准保留，旧撤销失效。"):L10n.Format("实际结果已核对：{0}；未盲重试。",phase));
        }catch(Exception error){foreach(var row in photos.Where(r=>r.Document.FilePath==selected.Record.Photo))row.Document.InspectionError="过期快照：核对／恢复未确认；"+error.Message;RefreshPhotoRows();InplaceStatus.Text=L10n.Message(L10n.Text("未完成核对／恢复；目标、备份、记录和草稿保留：")+L10n.Message(error.Message));}
        finally{EndOperation();string result=InplaceStatus.Text;LoadInplaceRecords();InplaceStatus.Text+=L10n.Message("\n"+result);reviewedRecovery=null;}
    }
}
