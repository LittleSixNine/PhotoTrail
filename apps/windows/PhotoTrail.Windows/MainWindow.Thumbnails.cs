using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    readonly ThumbnailLoader thumbnailLoader=new();bool syncingPhotoStrip,stripSelectionChange;
    internal event Action? ThumbnailsChanged;
    int selectionPresentationRevision;
    void QueueSelectionPresentation()
    {
        var revision=++selectionPresentationRevision;var input=Fields.Select(f=>(f.Apply.IsChecked,f.Value.Text)).ToArray();bool preserveView=stripSelectionChange;
        // Updating editor controls inside WPF's selection transaction stalls its reentrant notifications.
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.DataBind,()=>{
            if(!IsLoaded||revision!=selectionPresentationRevision)return;
            if(Fields.Select(f=>(f.Apply.IsChecked,f.Value.Text)).SequenceEqual(input))RefreshSelection();else{RefreshPhotoCount();RefreshInspector();}
            SyncPhotoStrip();RefreshMatchPhoto();bool previous=stripSelectionChange;stripSelectionChange=preserveView;try{_=PostPhotosAsync();}finally{stripSelectionChange=previous;}
        });
    }
    internal bool ThumbnailConsumerCurrent(PhotoDocument document)=>photos.Any(r=>ReferenceEquals(r.Document,document));
    internal async Task<BitmapSource> LoadThumbnailAsync(PhotoDocument document,int pixels,double dpi,bool preview,CancellationToken token)
    {
        if(document.FileType is not ("JPEG" or "PNG" or "TIFF")&&!ImportSource.Raw(document.FileType))throw new NotSupportedException("本机解码或合法内嵌预览不可用；元数据读取资格独立。");
        var version=await Task.Run(()=>ImportSource.Read(document.FilePath),token);if(document.Times is {} times&&(times.Created!=version.Created||times.Written!=version.Written))throw new IOException("显示来源属性改变，请重新读取来源。");
        var rawOrientation=document.Value("IFD0:Orientation");
        var orientation=string.IsNullOrEmpty(rawOrientation)?1:int.TryParse(rawOrientation,out var number)&&number is >=1 and <=8?number:throw new InvalidDataException("来源方向无效，拒绝猜测旋转。");
        var key=new ThumbnailKey(document.FilePath,document.SourceHash,$"{version.Identity}/{version.Length}/{version.Created.Ticks}/{version.Written.Ticks}/{version.Changed}",orientation,pixels,dpi,preview);
        var result=await thumbnailLoader.GetAsync(key,async()=>{BitmapSource image;
            if(ImportSource.Raw(document.FileType))image=await PhotoPreview.LoadDngAsync(Tool(),document.FilePath,document.SourceHash,orientation,maximumDimension:pixels);
            else image=PhotoPreview.Load(document.FilePath,document.FileType,document.SourceHash,orientation,pixels);
            version.RequireCurrent();return image;
        },token);if(firstThumbnailMs<0)firstThumbnailMs=System.Diagnostics.Stopwatch.GetElapsedTime(importStartTicks).TotalMilliseconds;return result;
    }
    void SyncPhotoStrip(){if(PhotoStrip is null)return;syncingPhotoStrip=true;try{PhotoStrip.SelectedItems.Clear();foreach(var row in Selected)if(PhotoStrip.Items.Contains(row))PhotoStrip.SelectedItems.Add(row);}finally{syncingPhotoStrip=false;}}
    void StripSelected(object sender,SelectionChangedEventArgs e)
    {
        if(syncingPhotoStrip||busy)return;var selected=PhotoStrip.SelectedItems.Cast<PhotoRow>().ToArray();fillingEditor=true;try{Photos.SelectedItems.Clear();foreach(var row in selected)if(Photos.Items.Contains(row))Photos.SelectedItems.Add(row);}finally{fillingEditor=false;}stripSelectionChange=true;try{PhotoSelected(Photos,new SelectionChangedEventArgs(SelectorEvent(),e.RemovedItems,e.AddedItems));}finally{stripSelectionChange=false;SyncPhotoStrip();}
    }
    static RoutedEvent SelectorEvent()=>System.Windows.Controls.Primitives.Selector.SelectionChangedEvent;
    void ReturnToCurrent(object sender,RoutedEventArgs e){if(Photos.SelectedItem is not PhotoRow row||!PhotoStrip.Items.Contains(row)){PhotoStripStatus.Text="当前筛选下没有可见的当前照片；筛选、选择与地图视野保留。";return;}PhotoStrip.ScrollIntoView(row);Photos.ScrollIntoView(row);PhotoStripStatus.Text="已滚动到当前照片；选择、地图视野与应用范围未改变。";}
}
