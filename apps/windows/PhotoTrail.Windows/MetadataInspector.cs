using System.IO;
using System.Text.Json;
namespace PhotoTrail.Windows;

// Fixed 73-field display directory from Mac 73c0640b. Display matching never grants write permission.
public sealed record InspectorField(string Section,string Tag)
{
    public string Name=>MetadataInspector.Label(Tag);
}
public sealed record InspectorValue(string Role,string Tag,string Value)
{
    public string Family=>Tag.Split(':')[0];
    public string Canonical=>Family+":"+Tag.Split(':')[^1];
    public bool IsCopy=>Tag.Split(':').Length>2;
    public bool Counted=>Family is not("File" or "System" or "Composite" or "ExifTool");
}
public sealed record InspectorRow(string Section,string Name,string Tag,string Value,string State,bool IsCommon,bool CanEdit=false,string? EditTag=null)
{
    public string FamilyTag {get {int colon=Tag.LastIndexOf(':');return colon>=0?Tag[..colon]:Tag;}}
    public string Permission=>CanEdit?"编辑精确来源字段":"只读";
    public bool ShowFullTag {get;init;}=true;
    public bool HasDraft {get;init;}
    public string SourceLabel=>ShowFullTag?Tag:FamilyTag;
    public string MissingLabel {get;init;}="";
    public string DraftLabel {get;init;}="";
    public string DisplayValue=>Value.Length==0?(State.Contains("未读")||State.Contains("失败")||State.Contains("过期")?State:MissingLabel):Value;
    public string DisplayState=>(HasDraft?"● "+DraftLabel+" · ":"")+State;
    public string ActionLabel=>CanEdit?"✎":"🔒";
}
public static class MetadataInspector
{
    public static readonly InspectorField[] Standard=[
        new("文件","File:FileName"),
        new("文件","File:FilePath"),
        new("文件","File:MDItemUserTags"),
        new("作者","EXIF:Artist"),
        new("作者","IPTC:By-line"),
        new("作者","IPTC:By-lineTitle"),
        new("作者","IPTC:Contact"),
        new("描述信息","EXIF:ImageDescription"),
        new("描述信息","EXIF:Copyright"),
        new("描述信息","EXIF:Software"),
        new("描述信息","EXIF:UserComment"),
        new("描述信息","IPTC:Headline"),
        new("描述信息","IPTC:Caption-Abstract"),
        new("描述信息","IPTC:ObjectName"),
        new("描述信息","IPTC:Keywords"),
        new("描述信息","XMP-dc:Subject"),
        new("描述信息","XMP:Keyword"),
        new("日期和时间","File:FileCreateDate"),
        new("日期和时间","File:FileModifyDate"),
        new("日期和时间","Composite:SubSecDateTimeOriginal"),
        new("日期和时间","Composite:SubSecCreateDate"),
        new("日期和时间","Composite:SubSecModifyDate"),
        new("日期和时间","IPTC:DateCreated"),
        new("日期和时间","IPTC:TimeCreated"),
        new("日期和时间","XMP-xmp:CreateDate"),
        new("日期和时间","XMP-xmp:ModifyDate"),
        new("相机","IFD0:Make"),
        new("相机","IFD0:Model"),
        new("相机","EXIF:SerialNumber"),
        new("拍摄参数","ExifIFD:ISO"),
        new("拍摄参数","ExifIFD:FNumber"),
        new("拍摄参数","EXIF:ApertureValue"),
        new("拍摄参数","ExifIFD:ShutterSpeedValue"),
        new("拍摄参数","ExifIFD:FocalLength"),
        new("拍摄参数","EXIF:FocalLengthIn35mmFormat"),
        new("拍摄参数","ExifIFD:ExposureCompensation"),
        new("拍摄参数","EXIF:Flash"),
        new("高级参数","EXIF:ColorSpace"),
        new("高级参数","EXIF:MaxApertureValue"),
        new("高级参数","EXIF:ExposureMode"),
        new("高级参数","EXIF:ExposureProgram"),
        new("高级参数","EXIF:ExposureTime"),
        new("高级参数","EXIF:MeteringMode"),
        new("高级参数","EXIF:WhiteBalance"),
        new("高级参数","EXIF:Saturation"),
        new("高级参数","EXIF:Sharpness"),
        new("镜头","EXIF:LensMake"),
        new("镜头","EXIF:Lens"),
        new("镜头","EXIF:LensModel"),
        new("镜头","EXIF:LensSerialNumber"),
        new("镜头","XMP-aux:Lens"),
        new("镜头","XMP:LensInfo"),
        new("镜头","XMP-exif:FocalLength"),
        new("尺寸和分辨率","EXIF:Orientation"),
        new("尺寸和分辨率","EXIF:ImageWidth"),
        new("尺寸和分辨率","EXIF:ImageHeight"),
        new("尺寸和分辨率","EXIF:ExifImageWidth"),
        new("尺寸和分辨率","EXIF:ExifImageHeight"),
        new("尺寸和分辨率","EXIF:XResolution"),
        new("尺寸和分辨率","EXIF:YResolution"),
        new("GPS坐标","EXIF:GPSLatitude"),
        new("GPS坐标","EXIF:GPSLatitudeRef"),
        new("GPS坐标","EXIF:GPSLongitude"),
        new("GPS坐标","EXIF:GPSLongitudeRef"),
        new("GPS坐标","EXIF:GPSAltitude"),
        new("GPS坐标","EXIF:GPSAltitudeRef"),
        new("GPS坐标","EXIF:GPSDateStamp"),
        new("GPS坐标","EXIF:GPSTimeStamp"),
        new("地址","IPTC:City"),
        new("地址","IPTC:Province-State"),
        new("地址","IPTC:Sub-location"),
        new("地址","IPTC:Country-PrimaryLocationName"),
        new("地址","IPTC:Country-PrimaryLocationCode"),
    ];
    public static readonly string[] DefaultCommon=[
"File:FileName","File:FilePath","Composite:SubSecDateTimeOriginal","Composite:SubSecCreateDate","Composite:SubSecModifyDate","IPTC:DateCreated","IPTC:TimeCreated","XMP-xmp:CreateDate","XMP-xmp:ModifyDate","XMP-exif:DateTimeOriginal","XMP-exif:DateTimeDigitized","IFD0:Make","IFD0:Model","ExifIFD:ISO","ExifIFD:FNumber","ExifIFD:ShutterSpeedValue","ExifIFD:FocalLength","ExifIFD:ExposureCompensation","EXIF:GPSLatitude","EXIF:GPSLatitudeRef","EXIF:GPSLongitude","EXIF:GPSLongitudeRef","EXIF:GPSDateStamp","EXIF:GPSTimeStamp"
    ];
    public static readonly string[] Configurable=Standard.Select(f=>f.Tag).Concat(DefaultCommon).Concat(PhotoDocument.EditableTags).Distinct(StringComparer.Ordinal).ToArray();
    public static IEnumerable<string> Options(IEnumerable<PhotoDocument> docs,IEnumerable<string> configured)=>Configurable.Concat(configured).Concat(docs.SelectMany(d=>d.Inspection??[]).Select(v=>v.Canonical)).Distinct(StringComparer.Ordinal);
    public static string Label(string tag)=>tag.Split(':')[^1] switch {
        "FileName"=>"文件名", "FilePath"=>"完整路径", "Make"=>"制造商", "Model"=>"设备型号", "ISO"=>"感光度", "FNumber"=>"光圈", "ShutterSpeedValue"=>"快门", "FocalLength"=>"焦距", "ExposureCompensation"=>"曝光补偿", "DateTimeOriginal" or "SubSecDateTimeOriginal"=>"拍摄时间", "DateTimeDigitized" or "SubSecCreateDate"=>"数字化时间", "CreateDate"=>"创建时间", "ModifyDate" or "SubSecModifyDate"=>"修改时间", "GPSLatitude"=>"纬度", "GPSLongitude"=>"经度", "GPSLatitudeRef"=>"纬度方向", "GPSLongitudeRef"=>"经度方向", "GPSDateStamp"=>"GPS日期", "GPSTimeStamp"=>"GPS时间", "DateCreated"=>"IPTC日期", "TimeCreated"=>"IPTC时间", "Title"=>"标题", "Rights" or "Copyright"=>"版权", "Creator" or "Artist"=>"作者", "Description"=>"说明", "Subject" or "Keywords"=>"关键词", _=>tag.Split(':')[^1]
    };
    public static bool Matches(string reference,string actual)
    {
        var parts=actual.Split(':');string family=parts[0], name=parts[^1];var wanted=reference.Split(':');
        if(wanted.Length!=2||wanted[1]!=name)return false;
        return wanted[0] switch { "EXIF"=>family is "IFD0" or "IFD1" or "ExifIFD" or "GPS" or "InteropIFD" or "EXIF", "XMP"=>family=="XMP"||family.StartsWith("XMP-",StringComparison.Ordinal), "File"=>family is "File" or "System", _=>wanted[0]==family };
    }
    public static InspectorValue[] Parse(JsonElement metadata,string role)
    {
        if(metadata.ValueKind!=JsonValueKind.Object)throw new InvalidDataException("完整来源返回格式无效。");
        var names=new HashSet<string>(StringComparer.Ordinal);var result=new List<InspectorValue>();
        foreach(var value in metadata.EnumerateObject()) {
            if(!names.Add(value.Name))throw new InvalidDataException("完整来源存在未区分的重复实例。");
            if(value.Name=="SourceFile")continue;
            if(value.Name=="Error"||value.Name.StartsWith("ExifTool:",StringComparison.Ordinal)&&value.Name.Split(':')[^1]=="Error")throw new InvalidDataException("完整来源读取失败。");
            result.Add(new(role,value.Name,PhotoDocument.Text(value.Value)));
        }
        return result.ToArray();
    }
    public static InspectorRow[] Rows(IReadOnlyList<PhotoDocument> docs,IReadOnlySet<string> common)
    {
        if(docs.Count==0)return [];
        var all=docs.SelectMany(d=>d.Inspection??[]).DistinctBy(v=>(v.Role,v.Tag)).ToArray();var rows=new List<InspectorRow>();var covered=new HashSet<(string,string)>();
        var fields=Standard.Concat(Configurable.Concat(common).Distinct(StringComparer.Ordinal).Where(t=>!Standard.Any(f=>f.Tag==t)).Select(t=>new InspectorField("附加字段",t)));
        foreach(var field in fields) {
            var keys=all.Where(v=>Matches(field.Tag,v.Tag)).Select(v=>(v.Role,v.Tag)).Distinct().ToArray();
            if(keys.Length==0){
                bool editable=docs.Count>0&&docs.All(d=>MetadataFields.CanEdit(d,field.Tag))&&!SavePlan.IsGps(field.Tag);
                bool draft=docs.Any(d=>d.Draft.ContainsKey(field.Tag));
                var current=docs.Select(d=>d.Value(field.Tag)).ToArray();
                string value=!draft?"":current.Distinct(StringComparer.Ordinal).Count()==1?current[0]:$"混合值（{current.Count(v=>v.Length>0)}/{docs.Count}有值）";
                string state=field.Tag=="File:MDItemUserTags"?"平台例外：Finder标签本体":docs.Any(d=>d.InspectionError.Length>0)?"读取失败／过期":docs.Any(d=>d.Inspection is null)?"未读":draft&&value.Length>0?(current.Distinct(StringComparer.Ordinal).Count()>1?"混合值":"已读"):"缺失";
                rows.Add(new(field.Section,field.Name,field.Tag,value,state,common.Contains(field.Tag),editable,editable?field.Tag:null){HasDraft=draft});continue;
            }
            foreach(var key in keys){if(!covered.Add(key))continue;Add(field.Section,field.Name,key.Role,key.Tag,common.Any(t=>Matches(t,key.Tag)));}
        }
        foreach(var key in all.Select(v=>(v.Role,v.Tag)).Distinct())if(covered.Add(key))Add("附加字段",Label(key.Tag),key.Role,key.Tag,common.Any(t=>Matches(t,key.Tag)));
        if(docs.Count==1)for(int i=0;i<rows.Count;i++)if(rows[i].Tag.Contains("IPTC:",StringComparison.Ordinal))rows[i]=rows[i] with{State=rows[i].State+"；"+(docs[0].Iptc?.ReadState??"原始IPTC来源未读取")};
        return rows.ToArray();
        void Add(string section,string name,string role,string tag,bool isCommon) {
            var values=docs.Select(d=>d.Inspection?.FirstOrDefault(v=>v.Role==role&&v.Tag==tag)?.Value).ToArray();var present=values.Where(v=>v is not null).ToArray();
            string state=docs.Any(d=>d.InspectionError.Length>0)?"过期快照／读取失败":docs.Any(d=>d.Inspection is null)?"未读":present.Length!=docs.Count||present.Distinct(StringComparer.Ordinal).Count()>1?"混合值":"已读";
            bool mixed=present.Length!=docs.Count||present.Distinct(StringComparer.Ordinal).Count()>1;
            string value=mixed?$"混合值（{present.Length}/{docs.Count}已读）":present.FirstOrDefault()??"";
            if(state=="已读"&&value.Length==0)state="空值";
            bool writable=docs.Count>0&&docs.All(d=>MetadataFields.CanEdit(d,tag)&&role==(d.SidecarPath is not null?"旁车XMP":d.FileType=="XMP"?"独立XMP":"原图"))&&tag.Split(':').Length==2&&PhotoDocument.EditableTags.Contains(tag)&&!tag.Contains(":GPS",StringComparison.Ordinal);
            bool TargetRole(PhotoDocument d)=>role==(d.SidecarPath is not null?"旁车XMP":d.FileType=="XMP"?"独立XMP":"原图");
            bool draft=docs.Any(d=>TargetRole(d)&&d.Draft.ContainsKey(tag));
            if(draft) {
                var current=docs.Select(d=>TargetRole(d)?d.Value(tag):d.Inspection?.FirstOrDefault(v=>v.Role==role&&v.Tag==tag)?.Value??"").ToArray();
                value=current.Distinct(StringComparer.Ordinal).Count()==1?current[0]:$"混合值（{current.Count(v=>v.Length>0)}/{docs.Count}有值）";
                if(!docs.Any(d=>d.InspectionError.Length>0))state=current.Distinct(StringComparer.Ordinal).Count()>1?"混合值":value.Length==0?"缺失":"已读";
            }
            rows.Add(new(section,name,role+" / "+tag,value,state,isCommon,writable,writable?tag:null){HasDraft=draft});
        }
    }
    public static int PendingFields(PhotoDocument doc)=>doc.Draft.Keys.Count(t=>!t.StartsWith("XMP-exif:GPS",StringComparison.Ordinal))+(doc.Draft.Keys.Any(t=>t.StartsWith("XMP-exif:GPS",StringComparison.Ordinal))?1:0);
    public static string Counts(IEnumerable<PhotoDocument> photos)
    {
        var docs=photos.ToArray();int known=docs.Count(d=>d.Inspection is not null),failed=docs.Count(d=>d.InspectionError.Length>0);
        string count=docs.Length==0?"0":known==0?"未知":docs.Where(d=>d.Inspection is not null).Sum(d=>d.Inspection!.Count(v=>v.Counted)).ToString();
        return $"{docs.Length}张；原标签{count}（已读{known}，未读{docs.Length-known}，失败/过期{failed}）；净草稿字段{docs.Sum(PendingFields)}";
    }
}
