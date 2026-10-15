using System.Collections.ObjectModel;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace PhotoTrail.Windows;
public partial class MainWindow
{
    readonly ObservableCollection<MetadataOperation> presetOperations = [];
    bool fillingPreset, presetEditorDirty;
    int presetEditingIndex = -1;
    sealed record PresetField(string Tag,string Name);
    void InitializePresetEditor()
    {
        fillingPreset = true;
        var fields = MetadataCsv.Tags.Select(tag => new PresetField(tag, fieldLabels[tag] + " · " + tag)).ToArray();
        PresetOperations.ItemsSource = presetOperations;
        PresetTarget.ItemsSource = PresetSource.ItemsSource = PresetRecipients.ItemsSource = fields;
        PresetTarget.SelectedIndex = PresetSource.SelectedIndex = 0;
        PresetAction.ItemsSource = new[] { ("setText","固定设置文字／日期／数字"),("remove","明确清除"),("fillMissingText","仅补确认缺失的标量"),("appendText","文字精确追加"),("replaceAuthors","替换作者列表"),("fillMissingAuthors","仅补缺失作者"),("replaceKeywords","替换关键词"),("appendKeywords","精确追加关键词"),("removeKeywords","精确移除关键词"),("copy","按照片自身字段复制"),("offsetDate","六组件时间偏移"),("dateComponent","修改时间中的指定部分"),("sequence","按固定间隔设置日期"),("distribute","范围内均匀分配日期"),("filenameDate","从每张照片文件名提取日期") }.Select(p => new { Action=p.Item1,Name=p.Item2 }).ToArray();
        PresetAction.SelectedIndex = 4; fillingPreset = false;
        presetOperations.CollectionChanged += (_,_) => { InvalidateDates(); RefreshPresetLibraryControls(); RebuildWorkflowCards(); };
    }
    void PresetInputChanged(object sender,TextChangedEventArgs e) { if (!fillingPreset) { InvalidateDates(); RefreshPresetLibraryControls(); } }
    void PresetEditorChanged(object sender,RoutedEventArgs e) { if (!fillingPreset && IsLoaded) { presetEditorDirty = true; InvalidateDates(); RefreshPresetLibraryControls(); } }
    void PresetActionChanged(object sender,SelectionChangedEventArgs e) {
        if (PresetCopyControls is null) return;
        bool copy = PresetAction.SelectedValue as string == "copy";
        PresetCopyControls.Visibility = copy ? Visibility.Visible : Visibility.Collapsed;
        var action=PresetAction.SelectedValue as string??"";bool date=PresetDateArguments.IsAction(action);
        if(PresetDateControls is not null) {
            PresetDateControls.Visibility=date?Visibility.Visible:Visibility.Collapsed;
            PresetDateShiftOptions.Visibility=action is "offsetDate" or "shiftDate" or "calendarDays"?Visibility.Visible:Visibility.Collapsed;
            PresetDateReplaceOptions.Visibility=action=="dateComponent"?Visibility.Visible:Visibility.Collapsed;
            PresetDateStartOptions.Visibility=action is "sequence" or "distribute"?Visibility.Visible:Visibility.Collapsed;
            PresetDateSequenceOptions.Visibility=action=="sequence"?Visibility.Visible:Visibility.Collapsed;
            PresetDateDistributionOptions.Visibility=action=="distribute"?Visibility.Visible:Visibility.Collapsed;
            PresetDateFilenameOptions.Visibility=action=="filenameDate"?Visibility.Visible:Visibility.Collapsed;
        }
        PresetTarget.IsEnabled = !copy; PresetValue.IsEnabled = !copy && !date && action != "remove";
        PresetEditorChanged(sender,e);
    }
    void PresetSelectionChanged(object sender,SelectionChangedEventArgs e) {
        if (fillingPreset || PresetOperations.SelectedItem is not MetadataOperation op) return;
        if (presetEditorDirty) { fillingPreset=true;try{PresetOperations.SelectedIndex=presetEditingIndex;}finally{fillingPreset=false;} PresetPreview.Text = "未编排参数保留；请先添加／更新或放弃参数，再选择操作。"; return; }
        presetEditingIndex=PresetOperations.SelectedIndex; FillPresetOperation(op);
    }
    void FillPresetOperation(MetadataOperation op) {
        fillingPreset = true;
        try { PresetTarget.SelectedValue=op.Tag; PresetAction.SelectedValue=op.Action; PresetValue.Text=op.Action=="copy"?"":op.Value; PresetSource.SelectedValue=op.Action=="copy"?op.Value:MetadataCsv.Tags[0]; PresetRecipients.SelectedItems.Clear();FillPresetDate(op.Date??new()); if(op.Action=="copy")foreach(PresetField field in PresetRecipients.Items)if(field.Tag==op.Tag)PresetRecipients.SelectedItems.Add(field); }
        finally { fillingPreset=false;presetEditorDirty=false;RefreshPresetLibraryControls(); }
    }
    MetadataOperation[] ReadPresetOperations() {
        string action=PresetAction.SelectedValue as string ?? throw new ArgumentException("请选择动作。");
        if(action=="copy") {
            string source=PresetSource.SelectedValue as string ?? throw new ArgumentException("请选择复制源。");
            var targets=PresetRecipients.SelectedItems.Cast<PresetField>().Select(p=>p.Tag).ToHashSet();
            var result=MetadataCsv.Tags.Where(tag=>targets.Contains(tag)&&tag!=source).Select(tag=>MetadataPreset.Validate(new(tag,"copy",source))).ToArray();
            if(result.Length==0)throw new ArgumentException("请选择至少一个不同于源的接收字段。");return result;
        }
        return [MetadataPreset.Validate(PresetDateArguments.IsAction(action)?new(PresetTarget.SelectedValue as string??"",action,Date:ReadPresetDate(action)):new(PresetTarget.SelectedValue as string ?? "",action,action=="remove"?"":PresetValue.Text.Replace("\r\n","\n")))];
    }
    void FillPresetDate(PresetDateArguments date) {
        foreach(var (box,value) in new[]{(PresetDateYears,date.Years),(PresetDateMonths,date.Months),(PresetDateDays,date.Days),(PresetDateHours,date.Hours),(PresetDateMinutes,date.Minutes),(PresetDateSeconds,date.Seconds),(PresetDateStep,date.Seconds)})box.Text=value.ToString(System.Globalization.CultureInfo.InvariantCulture);
        foreach(var (key,box) in new[]{("year",PresetDateReplaceYear),("month",PresetDateReplaceMonth),("day",PresetDateReplaceDay),("hour",PresetDateReplaceHour),("minute",PresetDateReplaceMinute),("second",PresetDateReplaceSecond)})box.Text=date.Components is {} c&&c.TryGetValue(key,out var n)?n.ToString(System.Globalization.CultureInfo.InvariantCulture):"";
        PresetDateStart.Text=date.Start;PresetDateEnd.Text=date.End;PresetDateFilenamePattern.Text=date.Pattern;PresetDateFilenameTemplate.Text=date.Template;
    }
    PresetDateArguments ReadPresetDate(string action) {
        long N(TextBox box)=>long.TryParse(box.Text,System.Globalization.NumberStyles.AllowLeadingSign,System.Globalization.CultureInfo.InvariantCulture,out var n)?n:throw new ArgumentException("日期参数须为有符号宽整数。");
        return action switch {
            "offsetDate"=>new(N(PresetDateYears),N(PresetDateMonths),N(PresetDateDays),N(PresetDateHours),N(PresetDateMinutes),N(PresetDateSeconds)),
            "sequence"=>new(Seconds:N(PresetDateStep),Start:PresetDateStart.Text),"distribute"=>new(Start:PresetDateStart.Text,End:PresetDateEnd.Text),
            "dateComponent"=>new(Components:new[]{("year",PresetDateReplaceYear),("month",PresetDateReplaceMonth),("day",PresetDateReplaceDay),("hour",PresetDateReplaceHour),("minute",PresetDateReplaceMinute),("second",PresetDateReplaceSecond)}.Where(p=>p.Item2.Text.Length>0).ToDictionary(p=>p.Item1,p=>N(p.Item2))),
            "filenameDate"=>new(Pattern:PresetDateFilenamePattern.Text,Template:PresetDateFilenameTemplate.Text),
            "shiftDate"=>new(Seconds:N(PresetDateSeconds)),"calendarDays"=>new(Days:N(PresetDateDays)),_=>throw new ArgumentException("日期动作未知。")
        };
    }
    void ChangePreset(Action action) {
        if(busy||renameRecoveryRequired)return;
        try{action();PresetPreview.Text=$"当前操作链 {presetOperations.Count} 条；尚未应用到照片。";}
        catch(Exception error){PresetPreview.Text="操作链未改变："+error.Message;}
    }
    void AddPresetOperation(object sender,RoutedEventArgs e)=>ChangePreset(()=>{
        var additions=ReadPresetOperations();MetadataPreset.Create(PresetName.Text,presetOperations.Concat(additions).ToArray());
        foreach(var op in additions)presetOperations.Add(op);presetEditorDirty=false;PresetOperations.SelectedIndex=presetOperations.Count-1;
    });
    void UpdatePresetOperation(object sender,RoutedEventArgs e)=>ChangePreset(()=>{
        int index=PresetOperations.SelectedIndex;if(index<0)throw new ArgumentException("请选择要编辑的操作。");var replacement=ReadPresetOperations();
        var chain=presetOperations.ToList();chain.RemoveAt(index);chain.InsertRange(index,replacement);MetadataPreset.Create(PresetName.Text,chain);
        presetEditorDirty=false;presetOperations.RemoveAt(index);for(int i=0;i<replacement.Length;i++)presetOperations.Insert(index+i,replacement[i]);PresetOperations.SelectedIndex=index;
    });
    void RequirePresetInputSaved(){if(presetEditorDirty || invalidWorkflowCards.Count > 0)throw new InvalidOperationException("请先添加／更新或放弃未编排参数。");if(disabledWorkflowOperations.Count > 0)throw new InvalidOperationException(WText("DisabledExport"));}
    void MovePreset(int delta)=>ChangePreset(()=>{RequirePresetInputSaved();int index=PresetOperations.SelectedIndex;if(index>=0&&index+delta>=0&&index+delta<presetOperations.Count){presetOperations.Move(index,index+delta);PresetOperations.SelectedIndex=index+delta;}});
    void MovePresetUp(object sender,RoutedEventArgs e)=>MovePreset(-1);
    void MovePresetDown(object sender,RoutedEventArgs e)=>MovePreset(1);
    void DeletePresetOperation(object sender,RoutedEventArgs e)=>ChangePreset(()=>{RequirePresetInputSaved();if(PresetOperations.SelectedIndex>=0)presetOperations.RemoveAt(PresetOperations.SelectedIndex);});
    void ClearPresetOperations(object sender,RoutedEventArgs e)=>ChangePreset(()=>{RequirePresetInputSaved();presetOperations.Clear();});
    void DiscardPresetInput(object sender,RoutedEventArgs e){if(busy)return;presetEditorDirty=false;FillPresetOperation(PresetOperations.SelectedItem as MetadataOperation ?? new(MetadataCsv.Tags[0],"replaceAuthors",""));PresetPreview.Text="未编排参数已放弃；照片草稿保留。";}
    void SetPresetChain(MetadataPreset preset){fillingPreset=true;try{PresetName.Text=preset.Name;presetOperations.Clear();foreach(var op in preset.Operations)presetOperations.Add(op);PresetOperations.SelectedIndex=-1;presetEditingIndex=-1;}finally{fillingPreset=false;presetEditorDirty=false;}InvalidateDates();PresetPreview.Text=$"{preset.Name}：{presetOperations.Count} 条有序操作，尚未应用。";RefreshPresetLibraryControls();}
    void PresetFromFields(object sender,RoutedEventArgs e)=>_ = LibraryActionAsync(async()=>{RequirePresetInputSaved();var next=MetadataPreset.Create(PresetName.Text,ReadFieldInput());await ValidatePresetAsync(next);if(!await ResolvePresetChainEditsAsync())return;SetUnsavedPreset(next);FillEditor(new Dictionary<string,string>());});
    void ChoosePreset(object sender,RoutedEventArgs e){if(busy)return;var dialog=new OpenFileDialog{Title="选择字段预设",Filter="JSON预设|*.json",CheckFileExists=true};if(dialog.ShowDialog(this)==true)PresetPath.Text=dialog.FileName;}
    void SaveFieldPreset(object sender,RoutedEventArgs e)=>SavePresetFile(()=>MetadataPreset.Create(PresetName.Text,ReadFieldInput()));
    void SavePreset(object sender,RoutedEventArgs e)=>SavePresetFile(()=>{RequirePresetInputSaved();return MetadataPreset.Create(PresetName.Text,presetOperations);});
    async void SavePresetFile(Func<MetadataPreset> read){if(busy||renameRecoveryRequired)return;try{var preset=read();await ValidatePresetAsync(preset);var text=preset.Encode();var dialog=new SaveFileDialog{Title="保存字段预设（不覆盖）",Filter="JSON预设|*.json",DefaultExt=".json",FileName="PhotoTrail-preset.json",OverwritePrompt=false};if(dialog.ShowDialog(this)!=true)return;MetadataCsv.WriteNew(dialog.FileName,text);Status.Text="预设已保存，操作链和草稿保留；未修改照片。";}catch(Exception error){Status.Text="预设未保存："+error.Message;}}
    async void LoadPreset(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{RequirePresetInputSaved();if(Fields.Any(f=>f.Apply.IsChecked==true))throw new InvalidOperationException("请先应用或撤销编辑区输入，再载入操作链。");var preset=ReadPresetFile(PresetPath.Text);await ValidatePresetAsync(preset);if(!await ResolvePresetChainEditsAsync())return;SetUnsavedPreset(preset);Status.Text="预设已载入有序操作链；未应用草稿或写照片。";}catch(Exception error){Status.Text="预设未载入："+error.Message;}}
    async void ApplyPreset(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{RequirePresetInputSaved();if(Fields.Any(f=>f.Apply.IsChecked==true))throw new InvalidOperationException("请先应用或撤销编辑区输入。");var preset=MetadataPreset.Create(PresetName.Text,presetOperations);string input=preset.Encode();await ApplyMetadataBatch("预设",async(docs,revision,token)=>{var result=await preset.CalculateAsync(docs,revision,()=>Volatile.Read(ref dateRevision),token,adapter=>{batchDateAdapter=adapter;adapter.CalculationStarted+=()=>{batchCalculationTicks=System.Diagnostics.Stopwatch.GetTimestamp();batchCalculationStarted=true;};});return new BatchDetails(Missing:result.Missing,FilenameMismatch:result.FilenameMismatch,FilenameInvalid:result.FilenameInvalid,CopyMissing:result.CopyMissing,OperationCount:preset.Operations.Count,Measurements:result.Measurements,InitialSourceMs:result.ReadMs,ParameterValidationMs:result.ParameterValidationMs);},()=>!presetEditorDirty&&!Fields.Any(f=>f.Apply.IsChecked==true)&&MetadataPreset.Create(PresetName.Text,presetOperations).Encode()==input);}catch(Exception error){Status.Text="预设未应用："+error.Message;}}
}
