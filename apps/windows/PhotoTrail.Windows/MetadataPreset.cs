using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public sealed record MetadataPreset(string Name, IReadOnlyDictionary<string, string> Changes)
{
    public const int MaximumBytes = 128 * 1024;
    public static MetadataPreset Create(string name, IReadOnlyDictionary<string, string> changes)
    {
        name = name.Trim();
        if (name.Length is < 1 or > 80 || name.Any(char.IsControl) || (changes.Count < 1 || changes.Count > MetadataCsv.Tags.Length) || changes.Keys.Any(tag => !MetadataCsv.Tags.Contains(tag))) throw new ArgumentException($"预设名称须为1至80字，且包含1至{MetadataCsv.Tags.Length}个支持字段。");
        PhotoDocument.ValidateChanges(changes);
        var normalized = new Dictionary<string,string>(changes);
        foreach (var tag in new[] { "XMP-dc:Creator", "XMP-dc:Subject" })
            if (normalized.TryGetValue(tag, out var value) && value.Length > 0)
            {
                var words = value.Split('\n');
                if (words.Any(word => word.Length == 0 || word.Contains('\r'))) throw new ArgumentException("列表每项不能为空或含额外换行。");
                if (tag == "XMP-dc:Subject") normalized[tag] = string.Join("\n", words.Distinct(StringComparer.Ordinal));
            }
        return new(name, new System.Collections.ObjectModel.ReadOnlyDictionary<string,string>(normalized));
    }
    public string Encode()
    {
        var preset = Create(Name, Changes);
        var operations = preset.Changes.Select(field =>
        {
            var list = field.Key is "XMP-dc:Creator" or "XMP-dc:Subject";
            var kind = field.Value.Length == 0 ? "remove" : field.Key == "XMP-dc:Creator" ? "replaceAuthors" : field.Key == "XMP-dc:Subject" ? "replaceKeywords" : "setText";
            object payload = field.Value.Length == 0 ? new Dictionary<string,object>() : new Dictionary<string,object> { ["_0"] = list ? field.Value.Split('\n').Select(item => item.TrimEnd('\r')).ToArray() : field.Value };
            return new { tag = PhotoDocument.WriteTag(field.Key), action = new Dictionary<string,object> { [kind] = payload } };
        });
        var text = JsonSerializer.Serialize(new { version = 1, name = preset.Name, operations }, new JsonSerializerOptions { WriteIndented = true });
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("预设超过128KiB上限。");
        return text;
    }
    private static void Members(JsonElement node, params string[] expected)
    {
        if (node.ValueKind != JsonValueKind.Object || node.EnumerateObject().Count() != expected.Length || node.EnumerateObject().Any(field => !expected.Contains(field.Name)) || node.EnumerateObject().Select(field => field.Name).Distinct().Count() != expected.Length) throw new ArgumentException("预设结构或重复属性无效。");
    }
    public static MetadataPreset Decode(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("预设超过128KiB上限。");
        try
        {
            using var json = JsonDocument.Parse(text.TrimStart('\ufeff')); var root = json.RootElement;
            Members(root, "version", "name", "operations");
            if (!root.GetProperty("version").TryGetInt32(out var version) || version != 1 || root.GetProperty("name").ValueKind != JsonValueKind.String) throw new ArgumentException("预设版本或名称无效。");
            var operations = root.GetProperty("operations");
            if (operations.ValueKind != JsonValueKind.Array || (operations.GetArrayLength() < 1 || operations.GetArrayLength() > MetadataCsv.Tags.Length)) throw new ArgumentException($"预设需包含1至{MetadataCsv.Tags.Length}个操作。");
            var changes = new Dictionary<string,string>();
            foreach (var operation in operations.EnumerateArray())
            {
                Members(operation, "tag", "action");
                if (operation.GetProperty("tag").ValueKind != JsonValueKind.String) throw new ArgumentException("预设字段无效。");
                var tag = PhotoDocument.BaseTag(operation.GetProperty("tag").GetString()!); var action = operation.GetProperty("action");
                if (!MetadataCsv.Tags.Contains(tag) || changes.ContainsKey(tag) || action.ValueKind != JsonValueKind.Object || action.EnumerateObject().Count() != 1) throw new ArgumentException("预设含重复或未支持字段/操作。");
                var item = action.EnumerateObject().Single(); string value;
                if (item.Name == "remove") { Members(item.Value); value = ""; }
                else
                {
                    Members(item.Value, "_0"); var argument = item.Value.GetProperty("_0");
                    if (item.Name == "setText" && tag is not ("XMP-dc:Creator" or "XMP-dc:Subject") && argument.ValueKind == JsonValueKind.String) value = argument.GetString()!;
                    else if ((item.Name == "replaceAuthors" && tag == "XMP-dc:Creator" || item.Name == "replaceKeywords" && tag == "XMP-dc:Subject") && argument.ValueKind == JsonValueKind.Array && argument.GetArrayLength() is >= 1 and <= 256)
                    {
                        if (argument.EnumerateArray().Any(word => word.ValueKind != JsonValueKind.String)) throw new ArgumentException("预设列表必须为字符串。");
                        var words = argument.EnumerateArray().Select(word => word.GetString()!).ToArray();
                        if (words.Any(word => word.Length == 0 || word.Contains('\r') || word.Contains('\n'))) throw new ArgumentException("预设列表每项不能为空或含换行。");
                        value = string.Join("\n", words);
                    }
                    else throw new ArgumentException("此预设操作当前未支持；未载入任何字段。");
                }
                changes.Add(tag, value);
            }
            return Create(root.GetProperty("name").GetString()!, changes);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException) { throw new ArgumentException("预设JSON结构无效。"); }
    }
}
