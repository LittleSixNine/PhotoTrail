using System.Text.Json;
namespace PhotoTrail.Windows;

public record MapPlace(int Id, MapPoint Point, string Status, IReadOnlyDictionary<string,string> Fields)
{
    public static bool TryRead(string source, string json, out MapPlace? place)
    {
        place=null;
        if(source!=MapMessage.GooglePage||json.Length>4096)return false;
        try
        {
            using var document=JsonDocument.Parse(json); var data=document.RootElement;
            if(data.GetProperty("type").GetString()!="place")return false;
            var id=data.GetProperty("id").GetInt32(); if(id<0)return false;
            var point=data.GetProperty("point"); var lon=point.GetProperty("Longitude").GetDouble(); var lat=point.GetProperty("Latitude").GetDouble();
            if(!double.IsFinite(lon)||!double.IsFinite(lat)||Math.Abs(lon)>180||Math.Abs(lat)>90)return false;
            var status=data.GetProperty("status").GetString()!;
            if(status is not ("OK" or "ZERO_RESULTS" or "OVER_QUERY_LIMIT" or "REQUEST_DENIED" or "INVALID_REQUEST" or "UNKNOWN_ERROR" or "ERROR"))return false;
            var fields=new Dictionary<string,string>();
            var values=data.GetProperty("fields"); if(values.ValueKind!=JsonValueKind.Object)return false;
            foreach(var property in values.EnumerateObject())
            {
                if(property.Name is not ("country" or "countryCode" or "state" or "city" or "sublocation"))return false;
                var value=property.Value.GetString()!;
                if(value is null||value.Length>256||value.Any(char.IsControl)||fields.ContainsKey(property.Name))return false;
                if(property.Name=="countryCode"&&value.Length>0&&(value.Length!=2||value.Any(c=>c is < 'A' or > 'Z')))return false;
                fields.Add(property.Name,value);
            }
            if(status!="OK"&&fields.Count>0)return false;
            place=new(id,new(lon,lat),status,fields);return true;
        }
        catch(Exception error) when(error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException){return false;}
    }
    public string Summary
    {
        get
        {
            var labels = new Dictionary<string,string> { ["country"]="国家", ["countryCode"]="两位国家码", ["state"]="省／州", ["city"]="城市", ["sublocation"]="区／地点" };
            var values = Fields.Where(pair=>!string.IsNullOrWhiteSpace(pair.Value)).Select(pair=>labels[pair.Key]+"："+pair.Value).ToArray();
            return values.Length > 0 ? string.Join(" · ", values) : "未返回可确认的地区字段；未改照片。";
        }
    }
    public bool Matches(int id,MapPoint? point)=>Id==id&&Point==point;
}
