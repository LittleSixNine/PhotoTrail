using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace PhotoTrail.Windows;
public partial class MainWindow
{
    internal readonly Dictionary<string,double> batchTimings=[];
    internal int batchHostRequests;
    internal DateAdapter? batchDateAdapter;
    internal volatile bool batchCalculationStarted;
    internal long batchCalculationTicks,batchFinishedTicks;
    sealed record BatchDetails(int Missing=0,int FilenameMismatch=0,int FilenameInvalid=0,int CsvIdentity=0,int CsvUnknown=0,IReadOnlyList<Measurement>? Measurements=null,double InitialSourceMs=0,int CopyMissing=0,int OperationCount=0,int DateCandidates=0,int CsvInvalid=0,double ProjectionHostMs=0,int ProjectionRequests=0,double ParameterValidationMs=0);
    sealed record AppliedBatch(PhotoRow[] Rows,Dictionary<string,string>[] Before,long[] Revisions);
    AppliedBatch? lastApply;
    bool preserveBatchEditor;
    static bool SameDraft(IReadOnlyDictionary<string,string> a,IReadOnlyDictionary<string,string> b)=>a.Count==b.Count&&a.All(p=>b.TryGetValue(p.Key,out var value)&&value==p.Value);
    bool LastApplyCurrent()=>lastApply is {} batch&&batch.Rows.Select((row,i)=>photos.Contains(row)&&row.Document.DraftRevision==batch.Revisions[i]).All(x=>x);
    Dictionary<string,string> ReadFieldInput()=>Fields.Where(f=>f.Apply.IsChecked==true).ToDictionary(f=>f.Tag,f=>MetadataIptc.Fields.ContainsKey(f.Tag)?f.Value.Text:f.Value.Text.Replace("\r\n","\n"));
    DatePageOptions ReadDateInput() {
        int Number(System.Windows.Controls.TextBox box)=>int.TryParse(box.Text,System.Globalization.NumberStyles.AllowLeadingSign,System.Globalization.CultureInfo.InvariantCulture,out var n)?n:throw new ArgumentException("调整量须为整数。");
        long Seconds(System.Windows.Controls.TextBox box)=>long.TryParse(box.Text,System.Globalization.NumberStyles.AllowLeadingSign,System.Globalization.CultureInfo.InvariantCulture,out var n)?n:throw new ArgumentException("秒数须为整数。");
        Dictionary<string,long> Components(){var values=new Dictionary<string,long>();foreach(var (key,box) in new[]{("year",DateReplaceYear),("month",DateReplaceMonth),("day",DateReplaceDay),("hour",DateReplaceHour),("minute",DateReplaceMinute),("second",DateReplaceSecond)})if(box.Text.Length>0)values[key]=Number(box);return values;}
        DatePageOptions options=DateMode.SelectedIndex switch {
            0=>new(0,Seconds(DateYears),Seconds(DateMonths),Seconds(DateDays),Seconds(DateHours),Seconds(DateMinutes),Seconds(DateSeconds)),
            1=>new(1,Seconds:Seconds(DateStep),Start:DateStart.Text),2=>new(2,Components:Components()),
            3=>new(3,Start:DateStart.Text,End:DateEnd.Text),_=>new(4,Pattern:DateFilenamePattern.Text,Template:DateFilenameTemplate.Text)
        };
        return options with{Target=(DateTarget.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Tag as string};
    }
    private async void ApplyDates(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired)return;
        if(dateEditorWindow is not null&&!dateEditorSelection.SequenceEqual(Selected)){Status.Text=WText("SelectionChanged");return;}
        try {
            if(InspectorHasInput())throw new InvalidOperationException("请先应用编辑区输入。");
            var options=ReadDateInput();string input=JsonSerializer.Serialize(options);
            await ApplyMetadataBatch("日期",async(docs,revision,token)=>{
                var plan=await DatePagePreview.CalculateAsync(docs,options,revision,()=>Volatile.Read(ref dateRevision),token,()=>{if(revision==Volatile.Read(ref dateRevision)&&!token.IsCancellationRequested){batchCalculationTicks=Stopwatch.GetTimestamp();batchCalculationStarted=true;}},adapter=>{if(revision==Volatile.Read(ref dateRevision))batchDateAdapter=adapter;});
                plan.Apply();return new(plan.MissingCount,plan.FilenameMismatchCount,plan.FilenameInvalidCount,Measurements:plan.Measurements,InitialSourceMs:plan.SourceCheckMs,ProjectionHostMs:plan.ProjectionHostMs,ProjectionRequests:plan.ProjectionRequests);
            },()=>!Fields.Any(f=>f.Apply.IsChecked==true)&&JsonSerializer.Serialize(ReadDateInput())==input);
        }catch(Exception error){Status.Text="日期未应用："+DateFailureText(error);}
    }
    private async void ApplyDraft(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired)return;
        try {
            var changes=ReadFieldInput();if(changes.Count==0){Status.Text="请先勾选要修改的字段。";return;}PhotoDocument.ValidateChanges(changes);
            string input=JsonSerializer.Serialize(changes);
            await ApplyMetadataBatch("字段",(docs,_,token)=>{foreach(var doc in docs){token.ThrowIfCancellationRequested();doc.StageDraft(changes);}return Task.FromResult(new BatchDetails());},()=>JsonSerializer.Serialize(ReadFieldInput())==input);
        }catch(Exception error){Status.Text="字段未应用："+error.Message;}
    }
    private async void ApplyCsv(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired)return;
        try {
            if(InspectorHasInput())throw new InvalidOperationException("请先应用编辑区输入。");
            string path=CsvPath.Text;string? sourceHash=null;
            await ApplyMetadataBatch("CSV",async(docs,_,token)=>{
                using var guard=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
                if(guard.Length>MetadataCsv.MaximumBytes)throw new InvalidDataException("CSV超过8MiB上限。");
                sourceHash=await PhotoDocument.HashAsync(path,token);
                using var reader=new StreamReader(guard,new System.Text.UTF8Encoding(false,true),true);
                var result=await MetadataCsv.ValidateRowsAsync(MetadataCsv.Load(await reader.ReadToEndAsync(token),MetadataCsv.Snapshot(docs)),docs,token);
                var targets=docs.ToDictionary(d=>MetadataCsv.Identity(d.FilePath));
                foreach(var (id,changes) in result.Changes){token.ThrowIfCancellationRequested();targets[id].StageDraft(changes);}
                return new(CsvIdentity:result.IdentitySkippedCount,CsvUnknown:result.UnknownFieldCount,CsvInvalid:result.InvalidRowCount);
            },()=>CsvPath.Text==path&&!InspectorHasInput(),async token=>{if(await PhotoDocument.HashAsync(path,token)!=sourceHash)throw new IOException("CSV来源已改变。");},inputPath:path);
        }catch(Exception error){Status.Text="CSV未应用："+error.Message;}
    }
    async Task ApplyMetadataBatch(string label,Func<PhotoDocument[],int,CancellationToken,Task<BatchDetails>> calculate,Func<bool> inputCurrent,Func<CancellationToken,Task>? inputSource=null,string? inputPath=null) {
        var selection=Selected;var order=photos.ToArray();var sortState=PhotoSort.SelectedIndex;
        if(selection.Length is <1 or >3000||selection.Any(r=>!r.Document.CanStage)||selection.Select(r=>r.Document.SidecarPath??r.Document.FilePath).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=selection.Length)throw new InvalidOperationException("请选择1至3000个不同的可编辑文件。");
        var frozen=selection.Select(r=>r.Document.BatchSnapshot()).ToArray();var before=frozen.Select(d=>new Dictionary<string,string>(d.Draft)).ToArray();var revisions=frozen.Select(d=>d.DraftRevision).ToArray();
        BeginOperation();var request=operation!;dateRequest=request;int revision=dateRevision;datePending++;batchTimings.Clear();batchHostRequests=0;batchDateAdapter=null;batchCalculationStarted=false;batchCalculationTicks=batchFinishedTicks=0;
        var sourceGuards=new List<FileStream>();bool completed=false;
        bool Current()=>ReferenceEquals(operation,request)&&revision==dateRevision&&!request.IsCancellationRequested;
        void ValidateState(){if(selection.Any(r=>r.Document.Times is {} times&&times!=SourceTimes.Read(r.Document.FilePath)))throw new IOException("终态原图系统属性已改变，整批未应用。");if(frozen.Any(d=>d.Draft.Keys.Any(MetadataTimes.IsSystem)&&d.TimeZoneSnapshot!=MetadataTimes.Zone))throw new IOException("本机时区已改变，整批未应用。");if(!Current()||!busy||renameRecoveryRequired||checkingEnvironment||!Selected.SequenceEqual(selection)||!photos.SequenceEqual(order)||PhotoSort.SelectedIndex!=sortState||!inputCurrent()||selection.Select((r,i)=>r.Document.DraftRevision==revisions[i]&&r.Document.CanStage&&photos.Contains(r)&&((r.Document.SidecarPath is not null)==(!r.Document.FilePath.Equals(Path.ChangeExtension(r.Document.FilePath,".xmp"),StringComparison.OrdinalIgnoreCase)&&File.Exists(Path.ChangeExtension(r.Document.FilePath,".xmp"))))).Any(x=>!x))throw new InvalidOperationException("选择、参数、草稿或任务状态已改变，整批未应用。");}
        try {
            Status.Text="正在计算与校验"+label+"；可取消，尚未加入草稿。";
            var clock=Stopwatch.StartNew();var result=await Task.Run(async()=>{
                var details=await calculate(frozen,revision,request.Token);
                if(label=="日期")return details;
                var dates=await VerifiedMetadataDates.CreateAsync(frozen.SelectMany(d=>d.DateCandidates),request.Token,adapter=>{batchDateAdapter=adapter;adapter.CalculationStarted+=()=>{if(Current()){batchCalculationTicks=Stopwatch.GetTimestamp();batchCalculationStarted=true;}};});
                foreach(var doc in frozen){foreach(var pair in doc.DateCandidates)dates.Require(new Dictionary<string,string>{{pair.Key,pair.Value}});doc.AcceptDateInputs(dates);}
                return details with{Measurements=(details.Measurements??Array.Empty<Measurement>()).Concat(dates.Measurements).ToArray(),DateCandidates=dates.CandidateCount,ProjectionHostMs=dates.Measurements.Sum(m=>m.TotalMs),ProjectionRequests=dates.Measurements.Count};
            },request.Token);
            if(!Current())return;batchTimings["dateCandidates"]=result.DateCandidates;batchTimings["projectionHostMs"]=result.ProjectionHostMs;batchTimings["projectionRequests"]=result.ProjectionRequests;batchTimings["computeMs"]=clock.Elapsed.TotalMilliseconds;
            batchHostRequests=result.Measurements?.Count??0;batchTimings["hostComputeMs"]=result.Measurements?.Sum(m=>m.ComputeMs)??0;batchTimings["hostTotalMs"]=result.Measurements?.Sum(m=>m.TotalMs)??0;batchTimings["initialSourceMs"]=result.InitialSourceMs;batchTimings["parameterValidationMs"]=result.ParameterValidationMs;
            if(!Current())return;ValidateState();Status.Text="正在复核全部来源，包括无变化及跳过项…";clock.Restart();
            await Task.Run(async()=>{foreach(var path in selection.SelectMany(r=>r.Document.SidecarPath is {} sidecar?new[]{r.Document.FilePath,sidecar}:new[]{r.Document.FilePath}).Concat(inputPath is null?Array.Empty<string>():new[]{inputPath}).Distinct(StringComparer.OrdinalIgnoreCase)){request.Token.ThrowIfCancellationRequested();sourceGuards.Add(new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read));}foreach(var row in selection){request.Token.ThrowIfCancellationRequested();await row.Document.EnsureUnchangedAsync(request.Token);}if(inputSource is not null)await inputSource(request.Token);},request.Token);
            if(!Current())return;
            batchTimings["sourceMs"]=clock.Elapsed.TotalMilliseconds;ValidateState();request.Token.ThrowIfCancellationRequested();
            var drafts=frozen.Select(d=>new Dictionary<string,string>(d.Draft)).ToArray();var changed=Enumerable.Range(0,selection.Length).Where(i=>!SameDraft(before[i],drafts[i])).ToArray();
            int items=changed.Sum(i=>before[i].Keys.Concat(drafts[i].Keys).Distinct().Count(key=>before[i].GetValueOrDefault(key)!=drafts[i].GetValueOrDefault(key)));
            clock.Restart();
            CommitBatchDrafts(selection,before,drafts,changed,frozen);
            batchTimings["commitMs"]=clock.Elapsed.TotalMilliseconds;
            clock.Restart();if(changed.Length>0){RefreshPhotoRows();RefreshMatchTime();ClearMatchMarker();_=PostPhotosAsync();}batchTimings["refreshMs"]=clock.Elapsed.TotalMilliseconds;
            string notice=$"{label}应用完成：修改{changed.Length}张，无变化{selection.Length-changed.Length}张；变化操作{items}项；缺失时间跳过{result.Missing}项，文件名不匹配{result.FilenameMismatch}项，文件名日期无效{result.FilenameInvalid}项；CSV身份跳过{result.CsvIdentity}行，无效值跳过{result.CsvInvalid}行，忽略字段{result.CsvUnknown}列。原文件未修改；显式确认保存后才写文件。";
            if(label=="预设")notice=$"预设应用完成：修改{changed.Length}张，无变化{selection.Length-changed.Length}张；操作链{result.OperationCount}条，净变化字段{items}项，复制源缺失跳过{result.CopyMissing}项，缺失时间跳过{result.Missing}项，文件名不匹配{result.FilenameMismatch}项，文件名日期无效{result.FilenameInvalid}项。原文件未修改；显式确认保存后才写文件。";
            if(changed.Length==0)notice=M1Format("NoNetChange",label)+notice[(notice.IndexOf('：')+1)..];
            completed=true;Status.Text=notice;if(label=="预设")PresetPreview.Text=notice;if(label=="日期")DatePlanPreview.Text=notice;if(label=="CSV")CsvPreview.Text=notice;
        }
        catch(Exception error){if(Current())Status.Text=label+"未应用："+DateFailureText(error);}
        finally {
            foreach(var guard in sourceGuards)guard.Dispose();
            if(ReferenceEquals(operation,request))batchFinishedTicks=Stopwatch.GetTimestamp();datePending--;if(ReferenceEquals(dateRequest,request))dateRequest=null;
            if(ReferenceEquals(operation,request)){if(!completed&&request.IsCancellationRequested&&(Status.Text=="正在取消任务…"||Status.Text=="正在取消日期任务；结束后可关闭。"||Status.Text.StartsWith("正在计算与校验"+label,StringComparison.Ordinal)||Status.Text=="正在复核全部来源，包括无变化及跳过项…"))Status.Text="任务已取消或失效，整批草稿未应用。";var clock=Stopwatch.StartNew();preserveBatchEditor=!completed;try{EndOperation();}finally{preserveBatchEditor=false;}batchTimings["refreshMs"]=batchTimings.GetValueOrDefault("refreshMs")+clock.Elapsed.TotalMilliseconds;}
        }
    }
    void CommitBatchDrafts(PhotoRow[] selection,Dictionary<string,string>[] before,Dictionary<string,string>[] drafts,int[] changed,IReadOnlyList<PhotoDocument>? frozen=null) {
        // All validation has completed: observers see the whole batch, never a half-mutated selection.
        foreach(int i in changed){selection[i].Document.ReplaceDraft(drafts[i]);if(frozen is not null)selection[i].Document.UsePreparedDates(frozen[i]);}
        foreach(int i in changed)selection[i].Document.NotifyDraftChanged();
        if(changed.Length>0)lastApply=new(selection,before,selection.Select(r=>r.Document.DraftRevision).ToArray());
    }
    private void UndoLastApply(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired)return;
        if(!LastApplyCurrent()){lastApply=null;RefreshSelection();Status.Text="最近一次应用撤销已失效，当前草稿保留。";return;}
        var batch=lastApply!;lastApply=null;
        foreach(var (row,i) in batch.Rows.Select((r,i)=>(r,i)))row.Document.ReplaceDraft(batch.Before[i]);
        foreach(var row in batch.Rows)row.Document.NotifyDraftChanged();
        DatePlanPreview.Text=PresetPreview.Text=CsvPreview.Text=MatchResult.Text=M1Text("UndoFeedback");
        RefreshPhotoRows();RefreshSelection();RefreshMatchTime();ClearMatchMarker();_=PostPhotosAsync();Status.Text="已撤销最近一次应用，恢复该批之前的完整草稿；此前编辑和原文件保留。";
    }
}
