using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text;

namespace PhotoTrail.Windows;

public record RenameRule(string Kind, string Text = "", string Replacement = "", long Start = 1, long Step = 1, int Padding = 3)
{
    public Guid? Id { get; init; }
    public string Action { get; init; } = "date-set";
    public bool Enabled { get; init; } = true;
    public string Part { get; init; } = "stem";
    public string Occurrence { get; init; } = "all";
    public int MatchNumber { get; init; } = 1;
    public bool CaseSensitive { get; init; } = true;
    public string Anchor { get; init; } = "";
    public int Position { get; init; }
    public int Length { get; init; } = 1;
    public string Prefix { get; init; } = "";
    public string Suffix { get; init; } = "";
    public string? MetadataField { get; init; }
    public string DateSource { get; init; } = "shooting";
    public string DateFormat { get; init; } = "yyyyMMdd_HHmmss";
    public string TimeZone { get; init; } = "source";
    public int NightHour { get; init; }
    public bool SkipMissing { get; init; } = true;
    public bool FullMatch { get; init; }
    public string AlphabetStart { get; init; } = "A";
    public int AlphabetWidth { get; init; } = 1;
    public string NumberOperation { get; init; } = "add";
    public long NumberValue { get; init; } = 1;
    public bool PerDirectory { get; init; }
    public int Counter { get; init; }
    public bool FilterAny { get; init; }
    public RenameFilterCondition[] Filters { get; init; } = [new("name","contains","")];
}
public sealed record RenameFilterCondition(string Field,string Comparison,string Value) { public Guid? Id { get; init; } }
public record RenameFile(string Source, string Target, string Hash)
{
    internal FileProperties? Properties { get; init; }
    public string Steps { get; init; } = "";
    public string OriginalName => Path.GetFileName(Source);
    public string NewName => Path.GetFileName(Target);
    public string Status => Source == Target ? "无需更名" : "预览；尚未执行";
}
public sealed record RenamePlan(ReadOnlyCollection<RenameFile> Files,bool ExplicitGroups=false)
{
    internal IReadOnlyList<RenameRule> SourceRules { get; init; } = [];
    internal RenameCounterUse? CounterUse { get; init; }
    internal RenameOrderSettings? GroupSettings {get;init;}
    public static IReadOnlyList<RenameRule> ParseRules(string text)
    {
        if (text.Length > 32768 || text.Any(c => char.IsControl(c) && c is not ('\r' or '\n'))) throw new ArgumentException("规则文字超过上限或含控制字符。");
        var result = new List<RenameRule>();
        foreach (var line in text.Split('\n').Where(value => value.Trim().Length > 0))
        {
            if (line.TrimStart().StartsWith('{')) {
                result.Add(ParseSerializedRule(line));
                if(result.Count>64)throw new ArgumentException("规则最多64条。");
                continue;
            }
            var parts = line.TrimEnd('\r').Split('|');
            var kind = parts[0] switch { "前缀" => "prefix", "后缀" => "suffix", "替换" => "replace", "设名" => "set", "大写" => "upper", "小写" => "lower", "序号" => "sequence", _ => parts[0] };
            if (kind == "sequence" && parts.Length == 4 && int.TryParse(parts[1], out var start) && int.TryParse(parts[2], out var step) && int.TryParse(parts[3], out var padding)) result.Add(new(kind, Start:start, Step:step, Padding:padding));
            else if (kind is "prefix" or "suffix" or "set" or "date-prefix" or "city-prefix" or "model-suffix" && parts.Length == 2) result.Add(new(kind, parts[1]));
            else if (kind == "replace" && parts.Length == 3) result.Add(new(kind, parts[1], parts[2]));
            else if (kind == "sequence-prefix" && parts.Length == 5 && int.TryParse(parts[1],out start) && int.TryParse(parts[2],out step) && int.TryParse(parts[3],out padding)) result.Add(new(kind,parts[4],Start:start,Step:step,Padding:padding));
            else if (kind is "upper" or "lower" or "date-set" && parts.Length == 1) result.Add(new(kind));
            else throw new ArgumentException("规则格式无效；请参考上方例子。");
            if (result.Count > 64) throw new ArgumentException("规则最多64条。");
        }
        var counters=result.Where(r=>r.Enabled&&r.Counter>0).Select(r=>r.Counter).ToArray();if(counters.Distinct().Count()!=counters.Length)throw new ArgumentException("同一方案不能重复使用持续计数槽位。");
        return result;
    }
    sealed record LegacyEditorRule(string Kind,string Text="",string Replacement="",long Start=1,long Step=1,int Padding=3,bool Enabled=true);
    // Typed cards retain legacy rule kinds exactly; new actions still use the existing strict action decoder.
    static RenameRule ParseSerializedRule(string text) {
        try {
        using var json=System.Text.Json.JsonDocument.Parse(text,new(){MaxDepth=4});
        if(json.RootElement.ValueKind!=System.Text.Json.JsonValueKind.Object||json.RootElement.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()!=json.RootElement.EnumerateObject().Count())throw new ArgumentException("参数规则字段重复或类型错误。");
        if(!json.RootElement.TryGetProperty("Kind",out var kind)||kind.ValueKind!=System.Text.Json.JsonValueKind.String)throw new ArgumentException("参数规则Kind缺失。");
        if(kind.GetString()=="action")return RenameTransform.Parse(text);
        var legacy=System.Text.Json.JsonSerializer.Deserialize<LegacyEditorRule>(text,new System.Text.Json.JsonSerializerOptions{UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow,MaxDepth=4})??throw new ArgumentException("旧规则缺失。");
        if(legacy.Kind is not("prefix" or "suffix" or "set" or "replace" or "upper" or "lower" or "sequence" or "sequence-prefix" or "date-set" or "date-prefix" or "city-prefix" or "model-suffix")||legacy.Text is null||legacy.Replacement is null)throw new ArgumentException("旧规则类型或参数无效。");
        if(legacy.Text.Length>256||legacy.Replacement.Length>256||legacy.Text.Any(char.IsControl)||legacy.Replacement.Any(char.IsControl)||legacy.Kind is "sequence" or "sequence-prefix"&&(legacy.Start<0||legacy.Step<=0||legacy.Padding is <1 or >9)||legacy.Kind=="replace"&&legacy.Text.Length==0)throw new ArgumentException("旧规则参数无效。");
        _=new UTF8Encoding(false,true).GetByteCount(legacy.Text);_=new UTF8Encoding(false,true).GetByteCount(legacy.Replacement);
        return new(legacy.Kind,legacy.Text,legacy.Replacement,legacy.Start,legacy.Step,legacy.Padding){Enabled=legacy.Enabled};
        }catch(System.Text.Json.JsonException error){throw new ArgumentException("参数规则JSON无效："+error.Message);}
    }
    internal static string EncodeEditorRules(IEnumerable<RenameRule> rules)=>string.Join("\n",rules.Select(r=>r.Kind=="action"?EncodeAction(r):System.Text.Json.JsonSerializer.Serialize(new LegacyEditorRule(r.Kind,r.Text,r.Replacement,r.Start,r.Step,r.Padding,r.Enabled))));
    static string EncodeAction(RenameRule rule) {
        var data=System.Text.Json.JsonSerializer.SerializeToElement(rule);var defaults=System.Text.Json.JsonSerializer.SerializeToElement(new RenameRule("action"));
        return System.Text.Json.JsonSerializer.Serialize(data.EnumerateObject().Where(p=>p.Name is "Kind" or "Action"||p.Value.GetRawText()!=defaults.GetProperty(p.Name).GetRawText()).ToDictionary(p=>p.Name,p=>p.Value));
    }
    public static bool ValidName(string name)
    {
        if (name.Length is < 1 or > 255 || name is "." or ".." || name.EndsWith(' ') || name.EndsWith('.') || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return false;
        try { new UTF8Encoding(false,true).GetByteCount(name); } catch (EncoderFallbackException) { return false; }
        var first = name.Split('.')[0].TrimEnd(' ').ToUpperInvariant();
        if (first is "CON" or "PRN" or "AUX" or "NUL" or "CONIN$" or "CONOUT$") return false;
        return !(first.Length == 4 && (first.StartsWith("COM") || first.StartsWith("LPT")) && "123456789¹²³".Contains(first[3]));
    }
    public static string Apply(string name,IReadOnlyList<RenameRule> rules,int index,Func<string,string?>? metadata=null) {
        RenameLaunchSupport.RequireAvailable(rules);
        if(UsesDates(rules))throw new InvalidOperationException("日期命名规则须异步共享验证。");
        return ApplyVerified(name,rules,index,metadata,null);
    }
    public static async Task<string> ApplyAsync(string name,IReadOnlyList<RenameRule> rules,int index,Func<string,string?>? metadata=null,CancellationToken token=default) {
        var frozenRules=rules.ToArray();RenameLaunchSupport.RequireAvailable(frozenRules);string? captured=frozenRules.Any(r=>r.Kind is "date-set" or "date-prefix")?Required(metadata,"captured"):null;
        var texts=new List<string>();if(captured is not null)texts.Add(VerifiedPhotoDate.Bridge(captured));if(UsesDates(frozenRules))foreach(var key in new[]{"captured","File:FileCreateDate","File:FileModifyDate","PhotoTrail:RenameReferenceDate"})if(metadata?.Invoke(key) is {} raw)texts.Add(RenameInput.BridgeDate(raw));
        var dates=await RenameTransform.PrepareDatesAsync(texts,frozenRules,token);
        return ApplyVerified(name,frozenRules,index,metadata,captured is null?null:dates.GetValueOrDefault(VerifiedPhotoDate.Bridge(captured)),dates);
    }
    internal static string ApplyVerified(string name,IReadOnlyList<RenameRule> rules,int index,Func<string,string?>? metadata,VerifiedPhotoDate? date,IReadOnlyDictionary<string,VerifiedPhotoDate?>? dates=null,List<string>? steps=null,Func<int,int>? ordinal=null,Action<int,int,bool>? completed=null)
    {
        RenameLaunchSupport.RequireAvailable(rules);
        if (rules.Count > 64 || index < 0) throw new ArgumentException("规则数量或序号无效。");
        var original=name;bool included=true;
        foreach (var (rule,ruleIndex) in rules.Select((r,i)=>(r,i)).Where(p=>p.r.Enabled))
        {
            if(rule.Kind=="action"&&rule.Action=="filter-following") { included=RenameTransform.MatchesFilter(original,rule,metadata,date,dates);steps?.Add(name+(included?"":" [excluded]"));continue; }
            if(!included){steps?.Add(name+" [excluded]");continue;}
            int itemIndex=ordinal?.Invoke(ruleIndex)??index;
            if(rule.Kind=="action") {
                var transformed=RenameTransform.Apply(name,rule,itemIndex,metadata,date,dates);
                name=transformed.Skip?original:transformed.Name;steps?.Add(name+(transformed.Issue is null?"":" ["+transformed.Issue+"]"));
                completed?.Invoke(ruleIndex,itemIndex,transformed.Issue is null);
                if(transformed.Skip)break;
                continue;
            }
            var (stem,extension)=RenameTransform.Split(name);
            if (rule.Text.Length > 256 || rule.Replacement.Length > 256) throw new ArgumentException("规则文字过长。");
            stem = rule.Kind switch
            {
                "date-set" => CaptureName(metadata,date),
                "date-prefix" => CaptureName(metadata,date)+rule.Text+stem,
                "city-prefix" => Required(metadata,"city")+rule.Text+stem,
                "model-suffix" => stem+rule.Text+Required(metadata,"model"),
                "sequence-prefix" when rule.Start>=0 && rule.Step>0 && rule.Padding is >=1 and <=9 => checked(rule.Start+(long)itemIndex*rule.Step).ToString("D"+rule.Padding,CultureInfo.InvariantCulture)+rule.Text+stem,
                "prefix" => rule.Text + stem,
                "suffix" => stem + rule.Text,
                "set" => rule.Text,
                "replace" when rule.Text.Length > 0 => stem.Replace(rule.Text, rule.Replacement, StringComparison.Ordinal),
                "upper" => stem.ToUpperInvariant(),
                "lower" => stem.ToLowerInvariant(),
                "sequence" when rule.Start >= 0 && rule.Step > 0 && rule.Padding is >= 1 and <= 9 => stem + checked(rule.Start + (long)itemIndex * rule.Step).ToString("D" + rule.Padding, CultureInfo.InvariantCulture),
                _ => throw new ArgumentException("规则无效或尚未支持。")
            };
            if (stem.Length > 255) throw new ArgumentException("生成文件名过长。");
            name=stem+extension;steps?.Add(name);
            completed?.Invoke(ruleIndex,itemIndex,true);
        }
        var target = name;
        if (!ValidName(target)) throw new ArgumentException("生成名称违反Windows文件名规则。");
        return target;
    }
    internal static bool UsesDates(IReadOnlyList<RenameRule> rules)=>rules.Any(r=>r.Enabled&&(r.Kind is "date-set" or "date-prefix"||r.Kind=="action"&&RenameTransform.NeedsDates(r)));
    internal static bool UsesMetadata(IReadOnlyList<RenameRule> rules)=>rules.Any(r=>r.Kind is "date-set" or "date-prefix" or "city-prefix" or "model-suffix"||r.Kind=="action");
    internal static bool UsesNewRules(IReadOnlyList<RenameRule> rules)=>UsesMetadata(rules)||rules.Any(r=>r.Kind=="sequence-prefix");
    internal static bool RequiresV3(IReadOnlyList<RenameRule> rules)=>rules.Any(r=>r.Counter>0||r.PerDirectory||!r.Enabled||r.Action=="filter-following"||r.Kind=="action"&&RenameTransform.Actions.TryGetValue(r.Action,out var n)&&(n is >=46 and <=65||n==94));
    internal static void ValidateRules(string text) {
        _=new UTF8Encoding(false,true).GetByteCount(text);var rules=ParseRules(text);
        if(!UsesNewRules(rules)){_=Apply("sample.jpg",rules,0);return;}
        foreach(var rule in rules) {
            if(rule.Kind=="action"){RenameTransform.Validate(rule);continue;}
            if(rule.Text.Length>256||rule.Replacement.Length>256)throw new ArgumentException("规则文字过长。");
            if(rule.Kind is "sequence" or "sequence-prefix" && (rule.Start<0||rule.Step<=0||rule.Padding is <1 or >9))throw new ArgumentException("编号设置无效。");
            if(rule.Kind=="replace"&&rule.Text.Length==0)throw new ArgumentException("替换文字不能为空。");
        }
    }
    static string Required(Func<string,string?>? metadata,string key)=>metadata?.Invoke(key) is {Length:>0} value?value:throw new ArgumentException(key switch{"city"=>"缺失城市，不能生成名称。","model"=>"缺失设备型号，不能生成名称。",_=>"缺失拍摄时间，不能生成名称。"});
    static string CaptureName(Func<string,string?>? metadata,VerifiedPhotoDate? date) {
        var raw=Required(metadata,"captured");
        if(raw.Length>=19&&raw[4]=='-'&&raw[7]=='-'&&raw[10]=='T')raw=raw[..4]+":"+raw[5..7]+":"+raw[8..10]+" "+raw[11..];
        if(date is null||date.Text!=raw)throw new ArgumentException("拍摄时间未经本次共享验证或已改变，不能生成名称。");
        return date.NameSeconds;
    }
    public static async Task<RenamePlan> BuildAsync(IEnumerable<string> paths, IReadOnlyList<RenameRule> rules, bool sortByName, CancellationToken cancellation = default)
    {
        var inputs = paths.ToArray(); var frozenRules = rules.ToArray();RenameLaunchSupport.RequireAvailable(frozenRules);
        if(frozenRules.Any(r=>r.Counter>0||r.PerDirectory))throw new ArgumentException("持续计数/每目录编号须完整任务上下文冻结，不能用单文件入口执行。");
        if (inputs.Length is < 1 or > 3000) throw new ArgumentException("一次预览须为1至3000个主文件。");
        if (sortByName) inputs = inputs.OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase).ThenBy(x => x, StringComparer.Ordinal).ToArray();
        var targets = inputs.Select((path, index) => (path, Apply(Path.GetFileName(path), frozenRules, index))).ToArray();
        return (await BuildTargetsAsync(targets, cancellation)) with{SourceRules=frozenRules};
    }
    public static async Task<RenamePlan> BuildTargetsAsync(IEnumerable<(string Source, string Name)> targets, CancellationToken cancellation = default, bool includeSidecars = true)
    {
        var inputs = targets.ToArray();
        if (inputs.Length < 1 || inputs.Length > (includeSidecars?3000:6000)) throw new ArgumentException("一次预览最多3000个主文件或6000个已配对物理文件。");
        var pairs = new List<(string Source, string Target)>();
        foreach (var (source, name) in inputs)
        {
            cancellation.ThrowIfCancellationRequested();
            if (!ValidName(name)) throw new ArgumentException("目标名称无效。");
            var full = Path.GetFullPath(source);
            try { new UTF8Encoding(false,true).GetByteCount(full); } catch (EncoderFallbackException) { throw new ArgumentException("源路径Unicode无效，无法形成可靠记录。"); }
            if (!ValidName(Path.GetFileName(full))) throw new ArgumentException("源名称不在Windows安全更名范围内。");
            if (!File.Exists(full) || (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) throw new IOException("源文件缺失或为链接，未安排重命名。");
            var target = Path.Combine(Path.GetDirectoryName(full)!, name);
            pairs.Add((full, target));
            var sidecar = Path.ChangeExtension(full, ".xmp");
            if (includeSidecars && !full.Equals(sidecar, StringComparison.OrdinalIgnoreCase) && File.Exists(sidecar))
            {
                if ((File.GetAttributes(sidecar) & FileAttributes.ReparsePoint) != 0) throw new IOException("旁车为链接，未安排重命名。");
                var sidecarTarget = Path.ChangeExtension(target, ".xmp");
                if (!ValidName(Path.GetFileName(sidecarTarget))) throw new ArgumentException("旁车目标名称无效。");
                pairs.Add((sidecar, sidecarTarget));
            }
        }
        var sources = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var destinations = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (source, target) in pairs)
        {
            if (!sources.Add(source)) throw new IOException("主文件/旁车重复参与，未安排重命名。");
            if (!destinations.Add(target)) throw new IOException("目标名称大小写折叠后冲突。");
        }
        var files = new List<RenameFile>();
        foreach (var (source, target) in pairs)
        {
            cancellation.ThrowIfCancellationRequested();
            if (Directory.Exists(target) || (File.Exists(target) && !sources.Contains(target))) throw new IOException("目标已存在且不在本次源文件中，拒绝覆盖。");
            using var parents=SavePaths.LockParents(source,true);
            using var handle=WindowsRename.Open(source);
            var properties=WindowsRename.Properties(handle,source);
            var hash=Convert.ToHexString(await System.Security.Cryptography.SHA256.HashDataAsync(handle,cancellation));
            if(!WindowsRename.SameProperties(properties,WindowsRename.Properties(handle,source)))throw new IOException("冻结读取期间System属性改变。");
            files.Add(new(source,target,hash){Properties=properties});
        }
        return new(Array.AsReadOnly(files.ToArray()),!includeSidecars);
    }
}

