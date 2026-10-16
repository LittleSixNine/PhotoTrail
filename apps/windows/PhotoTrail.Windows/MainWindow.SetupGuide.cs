using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    Window? setupWindow;
    void ShowSetupGuide(bool firstRun){
        if(busy||renameRecoveryRequired)return;if(setupWindow is not null){setupWindow.Activate();return;}
        int page=0,mapNext=0;string chosen=ui.Language;var body=new DockPanel{Margin=new(24)};var footer=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Right};DockPanel.SetDock(footer,Dock.Bottom);body.Children.Add(footer);var content=new StackPanel();body.Children.Add(new ScrollViewer{Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});
        var dialog=M3Dialog(L10n.Text("打开启动设置向导"),body,660,580);dialog.Owner=settingsWindow??this;setupWindow=dialog;AutomationProperties.SetAutomationId(dialog,"M5SetupGuide");
        void Render(){content.Children.Clear();footer.Children.Clear();string T(string key)=>L10n.Text(key,chosen);content.Children.Add(PreferenceText("PhotoTrail",true));content.Children.Add(new TextBlock{Text=T("第 {0} 步，共 4 步").Replace("{0}",(page+1).ToString()),Margin=new(2,4,2,12)});var title=new TextBlock{Text=T(new[]{"选择语言","保护原始照片","选择地图服务","准备开始"}[page]),FontSize=26,FontWeight=FontWeights.SemiBold,TextWrapping=TextWrapping.Wrap,Margin=new(2,4,2,18)};AutomationProperties.SetAutomationId(title,"M5SetupTitle");content.Children.Add(title);
            void Explain(string key)=>content.Children.Add(new TextBlock{Text=T(key),TextWrapping=TextWrapping.Wrap,Margin=new(2,8,2,12)});
            if(page==0){var language=PreferenceChoice("M5SetupLanguage",L10n.LanguageNames,Math.Max(0,Array.IndexOf(L10n.Languages,chosen)),i=>{if(i>=0)chosen=L10n.Languages[i];});content.Children.Add(language);Explain("选择应用语言；完成后保存工作并重新打开，使所有窗口采用新语言。");}
            else if(page==1){Explain("默认保存为副本，原始照片保持不变。原位保存必须先设置备份目录并核对摘要，不能关闭备份。");Explain("副本保存后会话草稿仍保留；撤销只改变会话，不删除已保存文件。");}
            else if(page==2){Explain("默认 OpenFreeMap（WGS-84），无需密钥。Google 可在地图设置中明确配置和选择；服务许可与凭据保护保留。");content.Children.Add(PreferenceChoice("M5SetupMapChoice",new[]{T("保留当前地图配置"),T("完成后打开地图设置（不自动启用Google）")},mapNext,i=>{if(i>=0)mapNext=i;}));Explain("向导不改现有地图配置；选择配置Google仅在完成后打开设置，不保存密钥或请求服务。");Explain("地图点选和拖动仅预览；明确采用后进入草稿，不自动写文件。");}
            else{Explain("设置已就绪，可以编辑照片信息、添加地点或整理文件名。");Explain("导入照片 → 选择功能 → 检查结果");Explain("元数据和定位修改统一手动保存；重命名在确认执行后改名。三个页签可独立使用。");Explain("Windows 开发候选；没有自动更新安装器。");}
            void Add(string key,string id,Action run){var b=new Button{Content=T(key),IsCancel=id=="M5SetupCancel",IsDefault=id is "M5SetupNext" or "M5SetupFinish",Margin=new(4),Padding=new(12,7,12,7)};AutomationProperties.SetAutomationId(b,id);b.Click+=(_,_)=>run();footer.Children.Add(b);}
            Add("取消","M5SetupCancel",()=>dialog.Close());if(page>0)Add("上一步","M5SetupBack",()=>{page--;Render();});if(page<3)Add("下一步","M5SetupNext",()=>{page++;Render();});else Add("开始使用","M5SetupFinish",()=>{if(SaveUi(ui with{Language=chosen,SetupCompleted=true})){dialog.Close();if(languageChoice is not null){uiRestoring=true;languageChoice.SelectedIndex=Array.IndexOf(L10n.Languages,chosen);uiRestoring=false;}if(mapNext==1){M1OpenSettings(this,new RoutedEventArgs());SettingsPages.SelectedIndex=1;}}});
        }
        Render();dialog.Closed+=(_,_)=>{setupWindow=null;(settingsWindow??this).Activate();};dialog.ShowDialog();
    }
}
