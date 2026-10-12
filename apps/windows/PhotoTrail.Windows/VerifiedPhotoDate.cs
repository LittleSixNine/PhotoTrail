using System.Globalization;
using System.IO;
namespace PhotoTrail.Windows;

// Only a pinned host result authorizes text extraction. Native time projection is a separate, fallible adapter.
internal sealed record VerifiedPhotoDate
{
    internal string Text { get; }
    internal string Fraction { get; }
    internal string Offset { get; }
    internal DateTime? WallProjection { get; }
    internal string NameSeconds=>Text[..19].Replace(":","").Replace(" ","_");
    private VerifiedPhotoDate(string text) {
        Text=text;int suffix=19;while(suffix<text.Length&&(text[suffix]=='.'||char.IsAsciiDigit(text[suffix])))suffix++;
        Fraction=suffix>19?text[19..suffix]:"";Offset=text[suffix..];
        // The current wire has no epoch/calendar projection; historical values need a shared interface decision.
        if(string.CompareOrdinal(text[..10],"1582:10:15")>=0&&DateTime.TryParseExact(text[..19],"yyyy:MM:dd HH:mm:ss",CultureInfo.InvariantCulture,DateTimeStyles.None,out var wall))WallProjection=DateTime.SpecifyKind(wall,DateTimeKind.Unspecified);
    }
    internal DateTimeOffset? Instant() {
        if(WallProjection is not {} wall||Offset.Length==0||(Fraction.Length>8&&Fraction[8..].Any(c=>c!='0')))return null;
        try {
            long ticks=Fraction.Length==0?0:long.Parse(Fraction[1..].PadRight(7,'0')[..7],CultureInfo.InvariantCulture);
            var offset=Offset=="Z"?TimeSpan.Zero:TimeSpan.FromMinutes(int.Parse(Offset.AsSpan(1,2),CultureInfo.InvariantCulture)*60+int.Parse(Offset.AsSpan(4,2),CultureInfo.InvariantCulture))*(Offset[0]=='-'?-1:1);
            return new DateTimeOffset(wall.AddTicks(ticks),offset);
        }catch(ArgumentException){return null;}
    }
    internal (long Ticks,int Nanoseconds)? SortProjection { get {
        if(WallProjection is not {} wall)return null;
        long offset=Offset.Length<=1?0:(int.Parse(Offset.AsSpan(1,2),CultureInfo.InvariantCulture)*60L+int.Parse(Offset.AsSpan(4,2),CultureInfo.InvariantCulture))*(Offset[0]=='-'?-1:1);
        var seconds=checked(wall.Ticks-offset*TimeSpan.TicksPerMinute);
        int nano=Fraction.Length==0?0:int.Parse(Fraction[1..].PadRight(9,'0'),CultureInfo.InvariantCulture);
        return(seconds,nano);
    }}
    internal static VerifiedPhotoDate FromValidation(string text,VerifiedMetadataDates proof) { if(!proof.Contains(text))throw new InvalidOperationException("日期不属于本请求验证。");return new(text); }
    internal static VerifiedPhotoDate FromPage(DatePagePreview preview,PhotoDocument document)=>new(preview.ValueFor(document));
    internal static string Bridge(string text)=>text.Length>=19&&text[4]=='-'&&text[7]=='-'&&text[10]=='T'?text[..4]+":"+text[5..7]+":"+text[8..10]+" "+text[11..]:text;
    internal static async Task<IReadOnlyDictionary<string,VerifiedPhotoDate?>> InspectAsync(IEnumerable<string> values,CancellationToken token=default) {
        var texts=values.Where(x=>x.Length>0).Distinct(StringComparer.Ordinal).ToArray();
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
        DateResult[] results;try{results=await adapter.ComputeAsync(texts.Select((text,index)=>new DateJob(new WireItem(index.ToString(CultureInfo.InvariantCulture),"normalize",text))).ToArray(),0,()=>0,token);}catch(DateFailure)when(token.IsCancellationRequested){throw new OperationCanceledException(token);}
        token.ThrowIfCancellationRequested();return texts.Select((text,index)=>(text,value:results[index].Error is null?new VerifiedPhotoDate(text):null)).ToDictionary(x=>x.text,x=>x.value,StringComparer.Ordinal);
    }
}