public sealed record RenameRulesPreset(string Rules, bool SortByName, RenameOrderSettings? Order = null)
{
    public const int MaximumBytes = 64 * 1024;
    public static string Encode(string rules, bool sortByName, RenameOrderSettings? order = null)
    {
        var parsed = RenamePlan.ParseRules(rules);
        RenamePlan.ValidateRules(rules);
        if(order is not null||parsed.Any(r=>r.Kind=="action")){
            order??=new(sortByName?"name":"input");order.Validate();var advanced=System.Text.Json.JsonSerializer.Serialize(new{version=3,rules,order},new System.Text.Json.JsonSerializerOptions{PropertyNamingPolicy=System.Text.Json.JsonNamingPolicy.CamelCase});if(Encoding.UTF8.GetByteCount(advanced)>MaximumBytes)throw new ArgumentException("规则文件超过64KiB上限。");return advanced;
        }
        order?.Validate(); var data = new Dictionary<string,object?> { ["version"]=RenamePlan.UsesNewRules(parsed)?2:1,["rules"]=rules,["sortByName"]=sortByName }; if(order is not null){data["sort"]=order.Sort;data["descending"]=order.Descending;if(order.MetadataSortTag is not null)data["metadataSortTag"]=order.MetadataSortTag;} var text = System.Text.Json.JsonSerializer.Serialize(data);
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("规则文件超过64KiB上限。");
        return text;
    }
    public static RenameRulesPreset Decode(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("规则文件超过64KiB上限。");
        try
        {
            using var json = System.Text.Json.JsonDocument.Parse(text.TrimStart('\ufeff')); var root = json.RootElement;
            if(root.ValueKind==System.Text.Json.JsonValueKind.Object&&root.TryGetProperty("version",out var vv)&&vv.TryGetInt32(out var v3)&&v3==3){
                var properties=root.EnumerateObject().ToArray();if(properties.Length!=3||properties.Select(p=>p.Name).Distinct().Count()!=3||properties.Any(p=>p.Name is not("version" or "rules" or "order"))||root.GetProperty("rules").ValueKind!=System.Text.Json.JsonValueKind.String)throw new ArgumentException("Windows v3规则结构无效。");
                var value=root.GetProperty("order");if(value.ValueKind!=System.Text.Json.JsonValueKind.Object||value.EnumerateObject().Select(p=>p.Name).Distinct().Count()!=value.EnumerateObject().Count())throw new ArgumentException("v3排序重复或类型无效。");
                var options=new System.Text.Json.JsonSerializerOptions{PropertyNamingPolicy=System.Text.Json.JsonNamingPolicy.CamelCase,UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow,RespectNullableAnnotations=true};var settings=System.Text.Json.JsonSerializer.Deserialize<RenameOrderSettings>(value,options)??throw new ArgumentException("v3排序缺失。");settings.Validate();var rules3=root.GetProperty("rules").GetString()!;RenamePlan.ValidateRules(rules3);return new(rules3,settings.Sort=="name",settings);
            }
            string[] keys = ["version", "rules", "sortByName", "sort", "descending", "metadataSortTag"];
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object || root.EnumerateObject().Count() is < 3 or > 6 || root.EnumerateObject().Any(p => !keys.Contains(p.Name)) || root.EnumerateObject().Select(p => p.Name).Distinct().Count() != root.EnumerateObject().Count()) throw new ArgumentException("Windows规则文件结构无效。");
            if (!root.GetProperty("version").TryGetInt32(out var version) || version is not (1 or 2) || root.GetProperty("rules").ValueKind != System.Text.Json.JsonValueKind.String || root.GetProperty("sortByName").ValueKind is not (System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False)) throw new ArgumentException("规则版本或值类型无效。");
            var byName=root.GetProperty("sortByName").GetBoolean(); var sort=root.TryGetProperty("sort",out var sv)?sv.GetString():byName?"name":"input"; bool descending=false;if(root.TryGetProperty("descending",out var dv)){if(dv.ValueKind is not(System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False))throw new ArgumentException("排序方向类型无效。");descending=dv.GetBoolean();} var tag=root.TryGetProperty("metadataSortTag",out var tv)?tv.GetString():null;var order=new RenameOrderSettings(sort!,descending,tag);order.Validate();var preset = new RenameRulesPreset(root.GetProperty("rules").GetString()!,byName,order);
            if(version==1&&RenamePlan.UsesNewRules(RenamePlan.ParseRules(preset.Rules)))throw new ArgumentException("新Windows规则须使用版本2；Mac方案格式不直接支持。");
            if(RenamePlan.RequiresV3(RenamePlan.ParseRules(preset.Rules)))throw new ArgumentException("高级序列/计数/每目录规则须Windows版本3。");
            _ = Encode(preset.Rules, preset.SortByName);
            return preset;
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException) { throw new ArgumentException("规则JSON无效。"); }
    }
}
