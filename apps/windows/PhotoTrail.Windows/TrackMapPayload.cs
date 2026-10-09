using System.Text.Json;

namespace PhotoTrail.Windows;
public record PhotoMarker(int Id, string Name, MapPoint Position, bool Selected);

public static class TrackMapPayload
{
    public static string Photos(IReadOnlyList<PhotoMarker> markers, int revision, MapPoint? focus, CancellationToken cancellation = default)
    {
        var features = new List<object>();
        foreach (var marker in markers)
        {
            cancellation.ThrowIfCancellationRequested();
            features.Add(new { type = "Feature", properties = new { id = marker.Id, revision, name = marker.Name, selected = marker.Selected }, geometry = new { type = "Point", coordinates = new[] { marker.Position.Longitude, marker.Position.Latitude } } });
        }
        return JsonSerializer.Serialize(new { type = "photos", focus, geojson = new { type = "FeatureCollection", features } });
    }
    public static string Build(TrackData? data, string name, CancellationToken cancellation = default)
    {
        var features = new List<object>();
        foreach (var segment in data?.Segments ?? [])
        {
            var line = new List<double[]>();
            foreach (var point in segment)
            {
                cancellation.ThrowIfCancellationRequested();
                if (line.Count > 0 && Math.Abs(point.Longitude - line[^1][0]) > 180)
                {
                    var before = line[^1]; var edge = before[0] > 0 ? 180.0 : -180.0;
                    var unwrapped = point.Longitude + (before[0] > 0 ? 360 : -360);
                    var fraction = (edge - before[0]) / (unwrapped - before[0]);
                    var latitude = before[1] + (point.Latitude - before[1]) * fraction;
                    line.Add([edge, latitude]); AddFeature(line); line = [[-edge, latitude]];
                }
                line.Add([point.Longitude, point.Latitude]);
            }
            AddFeature(line);
        }
        void AddFeature(List<double[]> coordinates)
        {
            if (coordinates.Count == 0) return;
            features.Add(new { type = "Feature", properties = new { }, geometry = new
            { type = coordinates.Count == 1 ? "Point" : "LineString", coordinates = coordinates.Count == 1 ? (object)coordinates[0] : coordinates.ToArray() } });
        }
        cancellation.ThrowIfCancellationRequested();
        return JsonSerializer.Serialize(new { type = "tracks", name, geojson = new { type = "FeatureCollection", features } });
    }
}
