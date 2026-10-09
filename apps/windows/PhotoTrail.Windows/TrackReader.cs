using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Xml;

namespace PhotoTrail.Windows;

public record TrackPoint(double Longitude, double Latitude, double? Elevation, DateTimeOffset? Time);
public record TrackMatch(string Status, TrackPoint? Point, string? Method, string Reason);

public sealed class TrackData(IReadOnlyList<IReadOnlyList<TrackPoint>> segments)
{
    public IReadOnlyList<IReadOnlyList<TrackPoint>> Segments { get; } =
        Array.AsReadOnly(segments.Select(segment => (IReadOnlyList<TrackPoint>)Array.AsReadOnly(segment.ToArray())).ToArray());

    public TrackMatch Match(DateTimeOffset time, TimeSpan? maximumGap = null)
    {
        var gap = maximumGap ?? TimeSpan.FromMinutes(120);
        if (gap <= TimeSpan.Zero) return new("unmatched", null, null, "匹配间隔无效。");
        var exact = new List<TrackPoint>(); var interpolated = new List<TrackPoint>(); var invalidOrder = false;
        foreach (var segment in Segments)
        {
            foreach (var point in segment.Where(point => point.Time == time)) exact.Add(point);
            for (var index = 1; index < segment.Count; index++)
            {
                var before = segment[index - 1]; var after = segment[index];
                // Missing timestamps remain a break; never filter them out and bridge neighboring points.
                if (before.Time is not { } start || after.Time is not { } end) continue;
                var duration = end - start;
                if (duration <= TimeSpan.Zero) { invalidOrder = true; continue; }
                if (time <= start || time >= end || duration > gap) continue;
                var fraction = (time - start).TotalSeconds / duration.TotalSeconds;
                var longitudeDelta = (after.Longitude - before.Longitude + 540) % 360 - 180;
                var longitude = (before.Longitude + longitudeDelta * fraction + 540) % 360 - 180;
                var elevation = before.Elevation is { } first && after.Elevation is { } last ? first + (last - first) * fraction : (double?)null;
                interpolated.Add(new(longitude, before.Latitude + (after.Latitude - before.Latitude) * fraction, elevation, time));
            }
        }
        var candidates = exact.Count > 0 ? exact : interpolated;
        if (candidates.Count == 0) return new("unmatched", null, null, invalidOrder ? "轨迹时间倒退或重复，未自动匹配。" : "时间不在可安全匹配的区间内。");
        if (candidates.Skip(1).Any(point => Distance(candidates[0], point) > 1))
            return new("ambiguous", null, null, "同一拍摄时间对应不同位置，请选择轨迹来源。");
        return new("matched", candidates[0], exact.Count > 0 ? "recorded" : "linear", "已匹配；尚未加入照片草稿。");
    }

    private static double Distance(TrackPoint first, TrackPoint second)
    {
        // ponytail: spherical distance for the 1m ambiguity threshold; use ellipsoidal geodesics if required.
        var radians = Math.PI / 180;
        var latitude = (second.Latitude - first.Latitude) * radians;
        var longitude = (second.Longitude - first.Longitude) * radians;
        var square = Math.Pow(Math.Sin(latitude / 2), 2) + Math.Cos(first.Latitude * radians) * Math.Cos(second.Latitude * radians) * Math.Pow(Math.Sin(longitude / 2), 2);
        return 6371000 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(square, 0, 1)));
    }
}

public static partial class TrackReader
{
    public const long MaximumBytes = 64 * 1024 * 1024;
    public static DateTimeOffset ParseTimestamp(string value) => Timestamp(value);
    public static TrackData ReadGpx(string path, CancellationToken cancellation = default)
    {
        using var input = File.OpenRead(path);
        return ReadGpx(input, cancellation);
    }

    public static TrackData ReadGpx(Stream input, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!input.CanSeek || input.Length > MaximumBytes) throw new InvalidDataException("轨迹输入须为不超过64MiB的本地文件。");
        using var reader = XmlReader.Create(input, new XmlReaderSettings
        { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaximumBytes, CloseInput = false });
        reader.MoveToContent();
        if (reader.LocalName != "gpx" || !KnownNamespace(reader.NamespaceURI)) throw new InvalidDataException("不是GPX轨迹文档。");
        var segments = new List<IReadOnlyList<TrackPoint>>();
        List<TrackPoint>? points = null;
        var trackDepth = -1; var segmentDepth = -1; var count = 0;
        while (reader.Read())
        {
            cancellation.ThrowIfCancellationRequested();
            if (reader.Depth > 64) throw new InvalidDataException("轨迹XML嵌套过深。");
            if (!KnownNamespace(reader.NamespaceURI)) continue;
            if (reader.NodeType == XmlNodeType.Element)
            {
                if (reader.LocalName == "trk" && reader.Depth == 1 && !reader.IsEmptyElement) trackDepth = reader.Depth;
                else if (reader.LocalName == "trkseg" && trackDepth == 1 && reader.Depth == 2 && !reader.IsEmptyElement)
                { points = []; segmentDepth = reader.Depth; }
                else if (reader.LocalName == "trkpt" && points is not null && reader.Depth == segmentDepth + 1)
                {
                    if (++count > 1_000_000) throw new InvalidDataException("轨迹最多支持100万个点。");
                    var latitude = Number(reader.GetAttribute("lat")); var longitude = Number(reader.GetAttribute("lon"));
                    if (latitude is < -90 or > 90 || longitude is < -180 or > 180) throw new InvalidDataException("轨迹坐标越界。");
                    double? elevation = null; DateTimeOffset? time = null;
                    using (var subtree = reader.ReadSubtree())
                    {
                        while (subtree.Read())
                        {
                            cancellation.ThrowIfCancellationRequested();
                            if (subtree.Depth > 61) throw new InvalidDataException("轨迹XML嵌套过深。");
                            if (subtree.NodeType != XmlNodeType.Element || subtree.Depth != 1 || !KnownNamespace(subtree.NamespaceURI)) continue;
                            if (subtree.LocalName == "ele") elevation = Number(subtree.ReadString().Trim());
                            else if (subtree.LocalName == "time") time = Timestamp(subtree.ReadString().Trim());
                        }
                    }
                    points.Add(new(longitude, latitude, elevation, time));
                }
            }
            else if (reader.NodeType == XmlNodeType.EndElement)
            {
                if (reader.LocalName == "trkseg" && reader.Depth == segmentDepth)
                { if (points is { Count: > 0 }) segments.Add(points); points = null; segmentDepth = -1; }
                else if (reader.LocalName == "trk" && reader.Depth == trackDepth) trackDepth = -1;
            }
        }
        if (segments.Count == 0) throw new InvalidDataException("GPX没有可用轨迹点。");
        return new(segments);
    }

    private static bool KnownNamespace(string value) => value is "" or "http://www.topografix.com/GPX/1/0" or "http://www.topografix.com/GPX/1/1";
    private static double Number(string? value) => double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number) && double.IsFinite(number)
        ? number : throw new InvalidDataException("轨迹数字无效。");
    private static DateTimeOffset Timestamp(string value)
    {
        if (value.Length <= 64 && Regex.IsMatch(value, @"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking) &&
            DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var time)) return time;
        throw new InvalidDataException("轨迹时间须为带Z或UTC偏移的ISO8601时间。");
    }
}
