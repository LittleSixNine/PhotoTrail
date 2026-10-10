using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public sealed record PhotoReadResult(string FilePath, PhotoDocument? Document, string? Error);

public sealed class PhotoDocument
{
    public static readonly IReadOnlyList<string> EditableTags = Array.AsReadOnly(new[] { "XMP-dc:Creator", "XMP-dc:Title", "XMP-dc:Description", "XMP-dc:Subject", "XMP-exif:DateTimeOriginal", "XMP-exif:GPSLatitude", "XMP-exif:GPSLongitude", "XMP-exif:GPSAltitude", "XMP-exif:GPSAltitudeRef", "XMP-exif:GPSMapDatum", "XMP-exif:GPSProcessingMethod", "XMP-exif:GPSDateTime", "XMP-photoshop:Country", "XMP-photoshop:State", "XMP-photoshop:City", "XMP-iptcCore:Location", "XMP-iptcCore:CountryCode", "XMP-dc:Rights", "XMP-xmp:Rating", "XMP-xmp:Label", "XMP-tiff:Make", "XMP-tiff:Model", "XMP-aux:Lens", "XMP-aux:LensSerialNumber", "XMP-exif:DateTimeDigitized", "XMP-xmp:CreateDate", "XMP-xmp:ModifyDate", "XMP-exif:ExposureTime", "XMP-exif:FNumber", "XMP-exif:ISO", "XMP-exif:FocalLength", "XMP-exif:ExposureCompensation", "XMP-exif:ExposureProgram", "XMP-exif:WhiteBalance" });
    public string FilePath { get; }
    public string? SidecarPath { get; }
    public JsonElement Embedded { get; }
    public JsonElement? Sidecar { get; }
    public string SourceHash { get; }
    public string? SidecarHash { get; }
    private readonly Dictionary<string, string> draft = [];
    public IReadOnlyDictionary<string, string> Draft => draft;
    internal long DraftRevision { get; private set; }
    internal event Action? DraftChanged;
    private void ChangedDraft() { DraftRevision++; DraftChanged?.Invoke(); }
    public void ClearDraft() { draft.Clear(); ChangedDraft(); }
    public string FileType => Embedded.TryGetProperty("File:FileType", out var type) ? type.ToString() : "";
    public bool CanEdit => FileType is "JPEG" or "XMP" || (SidecarPath is not null &&
        FileType is "DNG" or "TIFF" or "HEIC" or "PNG" or "ARW" or "NEF" or "RAF" or "CR2" or "CR3" or "RW2" or "ORF" or "PEF");

    private PhotoDocument(string file, string? sidecar, JsonElement embedded, JsonElement? metadata, string hash, string? sidecarHash)
    { FilePath = file; SidecarPath = sidecar; Embedded = embedded; Sidecar = metadata; SourceHash = hash; SidecarHash = sidecarHash; }

    public static async Task<PhotoDocument> LoadAsync(ExifToolClient client, string file, CancellationToken cancellation = default)
    {
        file = Path.GetFullPath(file);
        var candidate = Path.ChangeExtension(file, ".xmp");
        var sidecar = !file.Equals(candidate, StringComparison.OrdinalIgnoreCase) && File.Exists(candidate) ? candidate : null;
        var hash = await HashAsync(file, cancellation);
        var sidecarHash = sidecar is null ? null : await HashAsync(sidecar, cancellation);
        var metadata = await client.ReadAsync(file, cancellation);
        JsonElement? external = sidecar is null ? null : await client.ReadAsync(sidecar, cancellation);
        return await VerifiedAsync(file, sidecar, metadata, external, hash, sidecarHash, cancellation);
    }

