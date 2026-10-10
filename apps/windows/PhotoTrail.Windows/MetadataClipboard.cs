namespace PhotoTrail.Windows;

public static class MetadataClipboard
{
    public static string CopyGps(MapPoint point)
    {
        _ = PhotoDocument.PositionChanges(point,null,"MANUAL");
        return System.Text.Json.JsonSerializer.Serialize(new { format = "PhotoTrail GPS 1", latitude = point.Latitude, longitude = point.Longitude });
    }
    public static MapPoint ReadGps(string text)
    {
        if (text.Length > 4096) throw new ArgumentException("定位剪贴板最多4096字符。");
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(text);
            var data = document.RootElement;
            if (data.ValueKind != System.Text.Json.JsonValueKind.Object || data.EnumerateObject().Count() != 3 ||
                data.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count() != 3 ||
                !data.TryGetProperty("format",out var format) || format.ValueKind != System.Text.Json.JsonValueKind.String || format.GetString() != "PhotoTrail GPS 1" ||
                !data.TryGetProperty("latitude",out var lat) || !lat.TryGetDouble(out var latitude) ||
                !data.TryGetProperty("longitude",out var lon) || !lon.TryGetDouble(out var longitude)) throw new ArgumentException("请复制PhotoTrail GPS坐标后再预览。");
            var point = new MapPoint(longitude,latitude);
            _ = PhotoDocument.PositionChanges(point,null,"MANUAL");
            return point;
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException)
        { throw new ArgumentException("定位剪贴板格式无效。",error); }
    }
    public static string CommonValue(IEnumerable<string> values)
    {
        var distinct = values.Distinct(StringComparer.Ordinal).Take(2).ToArray();
        if (distinct.Length != 1 || distinct[0].Length == 0 || distinct[0].Length > 8192 || distinct[0].Contains('\0')) throw new ArgumentException("所选字段缺失、混合或超出可复制范围，不能复制为单一值。");
        return distinct[0];
    }
    public static Dictionary<string,string> Prepare(string text, IEnumerable<string> tags)
    {
        var selected = tags.Distinct().ToArray();
        if ((selected.Length < 1 || selected.Length > MetadataCsv.Tags.Length) || selected.Any(tag => !MetadataCsv.Tags.Contains(tag))) throw new ArgumentException("请在编辑草稿页勾选支持的目标字段。");
        var changes = selected.ToDictionary(tag => tag, _ => text.Replace("\r\n", "\n"));
        PhotoDocument.ValidateChanges(changes);
        return changes;
    }
}
