using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace PhotoTrail.Windows;
public partial class MainWindow
{
    RenameSchemeSnapshot? renameSchemes;
    Guid? currentRenameScheme;
    RenameScheme? renameSchemeBaseline;
    bool fillingSchemes,renameReadingPreview;
    bool RenameSchemeDirty=>M3InvalidInputs||renameSchemeBaseline is null||RenameSchemeName.Text!=renameSchemeBaseline.Name||RenameSchemeExample.Text!=renameSchemeBaseline.Example||RenameRules.Text!=renameSchemeBaseline.Rules||!SameSchemeOrder(ReadRenameOrder(),renameSchemeBaseline.Order);
    static bool SameSchemeOrder(RenameOrderSettings first,RenameOrderSettings second)=>(first with{MetadataSortTag=first.MetadataSortTag??""})==(second with{MetadataSortTag=second.MetadataSortTag??""});
    void LoadRenameSchemes() {
        try{renameSchemes=RenameSchemeLibrary.Open(RenameSchemeLibrary.DefaultPath);var state=renameSchemes.State;var scheme=state.Schemes.FirstOrDefault(s=>s.Id==state.LastId)??state.Schemes.FirstOrDefault();SetSchemeEditor(scheme);}
        catch(Exception error){renameSchemes=null;RenameSchemeStatus.Text=L10n.Message(L10n.Text("方案库不可读取；未初始化或覆盖：")+L10n.Message(error.Message));}
    }
    void RefreshSchemeControls() {
        if(RenameSchemeList is null)return;bool allowed=!busy&&!renameRecoveryRequired&&renameSchemes is not null;
        RenameSchemeList.IsEnabled=RenameSchemeActions.IsEnabled=allowed;RenameSchemeManager.IsEnabled=allowed||renameReadingPreview&&!renameRecoveryRequired&&renameSchemes is not null;
        if(renameSchemes is not null)RenameSchemeStatus.Text=L10n.Message((currentRenameScheme is null?L10n.Text("未保存方案"):renameSchemeBaseline?.Name??L10n.Text("方案"))+(RenameSchemeDirty?L10n.Text(" · 未保存修改"):L10n.Text(" · 已保存"))+L10n.Text("；方案保存只写配置。"));
    }
    void RefreshSchemeList() {
        fillingSchemes=true;try{RenameSchemeList.ItemsSource=renameSchemes?.State.Schemes;RenameSchemeList.SelectedItem=renameSchemes?.State.Schemes.FirstOrDefault(s=>s.Id==currentRenameScheme);}finally{fillingSchemes=false;}
        RefreshSchemeControls();
    }
    void SetSchemeEditor(RenameScheme? scheme) {
        fillingSchemes=fillingRenameControls=true;
        try{currentRenameScheme=scheme?.Id;renameSchemeBaseline=scheme;RenameSchemeName.Text=scheme?.Name??L10n.Text("新方案");RenameSchemeExample.Text=scheme?.Example??"";RenameRules.Text=scheme?.Rules??"";var order=scheme?.Order??new RenameOrderSettings(){Conflict="numbers"};RenameProcessingSort.SelectedIndex=Array.IndexOf(RenameOrderSettings.Sorts,order.Sort);RenameDescending.IsChecked=order.Descending;RenameMetadataTag.Text=order.MetadataSortTag??"";RenameConflictChoice.SelectedIndex=Array.IndexOf(new[]{"stop","numbers","letters"},order.Conflict);RenameConflictDigits.Text=order.ConflictDigits.ToString(System.Globalization.CultureInfo.InvariantCulture);RenameNumberSuffix.SelectedIndex=Array.IndexOf(new[]{"plain","underscore","dash","parentheses"},order.NumberSuffixFormat);RenameLetterSuffix.SelectedIndex=Array.IndexOf(new[]{"plain","underscore","dash","parentheses"},order.LetterSuffixFormat);RenameKeepFirst.IsChecked=order.KeepFirst;RenamePair.IsChecked=order.Pair;RenameSources.Text=order.SourceExtensions;RenameTargets.Text=order.TargetExtensions;RenameDatePriority.Text=order.DatePriority;}
        finally{fillingSchemes=fillingRenameControls=false;}
        RefreshSchemeList();M3LoadCards();RenameRulesChanged(this,new RoutedEventArgs());
    }
    RenameScheme EditedScheme(Guid id,string? name=null) { M3EnsureValid();return new(id,name??RenameSchemeName.Text,RenameRules.Text,ReadRenameOrder(),RenameSchemeExample.Text); }
    void PersistSchemes(RenameSchemeState state) {
        if(renameSchemes is null)throw new InvalidOperationException(L10n.Text("方案库读取失败，当前编辑保留。"));
        var saved=RenameSchemeLibrary.Save(RenameSchemeLibrary.DefaultPath,renameSchemes,state);renameSchemes=saved;
    }
    void SaveScheme(bool copy) {
        if(renameSchemes is null)throw new InvalidOperationException(L10n.Text("方案库不可用。"));
        var id=!copy&&currentRenameScheme is {} current?current:Guid.NewGuid();var name=RenameSchemeLibrary.UniqueName(RenameSchemeName.Text,renameSchemes.State.Schemes,id);var scheme=EditedScheme(id,name);scheme.Validate();
        var entries=renameSchemes.State.Schemes.Where(s=>s.Id!=id).ToList();int position=Array.FindIndex(renameSchemes.State.Schemes,s=>s.Id==id);if(position<0)entries.Add(scheme);else entries.Insert(position,scheme);
        PersistSchemes(renameSchemes.State with{Schemes=entries.ToArray(),LastId=id});bool changedIdentity=currentRenameScheme!=id;
        currentRenameScheme=id;renameSchemeBaseline=scheme;fillingSchemes=true;try{RenameSchemeName.Text=name;}finally{fillingSchemes=false;}RefreshSchemeList();if(changedIdentity)RenameRulesChanged(this,new RoutedEventArgs());RenameStatus.Text=L10n.Message(L10n.Text("方案已保存；未执行重命名，未保存照片。"));
    }
    MessageBoxResult ResolveSchemeEdits() {
        if(!RenameSchemeDirty)return MessageBoxResult.No;
        var answer=MessageBox.Show(this,L10n.Text("方案有未保存规则、排序、名称或示例。是：保存；否：放弃；取消：保持整个现场。"),L10n.Text("未保存方案"),MessageBoxButton.YesNoCancel,MessageBoxImage.Question,MessageBoxResult.Cancel);
        if(answer==MessageBoxResult.Yes)SaveScheme(false);return answer;
    }
    private void RenameSchemeChanged(object sender,SelectionChangedEventArgs e) {
        if(fillingSchemes||!IsLoaded||RenameSchemeList.SelectedItem is not RenameScheme target)return;
        if(busy||renameRecoveryRequired){RefreshSchemeList();return;}
        try{if(ResolveSchemeEdits()==MessageBoxResult.Cancel){RefreshSchemeList();return;}PersistSchemes(renameSchemes!.State with{LastId=target.Id});SetSchemeEditor(target);}
        catch(Exception error){RefreshSchemeList();RenameStatus.Text=L10n.Message(L10n.Text("方案未切换，编辑保留：")+L10n.Message(error.Message));}
    }
    private void SchemeTextChanged(object sender,TextChangedEventArgs e){if(!fillingSchemes&&IsLoaded)RefreshSchemeControls();}
    private void NewRenameScheme(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||renameSchemes is null)return;
        try{if(ResolveSchemeEdits()==MessageBoxResult.Cancel)return;var example=RenamePreview.ItemsSource is System.Collections.IEnumerable rows?rows.Cast<object>().OfType<RenameFile>().FirstOrDefault()?.NewName??"":"";SetSchemeEditor(null);RenameSchemeExample.Text=example;}
        catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("未新建方案，编辑保留：")+L10n.Message(error.Message));}
    }
    private void UpdateRenameScheme(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{SaveScheme(false);}catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("方案未保存，编辑与旧库保留：")+L10n.Message(error.Message));}}
    private void SaveAsRenameScheme(object sender,RoutedEventArgs e){if(busy||renameRecoveryRequired)return;try{SaveScheme(true);}catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("方案未另存，编辑与旧库保留：")+L10n.Message(error.Message));}}
    private void RenameCurrentScheme(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||currentRenameScheme is not {} id||renameSchemes is null)return;
        try{var name=RenameSchemeLibrary.UniqueName(RenameSchemeName.Text,renameSchemes.State.Schemes,id);var changed=renameSchemes.State.Schemes.Select(s=>s.Id==id?s with{Name=name}:s).ToArray();PersistSchemes(renameSchemes.State with{Schemes=changed});renameSchemeBaseline=renameSchemeBaseline! with{Name=name};fillingSchemes=true;try{RenameSchemeName.Text=name;}finally{fillingSchemes=false;}RefreshSchemeList();}
        catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("未改名，编辑与旧库保留：")+L10n.Message(error.Message));}
    }
    private void DeleteRenameScheme(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||currentRenameScheme is not {} id||renameSchemes is null)return;
        try{var decision=ResolveSchemeEdits();if(decision==MessageBoxResult.Cancel)return;var keep=decision==MessageBoxResult.No&&RenameSchemeDirty?renameSchemeBaseline:EditedScheme(id);var remaining=renameSchemes.State.Schemes.Where(s=>s.Id!=id).ToArray();PersistSchemes(renameSchemes.State with{Schemes=remaining,LastId=remaining.FirstOrDefault()?.Id});SetSchemeEditor(keep);currentRenameScheme=null;renameSchemeBaseline=null;RefreshSchemeList();RenameStatus.Text=L10n.Message(L10n.Text("方案已删除；当前编辑规则保留为未保存方案，空库不会重建默认项。"));}
        catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("未删除方案，编辑与旧库保留：")+L10n.Message(error.Message));}
    }
    private void SaveRenamePreset(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired)return;
        try{var scheme=EditedScheme(currentRenameScheme??Guid.NewGuid());var dialog=new SaveFileDialog{Title=L10n.Text("导出重命名方案（不覆盖）"),Filter=L10n.Text("Windows v3方案|*.json|已映射Mac v1子集|*.json"),DefaultExt=".json",FileName="PhotoTrail-rename-scheme.json",OverwritePrompt=false};if(dialog.ShowDialog(this)!=true)return;var text=dialog.FilterIndex==2?MacRenamePreset.Export(scheme):RenameSchemeLibrary.Export(scheme);MetadataCsv.WriteNew(dialog.FileName,text);RenameStatus.Text=L10n.Message(L10n.Text("方案JSON已导出；计数槽当前值不传到另一端，照片和执行计划未修改。"));}
        catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("方案未导出：")+L10n.Message(error.Message));}
    }
    private void LoadRenamePreset(object sender,RoutedEventArgs e) {
        if(busy||renameRecoveryRequired||renameSchemes is null)return;
        try{var dialog=new OpenFileDialog{Title=L10n.Text("导入Windows方案／已映射Mac子集／旧规则"),Filter=L10n.Text("JSON方案或旧规则|*.json"),CheckFileExists=true};if(dialog.ShowDialog(this)!=true)return;using var file=new FileStream(dialog.FileName,FileMode.Open,FileAccess.Read,FileShare.Read);if(file.Length>RenameSchemeLibrary.MaximumBytes)throw new InvalidDataException(L10n.Text("方案超过1MiB。"));using var reader=new StreamReader(file,new UTF8Encoding(false,true),false);var imported=RenameSchemeLibrary.Import(reader.ReadToEnd(),Path.GetFileNameWithoutExtension(dialog.FileName));if(ResolveSchemeEdits()==MessageBoxResult.Cancel)return;imported=imported with{Name=RenameSchemeLibrary.UniqueName(imported.Name,renameSchemes.State.Schemes)};PersistSchemes(renameSchemes.State with{Schemes=renameSchemes.State.Schemes.Append(imported).ToArray(),LastId=imported.Id});SetSchemeEditor(imported);RenameStatus.Text=L10n.Message(L10n.Text("方案已作为独立身份完整导入；Mac仅明确映射子集，当前计数值不复制，未执行重命名。"));}
        catch(Exception error){RenameStatus.Text=L10n.Message(L10n.Text("方案未导入，编辑和旧库保留：")+L10n.Message(error.Message));}
    }
}