    private static async Task<PhotoDocument> VerifiedAsync(string file, string? sidecar, JsonElement metadata, JsonElement? external, string hash, string? sidecarHash, CancellationToken cancellation)
    {
        if (metadata.ValueKind != JsonValueKind.Object || metadata.TryGetProperty("ExifTool:Error", out _) || metadata.TryGetProperty("Error", out _) ||
            ((!metadata.TryGetProperty("File:FileType", out var fileType) || fileType.ToString() != "XMP") &&
             (!metadata.TryGetProperty("File:MIMEType", out var mime) || !mime.ToString().StartsWith("image/", StringComparison.OrdinalIgnoreCase))))
            throw new InvalidDataException("文件内容不是图片或XMP，未导入。");
        if (metadata.TryGetProperty("ExifTool:Warning", out var warning) && warning.ToString().Contains("JPEG format error", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("JPEG结构损坏，未导入。");
        if (external is { } sidecarMetadata && (sidecarMetadata.ValueKind != JsonValueKind.Object || sidecarMetadata.TryGetProperty("ExifTool:Error", out _) || sidecarMetadata.TryGetProperty("Error", out _) || !sidecarMetadata.TryGetProperty("File:FileType", out var sidecarType) || sidecarType.ToString() != "XMP"))
            throw new InvalidDataException("旁车元数据读取失败。");
        var candidate = Path.ChangeExtension(file, ".xmp");
        var paired = !file.Equals(candidate, StringComparison.OrdinalIgnoreCase) && File.Exists(candidate);
        if (paired != (sidecar is not null) || hash != await HashAsync(file, cancellation) || (sidecar is not null && sidecarHash != await HashAsync(sidecar, cancellation)))
            throw new IOException("读取期间文件或旁车关系已改变，请重新导入。");
        return new(file, sidecar, metadata, external, hash, sidecarHash);
    }

    public static async Task<IReadOnlyList<PhotoReadResult>> LoadBatchAsync(ExifToolClient client, IReadOnlyList<string> files, CancellationToken cancellation = default)
    {
        if (files.Count is < 1 or > 32 || files.Select(Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).Count() != files.Count) throw new ArgumentException("批次需包含1至32个不同文件。");
        var prepared = new List<(string File, string? Sidecar, string Hash, string? SidecarHash)>();
        var results = new Dictionary<string,PhotoReadResult>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in files)
        {
            cancellation.ThrowIfCancellationRequested(); var file = Path.GetFullPath(path);
            try
            {
                var candidate = Path.ChangeExtension(file, ".xmp");
                var sidecar = !file.Equals(candidate, StringComparison.OrdinalIgnoreCase) && File.Exists(candidate) ? candidate : null;
                prepared.Add((file, sidecar, await HashAsync(file, cancellation), sidecar is null ? null : await HashAsync(sidecar, cancellation)));
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException) { results[file] = new(file, null, error.Message); }
        }
        IReadOnlyDictionary<string,JsonElement>? metadata = null;
        if (prepared.Count > 0)
        {
            var sources = prepared.SelectMany(item => item.Sidecar is null ? new[] { item.File } : new[] { item.File, item.Sidecar }).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            try { metadata = await client.ReadManyAsync(sources, cancellation); }
            catch (OperationCanceledException) { throw; }
            // A bad input can make ExifTool fail the whole command; isolate it without dropping valid neighbours.
            catch (Exception error) when (error is IOException or InvalidDataException or JsonException or ArgumentException or TimeoutException) { }
        }
        foreach (var item in prepared)
        {
            cancellation.ThrowIfCancellationRequested();
            try
            {
                var embedded = metadata is null ? await client.ReadAsync(item.File, cancellation) : metadata[item.File];
                JsonElement? external = item.Sidecar is null ? null : metadata is null ? await client.ReadAsync(item.Sidecar, cancellation) : metadata[item.Sidecar];
                var photo = await VerifiedAsync(item.File, item.Sidecar, embedded, external, item.Hash, item.SidecarHash, cancellation);
                results[item.File] = new(item.File, photo, null);
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception error) when (error is IOException or InvalidDataException or JsonException or ArgumentException or TimeoutException or UnauthorizedAccessException) { results[item.File] = new(item.File, null, error.Message); }
        }
        return files.Select(path => results[Path.GetFullPath(path)]).ToArray();
    }

    public string Value(string tag)
    {
        if (draft.TryGetValue(tag, out var pending)) return pending;
        var source = Sidecar ?? Embedded;
        return source.TryGetProperty(tag, out var value) ? Text(value) : "";
    }

    public void SetDraft(IReadOnlyDictionary<string, string> changes)
    {
        if (!CanEdit) throw new InvalidOperationException("此格式目前仅支持读取；已有XMP旁车时可编辑旁车。");
        ValidateChanges(changes);
        foreach (var (tag, value) in changes)
        {
            var original = (Sidecar ?? Embedded).TryGetProperty(tag, out var field) ? Text(field) : "";
            var normalized = value.Length > 0 && NumericRange(tag) is not null ? CheckedNumber(tag,value).ToString(CultureInfo.InvariantCulture) : value;
            if (normalized == original) draft.Remove(tag); else draft[tag] = normalized;
        }
        ChangedDraft();
    }

    internal static void ValidateDatePageShape(string tag,string value)
    {
        if(tag!=DatePagePreview.Field || !EditableTags.Contains(tag) || value.Length is < 19 or > 128 || value.Any(char.IsControl))
            throw new ArgumentException("日期字段或文字不在允许范围。");
        _=new UTF8Encoding(false,true).GetByteCount(value);
    }
    internal void ApplyDatePage(DatePagePreview preview)
    {
        // The capability checks this exact document, source value and draft revision; no general bypass flag.
        var value=preview.ValueFor(this);
        ValidateDatePageShape(DatePagePreview.Field,value);
        var original=(Sidecar??Embedded).TryGetProperty(DatePagePreview.Field,out var field)?Text(field):"";
        if(value==original)draft.Remove(DatePagePreview.Field);else draft[DatePagePreview.Field]=value;
        ChangedDraft();
    }

    public static Dictionary<string, string> PositionChanges(MapPoint point, double? altitude, string method)
    {
        if (!double.IsFinite(point.Latitude) || !double.IsFinite(point.Longitude) || point.Latitude is < -90 or > 90 || point.Longitude is < -180 or > 180) throw new ArgumentException("GPS坐标超出WGS-84范围。");
        var changes = new Dictionary<string, string>
        {
            ["XMP-exif:GPSLatitude"] = point.Latitude.ToString("0.########", CultureInfo.InvariantCulture),
            ["XMP-exif:GPSLongitude"] = point.Longitude.ToString("0.########", CultureInfo.InvariantCulture),
            ["XMP-exif:GPSMapDatum"] = "WGS-84", ["XMP-exif:GPSProcessingMethod"] = method,
            ["XMP-exif:GPSAltitude"] = altitude is { } height ? Math.Abs(height).ToString("0.########", CultureInfo.InvariantCulture) : "",
            ["XMP-exif:GPSAltitudeRef"] = altitude is { } value ? (value < 0 ? "1" : "0") : "",
            // Photo time does not imply GPS measurement time; never retain an old XMP measurement time for a new position.
            ["XMP-exif:GPSDateTime"] = ""
        };
        if (!double.IsFinite(point.Latitude) || !double.IsFinite(point.Longitude) || (altitude is { } elevation && !double.IsFinite(elevation))) throw new ArgumentException("定位数字必须有限。");
        ValidateChanges(changes);
        return changes;
    }

    public MapPoint? Position()
    {
        var latitude = Value("XMP-exif:GPSLatitude"); var longitude = Value("XMP-exif:GPSLongitude");
        string datum;
        if (latitude.Length > 0 || longitude.Length > 0 || draft.ContainsKey("XMP-exif:GPSLatitude") || draft.ContainsKey("XMP-exif:GPSLongitude")) datum = Value("XMP-exif:GPSMapDatum");
        else
        {
            string EmbeddedValue(string tag) => Embedded.TryGetProperty(tag, out var value) ? Text(value) : "";
            latitude = EmbeddedValue("GPS:GPSLatitude"); longitude = EmbeddedValue("GPS:GPSLongitude");
            if (EmbeddedValue("GPS:GPSLatitudeRef") == "S") latitude = "-" + latitude.TrimStart('-');
            if (EmbeddedValue("GPS:GPSLongitudeRef") == "W") longitude = "-" + longitude.TrimStart('-');
            datum = EmbeddedValue("GPS:GPSMapDatum");
        }
        if (datum.Length > 0 && datum.Replace("-", "").Replace(" ", "").ToUpperInvariant() != "WGS84") return null;
        return double.TryParse(latitude, NumberStyles.Float, CultureInfo.InvariantCulture, out var lat) &&
            double.TryParse(longitude, NumberStyles.Float, CultureInfo.InvariantCulture, out var lon) && double.IsFinite(lat) && double.IsFinite(lon) && lat is >= -90 and <= 90 && lon is >= -180 and <= 180 ? new(lon, lat) : null;
    }

    public static string WriteTag(string tag) => tag is "XMP-dc:Title" or "XMP-dc:Description" or "XMP-dc:Rights" ? tag+"-x-default" : tag;
    public static string BaseTag(string tag) => tag is "XMP-dc:Title-x-default" or "XMP-dc:Description-x-default" or "XMP-dc:Rights-x-default" ? tag[..^10] : tag;

    public static (double Minimum, double Maximum, bool Integer)? NumericRange(string tag) => tag switch
    {
        "XMP-exif:ExposureTime" => (0.000001,86400,false), "XMP-exif:FNumber" => (0.1,128,false),
        "XMP-exif:ISO" => (1,1000000,true), "XMP-exif:FocalLength" => (0.1,10000,false),
        "XMP-exif:ExposureCompensation" => (-100,100,false), "XMP-exif:ExposureProgram" => (0,8,true),
        "XMP-exif:WhiteBalance" => (0,1,true), _ => null
    };
    public static double CheckedNumber(string tag,string text)
    {
        var range = NumericRange(tag) ?? throw new ArgumentException("字段不是可编辑曝光参数。");
        var parts = text.Split('/');
        if (parts.Length is < 1 or > 2 || !double.TryParse(parts[0],NumberStyles.Float,CultureInfo.InvariantCulture,out var number) || !double.IsFinite(number))
            throw new ArgumentException("曝光参数使用有限数值或分数。");
        if (parts.Length == 2)
        {
            if (!double.TryParse(parts[1],NumberStyles.Float,CultureInfo.InvariantCulture,out var denominator) || !double.IsFinite(denominator) || denominator == 0)
                throw new ArgumentException("曝光参数分母必须是非零有限数值。");
            number /= denominator;
        }
        if (!double.IsFinite(number) || number < range.Minimum || number > range.Maximum || range.Integer && Math.Truncate(number) != number)
            throw new ArgumentException("曝光参数超出字段范围或须为整数："+tag);
        return number;
    }

    public static void ValidateChanges(IReadOnlyDictionary<string, string> changes)
    {
        foreach (var (tag, value) in changes)
        {
            if (!EditableTags.Contains(tag) || value.Length > 8192 || value.Contains('\0')) throw new ArgumentException("字段或值不在允许范围。");
            _ = new UTF8Encoding(false,true).GetByteCount(value);
            if (value.Length > 0 && NumericRange(tag) is not null) _ = CheckedNumber(tag,value);
            if (tag == "XMP-xmp:Rating" && value is not ("" or "-1" or "0" or "1" or "2" or "3" or "4" or "5")) throw new ArgumentException("评分使用0至5的整数，-1表示拒绝；留空清除。");
            if (tag == "XMP-xmp:Label" && (value.Length > 256 || value.Any(char.IsControl))) throw new ArgumentException("标签最多256字且不可含控制字符。");
            if (tag is "XMP-photoshop:Country" or "XMP-photoshop:State" or "XMP-photoshop:City" or "XMP-iptcCore:Location" or "XMP-iptcCore:CountryCode")
            {
                if (value.Length > 256 || value.Any(char.IsControl)) throw new ArgumentException("地区字段最多256字且不可含控制字符。");
                if (tag == "XMP-iptcCore:CountryCode" && value.Length > 0 && (value.Length != 3 || value.Any(c => c is < 'A' or > 'Z'))) throw new ArgumentException("国家代码使用三个大写英文字母，例如CHN。");
            }
            if (value.Length > 0 && tag is "XMP-exif:GPSLatitude" or "XMP-exif:GPSLongitude" or "XMP-exif:GPSAltitude")
            {
                if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number) ||
                    (tag.EndsWith("Latitude") && Math.Abs(number) > 90) || (tag.EndsWith("Longitude") && Math.Abs(number) > 180) ||
                    (tag.EndsWith("Altitude") && (number < 0 || number > uint.MaxValue))) throw new ArgumentException("GPS数值超出可写范围。");
            }
            if (tag == "XMP-exif:GPSAltitudeRef" && value is not ("" or "0" or "1")) throw new ArgumentException("GPS海拔方向无效。");
            if (tag == "XMP-exif:GPSMapDatum" && value is not ("" or "WGS-84")) throw new ArgumentException("当前只写入WGS-84基准。");
            if (tag == "XMP-exif:GPSProcessingMethod" && value is not ("" or "GPS" or "MANUAL")) throw new ArgumentException("定位来源无效。");
            if (tag == "XMP-exif:GPSDateTime" && value.Length > 0) throw new ArgumentException("当前仅清除旧XMP定位时间，不从照片时间猜测GPS测量时间。");
            if (tag is "XMP-dc:Creator" or "XMP-dc:Subject" && value.Split('\n').Length > 256) throw new ArgumentException("作者或关键词最多支持256项。");
            if (value.Length != 0 && tag is "XMP-exif:DateTimeOriginal" or "XMP-exif:DateTimeDigitized" or "XMP-xmp:CreateDate" or "XMP-xmp:ModifyDate") _ = MetadataDate.Parse(value);
        }
    }

    public static string Text(JsonElement value) => value.ValueKind == JsonValueKind.Array
        ? string.Join("\n", value.EnumerateArray().Select(v => v.ToString())) : value.ToString();

    public async Task EnsureUnchangedAsync(CancellationToken cancellation = default)
    {
        var candidate = Path.ChangeExtension(FilePath,".xmp");
        if (SourceHash != await HashAsync(FilePath,cancellation) ||
            (SidecarPath is not null && SidecarHash != await HashAsync(SidecarPath,cancellation)) ||
            (SidecarPath is null && !FilePath.Equals(candidate,StringComparison.OrdinalIgnoreCase) && File.Exists(candidate)))
            throw new IOException("原文件、旁车内容或旁车关系已改变，请重新导入。");
    }

    public static async Task<string> HashAsync(string path, CancellationToken cancellation = default)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, FileOptions.Asynchronous);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellation));
    }
}

