using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    readonly string settingsPath=Environment.GetEnvironmentVariable("PHOTOTRAIL_SETTINGS_FILE")??SettingsPreference.DefaultPath;
    readonly string searchHistoryPath=Environment.GetEnvironmentVariable("PHOTOTRAIL_SEARCH_HISTORY_FILE")??MapSearchHistory.DefaultPath;
    SettingsPreference settings=new();
    bool restoringSettings;
    readonly Dictionary<string,string> fieldLabels=[];
    double metadataBaseFont;
    static readonly PhotoSortPreference[] sortOptions=[new("name",false),new("name",true),new("captured",false),new("captured",true),new("import",false),new("import",true)];
    void LoadSettings()
    {
        try{settings=SettingsPreference.Read(settingsPath);}catch(Exception){settings=new();SettingsStatus.Text="本机设置不可读取，使用默认值。";}
        BackupFolder.Text=settings.BackupFolder;ApplySettingsControls();
    }
    void ApplySettingsControls()
    {
        restoringSettings=true;
        try{ImportRecursive.IsChecked=settings.RecursiveImport;ImportPair.IsChecked=settings.PairImport;MetadataTextSize.SelectedIndex=settings.TextSize+1;MetadataSpacing.SelectedIndex=settings.Spacing+1;FullTagNames.IsChecked=settings.FullTagNames;RecordMapSearches.IsChecked=settings.RecordSearches;photoSort=Array.IndexOf(sortOptions,settings.PhotoSort[0]);PhotoSort.SelectedIndex=photoSort;}
        finally{restoringSettings=false;}
        RenderMetadataSettings();RefreshSearchHistory();ApplyPhotoView();RefreshInspectorSettings();RefreshInspector();
    }
    bool SaveSettings(){try{SettingsPreference.Save(settingsPath,settings);SettingsStatus.Text="设置已保存到本机；即时生效，重启恢复。";return true;}catch(Exception){SettingsStatus.Text="本次设置已生效，但未保存；请检查本机存储访问。";return false;}}
    private void MetadataSettingChanged(object sender,RoutedEventArgs e)
    {
        if(!IsLoaded||restoringSettings)return;
        settings=settings with{TextSize=MetadataTextSize.SelectedIndex-1,Spacing=MetadataSpacing.SelectedIndex-1,FullTagNames=FullTagNames.IsChecked==true,RecordSearches=RecordMapSearches.IsChecked==true};
        RenderMetadataSettings();RefreshSearchHistory();SaveSettings();
    }
    void RenderMetadataSettings()
    {
        System.Windows.Documents.TextElement.SetFontSize(Editor,metadataBaseFont+settings.FontDelta);MetadataGrid.FontSize=metadataBaseFont+settings.FontDelta;
        if(PresetControls is not null){System.Windows.Documents.TextElement.SetFontSize(PresetControls,metadataBaseFont+settings.FontDelta);MetadataPresetList.Padding=new Thickness(4,settings.RowPadding,4,settings.RowPadding);PresetValue.Padding=new Thickness(4,settings.RowPadding,4,settings.RowPadding);}
        foreach(var(tag,apply,input)in Fields){apply.FontSize=input.FontSize=metadataBaseFont+settings.FontDelta;apply.Content=fieldLabels[tag]+" · "+SettingsPreference.TagLabel(tag,settings.FullTagNames);apply.ToolTip=input.ToolTip=tag;System.Windows.Automation.AutomationProperties.SetName(apply,fieldLabels[tag]+" · "+tag);System.Windows.Automation.AutomationProperties.SetHelpText(input,tag);input.Padding=new Thickness(4,settings.RowPadding,4,settings.RowPadding);input.MinHeight=settings.MinimumRowHeight;}
        MetadataGrid.MinRowHeight=settings.MinimumRowHeight;
        MetadataGrid.Resources["M1.RowInset"]=new Thickness(8,settings.RowPadding,8,settings.RowPadding);
        MetadataGrid.Resources["M1.SourceFontSize"]=10+settings.FontDelta;
        var cells=new Style(typeof(DataGridCell));cells.Setters.Add(new Setter(Control.PaddingProperty,new Thickness(0)));MetadataGrid.CellStyle=cells;
        foreach(var column in MetadataGrid.Columns.OfType<DataGridTextColumn>()){var text=new Style(typeof(TextBlock));text.Setters.Add(new Setter(TextBlock.FontSizeProperty,metadataBaseFont+settings.FontDelta));text.Setters.Add(new Setter(TextBlock.PaddingProperty,new Thickness(4,settings.RowPadding,4,settings.RowPadding)));text.Setters.Add(new Setter(TextBlock.TextWrappingProperty,TextWrapping.Wrap));column.ElementStyle=text;}
        RefreshInspector();
    }
    private void ResetSettings(object sender,RoutedEventArgs e)
    {
        if(busy||InspectorHasInput()){SettingsStatus.Text="请先结束任务或将输入加入草稿，再恢复默认设置。";return;}
        settings=new();var saved=SaveSettings();ApplySettingsControls();SettingsStatus.Text=saved?"显示、排序及记录开关已恢复默认；历史内容、密钥、地图提供方和外观不变。":"默认设置已在本次会话生效，但未保存；历史及其他数据保留。";
    }
    private void ClearSearchHistory(object sender,RoutedEventArgs e){try{MapSearchHistory.Clear(searchHistoryPath);RefreshSearchHistory();SearchHistoryStatus.Text="最近搜索记录已清除；当前查询及其他数据保留。";}catch(Exception){SearchHistoryStatus.Text="历史未清除，请检查本机存储访问。";}}
    void RefreshSearchHistory()
    {
        try{var terms=MapSearchHistory.Read(searchHistoryPath);RecentMapSearches.ItemsSource=settings.RecordSearches?terms:Array.Empty<string>();RecentMapSearches.Visibility=settings.RecordSearches&&terms.Length>0?Visibility.Visible:Visibility.Collapsed;ClearSearchHistoryButton.IsEnabled=terms.Length>0;}
        catch(Exception){RecentMapSearches.ItemsSource=Array.Empty<string>();RecentMapSearches.Visibility=Visibility.Collapsed;SearchHistoryStatus.Text="搜索历史不可读取，已有文件未覆盖。";ClearSearchHistoryButton.IsEnabled=true;}
    }
    private void UseRecentMapSearch(object sender,RoutedEventArgs e){if(RecentMapSearches.SelectedItem is string term){MapSearchQuery.Text=term;MapSearchQuery.Focus();try{MapSearchHistory.Remember(searchHistoryPath,term,settings.RecordSearches);RefreshSearchHistory();}catch(Exception){SearchHistoryStatus.Text="词条已填入，历史顺序未保存；已有记录保持。";}}}
    private void MetadataFilterChanged(object sender,TextChangedEventArgs e)
    {
        RefreshInspector();
    }
    private void CopyMetadataTag(object sender,RoutedEventArgs e){try{if(MetadataGrid.SelectedItem is InspectorRow row)Clipboard.SetText(row.Tag);}catch(Exception){Status.Text="完整标签未复制；剪贴板暂不可用，草稿保留。";}}
    private void CopyMetadataRow(object sender,DataGridRowClipboardEventArgs e){if(e.Item is InspectorRow row)for(int i=0;i<e.ClipboardRowContent.Count;i++)if(e.ClipboardRowContent[i].Column==MetadataGrid.Columns[0])e.ClipboardRowContent[i]=new DataGridClipboardCellContent(row,MetadataGrid.Columns[0],row.Tag);}
    sealed class PhotoDateComparer(SettingsPreference preference):System.Collections.IComparer
    {
        public int Compare(object? x,object? y) {
            var a=(PhotoRow)x!;var b=(PhotoRow)y!;
            foreach(var sort in preference.PhotoSort) {
                int value;
                if(sort.Field=="captured") {
                    var first=a.Captured;var second=b.Captured;
                    if(first is null || second is null) { if(first is null && second is null)continue;return first is null?1:-1; }
                    value=first.Value.CompareTo(second.Value);
                }else value=sort.Field=="name"?StringComparer.CurrentCulture.Compare(a.Name,b.Name):a.Imported.CompareTo(b.Imported);
                if(value!=0)return sort.Descending?-value:value;
            }
            return a.Imported.CompareTo(b.Imported);
        }
    }
    void ApplyPhotoView()
    {
        var selected=Selected;var view=CollectionViewSource.GetDefaultView(photos);fillingEditor=true;
        try{
            using(view.DeferRefresh()){
                view.GroupDescriptions.Clear();view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(PhotoRow.DisplayGroup)));
                view.Filter=item=>item is PhotoRow row&&row.Name.Contains(photoSearch,StringComparison.OrdinalIgnoreCase)&&(photoFilter switch{1=>row.Document.Draft.Count>0,2=>row.Document.Draft.Count==0,3=>row.Document.Position()is not null,4=>row.Document.Position()is null,_=>true});
                if(view is ListCollectionView previous)previous.CustomSort=null;
                view.SortDescriptions.Clear();foreach(var sort in settings.PhotoSort)view.SortDescriptions.Add(new(sort.Field switch{"name"=>nameof(PhotoRow.Name),"captured"=>nameof(PhotoRow.Captured),_=>nameof(PhotoRow.Imported)},sort.Descending?ListSortDirection.Descending:ListSortDirection.Ascending));
                if(!settings.PhotoSort.Any(s=>s.Field=="import"))view.SortDescriptions.Add(new(nameof(PhotoRow.Imported),ListSortDirection.Ascending));
                if(view is ListCollectionView list&&settings.PhotoSort.Any(s=>s.Field=="captured"))list.CustomSort=new PhotoDateComparer(settings);
            }
            Photos.SelectedItems.Clear();foreach(var row in selected)if(Photos.Items.Contains(row))Photos.SelectedItems.Add(row);
        }finally{fillingEditor=false;}
        if(!Selected.SequenceEqual(selected)){InvalidateDates();previousSelection=Selected;RenameRulesChanged(this,new RoutedEventArgs());}
        PhotoSortStatus.Text="当前比较器序列："+string.Join(" → ",settings.PhotoSort.Select(s=>s.Field+(s.Descending?" ↓":" ↑")));
        SyncPhotoStrip();if(IsLoaded)RefreshSelection();
    }
}
