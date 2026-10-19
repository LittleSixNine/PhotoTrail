using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    StackPanel? workflowCards;
    TextBlock? workflowContext;
    Grid? workflowBody;
    TextBox? workflowPresetSearch;
    TextBox? workflowFirstInput;
    bool rebuildingWorkflow;
    readonly HashSet<MetadataOperation> disabledWorkflowOperations = new(ReferenceEqualityComparer.Instance);
    readonly HashSet<int> invalidWorkflowCards = [];
    sealed record WorkflowCardInput(string Tag,string Action,Dictionary<string,string> Values,string? Source,string Error);
    readonly Dictionary<MetadataOperation,WorkflowCardInput> workflowCardInputs=new(ReferenceEqualityComparer.Instance);
    readonly Dictionary<MetadataOperation,Dictionary<string,WorkflowCardInput>> workflowModeInputs=new(ReferenceEqualityComparer.Instance);
    string[] workflowTargets = [];
    string[] workflowReadOnly = [];
    PhotoRow[] workflowSelection = [];
    Window? dateEditorWindow;
    string? dateEditorBaseline;
    Func<bool>? dateEditorHasInput;
    PhotoRow[] dateEditorSelection=[];
    TextBlock? dateEditorContext;
    bool narrowMetadata, narrowInspector=true, changingNarrowMetadata;
    double widePhotoRatio=.5;
    string selectionSummaryText="";
    static readonly string[] WorkflowActions = ["setText", "remove", "fillMissingText", "appendText", "replaceAuthors", "fillMissingAuthors", "replaceKeywords", "appendKeywords", "removeKeywords", "copy", "offsetDate", "dateComponent", "sequence", "distribute", "filenameDate", "shiftDate", "calendarDays"];
    string WText(string key) => (string)FindResource("M2." + key);
    TextBlock WLabel(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 5) };
    Button WButton(string key, Action action)
    {
        var button = new Button { Content = WText(key), Margin = new Thickness(2), Padding = new Thickness(8, 4, 8, 4) };
        AutomationProperties.SetName(button, WText(key)); button.Click += (_, _) => action(); return button;
    }
    void M2PhotoSearchSized(object sender, SizeChangedEventArgs e)
    {
        if (PhotoSort is null || PhotoFilter is null || sender is not Grid grid) return;
        bool narrow = e.NewSize.Width < 450;
        Grid.SetRow(PhotoSort, narrow ? 1 : 0); Grid.SetRow(PhotoFilter, narrow ? 1 : 0);
        Grid.SetColumn(PhotoSort, narrow ? 0 : 1); Grid.SetColumn(PhotoFilter, narrow ? 1 : 2);
        Grid.SetColumnSpan(M1PhotoSearchBox, narrow ? 3 : 1);
        grid.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
        grid.ColumnDefinitions[1].Width = new GridLength(narrow ? 1 : 122, narrow ? GridUnitType.Star : GridUnitType.Pixel);
        grid.ColumnDefinitions[2].Width = new GridLength(narrow ? 0 : 112);
    }
    void M2MetadataLayoutSized(object sender,SizeChangedEventArgs e)=>RefreshM2MetadataLayout();
    void M2SplitterDragged(object sender,System.Windows.Controls.Primitives.DragCompletedEventArgs e)
    {
        if(narrowMetadata)return;var columns=M1MetadataLayout.ColumnDefinitions;double total=columns[0].ActualWidth+columns[2].ActualWidth;if(total>0)widePhotoRatio=columns[0].ActualWidth/total;
    }
    void M2NarrowSelected(object sender,RoutedEventArgs e)
    {
        if(changingNarrowMetadata||!IsLoaded)return;
        narrowInspector=sender is RadioButton{Tag:"fields"};RefreshM2MetadataLayout();
    }
    void RefreshM2MetadataLayout()
    {
        if(M2NarrowNavigation is null||Photos is null||M1MetadataLayout.ActualWidth<=0||changingNarrowMetadata)return;
        changingNarrowMetadata=true;bool priorFilling=fillingEditor;fillingEditor=true;
        try {
            bool narrow=M1MetadataLayout.ActualWidth<900;
            var columns=M1MetadataLayout.ColumnDefinitions;
            M2NarrowNavigation.Visibility=narrow?Visibility.Visible:Visibility.Collapsed;
            M2NarrowNavigation.IsEnabled=!busy&&!renameRecoveryRequired;M2NarrowFields.IsEnabled=Selected.Length>0;
            M2MetadataSplitter.Visibility=narrow?Visibility.Collapsed:Visibility.Visible;
            if(narrow) {
                columns[0].MinWidth=columns[2].MinWidth=0;columns[0].Width=new GridLength(1,GridUnitType.Star);columns[1].Width=columns[2].Width=new GridLength(0);
                Grid.SetColumn(M2PhotoPane,0);Grid.SetColumn(M2InspectorPane,0);Grid.SetColumnSpan(M2PhotoPane,3);Grid.SetColumnSpan(M2InspectorPane,3);
                bool fields=narrowInspector&&Selected.Length>0;
                M2PhotoPane.Visibility=fields?Visibility.Collapsed:Visibility.Visible;M2InspectorPane.Visibility=fields?Visibility.Visible:Visibility.Collapsed;
                M2NarrowPhotos.IsChecked=!fields;M2NarrowFields.IsChecked=fields;
            } else if(narrowMetadata) {
                columns[0].MinWidth=columns[2].MinWidth=280;columns[0].Width=new GridLength(widePhotoRatio,GridUnitType.Star);columns[1].Width=new GridLength(6);columns[2].Width=new GridLength(1-widePhotoRatio,GridUnitType.Star);
                Grid.SetColumn(M2PhotoPane,0);Grid.SetColumn(M2InspectorPane,2);Grid.SetColumnSpan(M2PhotoPane,1);Grid.SetColumnSpan(M2InspectorPane,1);M2PhotoPane.Visibility=M2InspectorPane.Visibility=Visibility.Visible;
            }
            narrowMetadata=narrow;
            RefreshM2SelectionSummary();
        }finally{fillingEditor=priorFilling;changingNarrowMetadata=false;}
    }
    void RefreshM2SelectionSummary()
    {
        if(SelectionInfo is null)return;
        SelectionInfo.ToolTip=selectionSummaryText;SelectionInfo.Text=L10n.Message(narrowMetadata?selectionSummaryText.Replace("\n"," · "):selectionSummaryText);
    }
    void M2ShowInspectorCounts(object sender,RoutedEventArgs e)=>MessageBox.Show(this,InspectorCounts.Text+(InspectorStatus.Text.Length>0?"\n"+InspectorStatus.Text:""),WText("Diagnostics"),MessageBoxButton.OK,MessageBoxImage.Information);
    void OpenWorkflowFields(IEnumerable<InspectorRow> selection)
    {
        if (busy || renameRecoveryRequired) return;
        var rows = selection.ToArray();
        var targets = rows.Where(r => r.CanEdit && r.EditTag is not null).Select(r => r.EditTag!).Distinct(StringComparer.Ordinal).ToArray();
        if (targets.Length == 0) { Status.Text = L10n.Message(WText("NoEditable")); return; }
        // Opening an inspector selection must not replace an unfinished operation chain.
        if (presetEditorDirty || invalidWorkflowCards.Count > 0 || PresetChainDirty || InspectorHasInput())
        {
            Status.Text = L10n.Message(WText("KeepInput")); OpenWorkflow(); return;
        }
        workflowTargets = targets;
        workflowReadOnly = rows.Where(r => !r.CanEdit).Select(r => r.Tag + " · " + r.Permission).ToArray();
        fillingPreset = true;
        try
        {
            presetOperations.Clear();
            foreach (string tag in targets)
            {
                string value = Selected.Select(r => r.Document.Value(tag)).Distinct(StringComparer.Ordinal).Count() == 1 ? Selected[0].Document.Value(tag) : "";
                string action = MetadataPreset.IsList(tag) ? tag == "XMP-dc:Creator" ? "replaceAuthors" : "replaceKeywords" : "setText";
                presetOperations.Add(new(tag, action, value));
            }
        }
        finally { fillingPreset = false; }
        OpenWorkflow();
    }
    void RefreshWorkflowContext()
    {
        if (workflowContext is null) return;
        workflowContext.Text = string.Format(CultureInfo.CurrentCulture, WText("Context"), workflowSelection.Length, workflowTargets.Length)
            + (workflowTargets.Length == 0 ? "" : "\n" + string.Join(" · ", workflowTargets))
            + (workflowReadOnly.Length == 0 ? "" : "\n" + WText("ReadOnlyExcluded") + string.Join(" · ", workflowReadOnly))
            + (workflowSelection.SequenceEqual(Selected) ? "" : "\n" + WText("SelectionChanged"));
    }
    void FilterWorkflowPresets()
    {
        if(workflowPresetSearch is null)return;
        var view=System.Windows.Data.CollectionViewSource.GetDefaultView(MetadataPresetList.ItemsSource);
        if(view is not null)view.Filter=item=>item is MetadataPresetEntry entry&&entry.Preset.Name.Contains(workflowPresetSearch.Text,StringComparison.CurrentCultureIgnoreCase);
    }
    void OpenWorkflow(bool compare = false)
    {
        if (busy || renameRecoveryRequired || metadataClosing) return;
        if (metadataWindow is not null) { metadataWindow.Activate(); return; }
        workflowSelection = Selected;
        var returnFocus = System.Windows.Input.Keyboard.FocusedElement;
        var root = new DockPanel { Margin = new Thickness(18) };
        var heading = new StackPanel();
        heading.Children.Add(new TextBlock { Text = WText("Title"), FontSize = 24, FontWeight = FontWeights.SemiBold });
        workflowContext = WLabel(""); RefreshWorkflowContext(); heading.Children.Add(workflowContext);
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        var feedback = new TextBlock { TextWrapping = TextWrapping.Wrap, MaxHeight = 65, Margin = new Thickness(0, 6, 0, 0) };
        feedback.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(TextBlock.Text)) { Source = Status });
        var footer = new DockPanel { Margin = new Thickness(0, 10, 0, 0) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(WButton("Cancel", () => { if (busy) CancelRead(this, new RoutedEventArgs()); else metadataWindow?.Close(); }));
        buttons.Children.Add(WButton("Undo", () => UndoLastApply(this, new RoutedEventArgs())));
        var applyButton = WButton("Apply", () => ApplyWorkflow()); applyButton.IsDefault=true; applyButton.SetResourceReference(StyleProperty,"M1.Primary"); buttons.Children.Add(applyButton);
        DockPanel.SetDock(buttons, Dock.Right); footer.Children.Add(buttons);
        footer.Children.Add(new TextBlock { Text = WText("DraftOnly"), TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center });
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        DockPanel.SetDock(feedback, Dock.Bottom); root.Children.Add(feedback);
        // These are the existing library controls, with the same handlers and optimistic concurrency checks.
        var libraryChildren = PresetControls.Children.Cast<UIElement>().Take(8).ToArray();
        var library = new StackPanel { Margin = new Thickness(12, 0, 0, 0) };
        var search = new TextBox { Margin = new Thickness(0, 4, 0, 8) };
        AutomationProperties.SetName(search, WText("SearchPresets")); search.ToolTip = WText("SearchPresets");
        workflowPresetSearch=search; search.TextChanged += (_, _) => FilterWorkflowPresets();
        library.Children.Add(search);
        foreach (var child in libraryChildren) { PresetControls.Children.Remove(child); library.Children.Add(child); }
        MetadataPresetList.Height = 200; MetadataPresetList.MinHeight = 130;
        foreach(var label in library.Children.OfType<TextBlock>()) label.TextWrapping = TextWrapping.Wrap;
        var columns = new Grid(); columns.ColumnDefinitions.Add(new ColumnDefinition()); columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(270) });
        workflowBody = columns;
        var libraryScroll = new ScrollViewer { Content = library, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(libraryScroll, 1); columns.Children.Add(libraryScroll);
        var tabs = new TabControl();
        var compose = new TabItem { Header = WText("Compose") };
        var composeDock = new DockPanel();
        var actions = new WrapPanel();
        actions.Children.Add(WButton("Add", () => { if (busy) return; if(presetOperations.Count < MetadataPreset.MaximumOperations) presetOperations.Add(new("XMP-dc:Title", "setText", "")); }));
        actions.Children.Add(WButton("Clear", () => { if (busy) return; presetOperations.Clear(); }));
        var presetNameParent = (Panel)PresetName.Parent; int nameIndex = presetNameParent.Children.IndexOf(PresetName); presetNameParent.Children.Remove(PresetName);
        PresetName.MinWidth = 180; actions.Children.Add(PresetName);
        DockPanel.SetDock(actions, Dock.Bottom); composeDock.Children.Add(actions);
        workflowCards = new StackPanel(); composeDock.Children.Add(new ScrollViewer { Content = workflowCards, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); compose.Content = composeDock;
        tabs.Items.Add(compose);
        var comparison = new TabItem { Header = WText("Compare") };
        var comparisonContent = ComparisonTab.Content; ComparisonTab.Content = null; comparison.Content = comparisonContent;
        var exchange = new WrapPanel();
        exchange.Children.Add(WButton("ExportCsv", () => ExportRoundtripCsv(this, new RoutedEventArgs())));
        exchange.Children.Add(WButton("ExportDisplay", () => ExportDisplayCsv(this, new RoutedEventArgs())));
        exchange.Children.Add(WButton("ExportDiskXmp", () => ExportDiskXmp(this, new RoutedEventArgs())));
        exchange.Children.Add(WButton("ExportDraftXmp", () => ExportXmp(this, new RoutedEventArgs())));
        exchange.Children.Add(WButton("ImportCsv", () => OpenMetadataTool((TabItem)MetadataToolsTabs.Items[8])));
        exchange.Children.Add(WButton("ImportXmp", () => OpenMetadataTool((TabItem)MetadataToolsTabs.Items[4])));
        exchange.Children.Add(WButton("Clipboard", () => OpenMetadataTool((TabItem)MetadataToolsTabs.Items[1])));
        if (comparisonContent is DockPanel comparisonPanel) { DockPanel.SetDock(exchange, Dock.Top); comparisonPanel.Children.Insert(0, exchange); }
        tabs.Items.Add(comparison);
        tabs.SelectionChanged += (_, args) => { if (ReferenceEquals(args.Source, tabs) && comparison.IsSelected) { ComparisonTab.IsSelected = true; RefreshComparison(); } };
        tabs.SelectedIndex = compare ? 1 : 0;
        columns.Children.Add(tabs); root.Children.Add(columns);
        columns.SizeChanged += (_, args) => { bool narrow = args.NewSize.Width < 850; columns.ColumnDefinitions[1].Width = new GridLength(narrow ? 210 : 270); };
        metadataWindow = new Window { Owner = this, Resources = Resources, Title = WText("Title"), FontSize = FontSize, FontFamily = FontFamily, Width = Math.Min(1120, SystemParameters.WorkArea.Width), Height = Math.Min(800, SystemParameters.WorkArea.Height), MinWidth = 650, MinHeight = 400, Content = root, WindowStartupLocation = WindowStartupLocation.CenterOwner };
#pragma warning disable WPF0001
        metadataWindow.ThemeMode = ThemeMode;
#pragma warning restore WPF0001
        metadataWindow.PreviewKeyDown += (_, args) => { if(args.Key==System.Windows.Input.Key.Escape) { if(CloseOpenDropdown(metadataWindow!)){args.Handled=true;return;} if(busy)CancelRead(this,new RoutedEventArgs());else metadataWindow?.Close();args.Handled=true; } };
        metadataWindow.Loaded += (_, _) => workflowFirstInput?.Focus();
        metadataWindow.Closing += (_, args) =>
        {
            if (metadataClosing) { args.Cancel = true; return; }
            metadataClosing=true;
            try {
            if (busy) { CancelRead(this, new RoutedEventArgs()); args.Cancel = true; return; }
            if (invalidWorkflowCards.Count > 0 && MessageBox.Show(metadataWindow, WText("DiscardParameters"), "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) { args.Cancel = true; return; }
            if (invalidWorkflowCards.Count == 0 && PresetChainDirty && MessageBox.Show(metadataWindow, WText("CloseWithParameters"), "PhotoTrail", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) { args.Cancel = true; return; }
            if (!DiscardEditor()) args.Cancel = true;
            } finally { metadataClosing=false; }
        };
        metadataWindow.Closed += (_, _) =>
        {
            if (comparisonContent is DockPanel oldComparisonPanel) oldComparisonPanel.Children.Remove(exchange);
            comparison.Content = null; ComparisonTab.Content = comparisonContent;
            actions.Children.Remove(PresetName); presetNameParent.Children.Insert(nameIndex, PresetName);
            foreach (var child in libraryChildren) library.Children.Remove(child);
            for (int i = 0; i < libraryChildren.Length; i++) PresetControls.Children.Insert(i, libraryChildren[i]);
            var listView=System.Windows.Data.CollectionViewSource.GetDefaultView(MetadataPresetList.ItemsSource);if(listView is not null)listView.Filter=null;
            workflowCards = null; workflowContext = null; workflowBody = null; workflowPresetSearch=null; metadataWindow = null; invalidWorkflowCards.Clear();workflowCardInputs.Clear();workflowModeInputs.Clear();
            ReturnEditorFocus(returnFocus);
        };
        RebuildWorkflowCards(); metadataWindow.Show(); if (compare) { ComparisonTab.IsSelected = true; RefreshComparison(); }
    }
    void OpenWorkflowDates(TabItem tab)
    {
        if(busy||renameRecoveryRequired)return;
        if(dateEditorWindow is not null){dateEditorWindow.Activate();return;}
        dateEditorSelection=Selected;
        var returnFocus=System.Windows.Input.Keyboard.FocusedElement;
        string Raw()=>string.Join("\0",new[]{DateTarget.SelectedIndex.ToString(CultureInfo.InvariantCulture),DateMode.SelectedIndex.ToString(CultureInfo.InvariantCulture)}.Concat(new[]{DateYears,DateMonths,DateDays,DateHours,DateMinutes,DateSeconds,DateStart,DateEnd,DateStep,DateReplaceYear,DateReplaceMonth,DateReplaceDay,DateReplaceHour,DateReplaceMinute,DateReplaceSecond,DateFilenamePattern,DateFilenameTemplate}.Select(box=>box.Text)));
        dateEditorBaseline??=Raw();dateEditorHasInput=()=>Raw()!=dateEditorBaseline;
        var content=tab.Content;tab.Content=null;
        var body=new DockPanel { Margin=new Thickness(16) };
        var heading=WLabel(string.Format(CultureInfo.CurrentCulture,WText("DateContext"),Selected.Length)+"\n"+string.Join(" · ",Selected.Select(row=>row.Document.MainDateTag).Distinct(StringComparer.Ordinal)));dateEditorContext=heading;
        DockPanel.SetDock(heading,Dock.Top);body.Children.Add(heading);
        var footer=new StackPanel { Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right };
        footer.Children.Add(WButton("ConfirmSelection",ConfirmWorkflowDateSelection));
        footer.Children.Add(WButton("Undo",()=>UndoLastApply(this,new RoutedEventArgs())));footer.Children.Add(WButton("Cancel",()=>{if(busy)CancelRead(this,new RoutedEventArgs());else dateEditorWindow?.Close();}));
        DockPanel.SetDock(footer,Dock.Bottom);body.Children.Add(footer);body.Children.Add((UIElement)content);
        dateEditorWindow=new Window { Owner=this,Resources=Resources,Title=WText("DateTitle"),FontSize=metadataBaseFont+settings.FontDelta,Width=Math.Min(880,SystemParameters.WorkArea.Width),Height=Math.Min(700,SystemParameters.WorkArea.Height),MinWidth=600,MinHeight=400,Content=body,WindowStartupLocation=WindowStartupLocation.CenterOwner };
#pragma warning disable WPF0001
        dateEditorWindow.ThemeMode=ThemeMode;
#pragma warning restore WPF0001
        dateEditorWindow.AddHandler(System.Windows.Controls.Primitives.ToggleButton.CheckedEvent,new RoutedEventHandler((_,_)=>{if(!fillingEditor)InvalidateDates();}));
        dateEditorWindow.AddHandler(System.Windows.Controls.Primitives.ToggleButton.UncheckedEvent,new RoutedEventHandler((_,_)=>{if(!fillingEditor)InvalidateDates();}));
        dateEditorWindow.PreviewKeyDown+=(_,args)=>{if(args.Key==System.Windows.Input.Key.Escape){if(CloseOpenDropdown(dateEditorWindow!)){args.Handled=true;return;}if(busy)CancelRead(this,new RoutedEventArgs());else dateEditorWindow?.Close();args.Handled=true;}};
        dateEditorWindow.Closing+=(_,args)=>{if(busy){CancelRead(this,new RoutedEventArgs());args.Cancel=true;return;}if(dateEditorHasInput()&&MessageBox.Show(dateEditorWindow,WText("CloseDateParameters"),"PhotoTrail",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)!=MessageBoxResult.Yes)args.Cancel=true;};
        dateEditorWindow.Closed+=(_,_)=>{body.Children.Remove((UIElement)content);tab.Content=content;dateEditorWindow=null;dateEditorContext=null;ReturnEditorFocus(returnFocus);};
        dateEditorWindow.Show();
    }
    void ConfirmWorkflowDateSelection()
    {
        if(busy||renameRecoveryRequired||dateEditorWindow is null)return;
        dateEditorSelection=Selected;InvalidateDates();
        if(dateEditorContext is not null)dateEditorContext.Text=string.Format(CultureInfo.CurrentCulture,WText("DateContext"),Selected.Length)+"\n"+string.Join(" · ",Selected.Select(row=>row.Document.MainDateTag).Distinct(StringComparer.Ordinal));
        DatePlanApplyButton.IsEnabled=Selected.Length>0&&Selected.All(row=>row.Document.CanStage);
        DatePlanPreview.Text=WText("SelectionConfirmed");
    }
    void RebuildWorkflowCards()
    {
        if (workflowCards is null || rebuildingWorkflow) return;
        rebuildingWorkflow = true;
        try
        {
            workflowCards.Children.Clear(); invalidWorkflowCards.Clear(); workflowFirstInput=null;
            disabledWorkflowOperations.RemoveWhere(op => !presetOperations.Any(x => ReferenceEquals(x, op)));
            foreach(var stale in workflowCardInputs.Keys.Where(op=>!presetOperations.Any(x=>ReferenceEquals(x,op))).ToArray())workflowCardInputs.Remove(stale);
            foreach(var stale in workflowModeInputs.Keys.Where(op=>!presetOperations.Any(x=>ReferenceEquals(x,op))).ToArray())workflowModeInputs.Remove(stale);
            for (int index = 0; index < presetOperations.Count; index++) workflowCards.Children.Add(BuildWorkflowCard(index));
            if (presetOperations.Count == 0) workflowCards.Children.Add(WLabel(WText("Empty")));
            workflowTargets=presetOperations.Select(op=>op.Tag).Distinct(StringComparer.Ordinal).ToArray();
            RefreshWorkflowContext();
        }
        finally { rebuildingWorkflow = false; }
    }
    FrameworkElement BuildWorkflowCard(int index)
    {
        var op = presetOperations[index];
        workflowCardInputs.TryGetValue(op,out var savedInput);
        if(!workflowModeInputs.TryGetValue(op,out var modeInputs))workflowModeInputs[op]=modeInputs=new(StringComparer.Ordinal);
        Expander? cardShell=null;
        var card = new StackPanel { Margin = new Thickness(10) };
        var bar = new WrapPanel();
        var enabled = new CheckBox { Content = WText("Enabled"), IsChecked = !disabledWorkflowOperations.Contains(op), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3) };
        bar.Children.Add(enabled);
        void Mutate(Action change) { if (busy) return; change(); }
        bar.Children.Add(WButton("Up", () => Mutate(() => { if (index > 0) presetOperations.Move(index, index - 1); })));
        bar.Children.Add(WButton("Down", () => Mutate(() => { if (index + 1 < presetOperations.Count) presetOperations.Move(index, index + 1); })));
        bar.Children.Add(WButton("Duplicate", () => Mutate(() => { if (presetOperations.Count < MetadataPreset.MaximumOperations) { var copy=presetOperations[index] with { };if(workflowCardInputs.TryGetValue(op,out var pending))workflowCardInputs[copy]=pending;workflowModeInputs[copy]=new(modeInputs,StringComparer.Ordinal);if(disabledWorkflowOperations.Contains(op))disabledWorkflowOperations.Add(copy);presetOperations.Insert(index + 1,copy); } })));
        bar.Children.Add(WButton("Delete", () => { if(busy)return; presetOperations.RemoveAt(index); })); card.Children.Add(bar);
        var target = new ComboBox { ItemsSource = MetadataCsv.Tags.Select(tag => new PresetField(tag, fieldLabels[tag] + " · " + tag)).ToArray(), DisplayMemberPath = "Name", SelectedValuePath = "Tag", SelectedValue = savedInput?.Tag??op.Tag, Margin = new Thickness(0, 4, 0, 5) };
        AutomationProperties.SetName(target, WText("Target")); card.Children.Add(WLabel(WText("Target"))); card.Children.Add(target);
        var action = new ComboBox { ItemsSource = WorkflowActions.Select(id => new { Id = id, Name = WText("Action." + id) }).ToArray(), DisplayMemberPath = "Name", SelectedValuePath = "Id", SelectedValue = savedInput?.Action??op.Action, Margin = new Thickness(0, 4, 0, 5) };
        AutomationProperties.SetName(action, WText("Action")); card.Children.Add(action);
        var currentValues=workflowSelection.Select(r=>r.Document.Value(savedInput?.Tag??op.Tag)).ToArray();
        var current = WLabel(string.Format(CultureInfo.CurrentCulture,WText("CurrentSummary"),currentValues.Distinct(StringComparer.Ordinal).Count(),currentValues.Count(v=>v.Length>0),currentValues.Length)+"\n"+string.Join(" · ", currentValues.Distinct(StringComparer.Ordinal).Take(3).Select(v=>v.Length>0?v:WText("Missing")))); current.Opacity = .7; card.Children.Add(current);
        var parameters = new StackPanel(); card.Children.Add(parameters);
        var error = WLabel(""); error.Foreground = Brushes.DarkOrange; card.Children.Add(error);
        var inputs = new Dictionary<string, TextBox>(); ComboBox? source = null;
        void Input(string key, string value, bool multi = false)
        {
            parameters.Children.Add(WLabel(WText("Param." + key)));
            var box = new TextBox { Text = value, AcceptsReturn = multi, MinHeight = multi ? 56 : 28, MaxLength = 8192, Margin = new Thickness(0, 0, 0, 5), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            AutomationProperties.SetName(box, WText("Param." + key)); inputs.Add(key, box); parameters.Children.Add(box); box.TextChanged += (_, _) => Commit();
            workflowFirstInput??=box;
            if(key=="value"&&target.SelectedValue is string valueTag)
            {
                string[]? choices=valueTag=="XMP-xmp:Rating"?Enumerable.Range(-1,7).Select(n=>n.ToString(CultureInfo.InvariantCulture)).ToArray():PhotoDocument.NumericRange(valueTag) is {} numeric&&numeric.Integer&&numeric.Maximum-numeric.Minimum<=16?Enumerable.Range((int)numeric.Minimum,(int)(numeric.Maximum-numeric.Minimum)+1).Select(n=>n.ToString(CultureInfo.InvariantCulture)).ToArray():null;
                if(PhotoDocument.NumericRange(valueTag) is {} range)parameters.Children.Add(WLabel(string.Format(CultureInfo.CurrentCulture,WText("NumericRange"),range.Minimum,range.Maximum,range.Integer?WText("IntegerType"):WText("NumberType"))));
                if(valueTag=="ExifIFD:Flash")AddFlashPicker(parameters,box);
                if(valueTag is "XMP-tiff:Make" or "XMP-tiff:Model" or "IFD0:Make" or "IFD0:Model")AddDevicePicker(parameters,valueTag,box);
                if(choices is not null)
                {
                    box.Visibility=Visibility.Collapsed;
                    var picker=new ComboBox { ItemsSource=choices,IsEditable=true,Margin=new Thickness(0,0,0,5) };
                    AutomationProperties.SetName(picker,WText("EnumValue"));picker.SetBinding(ComboBox.TextProperty,new System.Windows.Data.Binding(nameof(TextBox.Text)){Source=box,Mode=System.Windows.Data.BindingMode.TwoWay,UpdateSourceTrigger=System.Windows.Data.UpdateSourceTrigger.PropertyChanged});parameters.Children.Add(picker);
                }
            }
        }
        long N(string key) => long.TryParse(inputs[key].Text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long value) ? value : throw new ArgumentException(WText("Integer"));
        string S(string key) => inputs[key].Text;
        void Commit()
        {
            if (rebuildingWorkflow) return;
            try
            {
                string id = (string)action.SelectedValue, tag = (string)target.SelectedValue;
                PresetDateArguments? date = id switch
                {
                    "offsetDate" => new(N("years"), N("months"), N("days"), N("hours"), N("minutes"), N("seconds")),
                    "dateComponent" => new(Components: new[] { "year", "month", "day", "hour", "minute", "second" }.Where(k => S(k).Length > 0).ToDictionary(k => k, N)),
                    "sequence" => new(Seconds: N("seconds"), Start: S("start")), "distribute" => new(Start: S("start"), End: S("end")),
                    "filenameDate" => new(Pattern: S("pattern"), Template: S("template")), "shiftDate" => new(Seconds:N("seconds")), "calendarDays" => new(Days:N("days"),Zone:S("zone").Length==0?null:S("zone")), _ => null
                };
                var next = MetadataPreset.Validate(new(tag, id, date is not null || id == "remove" ? "" : id == "copy" ? source?.SelectedValue as string ?? "" : S("value"), date));
                if (workflowSelection.Any(r => !MetadataFields.CanEdit(r.Document, tag))) throw new ArgumentException(WText("NoEditable"));
                bool disabled = disabledWorkflowOperations.Remove(op);workflowCardInputs.Remove(op);workflowModeInputs.Remove(op);workflowModeInputs[next]=modeInputs; op = next;
                rebuildingWorkflow = true; try { presetOperations[index] = next; } finally { rebuildingWorkflow = false; }
                if (disabled) disabledWorkflowOperations.Add(next);
                workflowTargets=presetOperations.Select(item=>item.Tag).Distinct(StringComparer.Ordinal).ToArray();RefreshWorkflowContext();
                if(cardShell is not null)cardShell.Header=(index+1)+" · "+fieldLabels.GetValueOrDefault(op.Tag,op.Tag);
                invalidWorkflowCards.Remove(index); error.Text = ""; InvalidateDates();
            }
            catch (Exception problem) when (problem is ArgumentException or InvalidOperationException or KeyNotFoundException)
            { invalidWorkflowCards.Add(index); error.Text = string.Format(CultureInfo.CurrentCulture, WText("CardError"), index + 1, target.SelectedValue, L10n.Message(problem.Message));workflowCardInputs[op]=new((string)target.SelectedValue,(string)action.SelectedValue,inputs.ToDictionary(p=>p.Key,p=>p.Value.Text),source?.SelectedValue as string,problem.Message); InvalidateDates(); }
        }
        void Parameters()
        {
            parameters.Children.Clear(); inputs.Clear(); source = null; string id = action.SelectedValue as string ?? ""; var date = op.Date ?? new();
            if (id == "copy") { source = new ComboBox { ItemsSource = MetadataCsv.Tags, SelectedValue = op.Action == "copy" ? op.Value : MetadataCsv.Tags.FirstOrDefault(t => t != op.Tag) }; AutomationProperties.SetName(source, WText("Source")); parameters.Children.Add(WLabel(WText("Source"))); parameters.Children.Add(source); source.SelectionChanged += (_, _) => Commit(); }
            else if (id == "offsetDate") foreach (var pair in new[] { ("years", date.Years), ("months", date.Months), ("days", date.Days), ("hours", date.Hours), ("minutes", date.Minutes), ("seconds", date.Seconds) }) Input(pair.Item1, pair.Item2.ToString(CultureInfo.InvariantCulture));
            else if (id == "dateComponent") foreach (string key in new[] { "year", "month", "day", "hour", "minute", "second" }) Input(key, date.Components is {} components && components.TryGetValue(key,out var component) ? component.ToString(CultureInfo.InvariantCulture) : "");
            else if (id == "sequence") { Input("start", date.Start); Input("seconds", date.Seconds.ToString(CultureInfo.InvariantCulture)); }
            else if (id == "distribute") { Input("start", date.Start); Input("end", date.End); }
            else if (id == "filenameDate") { Input("pattern", date.Pattern); Input("template", date.Template); }
            else if (id == "shiftDate") Input("seconds", date.Seconds.ToString(CultureInfo.InvariantCulture));
            else if (id == "calendarDays") { Input("days", date.Days.ToString(CultureInfo.InvariantCulture)); Input("zone", date.Zone??""); }
            else if (id != "remove") Input("value", op.Value, MetadataPreset.IsList((string)target.SelectedValue)||MetadataPreset.IsText((string)target.SelectedValue));
        }
        bool switching=false;
        string previousAction=(string)action.SelectedValue;
        Parameters();
        if(savedInput is not null) { foreach(var pair in savedInput.Values)if(inputs.TryGetValue(pair.Key,out var box))box.Text=pair.Value;if(source is not null)source.SelectedValue=savedInput.Source; }
        target.SelectionChanged += (_, _) =>
        {
            if(switching)return;
            Commit();
            if(!invalidWorkflowCards.Contains(index))
            {
                Parameters();
                if(cardShell is not null)cardShell.Header=(index+1)+" · "+fieldLabels.GetValueOrDefault(op.Tag,op.Tag);
                var values=workflowSelection.Select(r=>r.Document.Value(op.Tag)).ToArray();current.Text=string.Format(CultureInfo.CurrentCulture,WText("CurrentSummary"),values.Distinct(StringComparer.Ordinal).Count(),values.Count(v=>v.Length>0),values.Length)+"\n"+string.Join(" · ",values.Distinct(StringComparer.Ordinal).Take(3).Select(v=>v.Length>0?v:WText("Missing")));
            }
        };
        action.SelectionChanged += (_, _) => {
            if(switching)return;
            var priorValues=inputs.ToDictionary(pair=>pair.Key,pair=>pair.Value.Text);
            modeInputs[previousAction]=new((string)target.SelectedValue,previousAction,priorValues,source?.SelectedValue as string,"");
            previousAction=(string)action.SelectedValue;
            bool building=rebuildingWorkflow;rebuildingWorkflow=true;
            try { Parameters();var values=modeInputs.TryGetValue(previousAction,out var savedMode)?savedMode.Values:priorValues;foreach(var pair in values)if(inputs.TryGetValue(pair.Key,out var box))box.Text=pair.Value;if(source is not null&&savedMode?.Source is string sourceTag)source.SelectedValue=sourceTag; }
            finally{rebuildingWorkflow=building;}
            Commit();
        };
        enabled.Click += (_, _) => { if (busy) return; if (enabled.IsChecked == true) { disabledWorkflowOperations.Remove(op); Commit(); } else { disabledWorkflowOperations.Add(op); invalidWorkflowCards.Remove(index); } parameters.IsEnabled = enabled.IsChecked == true; InvalidateDates(); };
        parameters.IsEnabled = enabled.IsChecked == true;
        if(enabled.IsChecked==true&&savedInput is not null) { invalidWorkflowCards.Add(index);error.Text=string.Format(CultureInfo.CurrentCulture,WText("CardError"),index+1,savedInput.Tag,L10n.Message(savedInput.Error)); }
        else if (enabled.IsChecked == true) try { MetadataPreset.Validate(op); } catch (ArgumentException problem) { invalidWorkflowCards.Add(index); error.Text = string.Format(CultureInfo.CurrentCulture, WText("CardError"), index + 1, op.Tag, L10n.Message(problem.Message)); }
        return cardShell=new Expander { Header = (index + 1) + " · " + fieldLabels.GetValueOrDefault(savedInput?.Tag??op.Tag, savedInput?.Tag??op.Tag), Content = card, IsExpanded = true, Margin = new Thickness(0, 5, 8, 8), BorderBrush = SystemColors.ControlDarkBrush, BorderThickness = new Thickness(1) };
    }
    async void ApplyWorkflow()
    {
        if (busy || renameRecoveryRequired) return;
        if (invalidWorkflowCards.Count > 0) { Status.Text = L10n.Message(WText("InvalidCards")); return; }
        if (!workflowSelection.SequenceEqual(Selected)) { Status.Text = L10n.Message(WText("SelectionChanged")); return; }
        try
        {
            if (presetEditorDirty || InspectorHasInput()) throw new InvalidOperationException(WText("KeepInput"));
            MetadataPreset Active() => MetadataPreset.Create(PresetName.Text, presetOperations.Where(op => !disabledWorkflowOperations.Contains(op)).ToArray());
            var preset = Active(); string input = preset.Encode();
            await ApplyMetadataBatch("预设", async (docs, revision, token) =>
            {
                var result = await preset.CalculateAsync(docs, revision, () => System.Threading.Volatile.Read(ref dateRevision), token);
                return new BatchDetails(Missing: result.Missing, FilenameMismatch: result.FilenameMismatch, FilenameInvalid: result.FilenameInvalid, CopyMissing: result.CopyMissing, OperationCount: preset.Operations.Count, Measurements: result.Measurements, InitialSourceMs: result.ReadMs, ParameterValidationMs: result.ParameterValidationMs);
            }, () => invalidWorkflowCards.Count == 0 && !presetEditorDirty && !InspectorHasInput() && workflowSelection.SequenceEqual(Selected) && Active().Encode() == input);
        }
        catch (Exception problem) { Status.Text = L10n.Message(WText("NotApplied") + L10n.Message(problem.Message)); }
    }
}