public static class MetadataCopy
{
    public static async Task<string> SaveAsync(ExifToolClient client, PhotoDocument photo, string folder, CancellationToken cancellation = default)
    {
        if (!photo.CanEdit || photo.Draft.Count == 0) throw new InvalidOperationException("没有可保存的草稿。");
        // Freeze only the requested fields; UI edits while saving cannot alter this operation.
        var changes = new Dictionary<string, string>(photo.Draft);
        if (!Directory.Exists(folder)) throw new DirectoryNotFoundException("输出文件夹不存在。");
        var output = Path.Combine(Path.GetFullPath(folder), Path.GetFileName(photo.FilePath));
        var sidecarOutput = photo.SidecarPath is null ? null : Path.ChangeExtension(output, ".xmp");
        if (File.Exists(output) || (sidecarOutput is not null && File.Exists(sidecarOutput))) throw new IOException("目标文件已存在，不会覆盖。");
        await photo.EnsureUnchangedAsync(cancellation);
        var temporary = Path.Combine(folder, ".phototrail-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporary);
        var stagedImage = Path.Combine(temporary, Path.GetFileName(photo.FilePath));
        var stagedSidecar = sidecarOutput is null ? null : Path.ChangeExtension(stagedImage, ".xmp");
        var valueFiles = new List<string>();
        bool movedImage = false;
        string? verifiedImageHash = null;
        try
        {
            await CopyNewAsync(photo.FilePath, stagedImage, cancellation);
            if (stagedSidecar is not null) await CopyNewAsync(photo.SidecarPath!, stagedSidecar, cancellation);
            if (photo.SourceHash != await PhotoDocument.HashAsync(stagedImage,cancellation) ||
                (stagedSidecar is not null && photo.SidecarHash != await PhotoDocument.HashAsync(stagedSidecar,cancellation)))
                throw new IOException("暂存副本与导入基线不一致，未写入元数据。");
            var writable = stagedSidecar ?? stagedImage;
            var arguments = new List<string> { "-charset", "filename=UTF8", "-n", "-overwrite_original" };
            foreach (var (tag, value) in changes)
            {
                var writeTag = PhotoDocument.WriteTag(tag);
                var values = tag is "XMP-dc:Creator" or "XMP-dc:Subject"
                    ? value.Split('\n').Where(s => s.Length > 0).Select(s => s.TrimEnd('\r')).ToArray() : [value];
                if (values.Length == 0 || value.Length == 0) arguments.Add("-" + writeTag + "=");
                else foreach (var item in values)
                {
                    // Literal UTF-8 value files preserve newlines, quotes, $, @ and leading spaces.
                    var valueFile = Path.Combine(temporary, $"value-{valueFiles.Count}.txt");
                    valueFiles.Add(valueFile);
                    await File.WriteAllTextAsync(valueFile, item, new UTF8Encoding(false), cancellation);
                    arguments.Add("-" + writeTag + "<=" + valueFile);
                }
            }
            arguments.Add("--"); arguments.Add(writable);
            await client.RunAsync(arguments, cancellation);
            var result = await client.ReadAsync(writable, cancellation);
            foreach (var (tag, expected) in changes)
            {
                var actual = result.TryGetProperty(tag, out var value) ? PhotoDocument.Text(value) : "";
                var numericGps = tag is "XMP-exif:GPSLatitude" or "XMP-exif:GPSLongitude" or "XMP-exif:GPSAltitude";
                if (numericGps && expected.Length > 0)
                {
                    if (!double.TryParse(actual, NumberStyles.Float, CultureInfo.InvariantCulture, out var read) ||
                        !double.TryParse(expected, NumberStyles.Float, CultureInfo.InvariantCulture, out var target) || !double.IsFinite(read) || Math.Abs(read - target) > 0.00000001)
                        throw new InvalidDataException("GPS保存回读不一致：" + tag);
                }
                else if (PhotoDocument.NumericRange(tag) is not null && expected.Length > 0)
                {
                    var target = PhotoDocument.CheckedNumber(tag,expected);
                    if (!double.TryParse(actual,NumberStyles.Float,CultureInfo.InvariantCulture,out var read) || !double.IsFinite(read) || Math.Abs(read-target) > Math.Max(1e-12,Math.Abs(target)*1e-9))
                        throw new InvalidDataException("曝光参数保存回读不一致："+tag);
                }
                else if (actual != expected.Replace("\r\n", "\n")) throw new InvalidDataException("保存后字段回读不一致：" + tag);
            }
            var before = photo.Sidecar ?? photo.Embedded;
            foreach (var field in before.EnumerateObject())
            {
                if (changes.ContainsKey(field.Name) || field.Name.StartsWith("System:") || field.Name.StartsWith("File:") ||
                    field.Name.StartsWith("ExifTool:") || field.Name.StartsWith("Composite:") ||
                    // The extended-XMP packet digest necessarily changes when the packet is rebuilt.
                    field.Name is "SourceFile" or "XMP-x:XMPToolkit" or "XMP-xmpNote:HasExtendedXMP") continue;
                if (!result.TryGetProperty(field.Name, out var after) || after.GetRawText() != field.Value.GetRawText())
                    throw new InvalidDataException("非目标元数据发生变化：" + field.Name);
            }
            if (stagedSidecar is not null)
            {
                if (photo.SourceHash != await PhotoDocument.HashAsync(stagedImage, cancellation)) throw new InvalidDataException("图像副本内容改变。");
            }
            else if (photo.FileType == "JPEG")
            {
                if (await JpegPixelsAsync(photo.FilePath, cancellation) != await JpegPixelsAsync(stagedImage, cancellation))
                    throw new InvalidDataException("JPEG像素载荷发生变化。");
            }
            await photo.EnsureUnchangedAsync(cancellation);
            verifiedImageHash = await PhotoDocument.HashAsync(stagedImage, cancellation);
            cancellation.ThrowIfCancellationRequested();
            File.Move(stagedImage, output); movedImage = true;
            if (stagedSidecar is not null) File.Move(stagedSidecar, sidecarOutput!);
            return output;
        }
        catch
        {
            if (movedImage && File.Exists(output) && verifiedImageHash == await PhotoDocument.HashAsync(output)) File.Delete(output);
            throw;
        }
        finally
        {
            // Delete only files this operation created; never recursively delete an output directory.
            foreach (var file in new[] { stagedImage, stagedSidecar }) if (file is not null && File.Exists(file)) File.Delete(file);
            foreach (var file in valueFiles) if (File.Exists(file)) File.Delete(file);
            Directory.Delete(temporary, recursive: false);
        }
    }

    private static async Task CopyNewAsync(string source, string target, CancellationToken cancellation)
    {
        await using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, FileOptions.Asynchronous);
        await using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, FileOptions.Asynchronous);
        await input.CopyToAsync(output, cancellation);
    }

    public static async Task<string> JpegPixelsAsync(string file, CancellationToken cancellation = default)
    {
        var bytes = await File.ReadAllBytesAsync(file, cancellation);
        if (bytes.Length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) throw new InvalidDataException("JPEG结构无效。");
        for (var index = 2; index + 3 < bytes.Length;)
        {
            if (bytes[index] != 0xff) throw new InvalidDataException("JPEG段边界无效。");
            while (index + 1 < bytes.Length && bytes[index + 1] == 0xff) index++;
            if (index + 3 >= bytes.Length) break;
            if (bytes[index + 1] == 0xda) return Convert.ToHexString(SHA256.HashData(bytes.AsSpan(index)));
            var length = (bytes[index + 2] << 8) + bytes[index + 3];
            if (length < 2 || index + 2 + length > bytes.Length) throw new InvalidDataException("JPEG段长度无效。");
            index += length + 2;
        }
        throw new InvalidDataException("JPEG缺少像素扫描段。");
    }
}
