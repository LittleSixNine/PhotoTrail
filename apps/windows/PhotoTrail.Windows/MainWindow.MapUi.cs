using System.Globalization;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    Grid? m4Columns,m4Rows;
    ScrollViewer? m4Sidebar;
    StackPanel? m4Commands;
    WrapPanel? m4Toolbar;
    TextBlock? m4Selection,m4Position,m4GpsSummary;
    PhotoThumbnail? m4Preview;
    Button? m4Toggle,m4Layer,m4Undo,m4GpsCopy,m4StripToggle,m4Tools;
    WrapPanel? m4LayerBar;
    bool? m4StripChoice;
    GridLength m4StripHeight=new(132);
    GridSplitter? m4Vertical,m4Horizontal;
    bool m4Hidden,m4Ready;
    ComboBox? m4Filter,m4Sort;
    string M4(string key)=>TryFindResource("M4."+key) as string??key;
    string M4Format(string key,params object[] values)=>string.Format(CultureInfo.CurrentCulture,M4(key),values);
    Button M4Button(string key,RoutedEventHandler action){var button=new Button{Content=M4(key),Margin=new(2),Padding=new(7,5,7,5)};AutomationProperties.SetName(button,M4(key));AutomationProperties.SetAutomationId(button,"M4"+key);button.Click+=action;return button;}
    static void M4Text(Panel panel,string value,bool heading=false){panel.Children.Add(new TextBlock{Text=value,TextWrapping=TextWrapping.Wrap,FontSize=heading?16:12,FontWeight=heading?FontWeights.SemiBold:FontWeights.Normal,Margin=new(2,8,2,5)});}
    void InitializeM4Map(){
        if(m4Ready)return;m4Ready=true;
        m4Rows=M4MapWorkspace;m4Rows.RowDefinitions.Add(new(){Height=new(1,GridUnitType.Star)});m4Rows.RowDefinitions.Add(new(){Height=new(6)});m4Rows.RowDefinitions.Add(new(){Height=new(132),MinHeight=132});
        m4Columns=new Grid();m4Columns.ColumnDefinitions.Add(new(){Width=new(300),MinWidth=260});m4Columns.ColumnDefinitions.Add(new(){Width=new(6)});m4Columns.ColumnDefinitions.Add(new(){Width=new(1,GridUnitType.Star),MinWidth=420});m4Rows.Children.Add(m4Columns);
        var side=new StackPanel{Margin=new(10,0,10,6)};m4Sidebar=new ScrollViewer{Content=side,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};m4Columns.Children.Add(m4Sidebar);
        M4Text(side,M4("Title"),true);m4Preview=new PhotoThumbnail{Strip=true,Height=200,Margin=new(2,8,2,8)};AutomationProperties.SetName(m4Preview,M4("Title"));side.Children.Add(m4Preview);
        m4Selection=new TextBlock{TextWrapping=TextWrapping.Wrap,FontWeight=FontWeights.SemiBold,Margin=new(2,4,2,4)};side.Children.Add(m4Selection);m4Position=new TextBlock{TextWrapping=TextWrapping.Wrap,Margin=new(2,3,2,6)};side.Children.Add(m4Position);m4GpsSummary=new TextBlock{TextWrapping=TextWrapping.Wrap,Margin=new(2,3,2,6)};side.Children.Add(m4GpsSummary);
        m4Commands=new StackPanel();side.Children.Add(m4Commands);m4Commands.Children.Add(M4Button("Location",(_,_)=>M4Location()));m4Commands.Children.Add(M4Button("Region",(_,_)=>M4Borrow("Region",[M4ManualRegion],650,600)));M4Text(m4Commands,M4("RegionLimit"));
        var favorite=new StackPanel();var favorites=new Expander{Header=M4("Favorites"),IsExpanded=true,Content=favorite,Margin=new(0,10,0,10)};side.Children.Add(favorites);FavoriteList.Width=double.NaN;FavoriteList.MaxHeight=180;M3Move(favorite,FavoriteList);M3Move(favorite,FavoritesExpanded);favorite.Children.Add(M4Button("FavoriteEdit",(_,_)=>M4FavoriteEditor()));M4Text(favorite,M4("FavoriteNotice"));
        var trackPanel=new StackPanel();var trackSection=new Expander{Header=M4("Tracks"),Content=trackPanel,IsExpanded=true};side.Children.Add(trackSection);M3Move(trackPanel,TrackReadButton);M3Move(trackPanel,TrackDisplayRows);TrackDisplayRows.MaxHeight=300;TrackDisplayRows.HorizontalContentAlignment=HorizontalAlignment.Stretch;ScrollViewer.SetHorizontalScrollBarVisibility(TrackDisplayRows,ScrollBarVisibility.Disabled);TrackDisplayRows.SetBinding(Selector.SelectedItemProperty,new Binding("SelectedItem"){Source=TrackList,Mode=BindingMode.TwoWay});
        M3Move(trackPanel,TrackInfo);M4Text(trackPanel,M4("TrackNotice"));trackPanel.Children.Add(M4Button("TimeSelect",M4SelectTrackTimes));trackPanel.Children.Add(M4Button("Match",(_,_)=>M4OpenMatching()));trackPanel.Children.Add(M4Button("TrackTools",(_,_)=>M4Borrow("TrackTools",[M4TrackAdjustment],700,620)));M3Move(trackPanel,TrackRemoveButton);trackPanel.Children.Add(M4Button("TrackHistory",(_,_)=>M4Borrow("TrackHistory",[M4TrackHistoryControls,M4OldTrackWorkspace],700,550)));
        side.Children.Add(M4Button("Gpx",(_,_)=>M4Borrow("Gpx",[PhotoGpxPanel],700,600)));m4Undo=M4Button("Undo",UndoLastApply);side.Children.Add(m4Undo);m4GpsCopy=M4Button("Save",M1PrepareGpsCopy);side.Children.Add(m4GpsCopy);
        var details=new StackPanel();M3Move(details,FavoriteStatus);M3Move(details,TrackWorkspaceStatus);side.Children.Add(new Expander{Header=M4("More"),Content=details,Margin=new(2,10,2,2)});
        m4Vertical=new GridSplitter{Width=6,HorizontalAlignment=HorizontalAlignment.Stretch,ResizeBehavior=GridResizeBehavior.PreviousAndNext};Grid.SetColumn(m4Vertical,1);m4Columns.Children.Add(m4Vertical);
        var map=new DockPanel{LastChildFill=true};Grid.SetColumn(map,2);m4Columns.Children.Add(map);var toolbar=new WrapPanel{Margin=new(4)};m4Toolbar=toolbar;DockPanel.SetDock(toolbar,Dock.Top);map.Children.Add(toolbar);m4Toggle=M4Button("Sidebar",(_,_)=>{m4Hidden=!m4Hidden;M4Size();});toolbar.Children.Add(m4Toggle);m4StripToggle=new Button{Content=L10n.Text("照片条"),Margin=new(2),Padding=new(7,5,7,5)};AutomationProperties.SetName(m4StripToggle,L10n.Text("显示或收起照片条"));AutomationProperties.SetAutomationId(m4StripToggle,"M6PhotoStripToggle");m4StripToggle.Click+=(_,_)=>{m4StripChoice=M4Strip.Visibility!=Visibility.Visible;M4Size();};toolbar.Children.Add(m4StripToggle);
        m4Tools=new Button{Content="⋯",ToolTip=L10n.Text("地图工具"),Margin=new(2),Padding=new(9,5,9,5)};AutomationProperties.SetName(m4Tools,L10n.Text("地图工具"));AutomationProperties.SetAutomationId(m4Tools,"M6MapTools");var tools=new ContextMenu();void Tool(string key,RoutedEventHandler action){var item=new MenuItem{Header=M4(key)};AutomationProperties.SetAutomationId(item,"M6MapMenu."+key);item.Click+=action;tools.Items.Add(item);}Tool("Search",(_,_)=>M4Borrow("Search",[M4SearchControls,PlacePreview],650,400));Tool("MapOptions",(_,_)=>M4Borrow("MapOptions",[M4MapDisplayOptions],650,400));Tool("Center",M4Center);Tool("OpenMap",(_,_)=>M4Borrow("MapOptions",[M4MapDisplayOptions],650,400));var retry=new MenuItem{Header=MapRetryButton.Content};retry.Click+=(_,_)=>MapRetryButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));tools.Items.Add(retry);m4Tools.ContextMenu=tools;m4Tools.Click+=(_,_)=>{tools.PlacementTarget=m4Tools;tools.IsOpen=true;};toolbar.Children.Add(m4Tools);toolbar.Children.Add(M4Button("Search",(_,_)=>M4Borrow("Search",[M4SearchControls,PlacePreview],650,400)));toolbar.Children.Add(M4Button("MapOptions",(_,_)=>M4Borrow("MapOptions",[M4MapDisplayOptions],650,400)));toolbar.Children.Add(M4Button("Center",M4Center));M3Move(toolbar,MapRetryButton);
        var layerBar=new WrapPanel{Margin=new(6,2,6,4)};m4LayerBar=layerBar;DockPanel.SetDock(layerBar,Dock.Top);map.Children.Add(layerBar);m4Layer=M4Button("OpenMap",(_,_)=>M4Borrow("MapOptions",[M4MapDisplayOptions],650,400));layerBar.Children.Add(m4Layer);var host=new Grid();map.Children.Add(host);M3Move(host,MapView);
        m4Horizontal=new GridSplitter{Height=6,HorizontalAlignment=HorizontalAlignment.Stretch,VerticalAlignment=VerticalAlignment.Stretch,ResizeDirection=GridResizeDirection.Rows,ResizeBehavior=GridResizeBehavior.PreviousAndNext};Grid.SetRow(m4Horizontal,1);m4Rows.Children.Add(m4Horizontal);M3Move(m4Rows,M4Strip);Grid.SetRow(M4Strip,2);M4OldStripHeader.Visibility=Visibility.Collapsed;
        var stripBar=new StackPanel{HorizontalAlignment=HorizontalAlignment.Right,Margin=new(4)};DockPanel.SetDock(stripBar,Dock.Right);M4Strip.Children.Insert(0,stripBar);m4Filter=new ComboBox{Width=110,Margin=new(3),ItemsSource=new[]{M4("All"),M4("Draft"),M4("NoDraft"),M4("HasGps"),M4("NoGps")}};m4Sort=new ComboBox{Width=130,Margin=new(3),ItemsSource=new[]{M4("NameAsc"),M4("NameDesc"),M4("DateAsc"),M4("DateDesc"),M4("ImportAsc"),M4("ImportDesc")}};
        AutomationProperties.SetName(m4Filter,M4("Filter"));AutomationProperties.SetName(m4Sort,M4("Sort"));stripBar.Children.Add(m4Filter);stripBar.Children.Add(m4Sort);stripBar.Children.Add(M4Button("ReturnCurrent",ReturnToCurrent));
        m4Filter.SetBinding(Selector.SelectedIndexProperty,new Binding("SelectedIndex"){Source=PhotoFilter,Mode=BindingMode.TwoWay});m4Sort.SetBinding(Selector.SelectedIndexProperty,new Binding("SelectedIndex"){Source=PhotoSort,Mode=BindingMode.TwoWay});
        var menu=new ContextMenu();void Add(string key,RoutedEventHandler action){var item=new MenuItem{Header=M4(key)};item.Click+=action;menu.Items.Add(item);}Add("Location",(_,_)=>M4Location());Add("Match",(_,_)=>M4OpenMatching());Add("Favorites",M1OpenFavorites);Add("Gpx",M4OpenPhotoGpx);Add("Save",M1PrepareGpsCopy);menu.Items.Add(new MenuItem{Header=M1Text("GpsClearLimit"),IsEnabled=false});PhotoStrip.ContextMenu=menu;
        M4MapWorkspace.SizeChanged+=(_,_)=>M4Size();M4Size();RefreshM4Map();
    }
    void M4Size(){
        if(m4Columns is null||m4Rows is null||m4Sidebar is null||m4Vertical is null)return;
        double width=M4MapWorkspace.ActualWidth,height=M4MapWorkspace.ActualHeight;if(width<1||height<1)return;
        bool hidden=m4Hidden;
        m4Sidebar.Visibility=hidden?Visibility.Collapsed:Visibility.Visible;m4Vertical.Visibility=hidden?Visibility.Collapsed:Visibility.Visible;
        m4Columns.ColumnDefinitions[0].MinWidth=hidden?0:260;m4Columns.ColumnDefinitions[0].MaxWidth=hidden?0:Math.Max(260,Math.Min(width*.5,width-426));if(m4Columns.ColumnDefinitions[0].Width.Value==0||m4Columns.ColumnDefinitions[0].Width.Value==300)m4Columns.ColumnDefinitions[0].Width=new(hidden?0:Math.Max(260,width*.26));
        m4Columns.ColumnDefinitions[1].Width=new(hidden?0:6);m4Columns.ColumnDefinitions[2].MinWidth=Math.Min(420,width);m4Rows.RowDefinitions[2].MaxHeight=Math.Max(132,height*.30);
        bool compact=height<500||width<900;foreach(var child in m4Toolbar!.Children.OfType<UIElement>())if(child!=m4Toggle&&child!=m4Tools&&child!=m4StripToggle)child.Visibility=compact?Visibility.Collapsed:Visibility.Visible;
        m4Tools!.Visibility=compact?Visibility.Visible:Visibility.Collapsed;m4LayerBar!.Visibility=compact?Visibility.Collapsed:Visibility.Visible;m4Toggle!.Content=compact?L10n.Text("照片面板"):M4("Sidebar");
        bool strip=m4StripChoice??!compact;var stripRow=m4Rows.RowDefinitions[2];if(!strip&&stripRow.Height.Value>0)m4StripHeight=stripRow.Height;stripRow.MinHeight=strip?132:0;stripRow.Height=strip?(stripRow.Height.Value==0?m4StripHeight:stripRow.Height):new(0);m4Rows.RowDefinitions[1].Height=new(strip?6:0);m4Horizontal!.Visibility=M4Strip.Visibility=strip?Visibility.Visible:Visibility.Collapsed;
        m4StripToggle!.ToolTip=L10n.Text("显示或收起照片条");
    }
    void RefreshM4Map(){
        if(!m4Ready||m4Preview is null)return;var selected=Selected;var current=Photos.SelectedItem as PhotoRow??selected.FirstOrDefault();m4Preview.Document=current?.Document;m4Preview.Visibility=current is null?Visibility.Collapsed:Visibility.Visible;
        m4Selection!.Text=current is null?M4("Empty"):M4Format("Selection",selected.Length,current.Name)+"\n"+current.Document.Value(current.Document.MainDateTag);int gpsDrafts=selected.Count(r=>r.Document.Draft.Keys.Any(k=>k.StartsWith("XMP-exif:GPS",StringComparison.Ordinal)));m4GpsSummary!.Text=M4Format("LocationSummary",selected.Count(r=>r.Document.Position()is null),selected.Count(r=>r.Document.Position()is not null),selected.Count(r=>!r.Document.CanStage))+(gpsDrafts==0?"":"\n"+M4Format("GpsPending",gpsDrafts));
        var point=current?.Document.Position();m4Position!.Text=point is null?M4("NoPosition"):M4Format("Latitude")+": "+DisplayCoordinate(point.Latitude)+"\n"+M4("Longitude")+": "+DisplayCoordinate(point.Longitude);
        m4Sidebar!.IsEnabled=m4Toolbar!.IsEnabled=m4Commands!.IsEnabled=!busy&&!renameRecoveryRequired; m4Filter!.IsEnabled=m4Sort!.IsEnabled=!busy;
        m4Undo!.IsEnabled=!busy&&!renameRecoveryRequired&&LastApplyCurrent();m4GpsCopy!.IsEnabled=!busy&&!renameRecoveryRequired&&gpsDrafts>0;
        m4Layer!.Content=currentMapPage==MapMessage.GooglePage?"Google · "+GoogleLayerChoice.Text:M4("OpenMap");
    }
    void M4Borrow(string key,FrameworkElement[] controls,double width,double height){
        if(busy||renameRecoveryRequired)return;foreach(var expansion in controls.OfType<Expander>())expansion.IsExpanded=true;M3Borrow(M4(key),controls,width,height);
    }
    void M4OpenMatching(){WorkspaceTabs.SelectedIndex=1;M4Borrow("Match",[M4BatchMatch],720,600);}
    void M4OpenPhotoGpx(object sender,RoutedEventArgs e){WorkspaceTabs.SelectedIndex=1;M4Borrow("Gpx",[PhotoGpxPanel],700,600);}
    void M4Location(){
        if(busy||renameRecoveryRequired)return;var content=new StackPanel{Margin=new(12)};M4Text(content,M4("PreviewNotice"));
        var longitude=new TextBox{Text=currentPreview?.Longitude.ToString("R",CultureInfo.InvariantCulture)??"",MaxLength=32};var latitude=new TextBox{Text=currentPreview?.Latitude.ToString("R",CultureInfo.InvariantCulture)??"",MaxLength=32};AutomationProperties.SetName(longitude,M4("Longitude"));AutomationProperties.SetName(latitude,M4("Latitude"));AutomationProperties.SetAutomationId(longitude,"M4Longitude");AutomationProperties.SetAutomationId(latitude,"M4Latitude");M4Text(content,M4("Longitude"));content.Children.Add(longitude);M4Text(content,M4("Latitude"));content.Children.Add(latitude);var status=new TextBlock{TextWrapping=TextWrapping.Wrap,Margin=new(2,8,2,8)};content.Children.Add(status);
        content.Children.Add(M4Button("Preview",(_,_)=>{if(busy||renameRecoveryRequired)return;try{if(!double.TryParse(longitude.Text,NumberStyles.Float,CultureInfo.InvariantCulture,out var lon)||!double.TryParse(latitude.Text,NumberStyles.Float,CultureInfo.InvariantCulture,out var lat)||!double.IsFinite(lon)||!double.IsFinite(lat)||Math.Abs(lon)>180||Math.Abs(lat)>90)throw new ArgumentException(M4("BadCoordinate"));InvalidateBatchTrack();ClearMatchMarker();currentPreview=new(lon,lat);previewAltitude=null;previewMethod="MANUAL";UpdateGpsButton();PostPreview();status.Text=M4("PreviewNotice");}catch(ArgumentException error){status.Text=error.Message;}}));
        content.Children.Add(M4Button("CancelPreview",(_,_)=>{if(busy)return;ClearMatchMarker();status.Text=M4("PreviewNotice");}));var original=(Panel)GpsDraftButton.Parent;int at=original.Children.IndexOf(GpsDraftButton);M3Move(content,GpsDraftButton);content.Children.Add(M4Button("ManualTime",(_,_)=>M4Borrow("ManualTime",[MatchPhotoInfo,(FrameworkElement)MatchButton.Parent,MatchResult],650,380)));
        var window=M3Dialog(M4("Location"),content,600,460);try{window.ShowDialog();}finally{M3Detach(GpsDraftButton);original.Children.Insert(Math.Min(at,original.Children.Count),GpsDraftButton);RefreshM4Map();}
    }
    void M4FavoriteEditor(){
        if(busy||renameRecoveryRequired)return;var content=new StackPanel{Margin=new(10)};var fields=new[]{FavoriteName,FavoriteNote,FavoriteLongitude,FavoriteLatitude};var placements=fields.Select(c=>(Control:c,Parent:(Panel)c.Parent,Index:((Panel)c.Parent).Children.IndexOf(c),Width:c.Width)).ToArray();var statusParent=(Panel)FavoriteStatus.Parent;string[] labels=["FavoriteName","FavoriteNote","Longitude","Latitude"];
        for(int i=0;i<fields.Length;i++){M4Text(content,M4(labels[i]));fields[i].Width=double.NaN;M3Move(content,fields[i]);}var actions=new WrapPanel();content.Children.Add(actions);actions.Children.Add(M4Button("FavoriteNew",NewFavorite));actions.Children.Add(M4Button("FavoriteSave",SaveFavorite));actions.Children.Add(M4Button("FavoriteDelete",(_,_)=>{if(MessageBox.Show(this,M4("DeleteConfirm"),M4("Favorites"),MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)==MessageBoxResult.Yes)DeleteFavorite(this,new RoutedEventArgs());}));actions.Children.Add(M4Button("FavoriteUp",MoveFavoriteUp));actions.Children.Add(M4Button("FavoriteReload",ReloadFavorites));M3Move(content,FavoriteStatus);var window=M3Dialog(M4("Favorites"),new ScrollViewer{Content=content,VerticalScrollBarVisibility=ScrollBarVisibility.Auto},560,500);
        content.Children.Add(M4Button("Cancel",(_,_)=>window.Close()));
        try{window.ShowDialog();}finally{foreach(var item in placements){M3Detach(item.Control);item.Control.Width=item.Width;item.Parent.Children.Insert(Math.Min(item.Index,item.Parent.Children.Count),item.Control);}M3Move(statusParent,FavoriteStatus);}
    }
    void M4Center(object sender,RoutedEventArgs e){
        if(busy||!mapReady||Photos.SelectedItem is not PhotoRow row||row.Document.Position()is not {} point)return;
        MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new{type="match-preview",point,focus=true}));
    }
    async void M4SelectTrackTimes(object sender,RoutedEventArgs e){
        if(busy||renameRecoveryRequired||!DiscardEditor())return;
        BeginOperation();try{
            var sources=tracks.Where(t=>!t.SourceUnavailable&&t.Data.Segments.Any(s=>s.Any(p=>p.Time is not null))).ToArray();
            if(sources.Length==0){Status.Text=L10n.Message(M4("NoTimedTracks"));return;}
            foreach(var source in sources)await EnsureTrackSource(source,operation!.Token);
            operation!.Token.ThrowIfCancellationRequested();
            var ranges=sources.SelectMany(t=>t.Data.Segments).Select(s=>s.Where(p=>p.Time is not null).Select(p=>p.Time!.Value).ToArray()).Where(s=>s.Length>0).Select(s=>(Start:s.Min(),End:s.Max())).ToArray();
            var selected=photos.Where(r=>r.Document.VerifiedCaptureDate?.Instant() is {} time&&ranges.Any(s=>time>=s.Start&&time<=s.End)).Where(r=>Photos.Items.Contains(r)).ToArray();var old=Selected;fillingEditor=true;try{Photos.SelectedItems.Clear();foreach(var row in selected)Photos.SelectedItems.Add(row);}finally{fillingEditor=false;}PhotoSelected(Photos,new SelectionChangedEventArgs(SelectorEvent(),old,selected));Status.Text=L10n.Message(M4Format("TimeSelection",selected.Length));
        }catch(OperationCanceledException){Status.Text=L10n.Message(M4("SelectCancelled"));}catch(Exception error){Status.Text=L10n.Message(M4("SelectFailed")+L10n.Message(error.Message));}finally{EndOperation();}
    }
}
