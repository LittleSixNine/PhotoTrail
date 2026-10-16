using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    Window? metadataWindow, settingsWindow, advancedWindow;
    bool changingM1Inspector, metadataClosing;
    static string M1Label(string key) => Application.Current?.MainWindow?.TryFindResource("M1." + key) as string ?? key;
    string M1Text(string key) => (string)FindResource("M1." + key);
    string M1Format(string key, params object[] values) => string.Format(CultureInfo.CurrentCulture, M1Text(key), values);

    void M1ToolbarSized(object sender, SizeChangedEventArgs e)
    {
        if (M1TopActions is null) return;
        bool narrow = e.NewSize.Width < 1000;
        Grid.SetRow(M1TopActions, narrow ? 1 : 0);
        Grid.SetColumn(M1TopActions, narrow ? 0 : 2);
        Grid.SetColumnSpan(M1TopActions, narrow ? 3 : 1);
    }
    void M1WorkspaceSelected(object sender, RoutedEventArgs e)
    {
        if (WorkspaceTabs is not null && sender is RadioButton { Tag: string index })
            WorkspaceTabs.SelectedIndex = int.Parse(index, CultureInfo.InvariantCulture);
    }
    void RefreshM1Shell()
    {
        if (M1DraftCount is null) return;
        RefreshM2MetadataLayout();
        RefreshM4Map();
        if (workflowBody is not null) workflowBody.IsEnabled = !busy && !renameRecoveryRequired;
        RefreshWorkflowContext();
        MetadataNavigation.IsChecked = WorkspaceTabs.SelectedIndex == 0;
        MapNavigation.IsChecked = WorkspaceTabs.SelectedIndex == 1;
        RenameNavigation.IsChecked = WorkspaceTabs.SelectedIndex == 2;
        SaveButton.Visibility = WorkspaceTabs.SelectedIndex == 2 ? Visibility.Collapsed : Visibility.Visible;
        M1TaskPanel.Visibility = busy || importRunning || checkingEnvironment ? Visibility.Visible : Visibility.Collapsed;
        ImportPending.Visibility = importRunning ? Visibility.Visible : Visibility.Collapsed;
        M1SelectionCount.Text = L10n.Message(M1Format("SelectedPhotoCount", Selected.Length, Photos.Items.Count));
        int pending = photos.Sum(r => MetadataInspector.PendingFields(r.Document));
        M1DraftCount.Text = L10n.Message(pending == 0 ? M1Text("NoDraft") : M1Format("DraftSummary", photos.Count(r => r.Document.Draft.Count > 0), pending));
        M1PhotoEmpty.Visibility = photos.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        M1InspectorEmpty.Visibility = Selected.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach(var control in new FrameworkElement[]{SelectionInfo,M2DiagnosticDetails,M1InspectorModes,M1FieldSearchBox})control.Visibility=Selected.Length==0?Visibility.Collapsed:Visibility.Visible;
        InspectorStatus.Visibility=Selected.Length>0&&InspectorStatus.Text.Length>0?Visibility.Visible:Visibility.Collapsed;
        MetadataGrid.Visibility = Selected.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        M1EditSelectedFields.IsEnabled = !busy && !renameRecoveryRequired && MetadataGrid.SelectedItems.OfType<InspectorRow>().Any(r => r.CanEdit);
        M1FieldSelectionCount.Text = L10n.Message(M1Format("FieldSelectedCount", MetadataGrid.SelectedItems.Count));
    }
    void M1PhotoTableSized(object sender, SizeChangedEventArgs e)
    {
        if (M1PhotoNameColumn is not null) M1PhotoNameColumn.Width = Math.Max(120, e.NewSize.Width - 274);
    }
    void M1TogglePhotoActions(object sender, RoutedEventArgs e) => M1PhotoSidebar.Visibility = M1PhotoSidebar.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    void M1InspectorModeSelected(object sender, RoutedEventArgs e)
    {
        if (InspectorView is not null && !changingM1Inspector && sender is RadioButton { Tag: string index })
            InspectorView.SelectedIndex = int.Parse(index, CultureInfo.InvariantCulture);
    }
    void M1InspectorGroupChanged(object sender, SelectionChangedEventArgs e) { if (IsLoaded && !changingM1Inspector) RefreshInspector(); }
    void M1FieldSelectionChanged(object sender, SelectionChangedEventArgs e) { if (IsLoaded) RefreshM1Shell(); }
    void M1InspectorDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (FindM1Row(e.OriginalSource as DependencyObject) is { } row && row.Item is InspectorRow { CanEdit: true } field)
        { OpenM1Field(field); e.Handled = true; }
    }
    void M1InspectorKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { EditInspectorField(sender, e); e.Handled = true; } }
    static DataGridRow? FindM1Row(DependencyObject? element)
    {
        for (; element is not null; element = VisualTreeHelper.GetParent(element)) if (element is DataGridRow row) return row;
        return null;
    }
    void M1EditRow(object sender, RoutedEventArgs e) { if (sender is Button { Tag: InspectorRow row }) OpenM1Field(row); }
    void OpenM1Field(InspectorRow row)
    {
        OpenWorkflowFields([row]);
    }
    void M1OpenTool(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string header })
            OpenMetadataTool((TabItem)MetadataToolsTabs.Items[int.Parse(header,CultureInfo.InvariantCulture)]);
    }
    void OpenMetadataTool(TabItem tab)
    {
        if (busy || renameRecoveryRequired || metadataClosing) return;
        int toolIndex = MetadataToolsTabs.Items.IndexOf(tab);
        if (toolIndex == 3) { OpenWorkflowDates(tab); return; }
        if (toolIndex is 0 or 2 or 5) { OpenWorkflow(toolIndex == 5); return; }
        if (advancedWindow is null)
        {
            MetadataToolsParking.Children.Remove(MetadataToolsTabs);
            var panel = new DockPanel { Margin = new Thickness(12) };
            var footer = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            var cancel = new Button { Content = M1Text("CancelEditor") };
            cancel.Click += (_, _) => {
                if (metadataClosing) return;
                if (busy) { CancelRead(this, new RoutedEventArgs()); return; }
                RefreshSelection(); DatePlanPreview.Text = M1Text("EditorCancelled"); advancedWindow?.Close();
            };
            var close = new Button { Content = M1Text("Close") }; close.Click += (_, _) => { if (!metadataClosing) advancedWindow?.Close(); };
            buttons.Children.Add(cancel); buttons.Children.Add(close); DockPanel.SetDock(buttons, Dock.Right); footer.Children.Add(buttons);
            footer.Children.Add(new TextBlock { Text = M1Text("EditorSelection"), TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center });
            DockPanel.SetDock(footer, Dock.Bottom); panel.Children.Add(footer); panel.Children.Add(MetadataToolsTabs);
            advancedWindow = new Window { Owner = this, Resources = Resources, Title = M1Text("ToolsTitle"), Width = 1000, Height = Math.Min(800, SystemParameters.WorkArea.Height), MinWidth = 600, MinHeight = 400, Content = panel, WindowStartupLocation = WindowStartupLocation.CenterOwner };
#pragma warning disable WPF0001
            advancedWindow.ThemeMode = ThemeMode;
#pragma warning restore WPF0001
            // Reparented controls no longer bubble through MainWindow; keep the original invalidation path.
            advancedWindow.AddHandler(ToggleButton.CheckedEvent, new RoutedEventHandler((_, _) => { if (!fillingEditor) InvalidateDates(); }));
            advancedWindow.AddHandler(ToggleButton.UncheckedEvent, new RoutedEventHandler((_, _) => { if (!fillingEditor) InvalidateDates(); }));
            advancedWindow.Closing += (_, args) => {
                metadataClosing = true;
                try {
                    if (busy) { CancelRead(this, new RoutedEventArgs()); args.Cancel = true; Status.Text = L10n.Message(M1Text("BusyEditor")); return; }
                    if (!DiscardEditor()) { args.Cancel = true; return; }
                    RefreshSelection();
                } finally { metadataClosing = false; }
            };
            advancedWindow.Closed += (_, _) => { panel.Children.Remove(MetadataToolsTabs); MetadataToolsParking.Children.Add(MetadataToolsTabs); advancedWindow = null; };
            advancedWindow.Show();
        }
        MetadataToolsTabs.SelectedItem = tab; advancedWindow.Activate();
    }
    void M1OpenSettings(object sender, RoutedEventArgs e)
    {
        if (settingsWindow is not null) { settingsWindow.Activate(); return; }
        ((Grid)SettingsPages.Parent).Children.Remove(SettingsPages); SettingsPages.Visibility = Visibility.Visible;
        SettingsPages.SelectedIndex = 0;
        settingsWindow = new Window { Owner = this, Resources = Resources, Title = M1Text("SettingsTitle"), FontSize=metadataBaseFont+settings.FontDelta, Width = 720, Height = Math.Min(690, SystemParameters.WorkArea.Height), MinWidth = 500, MinHeight = 400, Content = SettingsPages, WindowStartupLocation = WindowStartupLocation.CenterOwner };
#pragma warning disable WPF0001
        settingsWindow.ThemeMode = ThemeMode;
#pragma warning restore WPF0001
        settingsWindow.Closing += (_, args) => {if(!DiscardTrackPreferenceInput())args.Cancel=true;};
        settingsWindow.Closed += (_, _) => { settingsWindow!.Content = null; SettingsPages.Visibility = Visibility.Collapsed; ((Grid)WorkspaceTabs.Parent).Children.Add(SettingsPages); settingsWindow = null; Activate(); };
        settingsWindow.Show();
    }
    void M1ShowMore(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = M1MoreButton };
        void Add(string key, RoutedEventHandler action) { var item = new MenuItem { Header = M1Text(key) }; item.Click += action; menu.Items.Add(item); }
        Add("Import", ReadPhoto); Add("ImportFolder", ReadFolder); Add("SaveAll", PrepareSaveAll); Add("SaveWorkspace", PrepareSaveWorkspace);
        Add("SaveSummary", (_, _) => OpenMetadataTool(SaveTargetTab));
        foreach (var (key, index) in new[] { ("FieldEditor", 0), ("BatchDate", 3), ("Presets", 2), ("Compare", 5), ("Clipboard", 1), ("Xmp", 4), ("Csv", 8), ("Preview", 6) })
        { var item = new MenuItem { Header = M1Text(key) }; item.Click += (_, _) => OpenMetadataTool((TabItem)MetadataToolsTabs.Items[index]); menu.Items.Add(item); }
        Add("CopyTag", CopyMetadataTag); menu.IsOpen = true;
    }
    void M1OpenFavorites(object sender, RoutedEventArgs e) { WorkspaceTabs.SelectedIndex = 1; FavoriteList.BringIntoView(); FavoriteList.Focus(); }
    void M1OpenTrackMatch(object sender, RoutedEventArgs e) { M4OpenMatching(); }
    void M1PrepareGpsCopy(object sender, RoutedEventArgs e) => PrepareSave(Selected.Select(r => r.Document), SaveMode.Copy, SaveScope.Map);
}
