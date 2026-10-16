using System.Globalization;
using System.Reflection;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    sealed class RenameCard(RenameRule rule) {
        internal RenameRule Rule=rule;
        internal readonly Dictionary<string,string> Invalid=new();
        internal bool Expanded;
        internal Expander? Editor;
        internal TextBlock? Summary;
    }
    readonly List<RenameCard> m3Cards=[];
    bool m3Writing,m3Ready;
    string? m3RawError;
    StackPanel? m3CardPanel,m3Commands;
    Grid? m3Columns;
    FrameworkElement? m3Left,m3Right;
    ScrollViewer? m3ResultScroll;
    GridSplitter? m3Splitter;
    WrapPanel? m3Narrow;
    bool m3ShowResults;
    TextBlock? m3CardError;
    Button? m3LocateError;
    WrapPanel? m3Processing,m3Viewing;
    Button? m3HistoryButton;
    RenameCard? m3Selected;
    DataGridTextColumn? m3StepColumn;
    readonly Dictionary<string,string[]> m3Steps=new(StringComparer.OrdinalIgnoreCase);
    bool M3InvalidInputs=>m3RawError is not null||m3Cards.Any(c=>c.Invalid.Count>0);
    string M3(string key)=>TryFindResource("M3"+key) as string??key;
    Button M3Button(string key,RoutedEventHandler handler) {var b=new Button{Content=M3(key),Margin=new(2),Padding=new(7,4,7,4)};AutomationProperties.SetName(b,M3(key));b.Click+=handler;return b;}
    static void M3Detach(FrameworkElement item) {
        if(item.Parent is Panel p)p.Children.Remove(item);
        else if(item.Parent is Decorator d)d.Child=null;
        else if(item.Parent is ContentControl c)c.Content=null;
    }
    static void M3Move(Panel parent,FrameworkElement item){M3Detach(item);item.ClearValue(Grid.RowProperty);item.ClearValue(Grid.ColumnProperty);parent.Children.Add(item);}
    string M3RuleProblem(RenameCard card){
        if(card.Invalid.Count>0)return string.Join("; ",card.Invalid.Select(p=>L10n.Format("{0}：请输入有符号整数（{1}位）；原输入“{2}”已保留。",M3("P"+p.Key),typeof(RenameRule).GetProperty(p.Key)!.PropertyType==typeof(long)?64:32,p.Value)));
        try{RenamePlan.ValidateRules(RenamePlan.EncodeEditorRules([card.Rule]));return "";}catch(ArgumentException e){return L10n.Message(e.Message)+" · "+string.Join("; ",M3MainFields(card.Rule).Select(n=>M3("P"+n)+"="+Convert.ToString(typeof(RenameRule).GetProperty(n)!.GetValue(card.Rule),CultureInfo.InvariantCulture)))+" · "+(card.Rule.Kind is "sequence" or "sequence-prefix"?L10n.Text("起始值≥0；步长>0；最少位数1—9。") : L10n.Text("数值范围：位数0—32；字母宽度1—32；位置／长度0—4096；出现次数≥1；计数槽0—10；夜间小时0—23。持续计数的起始值≥0且步长>0。")+" "+L10n.Text("请按参数字段要求修正；不使用默认值替代。"));}
    }
    string[] M3Problems()=>m3Cards.Select((c,i)=>(c,i,problem:M3RuleProblem(c))).Where(x=>x.problem.Length>0).Select(x=>L10n.Format("第 {0} 条 · {1}：{2}",x.i+1,M3CardName(x.c),x.problem)).ToArray();
    void M3EnsureValid(){var errors=M3Problems();if(m3RawError is not null||errors.Length>0)throw new ArgumentException(m3RawError??string.Join("\n",errors));}
    void M3EditCard(RenameCard card){m3Selected=card;foreach(var c in m3Cards)if(c.Editor is not null)c.Editor.IsExpanded=ReferenceEquals(c,card);M3MarkSelected();M3StepBinding();card.Editor?.BringIntoView();}
    void M3LocateProblem(){var card=m3Cards.FirstOrDefault(c=>M3RuleProblem(c).Length>0);if(card is null)return;M3EditCard(card);if(card.Editor?.Content is Panel panel){var field=panel.Children.OfType<Panel>().SelectMany(p=>p.Children.OfType<TextBox>()).FirstOrDefault(b=>card.Invalid.ContainsKey(AutomationProperties.GetAutomationId(b).Replace("M6RenameParam.","")));field?.Focus();}}

    void M3RefreshEnabled(){if(m3CardPanel is not null)m3CardPanel.IsEnabled=!busy&&!renameRecoveryRequired;if(m3Commands is not null)m3Commands.IsEnabled=!busy&&!renameRecoveryRequired;if(m3Processing is not null)m3Processing.IsEnabled=!busy&&!renameRecoveryRequired;if(m3Viewing is not null)m3Viewing.IsEnabled=!busy;if(m3HistoryButton is not null)m3HistoryButton.IsEnabled=!busy;}
    void InitializeM3Rename() {
        if(m3Ready)return;m3Ready=true;
        var outer=M3RenameWorkspace;outer.RowDefinitions.Add(new(){Height=GridLength.Auto});outer.RowDefinitions.Add(new());
        m3Narrow=new(){Visibility=Visibility.Collapsed};m3Narrow.Children.Add(M3Button("Rules",(_,_)=>{m3ShowResults=false;M3Size();}));m3Narrow.Children.Add(M3Button("Results",(_,_)=>{m3ShowResults=true;M3Size();}));outer.Children.Add(m3Narrow);
        m3Columns=new Grid();Grid.SetRow(m3Columns,1);outer.Children.Add(m3Columns);m3Columns.ColumnDefinitions.Add(new(){Width=new(350),MinWidth=320,MaxWidth=420});m3Columns.ColumnDefinitions.Add(new(){Width=new(6)});m3Columns.ColumnDefinitions.Add(new(){MinWidth=480});
        var left=new DockPanel{LastChildFill=true};m3Left=left;m3Columns.Children.Add(left);
        var head=new StackPanel{Margin=new(0,0,8,8)};DockPanel.SetDock(head,Dock.Top);left.Children.Add(head);
        head.Children.Add(new TextBlock{Text=M3("Current"),FontSize=18,FontWeight=FontWeights.SemiBold});
        var name=new TextBlock{FontSize=15,Margin=new(0,8,0,4),TextTrimming=TextTrimming.CharacterEllipsis};name.SetBinding(TextBlock.TextProperty,new Binding("Text"){Source=RenameSchemeName});head.Children.Add(name);
        var summary=new TextBlock{TextWrapping=TextWrapping.Wrap};summary.SetBinding(TextBlock.TextProperty,new Binding("Text"){Source=RenameSchemeStatus});head.Children.Add(summary);
        m3Commands=new StackPanel();head.Children.Add(m3Commands);var bar=new WrapPanel();m3Commands.Children.Add(bar);bar.Children.Add(M3Button("Library",(_,_)=>M3SchemeLibrary()));bar.Children.Add(M3Button("Add",(_,_)=>M3AddAction()));bar.Children.Add(M3Button("Advanced",(_,_)=>M3Advanced()));
        m3CardError=new TextBlock{TextWrapping=TextWrapping.Wrap,Foreground=Brushes.Firebrick,Margin=new(2,5,2,5)};head.Children.Add(new ScrollViewer{Content=m3CardError,MaxHeight=88,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});m3LocateError=new Button{Content=L10n.Text("定位首个错误"),HorizontalAlignment=HorizontalAlignment.Left,Visibility=Visibility.Collapsed};AutomationProperties.SetName(m3LocateError,L10n.Text("定位首个错误"));m3LocateError.Click+=(_,_)=>M3LocateProblem();head.Children.Add(m3LocateError);
        m3CardPanel=new StackPanel{Margin=new(0,0,8,0)};left.Children.Add(new ScrollViewer{Content=m3CardPanel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled});
        m3Splitter=new GridSplitter{Width=6,HorizontalAlignment=HorizontalAlignment.Stretch,ResizeBehavior=GridResizeBehavior.PreviousAndNext};Grid.SetColumn(m3Splitter,1);m3Columns.Children.Add(m3Splitter);
        var right=new DockPanel{Margin=new(8,0,0,0),LastChildFill=true};m3Right=right;m3ResultScroll=new ScrollViewer{Content=right,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled};Grid.SetColumn(m3ResultScroll,2);m3Columns.Children.Add(m3ResultScroll);m3Columns.SizeChanged+=(_,_)=>M3Size();
        var top=new StackPanel();DockPanel.SetDock(top,Dock.Top);right.Children.Add(top);top.Children.Add(new TextBlock{Text=M3("Scope"),TextWrapping=TextWrapping.Wrap});
        var processing=new WrapPanel{Margin=new(0,6,0,0)};m3Processing=processing;top.Children.Add(processing);processing.Children.Add(M3Button("Refresh",RefreshRenameOrder));M3Move(processing,RenameProcessingSort);M3Move(processing,RenameDescending);processing.Children.Add(M3Button("Input",(_,_)=>M3InputSettings()));
        var viewing=new WrapPanel();m3Viewing=viewing;top.Children.Add(viewing);M3Move(viewing,RenameViewOrder);M3Move(viewing,RenameViewFilter);viewing.Children.Add(M3Button("Groups",(_,_)=>M3GroupOrder()));
        top.Children.Add(new TextBlock{Text=M3("OrderNotice"),TextWrapping=TextWrapping.Wrap,Opacity=.7,Margin=new(2,4,2,7)});
        var bottom=new StackPanel{Margin=new(0,6,0,0)};DockPanel.SetDock(bottom,Dock.Bottom);right.Children.Add(bottom);var execute=new WrapPanel();bottom.Children.Add(execute);M3Move(execute,FreezeRenameButton);M3Move(execute,ExecuteRenameButton);m3HistoryButton=M3Button("History",(_,_)=>M3History());execute.Children.Add(m3HistoryButton);M3Move(bottom,RenameOrderStatus);M3Move(bottom,RenameStatus);
        M3Move(right,RenamePreview);RenamePreview.MinWidth=0;RenamePreview.Columns.Clear();RenamePreview.Columns.Add(new DataGridTextColumn{Header=M3("Original"),Binding=new Binding("OriginalName"),Width=new(1,DataGridLengthUnitType.Star),MinWidth=100});m3StepColumn=new(){Header=M3("SelectStep"),MinWidth=100,Width=new(1,DataGridLengthUnitType.Star)};RenamePreview.Columns.Add(m3StepColumn);RenamePreview.Columns.Add(new DataGridTextColumn{Header=M3("Final"),Binding=new Binding("NewName"),Width=new(1,DataGridLengthUnitType.Star),MinWidth=100});RenamePreview.Columns.Add(new DataGridTextColumn{Header=M3("State"),Binding=new Binding("Status"){Converter=(IValueConverter)FindResource("LocalizedDisplay")},Width=145});
        M3RenameWorkspace.SizeChanged+=(_,_)=>M3Size();M3LoadCards();M3Size();M3RefreshEnabled();
    }
    void M3Size(){if(m3Columns is null||m3Left is null||m3Right is null||m3ResultScroll is null||m3Narrow is null||m3Splitter is null)return;bool narrow=M3RenameWorkspace.ActualWidth<850;m3Narrow.Visibility=narrow?Visibility.Visible:Visibility.Collapsed;m3Splitter.Visibility=narrow?Visibility.Collapsed:Visibility.Visible;m3Left.Visibility=narrow&&m3ShowResults?Visibility.Collapsed:Visibility.Visible;m3Right.Visibility=m3ResultScroll.Visibility=narrow&&!m3ShowResults?Visibility.Collapsed:Visibility.Visible;m3Columns.ColumnDefinitions[0].MinWidth=narrow?0:320;m3Columns.ColumnDefinitions[0].MaxWidth=narrow?double.PositiveInfinity:420;m3Columns.ColumnDefinitions[0].Width=narrow?new(1,GridUnitType.Star):new(350);m3Columns.ColumnDefinitions[1].Width=new(narrow?0:6);m3Columns.ColumnDefinitions[2].MinWidth=narrow?0:480;m3Columns.ColumnDefinitions[2].Width=narrow?new(0):new(1,GridUnitType.Star);Grid.SetColumn(m3ResultScroll,narrow?0:2);m3Right.Height=Math.Max(520,m3Columns.ActualHeight);}
    void M3LoadCards(){if(!m3Ready||m3Writing)return;try{var rules=RenamePlan.ParseRules(RenameRules.Text);m3Cards.Clear();m3Cards.AddRange(rules.Select(r=>new RenameCard(r)));m3RawError=null;m3Selected=m3Cards.FirstOrDefault();}catch(Exception e){m3RawError=e.Message;m3Cards.Clear();m3Selected=null;}M3RenderCards();}
    void M3Commit(){m3RawError=null;m3Writing=true;try{var next=RenamePlan.EncodeEditorRules(m3Cards.Select(c=>c.Rule));if(next!=RenameRules.Text)RenameRules.Text=next;else RenameRulesChanged(this,new RoutedEventArgs());}finally{m3Writing=false;}M3MarkSelected();M3ShowErrors();M3StepBinding();}
    void M3ShowErrors(){if(m3CardError is null)return;var errors=M3Problems();m3CardError.Text=m3RawError??string.Join("\n",errors);if(errors.Length==0&&m3RawError is null)try{RenamePlan.ValidateRules(RenameRules.Text);}catch(ArgumentException e){m3CardError.Text=L10n.Message(e.Message);}if(m3LocateError is not null)m3LocateError.Visibility=errors.Length>0?Visibility.Visible:Visibility.Collapsed;foreach(var c in m3Cards)if(c.Summary is not null){var problem=M3RuleProblem(c);c.Summary.Text=(problem.Length>0?"⚠ ":"")+M3CardSummary(c);c.Summary.ToolTip=problem.Length>0?problem:M3CardSummary(c);}}
    string M3CardSummary(RenameCard card)=>string.Join(" · ",M3MainFields(card.Rule).Take(3).Select(n=>M3("P"+n)+"="+(card.Invalid.GetValueOrDefault(n)??Convert.ToString(typeof(RenameRule).GetProperty(n)!.GetValue(card.Rule),CultureInfo.InvariantCulture))));
    string M3CardName(RenameCard c)=>c.Rule.Kind=="action"&&RenameTransform.Actions.TryGetValue(c.Rule.Action,out var id)?M3("Action"+id):M3("Legacy"+c.Rule.Kind);
    void M3RenderCards(){if(m3CardPanel is null)return;m3CardPanel.Children.Clear();if(m3Selected?.Expanded==true)foreach(var c in m3Cards.Where(c=>c!=m3Selected))c.Expanded=false;foreach(var card in m3Cards){
        var body=new StackPanel();var border=new Border{Child=body,Padding=new(9),Margin=new(0,0,0,8),BorderThickness=new(1),BorderBrush=SystemColors.ControlDarkBrush,CornerRadius=new(5),AllowDrop=true,Tag=card};m3CardPanel.Children.Add(border);
        var header=new DockPanel{LastChildFill=true};var on=new CheckBox{Content=M3("Enabled"),IsChecked=card.Rule.Enabled,VerticalAlignment=VerticalAlignment.Center,Margin=new(2,0,6,0)};DockPanel.SetDock(on,Dock.Left);header.Children.Add(on);on.Click+=(_,_)=>{card.Rule=card.Rule with{Enabled=on.IsChecked==true};M3Commit();};
        var more=new Button{Content="⋯",Padding=new(6,0,6,0),ToolTip=L10n.Text("规则操作")};DockPanel.SetDock(more,Dock.Right);AutomationProperties.SetName(more,L10n.Text("规则操作"));header.Children.Add(more);var menu=new ContextMenu();void Add(string key,RoutedEventHandler action){var item=new MenuItem{Header=M3(key)};item.Click+=action;menu.Items.Add(item);}Add("Select",(_,_)=>{m3Selected=card;M3MarkSelected();M3StepBinding();});Add("Copy",(_,_)=>{var copy=new RenameCard(card.Rule with{Filters=card.Rule.Filters.ToArray()});foreach(var x in card.Invalid)copy.Invalid[x.Key]=x.Value;m3Cards.Insert(m3Cards.IndexOf(card)+1,copy);M3Commit();M3RenderCards();});Add("Delete",(_,_)=>{m3Cards.Remove(card);M3Commit();M3RenderCards();});Add("Up",(_,_)=>M3MoveCard(card,-1));Add("Down",(_,_)=>M3MoveCard(card,1));more.ContextMenu=menu;more.Click+=(_,_)=>{menu.PlacementTarget=more;menu.IsOpen=true;};
        border.PreviewKeyDown+=(_,e)=>{var key=e.Key==Key.System?e.SystemKey:e.Key;if(Keyboard.Modifiers==ModifierKeys.Alt&&key is Key.Up or Key.Down){M3MoveCard(card,key==Key.Up?-1:1);e.Handled=true;}};
        var drag=new TextBlock{Text=$"{m3Cards.IndexOf(card)+1}. {M3CardName(card)}",FontWeight=FontWeights.SemiBold,Cursor=Cursors.SizeAll,VerticalAlignment=VerticalAlignment.Center,TextTrimming=TextTrimming.CharacterEllipsis,ToolTip=M3CardName(card)};header.Children.Add(drag);Point start=default;drag.PreviewMouseLeftButtonDown+=(_,e)=>start=e.GetPosition(drag);drag.MouseMove+=(_,e)=>{if(e.LeftButton==MouseButtonState.Pressed&&(e.GetPosition(drag)-start).Length>8)DragDrop.DoDragDrop(drag,new DataObject("PhotoTrail.RenameCard",card),DragDropEffects.Move);};border.DragOver+=(_,e)=>{e.Effects=e.Data.GetDataPresent("PhotoTrail.RenameCard")?DragDropEffects.Move:DragDropEffects.None;e.Handled=true;};border.Drop+=(_,e)=>{if(e.Data.GetData("PhotoTrail.RenameCard") is RenameCard from&&from!=card){int at=m3Cards.IndexOf(card);m3Cards.Remove(from);m3Cards.Insert(Math.Min(at,m3Cards.Count),from);M3Commit();M3RenderCards();}e.Handled=true;};
        var parameters=new StackPanel();var expansion=new Expander{Header=header,IsExpanded=card.Expanded,Content=parameters,HorizontalContentAlignment=HorizontalAlignment.Stretch};card.Editor=expansion;AutomationProperties.SetName(expansion,$"{m3Cards.IndexOf(card)+1}. {M3CardName(card)}");expansion.Expanded+=(_,_)=>{card.Expanded=true;m3Selected=card;foreach(var other in m3Cards.Where(c=>c!=card))if(other.Editor is not null)other.Editor.IsExpanded=false;M3MarkSelected();M3StepBinding();};expansion.Collapsed+=(_,_)=>card.Expanded=false;body.Children.Add(expansion);
        card.Summary=new TextBlock{TextWrapping=TextWrapping.NoWrap,TextTrimming=TextTrimming.CharacterEllipsis,Opacity=.8,Margin=new(20,4,2,0)};body.Children.Add(card.Summary);
        foreach(var property in M3MainFields(card.Rule))M3Field(parameters,card,property);
        var extra=new StackPanel();var advanced=new Expander{Header=M3("More"),Content=extra};parameters.Children.Add(advanced);foreach(var property in M3ExtraFields(card.Rule))M3Field(extra,card,property);
        advanced.Visibility=M3ExtraFields(card.Rule).Length==0?Visibility.Collapsed:Visibility.Visible;
        if(card.Rule.Kind=="action"&&card.Rule.Action=="filter-following")M3Filters(parameters,card);
    }M3MarkSelected();M3ShowErrors();M3StepBinding();}
    void M3MarkSelected(){if(m3CardPanel is null)return;foreach(var border in m3CardPanel.Children.OfType<Border>())border.BorderBrush=ReferenceEquals(border.Tag,m3Selected)?SystemColors.HighlightBrush:SystemColors.ControlDarkBrush;}
    void M3MoveCard(RenameCard card,int delta){int at=m3Cards.IndexOf(card),to=at+delta;if(to<0||to>=m3Cards.Count)return;m3Cards.RemoveAt(at);m3Cards.Insert(to,card);M3Commit();M3RenderCards();}
    static string[] M3MainFields(RenameRule r){
        if(r.Kind!="action")return r.Kind switch{"upper" or "lower" or "date-set"=>[],"sequence"=>["Start","Step","Padding"],"sequence-prefix"=>["Start","Step","Padding","Text"],"replace"=>["Text","Replacement"],_=>["Text"]};
        int n=RenameTransform.Actions[r.Action];if(n==98)return[];
        var fields=new List<string>{"Part"};
        if(n is >=40 and <=45)fields.AddRange(["DateSource","DateFormat","TimeZone","NightHour"]);
        else if(n is >=46 and <=51 or >=54 and <=59)fields.AddRange(["Start","Step","Padding","Prefix","Suffix"]);
        else if(n is >=60 and <=65)fields.AddRange(["AlphabetStart","AlphabetWidth","Step","Prefix","Suffix"]);
        else if(n==52)fields.AddRange(["NumberOperation","NumberValue","Padding"]);
        else if(n is 24 or 25 or 38)fields.Add("Length");
        else if(n is 26 or 27){fields.AddRange(["Position","Length"]);if(n==27)fields.Add("Start");}
        else if(n is >=100 and <=111)fields.AddRange(["MetadataField","Prefix","Suffix"]);
        else if(n is >=78 and <=93){fields.AddRange(["Text","Prefix","Suffix"]);if(n>=89)fields.AddRange(["Position","Length"]);}
        else if(n is 9 or 10 or 11 or 17 or 95 or 96)fields.AddRange(["Text","Replacement"]);
        else if(n<=19||n is >=66 and <=71 or 94 or 97)fields.Add("Text");
        if(n is 3 or 4 or 15 or 16 or 43 or 44 or 49 or 50 or 57 or 58 or 63 or 64 or 70 or 71 or 81 or 82 or 86 or 87 or 91 or 92 or 104 or 105 or 110 or 111)fields.Add("Anchor");
        if(n is 5 or 14 or 45 or 51 or 59 or 65 or 69 or 83 or 88 or 93 or 103 or 109)fields.Add("Position");
        return fields.Distinct().ToArray();
    }
    static string[] M3ExtraFields(RenameRule r){
        if(r.Kind!="action")return[];int n=RenameTransform.Actions[r.Action];var fields=new List<string>();
        if(n<=19||n is 43 or 44 or 49 or 50 or 52 or 53 or 57 or 58 or 63 or 64 or 70 or 71 or 81 or 82 or 86 or 87 or 91 or 92 or 94 or 95 or 96 or 104 or 105 or 110 or 111)fields.AddRange(["Occurrence","MatchNumber","CaseSensitive"]);
        if(n is >=40 and <=45 or >=66 and <=71 or >=78 and <=93 or >=100 and <=111)fields.Add("SkipMissing");
        if(n is >=66 and <=71)fields.AddRange(["TimeZone","NightHour"]);
        if(n is >=46 and <=51)fields.AddRange(["PerDirectory","Counter"]);
        if(n is >=54 and <=65 or 94)fields.Add("PerDirectory");
        if(n is >=54 and <=59 or 98)fields.Add("CaseSensitive");
        if(n is 94 or 96)fields.Add("FullMatch");
        if(n==98)fields.AddRange(["TimeZone","NightHour"]);
        return fields.Distinct().Except(M3MainFields(r)).ToArray();
    }
    static readonly Dictionary<string,string[]> M3Choices=new(){["Part"]=["stem","entire","dottedExtension","extensionOnly"],["Occurrence"]=["all","first","last","nth"],["DateSource"]=["shooting","created","modified","now"],["NumberOperation"]=["add","subtract","multiply","divide","set"]};
    ComboBox M3ChoiceBox(IEnumerable<string> ids,string? value)=>new(){ItemsSource=ids.Select(id=>new KeyValuePair<string,string>(id,M3("V"+id))).ToArray(),DisplayMemberPath="Value",SelectedValuePath="Key",SelectedValue=value,MinWidth=100};
    void M3Field(Panel parent,RenameCard card,string name){var property=typeof(RenameRule).GetProperty(name)!;var row=new StackPanel{Margin=new(2,4,2,3)};parent.Children.Add(row);row.Children.Add(new TextBlock{Text=M3("P"+name),Opacity=.8,TextWrapping=TextWrapping.Wrap});
        void Set(object? value){property.SetValue(card.Rule,value);card.Invalid.Remove(name);M3Commit();}
        var value=property.GetValue(card.Rule);if(property.PropertyType==typeof(bool)){var check=new CheckBox{Content=M3("P"+name),IsChecked=(bool)value!};AutomationProperties.SetName(check,M3("P"+name));row.Children.Add(check);check.Click+=(_,_)=>Set(check.IsChecked==true);return;}
        if(M3Choices.TryGetValue(name,out var choices)){var combo=M3ChoiceBox(choices,(string?)value);AutomationProperties.SetName(combo,M3("P"+name));row.Children.Add(combo);combo.SelectionChanged+=(_,_)=>{if(combo.SelectedValue is string selected)Set(selected);};return;}
        var box=new TextBox{Text=card.Invalid.GetValueOrDefault(name)??Convert.ToString(value,CultureInfo.InvariantCulture)??"",MinWidth=80,MaxLength=name=="Text"&&card.Rule.Action=="name-list"?16384:1024};if(name=="Text"&&card.Rule.Action=="name-list"){box.AcceptsReturn=true;box.Height=90;box.VerticalScrollBarVisibility=ScrollBarVisibility.Auto;}AutomationProperties.SetName(box,M3("P"+name));AutomationProperties.SetAutomationId(box,"M6RenameParam."+name);row.Children.Add(box);box.TextChanged+=(_,_)=>{if(property.PropertyType==typeof(int)&&!int.TryParse(box.Text,NumberStyles.Integer,CultureInfo.InvariantCulture,out _ )||property.PropertyType==typeof(long)&&!long.TryParse(box.Text,NumberStyles.Integer,CultureInfo.InvariantCulture,out _)){card.Invalid[name]=box.Text;box.BorderBrush=Brushes.Firebrick;M3Commit();return;}box.ClearValue(Control.BorderBrushProperty);Set(property.PropertyType==typeof(int)?(object)int.Parse(box.Text,CultureInfo.InvariantCulture):property.PropertyType==typeof(long)?(object)long.Parse(box.Text,CultureInfo.InvariantCulture):box.Text);};}
    void M3Filters(Panel parent,RenameCard card){var any=new ComboBox{ItemsSource=new[]{M3("All"),M3("Any")},SelectedIndex=card.Rule.FilterAny?1:0,Margin=new(2,5,2,5)};parent.Children.Add(any);any.SelectionChanged+=(_,_)=>{card.Rule=card.Rule with{FilterAny=any.SelectedIndex==1};M3Commit();};foreach(var condition in card.Rule.Filters){int at=Array.IndexOf(card.Rule.Filters,condition);var panel=new StackPanel{Margin=new(2,4,2,6)};parent.Children.Add(panel);var field=M3ChoiceBox(["name","fileExtension","shootingDate","comment"],condition.Field);var compare=M3ChoiceBox(["contains","notContains","equals","notEquals","starts","ends","before","after","exists","missing"],condition.Comparison);var text=new TextBox{Text=condition.Value,MaxLength=1024};AutomationProperties.SetName(field,M3("PField"));AutomationProperties.SetName(compare,M3("PComparison"));AutomationProperties.SetName(text,M3("PValue"));panel.Children.Add(field);panel.Children.Add(compare);panel.Children.Add(text);void Change(){var conditions=card.Rule.Filters.ToArray();conditions[at]=new((string)field.SelectedValue,(string)compare.SelectedValue,text.Text);card.Rule=card.Rule with{Filters=conditions};M3Commit();}field.SelectionChanged+=(_,_)=>Change();compare.SelectionChanged+=(_,_)=>Change();text.TextChanged+=(_,_)=>Change();if(card.Rule.Filters.Length>1)panel.Children.Add(M3Button("Delete",(_,_)=>{card.Rule=card.Rule with{Filters=card.Rule.Filters.Where((_,i)=>i!=at).ToArray()};M3Commit();M3RenderCards();}));}parent.Children.Add(M3Button("Condition",(_,_)=>{if(card.Rule.Filters.Length>=32)return;card.Rule=card.Rule with{Filters=card.Rule.Filters.Append(new("name","contains","")).ToArray()};M3Commit();M3RenderCards();}));}
    void M3AddAction(){if(busy||renameRecoveryRequired)return;var body=new DockPanel();var search=new TextBox{Margin=new(5),MinWidth=250};AutomationProperties.SetName(search,M3("Search"));AutomationProperties.SetAutomationId(search,"M3ActionSearch");DockPanel.SetDock(search,Dock.Top);body.Children.Add(search);var list=new StackPanel();body.Children.Add(new ScrollViewer{Content=list,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});var window=M3Dialog("Add",body,570,650);void Fill(){list.Children.Clear();for(int id=1;id<=111;id++){var number=id;string label=M3("Category"+id)+" · "+M3("Action"+id);if(!label.Contains(search.Text,StringComparison.CurrentCultureIgnoreCase))continue;var action=RenameTransform.Actions.FirstOrDefault(p=>p.Value==id).Key;var button=new Button{Content=label,HorizontalContentAlignment=HorizontalAlignment.Left,Margin=new(3),Padding=new(7),IsEnabled=action is not null||id==99,ToolTip=action is null&&id!=99?M3("Unavailable"):null};AutomationProperties.SetAutomationId(button,action is not null?"M3AddAction."+action:"M3Catalog."+number);list.Children.Add(button);button.Click+=(_,_)=>{if(number==99){window.Close();M3InputSettings();return;}if(m3Cards.Count>=64)return;var card=new RenameCard(new("action"){Action=action!});card.Expanded=true;m3Cards.Add(card);m3Selected=card;M3Commit();M3RenderCards();window.Close();};}}search.TextChanged+=(_,_)=>Fill();Fill();window.ShowDialog();}
    Window M3Dialog(string title,object content,double width,double height){
        var body=new DockPanel();var cancel=M3Button("CancelTask",CancelRead);cancel.HorizontalAlignment=HorizontalAlignment.Right;cancel.SetBinding(UIElement.VisibilityProperty,new Binding("Visibility"){Source=M1TaskPanel});DockPanel.SetDock(cancel,Dock.Bottom);body.Children.Add(cancel);body.Children.Add((UIElement)content);
        var window=new Window{Title=M3(title),Owner=this,Resources=Resources,FontSize=metadataBaseFont+settings.FontDelta,FontFamily=FontFamily,Content=body,Width=Math.Min(width,SystemParameters.WorkArea.Width-30),Height=Math.Min(height,SystemParameters.WorkArea.Height-40),MinWidth=360,MinHeight=300,WindowStartupLocation=WindowStartupLocation.CenterOwner,ShowInTaskbar=false,};
#pragma warning disable WPF0001
        window.ThemeMode=ThemeMode;
#pragma warning restore WPF0001
        window.Closing+=(_,e)=>{if(busy){CancelRead(this,new RoutedEventArgs());e.Cancel=true;}};
        window.PreviewKeyDown+=(_,e)=>{if(e.Key==Key.Escape){window.Close();e.Handled=true;}};return window;}
    void M3Borrow(string title,FrameworkElement[] controls,double width=760,double height=650){if(busy)return;var panel=new StackPanel{Margin=new(12)};var placements=controls.Select(c=>(Control:c,Parent:c.Parent,Index:c.Parent is Panel p?p.Children.IndexOf(c):0)).ToArray();foreach(var c in controls)M3Move(panel,c);var window=M3Dialog(title,new ScrollViewer{Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto},width,height);try{window.ShowDialog();}finally{foreach(var item in placements){M3Detach(item.Control);if(item.Parent is Panel p)p.Children.Insert(Math.Min(item.Index,p.Children.Count),item.Control);else if(item.Parent is Decorator d)d.Child=item.Control;else if(item.Parent is ContentControl c)c.Content=item.Control;}}}
    void M3InputSettings(){var conflict=(FrameworkElement)((FrameworkElement)RenameConflictChoice.Parent).Parent;M3Borrow("Settings",[RenameProcessingControls,conflict]);}
    void M3GroupOrder(){M3Borrow("Groups",[RenameGroups,RenameDropHint,(FrameworkElement)RenameUndoOrder.Parent],650,650);}
    void M3History(){
        if(busy)return;
        var list=new ListBox{Height=250,DisplayMemberPath="Value",Margin=new(2,6,2,6)};AutomationProperties.SetName(list,M3("History"));
        var status=new TextBlock{Text=M3("PickRecord"),TextWrapping=TextWrapping.Wrap,Margin=new(2,5,2,8)};
        try{list.ItemsSource=System.IO.Directory.Exists(RenameJournalDirectory)?System.IO.Directory.EnumerateFiles(RenameJournalDirectory,"rename-*.jsonl").OrderByDescending(System.IO.File.GetLastWriteTimeUtc).Select(path=>new KeyValuePair<string,string>(path,System.IO.Path.GetFileName(path))).ToArray():[];}catch(Exception error){status.Text=M3("RecordReadFailed")+error.Message;}
        list.SelectionChanged+=(_,_)=>{if(list.SelectedItem is not KeyValuePair<string,string> selected)return;RenameJournalPath.Text=selected.Key;try{var record=RenameExecutor.ReadJournal(selected.Key);status.Text=string.Format(CultureInfo.CurrentCulture,M3("RecordSummary"),record.Files.Count,record.Complete?M3("RecordComplete"):M3("RecordPartial"));}catch(Exception error){status.Text=M3("RecordReadFailed")+error.Message;}};
        var oldParent=(Panel)RenameJournalPath.Parent;int oldIndex=oldParent.Children.IndexOf(RenameJournalPath);M3Detach(RenameJournalPath);var advanced=new Expander{Header=M3("RecordPath"),Content=RenameJournalPath};
        try{M3Borrow("History",[list,status,new TextBlock{Text=M3("Journal"),TextWrapping=TextWrapping.Wrap},advanced,RestoreRenameButton],760,560);}finally{advanced.Content=null;oldParent.Children.Insert(Math.Min(oldIndex,oldParent.Children.Count),RenameJournalPath);}
    }
    void M3Advanced(){RenameRules.Height=280;M3Borrow("Advanced",[new TextBlock{Text=M3("RawHelp"),TextWrapping=TextWrapping.Wrap},RenameRules],760,430);}
    void M3SchemeLibrary(){
        if(busy||renameRecoveryRequired)return;
        var grid=new Grid{Margin=new(12)};grid.ColumnDefinitions.Add(new(){Width=new(250)});grid.ColumnDefinitions.Add(new());
        var left=new DockPanel{Margin=new(0,0,12,0)};grid.Children.Add(left);var search=new TextBox{Margin=new(3,0,3,8),ToolTip=M3("Search")};AutomationProperties.SetName(search,M3("Search"));AutomationProperties.SetAutomationId(search,"M3SchemeSearch");DockPanel.SetDock(search,Dock.Top);left.Children.Add(search);
        var list=new ListBox{DisplayMemberPath="Name"};AutomationProperties.SetName(list,M3("Library"));list.SetBinding(ItemsControl.ItemsSourceProperty,new Binding("ItemsSource"){Source=RenameSchemeList});list.SetBinding(System.Windows.Controls.Primitives.Selector.SelectedItemProperty,new Binding("SelectedItem"){Source=RenameSchemeList,Mode=BindingMode.TwoWay});left.Children.Add(list);
        var panel=new StackPanel{Margin=new(5)};Grid.SetColumn(panel,1);grid.Children.Add(new ScrollViewer{Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto});Grid.SetColumn(grid.Children[^1],1);
        var controls=new FrameworkElement[]{RenameSchemeName,RenameSchemeExample,RenameSchemeActions};var placements=controls.Select(c=>(Control:c,Parent:(Panel)c.Parent,Index:((Panel)c.Parent).Children.IndexOf(c),Width:c.Width,Alignment:c.HorizontalAlignment)).ToArray();
        foreach(var c in controls){if(c==RenameSchemeName||c==RenameSchemeExample){panel.Children.Add(new TextBlock{Text=M3(c==RenameSchemeName?"Name":"Example"),Margin=new(3,8,3,4)});c.Width=double.NaN;c.HorizontalAlignment=HorizontalAlignment.Stretch;}M3Move(panel,c);}
        foreach(var button in RenameSchemeActions.Children.OfType<Button>()){button.Margin=new(3);button.Padding=new(8,5,8,5);}
        search.TextChanged+=(_,_)=>{if(list.ItemsSource is null)return;CollectionViewSource.GetDefaultView(list.ItemsSource).Filter=item=>item is RenameScheme scheme&&scheme.Name.Contains(search.Text,StringComparison.CurrentCultureIgnoreCase);};
        var window=M3Dialog("Library",grid,850,550);try{window.ShowDialog();}finally{if(list.ItemsSource is not null)CollectionViewSource.GetDefaultView(list.ItemsSource).Filter=null;BindingOperations.ClearAllBindings(list);foreach(var item in placements){M3Detach(item.Control);item.Control.Width=item.Width;item.Control.HorizontalAlignment=item.Alignment;item.Parent.Children.Insert(Math.Min(item.Index,item.Parent.Children.Count),item.Control);}}
    }
    sealed class RenameStepConverter(MainWindow owner,int step):IValueConverter {public object Convert(object value,Type targetType,object parameter,CultureInfo culture)=>value is RenameFile file&&owner.m3Steps.TryGetValue(file.Source,out var steps)&&step>=0&&step<steps.Length?steps[step]:"—";public object ConvertBack(object value,Type targetType,object parameter,CultureInfo culture)=>Binding.DoNothing;}
    void M3StepBinding(){if(m3StepColumn is null)return;int step=m3Selected is null?-1:m3Cards.TakeWhile(c=>c!=m3Selected).Count(c=>c.Rule.Enabled);if(m3Selected?.Rule.Enabled!=true)step=-1;m3StepColumn.Header=M3("SelectStep")+(m3Selected is null?"":" · "+(m3Cards.IndexOf(m3Selected)+1));m3StepColumn.Binding=new Binding{Converter=new RenameStepConverter(this,step)};}
}
