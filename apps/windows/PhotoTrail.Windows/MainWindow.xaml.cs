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
    private string currentMapPage = MapMessage.Page;
    private int placeRequest;
    private bool placePending;
    private MapPoint? currentPreview;
    private bool clipboardGpsPreview;
    private double? previewAltitude;
    private string previewMethod = "MANUAL";
    private CancellationTokenSource? photoMapUpdate;
    private int photoRevision;
    private CancellationTokenSource? operation;
    private bool busy, fillingEditor, mapStarted, mapConfigured, mapInitializing, mapNeedsReplacement;
    private PhotoRow[] previousSelection = [];
    private readonly SemaphoreSlim photoPreviewGate = new(1,1);
    private CancellationTokenSource? photoPreviewRequest;
    private PhotoDocument? previewDocument;
    private int photoPreviewRevision;

    private readonly string[] extensions = [".jpg", ".jpeg", ".png", ".heic", ".dng", ".tif", ".tiff", ".xmp", ".arw", ".nef", ".raf", ".cr2", ".cr3", ".rw2", ".orf", ".pef"];
    public MainWindow() { InitializeComponent(); metadataBaseFont=FontSize; foreach(var field in Fields)fieldLabels[field.Tag]=field.Apply.Content.ToString()!.Replace(field.Tag,"").Trim(' ','·'); DatePlanChanged(this,new RoutedEventArgs()); Photos.ItemsSource = photos; TrackList.ItemsSource = tracks; ClipboardField.ItemsSource = Fields.Select(field => new { field.Tag, Name = fieldLabels[field.Tag]+" · "+field.Tag }).ToArray(); ClipboardField.SelectedIndex = 0; InitializePresetEditor();
        AddHandler(System.Windows.Controls.Primitives.ToggleButton.CheckedEvent,new RoutedEventHandler((s,e)=>{if(!fillingEditor)InvalidateDates();}));
        AddHandler(System.Windows.Controls.Primitives.ToggleButton.UncheckedEvent,new RoutedEventHandler((s,e)=>{if(!fillingEditor)InvalidateDates();}));
    }
    private (string Tag, CheckBox Apply, TextBox Value)[] Fields =>
    [ ("XMP-dc:Creator", AuthorApply, AuthorValue), ("XMP-dc:Title", TitleApply, TitleValue),
      ("XMP-dc:Description", DescriptionApply, DescriptionValue), ("XMP-dc:Subject", KeywordsApply, KeywordsValue),
      ("XMP-exif:DateTimeOriginal", DateApply, DateValue),
      ("XMP-exif:DateTimeDigitized", DigitizedApply, DigitizedValue), ("XMP-xmp:CreateDate", CreateDateApply, CreateDateValue),
      ("XMP-xmp:ModifyDate", ModifyDateApply, ModifyDateValue),
      ("XMP-photoshop:Country", CountryApply, CountryValue), ("XMP-photoshop:State", StateApply, StateValue),
      ("XMP-photoshop:City", CityApply, CityValue), ("XMP-iptcCore:Location", LocationApply, LocationValue),
      ("XMP-iptcCore:CountryCode", CountryCodeApply, CountryCodeValue),
      ("XMP-dc:Rights", RightsApply, RightsValue), ("XMP-xmp:Rating", RatingApply, RatingValue), ("XMP-xmp:Label", LabelApply, LabelValue),
      ("XMP-tiff:Make", MakeApply, MakeValue), ("XMP-tiff:Model", ModelApply, ModelValue),
      ("XMP-aux:Lens", LensApply, LensValue), ("XMP-aux:LensSerialNumber", LensSerialApply, LensSerialValue),
      ("XMP-exif:ExposureTime", ExposureTimeApply, ExposureTimeValue), ("XMP-exif:FNumber", FNumberApply, FNumberValue),
      ("XMP-exif:ISO", IsoApply, IsoValue), ("XMP-exif:FocalLength", FocalLengthApply, FocalLengthValue),
      ("XMP-exif:ExposureCompensation", ExposureBiasApply, ExposureBiasValue), ("XMP-exif:ExposureProgram", ExposureProgramApply, ExposureProgramValue),
      ("XMP-exif:WhiteBalance", WhiteBalanceApply, WhiteBalanceValue) ];
    private PhotoRow[] Selected => Photos.SelectedItems.Cast<PhotoRow>().ToArray();

    private readonly string themePreferencePath = Environment.GetEnvironmentVariable("PHOTOTRAIL_THEME_FILE") ?? ThemePreference.DefaultPath;
    private bool restoringTheme;
    private void ThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded) return;
#pragma warning disable WPF0001 // Native Fluent ThemeMode is experimental in the pinned .NET 10 SDK.
        ThemeMode = ThemeChoice.SelectedIndex switch { 1 => System.Windows.ThemeMode.Light, 2 => System.Windows.ThemeMode.Dark, _ => System.Windows.ThemeMode.System };
