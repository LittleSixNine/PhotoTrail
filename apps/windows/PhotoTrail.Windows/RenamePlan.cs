using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text;

namespace PhotoTrail.Windows;

public record RenameRule(string Kind, string Text = "", string Replacement = "", int Start = 1, int Step = 1, int Padding = 3);
public record RenameFile(string Source, string Target, string Hash)
{
    public string OriginalName => Path.GetFileName(Source);
    public string NewName => Path.GetFileName(Target);
    public string Status => Source == Target ? "无需更名" : "预览；尚未执行";
}
public sealed record RenamePlan(ReadOnlyCollection<RenameFile> Files,bool ExplicitGroups=false)
{
    public static IReadOnlyList<RenameRule> ParseRules(string text)
    {
        if (text.Length > 32768 || text.Any(c => char.IsControl(c) && c is not ('\r' or '\n'))) throw new ArgumentException("规则文字超过上限或含控制字符。");
        var result = new List<RenameRule>();
        foreach (var line in text.Split('\n').Where(value => value.Trim().Length > 0))
        {
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
        return result;
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
        if(rules.Any(r=>r.Kind is "date-set" or "date-prefix"))throw new InvalidOperationException("日期命名规则须异步共享验证。");
        return ApplyVerified(name,rules,index,metadata,null);
    }
    public static async Task<string> ApplyAsync(string name,IReadOnlyList<RenameRule> rules,int index,Func<string,string?>? metadata=null,CancellationToken token=default) {
        var frozenRules=rules.ToArray();string? captured=frozenRules.Any(r=>r.Kind is "date-set" or "date-prefix")?Required(metadata,"captured"):null;
        var dates=await VerifiedPhotoDate.InspectAsync(captured is null?Array.Empty<string>():new[]{VerifiedPhotoDate.Bridge(captured)},token);
        return ApplyVerified(name,frozenRules,index,metadata,captured is null?null:dates.GetValueOrDefault(VerifiedPhotoDate.Bridge(captured)));
    }
    internal static string ApplyVerified(string name,IReadOnlyList<RenameRule> rules,int index,Func<string,string?>? metadata,VerifiedPhotoDate? date)
    {
        if (rules.Count > 64 || index < 0) throw new ArgumentException("规则数量或序号无效。");
        var extension = Path.GetExtension(name); var stem = Path.GetFileNameWithoutExtension(name);
        foreach (var rule in rules)
        {
            if (rule.Text.Length > 256 || rule.Replacement.Length > 256) throw new ArgumentException("规则文字过长。");
            stem = rule.Kind switch
            {
                "date-set" => CaptureName(metadata,date),
                "date-prefix" => CaptureName(metadata,date)+rule.Text+stem,
                "city-prefix" => Required(metadata,"city")+rule.Text+stem,
                "model-suffix" => stem+rule.Text+Required(metadata,"model"),
                "sequence-prefix" when rule.Start>=0 && rule.Step>0 && rule.Padding is >=1 and <=9 => checked((long)rule.Start+(long)index*rule.Step).ToString("D"+rule.Padding,CultureInfo.InvariantCulture)+rule.Text+stem,
                "prefix" => rule.Text + stem,
                "suffix" => stem + rule.Text,
                "set" => rule.Text,
                "replace" when rule.Text.Length > 0 => stem.Replace(rule.Text, rule.Replacement, StringComparison.Ordinal),
                "upper" => stem.ToUpperInvariant(),
                "lower" => stem.ToLowerInvariant(),
                "sequence" when rule.Start >= 0 && rule.Step > 0 && rule.Padding is >= 1 and <= 9 => stem + checked((long)rule.Start + (long)index * rule.Step).ToString("D" + rule.Padding, CultureInfo.InvariantCulture),
                _ => throw new ArgumentException("规则无效或尚未支持。")
            };
            if (stem.Length > 255) throw new ArgumentException("生成文件名过长。");
        }
        var target = stem + extension;
        if (!ValidName(target)) throw new ArgumentException("生成名称违反Windows文件名规则。");
        return target;
    }
    internal static bool UsesMetadata(IReadOnlyList<RenameRule> rules)=>rules.Any(r=>r.Kind is "date-set" or "date-prefix" or "city-prefix" or "model-suffix");
    internal static bool UsesNewRules(IReadOnlyList<RenameRule> rules)=>UsesMetadata(rules)||rules.Any(r=>r.Kind=="sequence-prefix");
    internal static void ValidateRules(string text) {
        _=new UTF8Encoding(false,true).GetByteCount(text);var rules=ParseRules(text);
        if(!UsesNewRules(rules)){_=Apply("sample.jpg",rules,0);return;}
        foreach(var rule in rules) {
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
    public static Task<RenamePlan> BuildAsync(IEnumerable<string> paths, IReadOnlyList<RenameRule> rules, bool sortByName, CancellationToken cancellation = default)
    {
        var inputs = paths.ToArray(); var frozenRules = rules.ToArray();
        if (inputs.Length is < 1 or > 3000) throw new ArgumentException("一次预览须为1至3000个主文件。");
        if (sortByName) inputs = inputs.OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase).ThenBy(x => x, StringComparer.Ordinal).ToArray();
        var targets = inputs.Select((path, index) => (path, Apply(Path.GetFileName(path), frozenRules, index))).ToArray();
        return BuildTargetsAsync(targets, cancellation);
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
            files.Add(new(source, target, await PhotoDocument.HashAsync(source, cancellation)));
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
            string[] keys = ["version", "rules", "sortByName", "sort", "descending", "metadataSortTag"];
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object || root.EnumerateObject().Count() is < 3 or > 6 || root.EnumerateObject().Any(p => !keys.Contains(p.Name)) || root.EnumerateObject().Select(p => p.Name).Distinct().Count() != root.EnumerateObject().Count()) throw new ArgumentException("Windows规则文件结构无效。");
            if (!root.GetProperty("version").TryGetInt32(out var version) || version is not (1 or 2) || root.GetProperty("rules").ValueKind != System.Text.Json.JsonValueKind.String || root.GetProperty("sortByName").ValueKind is not (System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False)) throw new ArgumentException("规则版本或值类型无效。");
            var byName=root.GetProperty("sortByName").GetBoolean(); var sort=root.TryGetProperty("sort",out var sv)?sv.GetString():byName?"name":"input"; bool descending=false;if(root.TryGetProperty("descending",out var dv)){if(dv.ValueKind is not(System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False))throw new ArgumentException("排序方向类型无效。");descending=dv.GetBoolean();} var tag=root.TryGetProperty("metadataSortTag",out var tv)?tv.GetString():null;var order=new RenameOrderSettings(sort!,descending,tag);order.Validate();var preset = new RenameRulesPreset(root.GetProperty("rules").GetString()!,byName,order);
            if(version==1&&RenamePlan.UsesNewRules(RenamePlan.ParseRules(preset.Rules)))throw new ArgumentException("新Windows规则须使用版本2；Mac方案格式不直接支持。");
            _ = Encode(preset.Rules, preset.SortByName);
            return preset;
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException) { throw new ArgumentException("规则JSON无效。"); }
    }
}
