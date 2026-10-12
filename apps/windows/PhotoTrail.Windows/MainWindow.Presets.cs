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
        PresetAction.ItemsSource = new[] { ("setText","固定设置文字／日期／数字"),("remove","明确清除"),("fillMissingText","仅补确认缺失的标量"),("appendText","文字精确追加"),("replaceAuthors","替换作者列表"),("fillMissingAuthors","仅补缺失作者"),("replaceKeywords","替换关键词"),("appendKeywords","精确追加关键词"),("removeKeywords","精确移除关键词"),("copy","按照片自身字段复制") }.Select(p => new { Action=p.Item1,Name=p.Item2 }).ToArray();
        PresetAction.SelectedIndex = 4; fillingPreset = false;
        presetOperations.CollectionChanged += (_,_) => { InvalidateDates(); RefreshPresetLibraryControls(); };
    }
    void PresetInputChanged(object sender,TextChangedEventArgs e) { if (!fillingPreset) { InvalidateDates(); RefreshPresetLibraryControls(); } }
    void PresetEditorChanged(object sender,RoutedEventArgs e) { if (!fillingPreset && IsLoaded) { presetEditorDirty = true; InvalidateDates(); RefreshPresetLibraryControls(); } }
    void PresetActionChanged(object sender,SelectionChangedEventArgs e) {
        if (PresetCopyControls is null) return;
        bool copy = PresetAction.SelectedValue as string == "copy";
        PresetCopyControls.Visibility = copy ? Visibility.Visible : Visibility.Collapsed;
        PresetTarget.IsEnabled = !copy; PresetValue.IsEnabled = !copy && PresetAction.SelectedValue as string != "remove";
        PresetEditorChanged(sender,e);
    }
    void PresetSelectionChanged(object sender,SelectionChangedEventArgs e) {
        if (fillingPreset || PresetOperations.SelectedItem is not MetadataOperation op) return;
        if (presetEditorDirty) { fillingPreset=true;try{PresetOperations.SelectedIndex=presetEditingIndex;}finally{fillingPreset=false;} PresetPreview.Text = "未编排参数保留；请先添加／更新或放弃参数，再选择操作。"; return; }
        presetEditingIndex=PresetOperations.SelectedIndex; FillPresetOperation(op);
    }
    void FillPresetOperation(MetadataOperation op) {
        fillingPreset = true;
        try { PresetTarget.SelectedValue=op.Tag; PresetAction.SelectedValue=op.Action; PresetValue.Text=op.Action=="copy"?"":op.Value; PresetSource.SelectedValue=op.Action=="copy"?op.Value:MetadataCsv.Tags[0]; PresetRecipients.SelectedItems.Clear(); if(op.Action=="copy")foreach(PresetField field in PresetRecipients.Items)if(field.Tag==op.Tag)PresetRecipients.SelectedItems.Add(field); }
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
        return [MetadataPreset.Validate(new(PresetTarget.SelectedValue as string ?? "",action,action=="remove"?"":PresetValue.Text.Replace("\r\n","\n")))];
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
    void RequirePresetInputSaved(){if(presetEditorDirty)throw new InvalidOperationException("请先添加／更新或放弃未编排参数。");}
    void MovePreset(int delta)=>ChangePreset(()=>{RequirePresetInputSaved();int index=PresetOperations.SelectedIndex;if(index>=0&&index+delta>=0&&index+delta<presetOperations.Count){presetOperations.Move(index,index+delta);PresetOperations.SelectedIndex=index+delta;}});
    void MovePresetUp(object sender,RoutedEventArgs e)=>MovePreset(-1);
    void MovePresetDown(object sender,RoutedEventArgs e)=>MovePreset(1);
    void DeletePresetOperation(object sender,RoutedEventArgs e)=>ChangePreset(()=>{RequirePresetInputSaved();if(PresetOperations.SelectedIndex>=0)presetOperations.RemoveAt(PresetOperations.SelectedIndex);});
    void ClearPresetOperations(object sender,RoutedEventArgs e)=>ChangePreset(()=>{RequirePresetInputSaved();presetOperations.Clear();});
    void DiscardPresetInput(object sender,RoutedEventArgs e){if(busy)return;presetEditorDirty=false;FillPresetOperation(PresetOperations.SelectedItem as MetadataOperation ?? new(MetadataCsv.Tags[0],"replaceAuthors",""));PresetPreview.Text="未编排参数已放弃；照片草稿保留。";}
    void SetPresetChain(MetadataPreset preset){fillingPreset=true;try{PresetName.Text=preset.Name;presetOperations.Clear();foreach(var op in preset.Operations)presetOperations.Add(op);PresetOperations.SelectedIndex=-1;presetEditingIndex=-1;}finally{fillingPreset=false;presetEditorDirty=false;}InvalidateDates();PresetPreview.Text=$"{preset.Name}：{presetOperations.Count} 条有序操作，尚未应用。";RefreshPresetLibraryControls();}
    void PresetFromFields(object sender,RoutedEventArgs e)=>ChangePreset(()=>{RequirePresetInputSaved();var next=MetadataPreset.Create(PresetName.Text,ReadFieldInput());if(!ResolvePresetChainEdits())return;SetUnsavedPreset(next);FillEditor(new Dictionary<string,string>());});
    void ChoosePreset(object sender,RoutedEventArgs e){if(busy)return;var dialog=new OpenFileDialog{Title="选择字段预设",Filter="JSON预设|*.json",CheckFileExists=true};if(dialog.ShowDialog(this)==true)PresetPath.Text=dialog.FileName;}
    void SaveFieldPreset(object sender,RoutedEventArgs e)=>SavePresetFile(()=>MetadataPreset.Create(PresetName.Text,ReadFieldInput()));
    void SavePreset(object sender,RoutedEventArgs e)=>SavePresetFile(()=>{RequirePresetInputSaved();return MetadataPreset.Create(PresetName.Text,presetOperations);});
    void SavePresetFile(Func<MetadataPreset> read){if(busy||renameRecoveryRequired)return;try{var text=read().Encode();var dialog=new SaveFileDialog{Title="保存字段预设（不覆盖）",Filter="JSON预设|*.json",DefaultExt=".json",FileName="PhotoTrail-preset.json",OverwritePrompt=false};if(dialog.ShowDialog(this)!=true)return;MetadataCsv.WriteNew(dialog.FileName,text);Status.Text="预设已保存，操作链和草稿保留；未修改照片。";}catch(Exception error){Status.Text="预设未保存："+error.Message;}}
    void LoadPreset(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{RequirePresetInputSaved();if(Fields.Any(f=>f.Apply.IsChecked==true))throw new InvalidOperationException("请先应用或撤销编辑区输入，再载入操作链。");var preset=ReadPresetFile(PresetPath.Text);if(!ResolvePresetChainEdits())return;SetUnsavedPreset(preset);Status.Text="预设已载入有序操作链；未应用草稿或写照片。";}catch(Exception error){Status.Text="预设未载入："+error.Message;}}
    async void ApplyPreset(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{RequirePresetInputSaved();if(Fields.Any(f=>f.Apply.IsChecked==true))throw new InvalidOperationException("请先应用或撤销编辑区输入。");var preset=MetadataPreset.Create(PresetName.Text,presetOperations);string input=preset.Encode();await ApplyMetadataBatch("预设",(docs,_,token)=>{int missing=0;foreach(var doc in docs){token.ThrowIfCancellationRequested();missing+=preset.Apply(doc,token);}return Task.FromResult(new BatchDetails(CopyMissing:missing,OperationCount:preset.Operations.Count));},()=>!presetEditorDirty&&!Fields.Any(f=>f.Apply.IsChecked==true)&&MetadataPreset.Create(PresetName.Text,presetOperations).Encode()==input);}catch(Exception error){Status.Text="预设未应用："+error.Message;}}
}
