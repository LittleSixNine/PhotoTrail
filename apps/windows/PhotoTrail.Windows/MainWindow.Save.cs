using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
namespace PhotoTrail.Windows;
public partial class MainWindow
{
    SavePlan? preparedSave;
    int preparedMode;
    string preparedOutput="";
    string preparedBackup="";
    string preparedBackupText="";
    int previousSaveMode;
    bool changingSaveMode;
    internal Dictionary<string,double> saveTimings=new();
    internal List<SidecarResult> saveResults=new();
    SaveMode ChosenSaveMode=>SaveModeChoice.SelectedIndex==2?SaveMode.Inplace:SaveModeChoice.SelectedIndex==1?SaveMode.NewSidecar:SaveMode.Copy;
    void SyncSaveMode() {
        if(SaveModeChoice is null)return;
        foreach(var row in photos)
        {
            var doc=row.Document;bool sidecar=ChosenSaveMode==SaveMode.NewSidecar;
            // Undo can restore drafts bound to another target; selection refresh must preserve that binding.
            if(doc.Draft.Count>0&&(!sidecar&&!doc.CanEdit||sidecar&&doc.Draft.Keys.Any(t=>!t.StartsWith("XMP-",StringComparison.Ordinal))))continue;
            doc.SelectSidecarEditing(sidecar);
        }
        SaveModeChoice.IsEnabled=!busy&&!renameRecoveryRequired;
        if(ExecuteSaveButton is not null)ExecuteSaveButton.IsEnabled=!busy&&!renameRecoveryRequired&&preparedSave?.Items.Length>0;
    }
    void SaveModeChanged(object sender,SelectionChangedEventArgs e) {
        if(!IsLoaded||changingSaveMode)return;
        try {
            if(busy||renameRecoveryRequired||ChosenSaveMode!=SaveMode.NewSidecar&&photos.Any(r=>!r.Document.CanEdit&&r.Document.Draft.Count>0))throw new InvalidOperationException(L10n.Text("事务进行中或RAW草稿仍绑定新旁车，模式未改变。"));
            preparedSave=null;ExecuteSaveButton.IsEnabled=false;SyncSaveMode();InvalidateDates();InvalidateBatchTrack();
            bool preserve=preserveBatchEditor;preserveBatchEditor=true;try{RefreshSelection();}finally{preserveBatchEditor=preserve;}
            previousSaveMode=SaveModeChoice.SelectedIndex;Status.Text=L10n.Message(L10n.Text("模式已明确选择；尚未创建文件，草稿与未应用输入保留。"));
        }catch(Exception error){changingSaveMode=true;SaveModeChoice.SelectedIndex=previousSaveMode;changingSaveMode=false;Status.Text=L10n.Message(error.Message);}
    }
    void PrepareSaveAll(object sender,RoutedEventArgs e)=>PrepareSave(photos.Select(r=>r.Document),ChosenSaveMode,SaveScope.All);
    void PrepareSaveWorkspace(object sender,RoutedEventArgs e) {
        int workspace=WorkspaceTabs.SelectedIndex;
        if(workspace is not (0 or 1)){Status.Text=L10n.Message(L10n.Text("当前工作区没有元数据保存范围；重命名不产生第三套草稿。请选元数据或地图，或使用全部待保存。"));return;}
        PrepareSave(photos.Select(r=>r.Document),ChosenSaveMode,workspace==1?SaveScope.Map:SaveScope.Metadata);
    }
    async void PrepareSave(IEnumerable<PhotoDocument> docs,SaveMode mode,SaveScope scope) {
        if(busy||renameRecoveryRequired)return;
        preparedSave=null;ExecuteSaveButton.IsEnabled=false;
        if(InspectorHasInput()){Status.Text=L10n.Message(L10n.Text("保存准备被阻止：有未应用输入，请明确加入草稿；不会隐式保存。"));return;}
        var documents=docs.ToArray();var library=photos.Select(r=>r.Document).ToArray();string output=OutputFolder.Text,backup=BackupFolder.Text;int selectedMode=SaveModeChoice.SelectedIndex;
        BeginOperation();var request=operation!;
        try {
            var plan=await Task.Run(()=>SavePlan.Prepare(documents,mode,scope,output,library,request.Token),request.Token);
            request.Token.ThrowIfCancellationRequested();foreach(var item in plan.Items){SavePlan.Require(item);if(!photos.Any(r=>ReferenceEquals(r.Document,item.Document)))throw new IOException(L10n.Text("照片已移除或来源改变。"));}
            if(OutputFolder.Text!=output||BackupFolder.Text!=backup||SaveModeChoice.SelectedIndex!=selectedMode||InspectorHasInput())throw new IOException(L10n.Text("模式、目标或未应用输入改变，计划失效；未写入。"));
            preparedSave=plan;preparedMode=selectedMode;preparedOutput=output;preparedBackupText=backup;preparedBackup=mode==SaveMode.Inplace?Path.GetFullPath(backup):"";
            if(mode==SaveMode.Inplace&&!Directory.Exists(preparedBackup))throw new IOException(L10n.Text("原位必须先选择可用的既有备份目录。"));
            SaveSummary.Text=plan.Summary+(mode==SaveMode.Inplace?L10n.Format("\n强制备份：{0}；本次{1}份唯一完整字节备份。",preparedBackup,plan.Items.Length):"");ExecuteSaveButton.IsEnabled=plan.Items.Length>0;
            Status.Text=L10n.Message(L10n.Text("请核对冻结摘要；确认前不创建文件。"));
        }catch(Exception error){preparedSave=null;ExecuteSaveButton.IsEnabled=false;SaveSummary.Text=Status.Text=L10n.Message(L10n.Text("保存准备失败（未写入）：")+L10n.Message(error.Message));}
        finally{EndOperation();}
        OpenMetadataTool(SaveTargetTab);
    }
    void CancelSavePlan(object sender,RoutedEventArgs e) {
        if(busy){CancelRead(sender,e);return;}preparedSave=null;ExecuteSaveButton.IsEnabled=false;Status.Text=L10n.Text("\n计划已取消，未创建文件，草稿保留。").TrimStart('\n');SaveSummary.Text+="\n"+Status.Text;
    }
    async void ExecuteSavePlan(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||preparedSave is not {} plan)return;
        if(InspectorHasInput()||preparedMode!=SaveModeChoice.SelectedIndex||(plan.Mode==SaveMode.Copy&&preparedOutput!=OutputFolder.Text||plan.Mode==SaveMode.Inplace&&preparedBackupText!=BackupFolder.Text)){Status.Text=L10n.Message(L10n.Text("模式、目标或未应用输入改变，计划失效；未写入。"));return;}
        var library=photos.Select(r=>r.Document).ToArray();BeginOperation();var request=operation!;
        try {
            foreach(var item in plan.Items){SavePlan.Require(item);if(!photos.Any(r=>ReferenceEquals(r.Document,item.Document)))throw new IOException(L10n.Text("照片已移除或来源改变。"));}
            var check=await Task.Run(()=>SavePlan.Prepare(plan.Items.Select(i=>i.Document),plan.Mode,plan.Scope,plan.Mode==SaveMode.Copy?Path.GetDirectoryName(plan.Items[0].Target)!:"",library,request.Token),request.Token);
            request.Token.ThrowIfCancellationRequested();foreach(var item in plan.Items)SavePlan.Require(item);
            if(!check.Items.Select(i=>i.Target).SequenceEqual(plan.Items.Select(i=>i.Target)))throw new IOException(L10n.Text("目标资格已改变。"));
        }catch(Exception error){Status.Text=L10n.Message(L10n.Text("计划失效，未写入：")+L10n.Message(error.Message));preparedSave=null;ExecuteSaveButton.IsEnabled=false;EndOperation();return;}
        preparedSave=null;long sequence=++rereadSequence;
        var clock=Stopwatch.StartNew();long exif=Interlocked.Read(ref ExifToolClient.RequestCount),hosts=Interlocked.Read(ref DateAdapter.StartedProcesses);saveResults.Clear();
        try {
            var client=Tool();await using var toolSession=client.KeepAlive();
            // Include retained date drafts so source adoption can carry their verified values.
            var dates=await VerifiedMetadataDates.CreateAsync(plan.Items.SelectMany(i=>i.Document.Draft),request.Token);
            batchTimings["saveDateCandidates"]=dates.CandidateCount;batchTimings["saveHostRequests"]=dates.Measurements.Count;
            saveTimings["dateMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            foreach(var item in plan.Items) {
                if(request.IsCancellationRequested){saveResults.Add(new(item.Target,null,null,"取消","尚未执行；草稿保留。"));continue;}
                try {
                    SavePlan.Require(item);
                    if(sequence!=rereadSequence||!photos.Any(r=>ReferenceEquals(r.Document,item.Document)))throw new IOException(L10n.Text("请求或照片身份已失效。"));
                    if(plan.Mode==SaveMode.Copy) {
                        await MetadataCopy.SaveValidatedAsync(client,item.Document,Path.GetDirectoryName(item.Target)!,item.Fields,dates,request.Token);
                        saveResults.Add(new(item.Target,await PhotoDocument.HashAsync(item.Target),null,"成功","副本已验证，原会话草稿保留。"));
                    }else {
                        var result=plan.Mode==SaveMode.Inplace?await InplaceSave.SaveAsync(client,item,preparedBackup,dates,request.Token):await SavePlan.CreateAsync(client,item,dates,request.Token);
                        var refreshClock=Stopwatch.StartNew();
                        if(result.Document is {} next) {
                            try {
                                using var sourceGuard=new FileStream(next.FilePath,FileMode.Open,FileAccess.Read,FileShare.Read);
                                using var sidecarGuard=next.SidecarPath is null?null:new FileStream(next.SidecarPath,FileMode.Open,FileAccess.Read,FileShare.Read);
                                await next.EnsureUnchangedAsync(request.Token);SavePlan.Require(item,source:plan.Mode!=SaveMode.Inplace);
                                if(result.RecordId is {} recordId){var record=InplaceHistory.Read(InplaceHistory.PathFor(recordId));await InplaceHistory.VerifyCurrent(record,record.NewHash!,record.NewIdentity!,request.Token);}
                                if(sequence!=rereadSequence)throw new IOException(L10n.Text("保存请求已失效。"));
                                var old=photos.Single(r=>ReferenceEquals(r.Document,item.Document));var replacement=old.WithDocument(next);bool selected=Photos.SelectedItems.Contains(old);
                                fillingEditor=true;try{int index=photos.IndexOf(old);photos[index]=replacement;if(selected)Photos.SelectedItems.Add(replacement);try{if(result.RecordId is {} savedId)InplaceHistory.Append(InplaceHistory.Read(InplaceHistory.PathFor(savedId)) with{Phase="saved"});}catch{photos[index]=old;if(selected)Photos.SelectedItems.Add(old);throw;}previousSelection=Selected;}finally{fillingEditor=false;}
                                result=result with{State="成功",Detail="真实来源与界面已接纳；本次字段更新基准，残余草稿及完整备份保留。"};
                            }catch(Exception error){result=result with{Document=null,State="结果未知",Detail="磁盘已经提交，但UI／日志接纳失败；旧草稿保留，禁止盲写："+error.Message};}
                        }
                        if(result.RecordId is {} unknownId&&result.Document is null){try{var record=InplaceHistory.Read(InplaceHistory.PathFor(unknownId));if(InplaceHistory.Pending(record))InplaceHistory.Append(record with{Phase="unknown",Detail=result.Detail});}catch(Exception){}}
                        if(result.Timings is {} phases)phases["refreshMs"]=refreshClock.Elapsed.TotalMilliseconds;
                        saveResults.Add(result);
                        if(result.Document is null)item.Document.InspectionError="过期快照："+result.Detail;
                    }
                }catch(OperationCanceledException){saveResults.Add(new(item.Target,null,null,"取消","未确认交付；草稿保留。"));}
                catch(Exception error){bool exists=plan.Mode!=SaveMode.Inplace&&(File.Exists(item.Target)||item.Companion is {} companion&&File.Exists(companion));saveResults.Add(new(item.Target,null,null,exists?"结果未知":"失败",error.Message+(exists?"；磁盘已有目标，所有权／交付状态未确认，禁止盲重试。":"")));}
            }
        }catch(OperationCanceledException){foreach(var item in plan.Items.Where(i=>saveResults.All(r=>r.Path!=i.Target)))saveResults.Add(new(item.Target,null,null,"取消","未执行；草稿保留。"));}
        catch(Exception error){foreach(var item in plan.Items.Where(i=>saveResults.All(r=>r.Path!=i.Target)))saveResults.Add(new(item.Target,null,null,"未执行","批次准备失败，草稿保留："+error.Message));SaveSummary.Text+=L10n.Text("\n批次失败：")+L10n.Message(error.Message);}
        finally {
            saveTimings["writeAndReadbackMs"]=clock.Elapsed.TotalMilliseconds;saveTimings["exifRequests"]=Interlocked.Read(ref ExifToolClient.RequestCount)-exif;saveTimings["dateHostRequests"]=Interlocked.Read(ref DateAdapter.StartedProcesses)-hosts;
            lastApply=null;InvalidateDates();InvalidateBatchTrack();RenameRulesChanged(this,new RoutedEventArgs());RefreshPhotoRows();RefreshMatchPhoto();_=PostPhotosAsync();await LoadInplaceRecords();EndOperation();
            SaveSummary.Text+="\n"+string.Join("\n",saveResults.Select(r=>$"{L10n.Text(r.State)}：{r.Path} SHA={r.Hash??"unknown"}；{L10n.Message(r.Detail)}"));
            Status.Text=L10n.Message(plan.Mode==SaveMode.Copy?L10n.Format("保存结束：副本成功 {0}，失败 {1}，取消 {2}，结果未知 {3}；跳过{4}。详见摘要；原件和会话草稿保留。",saveResults.Count(r=>r.State=="成功"),saveResults.Count(r=>r.State=="失败"),saveResults.Count(r=>r.State=="取消"),saveResults.Count(r=>r.State=="结果未知"),plan.Skipped.Length):L10n.Format("保存结束：成功{0}，失败{1}，取消{2}，结果未知{3}；跳过{4}。详见摘要；备份、结果和未完成草稿保留。",saveResults.Count(r=>r.State=="成功"),saveResults.Count(r=>r.State=="失败"),saveResults.Count(r=>r.State=="取消"),saveResults.Count(r=>r.State=="结果未知"),plan.Skipped.Length));
        }
    }
}
