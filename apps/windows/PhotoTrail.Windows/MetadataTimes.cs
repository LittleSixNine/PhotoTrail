using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace PhotoTrail.Windows;

internal sealed record SourceTimes(DateTime Created,DateTime Written)
{
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileTime(SafeFileHandle file,out System.Runtime.InteropServices.ComTypes.FILETIME created,out System.Runtime.InteropServices.ComTypes.FILETIME accessed,out System.Runtime.InteropServices.ComTypes.FILETIME written);
    internal static DateTime FromFileTime(System.Runtime.InteropServices.ComTypes.FILETIME value)=>DateTime.FromFileTimeUtc(((long)(uint)value.dwHighDateTime<<32)|(uint)value.dwLowDateTime);
    internal static SourceTimes Read(string path) {
        // File.Get*TimeUtc converts through local DateTimeOffset and overflows near year 9999 on positive offsets.
        using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        if(!GetFileTime(file.SafeFileHandle,out var created,out _,out var written))throw new IOException("文件属性不可读取；Win32="+Marshal.GetLastWin32Error());
        return new(FromFileTime(created),FromFileTime(written));
    }
    internal string Value(string tag)=>Text(tag=="System:FileCreateDate"?Created:Written);
    internal static string Text(DateTime value)=>value.ToString("yyyy:MM:dd HH:mm:ss.fffffff",CultureInfo.InvariantCulture)+"+00:00";
}
internal static class MetadataTimes
{
    internal static readonly string[] Fields=["System:FileCreateDate","System:FileModifyDate"];
    internal static bool IsSystem(string tag)=>Fields.Contains(tag);
    internal static bool IsPartial(string tag)=>tag is "IPTC:DateCreated" or "IPTC:TimeCreated";
    internal static string Zone {get{TimeZoneInfo.ClearCachedData();return TimeZoneInfo.Local.ToSerializedString();}}
    static readonly Regex Full=new(@"^(\d{4}:\d{2}:\d{2}) (\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})?$",RegexOptions.CultureInvariant);
    static DateTime Wall(string text,string format) {
        if(!DateTime.TryParseExact(text,format,CultureInfo.InvariantCulture,DateTimeStyles.None,out var value)||value.ToString(format,CultureInfo.InvariantCulture)!=text)throw new ArgumentException("日期／时间分量不是严格公历有效值。");
        return DateTime.SpecifyKind(value,DateTimeKind.Unspecified);
    }
    static TimeSpan Offset(string text) {
        if(text=="Z")return TimeSpan.Zero;
        if(!Regex.IsMatch(text,@"^[+-]\d{2}:\d{2}$")||int.Parse(text.AsSpan(1,2))>23||int.Parse(text.AsSpan(4,2))>59)throw new ArgumentException("时间须有合法明确偏移。");
        return TimeSpan.FromMinutes((int.Parse(text.AsSpan(1,2))*60+int.Parse(text.AsSpan(4,2)))*(text[0]=='-'?-1:1));
    }
    internal static string Partial(string tag,string text) {
        var full=Full.Match(text);
        if(full.Success){Wall(full.Groups[1].Value+" "+full.Groups[2].Value,"yyyy:MM:dd HH:mm:ss");if(full.Groups[4].Success)_=Offset(full.Groups[4].Value);text=tag=="IPTC:DateCreated"?full.Groups[1].Value:full.Groups[2].Value+full.Groups[4].Value;}
        if(tag=="IPTC:DateCreated"){Wall(text,"yyyy:MM:dd");return text;}
        var time=Regex.Match(text,@"^(\d{2}:\d{2}:\d{2})(Z|[+-]\d{2}:\d{2})$");
        if(!time.Success)throw new ArgumentException("IPTC时间须为HH:mm:ss加明确偏移。");
        Wall(time.Groups[1].Value,"HH:mm:ss");_=Offset(time.Groups[2].Value);
        return time.Groups[1].Value+(time.Groups[2].Value=="Z"?"+00:00":time.Groups[2].Value);
    }
    internal static DateTime Parse(string text,TimeZoneInfo? zone=null) {
        var m=Full.Match(text);if(!m.Success)throw new ArgumentException("文件时间须为完整日期时间，可含1—9位亚秒及偏移。");
        var wall=Wall(m.Groups[1].Value+" "+m.Groups[2].Value,"yyyy:MM:dd HH:mm:ss");
        var fraction=m.Groups[3].Value.PadRight(9,'0');
        if(fraction.AsSpan(7).IndexOfAnyExcept('0')>=0)throw new ArgumentException("Windows文件时间精度100ns；不能无损表达的亚秒拒绝，不舍入。");
        wall=wall.AddTicks(long.Parse(fraction.AsSpan(0,7),CultureInfo.InvariantCulture));
        DateTime utc;
        if(m.Groups[4].Success)utc=new DateTime(checked(wall.Ticks-Offset(m.Groups[4].Value).Ticks),DateTimeKind.Utc);
        else {zone??=TimeZoneInfo.Local;if(zone.IsInvalidTime(wall)||zone.IsAmbiguousTime(wall))throw new ArgumentException("本机时区的DST时间无效或不唯一；请明确偏移。");utc=new DateTime(checked(wall.Ticks-zone.GetUtcOffset(wall).Ticks),DateTimeKind.Utc);}
        if(utc.Year<1601)throw new ArgumentException("Windows文件API时间下界为1601-01-01 UTC。");
        if(utc.ToFileTimeUtc()==0)throw new ArgumentException("FILETIME零值表示保持原属性，不能作为可核验设置；最小设置值为1601-01-01 UTC加100ns。");return utc;
    }
    internal static string Normalize(string tag,string text)=>IsSystem(tag)?SourceTimes.Text(Parse(text)):IsPartial(tag)&&text.Length>0?Partial(tag,text):text;
    internal static void Validate(string tag,string text){if(IsSystem(tag)){if(text.Length==0)throw new ArgumentException("文件创建／修改时间不可清除。");_=Parse(text);}else if(IsPartial(tag)&&text.Length>0)_=Partial(tag,text);}
    internal static FileProperties Requested(FileProperties source,IReadOnlyDictionary<string,string> fields)=>source with{Created=fields.TryGetValue(Fields[0],out var c)?Parse(c):source.Created,Written=fields.TryGetValue(Fields[1],out var w)?Parse(w):source.Written};
    internal static void Apply(string path,IReadOnlyDictionary<string,string> fields,SourceTimes source) {
        File.SetCreationTimeUtc(path,fields.TryGetValue(Fields[0],out var c)?Parse(c):source.Created);
        File.SetLastWriteTimeUtc(path,fields.TryGetValue(Fields[1],out var w)?Parse(w):source.Written);
        Require(path,fields,source);
    }
    internal static void Require(string path,IReadOnlyDictionary<string,string> fields,SourceTimes source) {
        var actual=SourceTimes.Read(path);var expected=new SourceTimes(fields.TryGetValue(Fields[0],out var c)?Parse(c):source.Created,fields.TryGetValue(Fields[1],out var w)?Parse(w):source.Written);
        if(actual!=expected)throw new IOException("文件系统时间独立回读未无损匹配；保留事务材料。");
    }
}
