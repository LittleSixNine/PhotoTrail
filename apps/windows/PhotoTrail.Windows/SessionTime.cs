using System.Globalization;

namespace PhotoTrail.Windows;

// The fixed shared host validates date text; this adapter only projects a validated wall clock into a session zone.
internal static class SessionTime
{
    internal static string InitialZone=TimeZoneInfo.Local.Id;
    internal static DateTimeOffset? Instant(VerifiedPhotoDate? date,string zoneId,out string reason){
        reason="";if(date is null){reason="非法主时间";return null;}
        if(date.Offset.Length>0){reason=date.InstantLimitation??"";return reason.Length==0?date.Instant():null;}
        if(date.Projection.Nanoseconds%100!=0){reason="精度不足";return null;}
        try{
            var zone=TimeZoneInfo.FindSystemTimeZoneById(zoneId);
            if(!DateTime.TryParseExact(date.Text[..19],"yyyy:MM:dd HH:mm:ss",CultureInfo.InvariantCulture,DateTimeStyles.None,out var parsed)){reason="平台范围不足";return null;}
            var wall=DateTime.SpecifyKind(parsed.AddTicks(date.Projection.Nanoseconds/100),DateTimeKind.Unspecified);
            if(zone.IsInvalidTime(wall)){reason="会话时区中不存在的时间";return null;}
            if(zone.IsAmbiguousTime(wall)){reason="会话时区中重复的时间";return null;}
            return new DateTimeOffset(wall,zone.GetUtcOffset(wall)).ToUniversalTime();
        }catch(Exception error)when(error is TimeZoneNotFoundException or InvalidTimeZoneException or ArgumentException or OverflowException){reason="会话时区或平台范围无效";return null;}
    }
}

internal sealed record DraftContext(string[] MapFields,bool ClearLocation);
