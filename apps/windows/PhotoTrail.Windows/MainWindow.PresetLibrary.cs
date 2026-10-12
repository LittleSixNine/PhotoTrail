using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
namespace PhotoTrail.Windows;
public partial class MainWindow
{
    MetadataPresetLibrarySnapshot? metadataPresets;
    Guid? currentMetadataPreset;
    MetadataPreset? metadataPresetBaseline;
    bool fillingPresetLibrary;
    string presetLibraryError="";
    bool PresetChainDirty=>metadataPresetBaseline is null ? presetOperations.Count>0 : PresetName.Text!=metadataPresetBaseline.Name || !presetOperations.SequenceEqual(metadataPresetBaseline.Operations);
    MetadataPresetEntry SelectedSavedPreset()=>MetadataPresetList.SelectedItem as MetadataPresetEntry ?? throw new InvalidOperationException("请选择已保存预设。");
    void RefreshPresetLibraryControls(){
        if(PresetLibraryStatus is null || fillingPreset)return;
        bool available=!busy&&!renameRecoveryRequired&&metadataPresets is not null;
        PresetLibraryActions.IsEnabled=available; MetadataPresetList.IsEnabled=available;
        UpdateMetadataPresetButton.IsEnabled=available&&currentMetadataPreset is not null;
        PresetLibraryStatus.Text=presetLibraryError.Length>0?presetLibraryError:$"库中 {metadataPresets?.Entries.Count??0} 项；当前 {(currentMetadataPreset is null?"未保存预设":"已保存预设")}{(PresetChainDirty?" · 有未保存修改":"")}{(presetEditorDirty?" · 有未编排参数":"")} · {presetOperations.Count} 条操作。管理不会应用照片。";
    }
    void RefreshPresetList(){fillingPresetLibrary=true;try{MetadataPresetList.ItemsSource=metadataPresets?.Entries;MetadataPresetList.SelectedItem=metadataPresets?.Entries.FirstOrDefault(e=>e.Id==currentMetadataPreset);}finally{fillingPresetLibrary=false;}RefreshPresetLibraryControls();}
    void LoadMetadataPresets(){try{metadataPresets=MetadataPresetLibrary.Open(MetadataPresetLibrary.DefaultPath);presetLibraryError="";}catch(Exception error){metadataPresets=null;presetLibraryError="库未载入，原件保留："+error.Message;}RefreshPresetList();}
    void LibraryAction(Action action){if(busy||renameRecoveryRequired)return;try{action();}catch(Exception error){presetLibraryError="库操作未完成；编辑及照片草稿保留："+error.Message;}RefreshPresetLibraryControls();}
    void PersistPresets(IReadOnlyList<MetadataPresetEntry> next){var saved=MetadataPresetLibrary.Save(MetadataPresetLibrary.DefaultPath,metadataPresets??throw new InvalidOperationException("库未成功载入，请先重新读取。"),next);metadataPresets=saved;presetLibraryError="";}
    MetadataPreset ReadEditedPreset(){RequirePresetInputSaved();return MetadataPreset.Create(PresetName.Text,presetOperations);}
    void SetLibraryPreset(MetadataPresetEntry saved){currentMetadataPreset=saved.Id;metadataPresetBaseline=saved.Preset;SetPresetChain(saved.Preset);RefreshPresetList();}
    void SetUnsavedPreset(MetadataPreset preset){currentMetadataPreset=null;metadataPresetBaseline=null;SetPresetChain(preset);RefreshPresetList();}
    void SaveNewPreset(){var preset=ReadEditedPreset();var entry=new MetadataPresetEntry(Guid.NewGuid(),preset);PersistPresets(metadataPresets!.Entries.Append(entry).ToArray());SetLibraryPreset(entry);}
    void UpdateCurrentPreset(){var preset=ReadEditedPreset();var id=currentMetadataPreset??throw new InvalidOperationException("未选择已保存项，不能更新。");var next=metadataPresets!.Entries.ToArray();int index=Array.FindIndex(next,e=>e.Id==id);if(index<0)throw new InvalidOperationException("当前条目已不存在，请重新读取。");var entry=new MetadataPresetEntry(id,preset);next[index]=entry;PersistPresets(next);SetLibraryPreset(entry);}
    bool ResolvePresetChainEdits(){RequirePresetInputSaved();if(!PresetChainDirty)return true;var choice=MessageBox.Show(this,"当前预设链尚未保存入库。是：保存；否：放弃预设编辑；取消：继续编辑。照片草稿保留。","未保存预设链",MessageBoxButton.YesNoCancel,MessageBoxImage.Question,MessageBoxResult.Cancel);if(choice==MessageBoxResult.Cancel)return false;if(choice==MessageBoxResult.Yes){if(currentMetadataPreset is null)SaveNewPreset();else UpdateCurrentPreset();}return true;}
    void SavedPresetSelected(object sender,SelectionChangedEventArgs e){if(fillingPresetLibrary||!IsLoaded||MetadataPresetList.SelectedItem is not MetadataPresetEntry target)return;LibraryAction(()=>{if(ResolvePresetChainEdits())SetLibraryPreset(metadataPresets!.Entries.First(x=>x.Id==target.Id));else RefreshPresetList();});if(currentMetadataPreset!=target.Id)RefreshPresetList();}
    void NewMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{if(!ResolvePresetChainEdits())return;currentMetadataPreset=null;metadataPresetBaseline=null;fillingPreset=true;try{PresetName.Text="新预设";presetOperations.Clear();PresetOperations.SelectedIndex=-1;presetEditingIndex=-1;}finally{fillingPreset=false;}FillPresetOperation(new(MetadataCsv.Tags[0],"replaceAuthors",""));InvalidateDates();RefreshPresetList();});
    void SaveNewMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(SaveNewPreset);
    void UpdateMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(UpdateCurrentPreset);
    void CopyMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{var source=SelectedSavedPreset();var copy=new MetadataPresetEntry(Guid.NewGuid(),MetadataPreset.Create(MetadataPresetLibrary.UniqueName(source.Preset.Name,metadataPresets!.Entries,true),source.Preset.Operations));PersistPresets(metadataPresets.Entries.Append(copy).ToArray());RefreshPresetList();});
    void RenameMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{var source=SelectedSavedPreset();string name=MetadataPresetLibrary.Name(PresetLibraryRenameName.Text);var renamed=new MetadataPresetEntry(source.Id,MetadataPreset.Create(name,source.Preset.Operations));bool dirty=PresetChainDirty;PersistPresets(metadataPresets!.Entries.Select(x=>x.Id==source.Id?renamed:x).ToArray());if(currentMetadataPreset==source.Id){metadataPresetBaseline=renamed.Preset;if(!dirty){fillingPreset=true;try{PresetName.Text=name;}finally{fillingPreset=false;}}}RefreshPresetList();});
    void DeleteMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{var source=SelectedSavedPreset();if(MessageBox.Show(this,$"仅删除库中“{source.Preset.Name}”？当前编辑链和照片草稿保留。","删除已保存预设",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)!=MessageBoxResult.Yes)return;PersistPresets(metadataPresets!.Entries.Where(x=>x.Id!=source.Id).ToArray());if(currentMetadataPreset==source.Id){currentMetadataPreset=null;metadataPresetBaseline=null;}RefreshPresetList();});
    static MetadataPreset ReadPresetFile(string path){using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);if(file.Length>MetadataPreset.MaximumBytes)throw new InvalidDataException("预设超过128KiB上限。");using var reader=new StreamReader(file,new UTF8Encoding(false,true),false);return MetadataPreset.Decode(reader.ReadToEnd());}
    void ImportMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{var dialog=new OpenFileDialog{Title="导入单条元数据预设到本机库",Filter="JSON预设|*.json",CheckFileExists=true};if(dialog.ShowDialog(this)!=true)return;var preset=ReadPresetFile(dialog.FileName);if(!ResolvePresetChainEdits())return;var imported=new MetadataPresetEntry(Guid.NewGuid(),MetadataPreset.Create(MetadataPresetLibrary.UniqueName(preset.Name,metadataPresets!.Entries),preset.Operations));PersistPresets(metadataPresets.Entries.Append(imported).ToArray());SetLibraryPreset(imported);});
    void ExportMetadataPreset(object sender,RoutedEventArgs e)=>LibraryAction(()=>{var source=SelectedSavedPreset();var text=source.Preset.Encode();var dialog=new SaveFileDialog{Title="导出已保存预设（不覆盖）",Filter="JSON预设|*.json",DefaultExt=".json",FileName="PhotoTrail-saved-preset.json",OverwritePrompt=false};if(dialog.ShowDialog(this)!=true)return;MetadataCsv.WriteNew(dialog.FileName,text);Status.Text="已导出列表中的保存版本，未保存编辑和照片草稿保留。";});
    void ReloadMetadataPresets(object sender,RoutedEventArgs e)=>LibraryAction(()=>{if(!ResolvePresetChainEdits())return;var reloaded=MetadataPresetLibrary.Open(MetadataPresetLibrary.DefaultPath);var current=reloaded.Entries.FirstOrDefault(x=>x.Id==currentMetadataPreset);metadataPresets=reloaded;presetLibraryError="";if(current is not null)SetLibraryPreset(current);else{currentMetadataPreset=null;metadataPresetBaseline=null;fillingPreset=true;try{presetOperations.Clear();PresetName.Text="新预设";PresetOperations.SelectedIndex=-1;}finally{fillingPreset=false;}FillPresetOperation(new(MetadataCsv.Tags[0],"replaceAuthors",""));RefreshPresetList();}InvalidateDates();});
}
