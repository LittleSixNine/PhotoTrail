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
    RenameOrderSettings ReadRenameOrder(){var settings=new RenameOrderSettings(RenameOrderSettings.Sorts[RenameProcessingSort.SelectedIndex],RenameDescending.IsChecked==true,RenameMetadataTag.Text.Trim() is {Length:>0} metadataTag?metadataTag:null){Conflict=new[]{"stop","numbers","letters"}[RenameConflictChoice.SelectedIndex],ConflictDigits=int.TryParse(RenameConflictDigits.Text,out var digits)?digits:0,NumberSuffixFormat=new[]{"plain","underscore","dash","parentheses"}[RenameNumberSuffix.SelectedIndex],LetterSuffixFormat=new[]{"plain","underscore","dash","parentheses"}[RenameLetterSuffix.SelectedIndex],KeepFirst=RenameKeepFirst.IsChecked==true,Pair=RenamePair.IsChecked==true,SourceExtensions=RenameSources.Text,TargetExtensions=RenameTargets.Text,DatePriority=RenameDatePriority.Text};return settings;}
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
        if(revision!=renameRevision||!ReferenceEquals(groups,renameGroups)||input!=RenameDateInputs())throw new InvalidOperationException(L10n.Text("日期验证期间规则、选择或元数据草稿已改变。"));
        renameDateResults=dates;renameGroups=groups.Select(g=>g with{Members=g.Members.Select(m=>m with{DateResults=dates}).ToArray()}).ToArray();
    }
    VerifiedPhotoDate? RenameVerifiedDate(RenameGroup group){var raw=RenameNameField(group,"captured");return raw is null?null:renameDateResults.GetValueOrDefault(VerifiedPhotoDate.Bridge(raw));}
    RenameInputFilter ReadRenameFilter(){
        decimal? Bound(string value){if(value.Trim().Length==0)return null;var parsed=RenameInput.Date(RenameBoundText(value),renameDateResults);return parsed??throw new ArgumentException(L10n.Text("日期边界无效，使用日期或完整时间；仅日期为当日00:00:00。"));}
        var from=Bound(RenameDateFrom.Text);var to=Bound(RenameDateTo.Text);if(from>to)throw new ArgumentException(L10n.Text("开始日期晚于结束日期。"));
        return new(RenameInputQuery.Text,RenameInputType.Text,RenameInputFolder.Text,RenameInputCamera.Text,from,to,RenameInputGps.SelectedIndex,RenameInputTag.Text,RenameInputPresence.SelectedIndex);
    }
    RenameGroup[] OrderedRenameGroups(){var settings=ReadRenameOrder();var automatic=RenameOrder.Ordered(renameGroups,settings);if(settings.Sort!="manual")return automatic;var byId=automatic.ToDictionary(g=>g.Id);return manualRenameOrder.Where(byId.ContainsKey).Select(id=>byId[id]).Concat(automatic.Where(g=>!manualRenameOrder.Contains(g.Id))).ToArray();}
    RenameGroup[] IncludedRenameGroups(){var filter=ReadRenameFilter();return OrderedRenameGroups().Where(g=>g.Members.Any(filter.Matches)).ToArray();}
    async Task RenderRenameGroupsAsync(){
        renameDateValidation?.Cancel();renameDateValidation?.Dispose();renameDateValidation=CancellationTokenSource.CreateLinkedTokenSource(operation?.Token??CancellationToken.None);var request=renameDateValidation;
        RenamePreview.ItemsSource=null;await PrepareRenameDatesAsync(request.Token);
        var included=IncludedRenameGroups();RenameOrderStatus.Text=L10n.Message(L10n.Format("完整组{0}／参与{1}／读取失败{2}；参与组连续编号，查看不影响处理。",renameGroups.Length,included.Length,renameGroups.SelectMany(g=>g.Members).Count(m=>m.MetadataFailed)));var computed=ComputeRenameTargets(included,ReadRenameRules());
        RenameGroups.ItemsSource=included;RenamePreview.ItemsSource=computed.Files;RenameViewChanged(this,new RoutedEventArgs());
        RenameOrderStatus.Text=L10n.Message(L10n.Format("完整组{0}／参与{1}／读取失败{2}；参与组连续编号，查看不影响处理。",renameGroups.Length,included.Length,renameGroups.SelectMany(g=>g.Members).Count(m=>m.MetadataFailed)));UpdateRenameButtons();
    }
    (RenameFile[] Files,RenameCounterUse? Counters) ComputeRenameTargets(RenameGroup[] groups,IReadOnlyList<RenameRule> sourceRules) {
        RenameLaunchSupport.RequireAvailable(sourceRules);
        var snapshot=sourceRules.Any(r=>r.Enabled&&r.Counter>0)?RenameCounters.Read(RenameCounters.DefaultPath):null;
        m3Steps.Clear();var rules=sourceRules.Select(r=>r.Enabled&&r.Counter>0?r with{Start=snapshot!.Values[r.Counter]}:r).ToArray();var ordinals=new Dictionary<(int Rule,string Directory),int>();var advances=new Dictionary<int,long>();var files=new List<RenameFile>();var ids=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(var (group,index) in groups.Select((g,i)=>(g,i))){
            int Ordinal(int rule){var key=(rule,rules[rule].PerDirectory?group.Leader.Directory.ToUpperInvariant():"");int next=ordinals.GetValueOrDefault(key);ordinals[key]=checked(next+1);return next;}
            void Completed(int rule,int ordinal,bool success){var value=rules[rule];if(value.Counter>0&&success){var next=checked(value.Start+checked(value.Step*(ordinal+1L)));advances[value.Counter]=Math.Max(advances.GetValueOrDefault(value.Counter,value.Start),next);}}
            var steps=new List<string>();var name=RenamePlan.ApplyVerified(group.Leader.Name,rules,index,key=>RenameNameField(group,key),RenamePlan.UsesDates(rules)?RenameVerifiedDate(group):null,renameDateResults,steps,Ordinal,Completed);
            foreach(var member in group.Members){m3Steps[member.Path]=steps.ToArray();ids[member.Path]=group.Id;files.Add(new(member.Path,Path.Combine(member.Directory,RenameMemberName(group,member,name)),""){Steps=string.Join(" → ",steps.Select((step,i)=>$"{i+1}: {step}"))});}
        }
        foreach(var rule in rules.Where(r=>r.Enabled&&r.Counter>0))advances.TryAdd(rule.Counter,rule.Start);
        return(RenameConflicts.Resolve(files,ids,ReadRenameOrder()),snapshot is null?null:new(snapshot,advances));
    }
    private void ResetRenameCounters(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{RenameCounters.Reset(RenameCounters.DefaultPath,ReadRenameRules());RenameRulesChanged(sender,e);RenameStatus.Text=L10n.Message(L10n.Text("所用计数槽位已明确重设为规则起点；未更名照片。"));}catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("计数未重设：")+L10n.Message(error.Message));}}
    string RenameGroupName(RenameGroup group,IReadOnlyList<RenameRule> rules,int index,List<string>? steps=null)=>RenamePlan.ApplyVerified(group.Leader.Name,rules,index,key=>RenameNameField(group,key),RenamePlan.UsesDates(rules)?RenameVerifiedDate(group):null,renameDateResults,steps);
    static string RenameMemberName(RenameGroup group,RenameInput member,string leaderName)=>member.Path==group.Leader.Path?leaderName:RenameTransform.Split(leaderName).Stem+RenameTransform.Split(member.Name).Extension;
    sealed record RenameNameIssue(string Source,string Reason) {public string OriginalName=>Path.GetFileName(Source);public string NewName=>L10n.Text("不可生成");public string Status=>Reason;}
    string? RenameNameField(RenameGroup group,string key) {
        if(group.Members.Any(m=>m.MetadataFailed))throw new IOException(L10n.Text("元数据读取失败，不能用缺失值生成名称。"));
        var imported=photos.FirstOrDefault(p=>p.Document.FilePath.Equals(group.Leader.Path,StringComparison.OrdinalIgnoreCase))?.Document;
        var embedded=group.Leader.Metadata??JsonSerializer.SerializeToElement(group.Leader.Tags);
        var sidecar=group.Members.FirstOrDefault(m=>m.Extension=="xmp"&&!m.Path.Equals(group.Leader.Path,StringComparison.OrdinalIgnoreCase))?.Metadata;
        if(key=="captured")return group.Leader.ShootingTexts().FirstOrDefault(raw=>renameDateResults.GetValueOrDefault(raw) is not null);
        if(key is not("city" or "model")) {
            var values=new Dictionary<string,string>(StringComparer.Ordinal);
            void Add(JsonElement data,bool xmpOnly=false){foreach(var property in data.EnumerateObject().Where(p=>!xmpOnly||p.Name.StartsWith("XMP-",StringComparison.Ordinal)))values[property.Name]=property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Null?"\0invalid-type":PhotoDocument.Text(property.Value);}
            Add(embedded);if((imported?.Sidecar??sidecar) is {} external)Add(external,true);
            if(imported is not null)foreach(var entry in imported.Draft)values[entry.Key]=entry.Value;
            foreach(var entry in group.Leader.Tags.Where(p=>p.Key is "File:FileCreateDate" or "File:FileModifyDate" or "PhotoTrail:RenameReferenceDate"))values[entry.Key]=entry.Value;
            var result=new RenameInput(group.Leader.Path,values).Tag(key);if(result?.StartsWith('\0')==true)throw new ArgumentException(L10n.Text("标签类型无效：")+key);return result;
        }
        var tags=key=="city"?new[]{"XMP-photoshop:City","IPTC:City"}:new[]{"XMP-tiff:Model","IFD0:Model","ExifIFD:Model"};
        foreach(var tag in tags) {
            if(imported?.Draft.TryGetValue(tag,out var draft)==true)return draft.Length==0?null:draft;
            var data=tag.StartsWith("XMP-",StringComparison.Ordinal)?imported?.Sidecar??sidecar??embedded:embedded;
            if(!data.TryGetProperty(tag,out var value))continue;
            if(value.ValueKind!=JsonValueKind.String)throw new ArgumentException(L10n.Text("字段类型错误：")+tag);
            if(!string.IsNullOrEmpty(value.GetString()))return value.GetString();
        }
        return null;
    }
    CancellationTokenSource? m8SettingsRefresh;
    private async void RenameOrderChanged(object sender,RoutedEventArgs e){
        if(!IsLoaded||fillingRenameControls)return;RenameRulesChanged(sender,e);
        if(sender!=RenamePair&&sender!=RenameSources&&sender!=RenameTargets&&sender!=RenameDatePriority)return;
        m8SettingsRefresh?.Cancel();m8SettingsRefresh?.Dispose();var request=m8SettingsRefresh=new();
        try{await Task.Delay(300,request.Token);if(busy||request.IsCancellationRequested)return;ReadRenameOrder().Validate();RefreshRenameOrder(sender,e);}
        catch(OperationCanceledException){}catch(ArgumentException error){RenameStatus.Text=L10n.Message(error.Message);}
    }
    private void RenameViewChanged(object sender,RoutedEventArgs e){if(!IsLoaded||RenamePreview.ItemsSource is null)return;var view=System.Windows.Data.CollectionViewSource.GetDefaultView(RenamePreview.ItemsSource);using(view.DeferRefresh()){view.Filter=item=>RenameViewFilter.SelectedIndex switch{1=>item is RenameFile f?f.Source!=f.Target:item is RenameOutcome o&&o.Source!=o.Current,2=>item is RenameFile f?f.Source==f.Target:item is RenameOutcome o&&o.Source==o.Current,_=>true};view.SortDescriptions.Clear();if(RenameViewOrder.SelectedIndex!=0)view.SortDescriptions.Add(new("NewName",RenameViewOrder.SelectedIndex==1?System.ComponentModel.ListSortDirection.Ascending:System.ComponentModel.ListSortDirection.Descending));}UpdateRenameButtons();}
    async Task ReadRenameGroupsAsync(CancellationToken cancellation){
        var reference=DateTimeOffset.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz",System.Globalization.CultureInfo.InvariantCulture);
        var selected=RenameSelection();var order=ReadRenameOrder();order.Validate();var inputPaths=selected.Select(r=>r.Document.FilePath).ToArray();
        if(!order.Pair&&selected.Any(r=>r.Document.SidecarPath is not null||File.Exists(Path.ChangeExtension(r.Document.FilePath,".xmp"))))throw new IOException(L10n.Text("关闭配对会拆开实际XMP来源，未安排更名；请启用配对。"));
        var roots=inputPaths.Select(p=>RenameGroup.Key(p,order)).ToHashSet(StringComparer.OrdinalIgnoreCase);var paths=inputPaths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if(order.Pair)foreach(var dir in inputPaths.Where(p=>order.SourceList.Contains(Path.GetExtension(p).TrimStart('.').ToLowerInvariant())).Select(Path.GetDirectoryName).Distinct(StringComparer.OrdinalIgnoreCase)){
            int scanned=0;foreach(var path in Directory.EnumerateFiles(dir!)){if(++scanned>100000)throw new IOException(L10n.Text("目录配对扫描超过100000项。"));if(roots.Contains(RenameGroup.Key(path,order)))paths.Add(path);}
        }
        if(roots.Count>3000||paths.Count>6000)throw new ArgumentException(L10n.Text("超过3000组或6000个物理文件上限。"));
        // Keep a full before/after source interval; batch only the external metadata process, never the file proofs.
        var proofs=new Dictionary<string,(ImportSource Version,string Hash,FileInfo File)>(StringComparer.OrdinalIgnoreCase);
        foreach(var path in paths) {
            cancellation.ThrowIfCancellationRequested();var version=ImportSource.Read(path);var hash=await PhotoDocument.HashAsync(path,cancellation);var file=new FileInfo(path);
            if((file.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException(L10n.Text("配对成员为链接，未读取。"));
            proofs.Add(path,(version,hash,file));
        }
        var inputs=new List<RenameInput>();
        foreach(var chunk in paths.Chunk(64)) {
            cancellation.ThrowIfCancellationRequested();var metadataByPath=new Dictionary<string,JsonElement>(StringComparer.OrdinalIgnoreCase);
            try { foreach(var pair in await Tool().ReadManyAsync(chunk,cancellation))metadataByPath.Add(pair.Key,pair.Value); }
            catch(Exception error)when(error is IOException or TimeoutException) {
                // A damaged member can make ExifTool fail the batch; retain individual failure attribution.
                foreach(var path in chunk)try{metadataByPath.Add(path,await Tool().ReadAsync(path,cancellation));}
                    catch(OperationCanceledException){throw;}catch(Exception readError)when(readError is IOException or JsonException or InvalidDataException or TimeoutException){}
            }
            foreach(var path in chunk) {
                cancellation.ThrowIfCancellationRequested();var (version,hash,file)=proofs[path];var tags=new Dictionary<string,string>();JsonElement? metadata=null;bool failed=!metadataByPath.TryGetValue(path,out var data);
                if(!failed)try {
                    metadata=data.Clone();var extension=Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
                    if(order.SourceList.Contains(extension)&&(!data.TryGetProperty("File:MIMEType",out var mime)||!mime.ToString().StartsWith("image/",StringComparison.OrdinalIgnoreCase))||extension=="xmp"&&(!data.TryGetProperty("File:FileType",out var kind)||kind.ToString()!="XMP"))throw new InvalidDataException(L10n.Text("配对照片或XMP内容无效。"));
                    foreach(var tag in data.EnumerateObject().Where(t=>t.Name!="SourceFile"))tags[tag.Name]=PhotoDocument.Text(tag.Value);
                }catch(Exception error)when(error is IOException or JsonException or InvalidDataException){failed=true;}
                if(hash!=await PhotoDocument.HashAsync(path,cancellation))throw new IOException(L10n.Text("配对成员读取期间改变。"));
                version.RequireCurrent();
                var imported=photos.FirstOrDefault(r=>r.Document.FilePath.Equals(path,StringComparison.OrdinalIgnoreCase));if(imported is not null&&hash!=imported.Document.SourceHash)throw new IOException(L10n.Text("已导入照片在外部改变，请重新导入。"));
                tags["PhotoTrail:RenameReferenceDate"]=reference;tags["File:FileCreateDate"]=file.CreationTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ");tags["File:FileModifyDate"]=file.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ");inputs.Add(new(path,tags,failed,file.Length,hash,metadata));
            }
        }
        inputs=inputs.Select(member=>{
            var imported=photos.FirstOrDefault(row=>(row.Document.FilePath.Equals(member.Path,StringComparison.OrdinalIgnoreCase)||row.Document.SidecarPath?.Equals(member.Path,StringComparison.OrdinalIgnoreCase)==true))?.Document;
            var external=inputs.FirstOrDefault(other=>other.Extension=="xmp"&&!other.Path.Equals(member.Path,StringComparison.OrdinalIgnoreCase)&&RenameGroup.Key(other.Path,order)==RenameGroup.Key(member.Path,order));
            var merged=new Dictionary<string,string>(member.Tags,StringComparer.Ordinal);
            if(external?.Metadata is {} side)foreach(var tag in side.EnumerateObject().Where(p=>p.Name.StartsWith("XMP-",StringComparison.Ordinal)))merged[tag.Name]=PhotoDocument.Text(tag.Value);
            if(imported is not null)foreach(var tag in imported.Draft)merged[tag.Key]=tag.Value;
            bool cleared=imported is not null&&imported.Draft.TryGetValue(imported.MainDateTag,out var pending)&&pending.Length==0;
            return member with{Tags=merged,DatePriority=order.DatePriority,CaptureKnown=cleared,MainCapture=null};
        }).ToList();
        var groups=inputs.GroupBy(m=>RenameGroup.Key(m.Path,order),StringComparer.OrdinalIgnoreCase).Select(values=>{var members=values.ToArray();var id=members.Select(m=>renameIdentities.GetValueOrDefault(m.Path)).FirstOrDefault(v=>v is not null)??Guid.NewGuid().ToString("N");foreach(var member in members)renameIdentities[member.Path]=id;return new RenameGroup(id,members){Settings=order};}).ToArray();
        renameGroups=groups;manualRenameOrder=manualRenameOrder.Concat(groups.Select(g=>g.Id).Where(id=>!manualRenameOrder.Contains(id))).ToArray();
    }
    private async void RefreshRenameOrder(object sender,RoutedEventArgs e){
        if(busy||renameRecoveryRequired)return;renameReadingPreview=true;var revision=++renameRevision;frozenRenamePlan=null;BeginOperation();try{await ReadRenameGroupsAsync(operation!.Token);if(revision==renameRevision){await RenderRenameGroupsAsync();RenameStatus.Text=L10n.Message(L10n.Text("配对元数据与完整处理组已读取；尚未写文件。"));}}catch(OperationCanceledException){RenameStatus.Text=L10n.Message(L10n.Text("读取已取消，未改文件。"));}catch(Exception error){renameGroups=[];RenameGroups.ItemsSource=null;RenamePreview.ItemsSource=null;RenameStatus.Text=L10n.Message(L10n.Text("处理预览未读取：")+L10n.Message(error.Message));}finally{renameReadingPreview=false;EndOperation();}
    }
    void RemapRenameIdentities(RenameResult result){var changed=result.Files.Where(f=>renameIdentities.ContainsKey(f.Source)).Select(f=>(file:f,id:renameIdentities[f.Source])).ToArray();foreach(var item in changed)renameIdentities.Remove(item.file.Source);foreach(var item in changed)renameIdentities[item.file.Current]=item.id;renameGroups=renameGroups.Select(g=>g with{Members=g.Members.Select(m=>result.Files.FirstOrDefault(f=>f.Source.Equals(m.Path,StringComparison.OrdinalIgnoreCase)) is{} f?m with{Path=f.Current}:m).ToArray()}).ToArray();RenameGroups.ItemsSource=IncludedRenameGroups();}
    bool CanMoveRenameGroups=>!busy&&!renameRecoveryRequired&&RenamePreview.ItemsSource is not null&&RenameViewOrder.SelectedIndex==0&&RenameViewFilter.SelectedIndex==0&&System.Windows.Data.CollectionViewSource.GetDefaultView(RenamePreview.ItemsSource).SortDescriptions.Count==0;
    void MoveRenameGroups(string[] moving,string target){if(!CanMoveRenameGroups)return;var current=OrderedRenameGroups().Select(g=>g.Id).ToArray();var currentSet=current.ToHashSet();int slot=0;var full=manualRenameOrder.Select(id=>currentSet.Contains(id)?current[slot++]:id).Concat(current.Where(id=>!manualRenameOrder.Contains(id))).ToArray();var visible=IncludedRenameGroups().Select(g=>g.Id).ToArray();var next=RenameOrder.Move(moving.ToHashSet(),target,visible,full);if(next.SequenceEqual(full))return;renameOrderUndo=full;manualRenameOrder=next;fillingRenameControls=true;try{RenameProcessingSort.SelectedIndex=14;RenameDescending.IsChecked=false;}finally{fillingRenameControls=false;}RenameRulesChanged(this,new RoutedEventArgs());RenameGroups.SelectedItems.Clear();foreach(var g in IncludedRenameGroups().Where(g=>moving.Contains(g.Id)))RenameGroups.SelectedItems.Add(g);}
    private void UndoRenameOrder(object sender,RoutedEventArgs e){if(!CanMoveRenameGroups||renameOrderUndo is null)return;manualRenameOrder=renameOrderUndo;renameOrderUndo=null;fillingRenameControls=true;try{RenameProcessingSort.SelectedIndex=14;RenameDescending.IsChecked=false;}finally{fillingRenameControls=false;}RenameRulesChanged(sender,e);}
    private void InsertRenameGroups(object sender,RoutedEventArgs e){if(!int.TryParse(RenameInsertPosition.Text,out var position)||position<1||position>RenameGroups.Items.Count+1){RenameStatus.Text=L10n.Message(L10n.Text("插入位置须为1至可见组数+1；最后一个位置代表末尾。"));return;}var moving=RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToArray();MoveRenameGroups(moving,position>RenameGroups.Items.Count?"":((RenameGroup)RenameGroups.Items[position-1]).Id);}
    void StepRenameGroups(bool down){if(!CanMoveRenameGroups)return;var visible=IncludedRenameGroups().Select(g=>g.Id).ToArray();var moving=RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToHashSet();var indices=visible.Select((id,i)=>(id,i)).Where(p=>moving.Contains(p.id)).Select(p=>p.i).ToArray();if(indices.Length==0)return;int target=down?indices.Max()+2:indices.Min()-1;if(target<0)return;MoveRenameGroups(moving.ToArray(),target>=visible.Length?"":visible[target]);}
    private void RenameMoveUp(object sender,RoutedEventArgs e)=>StepRenameGroups(false);
    private void RenameMoveDown(object sender,RoutedEventArgs e)=>StepRenameGroups(true);
    private void RenameOrderKey(object sender,KeyEventArgs e){var key=e.Key==Key.System?e.SystemKey:e.Key;if(Keyboard.Modifiers==ModifierKeys.Alt&&key is Key.Up or Key.Down){StepRenameGroups(key==Key.Down);e.Handled=true;}else if(Keyboard.Modifiers==ModifierKeys.Control&&key==Key.Z){UndoRenameOrder(sender,e);e.Handled=true;}}
    private void RenameDragBegin(object sender,MouseButtonEventArgs e){renameDragStart=e.GetPosition(RenameGroups);var node=e.OriginalSource as DependencyObject;while(node is not null&&node is not ListBoxItem)node=VisualTreeHelper.GetParent(node);renameDragIds=node is ListBoxItem item&&item.DataContext is RenameGroup group?(item.IsSelected?RenameGroups.SelectedItems.Cast<RenameGroup>().Select(g=>g.Id).ToArray():[group.Id]):[];if(node is ListBoxItem{IsSelected:true}&&RenameGroups.SelectedItems.Count>1&&Keyboard.Modifiers==ModifierKeys.None)e.Handled=true;}
    private void RenameDragMove(object sender,MouseEventArgs e){if(!CanMoveRenameGroups||e.LeftButton!=MouseButtonState.Pressed||renameDragIds.Length==0)return;var p=e.GetPosition(RenameGroups);if(Math.Abs(p.X-renameDragStart.X)<SystemParameters.MinimumHorizontalDragDistance&&Math.Abs(p.Y-renameDragStart.Y)<SystemParameters.MinimumVerticalDragDistance)return;var ids=renameDragIds;renameDragIds=[];DragDrop.DoDragDrop(RenameGroups,new DataObject("PhotoTrail.Windows.RenameGroups",ids),DragDropEffects.Move);RenameGroups.Focus();e.Handled=true;}
    string RenameDropTarget(DragEventArgs e){var hit=RenameGroups.InputHitTest(e.GetPosition(RenameGroups)) as DependencyObject;while(hit is not null&&hit is not ListBoxItem)hit=VisualTreeHelper.GetParent(hit);return (hit as ListBoxItem)?.DataContext is RenameGroup group?group.Id:"";}
    private void RenameDragOver(object sender,DragEventArgs e){var valid=CanMoveRenameGroups&&e.Data.GetData("PhotoTrail.Windows.RenameGroups")is string[] ids&&ids.All(id=>IncludedRenameGroups().Any(g=>g.Id==id));e.Effects=valid?DragDropEffects.Move:DragDropEffects.None;RenameDropHint.Text=valid?L10n.Text("插入到：")+(RenameDropTarget(e)is var target&&target.Length>0?IncludedRenameGroups().First(g=>g.Id==target).Name+L10n.Text(" 之前"):L10n.Text("可见组末尾")):L10n.Text("仅处理顺序视图、查看全部且空闲时可拖动。");e.Handled=true;}
    private void RenameDrop(object sender,DragEventArgs e){if(e.Data.GetData("PhotoTrail.Windows.RenameGroups")is string[] ids){var before=renameRevision;MoveRenameGroups(ids,RenameDropTarget(e));RenameDropHint.Text=before!=renameRevision?L10n.Text("放下成功；仅更新内存顺序。"):L10n.Text("放下未改变顺序。");}e.Handled=true;}
}
