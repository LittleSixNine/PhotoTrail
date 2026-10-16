using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    string sessionCameraZone=TimeZoneInfo.Local.Id;
    SaveScope MainSaveScope=>!ui.SaveCurrentPage||WorkspaceTabs.SelectedIndex==2?SaveScope.All:WorkspaceTabs.SelectedIndex==1?SaveScope.Map:SaveScope.Metadata;
    bool M9HasPending(SaveScope scope)=>photos.Any(r=>r.Document.Draft.Keys.Any(t=>scope==SaveScope.All||r.Document.IsMapDraft(t)==(scope==SaveScope.Map)));
    void M9RefreshSave(){
        SaveButton.Content=L10n.Text(MainSaveScope==SaveScope.All?(ChosenSaveMode==SaveMode.Copy?"保存全部副本":"保存全部元数据"):(ChosenSaveMode==SaveMode.Copy?"保存本页副本":"保存本页元数据"));
        AutomationProperties.SetName(SaveButton,L10n.Text("保存待保存修改 · Ctrl+S；先核对冻结摘要"));SaveButton.ToolTip=L10n.Text("保存待保存修改 · Ctrl+S；先核对冻结摘要");
        SaveButton.IsEnabled=!busy&&!renameRecoveryRequired&&M9HasPending(MainSaveScope);
    }
    void M9SetSaveScope(bool current){if(!SaveUi(ui with{SaveCurrentPage=current}))return;preparedSave=null;ExecuteSaveButton.IsEnabled=false;M9RefreshSave();}
    void M9RequestSave(bool forceAll=false){
        if(busy||renameRecoveryRequired)return;
        if(InspectorHasInput()){Status.Text=L10n.Text("保存准备被阻止：有未应用输入，请明确加入草稿；不会隐式保存。");return;}
        var scope=forceAll?SaveScope.All:MainSaveScope;if(!M9HasPending(scope)){Status.Text=L10n.Text("本范围没有待保存修改。");return;}
        if(scope==SaveScope.All&&!forceAll&&!ui.SkipSaveScopePrompt&&M9ConfirmSaveScope()!=1)return;
        PrepareSave(photos.Select(r=>r.Document),ChosenSaveMode,scope);
    }
    int M9ConfirmSaveScope(){
        int answer=0;var panel=new DockPanel{Margin=new(14)};var buttons=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Right};DockPanel.SetDock(buttons,Dock.Bottom);panel.Children.Add(buttons);
        var content=new StackPanel();panel.Children.Add(new ScrollViewer{Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});
        content.Children.Add(PreferenceText("保存元数据编辑和地图定位两个页面的全部待保存修改，不限当前选择、搜索或筛选。"));
        content.Children.Add(PreferenceText("默认副本保留会话草稿；下一步仍须核对冻结摘要并明确执行。"));
        var skip=new CheckBox{Content=L10n.Text("下次不再提示范围"),Margin=new(2,10,2,10)};content.Children.Add(skip);
        var dialog=M3Dialog(L10n.Text("确认保存范围"),panel,650,350);
        void Add(string text,string id,int result){var button=new Button{Content=L10n.Text(text),Margin=new(4),Padding=new(10,6,10,6)};AutomationProperties.SetName(button,L10n.Text(text));AutomationProperties.SetAutomationId(button,id);button.Click+=(_,_)=>{answer=result;if(result==1&&skip.IsChecked==true)SaveUi(ui with{SkipSaveScopePrompt=true});if(result==2)M9SetSaveScope(true);dialog.Close();};buttons.Children.Add(button);}
        Add("继续核对保存摘要","M9ScopeContinue",1);Add("取消","M9ScopeCancel",0);Add("改为仅保存本页","M9ScopeCurrent",2);
        dialog.ContentRendered+=(_,_)=>buttons.Children.OfType<Button>().ElementAt(1).Focus();dialog.ShowDialog();return answer;
    }
    void M9OpenSessionZone(object sender,RoutedEventArgs e){
        if(busy||renameRecoveryRequired)return;
        var panel=new StackPanel{Margin=new(14)};panel.Children.Add(PreferenceText("当前批次相机时区"));panel.Children.Add(PreferenceText(sessionCameraZone));
        var zones=TimeZoneInfo.GetSystemTimeZones().Select(z=>z.Id).Append(sessionCameraZone).Distinct(StringComparer.Ordinal).ToArray();
        var choice=new ComboBox{ItemsSource=zones,SelectedIndex=Array.IndexOf(zones,sessionCameraZone),Margin=new(2,10,2,10)};AutomationProperties.SetName(choice,L10n.Text("当前批次相机时区"));AutomationProperties.SetAutomationId(choice,"M9SessionZone");panel.Children.Add(choice);
        panel.Children.Add(PreferenceText("仅解释当前批次无偏移时间，不改原始值、草稿或新会话默认设置。重复／不存在时间将阻止匹配和GPX导出。"));
        var apply=new Button{Content=L10n.Text("应用当前批次时区"),Margin=new(2,12,2,8)};AutomationProperties.SetAutomationId(apply,"M9ApplySessionZone");panel.Children.Add(apply);
        var dialog=M3Dialog(L10n.Text("当前批次相机时区"),new ScrollViewer{Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto},600,380);
        apply.Click+=(_,_)=>{if(InspectorHasInput()||dateEditorWindow is not null){Status.Text=L10n.Text("请先应用或取消编辑输入，再调整当前批次时区。");return;}if(choice.SelectedItem is not string id)return;M9SetSessionZone(id);dialog.Close();};dialog.ShowDialog();
    }
    void M9SetSessionZone(string id){
        _=TimeZoneInfo.FindSystemTimeZoneById(id);sessionCameraZone=id;SessionTime.InitialZone=id;MetadataInspector.DisplayTimeZone=TimeZoneInfo.FindSystemTimeZoneById(id);
        foreach(var row in photos)row.Document.SetSessionZone(id);
        InvalidateBatchTrack();InvalidateDates();PhotoGpxInputChanged(this,new RoutedEventArgs());preparedSave=null;ExecuteSaveButton.IsEnabled=false;RenameRulesChanged(this,new RoutedEventArgs());RefreshSelection();RefreshMatchTime();
        Status.Text=L10n.Text("当前批次时区已调整；原始值和草稿未改，旧计算结果已失效。");
    }
    private async void M9ClearLocation(object sender,RoutedEventArgs e){
        if(busy||renameRecoveryRequired||Selected.Length==0)return;
        if(MessageBox.Show(this,L10n.Text("保留照片和列表项目，清除坐标、海拔、GPS基准／处理方式及关联地区；保存才写文件，可一次撤销。"),L10n.Text("清除照片定位？"),MessageBoxButton.OKCancel,MessageBoxImage.Warning,MessageBoxResult.Cancel)!=MessageBoxResult.OK)return;
        try{if(InspectorHasInput())throw new InvalidOperationException(L10n.Text("先处理未应用字段输入。"));
            await ApplyMetadataBatch("清除定位",(docs,_,token)=>{foreach(var doc in docs){token.ThrowIfCancellationRequested();doc.StageLocationClear();}return Task.FromResult(new BatchDetails());},()=>!InspectorHasInput());
            ClearMatchMarker();ClearPlacePreview();InvalidateBatchTrack();PhotoGpxInputChanged(this,new RoutedEventArgs());_ = PostPhotosAsync();
        }catch(Exception error){Status.Text=L10n.Message(error.Message);}
    }
    void M9MapEdit(string source,string json){
        if(source!=MapMessage.Page||busy||renameRecoveryRequired||!mapReady)return;
        if(!MapMessage.TryEdit(source,json,mapPhotoRevision,mapViewEpoch,ui.DoubleClickEdit,ui.DragPinEdit))return;
        if(InspectorHasInput()){Status.Text=L10n.Text("先处理未应用字段输入。");return;}
        AddGpsDraft(this,new RoutedEventArgs());
    }
}
