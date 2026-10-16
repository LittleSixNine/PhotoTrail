using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

public sealed record UiPreference(int Version=1,string Language="",int StartupWorkspace=-1,int LastWorkspace=0,int CoordinateFormat=0,bool HideUneditable=false,string CameraTimeZone="",string TrackColor="#1477d4",double TrackWidth=4,double MatchGapMinutes=120,decimal PhotoGpxGapSeconds=300,int BackupReminderDays=7,bool SetupCompleted=false)
{
    public static string PathForSettings(string file)=>Path.Combine(Path.GetDirectoryName(Path.GetFullPath(file))!,"ui-v1.json");
    static readonly JsonSerializerOptions Json=new(){UnmappedMemberHandling=JsonUnmappedMemberHandling.Disallow};
    internal void Validate(){
        if(Version!=1||Language is not("" or "zh-Hans" or "en" or "zh-Hant" or "ja" or "ko" or "es" or "pt-BR")||StartupWorkspace is <-1 or >2||LastWorkspace is <0 or >2||CoordinateFormat is <0 or >2||!Regex.IsMatch(TrackColor,"\\A#[0-9A-Fa-f]{6}\\z")||!double.IsFinite(TrackWidth)||TrackWidth is <0 or >1000||!double.IsFinite(MatchGapMinutes)||MatchGapMinutes is <=0 or >1000000||PhotoGpxGapSeconds is <=0 or >60000000||decimal.Truncate(PhotoGpxGapSeconds*TimeSpan.TicksPerSecond)!=PhotoGpxGapSeconds*TimeSpan.TicksPerSecond||BackupReminderDays is not(0 or 7 or 30 or 90))throw new InvalidDataException("应用设置结构或范围无效；原文件保留。");
        if(CameraTimeZone.Length>128)throw new InvalidDataException("相机时区无效。");
        if(CameraTimeZone.Length>0)_=TimeZoneInfo.FindSystemTimeZoneById(CameraTimeZone);
    }
    public static UiPreference Read(string file){
        if(!File.Exists(file))return new();
        if((File.GetAttributes(file)&(FileAttributes.ReadOnly|FileAttributes.ReparsePoint))!=0)throw new IOException("应用设置只读或链接，未覆盖。");
        using var document=SettingsPreference.ReadJson(file);
        if(document.RootElement.ValueKind!=JsonValueKind.Object||!document.RootElement.TryGetProperty("Version",out var version)||!version.TryGetInt32(out var v)||v!=1||document.RootElement.EnumerateObject().Select(p=>p.Name).Distinct(StringComparer.Ordinal).Count()!=document.RootElement.EnumerateObject().Count())throw new InvalidDataException("应用设置版本或重复字段无效；原文件保留。");
        var value=document.Deserialize<UiPreference>(Json)??throw new InvalidDataException("应用设置为空。");value.Validate();return value;
    }
    public static void Save(string file,UiPreference value){value.Validate();_=Read(file);SettingsPreference.WriteJson(file,value);}
}
