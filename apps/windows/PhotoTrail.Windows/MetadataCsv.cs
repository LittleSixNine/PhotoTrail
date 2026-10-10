using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.VisualBasic.FileIO;

namespace PhotoTrail.Windows;

public sealed record CsvRecord(string Id, string RelativePath, IReadOnlyDictionary<string, string> Cells);
public sealed record CsvImport(IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> Changes, IReadOnlyList<string> Warnings);

public static class MetadataCsv
{
    public const int MaximumBytes = 8 * 1024 * 1024;
    public static readonly string[] Tags = ["XMP-dc:Creator", "XMP-dc:Title", "XMP-dc:Description", "XMP-dc:Subject", "XMP-exif:DateTimeOriginal", "XMP-photoshop:Country", "XMP-photoshop:State", "XMP-photoshop:City", "XMP-iptcCore:Location", "XMP-iptcCore:CountryCode", "XMP-dc:Rights", "XMP-xmp:Rating", "XMP-xmp:Label", "XMP-tiff:Make", "XMP-tiff:Model", "XMP-aux:Lens", "XMP-aux:LensSerialNumber", "XMP-exif:DateTimeDigitized", "XMP-xmp:CreateDate", "XMP-xmp:ModifyDate", "XMP-exif:ExposureTime", "XMP-exif:FNumber", "XMP-exif:ISO", "XMP-exif:FocalLength", "XMP-exif:ExposureCompensation", "XMP-exif:ExposureProgram", "XMP-exif:WhiteBalance"];
    private static bool IsList(string tag) => tag is "XMP-dc:Creator" or "XMP-dc:Subject";
    public static string Identity(string path) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path)))).ToLowerInvariant();
    public static bool SafePath(string path) => path.Length is > 0 and <= 32767 && !path.Contains('\\') && !path.StartsWith('/') &&
        !path.Any(c => char.IsControl(c) || "*?[]:".Contains(c)) && path.Split('/').All(part => part is not ("" or "." or ".."));

    public static CsvRecord[] Snapshot(IReadOnlyList<PhotoDocument> photos)
    {
        if (photos.Count is < 1 or > 3000) throw new ArgumentException("请选择1至3000个文件。");
        var root = Path.GetDirectoryName(photos[0].FilePath)!;
        while (photos.Any(photo => !photo.FilePath.StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)))
            root = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(root)) ?? throw new ArgumentException("CSV需选择同一磁盘中的文件。");
        return photos.Select(photo =>
        {
            var relative = Path.GetRelativePath(root, photo.FilePath).Replace('\\', '/');
            if (!SafePath(relative)) throw new ArgumentException("文件名不适用于CSV安全相对路径。");
            var cells = new Dictionary<string, string>();
            foreach (var tag in Tags)
            {
                if (photo.Draft.TryGetValue(tag, out var draft))
                    cells[tag] = IsList(tag) ? JsonSerializer.Serialize(draft.Split('\n').Where(value => value.Length > 0).ToArray()) : JsonSerializer.Serialize(draft);
                else if ((photo.Sidecar ?? photo.Embedded).TryGetProperty(tag, out var value))
                    cells[tag] = IsList(tag) ? JsonSerializer.Serialize(value.ValueKind == JsonValueKind.Array ? value.EnumerateArray().Select(item => item.ToString()).ToArray() : new[] { value.ToString() }) : JsonSerializer.Serialize(value.ToString());
            }
            return new CsvRecord(Identity(photo.FilePath), relative, cells);
        }).ToArray();
    }

    private static string FormulaSafe(string text) => text.Length > 0 && "=+-@\t\r\n".Contains(text[0]) ? "'" + text : text;
    private static string Quote(string text) => "\"" + text.Replace("\"", "\"\"") + "\"";
    public static string Export(IReadOnlyList<CsvRecord> records, bool displayOnly = false)
    {
        ValidateRecords(records);
        var result = new StringBuilder();
        void Row(IEnumerable<string> cells) => result.AppendJoin(',', cells.Select(Quote)).Append("\r\n");
        Row(new[] { displayOnly ? "PhotoTrail display CSV 1" : "PhotoTrail CSV 1", "RelativePath" }.Concat(Tags.Select(PhotoDocument.WriteTag)));
        foreach (var record in records)
        {
            if (!displayOnly && FormulaSafe(record.RelativePath) != record.RelativePath) throw new ArgumentException("此文件名需使用显示CSV或先重命名；回导路径不能改变。");
            Row(new[] { record.Id, displayOnly ? FormulaSafe(record.RelativePath) : record.RelativePath }.Concat(Tags.Select(tag =>
            {
                if (!record.Cells.TryGetValue(tag, out var cell)) return "";
                if (!displayOnly) return cell;
                using var value = JsonDocument.Parse(cell);
                return FormulaSafe(IsList(tag) ? string.Join(" / ", value.RootElement.EnumerateArray().Select(item => item.GetString())) : value.RootElement.GetString()!);
            })));
        }
        if (Encoding.UTF8.GetByteCount(result.ToString()) > MaximumBytes) throw new ArgumentException("CSV超过8MiB上限，请分批导出。");
        return result.ToString();
    }

    public static void WriteNew(string path, string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new ArgumentException("CSV超过8MiB上限。");
        path = Path.GetFullPath(path);
        var temporary = Path.Combine(Path.GetDirectoryName(path)!, ".phototrail-csv-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                using var writer = new StreamWriter(stream, new UTF8Encoding(true, true), leaveOpen: true);
                writer.Write(text); writer.Flush(); stream.Flush(true);
            }
            File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static void ValidateRecords(IReadOnlyList<CsvRecord> records)
    {
        if (records.Count is < 1 or > 3000 || records.Select(row => row.Id).Distinct().Count() != records.Count ||
            records.Select(row => row.RelativePath).Distinct(StringComparer.OrdinalIgnoreCase).Count() != records.Count ||
            records.Any(row => row.Id.Length != 64 || row.Id.Any(c => !char.IsAsciiHexDigit(c)) || !SafePath(row.RelativePath)))
            throw new ArgumentException("CSV选择身份或路径无效。");
    }

    public static CsvImport Load(string text, IReadOnlyList<CsvRecord> authorized)
    {
        ValidateRecords(authorized);
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw new InvalidDataException("CSV超过8MiB上限。");
        using var reader = new TextFieldParser(new StringReader(text.TrimStart('\ufeff'))) { TextFieldType = FieldType.Delimited, HasFieldsEnclosedInQuotes = true, TrimWhiteSpace = false };
        reader.SetDelimiters(",");
        var rows = new List<string[]>();
        try { while (!reader.EndOfData) { rows.Add(reader.ReadFields()!); if (rows.Count > 3001) throw new InvalidDataException("CSV最多3000行数据。"); } }
        catch (MalformedLineException) { throw new InvalidDataException("CSV引号或行结构无效。"); }
        if (rows.Count == 0 || rows[0].Length is < 2 or > 128 || rows[0][0] != "PhotoTrail CSV 1" || rows[0][1] != "RelativePath") throw new InvalidDataException("仅支持PhotoTrail CSV 1回导格式；显示CSV不可导入。");
        var header = rows[0]; var tags = header.Skip(2).Select(PhotoDocument.BaseTag).ToArray();
        if (header.Distinct().Count() != header.Length || tags.Distinct().Count() != tags.Length) throw new InvalidDataException("CSV含重复列。");
        var seen = new HashSet<string>(); var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows.Skip(1))
            if (row.Length != header.Length || !seen.Add(row[0]) || !paths.Add(row[1])) throw new InvalidDataException("CSV行长度或重复身份/路径无效。");
        var allowed = authorized.ToDictionary(row => row.Id); var warnings = new List<string>();
        if (tags.Any(tag => !Tags.Contains(tag))) warnings.Add("未知或当前不支持的字段已忽略。");
        var result = new Dictionary<string, IReadOnlyDictionary<string, string>>();
        for (var index = 1; index < rows.Count; index++)
        {
            var row = rows[index];
            if (!SafePath(row[1]) || !allowed.TryGetValue(row[0], out var original) || original.RelativePath != row[1]) { warnings.Add($"第{index + 1}行：身份或相对路径不在当前选择中，已跳过。"); continue; }
            var changes = new Dictionary<string, string>();
            try
            {
                for (var column = 0; column < tags.Length; column++)
                {
                    var tag = tags[column]; var cell = row[column + 2];
                    if (!Tags.Contains(tag) || cell.Length == 0) continue;
                    if (cell == "@clear") { if (original.Cells.TryGetValue(tag, out var before) && before is not ("\"\"" or "[]")) changes[tag] = ""; continue; }
                    using var json = JsonDocument.Parse(cell);
                    string canonical; string value;
                    if (IsList(tag))
                    {
                        if (json.RootElement.ValueKind != JsonValueKind.Array || json.RootElement.GetArrayLength() > 256 || json.RootElement.EnumerateArray().Any(item => item.ValueKind != JsonValueKind.String)) throw new ArgumentException();
                        var items = json.RootElement.EnumerateArray().Select(item => item.GetString()!).ToArray();
                        canonical = JsonSerializer.Serialize(items);
                        if (original.Cells.GetValueOrDefault(tag) == canonical) continue;
                        if (items.Any(item => item.Length == 0 || item.Contains('\r') || item.Contains('\n'))) throw new ArgumentException();
                        value = string.Join("\n", items);
                    }
                    else
                    {
                        if (json.RootElement.ValueKind != JsonValueKind.String) throw new ArgumentException();
                        value = json.RootElement.GetString()!; canonical = JsonSerializer.Serialize(value);
                        if (original.Cells.GetValueOrDefault(tag) == canonical) continue;
                    }
                    changes[tag] = value;
                }
                PhotoDocument.ValidateChanges(changes);
                if (changes.Count > 0) result[row[0]] = changes;
            }
            catch (Exception error) when (error is JsonException or ArgumentException) { warnings.Add($"第{index + 1}行：字段值无效，整行未加入预览。"); }
        }
        return new(result, warnings.AsReadOnly());
    }
}
