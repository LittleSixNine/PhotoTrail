using System.Globalization;
using System.Text.Json;

namespace PhotoTrail.Windows;

internal sealed record BatchTrackResult(string Name,string Status,string Reason,TrackPoint? Point=null,string? Method=null,string Sources="")
{
    public string Summary => $"{Name} · {Status} · {Reason}" + (Point is {} p ? $" · {p.Latitude:F8}, {p.Longitude:F8} · {Method} · {Sources}" : "");
}
internal static class BatchTrackMatch
{
    static string? Read(JsonElement metadata,string tag,bool numeric=false) {
        if(!metadata.TryGetProperty(tag,out var value))return null;
        if((value.ValueKind!=JsonValueKind.String && !(numeric && value.ValueKind==JsonValueKind.Number)) || value.ToString().Length==0)throw new ArgumentException("字段格式或类型错误："+tag);
        return value.ToString();
    }
    internal static string? Capture(PhotoDocument document) {
        if(document.SidecarPath is null&&document.FileType is not("JPEG" or "XMP")&&!document.NewSidecarEditing)return Capture(document.Embedded,null,document.Draft);
        var text=MetadataFields.DateText(document,document.MainDateTag);return text.Length==0?null:text;
    }
    internal static string? Capture(JsonElement embedded,JsonElement? sidecar,IReadOnlyDictionary<string,string> draft) {
        string tag=sidecar is not null||embedded.TryGetProperty("File:FileType",out var xmpType)&&xmpType.ToString()=="XMP"?"XMP-xmp:CreateDate":embedded.TryGetProperty("File:FileType",out var type)&&type.ToString()=="JPEG"?"Composite:SubSecDateTimeOriginal":"XMP-exif:DateTimeOriginal";
        if(draft.TryGetValue(tag,out var pending))return pending.Length==0?null:pending;
        var text=MetadataFields.Read(sidecar??embedded,tag);
        if(sidecar is null&&tag=="XMP-exif:DateTimeOriginal"&&text.Length==0)text=MetadataFields.Read(embedded,"Composite:SubSecDateTimeOriginal");
        return text.Length==0?null:text;
    }

    internal static string Location(PhotoDocument document) {
        string? Value(string tag)=>document.Draft.TryGetValue(tag,out var value)?value:Read(document.Sidecar??document.Embedded,tag,true);
        var latitude=Value("XMP-exif:GPSLatitude");var longitude=Value("XMP-exif:GPSLongitude");var datum=Value("XMP-exif:GPSMapDatum");
        if(latitude is null && longitude is null) {
            latitude=Read(document.Embedded,"GPS:GPSLatitude",true);longitude=Read(document.Embedded,"GPS:GPSLongitude",true);datum=Read(document.Embedded,"GPS:GPSMapDatum");
            var latRef=Read(document.Embedded,"GPS:GPSLatitudeRef");var lonRef=Read(document.Embedded,"GPS:GPSLongitudeRef");
            if(latRef is not (null or "N" or "S") || lonRef is not (null or "E" or "W"))throw new ArgumentException("定位方向格式错误。");
            if(latRef=="S"&&latitude is not null)latitude="-"+latitude.TrimStart('-');
            if(lonRef=="W"&&longitude is not null)longitude="-"+longitude.TrimStart('-');
        }
        if(string.IsNullOrEmpty(latitude)&&string.IsNullOrEmpty(longitude))return "missing";
        if(datum is not null && datum.Replace("-","").Replace(" ","").ToUpperInvariant()!="WGS84")throw new ArgumentException("坐标基准未知，保留已有定位。");
        if(!double.TryParse(latitude,NumberStyles.Float,CultureInfo.InvariantCulture,out var lat)||!double.TryParse(longitude,NumberStyles.Float,CultureInfo.InvariantCulture,out var lon)||!double.IsFinite(lat)||!double.IsFinite(lon)||Math.Abs(lat)>90||Math.Abs(lon)>180)throw new ArgumentException("已有定位格式错误，不能当作缺失覆盖。");
        return "valid";
    }
    internal static BatchTrackResult Calculate(PhotoDocument document,IReadOnlyList<TrackSnapshot> tracks,bool overwrite,CancellationToken token) {
        var name=System.IO.Path.GetFileName(document.FilePath);token.ThrowIfCancellationRequested();
        if(!document.CanStage)return new(name,"不可编辑","保留全部草稿。");
        try{if(Location(document)=="valid"&&!overwrite)return new(name,"已有定位保持","补齐缺失定位，不覆盖。");}
        catch(ArgumentException error){return new(name,"定位无效",error.Message);}
        string? text;
        try{text=Capture(document);}catch(ArgumentException error){return new(name,"非法时间",error.Message);}
        if(text is null)return new(name,"缺失时间","未猜测照片拍摄时间。");
        VerifiedPhotoDate? date;
        try {
            if(text.Length>=19&&text[4]=='-'&&text[7]=='-'&&text[10]=='T')text=text[..4]+":"+text[5..7]+":"+text[8..10]+" "+text[11..];
            date=document.VerifiedCaptureDate;if(date is null)return new(name,"非法时间",document.DateReadFailure.Length>0?document.DateReadFailure:"共享日期未验证或拒绝此输入。");
        }catch(ArgumentException error){return new(name,"非法时间",error.Message);}
        if(date.InstantLimitation is {} limitation)return new(name,limitation,"共享日期有效，但不能无损适配轨迹时刻；不补时区、不舍入、不改原文。");
        var time=date.Instant()!.Value;
        var candidates=new List<(TrackMatch Match,TrackSnapshot Source)>();
        foreach(var track in tracks) {
            token.ThrowIfCancellationRequested();var result=track.Data.Match(time,cancellation:token);
            if(result.Status=="ambiguous")return new(name,"歧义",result.Reason,Sources:System.IO.Path.GetFileName(track.Path));
            if(result.Point is not null)candidates.Add((result,track));
        }
        if(candidates.Count==0)return new(name,"未匹配","无可安全匹配的点；不跨段、不跨无时间点、不外推，间隔最多120分钟。");
        if(candidates.Any(a=>candidates.Any(b=>TrackData.Distance(a.Match.Point!,b.Match.Point!)>1)))return new(name,"歧义","参与轨迹的候选位置相差超过1米。");
        // Equivalent coordinates retain the recorded-point method when available.
        var chosen=candidates.FirstOrDefault(c=>c.Match.Method=="recorded");if(chosen.Source is null)chosen=candidates[0];
        return new(name,"成功","仅计算结果，尚未加入草稿。",chosen.Match.Point,chosen.Match.Method,string.Join("；",candidates.Select(c=>System.IO.Path.GetFileName(c.Source.Path))));
    }
}
