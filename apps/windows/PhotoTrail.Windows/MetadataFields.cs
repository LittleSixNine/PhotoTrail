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
    internal static bool IsList(string tag)=>tag is "XMP-dc:Creator" or "XMP-dc:Subject";
    internal static bool CanEdit(PhotoDocument doc,string tag) {
        if(!PhotoDocument.EditableTags.Contains(tag)||!doc.CanStage||doc.InspectionError.Length>0)return false;
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
        if(changes.Keys.Any(t=>!CanEdit(doc,t)))throw new ArgumentException("字段来源没有唯一且可读的写入资格；EXIF仅支持无旁车JPEG图内目标。");
    }
    internal static string DateText(PhotoDocument doc,string tag) {
        if(doc.Draft.TryGetValue(tag,out var draft))return draft;
        var source=tag.StartsWith("XMP-",StringComparison.Ordinal)?doc.Sidecar??doc.Embedded:doc.Embedded;
        JsonElement value;
        if(!source.TryGetProperty(tag,out value)&&(!DateGroups.TryGetValue(tag,out var parts)||!source.TryGetProperty(parts[0],out value)))return "";
        if(value.ValueKind!=JsonValueKind.String||value.GetString()!.Length==0)throw new ArgumentException("日期来源类型或空值非法；不能当作缺失。");
        return Read(source,tag);
    }
    internal static string Original(PhotoDocument doc,string tag)=>Read(tag.StartsWith("XMP-",StringComparison.Ordinal)?doc.Sidecar??doc.Embedded:doc.Embedded,tag);
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
            if(!DateGroups.TryGetValue(tag,out var parts)){result.Add(tag,text);continue;}
            if(text.Length==0){foreach(var part in parts)result.Add(part,"");continue;}
            // Calendar validity and exact text are proved by the pinned Swift host before writing.
            var match=Regex.Match(text,@"^(\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$");
            if(!match.Success)throw new ArgumentException("EXIF成组日期文字不符合已验证格式。");
            result.Add(parts[0],match.Groups[1].Value);result.Add(parts[1],match.Groups[2].Value);result.Add(parts[2],match.Groups[3].Value=="Z"?"+00:00":match.Groups[3].Value);
        }
        return result;
    }
}
