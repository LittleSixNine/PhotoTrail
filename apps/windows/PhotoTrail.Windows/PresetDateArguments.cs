using System.Text.Json;
using System.Text.RegularExpressions;
using System.IO;
namespace PhotoTrail.Windows;

// Typed parameters use the existing date-page wire operations; no platform calendar is substituted.
public sealed record PresetDateArguments(long Years=0,long Months=0,long Days=0,long Hours=0,long Minutes=0,long Seconds=0,
    Dictionary<string,long>? Components=null,string Start="",string End="",string Pattern="",string Template="",string? Zone=null)
{
    public bool Equals(PresetDateArguments? other)=>other is not null&&Years==other.Years&&Months==other.Months&&Days==other.Days&&Hours==other.Hours&&Minutes==other.Minutes&&Seconds==other.Seconds&&Start==other.Start&&End==other.End&&Pattern==other.Pattern&&Template==other.Template&&Zone==other.Zone&&(Components is null?other.Components is null:other.Components is not null&&Components.Count==other.Components.Count&&Components.All(p=>other.Components.TryGetValue(p.Key,out var n)&&p.Value==n));
    public override int GetHashCode(){var h=new HashCode();h.Add(Years);h.Add(Months);h.Add(Days);h.Add(Hours);h.Add(Minutes);h.Add(Seconds);h.Add(Start);h.Add(End);h.Add(Pattern);h.Add(Template);h.Add(Zone);if(Components is not null)foreach(var p in Components.OrderBy(p=>p.Key,StringComparer.Ordinal)){h.Add(p.Key);h.Add(p.Value);}return h.ToHashCode();}
    internal static bool IsAction(string action)=>action is "offsetDate" or "dateComponent" or "sequence" or "distribute" or "filenameDate" or "shiftDate" or "calendarDays";
    internal DatePageOptions Options(string action,string target)=>action switch {
        "offsetDate"=>new(0,Years,Months,Days,Hours,Minutes,Seconds,Target:target),
        "sequence"=>new(1,Seconds:Seconds,Start:Start,Target:target),
        "dateComponent"=>new(2,Components:Components,Target:target),
        "distribute"=>new(3,Start:Start,End:End,Target:target),
        "filenameDate"=>new(4,Pattern:Pattern,Template:Template,Target:target),
        "shiftDate"=>new(5,Seconds:Seconds,Target:target),
        "calendarDays"=>new(6,Days:Days,Zone:Zone,Target:target),_=>throw new ArgumentException("日期动作未知。")
    };
    internal Dictionary<string,object?> Parameters(string action)=>action switch {
        "offsetDate"=>new(){{"years",Years},{"months",Months},{"days",Days},{"hours",Hours},{"minutes",Minutes},{"seconds",Seconds}},
        "dateComponent"=>new(){{"components",Components}},"sequence"=>new(){{"start",Start},{"seconds",Seconds}},
        "distribute"=>new(){{"start",Start},{"end",End}},"filenameDate"=>new(){{"pattern",Pattern},{"template",Template}},
        "shiftDate"=>new(){{"seconds",Seconds}},"calendarDays"=>new(){{"days",Days},{"zone",Zone}},_=>throw new ArgumentException("日期动作未知。")
    };
    internal static PresetDateArguments Decode(string action,JsonElement node) {
        var keys=new PresetDateArguments().Parameters(action).Keys;
        if(node.ValueKind!=JsonValueKind.Object||!node.EnumerateObject().Select(p=>p.Name).Order().SequenceEqual(keys.Order()))throw new ArgumentException("日期参数结构或重复属性无效。");
        long N(string key)=>node.GetProperty(key).TryGetInt64(out var value)?value:throw new ArgumentException("日期参数须为有符号宽整数。");
        string S(string key)=>node.GetProperty(key).ValueKind==JsonValueKind.String?node.GetProperty(key).GetString()!:throw new ArgumentException("日期参数文字无效。");
        return action switch {
            "offsetDate"=>new(N("years"),N("months"),N("days"),N("hours"),N("minutes"),N("seconds")),
            "dateComponent"=>new(Components:ComponentsOf(node.GetProperty("components"))),
            "sequence"=>new(Seconds:N("seconds"),Start:S("start")),"distribute"=>new(Start:S("start"),End:S("end")),
            "filenameDate"=>new(Pattern:S("pattern"),Template:S("template")),"shiftDate"=>new(Seconds:N("seconds")),
            "calendarDays"=>new(Days:N("days"),Zone:node.GetProperty("zone").ValueKind==JsonValueKind.Null?null:S("zone")),_=>throw new ArgumentException("日期动作未知。")
        };
    }
    static Dictionary<string,long> ComponentsOf(JsonElement node) {
        if(node.ValueKind!=JsonValueKind.Object)throw new ArgumentException("日期组件结构无效。");
        var result=new Dictionary<string,long>();foreach(var p in node.EnumerateObject())if(!p.Value.TryGetInt64(out var n)||!result.TryAdd(p.Name,n))throw new ArgumentException("日期组件整数或重复属性无效。");return result;
    }
    internal void Validate(string action,string target) {
        if(!VerifiedMetadataDates.IsDate(target)&&!MetadataTimes.IsSystem(target))throw new ArgumentException("完整日期动作不适用于此目标。");
        DatePagePreview.ValidateOptions(Options(action,target));
        // Reject unused typed members as well as unknown JSON properties.
        if(Decode(action,JsonSerializer.SerializeToElement(Parameters(action)))!=this && JsonSerializer.Serialize(Decode(action,JsonSerializer.SerializeToElement(Parameters(action))))!=JsonSerializer.Serialize(this))throw new ArgumentException("日期动作包含不适用参数。");
    }
    internal async Task<IReadOnlyList<Measurement>> ValidateAsync(string action,CancellationToken token) {
        if(action is not ("sequence" or "distribute" or "calendarDays"))return Array.Empty<Measurement>();
        var job=action switch {
            "sequence"=>new WireItem("parameters","sequence",Start,Seconds:Seconds,Count:1),
            "distribute"=>new WireItem("parameters","distribute",Start,Count:1,End:End),
            _=>new WireItem("parameters","calendarDays",Zone is null?"2024:01:01 00:00:00":"2024:01:01 00:00:00"+ZoneOffset(Zone),Days:0,Zone:Zone)
        };
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
        var results=await adapter.ComputeAsync([new(job)],0,()=>0,token);if(results[0].Error is {} e)throw new ArgumentException("共享日期参数拒绝："+e.Code);return adapter.Measurements.ToArray();
    }
    static string ZoneOffset(string zone) {
        var z=TimeZoneInfo.FindSystemTimeZoneById(zone);var offset=z.GetUtcOffset(new DateTime(2024,1,1,0,0,0,DateTimeKind.Utc));
        return (offset.Ticks<0?"-":"+")+offset.Duration().ToString(@"hh\:mm",System.Globalization.CultureInfo.InvariantCulture);
    }
}
