using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public sealed record MetadataOperation(string Tag, string Action, string Value = "")
{
    public override string ToString() => $"{Tag} · {Action} → {(Action == "remove" ? "（清除）" : Value.Replace("\n", " / "))}";
}

public sealed record MetadataPreset(string Name, IReadOnlyList<MetadataOperation> Operations)
{
    public const int MaximumBytes = 128 * 1024;
    public const int MaximumOperations = 27;
    public static bool IsList(string tag) => tag is "XMP-dc:Creator" or "XMP-dc:Subject";
    public static bool IsText(string tag) => MetadataCsv.Tags.Contains(tag) && !IsList(tag) && PhotoDocument.NumericRange(tag) is null && !VerifiedMetadataDates.IsDate(tag) && tag is not ("XMP-xmp:Rating" or "XMP-iptcCore:CountryCode" or "XMP-exif:DateTimeOriginal" or "XMP-exif:DateTimeDigitized" or "XMP-xmp:CreateDate" or "XMP-xmp:ModifyDate");
    public static MetadataPreset Create(string name, IReadOnlyDictionary<string,string> changes) => Create(name, changes.Select(p => new MetadataOperation(p.Key, p.Value.Length == 0 ? "remove" : p.Key == "XMP-dc:Creator" ? "replaceAuthors" : p.Key == "XMP-dc:Subject" ? "replaceKeywords" : "setText", p.Value)).ToArray());
    public static MetadataPreset Create(string name, IReadOnlyList<MetadataOperation> operations)
    {
        name = name.Trim();
        if (name.Length is < 1 or > 80 || name.Any(char.IsControl) || operations.Count is < 1 or > MaximumOperations) throw new ArgumentException("预设名称须为1至80字，操作条目须为1至27条（重复目标也计数）。");
        _ = new UTF8Encoding(false,true).GetByteCount(name);
        var normalized = operations.Select(Validate).ToArray();
        return new(name, Array.AsReadOnly(normalized));
    }
    public static MetadataOperation Validate(MetadataOperation op)
    {
        if (!MetadataCsv.Tags.Contains(op.Tag)) throw new ArgumentException("预设含未支持字段。");
        if (op.Action == "remove") { if (op.Value.Length != 0) throw new ArgumentException("清除不接受参数。"); return op; }
        if (op.Action == "copy") {
            if (!MetadataCsv.Tags.Contains(op.Value) || op.Tag == op.Value || op.Tag.StartsWith("XMP-",StringComparison.Ordinal)!=op.Value.StartsWith("XMP-",StringComparison.Ordinal) || IsList(op.Tag) != IsList(op.Value)) throw new ArgumentException("复制源和目标须为不同的已开放同类字段（文字／列表）；接收值仍须通过目标校验。");
            return op;
        }
        bool list = op.Action is "replaceAuthors" or "fillMissingAuthors" or "replaceKeywords" or "appendKeywords" or "removeKeywords";
        bool allowed = op.Action switch {
            "setText" or "fillMissingText" => !IsList(op.Tag),
            "appendText" => IsText(op.Tag),
            "replaceAuthors" or "fillMissingAuthors" => op.Tag == "XMP-dc:Creator",
            "replaceKeywords" or "appendKeywords" or "removeKeywords" => op.Tag == "XMP-dc:Subject",
            _ => false
        };
        if (!allowed) throw new ArgumentException("此预设动作／字段组合未支持（日期算法不在本批子集）；未载入任何操作。");
        if (op.Value.Length == 0 && op.Action != "replaceKeywords") throw new ArgumentException("设置／补空／追加参数不能为空；清除请使用明确清除动作。");
        if (list && op.Value.Length > 0) {
            var words = MetadataFields.List(op.Value);
            if (words.Length > 256 || words.Any(w => w.Length == 0 || w.Contains('\0'))) throw new ArgumentException("列表最多256项，每项不能为空或含控制字符。");
            op = op with { Value = MetadataFields.FormatList(op.Tag == "XMP-dc:Subject"?words.Distinct(StringComparer.Ordinal):words) };
        }
        PhotoDocument.ValidateChanges(new Dictionary<string,string>{{op.Tag, op.Value}});
        return op;
    }
    public string Encode()
    {
        var preset = Create(Name, Operations);
        var operations = preset.Operations.Select(op => new { tag = PhotoDocument.WriteTag(op.Tag), action = new Dictionary<string,object> { [op.Action] = op.Action == "remove" ? new Dictionary<string,object>() : new Dictionary<string,object>{{"_0", IsList(op.Tag) && op.Action != "copy" ? op.Value.Length == 0 ? Array.Empty<string>() : MetadataFields.List(op.Value) : op.Action == "copy" ? PhotoDocument.WriteTag(op.Value) : op.Value}} } });
        var text = JsonSerializer.Serialize(new { version = 1, name = preset.Name, operations }, new JsonSerializerOptions { WriteIndented = true });
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("预设超过128KiB上限。");
        return text;
    }
    private static void Members(JsonElement node, params string[] expected)
    {
        if (node.ValueKind != JsonValueKind.Object || node.EnumerateObject().Count() != expected.Length || node.EnumerateObject().Any(p => !expected.Contains(p.Name)) || node.EnumerateObject().Select(p => p.Name).Distinct().Count() != expected.Length) throw new ArgumentException("预设结构或重复属性无效。");
    }
    public static MetadataPreset Decode(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("预设超过128KiB上限。");
        try {
            using var json = JsonDocument.Parse(text.TrimStart('\ufeff')); var root = json.RootElement;
            Members(root,"version","name","operations");
            if (!root.GetProperty("version").TryGetInt32(out var version) || version != 1 || root.GetProperty("name").ValueKind != JsonValueKind.String) throw new ArgumentException("预设版本或名称无效。");
            var array = root.GetProperty("operations");
            if (array.ValueKind != JsonValueKind.Array || array.GetArrayLength() is < 1 or > MaximumOperations) throw new ArgumentException("预设须包含1至27条操作。");
            var operations = new List<MetadataOperation>();
            foreach (var item in array.EnumerateArray()) {
                Members(item,"tag","action");
                if (item.GetProperty("tag").ValueKind != JsonValueKind.String) throw new ArgumentException("预设字段无效。");
                var tag = PhotoDocument.BaseTag(item.GetProperty("tag").GetString()!); var action = item.GetProperty("action");
                if (action.ValueKind != JsonValueKind.Object || action.EnumerateObject().Count() != 1) throw new ArgumentException("预设动作无效。");
                var entry = action.EnumerateObject().Single(); string value = "";
                if (entry.Name is not ("remove" or "copy" or "setText" or "fillMissingText" or "appendText" or "replaceAuthors" or "fillMissingAuthors" or "replaceKeywords" or "appendKeywords" or "removeKeywords")) throw new ArgumentException("此预设动作未支持；日期算法不在本批子集，未载入任何操作。");
                if (entry.Name == "remove") Members(entry.Value);
                else {
                    Members(entry.Value,"_0"); var argument = entry.Value.GetProperty("_0");
                    if (entry.Name is "replaceAuthors" or "fillMissingAuthors" or "replaceKeywords" or "appendKeywords" or "removeKeywords") {
                        if (argument.ValueKind != JsonValueKind.Array || argument.GetArrayLength() > 256 || argument.EnumerateArray().Any(w => w.ValueKind != JsonValueKind.String || w.GetString()!.Length == 0 || w.GetString()!.Contains('\0'))) throw new ArgumentException("预设列表结构无效。");
                        value = MetadataFields.FormatList(argument.EnumerateArray().Select(w => w.GetString()!));
                    } else {
                        if (argument.ValueKind != JsonValueKind.String) throw new ArgumentException("预设参数须为文字。");
                        value = argument.GetString()!;
                        if (entry.Name == "copy") value = PhotoDocument.BaseTag(value);
                    }
                }
                operations.Add(new(tag,entry.Name,value));
            }
            return Create(root.GetProperty("name").GetString()!,operations);
        } catch (Exception error) when (error is JsonException or InvalidOperationException) { throw new ArgumentException("预设JSON结构无效。"); }
    }
    internal IEnumerable<KeyValuePair<string,string>> DateParameters=>Operations.Where(op=>VerifiedMetadataDates.IsDate(op.Tag)&&op.Action is "setText" or "fillMissingText").Select(op=>new KeyValuePair<string,string>(op.Tag,op.Value));
    public async Task<int> ApplyAsync(PhotoDocument photo,CancellationToken cancellation=default) {
        var preset=Create(Name,Operations);var revision=photo.DraftRevision;var copy=photo.BatchSnapshot();var skipped=preset.Apply(copy,cancellation);
        var proof=await VerifiedMetadataDates.CreateAsync(preset.DateParameters.Concat(copy.DateCandidates),cancellation);copy.AcceptDateInputs(proof);
        await photo.EnsureUnchangedAsync(cancellation);if(revision!=photo.DraftRevision)throw new InvalidOperationException("预设验证期间草稿已改变。");
        var next=new Dictionary<string,string>(copy.Draft);
        photo.ReplaceDraft(next);photo.UsePreparedDates(copy);photo.NotifyDraftChanged();return skipped;
    }
    // The caller supplies detached batch snapshots; no live document is touched before the terminal check.
    public int Apply(PhotoDocument photo, CancellationToken cancellation = default)
    {
        if(!photo.IsBatchSnapshot&&Operations.Any(op=>VerifiedMetadataDates.IsDate(op.Tag)&&op.Action!="remove"))throw new InvalidOperationException("日期预设须异步共享验证。");
        var preset = Create(Name,Operations);CheckReadSource(photo); var values = new Dictionary<string,string?>(); var changes = new Dictionary<string,string>(); int skipped = 0;
        string? Current(string tag) {
            if (values.TryGetValue(tag,out var value)) return value;
            value = ReadCurrent(photo,tag); values[tag] = value; return value;
        }
        foreach (var op in preset.Operations) {
            cancellation.ThrowIfCancellationRequested(); string? value;
            if (op.Action == "copy") { _ = Current(op.Tag); value = Current(op.Value); if (value is null) { skipped++; continue; } }
            else {
                var current = op.Action=="remove"?null:Current(op.Tag);
                if (op.Action is "fillMissingText" or "fillMissingAuthors" && current is not null) continue;
                value = op.Action switch {
                    "remove" => null,
                    "appendText" => (current ?? "") + op.Value,
                    "appendKeywords" => MetadataFields.FormatList(Words(current).Concat(Words(op.Value)).Distinct(StringComparer.Ordinal)),
                    "removeKeywords" => MetadataFields.FormatList(Words(current).Where(w => !Words(op.Value).Contains(w,StringComparer.Ordinal))),
                    _ => op.Value
                };
            }
            if (IsList(op.Tag) && value == "") value = null;
            var checkedOp = string.IsNullOrEmpty(value) ? new MetadataOperation(op.Tag,"remove") : new MetadataOperation(op.Tag, IsList(op.Tag) ? op.Tag == "XMP-dc:Creator" ? "replaceAuthors" : "replaceKeywords" : "setText",value);
            value = Validate(checkedOp).Value;
            if(value.Length>0 && PhotoDocument.NumericRange(op.Tag) is not null)value=PhotoDocument.CheckedNumber(op.Tag,value).ToString(System.Globalization.CultureInfo.InvariantCulture);
            if(photo.IsBatchSnapshot&&VerifiedMetadataDates.IsDate(op.Tag)&&value.Length>0)photo.DateCandidates.Add(new(op.Tag,value));
            changes[op.Tag] = value; values[op.Tag] = value.Length == 0 ? null : value;
        }
        photo.StageDraft(changes); return skipped;
    }
    static string[] Words(string? value) => string.IsNullOrEmpty(value) ? [] : MetadataFields.List(value);
    static void CheckReadSource(PhotoDocument photo) {
        foreach (var source in new[] { photo.Embedded, photo.Sidecar ?? photo.Embedded })
            if (source.ValueKind != JsonValueKind.Object || source.TryGetProperty("ExifTool:Error",out _) || source.TryGetProperty("Error",out _)) throw new ArgumentException("来源读取失败，不能视为缺失。");
    }
    static string? ReadCurrent(PhotoDocument photo,string tag)
    {
        CheckReadSource(photo);
        if (photo.Draft.TryGetValue(tag,out var pending)) return pending.Length == 0 ? null : pending;
        if(MetadataFields.DateGroups.ContainsKey(tag)){var date=photo.Value(tag);return date.Length==0?null:date;}
        var metadata = photo.Sidecar ?? photo.Embedded;
        if (!metadata.TryGetProperty(tag,out var item)) return null;
        if (IsList(tag)) {
            if (item.ValueKind != JsonValueKind.String && (item.ValueKind != JsonValueKind.Array || item.EnumerateArray().Any(w => w.ValueKind != JsonValueKind.String || w.GetString()!.Length == 0 || w.GetString()!.Contains('\0')))) throw new ArgumentException("来源列表类型无效，不能视为缺失。");
        } else if (item.ValueKind != JsonValueKind.String && !(item.ValueKind == JsonValueKind.Number && (PhotoDocument.NumericRange(tag) is not null || tag == "XMP-xmp:Rating"))) throw new ArgumentException("来源标量类型无效，不能视为缺失。");
        var text = MetadataFields.Read(metadata,tag); PhotoDocument.ValidateChanges(new Dictionary<string,string>{{tag,text}}); return text;
    }
}
