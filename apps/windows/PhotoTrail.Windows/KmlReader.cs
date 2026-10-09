using System.IO;
using System.IO.Compression;
using System.Text.RegularExpressions;
using System.Xml;

namespace PhotoTrail.Windows;

public static partial class TrackReader
{
    public static TrackData Read(string path, CancellationToken cancellation = default)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        if (extension == ".gpx") return ReadGpx(path, cancellation);
        using var input = File.OpenRead(path);
        if (extension == ".kml") return ReadKml(input, cancellation);
        if (extension == ".kmz") return ReadKmz(input, cancellation);
        throw new InvalidDataException("轨迹格式须为GPX、KML或KMZ。");
    }

    public static TrackData ReadKmz(Stream input, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!input.CanSeek || input.Length > MaximumBytes) throw new InvalidDataException("KMZ最多64MiB。");
        using var archive = new ZipArchive(input, ZipArchiveMode.Read, leaveOpen: true);
        if (archive.Entries.Count > 1024) throw new InvalidDataException("KMZ最多1024个条目。");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase); long total = 0;
        foreach (var entry in archive.Entries)
        {
            cancellation.ThrowIfCancellationRequested();
            var name = entry.FullName.Replace('\\', '/');
            var parts = name.TrimEnd('/').Split('/');
            if (name.StartsWith('/') || parts.Any(part => part is "" or "." or ".." || part.Contains(':')) || !names.Add(name) ||
                ((entry.ExternalAttributes >> 16) & 0xf000) == 0xa000) throw new InvalidDataException("KMZ条目路径、重复名称或链接不安全。");
            if (entry.Length > MaximumBytes || entry.Length > MaximumBytes - total ||
                (entry.Length > 0 && (entry.CompressedLength == 0 || entry.Length / (double)entry.CompressedLength > 100)))
                throw new InvalidDataException("KMZ解压大小或压缩比例超过限制。");
            total += entry.Length;
        }
        var documents = archive.Entries.Where(entry => entry.FullName.EndsWith(".kml", StringComparison.OrdinalIgnoreCase)).ToArray();
        var roots = documents.Where(entry => entry.FullName.Equals("doc.kml", StringComparison.OrdinalIgnoreCase)).ToArray();
        var selected = roots.Length == 1 ? roots[0] : documents.Length == 1 ? documents[0] : null;
        if (selected is null) throw new InvalidDataException("KMZ主KML缺失或不唯一。");
        using var expanded = new MemoryStream();
        using (var member = selected.Open())
        {
            var buffer = new byte[65536]; int length;
            while ((length = member.Read(buffer)) > 0)
            {
                cancellation.ThrowIfCancellationRequested();
                if (expanded.Length + length > MaximumBytes || expanded.Length + length > selected.Length)
                    throw new InvalidDataException("KMZ实际解压数据超限。");
                expanded.Write(buffer, 0, length);
            }
        }
        if (expanded.Length != selected.Length) throw new InvalidDataException("KMZ条目长度不一致。");
        expanded.Position = 0;
        return ReadKml(expanded, cancellation);
    }

    public static TrackData ReadKml(Stream input, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!input.CanSeek || input.Length > MaximumBytes) throw new InvalidDataException("KML最多64MiB。");
        using var reader = XmlReader.Create(input, new XmlReaderSettings
        { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaximumBytes, CloseInput = false });
        reader.MoveToContent();
        if (reader.LocalName != "kml" || !KmlNamespace(reader.NamespaceURI)) throw new InvalidDataException("不是KML文档。");
        var segments = new List<IReadOnlyList<TrackPoint>>(); var path = new List<string> { "kml" }; var pointCount = 0;
        while (reader.Read())
        {
            cancellation.ThrowIfCancellationRequested();
            if (reader.Depth > 64) throw new InvalidDataException("KML嵌套过深。");
            if (reader.NodeType == XmlNodeType.Element)
            {
                var name = KmlNamespace(reader.NamespaceURI) ? reader.LocalName : "";
                path.Add(name);
                var placemark = path.LastIndexOf("Placemark");
                if (name is "LineString" or "Track" && placemark >= 0 &&
                    path.Take(placemark).All(part => part is "kml" or "Document" or "Folder") &&
                    path.Skip(placemark + 1).Take(path.Count - placemark - 2).All(part => part is "MultiGeometry" or "MultiTrack"))
                {
                    var coordinates = new List<string>(); var times = new List<DateTimeOffset>(); var altitudeMode = "clampToGround";
                    using (var geometry = reader.ReadSubtree())
                    {
                        while (geometry.Read())
                        {
                            cancellation.ThrowIfCancellationRequested();
                            if (geometry.Depth > 64) throw new InvalidDataException("KML嵌套过深。");
                            if (geometry.NodeType != XmlNodeType.Element || geometry.Depth != 1 || !KmlNamespace(geometry.NamespaceURI)) continue;
                            var field = geometry.LocalName;
                            if (field == "coordinates" && name == "LineString" || field == "coord" && name == "Track") coordinates.Add(geometry.ReadString().Trim());
                            else if (field == "when" && name == "Track") times.Add(Timestamp(geometry.ReadString().Trim()));
                            else if (field == "altitudeMode") altitudeMode = geometry.ReadString().Trim();
                            if (coordinates.Count > 1_000_000 || times.Count > 1_000_000) throw new InvalidDataException("KML点数超限。");
                        }
                    }
                    if (name == "Track" && times.Count > 0 && times.Count != coordinates.Count) throw new InvalidDataException("KML坐标与逐点时间数量不一致。");
                    var points = new List<TrackPoint>(); var coordinateIndex = 0;
                    foreach (var line in coordinates)
                    {
                        if (name == "LineString")
                        {
                            foreach (var token in Regex.EnumerateMatches(line, @"\S+", RegexOptions.NonBacktracking))
                                AddPoint(line.Substring(token.Index, token.Length), ',');
                        }
                        else if (line.Length == 0)
                        {
                            if (points.Count > 0) { segments.Add(points); points = []; }
                            coordinateIndex++;
                        }
                        else AddPoint(line, null);
                    }
                    if (points.Count > 0) segments.Add(points);
                    void AddPoint(string coordinate, char? separator)
                    {
                        cancellation.ThrowIfCancellationRequested();
                        if (++pointCount > 1_000_000) throw new InvalidDataException("KML最多100万个点。");
                        var parts = separator is { } character ? coordinate.Split(character) : coordinate.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length is < 2 or > 3) throw new InvalidDataException("KML坐标格式无效。");
                        var longitude = Number(parts[0]); var latitude = Number(parts[1]);
                        if (longitude is < -180 or > 180 || latitude is < -90 or > 90) throw new InvalidDataException("KML坐标越界。");
                        var altitude = parts.Length == 3 ? Number(parts[2]) : (double?)null;
                        points.Add(new(longitude, latitude, altitudeMode == "absolute" ? altitude : null, times.Count > 0 ? times[coordinateIndex] : null));
                        coordinateIndex++;
                    }
                    path.RemoveAt(path.Count - 1);
                }
                else if (reader.IsEmptyElement) path.RemoveAt(path.Count - 1);
            }
            else if (reader.NodeType == XmlNodeType.EndElement && path.Count > 0) path.RemoveAt(path.Count - 1);
        }
        if (segments.Count == 0) throw new InvalidDataException("KML没有可用轨迹点。");
        return new(segments);
    }
    private static bool KmlNamespace(string value) => value is "" or "http://www.opengis.net/kml/2.2" or "http://www.opengis.net/kml/2.3" or "http://earth.google.com/kml/2.1" or "http://earth.google.com/kml/2.2" or "http://www.google.com/kml/ext/2.2";
}
