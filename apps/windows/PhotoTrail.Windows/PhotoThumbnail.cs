using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public sealed class PhotoThumbnail : Grid
{
    public static readonly DependencyProperty DocumentProperty=DependencyProperty.Register(nameof(Document),typeof(PhotoDocument),typeof(PhotoThumbnail),new PropertyMetadata(null,(d,e)=>((PhotoThumbnail)d).Refresh()));
    public PhotoDocument? Document{get=>(PhotoDocument?)GetValue(DocumentProperty);set=>SetValue(DocumentProperty,value);}
    public bool Strip{get;set;}
    readonly Image image=new(){Stretch=Stretch.Uniform};readonly TextBlock status=new(){Text="准备缩略图",TextWrapping=TextWrapping.Wrap,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,FontSize=11};CancellationTokenSource? request;int revision;
    MainWindow? owner;
    public PhotoThumbnail(){Children.Add(image);Children.Add(status);Loaded+=(_,_)=>{owner=Window.GetWindow(this) as MainWindow;if(owner is not null)owner.ThumbnailsChanged+=Refresh;Refresh();};Unloaded+=(_,_)=>{if(owner is not null)owner.ThumbnailsChanged-=Refresh;owner=null;request?.Cancel();request?.Dispose();request=null;revision++;};SizeChanged+=(_,_)=>{if(Strip)Refresh();};}
    protected override void OnDpiChanged(DpiScale oldDpi,DpiScale newDpi){base.OnDpiChanged(oldDpi,newDpi);Refresh();}
    internal async void Refresh()
    {
        if(!IsLoaded||Window.GetWindow(this) is not MainWindow window||Document is not {} document)return;
        request?.Cancel();request?.Dispose();request=new();var token=request.Token;var generation=++revision;var dpi=VisualTreeHelper.GetDpi(this).DpiScaleX;var pixels=ThumbnailLoader.Pixels(Strip?Math.Max(160,ActualWidth):80,dpi,Strip);image.Source=null;status.Visibility=Visibility.Visible;status.Text="准备缩略图";
        try{var result=await window.LoadThumbnailAsync(document,pixels,dpi,false,token);if(!IsLoaded||token.IsCancellationRequested||generation!=revision||!ReferenceEquals(Document,document)||!window.ThumbnailConsumerCurrent(document))return;image.Source=result;status.Visibility=Visibility.Collapsed;ToolTip=$"显示规格{pixels}px · DPI倍率{dpi:F2}；只读显示。";}
        catch(OperationCanceledException){}catch(Exception){if(IsLoaded&&!token.IsCancellationRequested&&generation==revision){status.Text="预览不可用";ToolTip="当前合法解码不可用；元数据读取及来源资格独立。";}}
    }
}
