using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
namespace PhotoTrail.Windows;

public partial class MainWindow
{
    internal double importMilliseconds;
    internal long importExifToolRequests;
    internal long importDateHostRequests;
    long rereadSequence;
    bool changingInspectorSettings;
    internal Dictionary<string,double> rereadTimings=new();
    sealed record CommonOption(string Tag,string Label,bool Selected);
    void RefreshInspectorSettings()
    {
        if(CommonFieldOptions is null)return;
        changingInspectorSettings=true;
        try {
            InspectorView.SelectedIndex=settings.CommonOnly?0:1;
            string query=CommonFieldSearch.Text;var common=settings.CommonTags.ToHashSet(StringComparer.Ordinal);
            CommonFieldOptions.ItemsSource=MetadataInspector.Options(photos.Select(r=>r.Document),settings.CommonTags).Where(t=>t.Contains(query,StringComparison.OrdinalIgnoreCase)||L10n.Text(MetadataInspector.Label(t)).Contains(query,StringComparison.CurrentCultureIgnoreCase)).Select(t=>new CommonOption(t,L10n.Text(MetadataInspector.Label(t))+" · "+t,common.Contains(t))).ToArray();
        }finally{changingInspectorSettings=false;}
    }
    void CommonFieldSearchChanged(object sender,TextChangedEventArgs e){if(IsLoaded)RefreshInspectorSettings();}
    void CommonFieldToggled(object sender,RoutedEventArgs e)
    {
        if(!IsLoaded||changingInspectorSettings||sender is not CheckBox {Tag:string tag} box)return;
        var common=settings.CommonTags.ToHashSet(StringComparer.Ordinal);if(common.Contains(tag)==(box.IsChecked==true))return;
        if(box.IsChecked==true)common.Add(tag);else common.Remove(tag);
        settings=settings with{CommonFields=common.Order(StringComparer.Ordinal).ToArray()};SaveSettings();RefreshInspector();
    }
    void RestoreCommonFields(object sender,RoutedEventArgs e){settings=settings with{CommonFields=MetadataInspector.DefaultCommon.ToArray()};SaveSettings();RefreshInspectorSettings();RefreshInspector();}
    void ClearCommonFields(object sender,RoutedEventArgs e){settings=settings with{CommonFields=[]};SaveSettings();RefreshInspectorSettings();RefreshInspector();}
    void InspectorViewChanged(object sender,SelectionChangedEventArgs e)
    {
        if(!IsLoaded||changingInspectorSettings)return;settings=settings with{CommonOnly=InspectorView.SelectedIndex==0};SaveSettings();RefreshInspector();
    }
    void RefreshInspector()
    {
        if(MetadataGrid is null||InspectorCounts is null)return;
        var selected=Selected.Select(r=>r.Document).ToArray();string query=MetadataSearch.Text;
        var rows=MetadataInspector.Rows(selected,settings.CommonTags.ToHashSet(StringComparer.Ordinal)).Select(r=>r with{Section=L10n.Text(r.Section),Name=L10n.Text(r.Name),SourceRoleLabel=r.Tag.Contains(" / ",StringComparison.Ordinal)?L10n.Text(r.Tag.Split(" / ",StringSplitOptions.None)[0]):"",StateLabel=string.Join("; ",r.State.Split('；').Select(L10n.Message)),PermissionLabel=r.CanEdit?L10n.Text("编辑精确来源字段"):r.ReadOnlyReason.Length>0?L10n.Format("只读：{0}",L10n.Message(r.ReadOnlyReason)):L10n.Text("只读"),Value=r.State=="混合值"?L10n.Message(r.Value):r.Value}).ToArray();
        string? group=M1InspectorGroup.SelectedItem as string;
        var selectedTags=MetadataGrid.SelectedItems.OfType<InspectorRow>().Select(r=>r.Tag).ToHashSet(StringComparer.Ordinal);
        changingM1Inspector=true;
        try {
            M1CommonFields.IsChecked=settings.CommonOnly;M1FullFields.IsChecked=!settings.CommonOnly;
            M1InspectorGroup.Visibility=settings.CommonOnly?Visibility.Collapsed:Visibility.Visible;
            M1InspectorGroup.ItemsSource=new[]{M1Text("AllGroups")}.Concat(rows.Select(r=>r.Section).Distinct()).ToArray();
            M1InspectorGroup.SelectedItem=group is not null&&M1InspectorGroup.Items.Contains(group)?group:M1Text("AllGroups");
        } finally {changingM1Inspector=false;}
        MetadataGrid.ItemsSource=rows.Where(r=>(query.Length>0?r.Tag.Contains(query,StringComparison.OrdinalIgnoreCase)||r.Name.Contains(query,StringComparison.CurrentCultureIgnoreCase)||r.Value.Contains(query,StringComparison.OrdinalIgnoreCase):!settings.CommonOnly||r.IsCommon)&&
            (settings.CommonOnly||M1InspectorGroup.SelectedItem as string==M1Text("AllGroups")||r.Section==M1InspectorGroup.SelectedItem as string)).Select(r=>r with{ShowFullTag=settings.FullTagNames,MissingLabel=M1Text("MissingValue"),DraftLabel=M1Text("Draft"),DateFractionLabel=WText("Subseconds"),DateUnknownZoneLabel=WText("NoTimezone")}).ToArray();
        foreach(var row in MetadataGrid.Items.OfType<InspectorRow>())if(selectedTags.Contains(row.Tag))MetadataGrid.SelectedItems.Add(row);
        var view=CollectionViewSource.GetDefaultView(MetadataGrid.ItemsSource);view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(InspectorRow.Section)));
        InspectorCounts.Text=L10n.Message(L10n.Text("所选：")+L10n.Message(MetadataInspector.Counts(selected))+L10n.Text("\n全库：")+L10n.Message(MetadataInspector.Counts(photos.Select(r=>r.Document))));
        InspectorStatus.Text=L10n.Message(string.Join("\n",selected.Where(d=>L10n.Message(d.InspectionError).Length>0).Select(d=>Path.GetFileName(d.FilePath)+"："+L10n.Message(d.InspectionError))));
        RefreshM1Shell();
    }
    readonly Dictionary<string,string> editorBaseline=new(StringComparer.Ordinal);
    void CaptureEditorBaseline(){editorBaseline.Clear();foreach(var field in Fields)editorBaseline[field.Tag]=field.Value.Text;}
    bool InspectorHasInput()=>Fields.Any(f=>f.Apply.IsChecked==true||f.Value.Text!=editorBaseline.GetValueOrDefault(f.Tag,""));
    void EditInspectorField(object sender,RoutedEventArgs e)
    {
        OpenWorkflowFields(MetadataGrid.SelectedItems.OfType<InspectorRow>());
    }
    private async void RereadPhotos(object sender,RoutedEventArgs e)
    {
        if(busy||renameRecoveryRequired)return;
        var selected=Selected;if(selected.Length==0)return;
        if(InspectorHasInput()){Status.Text=L10n.Message(L10n.Text("重新读取已跳过：所选有未应用输入，输入及草稿保留。"));return;}
        bool Clear(PhotoRow row){try{InplaceHistory.RequireClear([row.Document.FilePath,row.Document.SidecarPath??row.Document.FilePath]);return true;}catch(Exception error){row.Document.InspectionError="待核对，旧快照保留："+error.Message;return false;}}
        var eligible=selected.Where(r=>r.Document.Draft.Count==0&&Clear(r)).ToArray();int skipped=selected.Length-eligible.Length;
        if(eligible.Length==0){Status.Text=L10n.Message(L10n.Format("重新读取已跳过{0}张：有草稿或持久待核对记录；草稿保留。",skipped));return;}
        long sequence=++rereadSequence;var revisions=eligible.Select(r=>r.Document.DraftRevision).ToArray();
        var editor=Fields.Select(f=>(f.Apply.IsChecked,f.Value.Text)).ToArray();
        BeginOperation();var request=operation!;var clock=Stopwatch.StartNew();long requests=Interlocked.Read(ref ExifToolClient.RequestCount),hostRequests=Interlocked.Read(ref DateAdapter.StartedProcesses);int refreshed=0,failed=0,addedSidecars=0,removedSidecars=0;bool cancelled=false;
        bool Current()=>ReferenceEquals(operation,request)&&sequence==rereadSequence&&!request.IsCancellationRequested&&Selected.SequenceEqual(selected)&&Fields.Select(f=>(f.Apply.IsChecked,f.Value.Text)).SequenceEqual(editor)&&eligible.Select((r,i)=>photos.Contains(r)&&r.Document.DraftRevision==revisions[i]&&r.Document.Draft.Count==0).All(x=>x);
        var prepared=new List<(PhotoRow Old,PhotoDocument? Next,string Error)>();
        try {
            var client=Tool();
            await Task.Run(async()=>{
                foreach(var chunk in eligible.Chunk(32)) {
                    var result=await PhotoDocument.LoadBatchAsync(client,chunk.Select(r=>r.Document.FilePath).ToArray(),request.Token,inspect:true);
                    for(int i=0;i<chunk.Length;i++){var item=result[i];prepared.Add((chunk[i],item.Document,item.Error??item.Document?.InspectionError??""));}
                }
            },request.Token);
            rereadTimings["readMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            if(!Current())throw new OperationCanceledException();
            // Lock all accepted sources while verifying and swapping. A new hash never attaches to an old draft.
            var guards=new List<FileStream>();
            try {
                foreach(var item in prepared.Where(x=>x.Next is not null&&x.Error.Length==0)){
                    request.Token.ThrowIfCancellationRequested();
                    foreach(var path in item.Next!.SidecarPath is {} side?new[]{item.Next.FilePath,side}:new[]{item.Next.FilePath})guards.Add(new(path,FileMode.Open,FileAccess.Read,FileShare.Read));
                    InplaceHistory.RequireClear([item.Next.FilePath,item.Next.SidecarPath??item.Next.FilePath]);await item.Next.EnsureUnchangedAsync(request.Token);
                }
                if(!Current())throw new OperationCanceledException();rereadTimings["sourceMs"]=clock.Elapsed.TotalMilliseconds;
                fillingEditor=true;try {
                    var replacements=new Dictionary<PhotoRow,PhotoRow>();
                    foreach(var item in prepared) {
                        if(item.Next is null||item.Error.Length>0){item.Old.Document.InspectionError="重读失败，保留过期快照："+item.Error;failed++;continue;}
                        if(item.Old.Document.SidecarPath is null&&item.Next.SidecarPath is not null)addedSidecars++;
                        if(item.Old.Document.SidecarPath is not null&&item.Next.SidecarPath is null)removedSidecars++;
                        var next=item.Old.WithDocument(item.Next);photos[photos.IndexOf(item.Old)]=next;replacements[item.Old]=next;refreshed++;
                    }
                    Photos.SelectedItems.Clear();foreach(var row in selected)Photos.SelectedItems.Add(replacements.GetValueOrDefault(row,row));previousSelection=Selected;
                }finally{fillingEditor=false;}
            }finally{foreach(var guard in guards)guard.Dispose();}
            if(refreshed>0&&!LastApplyCurrent())lastApply=null;InvalidateDates();InvalidateBatchTrack();RenameRulesChanged(this,new RoutedEventArgs());RefreshPhotoRows();RefreshMatchPhoto();_=PostPhotosAsync();
        }
        catch(OperationCanceledException){cancelled=true;}
        catch(Exception error){if(Current())foreach(var row in eligible)row.Document.InspectionError="重读失败，保留过期快照："+error.Message;failed=eligible.Length;}
        finally {
            rereadTimings["requests"]=Interlocked.Read(ref ExifToolClient.RequestCount)-requests;
            rereadTimings["dateHostRequests"]=Interlocked.Read(ref DateAdapter.StartedProcesses)-hostRequests;
            if(ReferenceEquals(operation,request)){
                bool preserve=preserveBatchEditor;preserveBatchEditor=preserve||!Fields.Select(f=>(f.Apply.IsChecked,f.Value.Text)).SequenceEqual(editor);
                try{EndOperation();}finally{preserveBatchEditor=preserve;}
                Status.Text=L10n.Message(L10n.Format("重新读取{0}：更新{1}，草稿跳过{2}，失败{3}；旁车新增{4}、消失{5}。失败保留旧快照；原文件未写入。",(cancelled?L10n.Text("已取消或失效"):L10n.Text("完成")),refreshed,skipped,failed,addedSidecars,removedSidecars));}
        }
    }
}
