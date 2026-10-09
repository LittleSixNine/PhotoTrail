using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public sealed class PhotoDocument
{
    public static readonly IReadOnlyList<string> EditableTags = Array.AsReadOnly(new[] { "XMP-dc:Creator", "XMP-dc:Title", "XMP-dc:Description", "XMP-dc:Subject", "XMP-exif:DateTimeOriginal" });
    public string FilePath { get; }
    public string? SidecarPath { get; }
    public JsonElement Embedded { get; }
    public JsonElement? Sidecar { get; }
    public string SourceHash { get; }
    public string? SidecarHash { get; }
    private readonly Dictionary<string, string> draft = [];
    public IReadOnlyDictionary<string, string> Draft => draft;
    public void ClearDraft() => draft.Clear();
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
        if ((!metadata.TryGetProperty("File:FileType", out var fileType) || fileType.ToString() != "XMP") &&
            (!metadata.TryGetProperty("File:MIMEType", out var mime) || !mime.ToString().StartsWith("image/", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("文件内容不是图片或XMP，未导入。");
        JsonElement? external = sidecar is null ? null : await client.ReadAsync(sidecar, cancellation);
        if (hash != await HashAsync(file, cancellation) || (sidecar is not null && sidecarHash != await HashAsync(sidecar, cancellation)))
            throw new IOException("读取期间文件已改变，请重新导入。");
        return new(file, sidecar, metadata, external, hash, sidecarHash);
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
            if (value == original) draft.Remove(tag); else draft[tag] = value;
        }
    }

    public static void ValidateChanges(IReadOnlyDictionary<string, string> changes)
    {
        foreach (var (tag, value) in changes)
        {
            if (!EditableTags.Contains(tag) || value.Length > 8192 || value.Contains('\0')) throw new ArgumentException("字段或值不在允许范围。");
            if (tag is "XMP-dc:Creator" or "XMP-dc:Subject" && value.Split('\n').Length > 256) throw new ArgumentException("作者或关键词最多支持256项。");
            if (tag == "XMP-exif:DateTimeOriginal" && value.Length != 0 &&
                !DateTimeOffset.TryParseExact(value, ["yyyy:MM:dd HH:mm:ss", "yyyy:MM:dd HH:mm:sszzz"], CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
                throw new ArgumentException("拍摄时间请使用 yyyy:MM:dd HH:mm:ss，可附带 +09:00 等时区。");
        }
    }

    public static string Text(JsonElement value) => value.ValueKind == JsonValueKind.Array
        ? string.Join("\n", value.EnumerateArray().Select(v => v.ToString())) : value.ToString();

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
        if (photo.SourceHash != await PhotoDocument.HashAsync(photo.FilePath, cancellation) ||
            (photo.SidecarPath is not null && photo.SidecarHash != await PhotoDocument.HashAsync(photo.SidecarPath, cancellation)))
            throw new IOException("原文件或旁车已被其他程序修改，请重新导入。");
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
            var writable = stagedSidecar ?? stagedImage;
            var arguments = new List<string> { "-charset", "filename=UTF8", "-overwrite_original" };
            foreach (var (tag, value) in changes)
            {
                var writeTag = tag + (tag is "XMP-dc:Title" or "XMP-dc:Description" ? "-x-default" : "");
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
                if (actual != expected.Replace("\r\n", "\n")) throw new InvalidDataException("保存后字段回读不一致：" + tag);
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
            if (photo.SourceHash != await PhotoDocument.HashAsync(photo.FilePath, cancellation) ||
                (photo.SidecarPath is not null && photo.SidecarHash != await PhotoDocument.HashAsync(photo.SidecarPath, cancellation)))
                throw new IOException("保存期间原文件改变，结果未交付。");
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
