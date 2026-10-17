using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    static readonly JsonElement[] deviceBrands=ReadDeviceBrands();
    static JsonElement[] ReadDeviceBrands(){
        using var stream=typeof(MainWindow).Assembly.GetManifestResourceStream("PhotoTrail.Windows.Resources.MetadataDevices.json")!;
        using var data=JsonDocument.Parse(stream);return data.RootElement.GetProperty("brands").EnumerateArray().Select(b=>b.Clone()).ToArray();
    }
    static bool ProductOnly(JsonElement device)=>device.TryGetProperty("productNameOnly",out var only)&&only.ValueKind==JsonValueKind.True;
    static void AddDevicePicker(Panel panel,string tag,TextBox value){
        bool model=tag is "XMP-tiff:Model" or "IFD0:Model";
        var brands=deviceBrands.Where(b=>model||b.GetProperty("models").EnumerateArray().Any(d=>!ProductOnly(d))).ToArray();
        var brand=new ComboBox{ItemsSource=brands.Select(b=>b.GetProperty("name").GetString()).ToArray(),Margin=new(0,4,0,5)};
        var search=new TextBox{Margin=new(0,4,0,5),MaxLength=256};
        var choices=new ComboBox{Margin=new(0,4,0,5),MaxDropDownHeight=320,IsTextSearchEnabled=false,DisplayMemberPath="Label",SelectedValuePath="Value"};
        AutomationProperties.SetAutomationId(brand,"MetadataDeviceBrand");AutomationProperties.SetName(brand,L10n.Text("设备品牌"));
        AutomationProperties.SetAutomationId(search,"MetadataDeviceSearch");AutomationProperties.SetName(search,L10n.Text("搜索机型或型号编号"));
        AutomationProperties.SetAutomationId(choices,"MetadataDeviceModel");AutomationProperties.SetName(choices,L10n.Text("设备型号"));
        foreach(var pair in new[]{(L10n.Text("设备品牌"),(UIElement)brand),(L10n.Text("搜索机型或型号编号"),(UIElement)search),(L10n.Text("设备型号"),(UIElement)choices)}){panel.Children.Add(new TextBlock{Text=pair.Item1,TextWrapping=TextWrapping.Wrap});panel.Children.Add(pair.Item2);}
        void Refresh(){
            var items=new List<DeviceChoice>();
            if(brand.SelectedIndex>=0)foreach(var d in brands[brand.SelectedIndex].GetProperty("models").EnumerateArray()){
                if(!model&&ProductOnly(d))continue;
                string name=d.GetProperty("name").GetString()!,make=d.GetProperty("make").GetString()!,code=d.GetProperty("model").GetString()!;
                if(!new[]{name,make,code}.Any(t=>t.Contains(search.Text,StringComparison.CurrentCultureIgnoreCase)))continue;
                if(model){items.Add(new(name, name));if(!ProductOnly(d)&&name!=code)items.Add(new(code,code));}
                else items.Add(new(name+" → "+make,make));
            }
            choices.ItemsSource=items.Distinct().ToArray();
        }
        brand.SelectionChanged+=(_,_)=>{search.Text="";Refresh();if(!model&&brand.SelectedIndex>=0)value.Text=brands[brand.SelectedIndex].GetProperty("models").EnumerateArray().First(d=>!ProductOnly(d)).GetProperty("make").GetString()!;};
        search.TextChanged+=(_,_)=>Refresh();choices.SelectionChanged+=(_,_)=>{if(choices.SelectedItem is DeviceChoice selected)value.Text=selected.Value;};
        for(int i=0;i<brands.Length;i++)if(brands[i].GetProperty("models").EnumerateArray().Any(d=>model?d.GetProperty("name").GetString()==value.Text||!ProductOnly(d)&&d.GetProperty("model").GetString()==value.Text:!ProductOnly(d)&&d.GetProperty("make").GetString()==value.Text)){brand.SelectedIndex=i;break;}
    }
    static void AddFlashPicker(Panel panel,TextBox value){
        var labels=new[]{"未闪光","已闪光","强制开启并闪光","关闭且未闪光","自动，未闪光","自动，已闪光","无闪光灯","已闪光，防红眼"};
        var choices=new[]{0,1,9,16,24,25,32,65}.Select((n,i)=>new DeviceChoice(n+" · "+L10n.Text(labels[i]),n.ToString(System.Globalization.CultureInfo.InvariantCulture))).ToArray();
        var picker=new ComboBox{ItemsSource=choices,DisplayMemberPath="Label",SelectedValuePath="Value",SelectedValue=value.Text,Margin=new(0,4,0,5)};
        AutomationProperties.SetAutomationId(picker,"MetadataFlashPreset");AutomationProperties.SetName(picker,L10n.Text("常用状态"));
        picker.SelectionChanged+=(_,_)=>{if(picker.SelectedItem is DeviceChoice selected)value.Text=selected.Value;};
        value.TextChanged+=(_,_)=>picker.SelectedValue=value.Text;panel.Children.Add(picker);
    }
    sealed record DeviceChoice(string Label,string Value);
}
