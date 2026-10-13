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
    bool changingSaveMode;
    internal Dictionary<string,double> saveTimings=new();
    internal List<SidecarResult> saveResults=new();
    SaveMode ChosenSaveMode=>SaveModeChoice.SelectedIndex==1?SaveMode.NewSidecar:SaveMode.Copy;
    void SyncSaveMode() {
        if(SaveModeChoice is null)return;
        foreach(var row in photos)row.Document.SelectSidecarEditing(ChosenSaveMode==SaveMode.NewSidecar);
        SaveModeChoice.IsEnabled=!busy&&!renameRecoveryRequired;
        if(ExecuteSaveButton is not null)ExecuteSaveButton.IsEnabled=!busy&&!renameRecoveryRequired&&preparedSave?.Items.Length>0;
    }
    void SaveModeChanged(object sender,SelectionChangedEventArgs e) {
        if(!IsLoaded||changingSaveMode)return;
        try {
            if(busy||renameRecoveryRequired||ChosenSaveMode==SaveMode.Copy&&photos.Any(r=>!r.Document.CanEdit&&r.Document.Draft.Count>0))throw new InvalidOperationException("事务进行中或RAW草稿仍绑定新旁车，模式未改变。");
            preparedSave=null;ExecuteSaveButton.IsEnabled=false;SyncSaveMode();InvalidateDates();InvalidateBatchTrack();
            bool preserve=preserveBatchEditor;preserveBatchEditor=true;try{RefreshSelection();}finally{preserveBatchEditor=preserve;}
            Status.Text="模式已明确选择；尚未创建文件，草稿与未应用输入保留。";
        }catch(Exception error){changingSaveMode=true;SaveModeChoice.SelectedIndex=SaveModeChoice.SelectedIndex==1?0:1;changingSaveMode=false;Status.Text=error.Message;}
    }
    void PrepareSaveAll(object sender,RoutedEventArgs e)=>PrepareSave(photos.Select(r=>r.Document),ChosenSaveMode,SaveScope.All);
    void PrepareSaveWorkspace(object sender,RoutedEventArgs e) {
        string workspace=(WorkspaceTabs.SelectedItem as TabItem)?.Header?.ToString()??"";
        if(workspace is not ("地图" or "元数据")){Status.Text="当前工作区没有元数据保存范围；重命名不产生第三套草稿。请选元数据或地图，或使用全部待保存。";return;}
        PrepareSave(photos.Select(r=>r.Document),ChosenSaveMode,workspace=="地图"?SaveScope.Map:SaveScope.Metadata);
    }
    void PrepareSave(IEnumerable<PhotoDocument> docs,SaveMode mode,SaveScope scope) {
        if(busy||renameRecoveryRequired)return;
        preparedSave=null;ExecuteSaveButton.IsEnabled=false;
        if(InspectorHasInput()){Status.Text="保存准备被阻止：有未应用输入，请明确加入草稿；不会隐式保存。";return;}
        try {
            var plan=SavePlan.Prepare(docs.ToArray(),mode,scope,OutputFolder.Text,photos.Select(r=>r.Document));
            preparedSave=plan;preparedMode=SaveModeChoice.SelectedIndex;preparedOutput=OutputFolder.Text;SaveSummary.Text=plan.Summary;SaveTargetTab.IsSelected=true;ExecuteSaveButton.IsEnabled=plan.Items.Length>0;
            Status.Text="请核对冻结摘要；确认前不创建文件。";
        }catch(Exception error){SaveSummary.Text=Status.Text="保存准备失败（未写入）："+error.Message;SaveTargetTab.IsSelected=true;}
    }
    void CancelSavePlan(object sender,RoutedEventArgs e) {
        if(busy){CancelRead(sender,e);return;}preparedSave=null;ExecuteSaveButton.IsEnabled=false;SaveSummary.Text+="\n计划已取消，未创建文件，草稿保留。";
    }
    async void ExecuteSavePlan(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||preparedSave is not {} plan)return;
        if(InspectorHasInput()||preparedMode!=SaveModeChoice.SelectedIndex||plan.Mode==SaveMode.Copy&&preparedOutput!=OutputFolder.Text){Status.Text="模式、目标或未应用输入改变，计划失效；未写入。";return;}
        try {
            foreach(var item in plan.Items){SavePlan.Require(item);if(!photos.Any(r=>ReferenceEquals(r.Document,item.Document)))throw new IOException("照片已移除或来源改变。");}
            var check=SavePlan.Prepare(plan.Items.Select(i=>i.Document),plan.Mode,plan.Scope,plan.Mode==SaveMode.Copy?Path.GetDirectoryName(plan.Items[0].Target)!:"",photos.Select(r=>r.Document));
            if(!check.Items.Select(i=>i.Target).SequenceEqual(plan.Items.Select(i=>i.Target)))throw new IOException("目标资格已改变。");
        }catch(Exception error){Status.Text="计划失效，未写入："+error.Message;preparedSave=null;ExecuteSaveButton.IsEnabled=false;return;}
        preparedSave=null;BeginOperation();long sequence=++rereadSequence;var request=operation!;
        var clock=Stopwatch.StartNew();long exif=Interlocked.Read(ref ExifToolClient.RequestCount),hosts=Interlocked.Read(ref DateAdapter.StartedProcesses);saveResults.Clear();
        try {
            var client=Tool();
            // Include retained date drafts so source adoption can carry their verified values.
            var dates=await VerifiedMetadataDates.CreateAsync(plan.Items.SelectMany(i=>i.Document.Draft),request.Token);
            saveTimings["dateMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            foreach(var item in plan.Items) {
                if(request.IsCancellationRequested){saveResults.Add(new(item.Target,null,null,"取消","尚未执行；草稿保留。"));continue;}
                try {
                    SavePlan.Require(item);
                    if(sequence!=rereadSequence||!photos.Any(r=>ReferenceEquals(r.Document,item.Document)))throw new IOException("请求或照片身份已失效。");
                    if(plan.Mode==SaveMode.Copy) {
                        await MetadataCopy.SaveValidatedAsync(client,item.Document,Path.GetDirectoryName(item.Target)!,item.Fields,dates,request.Token);
                        saveResults.Add(new(item.Target,await PhotoDocument.HashAsync(item.Target),null,"成功","副本已验证，原会话草稿保留。"));
                    }else {
                        var result=await SavePlan.CreateAsync(client,item,dates,request.Token);
                        if(result.Document is {} next) {
                            try {
                                using var sourceGuard=new FileStream(next.FilePath,FileMode.Open,FileAccess.Read,FileShare.Read);
                                using var sidecarGuard=new FileStream(next.SidecarPath!,FileMode.Open,FileAccess.Read,FileShare.Read);
                                await next.EnsureUnchangedAsync(request.Token);SavePlan.Require(item);
                                if(sequence!=rereadSequence)throw new IOException("保存请求已失效。");
                                var old=photos.Single(r=>ReferenceEquals(r.Document,item.Document));var replacement=old with{Document=next};bool selected=Photos.SelectedItems.Contains(old);
                                fillingEditor=true;try{photos[photos.IndexOf(old)]=replacement;if(selected)Photos.SelectedItems.Add(replacement);previousSelection=Selected;}finally{fillingEditor=false;}
                            }catch(Exception error){result=result with{Document=null,State="结果未知",Detail="旁车已经创建，但UI接纳新来源失败；旧草稿保留，禁止再次创建："+error.Message};}
                        }
                        saveResults.Add(result);
                        if(result.Document is null)item.Document.InspectionError="过期快照："+result.Detail;
                    }
                }catch(OperationCanceledException){saveResults.Add(new(item.Target,null,null,"取消","未确认交付；草稿保留。"));}
                catch(Exception error){bool exists=File.Exists(item.Target)||item.Companion is {} companion&&File.Exists(companion);saveResults.Add(new(item.Target,null,null,exists?"结果未知":"失败",error.Message+(exists?"；磁盘已有目标，所有权／交付状态未确认，禁止盲重试。":"")));}
            }
        }catch(OperationCanceledException){foreach(var item in plan.Items.Where(i=>saveResults.All(r=>r.Path!=i.Target)))saveResults.Add(new(item.Target,null,null,"取消","未执行；草稿保留。"));}
        catch(Exception error){SaveSummary.Text+="\n批次失败："+error.Message;}
        finally {
            saveTimings["writeAndReadbackMs"]=clock.Elapsed.TotalMilliseconds;saveTimings["exifRequests"]=Interlocked.Read(ref ExifToolClient.RequestCount)-exif;saveTimings["dateHostRequests"]=Interlocked.Read(ref DateAdapter.StartedProcesses)-hosts;
            lastApply=null;InvalidateDates();InvalidateBatchTrack();RenameRulesChanged(this,new RoutedEventArgs());RefreshPhotoRows();RefreshMatchPhoto();_=PostPhotosAsync();EndOperation();
            SaveSummary.Text+="\n"+string.Join("\n",saveResults.Select(r=>$"{r.State}：{r.Path} SHA={r.Hash??"unknown"}；{r.Detail}"));
            Status.Text=$"保存结束：成功{saveResults.Count(r=>r.State=="成功")}，失败{saveResults.Count(r=>r.State=="失败")}，取消{saveResults.Count(r=>r.State=="取消")}，结果未知{saveResults.Count(r=>r.State=="结果未知")}；跳过{plan.Skipped.Length}。详见摘要；原图未改写。";
        }
    }
}
