using System.Text.Json;

namespace PhotoTrail.Windows;

public record MapPoint(double Longitude, double Latitude);

public static class MapMessage
{
    public const string Page = "https://phototrail.local/map.html";

    public static bool IsReady(string source, string json)
    {
        if (source != Page || json.Length > 4096) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("type", out var type) &&
                type.ValueKind == JsonValueKind.String && type.GetString() == "ready";
        }
        catch (JsonException) { return false; }
    }

    public static bool TryPoint(string source, string json, out MapPoint? point)
    {
        point = null;
        if (source != Page || json.Length > 4096) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            var data = document.RootElement;
            if (data.ValueKind != JsonValueKind.Object || !data.TryGetProperty("type", out var type) ||
                type.ValueKind != JsonValueKind.String || type.GetString() != "point" ||
                !data.TryGetProperty("longitude", out var lng) || !data.TryGetProperty("latitude", out var lat) ||
                !lng.TryGetDouble(out var longitude) || !lat.TryGetDouble(out var latitude) ||
                !double.IsFinite(longitude) || !double.IsFinite(latitude) ||
                longitude is < -180 or > 180 || latitude is < -90 or > 90) return false;
            point = new(longitude, latitude);
            return true;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return false; }
    }
}
