using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Text.Json;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    private string placeQuery="";
    private void MapSearchQueryChanged(object sender,TextChangedEventArgs e){if(placeQuery.Length>0)ClearPlacePreview();}
    private void MapSearchKeyDown(object sender,KeyEventArgs e){if(e.Key==Key.Enter){SearchPlace(sender,e);e.Handled=true;}}
    private async void SearchPlace(object sender,RoutedEventArgs e)
    {
        if(busy||!mapReady||currentMapPage!=MapMessage.GooglePage){PlacePreview.Text=L10n.Text("请先在地图设置明确选择Google地图；文字查询使用已有Geocoding路径。");return;}
        var query=MapSearchQuery.Text.Trim();if(query.Length==0)return;
        if(query.Length>256||query.Any(char.IsControl)){PlacePreview.Text=L10n.Text("搜索词含无效字符。");return;}
        try{MapSearchHistory.Remember(searchHistoryPath,query,settings.RecordSearches);RefreshSearchHistory();}catch(Exception){SearchHistoryStatus.Text=L10n.Message(L10n.Text("查询继续，但搜索历史未保存；已有记录保持。"));}
        var id=++placeRequest;placeQuery=query;placePending=true;PlacePreview.Text=L10n.Text("正在向Google Maps查询地点…");
        MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new{type="geocode",id,query}));
        await Task.Delay(TimeSpan.FromSeconds(20));
        if(id==placeRequest&&placePending){placeRequest++;placePending=false;PlacePreview.Text=L10n.Text("Google Maps查询超时，未改照片。");}
    }
}
