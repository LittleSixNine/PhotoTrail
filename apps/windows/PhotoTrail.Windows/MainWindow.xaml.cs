using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Core;
using Microsoft.Win32;

namespace PhotoTrail.Windows;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<PhotoRow> photos = [];
    private readonly ObservableCollection<TrackRow> tracks = [];
    private CancellationTokenSource? mapUpdate;
    private int mapRevision;
    private bool mapReady;
    private MapPoint? currentPreview;
    private double? previewAltitude;
    private string previewMethod = "MANUAL";
    private CancellationTokenSource? photoMapUpdate;
    private int photoRevision;
    private CancellationTokenSource? operation;
    private bool busy, fillingEditor, mapStarted;
    private PhotoRow[] previousSelection = [];
    private readonly string[] extensions = [".jpg", ".jpeg", ".png", ".heic", ".dng", ".tif", ".tiff", ".xmp", ".arw", ".nef", ".raf", ".cr2", ".cr3", ".rw2", ".orf", ".pef"];
    public MainWindow() { InitializeComponent(); Photos.ItemsSource = photos; TrackList.ItemsSource = tracks; }
    private (string Tag, CheckBox Apply, TextBox Value)[] Fields =>
    [ ("XMP-dc:Creator", AuthorApply, AuthorValue), ("XMP-dc:Title", TitleApply, TitleValue),
      ("XMP-dc:Description", DescriptionApply, DescriptionValue), ("XMP-dc:Subject", KeywordsApply, KeywordsValue),
      ("XMP-exif:DateTimeOriginal", DateApply, DateValue) ];
    private PhotoRow[] Selected => Photos.SelectedItems.Cast<PhotoRow>().ToArray();

    private async void WindowLoaded(object sender, RoutedEventArgs e)
    {
        var arguments = Environment.GetCommandLineArgs().Skip(1).ToArray();
        OutputFolder.Text = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        var files = arguments.Where(File.Exists).ToArray();
        await ImportAsync(files.Where(path => !IsTrack(path)));
        await ImportTracksAsync(files.Where(IsTrack));
        if (arguments.Contains("--map")) WorkspaceTabs.SelectedIndex = 1;
    }
    private static bool IsTrack(string path) => Path.GetExtension(path).ToLowerInvariant() is ".gpx" or ".kml" or ".kmz";
    private async void ReadTracks(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Multiselect = true, Filter = "轨迹|*.gpx;*.kml;*.kmz" };
        if (dialog.ShowDialog(this) == true) await ImportTracksAsync(dialog.FileNames);
    }
    private async Task ImportTracksAsync(IEnumerable<string> paths)
    {
        var files = paths.ToArray();
        if (busy || files.Length == 0 || !DiscardEditor()) return;
        BeginOperation(); var added = 0; var skipped = 0; var failures = new List<string>(); var cancelled = false;
        try
        {
            foreach (var path in files)
            {
                operation!.Token.ThrowIfCancellationRequested();
                var full = Path.GetFullPath(path);
                if (!IsTrack(full) || tracks.Any(row => row.Path.Equals(full, StringComparison.OrdinalIgnoreCase))) { skipped++; continue; }
                Status.Text = "读取轨迹：" + Path.GetFileName(full);
                try { var data = await Task.Run(() => TrackReader.Read(full, operation.Token), operation.Token); tracks.Add(new(full, data)); added++; }
                catch (OperationCanceledException) { throw; }
                catch (Exception error) { failures.Add(Path.GetFileName(full) + "：" + error.Message); }
            }
        }
        catch (OperationCanceledException) { cancelled = true; }
        finally { EndOperation(); }
        if (TrackList.SelectedIndex < 0 && tracks.Count > 0) TrackList.SelectedIndex = 0;
        Status.Text = $"轨迹{(cancelled ? "已取消" : "导入完成")}：新增{added}，跳过{skipped}，失败{failures.Count}。未改照片。";
        ShowFailures(failures);
    }
    private async void TrackSelected(object sender, SelectionChangedEventArgs e)
    {
        var row = TrackList.SelectedItem as TrackRow;
        TrackInfo.Text = row is null ? "未选择轨迹。" : $"{row.Name}：{row.Data.Segments.Count}段，{row.Data.Segments.Sum(s => s.Count)}点；其中{row.Data.Segments.Sum(s => s.Count(p => p.Time is not null))}点有时间。";
        MatchResult.Text = "轨迹已切换；请重新预览匹配。尚未写入GPS。";
        ClearMatchMarker();
        await PostTrackAsync();
    }
    private void RemoveTrack(object sender, RoutedEventArgs e)
    {
        if (!busy && TrackList.SelectedItem is TrackRow row) { tracks.Remove(row); Status.Text = "轨迹已从会话移除，磁盘文件保留。"; }
    }
    private async Task PostTrackAsync()
    {
        var revision = ++mapRevision; mapUpdate?.Cancel(); mapUpdate?.Dispose(); mapUpdate = new();
        if (!mapReady) return;
        var row = TrackList.SelectedItem as TrackRow; var cancellation = mapUpdate.Token;
        try
        {
            var payload = await Task.Run(() => TrackMapPayload.Build(row?.Data, row?.Name ?? "", cancellation), cancellation);
            if (revision == mapRevision && !cancellation.IsCancellationRequested)
            { MapView.CoreWebView2.PostWebMessageAsJson(payload); PostPreview(); }
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { TrackInfo.Text = "轨迹显示失败：" + error.Message; }
    }
    private void MatchTrack(object sender, RoutedEventArgs e)
    {
        if (busy) return;
        try
        {
            if (TrackList.SelectedItem is not TrackRow row) throw new InvalidOperationException("请先导入并选择轨迹。");
            if (Selected.Length != 1) throw new InvalidOperationException("请在元数据页选择一张照片。");
            var result = row.Data.Match(TrackReader.ParseTimestamp(MatchTimeValue.Text.Trim()));
            MatchResult.Text = result.Point is { } point ? $"{Selected[0].Name}：{point.Latitude:F6}, {point.Longitude:F6}，{result.Method}。仅预览，未加入GPS草稿。" : result.Reason;
            currentPreview = result.Point is { } matched ? new(matched.Longitude, matched.Latitude) : null;
            previewAltitude = result.Point?.Elevation; previewMethod = "GPS"; UpdateGpsButton();
            PostPreview();
        }
        catch (Exception error) { ClearMatchMarker(); MatchResult.Text = "匹配未执行：" + error.Message; }
    }
    private void ClearMatchMarker()
    {
        currentPreview = null; previewAltitude = null; previewMethod = "MANUAL"; UpdateGpsButton(); PostPreview();
    }
    private void PostPreview()
    {
        if (mapReady) MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { type = "match-preview", point = currentPreview }));
    }
    private void UpdateGpsButton() => GpsDraftButton.IsEnabled = !busy && currentPreview is not null && Selected.Length > 0 && Selected.All(row => row.Document.CanEdit);
    private void AddGpsDraft(object sender, RoutedEventArgs e)
    {
        try
        {
            if (busy || currentPreview is null || Selected.Length == 0 || Selected.Any(row => !row.Document.CanEdit)) throw new InvalidOperationException("请选择可编辑照片，并先预览定位。");
            var changes = PhotoDocument.PositionChanges(currentPreview, previewAltitude, previewMethod);
            var selected = Selected;
            foreach (var row in selected) row.Document.SetDraft(changes);
            Photos.Items.Refresh(); RefreshSelection(); _ = PostPhotosAsync();
            MatchResult.Text = $"已为{selected.Length}张照片加入WGS-84 GPS草稿。未知海拔／定位时间清除旧XMP值；请在元数据页保存副本。";
            Status.Text = "GPS已加入可撤销草稿，原文件未修改。";
        }
        catch (Exception error) { Status.Text = "GPS草稿未应用：" + error.Message; }
    }
    private async Task PostPhotosAsync()
    {
        var revision = ++photoRevision; photoMapUpdate?.Cancel(); photoMapUpdate?.Dispose(); photoMapUpdate = new();
        if (!mapReady) return;
        var selected = Selected.ToHashSet(); var markers = new List<PhotoMarker>();
        for (var index = 0; index < photos.Count; index++)
            if (photos[index].Document.Position() is { } position) markers.Add(new(index, photos[index].Name, position, selected.Contains(photos[index])));
        var focus = TrackList.SelectedItem is null && Selected.Length == 1 ? Selected[0].Document.Position() : null;
        var cancellation = photoMapUpdate.Token;
        try
        {
            var payload = await Task.Run(() => TrackMapPayload.Photos(markers, revision, focus, cancellation), cancellation);
            if (revision == photoRevision && !cancellation.IsCancellationRequested) MapView.CoreWebView2.PostWebMessageAsJson(payload);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { Status.Text = "照片标记暂不可用：" + error.Message; }
    }
    private ExifToolClient Tool()
    {
        var tool = Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL");
        var script = Environment.GetEnvironmentVariable("PHOTOTRAIL_EXIFTOOL_SCRIPT");
        var bundled = Path.Combine(AppContext.BaseDirectory, "tools", "exiftool", "ExifTool.exe");
        if (string.IsNullOrWhiteSpace(tool) && File.Exists(bundled)) tool = bundled;
        var config = Path.Combine(AppContext.BaseDirectory, "development-tool.json");
        if (string.IsNullOrWhiteSpace(tool) && File.Exists(config))
        {
            var settings = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(config));
            tool = settings?.GetValueOrDefault("executable"); script = settings?.GetValueOrDefault("script");
        }
        if (string.IsNullOrWhiteSpace(tool)) throw new IOException("未找到 ExifTool，请按 Windows 开发说明配置。");
        return new(tool, script);
    }
    private async void ReadPhoto(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Multiselect = true, Filter = "照片与XMP|" + string.Join(";", extensions.Select(x => "*" + x)) };
        if (dialog.ShowDialog(this) == true) await ImportAsync(dialog.FileNames);
    }
    private async void ReadFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "导入文件夹（仅当前层）" };
        if (dialog.ShowDialog(this) != true) return;
        try { await ImportAsync(Directory.GetFiles(dialog.FolderName)); }
        catch (Exception error) { Status.Text = "文件夹无法读取：" + error.Message; }
    }
    private async void FilesDropped(object sender, DragEventArgs e)
    {
        if (busy || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
        try
        {
            var paths = (string[])e.Data.GetData(DataFormats.FileDrop);
            var files = paths.SelectMany(path => Directory.Exists(path) ? Directory.GetFiles(path) : [path]).ToArray();
            var pictures = files.Where(path => !IsTrack(path)).ToArray();
            await ImportAsync(pictures);
            if (pictures.Length > 0 && operation?.IsCancellationRequested == true) return;
            await ImportTracksAsync(files.Where(IsTrack));
        }
        catch (Exception error) { Status.Text = "拖入失败：" + error.Message; }
    }
    private async Task ImportAsync(IEnumerable<string> paths)
    {
        if (busy) return;
        var files = paths.ToArray();
        if (files.Length == 0 || !DiscardEditor()) return;
        BeginOperation();
        var added = 0; var skipped = 0; var failures = new List<string>(); var cancelled = false;
        try
        {
            var client = Tool();
            foreach (var path in files)
            {
                operation!.Token.ThrowIfCancellationRequested();
                var full = Path.GetFullPath(path);
                if (!extensions.Contains(Path.GetExtension(full), StringComparer.OrdinalIgnoreCase) ||
                    photos.Any(p => p.Document.FilePath.Equals(full, StringComparison.OrdinalIgnoreCase))) { skipped++; continue; }
                Status.Text = "读取：" + Path.GetFileName(full);
                try { photos.Add(new(await PhotoDocument.LoadAsync(client, full, operation.Token))); added++; }
                catch (OperationCanceledException) { throw; }
                catch (Exception error) { failures.Add(Path.GetFileName(full) + "：" + error.Message); }
            }
        }
        catch (OperationCanceledException) { cancelled = true; }
        catch (Exception error) { failures.Add(error.Message); }
        finally { EndOperation(); }
        if (Photos.SelectedIndex < 0 && photos.Count > 0) Photos.SelectedIndex = 0;
        _ = PostPhotosAsync();
        Status.Text = $"{(cancelled ? "导入已取消" : "导入完成")}：新增 {added}，跳过 {skipped}，失败 {failures.Count}。原文件未修改。";
        ShowFailures(failures);
    }
    private void PhotoSelected(object sender, SelectionChangedEventArgs e)
    {
        if (fillingEditor) return;
        if (!DiscardEditor())
        {
            fillingEditor = true; Photos.SelectedItems.Clear();
            foreach (var row in previousSelection) Photos.SelectedItems.Add(row);
            fillingEditor = false; return;
        }
        previousSelection = Selected;
        RefreshSelection();
        MatchPhotoInfo.Text = Selected.Length == 1 ? "匹配照片：" + Selected[0].Name + "；无时区时间须手动提供明确匹配时间。" : "请在元数据页选择一张照片进行匹配预览。";
        MatchTimeValue.Text = "";
        if (Selected.Length == 1)
        {
            var value = Selected[0].Document.Value("XMP-exif:DateTimeOriginal");
            if (DateTimeOffset.TryParseExact(value, "yyyy:MM:dd HH:mm:sszzz", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var time)) MatchTimeValue.Text = time.ToString("O");
        }
        MatchResult.Text = "照片选择已切换；请重新预览匹配。尚未写入GPS。";
        ClearMatchMarker();
        _ = PostPhotosAsync();
    }
    private void RefreshSelection()
    {
        fillingEditor = true;
        var selected = Selected;
        var editable = selected.Length > 0 && selected.All(p => p.Document.CanEdit);
        Editor.IsEnabled = !busy && editable;
        UpdateGpsButton();
        DraftActions.IsEnabled = !busy && editable;
        SaveButton.IsEnabled = !busy && selected.Any(p => p.Document.Draft.Count > 0);
        RemoveButton.IsEnabled = !busy && selected.Length > 0;
        SelectionInfo.Text = selected.Length == 0 ? "请选择照片。Ctrl / Shift 可多选。" :
            $"已选 {selected.Length} 张；{selected.Count(p => p.Document.Draft.Count > 0)} 张有草稿。" +
            (selected.Length == 1 ? (selected[0].Document.SidecarPath is null ? "XMP 来源：文件内嵌。" : "XMP 来源：同名旁车。") : "混合值显示为空；只应用勾选字段。") +
            (editable ? "" : "所选包含只读格式，暂不支持编辑。");
        foreach (var (tag, apply, value) in Fields)
        {
            var values = selected.Select(p => p.Document.Value(tag)).Distinct().ToArray();
            value.Text = values.Length == 1 ? values[0] : ""; apply.IsChecked = false;
        }
        var metadata = new List<MetadataRow>();
        if (selected.Length == 1)
        {
            var photo = selected[0].Document;
            metadata.AddRange(photo.Embedded.EnumerateObject().Where(p => p.Name != "SourceFile").Select(p => new MetadataRow("内嵌 / " + p.Name, PhotoDocument.Text(p.Value))));
            if (photo.Sidecar is { } sidecar) metadata.AddRange(sidecar.EnumerateObject().Where(p => p.Name != "SourceFile").Select(p => new MetadataRow("旁车 / " + p.Name, PhotoDocument.Text(p.Value))));
        }
        MetadataGrid.ItemsSource = metadata;
        fillingEditor = false;
    }
    private void EditorChanged(object sender, TextChangedEventArgs e)
    {
        if (fillingEditor || !IsLoaded) return;
        foreach (var (_, apply, value) in Fields) if (ReferenceEquals(value, sender)) apply.IsChecked = true;
    }
    private bool DiscardEditor()
    {
        if (!Fields.Any(f => f.Apply.IsChecked == true)) return true;
        return MessageBox.Show(this, "输入尚未加入草稿。放弃这次输入？", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) == MessageBoxResult.Yes;
    }
    private void ApplyDraft(object sender, RoutedEventArgs e)
    {
        var selected = Selected;
        try
        {
            if (selected.Length == 0 || selected.Any(p => !p.Document.CanEdit)) throw new InvalidOperationException("请选择可编辑照片。");
            var changes = Fields.Where(f => f.Apply.IsChecked == true).ToDictionary(f => f.Tag, f => f.Value.Text.Replace("\r\n", "\n"));
            if (changes.Count == 0) { Status.Text = "请先勾选要修改的字段。"; return; }
            PhotoDocument.ValidateChanges(changes);
            foreach (var row in selected) row.Document.SetDraft(changes);
            Photos.Items.Refresh(); RefreshSelection();
            if (changes.ContainsKey("XMP-exif:DateTimeOriginal")) ClearMatchMarker();
            _ = PostPhotosAsync();
            Status.Text = $"已为 {selected.Length} 张照片加入草稿。尚未写入文件。";
        }
        catch (Exception error) { Status.Text = "草稿未应用：" + error.Message; }
    }
    private void UndoDraft(object sender, RoutedEventArgs e)
    {
        foreach (var row in Selected) row.Document.ClearDraft();
        Photos.Items.Refresh(); RefreshSelection(); Status.Text = "所选草稿已撤销。原文件未修改。";
        ClearMatchMarker(); _ = PostPhotosAsync();
    }
    private void RemovePhotos(object sender, RoutedEventArgs e)
    {
        if (busy || !DiscardEditor()) return;
        var selected = Selected;
        if (selected.Any(p => p.Document.Draft.Count > 0) &&
            MessageBox.Show(this, "移除会放弃所选草稿，磁盘文件保留。继续？", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        fillingEditor = true;
        foreach (var row in selected) photos.Remove(row);
        previousSelection = Selected; fillingEditor = false; RefreshSelection();
        ClearMatchMarker(); _ = PostPhotosAsync();
        Status.Text = $"已从列表移除 {selected.Length} 项，磁盘文件保留。";
    }
    private void ChooseOutput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "选择保存副本的文件夹" };
        if (dialog.ShowDialog(this) == true) OutputFolder.Text = dialog.FolderName;
    }
    private async void SaveCopies(object sender, RoutedEventArgs e)
    {
        if (busy) return;
        if (Fields.Any(f => f.Apply.IsChecked == true)) { Status.Text = "请先将输入加入草稿，再保存副本。"; return; }
        var selected = Selected.Where(p => p.Document.Draft.Count > 0).ToArray();
        if (selected.Length == 0) return;
        var folder = OutputFolder.Text;
        BeginOperation();
        var saved = 0; var failures = new List<string>(); var cancelled = false;
        try
        {
            var client = Tool();
            foreach (var row in selected)
            {
                operation!.Token.ThrowIfCancellationRequested(); Status.Text = "保存副本：" + row.Name;
                try { await MetadataCopy.SaveAsync(client, row.Document, folder, operation.Token); saved++; }
                catch (OperationCanceledException) { throw; }
                catch (Exception error) { failures.Add(row.Name + "：" + error.Message); }
            }
        }
        catch (OperationCanceledException) { cancelled = true; }
        catch (Exception error) { failures.Add(error.Message); }
        finally { EndOperation(); }
        Status.Text = $"{(cancelled ? "保存已取消" : "保存结束")}：副本成功 {saved}，失败 {failures.Count}。原文件未修改；草稿保留，可撤销。";
        ShowFailures(failures);
    }
    private void ShowFailures(List<string> failures)
    {
        if (failures.Count > 0) MessageBox.Show(this, string.Join("\n", failures), "任务结果", MessageBoxButton.OK, MessageBoxImage.Warning);
    }
    private void BeginOperation()
    {
        busy = true; operation?.Dispose(); operation = new();
        ReadButton.IsEnabled = FolderButton.IsEnabled = OutputButton.IsEnabled = OutputFolder.IsEnabled = Photos.IsEnabled = false;
        TrackReadButton.IsEnabled = TrackList.IsEnabled = TrackRemoveButton.IsEnabled = MatchButton.IsEnabled = false;
        RefreshSelection();
    }
    private void EndOperation()
    {
        busy = false;
        ReadButton.IsEnabled = FolderButton.IsEnabled = OutputButton.IsEnabled = OutputFolder.IsEnabled = Photos.IsEnabled = true;
        TrackReadButton.IsEnabled = TrackList.IsEnabled = TrackRemoveButton.IsEnabled = MatchButton.IsEnabled = true;
        RefreshSelection();
    }
    private void CancelRead(object sender, RoutedEventArgs e) { operation?.Cancel(); if (busy) Status.Text = "正在取消任务…"; }
    private void WindowClosing(object? sender, CancelEventArgs e)
    {
        if (busy) { operation?.Cancel(); e.Cancel = true; Status.Text = "正在取消任务；结束后可关闭。"; return; }
        if (photos.Any(p => p.Document.Draft.Count > 0) || Fields.Any(f => f.Apply.IsChecked == true))
            e.Cancel = MessageBox.Show(this, "存在未撤销的草稿或未应用输入。放弃并退出？保存的副本仍保留。", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes;
    }
    private void WindowClosed(object? sender, EventArgs e) { operation?.Cancel(); mapRevision++; photoRevision++; mapReady = false; mapUpdate?.Cancel(); photoMapUpdate?.Cancel(); MapView.Dispose(); }
    private void MapSelected(object sender, SelectionChangedEventArgs e)
    {
        if (ReferenceEquals(e.Source, WorkspaceTabs) && IsLoaded && WorkspaceTabs.SelectedIndex == 1)
            MapLoaded(sender, e);
    }
    private async void MapLoaded(object sender, RoutedEventArgs e)
    {
        if (mapStarted || WorkspaceTabs.SelectedIndex != 1) return;
        mapStarted = true;
        try
        {
            var cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "WindowsValidation", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: cache);
            await MapView.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(15));
            MapView.CoreWebView2.SetVirtualHostNameToFolderMapping("phototrail.local", Path.Combine(AppContext.BaseDirectory, "Web"), CoreWebView2HostResourceAccessKind.DenyCors);
            MapView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            MapView.CoreWebView2.Settings.AreDevToolsEnabled = false;
            MapView.CoreWebView2.Settings.AreHostObjectsAllowed = false;
            MapView.CoreWebView2.NavigationStarting += (_, args) => args.Cancel = args.Uri != MapMessage.Page;
            MapView.CoreWebView2.NewWindowRequested += (_, args) => args.Handled = true;
            MapView.CoreWebView2.WebMessageReceived += (_, args) =>
            {
                if (MapMessage.IsReady(args.Source, args.WebMessageAsJson)) { mapReady = true; _ = PostTrackAsync(); _ = PostPhotosAsync(); }
                if (busy) return;
                if (MapMessage.TryPhoto(args.Source, args.WebMessageAsJson, out var id, out var revision) && revision == photoRevision && id < photos.Count)
                {
                    if (!DiscardEditor()) return;
                    fillingEditor = true;
                    foreach (var (_, apply, _) in Fields) apply.IsChecked = false;
                    Photos.SelectedItems.Clear(); fillingEditor = false; Photos.SelectedItem = photos[id];
                }
                if (MapMessage.IsReady(args.Source, args.WebMessageAsJson)) Status.Text = "默认地图已加载；点击地图只作坐标预览。";
                if (MapMessage.TryPoint(args.Source, args.WebMessageAsJson, out var point)) { currentPreview = point; previewAltitude = null; previewMethod = "MANUAL"; UpdateGpsButton(); Status.Text = $"选点预览：{point!.Latitude:F6}, {point.Longitude:F6}。尚未写入照片。"; }
            };
            MapView.CoreWebView2.Navigate(MapMessage.Page);
        }
        catch (Exception error) { if (!busy) Status.Text = "地图暂不可用：" + error.Message; mapStarted = false; }
    }
    private record MetadataRow(string Tag, string Value);
    private record TrackRow(string Path, TrackData Data) { public string Name => System.IO.Path.GetFileName(Path); }
    private record PhotoRow(PhotoDocument Document)
    {
        public string Name => Path.GetFileName(Document.FilePath);
        public string Summary => $"{Document.FileType} · {(Document.SidecarPath is null ? "内嵌" : "XMP旁车")} · {(Document.Draft.Count > 0 ? $"{Document.Draft.Count}项草稿" : "原始值")}";
    }
}
