using System.Text.Json;

namespace PhotoTrail.Windows;

public record MapPoint(double Longitude, double Latitude);

public static class MapMessage
{
    public const string Page = "https://phototrail.local/map.html";
    public const string GooglePage = "https://phototrail.local/google.html";
    private static bool IsLocalPage(string source) => source == Page || source == GooglePage;
    public static bool TryPhoto(string source, string json, out int id, out int revision)
    {
        id = revision = -1;
        if (!IsLocalPage(source) || json.Length > 4096) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            var data = document.RootElement;
            return data.ValueKind == JsonValueKind.Object && data.TryGetProperty("type", out var type) && type.ValueKind == JsonValueKind.String && type.GetString() == "select-photo" &&
                data.TryGetProperty("id", out var identifier) && identifier.TryGetInt32(out id) && id >= 0 &&
                data.TryGetProperty("revision", out var generation) && generation.TryGetInt32(out revision) && revision >= 0;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException) { return false; }
    }

    public static bool IsGoogleBootstrap(string source, string json) => source == GooglePage && IsType(source, json, "google-bootstrap");
    public static bool IsReady(string source, string json) => IsType(source, json, "ready");
    public static bool IsError(string source, string json) => IsType(source, json, "map-error");
    private static bool IsType(string source, string json, string expected)
    {
        if (!IsLocalPage(source) || json.Length > 4096) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("type", out var type) &&
                type.ValueKind == JsonValueKind.String && type.GetString() == expected;
        }
        catch (JsonException) { return false; }
    }

    public static bool TryPoint(string source, string json, out MapPoint? point)
    {
        point = null;
        if (!IsLocalPage(source) || json.Length > 4096) return false;
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
