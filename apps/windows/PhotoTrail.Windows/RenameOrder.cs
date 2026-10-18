using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace PhotoTrail.Windows;

// Windows adaptation of the fixed REN-01/02 contract; names still use the existing rule engine.
public sealed record RenameInput(string Path,IReadOnlyDictionary<string,string> Tags,bool MetadataFailed=false,long? Size=null,string Hash="",System.Text.Json.JsonElement? Metadata=null)
{
    public string Name=>System.IO.Path.GetFileName(Path);
    public string Directory=>System.IO.Path.GetDirectoryName(Path)!;
    public string Extension=>System.IO.Path.GetExtension(Path).TrimStart('.').ToLowerInvariant();
    public string? Tag(string token) {
        if(Tags.TryGetValue(token,out var exact)&&exact.Length>0)return exact;
        string? preferred=token switch{"IPTCCity"=>"XMP-photoshop:City","IPTCProvinceState"=>"XMP-photoshop:State","IPTCSubLocation"=>"XMP-iptcCore:Location","IPTCCountry"=>"XMP-photoshop:Country",_=>null};
        if(preferred is not null&&Tags.TryGetValue(preferred,out var region)&&region.Length>0)return region;
        if(token.Contains(':'))return null;
        var candidates=token switch{"CameraMake"=>new[]{"Make"},"CameraModel"=>new[]{"Model"},"CameraSerialNumber"=>new[]{"SerialNumber"},"IPTCCity"=>new[]{"City"},"IPTCProvinceState"=>new[]{"Province-State","State"},"IPTCSubLocation"=>new[]{"Sub-location","Location"},"IPTCCountry"=>new[]{"Country-PrimaryLocationName","Country"},"ImageCaption"=>new[]{"Caption-Abstract","Description","ImageDescription"},"ImageKeywords"=>new[]{"Keywords","Subject"},"ImageUserComment"=>new[]{"UserComment"},"Lens"=>new[]{"LensModel","LensID","Lens"},"Aperture"=>new[]{"FNumber","Aperture"},"ShutterSpeed"=>new[]{"ExposureTime","ShutterSpeed"},"FocalLength35mm"=>new[]{"FocalLengthIn35mmFormat"},"width" or "ImageWidth"=>new[]{"ImageWidth","ExifImageWidth"},"height" or "ImageHeight"=>new[]{"ImageHeight","ExifImageHeight"},_=>new[]{token}};
        foreach(var candidate in candidates){var key=Tags.Keys.Where(k=>k.Split(':').Last()==candidate).Order(StringComparer.Ordinal).FirstOrDefault();if(key is not null&&Tags[key].Length>0)return Tags[key];}
        if(token.StartsWith('0')&&long.TryParse(Tag(token[1..]),NumberStyles.Integer,CultureInfo.InvariantCulture,out var number))return number.ToString("D2",CultureInfo.InvariantCulture);
        return token switch{"FileName"=>Name,"FileNameWithoutExtension"=>RenameTransform.Split(Name).Stem,"FileExtension"=>RenameTransform.Split(Name).Extension.TrimStart('.'),"ParentFolderName"=>System.IO.Path.GetFileName(Directory),"FilePath"=>Path,"NULL"=>"",_=>null};
    }
    internal IReadOnlyDictionary<string,VerifiedPhotoDate?> DateResults {get;init;}=new Dictionary<string,VerifiedPhotoDate?>();
    internal static string BridgeDate(string raw) {
        raw=VerifiedPhotoDate.Bridge(raw);
        if(raw.Length>=24&&raw[^5] is '+' or '-'&&raw[^3]!=':')raw=raw.Insert(raw.Length-2,":");return raw;
    }
    internal static decimal? Date(string? raw,IReadOnlyDictionary<string,VerifiedPhotoDate?> results) {
        if(raw is null)return null;var date=results.GetValueOrDefault(BridgeDate(raw));
        if(date?.SortProjection is not {} projected)return null;
        return projected.Seconds+projected.Nanoseconds/1_000_000_000m;
    }
    // System file times are a different domain and never authorize metadata writes.
    public static decimal? SystemDate(string? raw) {
        if(raw is null||!DateTimeOffset.TryParse(raw,CultureInfo.InvariantCulture,DateTimeStyles.None,out var time))return null;
        return (time.UtcTicks-DateTime.UnixEpoch.Ticks)/(decimal)TimeSpan.TicksPerSecond;
    }
    internal string DatePriority {get;init;}=RenameOrderSettings.DefaultDatePriority;
    internal bool CaptureKnown {get;init;}
    internal string? MainCapture {get;init;}
    internal IEnumerable<string> ShootingTexts() {
        if(CaptureKnown){if(MainCapture is not null)yield return BridgeDate(MainCapture);yield break;}
        foreach(var key in DatePriority.Replace("\r\n","\n").Split('\n',StringSplitOptions.RemoveEmptyEntries)) {
            var raw=Tag(key);if(raw is null)continue;bool digitized=key.EndsWith(":CreateDate",StringComparison.Ordinal);
            var fraction=Tag(digitized?"SubSecTimeDigitized":"SubSecTimeOriginal");var offset=Tag(digitized?"OffsetTimeDigitized":"OffsetTimeOriginal");
            if(raw.Length>=19&&!raw.Contains('.')) {if(fraction is not null)raw=raw[..19]+"."+fraction+raw[19..];}
            if(raw.Length>=19&&!raw.Contains('Z')&&raw.IndexOf('+',19)<0&&raw.IndexOf('-',19)<0&&offset is not null)raw+=offset;
            yield return BridgeDate(raw);
        }
    }
    public decimal? Shooting {get {foreach(var text in ShootingTexts()){if(DateResults.TryGetValue(text,out var valid)&&valid is not null)return Date(text,DateResults);}return null;}}

}
public sealed record RenameGroup(string Id,IReadOnlyList<RenameInput> Members)
{
    public static readonly string[] Sources=["jpg","jpeg","heic","cr3","cr2","nef","arw","dng","raf"];
    public static readonly string[] Targets=["xmp","aae","thm"];
    public RenameOrderSettings Settings {get;init;}=new();
    public RenameInput Leader=>Members.OrderBy(m=>Array.IndexOf(Settings.SourceList,m.Extension) is var n&&n>=0?n:int.MaxValue).First();
    public string Name=>Leader.Name;
    public static string Key(string path,RenameOrderSettings settings)=>settings.Pair&&settings.SourceList.Concat(settings.TargetList).Contains(System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant())?System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path)!,RenameTransform.Split(System.IO.Path.GetFileName(path)).Stem).ToLowerInvariant():System.IO.Path.GetFullPath(path).ToLowerInvariant();
    public string Identity=>Id;
    public string Status=>Members.Any(m=>m.MetadataFailed)?"元数据读取失败；不可冻结":"处理预览";
    public static string Key(string path)=>Sources.Concat(Targets).Contains(System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant())?System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path)!,RenameTransform.Split(System.IO.Path.GetFileName(path)).Stem).ToLowerInvariant():System.IO.Path.GetFullPath(path).ToLowerInvariant();
}
public sealed record RenameOrderSettings(string Sort="input",bool Descending=false,string? MetadataSortTag=null)
{
    public bool Pair {get;init;}=true;
    public string SourceExtensions {get;init;}="jpg,jpeg,heic,cr3,cr2,nef,arw,dng,raf";
    public string TargetExtensions {get;init;}="xmp,aae,thm";
    public const string DefaultDatePriority="Composite:SubSecDateTimeOriginal\nComposite:DateTimeOriginal\nExifIFD:DateTimeOriginal\nXMP-exif:DateTimeOriginal\nExifIFD:CreateDate\nQuickTime:CreationDate\nQuickTime:DateTimeOriginal\nQuickTime:ContentCreateDate\nQuickTime:CreateDate\nQuickTime:MediaCreateDate\nID3:Date\nXMP-xmp:CreateDate";
    public string DatePriority {get;init;}=DefaultDatePriority;
    [System.Text.Json.Serialization.JsonIgnore] public string[] SourceList=>Extensions(SourceExtensions);
    [System.Text.Json.Serialization.JsonIgnore] public string[] TargetList=>Extensions(TargetExtensions);
    static string[] Extensions(string value)=>value.Split(',',StringSplitOptions.RemoveEmptyEntries).Select(e=>e.Trim().ToLowerInvariant()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    internal void ValidateInputs(){
        if(SourceExtensions is null||TargetExtensions is null||DatePriority is null||SourceExtensions.Length>1024||TargetExtensions.Length>1024||DatePriority.Length>8192)throw new ArgumentException("配对或日期来源设置缺失／过长。");
        foreach(var list in new[]{SourceList,TargetList})if(list.Length>64||list.Any(e=>e.Length is <1 or >16||e.Any(c=>!char.IsAsciiLetterOrDigit(c)))||list.Distinct(StringComparer.OrdinalIgnoreCase).Count()!=list.Length)throw new ArgumentException("扩展名须为不带点的非空字母数字、逗号分隔且不重复。");
        var priorities=DatePriority.Replace("\r\n","\n").Split('\n',StringSplitOptions.RemoveEmptyEntries);
        if(priorities.Length>64||priorities.Any(p=>p!=p.Trim()||p.Length>256||p.Any(char.IsControl))||priorities.Distinct(StringComparer.Ordinal).Count()!=priorities.Length)throw new ArgumentException("日期来源须为每行一个非空且不重复的精确标签。");
    }
    public string Conflict { get; init; } = "stop";
    public int ConflictDigits { get; init; } = 3;
    public string NumberSuffixFormat { get; init; } = "underscore";
    public string LetterSuffixFormat { get; init; } = "plain";
    public bool KeepFirst { get; init; } = true;
    public static readonly string[] Sorts=["input","name","natural","shooting","created","modified","fileExtension","folder","size","make","model","city","rating","metadata","manual"];
    public void Validate(){ValidateInputs();if(!Sorts.Contains(Sort)||MetadataSortTag?.Length>256||MetadataSortTag?.Any(char.IsControl)==true||Conflict is not("stop" or "numbers" or "letters")||ConflictDigits is <2 or >5||NumberSuffixFormat is not("plain" or "underscore" or "dash" or "parentheses")||LetterSuffixFormat is not("plain" or "underscore" or "dash" or "parentheses"))throw new ArgumentException("排序或碰撞参数无效。");}
}
public sealed record RenameInputFilter(string Query="",string Extension="",string Folder="",string Camera="",decimal? From=null,decimal? To=null,int Gps=0,string Tag="",int Presence=0)
{
    public bool NeedsTags=>Camera.Length>0||From is not null||To is not null||Gps!=0||Tag.Length>0;
    public bool Matches(RenameInput input){
        bool Contains(string value,string needle)=>needle.Length==0||value.Contains(needle,StringComparison.CurrentCultureIgnoreCase);
        if(!Contains(input.Path,Query)||(Extension.Length>0&&!input.Extension.Equals(Extension.Trim('.',' '),StringComparison.OrdinalIgnoreCase))||!Contains(input.Directory,Folder)||(NeedsTags&&input.MetadataFailed))return false;
        if(!Contains((input.Tag("CameraMake")??"")+" "+(input.Tag("CameraModel")??""),Camera))return false;
        if(From is not null||To is not null){var date=input.Shooting;if(date is null||From is not null&&date<From||To is not null&&date>To)return false;}
        var located=input.Tag("GPSLatitude")is not null&&input.Tag("GPSLongitude")is not null;if(Gps!=0&&located!=(Gps==1))return false;
        return Tag.Length==0||Presence==0||!string.IsNullOrWhiteSpace(input.Tag(Tag))==(Presence==1);
    }
}
public static class RenameOrder
{
    [DllImport("shlwapi.dll",CharSet=CharSet.Unicode,ExactSpelling=true)]static extern int StrCmpLogicalW(string a,string b);
    public static RenameGroup[] Ordered(IEnumerable<RenameGroup> groups,RenameOrderSettings settings){
        settings.Validate();var inputs=groups.ToArray();if(settings.Sort is "input" or "manual")return settings.Descending&&settings.Sort!="manual"?inputs.Reverse().ToArray():inputs;
        string? Value(RenameGroup g){var m=g.Leader;return settings.Sort switch{"name" or "natural"=>m.Name,"fileExtension"=>m.Extension,"folder"=>m.Directory,"size"=>m.Size?.ToString(CultureInfo.InvariantCulture),"created"=>m.Tag("File:FileCreateDate") is var c?RenameInput.SystemDate(c)?.ToString(CultureInfo.InvariantCulture):null,"modified"=>RenameInput.SystemDate(m.Tag("File:FileModifyDate"))?.ToString(CultureInfo.InvariantCulture),"shooting"=>m.MetadataFailed?null:m.Shooting?.ToString(CultureInfo.InvariantCulture),"make"=>m.Tag("CameraMake"),"model"=>m.Tag("CameraModel"),"city"=>m.Tag("IPTCCity"),"rating"=>m.Tag("XMP-xmp:Rating"),"metadata"=>m.Tag(settings.MetadataSortTag??"") is var v?(RenameInput.Date(v,m.DateResults)?.ToString(CultureInfo.InvariantCulture)??v):null,_=>null};}
        // shortcut: canonical ordinal matches the supplied Mac name vector; broader Foundation ordering still needs Mac vectors.
        var indexed=inputs.Select((g,i)=>(g,i,v:settings.Sort=="name"?Value(g)?.Normalize(NormalizationForm.FormC):Value(g))).ToArray();Array.Sort(indexed,(a,b)=>{
            bool am=string.IsNullOrWhiteSpace(a.v),bm=string.IsNullOrWhiteSpace(b.v);if(am||bm)return am&&bm?a.i.CompareTo(b.i):am?1:-1;
            int compare;bool numeric=settings.Sort is "created" or "modified" or "shooting" or "size" or "rating" or "metadata";
            bool an=double.TryParse(a.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var av)&&double.IsFinite(av),bn=double.TryParse(b.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var bv)&&double.IsFinite(bv);
            bool dateOrder=settings.Sort is "created" or "modified" or "shooting" || settings.Sort=="metadata"&&(a.g.Leader.DateResults.GetValueOrDefault(RenameInput.BridgeDate(a.g.Leader.Tag(settings.MetadataSortTag??"")??"")) is not null||b.g.Leader.DateResults.GetValueOrDefault(RenameInput.BridgeDate(b.g.Leader.Tag(settings.MetadataSortTag??"")??"")) is not null);
            if(dateOrder&&decimal.TryParse(a.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var ad)&&decimal.TryParse(b.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var bd))compare=ad.CompareTo(bd);
            else if(numeric&&(an||bn))compare=an&&bn?av.CompareTo(bv):an?-1:1;else compare=settings.Sort=="natural"?Math.Sign(StrCmpLogicalW(a.v!,b.v!)):StringComparer.Ordinal.Compare(a.v,b.v);
            return compare==0?a.i.CompareTo(b.i):settings.Descending?-compare:compare;
        });return indexed.Select(v=>v.g).ToArray();
    }
    public static string[] Move(IReadOnlySet<string> moving,string target,IReadOnlyList<string> visible,IReadOnlyList<string> full){
        if(moving.Count==0||moving.Contains(target)||(target.Length>0&&!visible.Contains(target))||moving.Any(m=>!visible.Contains(m)))return full.ToArray();
        var block=visible.Where(moving.Contains).ToArray();var next=visible.Where(v=>!moving.Contains(v)).ToList();var index=target.Length==0?next.Count:next.IndexOf(target);next.InsertRange(index,block);var set=visible.ToHashSet();int n=0;return full.Select(id=>set.Contains(id)?next[n++]:id).ToArray();
    }
}
