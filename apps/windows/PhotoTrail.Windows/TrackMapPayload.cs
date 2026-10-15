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
    public static string Many(IEnumerable<string> payloads,CancellationToken token=default){var features=new List<JsonElement>();var names=new List<string>();foreach(var payload in payloads){token.ThrowIfCancellationRequested();using var item=JsonDocument.Parse(payload);features.AddRange(item.RootElement.GetProperty("geojson").GetProperty("features").EnumerateArray().Select(f=>f.Clone()));names.Add(item.RootElement.GetProperty("name").GetString()??"");}return JsonSerializer.Serialize(new{type="tracks",name=string.Join(" / ",names),geojson=new{type="FeatureCollection",features}});}
    public static string Compare(TrackData current,TrackData preview,string name,CancellationToken cancellation=default)
    {
        using var first=JsonDocument.Parse(Build(current,name,cancellation));using var second=JsonDocument.Parse(Build(preview,name,cancellation,"preview"));
        var features=first.RootElement.GetProperty("geojson").GetProperty("features").EnumerateArray().Concat(second.RootElement.GetProperty("geojson").GetProperty("features").EnumerateArray()).Select(f=>f.Clone()).ToArray();
        return JsonSerializer.Serialize(new{type="tracks",name,geojson=new{type="FeatureCollection",features}});
    }
    public static string Build(TrackData? data, string name, CancellationToken cancellation = default,string role="current")
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
            features.Add(new { type = "Feature", properties = new { role }, geometry = new
            { type = coordinates.Count == 1 ? "Point" : "LineString", coordinates = coordinates.Count == 1 ? (object)coordinates[0] : coordinates.ToArray() } });
        }
        cancellation.ThrowIfCancellationRequested();
        return JsonSerializer.Serialize(new { type = "tracks", name, geojson = new { type = "FeatureCollection", features } });
    }
}
