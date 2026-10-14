using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    readonly Dictionary<string,string> renameIdentities=new(StringComparer.OrdinalIgnoreCase);
    RenameGroup[] renameGroups=[];
    string[] manualRenameOrder=[];
    string[]? renameOrderUndo;
    bool fillingRenameControls;
    Point renameDragStart;
    string[] renameDragIds=[];
    RenameOrderSettings ReadRenameOrder()=>new(RenameOrderSettings.Sorts[RenameProcessingSort.SelectedIndex],RenameDescending.IsChecked==true,RenameMetadataTag.Text.Trim());
    IReadOnlyDictionary<string,VerifiedPhotoDate?> renameDateResults=new Dictionary<string,VerifiedPhotoDate?>();
    CancellationTokenSource? renameDateValidation;
    static string RenameBoundText(string value)=>value.Trim().Length==10?value.Trim().Replace('-',':')+" 00:00:00":RenameInput.BridgeDate(value.Trim());
    string RenameDateInputs()=>System.Text.Json.JsonSerializer.Serialize(new{Rules=RenameRules.Text,From=RenameDateFrom.Text,To=RenameDateTo.Text,Order=ReadRenameOrder(),Selection=Selected.Select(r=>new{r.Document.FilePath,r.Document.DraftRevision}).ToArray()});
    async Task PrepareRenameDatesAsync(CancellationToken token) {
        var groups=renameGroups;int revision=renameRevision;string input=RenameDateInputs();
        var rules=ReadRenameRules();bool nameDates=RenamePlan.UsesDates(rules);
        bool needs=nameDates||ReadRenameOrder().Sort is "shooting" or "metadata"||RenameDateFrom.Text.Trim().Length>0||RenameDateTo.Text.Trim().Length>0;
        var texts=new List<string>();
        if(needs){foreach(var group in groups){if(nameDates)try{var raw=RenameNameField(group,"captured");if(raw is not null)texts.Add(VerifiedPhotoDate.Bridge(raw));}catch(ArgumentException){}catch(IOException){}
            foreach(var member in group.Members){texts.AddRange(member.ShootingTexts());if(nameDates){foreach(var key in new[]{"File:FileCreateDate","File:FileModifyDate","PhotoTrail:RenameReferenceDate"})if(member.Tag(key) is {} system)texts.Add(RenameInput.BridgeDate(system));}if(ReadRenameOrder().Sort=="metadata"&&member.Tag(ReadRenameOrder().MetadataSortTag??"") is {} raw)texts.Add(RenameInput.BridgeDate(raw));}}
            if(RenameDateFrom.Text.Trim().Length>0)texts.Add(RenameBoundText(RenameDateFrom.Text));if(RenameDateTo.Text.Trim().Length>0)texts.Add(RenameBoundText(RenameDateTo.Text));}
        var dates=await RenameTransform.PrepareDatesAsync(texts,rules,token);token.ThrowIfCancellationRequested();
        if(revision!=renameRevision||!ReferenceEquals(groups,renameGroups)||input!=RenameDateInputs())throw new InvalidOperationException("日期验证期间规则、选择或元数据草稿已改变。");
        renameDateResults=dates;renameGroups=groups.Select(g=>g with{Members=g.Members.Select(m=>m with{DateResults=dates}).ToArray()}).ToArray();
    }
    VerifiedPhotoDate? RenameVerifiedDate(RenameGroup group){var raw=RenameNameField(group,"captured");return raw is null?null:renameDateResults.GetValueOrDefault(VerifiedPhotoDate.Bridge(raw));}
    RenameInputFilter ReadRenameFilter(){
        decimal? Bound(string value){if(value.Trim().Length==0)return null;var parsed=RenameInput.Date(RenameBoundText(value),renameDateResults);return parsed??throw new ArgumentException("日期边界无效，使用日期或完整时间；仅日期为当日00:00:00。");}
        var from=Bound(RenameDateFrom.Text);var to=Bound(RenameDateTo.Text);if(from>to)throw new ArgumentException("开始日期晚于结束日期。");
        return new(RenameInputQuery.Text,RenameInputType.Text,RenameInputFolder.Text,RenameInputCamera.Text,from,to,RenameInputGps.SelectedIndex,RenameInputTag.Text,RenameInputPresence.SelectedIndex);
    }
    RenameGroup[] OrderedRenameGroups(){var settings=ReadRenameOrder();var automatic=RenameOrder.Ordered(renameGroups,settings);if(settings.Sort!="manual")return automatic;var byId=automatic.ToDictionary(g=>g.Id);return manualRenameOrder.Where(byId.ContainsKey).Select(id=>byId[id]).Concat(automatic.Where(g=>!manualRenameOrder.Contains(g.Id))).ToArray();}
    RenameGroup[] IncludedRenameGroups(){var filter=ReadRenameFilter();return OrderedRenameGroups().Where(g=>g.Members.Any(filter.Matches)).ToArray();}
    async Task RenderRenameGroupsAsync(){
        renameDateValidation?.Cancel();renameDateValidation?.Dispose();renameDateValidation=CancellationTokenSource.CreateLinkedTokenSource(operation?.Token??CancellationToken.None);var request=renameDateValidation;
        RenamePreview.ItemsSource=null;await PrepareRenameDatesAsync(request.Token);
        var included=IncludedRenameGroups();var rules=ReadRenameRules();var previews=new List<object>();
        foreach(var (group,index) in included.Select((g,i)=>(g,i))) {
            try{var steps=new List<string>();var name=RenameGroupName(group,rules,index,steps);foreach(var member in group.Members)previews.Add(new RenameFile(member.Path,Path.Combine(member.Directory,RenameMemberName(group,member,name)),""){Steps=string.Join(" → ",steps.Select((step,i)=>$"{i+1}: {step}"))});}
            catch(Exception error)when(error is ArgumentException or IOException){foreach(var member in group.Members)previews.Add(new RenameNameIssue(member.Path,error.Message));}
        }
        RenameGroups.ItemsSource=included;RenamePreview.ItemsSource=previews;RenameViewChanged(this,new RoutedEventArgs());
        RenameOrderStatus.Text=$"完整组{renameGroups.Length}／参与{included.Length}／读取失败{renameGroups.SelectMany(g=>g.Members).Count(m=>m.MetadataFailed)}；参与组连续编号，查看不影响处理。";UpdateRenameButtons();
    }
    string RenameGroupName(RenameGroup group,IReadOnlyList<RenameRule> rules,int index,List<string>? steps=null)=>RenamePlan.ApplyVerified(group.Leader.Name,rules,index,key=>RenameNameField(group,key),RenamePlan.UsesDates(rules)?RenameVerifiedDate(group):null,renameDateResults,steps);
    static string RenameMemberName(RenameGroup group,RenameInput member,string leaderName)=>member.Path==group.Leader.Path?leaderName:RenameTransform.Split(leaderName).Stem+RenameTransform.Split(member.Name).Extension;
    sealed record RenameNameIssue(string Source,string Reason) {public string OriginalName=>Path.GetFileName(Source);public string NewName=>"不可生成";public string Status=>Reason;}
    string? RenameNameField(RenameGroup group,string key) {
        if(group.Members.Any(m=>m.MetadataFailed))throw new IOException("元数据读取失败，不能用缺失值生成名称。");
        var imported=photos.FirstOrDefault(p=>p.Document.FilePath.Equals(group.Leader.Path,StringComparison.OrdinalIgnoreCase))?.Document;
        var embedded=group.Leader.Metadata??JsonSerializer.SerializeToElement(group.Leader.Tags);
        var sidecar=group.Members.FirstOrDefault(m=>m.Extension=="xmp"&&!m.Path.Equals(group.Leader.Path,StringComparison.OrdinalIgnoreCase))?.Metadata;
        if(key=="captured")return imported is not null?BatchTrackMatch.Capture(imported):BatchTrackMatch.Capture(embedded,sidecar,new Dictionary<string,string>());
        if(key is not("city" or "model")) {
            var values=new Dictionary<string,string>(StringComparer.Ordinal);
            void Add(JsonElement data,bool xmpOnly=false){foreach(var property in data.EnumerateObject().Where(p=>!xmpOnly||p.Name.StartsWith("XMP-",StringComparison.Ordinal)))values[property.Name]=property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Null?"\0invalid-type":PhotoDocument.Text(property.Value);}
            Add(embedded);if((imported?.Sidecar??sidecar) is {} external)Add(external,true);
            if(imported is not null)foreach(var entry in imported.Draft)values[entry.Key]=entry.Value;
            foreach(var entry in group.Leader.Tags.Where(p=>p.Key is "File:FileCreateDate" or "File:FileModifyDate" or "PhotoTrail:RenameReferenceDate"))values[entry.Key]=entry.Value;
            var result=new RenameInput(group.Leader.Path,values).Tag(key);if(result?.StartsWith('\0')==true)throw new ArgumentException("标签类型无效："+key);return result;
        }
        var tags=key=="city"?new[]{"XMP-photoshop:City","IPTC:City"}:new[]{"XMP-tiff:Model","IFD0:Model","ExifIFD:Model"};
        foreach(var tag in tags) {
            if(imported?.Draft.TryGetValue(tag,out var draft)==true)return draft.Length==0?null:draft;
            var data=tag.StartsWith("XMP-",StringComparison.Ordinal)?imported?.Sidecar??sidecar??embedded:embedded;
            if(!data.TryGetProperty(tag,out var value))continue;
            if(value.ValueKind!=JsonValueKind.String)throw new ArgumentException("字段类型错误："+tag);
            if(!string.IsNullOrEmpty(value.GetString()))return value.GetString();
        }
        return null;
    }
    private void RenameOrderChanged(object sender,RoutedEventArgs e){if(!IsLoaded||fillingRenameControls)return;RenameRulesChanged(sender,e);}
    private void RenameViewChanged(object sender,RoutedEventArgs e){if(!IsLoaded||RenamePreview.ItemsSource is null)return;var view=System.Windows.Data.CollectionViewSource.GetDefaultView(RenamePreview.ItemsSource);using(view.DeferRefresh()){view.Filter=item=>RenameViewFilter.SelectedIndex switch{1=>item is RenameFile f?f.Source!=f.Target:item is RenameOutcome o&&o.Source!=o.Current,2=>item is RenameFile f?f.Source==f.Target:item is RenameOutcome o&&o.Source==o.Current,_=>true};view.SortDescriptions.Clear();if(RenameViewOrder.SelectedIndex!=0)view.SortDescriptions.Add(new("NewName",RenameViewOrder.SelectedIndex==1?System.ComponentModel.ListSortDirection.Ascending:System.ComponentModel.ListSortDirection.Descending));}UpdateRenameButtons();}
    async Task ReadRenameGroupsAsync(CancellationToken cancellation){
        var reference=DateTimeOffset.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz",System.Globalization.CultureInfo.InvariantCulture);
        var selected=RenameSelection();var inputPaths=selected.Select(r=>r.Document.FilePath).ToArray();var roots=inputPaths.Select(RenameGroup.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);var paths=inputPaths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach(var dir in inputPaths.Select(Path.GetDirectoryName).Distinct(StringComparer.OrdinalIgnoreCase))foreach(var path in Directory.EnumerateFiles(dir!))if(roots.Contains(RenameGroup.Key(path)))paths.Add(path);
        if(roots.Count>3000||paths.Count>6000)throw new ArgumentException("超过3000组或6000个物理文件上限。");
        var inputs=new List<RenameInput>();foreach(var path in paths){cancellation.ThrowIfCancellationRequested();var version=ImportSource.Read(path);var hash=await PhotoDocument.HashAsync(path,cancellation);var file=new FileInfo(path);if((file.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("配对成员为链接，未读取。");var tags=new Dictionary<string,string>();JsonElement? metadata=null;bool failed=false;
            try{var data=await Tool().ReadAsync(path,cancellation);metadata=data.Clone();var extension=Path.GetExtension(path).TrimStart('.').ToLowerInvariant();if(RenameGroup.Sources.Contains(extension)&&(!data.TryGetProperty("File:MIMEType",out var mime)||!mime.ToString().StartsWith("image/",StringComparison.OrdinalIgnoreCase))||extension=="xmp"&&(!data.TryGetProperty("File:FileType",out var kind)||kind.ToString()!="XMP"))throw new InvalidDataException("配对照片或XMP内容无效。");foreach(var tag in data.EnumerateObject().Where(t=>t.Name!="SourceFile"))tags[tag.Name]=PhotoDocument.Text(tag.Value);}
            catch(OperationCanceledException){throw;}catch(Exception error)when(error is IOException or JsonException or InvalidDataException or TimeoutException){failed=true;}
            if(hash!=await PhotoDocument.HashAsync(path,cancellation))throw new IOException("配对成员读取期间改变。");
            version.RequireCurrent();
            var imported=photos.FirstOrDefault(r=>r.Document.FilePath.Equals(path,StringComparison.OrdinalIgnoreCase));if(imported is not null&&hash!=imported.Document.SourceHash)throw new IOException("已导入照片在外部改变，请重新导入。");
            tags["PhotoTrail:RenameReferenceDate"]=reference;tags["File:FileCreateDate"]=file.CreationTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ");tags["File:FileModifyDate"]=file.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ");inputs.Add(new(path,tags,failed,file.Length,hash,metadata));
        }
        inputs=inputs.Select(member=>{
            var imported=photos.FirstOrDefault(row=>(row.Document.FilePath.Equals(member.Path,StringComparison.OrdinalIgnoreCase)||row.Document.SidecarPath?.Equals(member.Path,StringComparison.OrdinalIgnoreCase)==true))?.Document;
            var external=inputs.FirstOrDefault(other=>other.Extension=="xmp"&&!other.Path.Equals(member.Path,StringComparison.OrdinalIgnoreCase)&&RenameGroup.Key(other.Path)==RenameGroup.Key(member.Path));
            bool known=imported is not null||external is not null||member.Extension is "jpg" or "jpeg" or "xmp";
            var capture=imported is not null?BatchTrackMatch.Capture(imported):member.Metadata is {} data?BatchTrackMatch.Capture(data,external?.Metadata,new Dictionary<string,string>()):null;
            return member with{CaptureKnown=known,MainCapture=capture};
        }).ToList();
        var groups=inputs.GroupBy(m=>RenameGroup.Key(m.Path),StringComparer.OrdinalIgnoreCase).Select(values=>{var members=values.ToArray();var id=members.Select(m=>renameIdentities.GetValueOrDefault(m.Path)).FirstOrDefault(v=>v is not null)??Guid.NewGuid().ToString("N");foreach(var member in members)renameIdentities[member.Path]=id;return new RenameGroup(id,members);}).ToArray();
        renameGroups=groups;manualRenameOrder=manualRenameOrder.Concat(groups.Select(g=>g.Id).Where(id=>!manualRenameOrder.Contains(id))).ToArray();
    }
    private async void RefreshRenameOrder(object sender,RoutedEventArgs e){
        if(busy||renameRecoveryRequired)return;renameReadingPreview=true;var revision=++renameRevision;frozenRenamePlan=null;BeginOperation();try{await ReadRenameGroupsAsync(operation!.Token);if(revision==renameRevision){await RenderRenameGroupsAsync();RenameStatus.Text="配对元数据与完整处理组已读取；尚未写文件。";}}catch(OperationCanceledException){RenameStatus.Text="读取已取消，未改文件。";}catch(Exception error){renameGroups=[];RenameGroups.ItemsSource=null;RenamePreview.ItemsSource=null;RenameStatus.Text="处理预览未读取："+error.Message;}finally{renameReadingPreview=false;EndOperation();}
    }
    void RemapRenameIdentities(RenameResult result){var changed=result.Files.Where(f=>renameIdentities.ContainsKey(f.Source)).Select(f=>(file:f,id:renameIdentities[f.Source])).ToArray();foreach(var item in changed)renameIdentities.Remove(item.file.Source);foreach(var item in changed)renameIdentities[item.file.Current]=item.id;renameGroups=renameGroups.Select(g=>g with{Members=g.Members.Select(m=>result.Files.FirstOrDefault(f=>f.Source.Equals(m.Path,StringComparison.OrdinalIgnoreCase)) is{} f?m with{Path=f.Current}:m).ToArray()}).ToArray();RenameGroups.ItemsSource=IncludedRenameGroups();}
    bool CanMoveRenameGroups=>!busy&&!renameRecoveryRequired&&RenamePreview.ItemsSource is not null&&RenameViewOrder.SelectedIndex==0&&RenameViewFilter.SelectedIndex==0&&System.Windows.Data.CollectionViewSource.GetDefaultView(RenamePreview.ItemsSource).SortDescriptions.Count==0;
    void MoveRenameGroups(string[] moving,string target){if(!CanMoveRenameGroups)return;var current=OrderedRenameGroups().Select(g=>g.Id).ToArray();var currentSet=current.ToHashSet();int slot=0;var full=manualRenameOrder.Select(id=>currentSet.Contains(id)?current[slot++]:id).Concat(current.Where(id=>!manualRenameOrder.Contains(id))).ToArray();var visible=IncludedRenameGroups().Select(g=>g.Id).ToArray();var next=RenameOrder.Move(moving.ToHashSet(),target,visible,full);if(next.SequenceEqual(full))return;renameOrderUndo=full;manualRenameOrder=next;fillingRenameControls=true;try{RenameProcessingSort.SelectedIndex=14;RenameDescending.IsChecked=false;}finally{fillingRenameControls=false;}RenameRulesChanged(this,new RoutedEventArgs());RenameGroups.SelectedItems.Clear();foreach(var g in IncludedRenameGroups().Where(g=>moving.Contains(g.Id)))RenameGroups.SelectedItems.Add(g);}
    private void UndoRenameOrder(object sender,RoutedEventArgs e){if(!CanMoveRenameGroups||renameOrderUndo is null)return;manualRenameOrder=renameOrderUndo;renameOrderUndo=null;fillingRenameControls=true;try{RenameProcessingSort.SelectedIndex=14;RenameDescending.IsChecked=false;}finally{fillingRenameControls=false;}RenameRulesChanged(sender,e);}
    private void InsertRenameGroups(object sender,RoutedEventArgs e){if(!int.TryParse(RenameInsertPosition.Text,out var position)||position<1||position>RenameGroups.Items.Count+1){RenameStatus.Text="插入位置须为1至可见组数+1；最后一个位置代表末尾。";return;}var moving=RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToArray();MoveRenameGroups(moving,position>RenameGroups.Items.Count?"":((RenameGroup)RenameGroups.Items[position-1]).Id);}
    void StepRenameGroups(bool down){if(!CanMoveRenameGroups)return;var visible=IncludedRenameGroups().Select(g=>g.Id).ToArray();var moving=RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToHashSet();var indices=visible.Select((id,i)=>(id,i)).Where(p=>moving.Contains(p.id)).Select(p=>p.i).ToArray();if(indices.Length==0)return;int target=down?indices.Max()+2:indices.Min()-1;if(target<0)return;MoveRenameGroups(moving.ToArray(),target>=visible.Length?"":visible[target]);}
    private void RenameMoveUp(object sender,RoutedEventArgs e)=>StepRenameGroups(false);
    private void RenameMoveDown(object sender,RoutedEventArgs e)=>StepRenameGroups(true);
    private void RenameOrderKey(object sender,KeyEventArgs e){var key=e.Key==Key.System?e.SystemKey:e.Key;if(Keyboard.Modifiers==ModifierKeys.Alt&&key is Key.Up or Key.Down){StepRenameGroups(key==Key.Down);e.Handled=true;}else if(Keyboard.Modifiers==ModifierKeys.Control&&key==Key.Z){UndoRenameOrder(sender,e);e.Handled=true;}}
    private void RenameDragBegin(object sender,MouseButtonEventArgs e){renameDragStart=e.GetPosition(RenameGroups);var node=e.OriginalSource as DependencyObject;while(node is not null&&node is not ListBoxItem)node=VisualTreeHelper.GetParent(node);renameDragIds=node is ListBoxItem item&&item.DataContext is RenameGroup group?(item.IsSelected?RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToArray():[group.Id]):[];if(node is ListBoxItem{IsSelected:true}&&RenameGroups.SelectedItems.Count>1&&Keyboard.Modifiers==ModifierKeys.None)e.Handled=true;}
    private void RenameDragMove(object sender,MouseEventArgs e){if(!CanMoveRenameGroups||e.LeftButton!=MouseButtonState.Pressed||renameDragIds.Length==0)return;var p=e.GetPosition(RenameGroups);if(Math.Abs(p.X-renameDragStart.X)<SystemParameters.MinimumHorizontalDragDistance&&Math.Abs(p.Y-renameDragStart.Y)<SystemParameters.MinimumVerticalDragDistance)return;var ids=renameDragIds;renameDragIds=[];DragDrop.DoDragDrop(RenameGroups,new DataObject("PhotoTrail.Windows.RenameGroups",ids),DragDropEffects.Move);RenameGroups.Focus();e.Handled=true;}
    string RenameDropTarget(DragEventArgs e){var hit=RenameGroups.InputHitTest(e.GetPosition(RenameGroups)) as DependencyObject;while(hit is not null&&hit is not ListBoxItem)hit=VisualTreeHelper.GetParent(hit);return (hit as ListBoxItem)?.DataContext is RenameGroup group?group.Id:"";}
    private void RenameDragOver(object sender,DragEventArgs e){var valid=CanMoveRenameGroups&&e.Data.GetData("PhotoTrail.Windows.RenameGroups")is string[] ids&&ids.All(id=>IncludedRenameGroups().Any(g=>g.Id==id));e.Effects=valid?DragDropEffects.Move:DragDropEffects.None;RenameDropHint.Text=valid?"插入到："+(RenameDropTarget(e)is var target&&target.Length>0?IncludedRenameGroups().First(g=>g.Id==target).Name+" 之前":"可见组末尾"):"仅处理顺序视图、查看全部且空闲时可拖动。";e.Handled=true;}
    private void RenameDrop(object sender,DragEventArgs e){if(e.Data.GetData("PhotoTrail.Windows.RenameGroups")is string[] ids){var before=renameRevision;MoveRenameGroups(ids,RenameDropTarget(e));RenameDropHint.Text=before!=renameRevision?"放下成功；仅更新内存顺序。":"放下未改变顺序。";}e.Handled=true;}
}
