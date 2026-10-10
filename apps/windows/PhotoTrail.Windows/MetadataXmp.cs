using System.IO;
using System.Text.Json;
using System.Xml;
namespace PhotoTrail.Windows;
public sealed record XmpImport(IReadOnlyDictionary<string,string> Changes, IReadOnlyList<string> IgnoredTags);
public static class MetadataXmp
{
    public const int MaximumBytes = 8 * 1024 * 1024;
    private const string EmptyPacket = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\"/></rdf:RDF></x:xmpmeta>";
    private static void ValidateXml(string path)
    {
        using var input = new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if (input.Length is < 1 or > MaximumBytes) throw new InvalidDataException("XMP须为不超过8MiB的非空文件。");
        using var reader = XmlReader.Create(input,new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaximumBytes });
        while(reader.Read()) { }
    }
    public static async Task<XmpImport> ImportAsync(ExifToolClient client,string path,CancellationToken cancellation = default)
    {
        if(!Path.GetExtension(path).Equals(".xmp",StringComparison.OrdinalIgnoreCase))throw new ArgumentException("请选择XMP文件。");
        using var guard = new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        ValidateXml(path); var document = await PhotoDocument.LoadAsync(client,path,cancellation);
        if(document.FileType != "XMP")throw new InvalidDataException("内容不是XMP。");
        var changes = new Dictionary<string,string>(); var ignored = new List<string>();
        foreach(var field in document.Embedded.EnumerateObject().Where(field=>field.Name.StartsWith("XMP-")))
        {
            if(!MetadataCsv.Tags.Contains(field.Name)) { if(field.Name != "XMP-x:XMPToolkit")ignored.Add(field.Name); continue; }
            if(field.Name is "XMP-dc:Creator" or "XMP-dc:Subject")
            {
                var words = field.Value.ValueKind == JsonValueKind.Array ? field.Value.EnumerateArray().ToArray() : new[] { field.Value };
                if(words.Any(word=>word.ValueKind != JsonValueKind.String || word.GetString()!.Length == 0 || word.GetString()!.Contains('\r') || word.GetString()!.Contains('\n')))throw new InvalidDataException("XMP列表含不能安全填入编辑区的项。");
                changes.Add(field.Name,string.Join("\n",words.Select(word=>word.GetString())));
            }
            else
            {
                if(field.Value.ValueKind != JsonValueKind.String && !((field.Name == "XMP-xmp:Rating" || PhotoDocument.NumericRange(field.Name) is not null) && field.Value.ValueKind == JsonValueKind.Number))throw new InvalidDataException("XMP手填字段值类型无效。");
                changes.Add(field.Name,field.Value.ToString().Replace("\r\n","\n"));
            }
        }
        if(changes.Count == 0)throw new InvalidDataException("XMP没有当前支持的手填字段。");
        PhotoDocument.ValidateChanges(changes);
        return new(new System.Collections.ObjectModel.ReadOnlyDictionary<string,string>(changes),ignored.AsReadOnly());
    }
    public static async Task ExportAsync(ExifToolClient client,PhotoDocument photo,string path,CancellationToken cancellation = default)
    {
        path = Path.GetFullPath(path);var folder = Path.GetDirectoryName(path)!;
        if(!Path.GetExtension(path).Equals(".xmp",StringComparison.OrdinalIgnoreCase))throw new ArgumentException("输出须为.xmp文件。");
        if(!Directory.Exists(folder))throw new DirectoryNotFoundException("输出文件夹不存在。");
        if(File.Exists(path))throw new IOException("目标已存在，不会覆盖。");
        var draft = new Dictionary<string,string>(photo.Draft); await photo.EnsureUnchangedAsync(cancellation);
        var temporary = Path.Combine(folder,".phototrail-xmp-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temporary);
        var packet = Path.Combine(temporary,"packet.xmp");var savedFolder = Path.Combine(temporary,"saved");var saved = Path.Combine(savedFolder,"packet.xmp");
        try
        {
            if(photo.FileType == "XMP")File.Copy(photo.FilePath,packet);
            else
            {
                var bytes = await client.RunBytesAsync(["-charset","filename=UTF8","-b","-XMP","--",photo.SidecarPath ?? photo.FilePath],cancellation);
                if(bytes.Length > MaximumBytes)throw new InvalidDataException("XMP超过8MiB上限。");
                await File.WriteAllBytesAsync(packet,bytes.Length == 0 ? System.Text.Encoding.UTF8.GetBytes(EmptyPacket) : bytes,cancellation);
            }
            ValidateXml(packet);var document = await PhotoDocument.LoadAsync(client,packet,cancellation);
            document.SetDraft(draft);var result = packet;
            if(document.Draft.Count > 0){Directory.CreateDirectory(savedFolder);result = await MetadataCopy.SaveAsync(client,document,savedFolder,cancellation);}
            ValidateXml(result);await photo.EnsureUnchangedAsync(cancellation);cancellation.ThrowIfCancellationRequested();
            File.Move(result,path);
        }
        finally
        {
            foreach(var file in new[]{packet,saved})if(File.Exists(file))File.Delete(file);
            if(Directory.Exists(savedFolder))Directory.Delete(savedFolder,recursive:false);
            Directory.Delete(temporary,recursive:false);
        }
    }
}
