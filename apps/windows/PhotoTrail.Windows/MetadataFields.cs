using System.Text.Json;
using System.Text.RegularExpressions;
namespace PhotoTrail.Windows;

internal static class MetadataFields
{
    internal static readonly string[] ExifText=["IFD0:Artist","IFD0:ImageDescription","IFD0:Copyright","IFD0:Software","ExifIFD:UserComment","IFD0:Make","IFD0:Model","ExifIFD:SerialNumber","ExifIFD:LensMake","ExifIFD:LensModel","ExifIFD:LensSerialNumber"];
    internal static readonly Dictionary<string,string[]> DateGroups=new() {
        ["Composite:SubSecDateTimeOriginal"]=["ExifIFD:DateTimeOriginal","ExifIFD:SubSecTimeOriginal","ExifIFD:OffsetTimeOriginal"],
        ["Composite:SubSecCreateDate"]=["ExifIFD:CreateDate","ExifIFD:SubSecTimeDigitized","ExifIFD:OffsetTimeDigitized"],
        ["Composite:SubSecModifyDate"]=["IFD0:ModifyDate","ExifIFD:SubSecTime","ExifIFD:OffsetTime"]
    };
    internal static readonly Dictionary<string,(double Minimum,double Maximum,bool Integer)> ExifNumeric=new() {
        ["ExifIFD:ExposureTime"]=(.000001,86400,false),["ExifIFD:ShutterSpeedValue"]=(.000001,86400,false),
        ["ExifIFD:FNumber"]=(.1,128,false),["ExifIFD:ApertureValue"]=(1,128,false),["ExifIFD:MaxApertureValue"]=(1,128,false),
        ["ExifIFD:ISO"]=(1,65535,true),["ExifIFD:FocalLength"]=(.1,10000,false),["ExifIFD:FocalLengthIn35mmFormat"]=(0,65535,true),
        ["ExifIFD:ExposureCompensation"]=(-100,100,false),["ExifIFD:Flash"]=(0,127,true),["ExifIFD:ColorSpace"]=(1,65535,true),
        ["ExifIFD:ExposureMode"]=(0,2,true),["ExifIFD:ExposureProgram"]=(0,8,true),["ExifIFD:MeteringMode"]=(0,255,true),
        ["ExifIFD:WhiteBalance"]=(0,1,true),["ExifIFD:Saturation"]=(0,2,true),["ExifIFD:Sharpness"]=(0,2,true),
        ["IFD0:Orientation"]=(1,8,true),["IFD0:XResolution"]=(.000001,1000000,false),["IFD0:YResolution"]=(.000001,1000000,false),["IFD0:ResolutionUnit"]=(1,3,true)
    };
    internal static bool IsApex(string tag)=>tag is "ExifIFD:ShutterSpeedValue" or "ExifIFD:ApertureValue" or "ExifIFD:MaxApertureValue";
    internal static bool Matches(string tag,string actual,string expected) {
        if(MetadataTimes.IsSystem(tag))return MetadataTimes.Parse(actual)==MetadataTimes.Parse(expected);
        if(tag is "XMP-exif:GPSLatitude" or "XMP-exif:GPSLongitude" or "XMP-exif:GPSAltitude"&&expected.Length>0)
            return double.TryParse(actual,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var gps)&&double.TryParse(expected,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var targetGps)&&double.IsFinite(gps)&&double.IsFinite(targetGps)&&Math.Abs(gps-targetGps)<=1e-8;
        if(PhotoDocument.NumericRange(tag) is not null&&expected.Length>0) {
            var target=PhotoDocument.CheckedNumber(tag,expected);
            return double.TryParse(actual,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var value)&&double.IsFinite(value)&&Math.Abs(value-target)<=Math.Max(1e-12,Math.Abs(target)*(IsApex(tag)?1e-6:1e-9));
        }
        return IsList(tag)?List(actual).SequenceEqual(List(expected)):VerifiedMetadataDates.IsDate(tag)?actual.Replace("Z","+00:00")==expected.Replace("Z","+00:00"):actual==expected;
    }
    internal static bool IsList(string tag)=>tag is "XMP-dc:Creator" or "XMP-dc:Subject" || MetadataIptc.Fields.TryGetValue(tag,out var field)&&field.List;
    internal static bool CanEdit(PhotoDocument doc,string tag) {
        if(!PhotoDocument.EditableTags.Contains(tag)||!doc.CanStage||doc.InspectionError.Length>0)return false;
        if(MetadataIptc.Fields.TryGetValue(tag,out var iptc)&&(doc.Iptc is null||doc.Iptc.Error.Length>0||!iptc.List&&doc.Iptc.Records.Count(r=>r.Record==2&&r.Id==iptc.Dataset)>1))return false;
        var source=tag.StartsWith("XMP-",StringComparison.Ordinal)?doc.Sidecar??doc.Embedded:doc.Embedded;
        var targets=DateGroups.TryGetValue(tag,out var components)?components:[tag];
        if(targets.Any(t=>source.EnumerateObject().Count(v=>v.Name==t)>1))return false;
        var role=doc.SidecarPath is not null?"旁车XMP":doc.FileType=="XMP"?"独立XMP":"原图";
        // CopyN may disambiguate names across different families; only repeated exact-family targets are ambiguous.
        if(doc.Inspection?.Count(v=>v.Canonical==tag&&v.Role==role)>1)return false;
        return tag.StartsWith("XMP-",StringComparison.Ordinal)||doc.FileType=="JPEG"&&doc.SidecarPath is null&&!doc.NewSidecarEditing;
    }
    internal static void Require(PhotoDocument doc,IReadOnlyDictionary<string,string> changes) {
        PhotoDocument.ValidateChanges(changes);
        if(changes.Keys.Any(MetadataIptc.Fields.ContainsKey)) (doc.Iptc??throw new ArgumentException("IPTC原始来源未读取，保留只读。")).Require(changes);
        if(changes.Keys.Any(t=>!CanEdit(doc,t)))throw new ArgumentException("字段来源没有唯一且可读的写入资格；EXIF／IPTC仅支持无旁车JPEG图内目标。");
    }
    internal static string DateText(PhotoDocument doc,string tag) {
        if(doc.Draft.TryGetValue(tag,out var draft))return draft;
        var source=tag.StartsWith("XMP-",StringComparison.Ordinal)?doc.Sidecar??doc.Embedded:doc.Embedded;
        JsonElement value;
        if(!source.TryGetProperty(tag,out value)&&(!DateGroups.TryGetValue(tag,out var parts)||!source.TryGetProperty(parts[0],out value)))return "";
        if(value.ValueKind!=JsonValueKind.String||value.GetString()!.Length==0)throw new ArgumentException("日期来源类型或空值非法；不能当作缺失。");
        return Read(source,tag);
    }
    internal static string Original(PhotoDocument doc,string tag)=>MetadataTimes.IsSystem(tag)?doc.Times?.Value(tag)??"":Read(tag.StartsWith("XMP-",StringComparison.Ordinal)?doc.Sidecar??doc.Embedded:doc.Embedded,tag);
    internal static string Read(JsonElement source,string tag) {
        if(source.TryGetProperty(tag,out var value)) {
            if(!IsList(tag))return PhotoDocument.Text(value);
            if(value.ValueKind==JsonValueKind.Array&&value.EnumerateArray().All(v=>v.ValueKind==JsonValueKind.String))return FormatList(value.EnumerateArray().Select(v=>v.GetString()!));
            return value.ValueKind==JsonValueKind.String?FormatList([value.GetString()!]):PhotoDocument.Text(value);
        }
        if(DateGroups.TryGetValue(tag,out var parts)) {
            string Get(string key)=>source.TryGetProperty(key,out var item)?item.ToString():"";
            var main=Get(parts[0]);if(main.Length==0)return "";
            var sub=Get(parts[1]);return main+(sub.Length==0?"":"."+sub)+Get(parts[2]);
        }
        return "";
    }
    // Legacy newline lists remain readable; JSON arrays preserve commas and newlines within an element.
    internal static string[] List(string text) {
        if(text.Length==0)return [];
        string[] values;
        if(text.TrimStart().StartsWith('[')) {
            try {values=JsonSerializer.Deserialize<string[]>(text)??throw new ArgumentException("列表数组无效。");}
            catch(JsonException e){throw new ArgumentException("列表使用每行一项或JSON字符串数组。",e);}
        } else values=text.Replace("\r\n","\n").Split('\n');
        if(values.Length>256||values.Any(v=>string.IsNullOrEmpty(v)||v.Contains('\0')))throw new ArgumentException("列表最多256项，每项非空且不含NUL。");
        return values;
    }
    internal static string FormatList(IEnumerable<string> input) {
        var values=input.ToArray();
        return values.Any(v=>v.Contains('\n')||v.Contains('\r'))||values.FirstOrDefault()?.TrimStart().StartsWith('[')==true?JsonSerializer.Serialize(values):string.Join("\n",values);
    }
    internal static Dictionary<string,string> WriteChanges(IReadOnlyDictionary<string,string> changes) {
        var result=new Dictionary<string,string>();
        foreach(var (tag,text) in changes) {
            if(!DateGroups.TryGetValue(tag,out var parts)){result.Add(tag,MetadataTimes.Normalize(tag,text));continue;}
            if(text.Length==0){foreach(var part in parts)result.Add(part,"");continue;}
            // Calendar validity and exact text are proved by the pinned Swift host before writing.
            var match=Regex.Match(text,@"^(\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$");
            if(!match.Success)throw new ArgumentException("EXIF成组日期文字不符合已验证格式。");
            result.Add(parts[0],match.Groups[1].Value);result.Add(parts[1],match.Groups[2].Value);result.Add(parts[2],match.Groups[3].Value=="Z"?"+00:00":match.Groups[3].Value);
        }
        return result;
    }
}