#pragma warning restore WPF0001
        if (restoringTheme) return;
        try { ThemePreference.Save(themePreferencePath,ThemeChoice.SelectedIndex); ThemeStatus.Text = "应用外观已保存为本机偏好，重启恢复；不改变Windows设置。"; }
        catch (Exception) { ThemeStatus.Text = "本次外观已切换，但本机偏好未保存；已检测的损坏配置不覆盖。"; }
    }
    private void WindowKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var modifiers = System.Windows.Input.Keyboard.Modifiers;
        if (e.Key == System.Windows.Input.Key.Escape && (busy || checkingEnvironment)) { CancelRead(sender,e); e.Handled = true; return; }
        if (busy) return;
        if (e.Key == System.Windows.Input.Key.O && modifiers == System.Windows.Input.ModifierKeys.Control) { e.Handled = true; ReadPhoto(sender,e); }
        else if (e.Key == System.Windows.Input.Key.O && modifiers == (System.Windows.Input.ModifierKeys.Control | System.Windows.Input.ModifierKeys.Shift)) { e.Handled = true; ReadFolder(sender,e); }
        else if (e.Key == System.Windows.Input.Key.S && modifiers == System.Windows.Input.ModifierKeys.Control) { e.Handled = true; SaveCopies(sender,e); }
        else if (e.Key == System.Windows.Input.Key.F3 && modifiers == System.Windows.Input.ModifierKeys.None) { e.Handled = true; WorkspaceTabs.SelectedIndex = 0; PhotoSearch.Focus(); PhotoSearch.SelectAll(); }
    }

    private async void WindowLoaded(object sender, RoutedEventArgs e)
    {
        var arguments = Environment.GetCommandLineArgs().Skip(1).ToArray();
        OutputFolder.Text = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        restoringTheme = true;
        try { ThemeChoice.SelectedIndex = ThemePreference.Read(themePreferencePath); ThemeStatus.Text = "已读取本机外观偏好；不改变Windows设置。"; }
        catch (Exception) { ThemeStatus.Text = "本机外观偏好不可读取，暂跟随系统；已有配置未覆盖。"; }
        finally { restoringTheme = false; }
        LoadSettings();LoadInplaceRecords();LoadMetadataPresets();
        RefreshGoogleKeyStatus();
        LoadLatestRenameJournal();LoadRenameSchemes();
        LoadTrackHistory();LoadTrackSnapshots();
        try
        {
            var files = arguments.Where(path => File.Exists(path) || Directory.Exists(path)).SelectMany(path => Directory.Exists(path) ? Directory.GetFiles(path) : new[] { path }).ToArray();
            await ImportAsync(files.Where(path => !IsTrack(path)));
            await ImportTracksAsync(files.Where(IsTrack));
        }
        catch (Exception error) { Status.Text = "启动路径无法读取：" + error.Message; }
        if (arguments.Contains("--map")) WorkspaceTabs.SelectedIndex = 1;
    }
    private CancellationTokenSource? dependencyCheck;
    private bool checkingEnvironment;
    private async void CheckDependencies(object sender, RoutedEventArgs e)
    {
        if (busy || checkingEnvironment) return;
        checkingEnvironment = true; EnvironmentCheckButton.IsEnabled = false;
        dependencyCheck?.Dispose(); dependencyCheck = new();
        try
        {
            var lines = new List<string> { ".NET：" + Environment.Version, "Windows：" + Environment.OSVersion.Version,
                "WPF渲染偏好：" + System.Windows.Media.RenderOptions.ProcessRenderMode,
                "显示缩放：" + (System.Windows.Media.VisualTreeHelper.GetDpi(this).DpiScaleX * 100).ToString("F0") + "%" };
            try { lines.Add("WebView2：" + CoreWebView2Environment.GetAvailableBrowserVersionString()); }
            catch (Exception) { lines.Add("WebView2不可用：请安装Microsoft Edge WebView2 Runtime；元数据功能仍可使用。"); }
            DependencyStatus.Text = string.Join("\n", lines) + "\n正在检查ExifTool…";
            try
            {
                var version = (await Tool().RunAsync(["-ver"], dependencyCheck.Token, TimeSpan.FromSeconds(5))).Trim();
                lines.Add(version.Length <= 64 && version.All(c => char.IsAsciiDigit(c) || c == '.') ? "ExifTool：" + version : "ExifTool版本响应异常，请检查完整工具目录。");
            }
            catch (OperationCanceledException) { lines.Add("ExifTool检查已取消。"); }
            catch (Exception) { lines.Add("ExifTool不可用：请保留完整发行目录及随附文件。测试包应包含tools/exiftool/ExifTool.exe。"); }
            DependencyStatus.Text = string.Join("\n", lines);
        }
        finally { checkingEnvironment = false; EnvironmentCheckButton.IsEnabled = true; }
    }
    private void RefreshGoogleKeyStatus() => GoogleKeyStatus.Text = File.Exists(GoogleKeyStore.DefaultPath) ? "已保存本机密钥；尚未联网验证，当前默认地图为OpenFreeMap。" : "尚未保存本机密钥；当前使用OpenFreeMap。";
    private void SaveGoogleKey(object sender, RoutedEventArgs e)
    {
        try { GoogleKeyStore.Save(GoogleKeyStore.DefaultPath, GoogleKeyInput.Password); RefreshGoogleKeyStatus(); }
        catch (ArgumentException) { GoogleKeyStatus.Text = "密钥格式无效：请输入20至256位英文字母、数字、横线或下划线。"; }
        catch (Exception) { GoogleKeyStatus.Text = "本机密钥未保存；请检查本机存储访问，已有密钥保持不变。"; }
        finally { GoogleKeyInput.Clear(); }
    }
    private void ClearGoogleKey(object sender, RoutedEventArgs e)
    {
        if (busy || mapInitializing) { GoogleKeyStatus.Text = "任务或地图初始化中，完成后再删除密钥。"; return; }
        try { GoogleKeyStore.Clear(GoogleKeyStore.DefaultPath); GoogleKeyInput.Clear(); if (currentMapPage == MapMessage.GooglePage) UseDefaultMap(sender, e); RefreshGoogleKeyStatus(); }
        catch (Exception) { GoogleKeyStatus.Text = "本机密钥未删除；请检查本机存储访问。"; }
    }
    private void UseDefaultMap(object sender, RoutedEventArgs e)
    {
        if (busy || mapInitializing) return;
        currentMapPage = MapMessage.Page; RefreshGoogleKeyStatus(); SuspendMap();
        WorkspaceTabs.SelectedIndex = 1;
        if (mapConfigured) RetryMap(sender, e);
    }
    private void UseGoogleMap(object sender, RoutedEventArgs e)
    {
        if (busy || mapInitializing) return;
        try
        {
            if (GoogleKeyStore.Load(GoogleKeyStore.DefaultPath) is null) { GoogleKeyStatus.Text = "请先保存本机密钥。"; return; }
            currentMapPage = MapMessage.GooglePage; SuspendMap(); WorkspaceTabs.SelectedIndex = 1;
            if (mapConfigured) RetryMap(sender, e);
        }
        catch (Exception) { GoogleKeyStatus.Text = "本机密钥不可读取；请重新保存。"; }
    }
    private void ClearPlacePreview()
    {
        placeRequest++; placePending = false;placeQuery="";
        PlacePreview.Text = "地区查询只预览；Google Maps结果不自动写入照片。";
    }
    private async void LookupPlace(object sender, RoutedEventArgs e)
    {
        if (busy || !mapReady || currentMapPage != MapMessage.GooglePage || currentPreview is null)
        { PlacePreview.Text = "请先明确选择Google地图并预览一个位置。"; return; }
        var id = ++placeRequest; placePending = true;placeQuery="";
        PlacePreview.Text = "正在向Google Maps查询预览位置…";
        MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { type = "geocode", id, point = currentPreview }));
        await Task.Delay(TimeSpan.FromSeconds(20));
        if (id == placeRequest && placePending) { placeRequest++; placePending = false; PlacePreview.Text = "Google Maps查询超时，未改照片。"; }
    }
    private RenamePlan? frozenRenamePlan;
    private int renameRevision;
    private bool renameRecoveryRequired;
    private string RenameJournalDirectory => Environment.GetEnvironmentVariable("PHOTOTRAIL_RENAME_HISTORY") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "Windows", "RenameHistory");
    private void LoadLatestRenameJournal()
    {
        if (!Directory.Exists(RenameJournalDirectory)) return;
        try
        {
            var path = Directory.EnumerateFiles(RenameJournalDirectory, "rename-*.jsonl").OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
            if (path is null) return;
            RenameJournalPath.Text = path;
            var record = RenameExecutor.ReadJournal(path);
            renameRecoveryRequired = !record.Complete && record.Files.Any(file => file.Current != file.Source);
            RenameStatus.Text = renameRecoveryRequired ? "最近更名未完成，请先按记录恢复；元数据编辑暂不可用。" : "已载入最近执行记录，可核对或恢复。";
        }
        catch (Exception) { renameRecoveryRequired = true; RenameStatus.Text = "最近执行记录不可读取，请核对该记录及实际名称；元数据编辑暂不可用。"; }
    }
    private PhotoRow[] RenameSelection() {
        var selected=Selected;

        var targets=selected.ToHashSet();return photos.Where(targets.Contains).ToArray();
    }
    private void UpdateRenameButtons()
    {
        if (ExecuteRenameButton is not null) ExecuteRenameButton.IsEnabled = !busy && !renameRecoveryRequired && frozenRenamePlan is not null;
        if (FreezeRenameButton is not null) FreezeRenameButton.IsEnabled = !busy && !renameRecoveryRequired && Selected.Length > 0;
        if (RestoreRenameButton is not null) RestoreRenameButton.IsEnabled = !busy;
        if (RenameRules is not null) RenameRules.IsEnabled = !busy;
        if(RenameProcessingControls is not null)RenameProcessingControls.IsEnabled=!busy; if(RenameGroups is not null)RenameGroups.IsEnabled=!busy; if(RenameUndoOrder is not null)RenameUndoOrder.IsEnabled=CanMoveRenameGroups&&renameOrderUndo is not null;
        RefreshSchemeControls();
        if (RenamePresetSaveButton is not null) RenamePresetSaveButton.IsEnabled = !busy && !renameRecoveryRequired;
        if (RenamePresetLoadButton is not null) RenamePresetLoadButton.IsEnabled = !busy && !renameRecoveryRequired;
        if (RenameJournalPath is not null) RenameJournalPath.IsEnabled = !busy;
        if (RecentTrackReadButton is not null) RecentTrackReadButton.IsEnabled = !busy;
        if (RecentTracks is not null) RecentTracks.IsEnabled = !busy;
    }
    private bool RenameHasDraft(IEnumerable<string> paths)
    {
        var affected = paths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return photos.Any(row => affected.Contains(row.Document.FilePath) && row.Document.Draft.Count > 0) || Fields.Any(field => field.Apply.IsChecked == true);
    }
    private async Task<int> RefreshRenamedPhotos(RenameResult result)
    {
        RemapRenameIdentities(result); var mappings = result.Files.ToDictionary(file => file.Source, file => file.Current, StringComparer.OrdinalIgnoreCase);
        var failures = 0; var selected = Selected.ToHashSet(); var affected = photos.Where(row => mappings.ContainsKey(row.Document.FilePath)).ToArray();
        fillingEditor = true;
        try
        {
            foreach (var row in affected)
            {
                var index = photos.IndexOf(row); var wasSelected = selected.Contains(row); photos.RemoveAt(index);
                try
                {
                    var document = await PhotoDocument.LoadAsync(Tool(), mappings[row.Document.FilePath],inspect:true);
                    var replacement = new PhotoRow(document){Imported=row.Imported}; photos.Insert(index, replacement);
                    if (wasSelected) Photos.SelectedItems.Add(replacement);
                }
                catch (Exception) { failures++; }
            }
        }
        finally { fillingEditor = false; previousSelection = Selected; }
        ClearMatchMarker(); _ = PostPhotosAsync(); return failures;
    }
    private async void ExecuteRename(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired || frozenRenamePlan is not { } plan) return;
        if (RenameHasDraft(plan.Files.Select(file => file.Source))) { RenameStatus.Text = "存在草稿或未应用输入，未执行更名。"; return; }
        frozenRenamePlan = null; BeginOperation();
        try
        {
            var result = await Task.Run(() => RenameExecutor.ExecuteAsync(plan, RenameJournalDirectory, operation!.Token,
                (completed,total) => Dispatcher.BeginInvoke(() => { if (busy && !operation!.IsCancellationRequested) RenameStatus.Text = $"更名／核验：{completed}/{total}；取消后按记录恢复。"; })));
            renameRecoveryRequired = !result.Complete && result.Files.Any(file=>file.Current!=file.Source);
            var reloadFailures = await RefreshRenamedPhotos(result);
            RenamePreview.ItemsSource = result.Files; RenameViewChanged(this,new RoutedEventArgs());
            if (result.Journal.Length > 0) RenameJournalPath.Text = result.Journal;
            RenameStatus.Text = result.Complete ? "更名及内容核验完成；执行记录已保存，可按记录恢复。" : "更名部分完成：" + result.Error + " 实际名称与记录已保留；恢复前不可编辑元数据。";
            if (reloadFailures > 0) RenameStatus.Text += $" {reloadFailures}个上下文未能重读，磁盘文件保留，实际路径见记录。";
        }
        catch (OperationCanceledException) { RenameStatus.Text = "执行准备已取消，未移动文件。"; }
        catch (Exception error) { RenameStatus.Text = "未开始更名：" + error.Message; }
        finally { EndOperation(); }
    }
    private async void RestoreRename(object sender, RoutedEventArgs e)
    {
        if (busy || RenameJournalPath.Text.Trim().Length == 0) return;
        try
        {
            var path = RenameJournalPath.Text.Trim(); var record = RenameExecutor.ReadJournal(path);
            if (RenameHasDraft(record.Files.Select(file => file.Current))) { RenameStatus.Text = "相关文件存在草稿或未应用输入，未恢复更名。"; return; }
            frozenRenamePlan = null; BeginOperation();
            try
            {
                var result = await Task.Run(() => RenameExecutor.RestoreAsync(path, RenameJournalDirectory, operation!.Token));
                renameRecoveryRequired = !result.Complete && result.Files.Any(file=>file.Current!=file.Source);
                var reloadFailures = await RefreshRenamedPhotos(result); RenamePreview.ItemsSource = result.Files; RenameViewChanged(this,new RoutedEventArgs());
                if (result.Journal.Length > 0) RenameJournalPath.Text = result.Journal;
                RenameStatus.Text = result.Complete ? "按执行记录恢复完成；内容核验通过，恢复动作也有新记录。" : "恢复部分完成：" + result.Error + " 实际名称见当前记录。";
                if (reloadFailures > 0) RenameStatus.Text += $" {reloadFailures}个上下文未能重读，磁盘文件保留，实际路径见记录。";
            }
            finally { EndOperation(); }
        }
        catch (OperationCanceledException) { RenameStatus.Text = "恢复准备已取消，未移动文件。"; }
        catch (Exception error) { RenameStatus.Text = "未开始恢复：" + error.Message; }
    }
    private IReadOnlyList<RenameRule> ReadRenameRules() => RenamePlan.ParseRules(RenameRules.Text);
    private async void RenameRulesChanged(object sender, RoutedEventArgs e)
    {
        if (RenameRules is null || RenamePreview is null || RenameStatus is null || RenameProcessingSort is null || RenameViewOrder is null || RenameViewFilter is null || fillingRenameControls) return;
        renameRevision++; frozenRenamePlan = null; UpdateRenameButtons();RefreshSchemeControls();
        var revision=renameRevision;
        try
        {
            var rules = ReadRenameRules();
            var roots=RenameSelection().Select(r=>RenameGroup.Key(r.Document.FilePath)).ToHashSet(StringComparer.OrdinalIgnoreCase); renameGroups=renameGroups.Where(g=>g.Members.Any(m=>roots.Contains(RenameGroup.Key(m.Path)))).ToArray();await RenderRenameGroupsAsync();
            if(revision!=renameRevision)return;RenameStatus.Text = "名称预览已更新；请检查冲突并冻结计划后执行。";
        }
        catch (Exception error) { if(revision!=renameRevision)return;RenamePreview.ItemsSource = null; RenameStatus.Text = "未生成预览：" + error.Message; }
    }
    private async void FreezeRename(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired || Selected.Length == 0) return;
        frozenRenamePlan = null; UpdateRenameButtons();
        if (Selected.Any(row => row.Document.Draft.Count > 0) || Fields.Any(field => field.Apply.IsChecked == true))
        { RenameStatus.Text = "所选照片有草稿或未应用输入；请先保存副本并撤销源草稿，或明确撤销后再冻结。"; return; }
        try
        {
            var selected = RenameSelection(); var paths = selected.Select(row => row.Document.FilePath).ToArray(); var rules = ReadRenameRules();
            var revision = ++renameRevision; BeginOperation();
            try
            {
                await ReadRenameGroupsAsync(operation!.Token);await PrepareRenameDatesAsync(operation.Token); var included=IncludedRenameGroups();if(included.Length==0)throw new ArgumentException("筛选后无参与组。");if(included.Any(g=>g.Members.Any(m=>m.MetadataFailed)))throw new IOException("参与组元数据读取失败，不能当成缺失冻结。");var targets=included.SelectMany((g,i)=>g.Members.Select(m=>(Source:m.Path,Name:Path.GetFileNameWithoutExtension(RenamePlan.ApplyVerified(g.Leader.Name,rules,i,key=>RenameNameField(g,key),rules.Any(r=>r.Kind is "date-set" or "date-prefix")?RenameVerifiedDate(g):null))+Path.GetExtension(m.Path)))).ToArray(); var plan=await RenamePlan.BuildTargetsAsync(targets,operation!.Token,includeSidecars:false); foreach(var member in included.SelectMany(g=>g.Members))if(plan.Files.Single(f=>f.Source.Equals(member.Path,StringComparison.OrdinalIgnoreCase)).Hash!=member.Hash)throw new IOException("预览元数据读取后源内容改变。");
                if (revision != renameRevision) return;
                if (RenameHasDraft(plan.Files.Select(file=>file.Source))) throw new InvalidOperationException("计划中的照片或旁车有草稿，未冻结。");
                var versions = plan.Files.ToDictionary(file=>file.Source,file=>file.Hash,StringComparer.OrdinalIgnoreCase);
                foreach (var row in selected.Where(row=>versions.ContainsKey(row.Document.FilePath)))
                {
                    if (!Path.GetExtension(row.Document.FilePath).Equals(".xmp",StringComparison.OrdinalIgnoreCase) && (row.Document.SidecarPath is not null) != File.Exists(Path.ChangeExtension(row.Document.FilePath,".xmp"))) throw new IOException("同名旁车关系已改变，请重新导入。");
                    if (versions[row.Document.FilePath] != row.Document.SourceHash) throw new IOException("照片已在外部改变，请重新导入。");
                    if (row.Document.SidecarPath is { } sidecar && versions[sidecar] != row.Document.SidecarHash) throw new IOException("旁车已在外部改变，请重新导入。");
                }
                RenameGroups.ItemsSource=included; frozenRenamePlan = plan; RenamePreview.ItemsSource = plan.Files; RenameViewChanged(this,new RoutedEventArgs());
                RenameStatus.Text = $"已冻结{plan.Files.Count}个物理文件（包含旁车），冲突检查与SHA256读取通过；尚未更名。";
            }
            finally { EndOperation(); }
        }
        catch (OperationCanceledException) { frozenRenamePlan = null; RenameStatus.Text = "冻结已取消，未改文件。"; }
        catch (Exception error) { frozenRenamePlan = null; RenameStatus.Text = "计划未冻结：" + error.Message; }
    }
    private string[] recentTrackPaths = [];
    private void LoadTrackHistory()
    {
        try { recentTrackPaths = TrackHistory.Read(TrackHistory.DefaultPath); RecentTracks.ItemsSource = recentTrackPaths; if(recentTrackPaths.Length > 0) RecentTracks.SelectedIndex = 0; }
        catch (Exception) { TrackHistoryStatus.Text = "轨迹历史不可读取，未自动覆盖；当前会话仍可导入。"; }
    }
    private void LoadTrackSnapshots()
    {
        try { foreach(var snapshot in TrackSnapshots.Read(TrackSnapshots.DefaultPath))tracks.Add(new TrackRow(snapshot));if(tracks.Count>0)TrackList.SelectedIndex=0; }
        catch(Exception){TrackAdjustmentStatus.Text="调整记录不可读取，未覆盖；显式导入仍可查看源轨迹。";}
    }
    private async void ReadRecentTrack(object sender, RoutedEventArgs e)
    {
        if (!busy && RecentTracks.SelectedItem is string path) await ImportTracksAsync([path], reloadExisting:true);
    }
    private async Task RememberTrackAsync(string path)
    {
        try
        {
            // Preserve unreadable history rather than replacing it with this session's entries.
            var updated = await Task.Run(() => TrackHistory.RememberAndSave(TrackHistory.DefaultPath,path));
            recentTrackPaths = updated; RecentTracks.ItemsSource = recentTrackPaths; RecentTracks.SelectedIndex = 0;
            TrackHistoryStatus.Text = $"本机历史{recentTrackPaths.Length}项；重新读取会解析当前文件，不自动定位或写照片。";
        }
        catch (Exception) { TrackHistoryStatus.Text = "轨迹已导入，历史未保存；已有记录保持。"; }
    }
    private static bool IsTrack(string path) => Path.GetExtension(path).ToLowerInvariant() is ".gpx" or ".kml" or ".kmz";
    private async void ReadTracks(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Multiselect = true, Filter = "轨迹|*.gpx;*.kml;*.kmz" };
        if (dialog.ShowDialog(this) == true) await ImportTracksAsync(dialog.FileNames);
    }
    private async Task ImportTracksAsync(IEnumerable<string> paths, bool reloadExisting = false)
    {
        var files = paths.ToArray();
        if (busy || files.Length == 0 || !DiscardEditor()) return;
        BeginOperation(); var added = 0; var refreshed = 0; var skipped = 0; var failures = new List<string>(); var cancelled = false;
        try
        {
            foreach (var path in files)
            {
                operation!.Token.ThrowIfCancellationRequested();
                var full = Path.GetFullPath(path);
                var existing = tracks.FirstOrDefault(row => row.Path.Equals(full, StringComparison.OrdinalIgnoreCase));
                if (!IsTrack(full)) { skipped++; continue; }
                Status.Text = "读取轨迹：" + Path.GetFileName(full);
                try
                {
                    var source = await TrackSnapshots.ReadSourceAsync(full,operation.Token);
                    TrackSnapshot? saved=null;
                    try{saved=TrackSnapshots.Read(TrackSnapshots.DefaultPath).FirstOrDefault(r=>r.Path.Equals(full,StringComparison.OrdinalIgnoreCase));}
                    catch(Exception){TrackAdjustmentStatus.Text="调整记录不可读取，未覆盖；当前导入仅查看源轨迹。";}
                    var snapshot=existing?.Snapshot??saved??source;
                    if(snapshot.Original is null && saved is null && existing?.Snapshot.Original is null)snapshot=source;
                    var replacement = new TrackRow(snapshot){SourceUnavailable=snapshot.SourceHash!=source.SourceHash,Undo=existing?.Undo};
                    if(existing is not null&&!reloadExisting){existing.SourceUnavailable=existing.Snapshot.SourceHash!=source.SourceHash;skipped++;if(ReferenceEquals(TrackList.SelectedItem,existing)){InvalidateTrackAdjustment();ClearMatchMarker();RefreshTrackControls();}continue;}
                    if (existing is null) { tracks.Add(replacement); added++; }
                    else
                    {
                        var selected = ReferenceEquals(TrackList.SelectedItem,existing);
                        tracks[tracks.IndexOf(existing)] = replacement;
                        if(selected)TrackList.SelectedItem = replacement;
                        refreshed++;
                    }
                    await RememberTrackAsync(full);
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception error) { failures.Add(Path.GetFileName(full) + "：" + error.Message); }
            }
        }
        catch (OperationCanceledException) { cancelled = true; }
        finally { EndOperation(); }
        if (TrackList.SelectedIndex < 0 && tracks.Count > 0) TrackList.SelectedIndex = 0;
        Status.Text = $"轨迹{(cancelled ? "已取消" : "导入完成")}：新增{added}，刷新{refreshed}，跳过{skipped}，失败{failures.Count}。未改照片。";
        if (reloadExisting && failures.Count > 0) Status.Text += " 会话中原有轨迹保留，请勿将其当作本次成功回读。";
        ShowFailures(failures);
    }
    private async void TrackSelected(object sender, SelectionChangedEventArgs e)
    {
        InvalidateTrackAdjustment();
        var row = TrackList.SelectedItem as TrackRow;
        TrackInfo.Text = row is null ? "未选择轨迹。" : $"{row.Name}：{row.Data.Segments.Count}段，{row.Data.Segments.Sum(s => s.Count)}点；其中{row.Data.Segments.Sum(s => s.Count(p => p.Time is not null))}点有时间。";
        MatchResult.Text = "轨迹已切换；请重新预览匹配。尚未写入GPS。";
        ClearMatchMarker();
        RefreshTrackControls();await PostTrackAsync();
    }
    private void RemoveTrack(object sender, RoutedEventArgs e)
    {
        if (!busy && TrackList.SelectedItem is TrackRow row) { tracks.Remove(row); Status.Text = "轨迹已从会话移除，磁盘文件保留。"; }
    }
    private async Task PostTrackAsync(bool fit=true)
    {
        var revision = ++mapRevision; mapUpdate?.Cancel(); mapUpdate?.Dispose(); mapUpdate = new();
        if (!mapReady) return;
        var row = TrackList.SelectedItem as TrackRow; var cancellation = mapUpdate.Token;
        try
        {
            var data=trackAdjustmentRow==row&&trackAdjustmentPreview is not null?trackAdjustmentPreview:null;
            var payload = data is not null ? await Task.Run(()=>TrackMapPayload.Compare(row!.Data,data,row.Name,cancellation),cancellation) : row?.MapPayload ?? await Task.Run(() => TrackMapPayload.Build(row?.Data, row?.Name ?? "", cancellation), cancellation);
            if(data is null&&row is not null&&revision==mapRevision)row.MapPayload=payload;
            if (revision == mapRevision && !cancellation.IsCancellationRequested)
            { MapView.CoreWebView2.PostWebMessageAsJson(fit?payload:payload.Replace("\"type\":\"tracks\"","\"type\":\"tracks-no-fit\"")); PostPreview(); }
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { if(revision==mapRevision)TrackInfo.Text = "轨迹显示失败：" + error.Message; }
    }
    private async void MatchTrack(object sender, RoutedEventArgs e)
    {
        if (busy) return;
        ClearMatchMarker();var matchingRevision=++trackMatchRevision;trackMatchPending++;
        try
        {
            if (TrackList.SelectedItem is not TrackRow row) throw new InvalidOperationException("请先导入并选择轨迹。");
            if (Selected.Length != 1) throw new InvalidOperationException("请在元数据页选择一张照片。");
            var snapshot=row.Snapshot;var revision=matchingRevision;var selection=Selected;var time=TrackReader.ParseTimestamp(MatchTimeValue.Text.Trim());
            await TrackSnapshots.EnsureSourceAsync(snapshot);
            var result=await Task.Run(()=>snapshot.Data.Match(time));
            await TrackSnapshots.EnsureSourceAsync(snapshot);
            if(revision!=trackMatchRevision||currentPreview is not null||!ReferenceEquals(row.Snapshot,snapshot)||!ReferenceEquals(TrackList.SelectedItem,row)||!Selected.SequenceEqual(selection)||TrackReader.ParseTimestamp(MatchTimeValue.Text.Trim())!=time)return;
            row.SourceUnavailable=false;
            MatchResult.Text = result.Point is { } point ? $"{Selected[0].Name}：{point.Latitude:F6}, {point.Longitude:F6}，{result.Method}。仅预览，未加入GPS草稿。" : result.Reason;
            ClearPlacePreview(); clipboardGpsPreview = false; currentPreview = result.Point is { } matched ? new(matched.Longitude, matched.Latitude) : null;
            matchedTrackSource=result.Point is not null?snapshot:null;previewAltitude = result.Point?.Elevation; previewMethod = "GPS"; UpdateGpsButton();
            PostPreview();
        }
        catch (Exception error) { if(matchingRevision==trackMatchRevision&&currentPreview is null){ClearMatchMarker(); MatchResult.Text = "匹配未执行：" + error.Message;} }
        finally{trackMatchPending--;}
    }
    private void ClearMatchMarker()
    {
        InvalidateBatchTrack();trackMatchRevision++;matchedTrackSource=null;ClearPlacePreview(); clipboardGpsPreview = false; currentPreview = null; previewAltitude = null; previewMethod = "MANUAL"; UpdateGpsButton(); PostPreview();
    }
    private void PostPreview()
    {
        if (mapReady) MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { type = "match-preview", point = currentPreview, focus = batchTrackViewing }));
    }
    private void UpdateGpsButton() => GpsDraftButton.IsEnabled = !batchTrackViewing && !busy && !renameRecoveryRequired && currentPreview is not null && Selected.Length > 0 && Selected.All(row => row.Document.CanStage);
    private async void AddGpsDraft(object sender, RoutedEventArgs e)
    {
        var selected = Selected;var point=currentPreview;var revision=trackMatchRevision;
        try
        {
            if (batchTrackViewing || busy || renameRecoveryRequired || currentPreview is null || Selected.Length == 0 || Selected.Any(row => !row.Document.CanStage)) throw new InvalidOperationException("请选择可编辑照片，并先预览定位。");
            if(previewMethod=="GPS"&&!clipboardGpsPreview&&matchedTrackSource is {} source)await TrackSnapshots.EnsureSourceAsync(source);
            if(revision!=trackMatchRevision||!ReferenceEquals(point,currentPreview)||!Selected.SequenceEqual(selected)||selected.Any(r=>!r.Document.CanStage))throw new InvalidOperationException("定位或选择已改变，请重新预览。");
            var changes = PhotoDocument.PositionChanges(point, previewAltitude, previewMethod);
            foreach (var row in selected) row.Document.SetDraft(changes);
            RefreshPhotoRows(); RefreshSelection(); _ = PostPhotosAsync();
            MatchResult.Text = $"已为{selected.Length}张照片加入WGS-84 GPS草稿。未知海拔／定位时间清除旧XMP值；请在元数据页保存副本。";
            Status.Text = "GPS已加入可撤销草稿，原文件未修改。";
        }
        catch (Exception error) { if(revision==trackMatchRevision&&ReferenceEquals(point,currentPreview)&&Selected.SequenceEqual(selected)){ClearMatchMarker();Status.Text = "GPS草稿未应用：" + error.Message;} }
    }
    private async Task PostPhotosAsync()
    {
        var revision = ++photoRevision; photoMapUpdate?.Cancel(); photoMapUpdate?.Dispose(); photoMapUpdate = new();
        if (!mapReady) return;
        var selected = Selected.ToHashSet(); var markers = new List<PhotoMarker>();
        for (var index = 0; index < photos.Count; index++)
            if (photos[index].Document.Position() is { } position) markers.Add(new(index, photos[index].Name, position, selected.Contains(photos[index])));
        var focus = clipboardGpsPreview ? currentPreview : (TrackList.SelectedItem is null && Selected.Length == 1 ? Selected[0].Document.Position() : null);
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
        lastApply=null;
        if (busy) return;
        var files = paths.ToArray();
        if (files.Length == 0 || !DiscardEditor()) return;
        BeginOperation();
        var added = 0; var skipped = 0; var failures = new List<string>(); var cancelled = false;
        var importClock = System.Diagnostics.Stopwatch.StartNew();
        long metadataRequests=Interlocked.Read(ref ExifToolClient.RequestCount),dateHostRequests=Interlocked.Read(ref DateAdapter.StartedProcesses);
        try
        {
            var client = Tool();
            var known = photos.Select(row => row.Document.FilePath).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var pending = new List<string>();
            foreach (var path in files)
            {
                var full = Path.GetFullPath(path);
                if (!extensions.Contains(Path.GetExtension(full), StringComparer.OrdinalIgnoreCase) || !known.Add(full)) { skipped++; continue; }
                pending.Add(full);
            }
            foreach (var batch in pending.Chunk(32))
            {
                operation!.Token.ThrowIfCancellationRequested();
                Status.Text = $"读取：{added + failures.Count}/{pending.Count}，当前批次{batch.Length}个文件…";
                var readings = await PhotoDocument.LoadBatchAsync(client, batch, operation.Token,inspect:true);
                foreach (var reading in readings)
                    if (reading.Document is { } photo) { photos.Add(new(photo)); added++; }
                    else failures.Add(Path.GetFileName(reading.FilePath) + "：" + reading.Error);
                RefreshPhotoCount();
            }
        }
        catch (OperationCanceledException) { cancelled = true; }
        catch (Exception error) { failures.Add(error.Message); }
        finally { EndOperation(); }
        if (Photos.SelectedIndex < 0 && photos.Count > 0) Photos.SelectedIndex = 0;
        _ = PostPhotosAsync();
        importMilliseconds=importClock.Elapsed.TotalMilliseconds;importExifToolRequests=Interlocked.Read(ref ExifToolClient.RequestCount)-metadataRequests;importDateHostRequests=Interlocked.Read(ref DateAdapter.StartedProcesses)-dateHostRequests;
        Status.Text = $"{(cancelled ? "导入已取消" : "导入完成")}：新增 {added}，跳过 {skipped}，失败 {failures.Count}。原文件未修改。用时{importClock.Elapsed.TotalSeconds:F1}秒。";
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
        rereadSequence++;InvalidateDates();previousSelection = Selected; RenameRulesChanged(this, new RoutedEventArgs());
        RefreshSelection();
        RefreshMatchPhoto();
        _ = PostPhotosAsync();
    }
    private void RefreshMatchPhoto()
    {
        MatchPhotoInfo.Text = Selected.Length == 1 ? "匹配照片：" + Selected[0].Name + "；无时区时间须手动提供明确匹配时间。" : "单张手动时间匹配须选择一张照片；上方批量入口逐张使用照片拍摄时间。";
        RefreshMatchTime();
        MatchResult.Text = "照片选择已切换；请重新预览匹配。尚未写入GPS。";
        ClearMatchMarker();
    }
    private void RefreshMatchTime()
    {
        MatchTimeValue.Text = "";
        if (Selected.Length != 1) return;
        try
        {
            if (Selected[0].Document.VerifiedDate("XMP-exif:DateTimeOriginal")?.Instant() is { } time) MatchTimeValue.Text = time.ToString("O");
        }
        catch (ArgumentException) { }
    }
    private void RefreshPhotoRows()
    {
        var selected = Selected;
        fillingEditor = true;
        try { System.Windows.Data.CollectionViewSource.GetDefaultView(photos).Refresh(); }
        finally { fillingEditor = false; }
        if (!Selected.SequenceEqual(selected))
        {
            InvalidateDates();previousSelection = Selected; RefreshMatchPhoto(); RenameRulesChanged(this, new RoutedEventArgs());
        }
    }
    private bool changingPhotoView;
    private string photoSearch = "";
    private int photoFilter, photoSort;
    private void PhotoViewChanged(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded || changingPhotoView) return;
        if (busy || InspectorHasInput())
        {
            changingPhotoView = true;
            try { PhotoSearch.Text = photoSearch; PhotoFilter.SelectedIndex = photoFilter; PhotoSort.SelectedIndex = photoSort; }
            finally { changingPhotoView = false; }
            Status.Text = "请先结束任务或将输入加入草稿，再筛选/排序。"; return;
        }
        photoSearch = PhotoSearch.Text; photoFilter = PhotoFilter.SelectedIndex; photoSort = PhotoSort.SelectedIndex;
        if(!restoringSettings && !settings.PhotoSort[0].Equals(sortOptions[photoSort])){settings=settings with{Sorts=[sortOptions[photoSort]]};SaveSettings();}
        ApplyPhotoView();
        RefreshSelection(); Status.Text = "列表已更新；隐藏照片与草稿仍保留在会话中。";
    }
    private void RefreshPhotoCount() => PhotoCount.Text = $"显示{Photos.Items.Count}／总计{photos.Count}；草稿{photos.Count(row => row.Document.Draft.Count > 0)}";
    private void RefreshSelection()
    {
        fillingEditor = true;
        RefreshPhotoCount();
        RefreshInspector();
        if(RereadPhotosButton is not null)RereadPhotosButton.IsEnabled=!busy&&!renameRecoveryRequired&&Selected.Length>0;
        SyncSaveMode();
        var selected = Selected;
        var editable = !renameRecoveryRequired && selected.Length > 0 && selected.All(p => p.Document.CanStage);
        Editor.IsEnabled = !busy && editable;
        if (PresetControls is not null) PresetControls.IsEnabled = !busy && !renameRecoveryRequired;
        RefreshPresetLibraryControls();
        if (PresetApplyButton is not null) PresetApplyButton.IsEnabled = !busy && editable;
        UpdateGpsButton(); UpdateRenameButtons();RefreshBatchTrackControls();
        DraftActions.IsEnabled = !busy && !renameRecoveryRequired;
        FieldApplyButton.IsEnabled=editable;ClearSelectedDraftButton.IsEnabled=editable;UndoLastApplyButton.IsEnabled=!busy&&!renameRecoveryRequired&&LastApplyCurrent();
        DatePlanApplyButton.IsEnabled=CsvApplyButton.IsEnabled=!busy&&editable;
        DateMode.IsEnabled=CsvPath.IsEnabled=!busy;
        foreach(var box in new[]{DateYears,DateMonths,DateDays,DateHours,DateMinutes,DateSeconds,DateStart,DateEnd,DateStep,DateReplaceYear,DateReplaceMonth,DateReplaceDay,DateReplaceHour,DateReplaceMinute,DateReplaceSecond,DateFilenamePattern,DateFilenameTemplate})box.IsEnabled=!busy;
        SaveButton.IsEnabled = !busy && !renameRecoveryRequired && selected.Any(p => p.Document.Draft.Count > 0);
        RemoveButton.IsEnabled = !busy && selected.Length > 0;
        SelectionInfo.Text = selected.Length == 0 ? "请选择照片。Ctrl / Shift 可多选。" :
            $"已选 {selected.Length} 张；{selected.Count(p => p.Document.Draft.Count > 0)} 张有草稿。" +
            (selected.Length == 1 ? (selected[0].Document.SidecarPath is null ? "XMP 来源：文件内嵌。" : "XMP 来源：同名旁车。") : "混合值显示为空；只应用勾选字段。") +
            (editable ? "" : "所选包含只读格式，暂不支持编辑。");
        if(busy||preserveBatchEditor){fillingEditor=false;return;}
        foreach (var (tag, apply, value) in Fields)
        {
            var values = selected.Select(p => p.Document.Value(tag)).Distinct().ToArray();
            value.Text = values.Length == 1 ? values[0] : ""; apply.IsChecked = false;
        }
        RefreshInspector();
        fillingEditor = false;
        _ = RefreshPhotoPreviewAsync();
    }
    private void PhotoPreviewTabChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ReferenceEquals(e.Source,sender)) _ = RefreshPhotoPreviewAsync();
    }
    private async Task RefreshPhotoPreviewAsync()
    {
        if (!IsLoaded || PhotoPreviewTab is null) return;
        var photo = Selected.Length == 1 ? Selected[0].Document : null;
        if (ReferenceEquals(photo,previewDocument)) return;
        photoPreviewRequest?.Cancel(); photoPreviewRequest?.Dispose(); photoPreviewRequest = null; photoPreviewRevision++;
        PhotoPreviewImage.Source = null; previewDocument = null;
        if (photo is null) { PhotoPreviewStatus.Text = "请选择一张JPEG/PNG/DNG照片进行预览。"; return; }
        if (!PhotoPreviewTab.IsSelected) return;
        previewDocument = photo; var revision = photoPreviewRevision;
        photoPreviewRequest = new(); var token = photoPreviewRequest.Token;
        PhotoPreviewStatus.Text = "正在读取本机预览…";
        try
        {
            await photoPreviewGate.WaitAsync(token);
            System.Windows.Media.Imaging.BitmapSource preview;
            try
            {
                var orientation = photo.Embedded.TryGetProperty("IFD0:Orientation",out var field) && int.TryParse(field.ToString(),out var value) && value is >= 1 and <= 8 ? value : 1;
                var client = photo.FileType == "DNG" ? Tool() : null;
                preview = await Task.Run(async () => photo.FileType == "DNG"
                    ? await PhotoPreview.LoadDngAsync(client!,photo.FilePath,photo.SourceHash,orientation,token)
                    : PhotoPreview.Load(photo.FilePath,photo.FileType,photo.SourceHash,orientation),token);
            }
            finally { photoPreviewGate.Release(); }
            if (!IsLoaded || token.IsCancellationRequested || revision != photoPreviewRevision) return;
            PhotoPreviewImage.Source = preview;
            PhotoPreviewStatus.Text = $"{Path.GetFileName(photo.FilePath)} · {(photo.FileType == "DNG" ? "内嵌JPEG预览" : "本机预览")}{preview.PixelWidth}×{preview.PixelHeight}；不修改原图。";
        }
        catch (OperationCanceledException) { }
        catch (Exception error)
        {
            if (!IsLoaded || token.IsCancellationRequested || revision != photoPreviewRevision) return;
            previewDocument = null; PhotoPreviewStatus.Text = "预览不可用：" + error.Message;
        }
    }
    private void EditorChanged(object sender, TextChangedEventArgs e)
    {
        if (fillingEditor || !IsLoaded) return;
        InvalidateDates();
        foreach (var (_, apply, value) in Fields) if (ReferenceEquals(value, sender)) apply.IsChecked = true;
    }
    private bool DiscardEditor()
    {
        if (!Fields.Any(f => f.Apply.IsChecked == true)) return true;
        return MessageBox.Show(this, "输入尚未加入草稿。放弃这次输入？", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) == MessageBoxResult.Yes;
    }
    private void CopyGpsClipboard(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired) return;
        try
        {
            if (Fields.Any(field => field.Apply.IsChecked == true)) throw new InvalidOperationException("请先将输入加入草稿再复制当前值。");
            var selected = Selected;
            if (selected.Length != 1 || selected[0].Document.Position() is not { } point) throw new InvalidOperationException("请选择一张有可用WGS-84坐标的照片。");
            Clipboard.SetText(MetadataClipboard.CopyGps(point));
            Status.Text = "GPS坐标已复制（包含坐标草稿）；不复制海拔、测量时间或地区。";
        }
        catch (Exception error) { Status.Text = "GPS未复制：" + error.Message; }
    }
    private void PreviewGpsClipboard(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired) return;
        try
        {
            if (Selected.Length == 0 || Selected.Any(row => !row.Document.CanStage)) throw new InvalidOperationException("请选择可编辑的目标照片。");
            if (Fields.Any(field => field.Apply.IsChecked == true)) throw new InvalidOperationException("请先处理未应用字段输入。");
            if (!Clipboard.ContainsText()) throw new InvalidOperationException("剪贴板没有可用文字。");
            var point = MetadataClipboard.ReadGps(Clipboard.GetText());
            InvalidateBatchTrack();ClearPlacePreview(); clipboardGpsPreview = false; currentPreview = point; previewAltitude = null; previewMethod = "MANUAL";
            clipboardGpsPreview = true; WorkspaceTabs.SelectedIndex = 1; UpdateGpsButton(); PostPreview(); _ = PostPhotosAsync();
            MatchResult.Text = $"剪贴板WGS-84坐标预览：{point.Latitude:F8}, {point.Longitude:F8}；目标{Selected.Length}张。核对后明确加入GPS草稿；海拔/测量时间未知，会清除旧XMP值。";
            Status.Text = "剪贴板GPS仅预览；尚未加入草稿或写入照片。";
        }
        catch (Exception error) { Status.Text = "GPS剪贴板未预览：" + error.Message; }
    }
    private void CopyField(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired) return;
        try
        {
            if (Fields.Any(field => field.Apply.IsChecked == true)) throw new InvalidOperationException("请先将输入加入草稿再复制当前值。");
            if (ClipboardField.SelectedValue is not string tag) throw new InvalidOperationException("请选择复制字段。");
            var value = MetadataClipboard.CommonValue(Selected.Select(row => row.Document.Value(tag)));
            Clipboard.SetText(value); Status.Text = "原始字段值已复制到系统剪贴板；未修改照片。";
        }
        catch (Exception error) { Status.Text = "字段未复制：" + error.Message; }
    }
    private async void PasteFields(object sender, RoutedEventArgs e)
    {
        if (busy || renameRecoveryRequired) return;
        try
        {
            if (Selected.Length == 0 || Selected.Any(row => !row.Document.CanStage)) throw new InvalidOperationException("请选择可编辑照片。");
            if (!Clipboard.ContainsText()) throw new InvalidOperationException("剪贴板没有可用文字。");
            var clipboard=Clipboard.GetText();var targets=Fields.Where(field=>field.Apply.IsChecked==true).Select(field=>field.Tag).ToArray();var selected=Selected;
            var changes=MetadataClipboard.Prepare(clipboard,targets);
            await ValidateEditorDatesAsync(changes);
            if(!Selected.SequenceEqual(selected)||!Clipboard.ContainsText()||Clipboard.GetText()!=clipboard||!Fields.Where(field=>field.Apply.IsChecked==true).Select(field=>field.Tag).SequenceEqual(targets))throw new InvalidOperationException("剪贴板、字段或选择已改变，未填入。");
            fillingEditor = true;
            try { foreach (var (tag, _, value) in Fields) if (changes.TryGetValue(tag, out var text)) value.Text = text; }
            finally { fillingEditor = false; }
            Status.Text = "剪贴板文字已填入勾选字段；请核对再加入草稿，尚未写入文件。";
        }
        catch (Exception error) { Status.Text = "剪贴板未填入：" + error.Message; }
    }

    private void FillEditor(IReadOnlyDictionary<string,string> changes)
    {
        fillingEditor = true;
        try
        {
            foreach(var (tag,apply,value) in Fields)
            {
                apply.IsChecked = changes.ContainsKey(tag);
                if(changes.TryGetValue(tag,out var text))value.Text = text;
            }
        }
        finally { fillingEditor = false; }
    }
    private void ChooseXmp(object sender,RoutedEventArgs e)
    {
        if(busy)return;
        var dialog = new OpenFileDialog { Title="选择XMP字段来源",Filter="XMP|*.xmp",CheckFileExists=true };
        if(dialog.ShowDialog(this)==true)XmpPath.Text = dialog.FileName;
    }
    private async void ImportXmp(object sender,RoutedEventArgs e)
    {
        if(busy || renameRecoveryRequired)return;
        try
        {
            if(Selected.Length == 0 || Selected.Any(row=>!row.Document.CanStage))throw new InvalidOperationException("请先选择可编辑照片。");
            if(Fields.Any(field=>field.Apply.IsChecked == true))throw new InvalidOperationException("请先将现有输入加入草稿或撤销输入。");
            var path = XmpPath.Text; var selected = Selected; XmpImport result;
            BeginOperation();
            try { result = await Task.Run(()=>MetadataXmp.ImportAsync(Tool(),path,operation!.Token)); }
            finally { EndOperation(); }
            if(path != XmpPath.Text || !Selected.SequenceEqual(selected))throw new InvalidOperationException("路径或选择已改变，请重新载入。");
            FillEditor(result.Changes);
            XmpPreview.Text = string.Join("\n",result.Changes.Select(field=>field.Key+" → "+field.Value))+
                (result.IgnoredTags.Count == 0 ? "" : "\n未导入字段："+string.Join("、",result.IgnoredTags));
            if(XmpPreview.Text.Length > 65536)XmpPreview.Text = XmpPreview.Text[..65536]+"\n显示已截短；编辑区包含全部已验证字段。";
            Status.Text = "XMP已载入编辑区，缺失字段保持；请核对并加入草稿，尚未写照片。";
        }
        catch(OperationCanceledException){Status.Text="XMP载入已取消，编辑区未改变。";}
        catch(Exception error){Status.Text="XMP未载入："+error.Message;}
    }
    private async void ExportXmp(object sender,RoutedEventArgs e)
    {
        if(busy || renameRecoveryRequired)return;
        try
        {
            if(Selected.Length != 1)throw new InvalidOperationException("完整XMP导出请选择一个文件。");
            if(Fields.Any(field=>field.Apply.IsChecked == true))throw new InvalidOperationException("请先将输入加入草稿，再导出。");
            var photo = Selected[0].Document;
            var dialog = new SaveFileDialog { Title="导出完整XMP及草稿（不覆盖）",Filter="XMP|*.xmp",DefaultExt=".xmp",FileName=Path.GetFileNameWithoutExtension(photo.FilePath)+".xmp",OverwritePrompt=false };
            if(dialog.ShowDialog(this)!=true)return;
            BeginOperation();
            try { await Task.Run(()=>MetadataXmp.ExportAsync(Tool(),photo,dialog.FileName,operation!.Token)); }
            finally { EndOperation(); }
            Status.Text="XMP已导出，包含当前草稿；原文件和会话草稿保留。";
        }
        catch(OperationCanceledException){Status.Text="XMP导出已取消，未交付文件。";}
        catch(Exception error){Status.Text="XMP未导出："+error.Message;}
    }

    private CancellationTokenSource? dateRequest;
    private int dateRevision,datePending;
    private void InvalidateDates() { dateRevision++;dateRequest?.Cancel(); }
    private void DatePlanChanged(object sender,RoutedEventArgs e) {
        InvalidateDates();if(DateFilenameOptions is null)return;
        DateShiftOptions.Visibility=DateMode.SelectedIndex==0?Visibility.Visible:Visibility.Collapsed;
        DateReplaceOptions.Visibility=DateMode.SelectedIndex==2?Visibility.Visible:Visibility.Collapsed;
        DateStartOptions.Visibility=DateMode.SelectedIndex is 1 or 3?Visibility.Visible:Visibility.Collapsed;
        DateSequenceOptions.Visibility=DateMode.SelectedIndex==1?Visibility.Visible:Visibility.Collapsed;
        DateDistributionOptions.Visibility=DateMode.SelectedIndex==3?Visibility.Visible:Visibility.Collapsed;
        DateFilenameOptions.Visibility=DateMode.SelectedIndex==4?Visibility.Visible:Visibility.Collapsed;
    }
    private static string DateFailureText(Exception error)=>error is OperationCanceledException ? "已取消，草稿未改变。" : error is DateFailure failure ? failure.Code switch {
        "canceled"=>"已取消，草稿未改变。", "timeout"=>"日期计算超时，草稿未改变。",
        "startFailed" or "dependencyMissing"=>"日期宿主或运行库不可用，请按Windows构建说明检查；未回退旧算法。",
        "staleRevision"=>"状态已改变，请重新应用。", _=>"日期协议或进程失败："+failure.Code
    }:error.Message;
    private void CsvChanged(object sender,TextChangedEventArgs e)=>InvalidateDates();
    private void ChooseCsv(object sender, RoutedEventArgs e)
    {
        if (busy) return;
        var dialog = new OpenFileDialog { Title = "选择PhotoTrail回导CSV", Filter = "CSV|*.csv", CheckFileExists = true };
        if (dialog.ShowDialog(this) == true) CsvPath.Text = dialog.FileName;
    }
    private void ExportRoundtripCsv(object sender, RoutedEventArgs e) => ExportCsv(false);
    private void ExportDisplayCsv(object sender, RoutedEventArgs e) => ExportCsv(true);
    private void ExportCsv(bool displayOnly)
    {
        if (busy || renameRecoveryRequired) return;
        try
        {
            if (Fields.Any(field => field.Apply.IsChecked == true)) throw new InvalidOperationException("请先将输入加入草稿。");
            var text = MetadataCsv.Export(MetadataCsv.Snapshot(Selected.Select(row => row.Document).ToArray()), displayOnly);
            var dialog = new SaveFileDialog { Title = "导出CSV（不覆盖）", Filter = "CSV|*.csv", DefaultExt = ".csv", FileName = displayOnly ? "PhotoTrail-display.csv" : "PhotoTrail.csv", OverwritePrompt = false };
            if (dialog.ShowDialog(this) != true) return;
            MetadataCsv.WriteNew(dialog.FileName, text);
            Status.Text = "CSV已导出；未修改照片。";
        }
        catch (Exception error) { Status.Text = "CSV未导出：" + error.Message; }
    }
    private void UndoDraft(object sender, RoutedEventArgs e)
    {
        if(busy||renameRecoveryRequired)return;lastApply=null;
        foreach (var row in Selected) row.Document.ClearDraft();
        RefreshPhotoRows(); RefreshSelection(); Status.Text = "所选全部草稿已清空。原文件未修改。";
        RefreshMatchTime(); ClearMatchMarker(); _ = PostPhotosAsync();
    }
    private void RemovePhotos(object sender, RoutedEventArgs e)
    {
        if (busy || !DiscardEditor()) return;
        var selected = Selected;
        if (selected.Any(p => p.Document.Draft.Count > 0) &&
            MessageBox.Show(this, "移除会放弃所选草稿，磁盘文件保留。继续？", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        fillingEditor = true;
        foreach (var row in selected) photos.Remove(row);
        previousSelection = Selected; RenameRulesChanged(this, new RoutedEventArgs()); fillingEditor = false; RefreshSelection();
        ClearMatchMarker(); _ = PostPhotosAsync();
        Status.Text = $"已从列表移除 {selected.Length} 项，磁盘文件保留。";
    }
    private void ChooseOutput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "选择保存副本的文件夹" };
        if (dialog.ShowDialog(this) == true) OutputFolder.Text = dialog.FolderName;
    }
    private void SaveCopies(object sender, RoutedEventArgs e)=>PrepareSave(Selected.Select(r=>r.Document),SaveMode.Copy,SaveScope.All);
    private void ShowFailures(List<string> failures)
    {
        if (failures.Count > 0) MessageBox.Show(this, string.Join("\n", failures), "任务结果", MessageBoxButton.OK, MessageBoxImage.Warning);
    }
    private void BeginOperation()
    {
        InvalidateDates();
        InvalidateBatchTrack();busy = true;RefreshTrackControls(); operation?.Dispose(); operation = new();
        PhotoSearch.IsEnabled = PhotoFilter.IsEnabled = PhotoSort.IsEnabled = false;
        ReadButton.IsEnabled = FolderButton.IsEnabled = OutputButton.IsEnabled = OutputFolder.IsEnabled = Photos.IsEnabled = false;
        TrackReadButton.IsEnabled = TrackList.IsEnabled = TrackRemoveButton.IsEnabled = MatchButton.IsEnabled = MapRetryButton.IsEnabled = false;
        RefreshSelection();
    }
    private void EndOperation()
    {
        busy = false;
        PhotoSearch.IsEnabled = PhotoFilter.IsEnabled = PhotoSort.IsEnabled = true;
        ReadButton.IsEnabled = FolderButton.IsEnabled = OutputButton.IsEnabled = OutputFolder.IsEnabled = Photos.IsEnabled = true;
        TrackReadButton.IsEnabled = TrackList.IsEnabled = TrackRemoveButton.IsEnabled = MatchButton.IsEnabled = true; MapRetryButton.IsEnabled = !mapInitializing;
        RefreshSelection();RefreshTrackControls();
    }
    private void CancelRead(object sender, RoutedEventArgs e) { batchTrackCancelTicks=System.Diagnostics.Stopwatch.GetTimestamp();InvalidateBatchTrack(); InvalidateTrackAdjustment();InvalidateDates();dependencyCheck?.Cancel(); operation?.Cancel(); Status.Text=busy?"正在取消任务…":"应用已取消或失效，草稿未改变。"; }
    private void WindowClosing(object? sender, CancelEventArgs e)
    {
        if(batchTrackRequest is not null){batchTrackRequest.Cancel();e.Cancel=true;Status.Text="正在取消匹配任务；结束后可关闭。";return;}
        if(datePending>0){InvalidateDates();e.Cancel=true;Status.Text="正在取消日期任务；结束后可关闭。";return;}
        if (checkingEnvironment) { dependencyCheck?.Cancel(); e.Cancel = true; DependencyStatus.Text = "正在取消环境检查；结束后可关闭。"; return; }
        if (busy) { operation?.Cancel(); e.Cancel = true; Status.Text = "正在取消任务；结束后可关闭。"; return; }
        if(presetEditorDirty||PresetChainDirty){
            if(MessageBox.Show(this,"存在未编排参数或尚未保存入库的预设链。明确放弃预设编辑并继续退出？（不会自动写库）","未保存元数据预设",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)!=MessageBoxResult.Yes){e.Cancel=true;return;}
        }
        if (photos.Any(p => p.Document.Draft.Count > 0) || Fields.Any(f => f.Apply.IsChecked == true))
            e.Cancel = MessageBox.Show(this, "存在未撤销的草稿或未应用输入。放弃并退出？保存的副本仍保留。", "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes;
    }
    private void WindowClosed(object? sender, EventArgs e) { renameDateValidation?.Cancel(); trackMatchRevision++;InvalidateTrackAdjustment(); photoPreviewRequest?.Cancel(); photoPreviewRevision++; PhotoPreviewImage.Source = null; dependencyCheck?.Cancel(); operation?.Cancel(); renameRevision++; SuspendMap(); GoogleKeyInput.Clear(); MapView.Dispose(); }
    private void MapSelected(object sender, SelectionChangedEventArgs e)
    {
        if (ReferenceEquals(e.Source, WorkspaceTabs) && IsLoaded && WorkspaceTabs.SelectedIndex == 1)
            MapLoaded(sender, e);
    }
    private void SuspendMap()
    {
        ClearPlacePreview(); mapReady = false; mapRevision++; photoRevision++;
        mapUpdate?.Cancel(); photoMapUpdate?.Cancel();
    }
    private void RetryMap(object sender, RoutedEventArgs e)
    {
        if (busy || mapInitializing) return;
        SuspendMap();
        Status.Text = "正在重载地图；照片、轨迹和草稿保留。";
        try
        {
            if (mapNeedsReplacement)
            {
                var previous = MapView; var parent = (Panel)previous.Parent; var index = parent.Children.IndexOf(previous);
                previous.Dispose(); parent.Children.RemoveAt(index); UnregisterName("MapView");
                MapView = new Microsoft.Web.WebView2.Wpf.WebView2 { Name = "MapView" };
                RegisterName("MapView", MapView); MapView.Loaded += MapLoaded;
                mapStarted = mapConfigured = mapNeedsReplacement = false;
                parent.Children.Insert(index, MapView);
            }
            if (mapConfigured) MapView.CoreWebView2.Navigate(currentMapPage);
            else { mapStarted = false; MapLoaded(sender, e); }
        }
        catch (Exception error) { Status.Text = "地图重载失败：" + error.Message; }
    }
    private async void MapLoaded(object sender, RoutedEventArgs e)
    {
        if (mapStarted || mapNeedsReplacement || WorkspaceTabs.SelectedIndex != 1) return;
        mapStarted = mapInitializing = true; MapRetryButton.IsEnabled = false;
        try
        {
            var cache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "WindowsValidation", "WebView2");
            // WaitAsync does not cancel native startup; a timed-out control must be replaced on retry.
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: cache).WaitAsync(TimeSpan.FromSeconds(15));
            await MapView.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(15));
            if (!IsLoaded) return;
            if (!mapConfigured)
            {
                MapView.CoreWebView2.SetVirtualHostNameToFolderMapping("phototrail.local", Path.Combine(AppContext.BaseDirectory, "Web"), CoreWebView2HostResourceAccessKind.DenyCors);
                MapView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                MapView.CoreWebView2.Settings.AreDevToolsEnabled = false;
                MapView.CoreWebView2.Settings.AreHostObjectsAllowed = false;
                MapView.CoreWebView2.NavigationStarting += (_, args) =>
                {
                    args.Cancel = args.Uri != currentMapPage;
                    if (!args.Cancel) SuspendMap();
                };
                MapView.CoreWebView2.NewWindowRequested += (_, args) => args.Handled = true;
                var configuredView = MapView;
                MapView.CoreWebView2.ProcessFailed += (_, args) =>
                {
                    var kind = args.ProcessFailedKind;
                    if (kind is not (CoreWebView2ProcessFailedKind.BrowserProcessExited or CoreWebView2ProcessFailedKind.RenderProcessExited or CoreWebView2ProcessFailedKind.RenderProcessUnresponsive)) return;
                    // Recreating a browser-closed control is required; do it after this callback returns.
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        if (!IsLoaded || !ReferenceEquals(configuredView, MapView)) return;
                        SuspendMap(); mapNeedsReplacement |= kind == CoreWebView2ProcessFailedKind.BrowserProcessExited;
                        if (!busy) Status.Text = "地图进程异常；点击重载地图恢复。照片、轨迹和草稿保留。";
                    }));
                };
                MapView.CoreWebView2.WebMessageReceived += (_, args) =>
                {
                    if (args.Source != currentMapPage) return;
                    if (MapMessage.IsGoogleBootstrap(args.Source, args.WebMessageAsJson))
                    {
                        try
                        {
                            var key = GoogleKeyStore.Load(GoogleKeyStore.DefaultPath) ?? throw new InvalidOperationException();
                            MapView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { type = "initialize", key }));
                        }
                        catch (Exception) { if (!busy) Status.Text = "Google密钥不可读取；请重新保存或切回默认地图。"; }
                        return;
                    }
                    if (MapPlace.TryRead(args.Source, args.WebMessageAsJson, out var place) && (placeQuery.Length==0?place!.Matches(placeRequest, currentPreview):place!.MatchesQuery(placeRequest,placeQuery)) && placePending)
                    {
                        placePending = false;
                        PlacePreview.Text = place.Status == "OK" ? "Google Maps · 地区预览：" + place.Summary : "Google Maps查询未得到地区：" + place.Status + "。未改照片。";
                        if(place.Query is not null&&place.Status=="OK"){InvalidateBatchTrack();currentPreview=place.Point;previewAltitude=null;previewMethod="MANUAL";clipboardGpsPreview=false;UpdateGpsButton();PostPreview();}
                        return;
                    }
                    if (MapMessage.IsError(args.Source, args.WebMessageAsJson))
                    {
                        if (!busy) Status.Text = "地图加载失败；检查网络后点击重载地图。照片和草稿保留。";
                        return;
                    }
                    if (MapMessage.IsReady(args.Source, args.WebMessageAsJson)) { mapReady = true; _ = PostTrackAsync(); _ = PostPhotosAsync(); }
                    if (busy || !mapReady) return;
                    if (MapMessage.TryPhoto(args.Source, args.WebMessageAsJson, out var id, out var revision) && revision == photoRevision && id < photos.Count)
                    {
                        if (!DiscardEditor()) return;
                        fillingEditor = true;
                        foreach (var (_, apply, _) in Fields) apply.IsChecked = false;
                        Photos.SelectedItems.Clear(); fillingEditor = false; Photos.SelectedItem = photos[id];
                    }
                    if (MapMessage.IsReady(args.Source, args.WebMessageAsJson)) Status.Text = currentMapPage == MapMessage.GooglePage ? "Google地图已加载；查询会产生Google请求。" : "默认地图已加载；点击地图只作坐标预览。";
                    if (MapMessage.TryPoint(args.Source, args.WebMessageAsJson, out var point)) { InvalidateBatchTrack(); ClearPlacePreview(); clipboardGpsPreview = false; currentPreview = point; previewAltitude = null; previewMethod = "MANUAL"; UpdateGpsButton(); MatchResult.Text = $"手动位置预览：{point!.Latitude:F6}, {point.Longitude:F6}。仅预览，未加入GPS草稿；海拔未知。"; Status.Text = "手动位置已更新；尚未写入照片。"; }
                };
                mapConfigured = true;
            }
            MapView.CoreWebView2.Navigate(currentMapPage);
        }
        catch (TimeoutException)
        {
            mapStarted = false; mapNeedsReplacement = true;
            if (!busy) Status.Text = "地图初始化超时；点击重载地图重新创建地图控件。照片、轨迹和草稿保留。";
        }
        catch (WebView2RuntimeNotFoundException)
        { if (!busy) Status.Text = "地图暂不可用：未找到WebView2 Runtime，请安装Microsoft Edge WebView2 Runtime后重试；元数据仍可使用。"; mapStarted = false; }
        catch (Exception error) { if (!busy) Status.Text = "地图暂不可用：" + error.Message; mapStarted = false; }
        finally { mapInitializing = false; MapRetryButton.IsEnabled = !busy; }
    }
    private sealed class TrackRow(TrackSnapshot snapshot) {
        public TrackSnapshot Snapshot {get;set;}=snapshot;
        public string Path=>Snapshot.Path;
        public TrackData Data=>Snapshot.Data;
        public TrackData? Undo {get;set;}
        public string? MapPayload {get;set;}
        public bool SourceUnavailable {get;set;}
        public string Name=>System.IO.Path.GetFileName(Path);
    }
    private record PhotoRow(PhotoDocument Document)
    {
        public long Imported {get;init;}=Interlocked.Increment(ref nextPhotoOrder);
        public (long Seconds,int Nanoseconds)? Captured {
            get=>Document.VerifiedDate(DatePagePreview.Field)?.SortProjection;
        }
        public string Name => Path.GetFileName(Document.FilePath);
        public string Summary => $"{Document.FileType} · {(Document.SidecarPath is null ? "内嵌" : "XMP旁车")} · 原标签{(Document.Inspection is null?"未知":Document.Inspection.Count(v=>v.Counted).ToString())}{(Document.InspectionError.Length>0?"（过期/失败）":"")} · {(Document.Draft.Count > 0 ? $"{MetadataInspector.PendingFields(Document)}项草稿" : "原始值")}";
    }
    private static long nextPhotoOrder;
}
