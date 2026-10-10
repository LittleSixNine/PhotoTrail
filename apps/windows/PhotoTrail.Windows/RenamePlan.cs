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
public sealed record RenamePlan(ReadOnlyCollection<RenameFile> Files)
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
            else if (kind is "prefix" or "suffix" or "set" && parts.Length == 2) result.Add(new(kind, parts[1]));
            else if (kind == "replace" && parts.Length == 3) result.Add(new(kind, parts[1], parts[2]));
            else if (kind is "upper" or "lower" && parts.Length == 1) result.Add(new(kind));
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
    public static string Apply(string name, IReadOnlyList<RenameRule> rules, int index)
    {
        if (rules.Count > 64 || index < 0) throw new ArgumentException("规则数量或序号无效。");
        var extension = Path.GetExtension(name); var stem = Path.GetFileNameWithoutExtension(name);
        foreach (var rule in rules)
        {
            if (rule.Text.Length > 256 || rule.Replacement.Length > 256) throw new ArgumentException("规则文字过长。");
            stem = rule.Kind switch
            {
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
    public static Task<RenamePlan> BuildAsync(IEnumerable<string> paths, IReadOnlyList<RenameRule> rules, bool sortByName, CancellationToken cancellation = default)
    {
        var inputs = paths.ToArray(); var frozenRules = rules.ToArray();
        if (inputs.Length is < 1 or > 3000) throw new ArgumentException("一次预览须为1至3000个主文件。");
        if (sortByName) inputs = inputs.OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase).ThenBy(x => x, StringComparer.Ordinal).ToArray();
        var targets = inputs.Select((path, index) => (path, Apply(Path.GetFileName(path), frozenRules, index))).ToArray();
        return BuildTargetsAsync(targets, cancellation);
    }
    public static async Task<RenamePlan> BuildTargetsAsync(IEnumerable<(string Source, string Name)> targets, CancellationToken cancellation = default)
    {
        var inputs = targets.ToArray();
        if (inputs.Length is < 1 or > 3000) throw new ArgumentException("一次预览须为1至3000个主文件。");
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
            if (!full.Equals(sidecar, StringComparison.OrdinalIgnoreCase) && File.Exists(sidecar))
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
        return new(Array.AsReadOnly(files.ToArray()));
    }
}

public sealed record RenameRulesPreset(string Rules, bool SortByName)
{
    public const int MaximumBytes = 64 * 1024;
    public static string Encode(string rules, bool sortByName)
    {
        var parsed = RenamePlan.ParseRules(rules);
        _ = RenamePlan.Apply("sample.jpg", parsed, 0);
        var text = System.Text.Json.JsonSerializer.Serialize(new { version = 1, rules, sortByName });
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("规则文件超过64KiB上限。");
        return text;
    }
    public static RenameRulesPreset Decode(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("规则文件超过64KiB上限。");
        try
        {
            using var json = System.Text.Json.JsonDocument.Parse(text.TrimStart('\ufeff')); var root = json.RootElement;
            string[] keys = ["version", "rules", "sortByName"];
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object || root.EnumerateObject().Count() != 3 || root.EnumerateObject().Any(p => !keys.Contains(p.Name)) || root.EnumerateObject().Select(p => p.Name).Distinct().Count() != 3) throw new ArgumentException("Windows规则文件结构无效。");
            if (!root.GetProperty("version").TryGetInt32(out var version) || version != 1 || root.GetProperty("rules").ValueKind != System.Text.Json.JsonValueKind.String || root.GetProperty("sortByName").ValueKind is not (System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False)) throw new ArgumentException("规则版本或值类型无效。");
            var preset = new RenameRulesPreset(root.GetProperty("rules").GetString()!, root.GetProperty("sortByName").GetBoolean());
            _ = Encode(preset.Rules, preset.SortByName);
            return preset;
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException) { throw new ArgumentException("规则JSON无效。"); }
    }
}
