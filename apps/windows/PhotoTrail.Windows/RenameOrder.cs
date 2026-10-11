using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

namespace PhotoTrail.Windows;

// Windows adaptation of the fixed REN-01/02 contract; names still use the existing rule engine.
public sealed record RenameInput(string Path,IReadOnlyDictionary<string,string> Tags,bool MetadataFailed=false,long? Size=null,string Hash="",System.Text.Json.JsonElement? Metadata=null)
{
    public string Name=>System.IO.Path.GetFileName(Path);
    public string Directory=>System.IO.Path.GetDirectoryName(Path)!;
    public string Extension=>System.IO.Path.GetExtension(Path).TrimStart('.').ToLowerInvariant();
    public string? Tag(string token) {
        if(Tags.TryGetValue(token,out var exact)&&exact.Length>0)return exact;
        string? preferred=token switch{"IPTCCity"=>"XMP-photoshop:City",_=>null};
        if(preferred is not null&&Tags.TryGetValue(preferred,out var region)&&region.Length>0)return region;
        var candidates=token switch{"CameraMake"=>new[]{"Make"},"CameraModel"=>new[]{"Model"},"IPTCCity"=>new[]{"City"},_=>new[]{token}};
        foreach(var candidate in candidates){var key=Tags.Keys.Where(k=>k.Split(':').Last()==candidate).Order(StringComparer.Ordinal).FirstOrDefault();if(key is not null&&Tags[key].Length>0)return Tags[key];}
        return token switch{"FileName"=>Name,"FileNameWithoutExtension"=>System.IO.Path.GetFileNameWithoutExtension(Path),"FileExtension"=>Extension,"ParentFolderName"=>System.IO.Path.GetFileName(Directory),"FilePath"=>Path,_=>null};
    }
    public static double? Date(string? raw) {
        if(string.IsNullOrWhiteSpace(raw))return null;
        if(raw.Length>=19)raw=raw[..10].Replace('-',':')+raw[10..].Replace('T',' ');
        if(raw.Length>=24&&raw[^5] is '+' or '-'&&raw[^3]!=':')raw=raw.Insert(raw.Length-2,":");
        int offset=0;if(raw.EndsWith('Z'))raw=raw[..^1];else if(raw.Length>=25&&raw[^6] is '+' or '-'){
            if(raw[^3]!=':'||!int.TryParse(raw.AsSpan(raw.Length-5,2),NumberStyles.None,CultureInfo.InvariantCulture,out var hours)||!int.TryParse(raw.AsSpan(raw.Length-2,2),NumberStyles.None,CultureInfo.InvariantCulture,out var minutes)||hours>23||minutes>59)return null;
            // Rename comparison uses a neutral epoch; it does not widen the metadata editor's offset policy.
            offset=(raw[^6]=='-'?-1:1)*(hours*3600+minutes*60);raw=raw[..^6];
        }
        try{var d=MetadataDate.Parse(raw);return (d.WallTime.Ticks-DateTime.UnixEpoch.Ticks)/(double)TimeSpan.TicksPerSecond+(d.Fraction.Length>0?double.Parse("0"+d.Fraction,CultureInfo.InvariantCulture):0)-offset;}
        catch(ArgumentException){return null;}
    }
    public double? Shooting {
        get{foreach(var key in new[]{"Composite:SubSecDateTimeOriginal","Composite:DateTimeOriginal","ExifIFD:DateTimeOriginal","XMP-exif:DateTimeOriginal","ExifIFD:CreateDate","QuickTime:CreationDate","QuickTime:DateTimeOriginal","QuickTime:ContentCreateDate","QuickTime:CreateDate","QuickTime:MediaCreateDate","ID3:Date","XMP-xmp:CreateDate"}){
            var raw=Tag(key);if(raw is null)continue;var offset=Tag(key.EndsWith(":CreateDate",StringComparison.Ordinal)?"OffsetTimeDigitized":"OffsetTimeOriginal");
            if(raw.Length>=19&&!raw.Contains('Z')&&raw.IndexOf('+',19)<0&&raw.IndexOf('-',19)<0&&offset is not null)raw+=offset;
            var value=Date(raw);if(value is null)continue;if(!raw.Contains('.')&&double.TryParse("0."+Tag(key.EndsWith(":CreateDate",StringComparison.Ordinal)?"SubSecTimeDigitized":"SubSecTimeOriginal"),CultureInfo.InvariantCulture,out var fraction)&&fraction is >=0 and <1)value+=fraction;return value;
        }return null;}
    }
}
public sealed record RenameGroup(string Id,IReadOnlyList<RenameInput> Members)
{
    public static readonly string[] Sources=["jpg","jpeg","heic","cr3","cr2","nef","arw","dng","raf"];
    public static readonly string[] Targets=["xmp","aae","thm"];
    public RenameInput Leader=>Members.OrderBy(m=>Array.IndexOf(Sources,m.Extension) is var n&&n>=0?n:int.MaxValue).First();
    public string Name=>Leader.Name;
    public string Identity=>Id;
    public string Status=>Members.Any(m=>m.MetadataFailed)?"元数据读取失败；不可冻结":"处理预览";
    public static string Key(string path)=>Sources.Concat(Targets).Contains(System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant())?System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path)!,System.IO.Path.GetFileNameWithoutExtension(path)).Normalize().ToLowerInvariant():System.IO.Path.GetFullPath(path).ToLowerInvariant();
}
public sealed record RenameOrderSettings(string Sort="input",bool Descending=false,string? MetadataSortTag=null)
{
    public static readonly string[] Sorts=["input","name","natural","shooting","created","modified","fileExtension","folder","size","make","model","city","rating","metadata","manual"];
    public void Validate(){if(!Sorts.Contains(Sort)||MetadataSortTag?.Length>256||MetadataSortTag?.Any(char.IsControl)==true)throw new ArgumentException("排序设置无效。");}
}
public sealed record RenameInputFilter(string Query="",string Extension="",string Folder="",string Camera="",double? From=null,double? To=null,int Gps=0,string Tag="",int Presence=0)
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
        string? Value(RenameGroup g){var m=g.Leader;return settings.Sort switch{"name" or "natural"=>m.Name,"fileExtension"=>m.Extension,"folder"=>m.Directory,"size"=>m.Size?.ToString(CultureInfo.InvariantCulture),"created"=>m.Tag("File:FileCreateDate") is var c?RenameInput.Date(c)?.ToString("R",CultureInfo.InvariantCulture):null,"modified"=>RenameInput.Date(m.Tag("File:FileModifyDate"))?.ToString("R",CultureInfo.InvariantCulture),"shooting"=>m.MetadataFailed?null:m.Shooting?.ToString("R",CultureInfo.InvariantCulture),"make"=>m.Tag("CameraMake"),"model"=>m.Tag("CameraModel"),"city"=>m.Tag("IPTCCity"),"rating"=>m.Tag("XMP-xmp:Rating"),"metadata"=>m.Tag(settings.MetadataSortTag??"") is var v?(RenameInput.Date(v)?.ToString("R",CultureInfo.InvariantCulture)??v):null,_=>null};}
        var indexed=inputs.Select((g,i)=>(g,i,v:Value(g))).ToArray();Array.Sort(indexed,(a,b)=>{
            bool am=string.IsNullOrWhiteSpace(a.v),bm=string.IsNullOrWhiteSpace(b.v);if(am||bm)return am&&bm?a.i.CompareTo(b.i):am?1:-1;
            int compare;bool numeric=settings.Sort is "created" or "modified" or "shooting" or "size" or "rating" or "metadata";
            bool an=double.TryParse(a.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var av)&&double.IsFinite(av),bn=double.TryParse(b.v,NumberStyles.Float,CultureInfo.InvariantCulture,out var bv)&&double.IsFinite(bv);
            if(numeric&&(an||bn))compare=an&&bn?av.CompareTo(bv):an?-1:1;else compare=settings.Sort=="natural"?Math.Sign(StrCmpLogicalW(a.v!,b.v!)):StringComparer.Ordinal.Compare(a.v,b.v);
            return compare==0?a.i.CompareTo(b.i):settings.Descending?-compare:compare;
        });return indexed.Select(v=>v.g).ToArray();
    }
    public static string[] Move(IReadOnlySet<string> moving,string target,IReadOnlyList<string> visible,IReadOnlyList<string> full){
        if(moving.Count==0||moving.Contains(target)||(target.Length>0&&!visible.Contains(target))||moving.Any(m=>!visible.Contains(m)))return full.ToArray();
        var block=visible.Where(moving.Contains).ToArray();var next=visible.Where(v=>!moving.Contains(v)).ToList();var index=target.Length==0?next.Count:next.IndexOf(target);next.InsertRange(index,block);var set=visible.ToHashSet();int n=0;return full.Select(id=>set.Contains(id)?next[n++]:id).ToArray();
    }
}
