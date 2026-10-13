using System.Globalization;
using System.IO;
namespace PhotoTrail.Windows;

// Only a pinned host result authorizes text extraction. Native time projection is a separate, fallible adapter.
internal sealed record VerifiedPhotoDate
{
    internal string Text { get; }
    internal string Fraction { get; }
    internal string Offset { get; }
    internal DateProjection Projection { get; }
    internal string NameSeconds=>Text[..19].Replace(":","").Replace(" ","_");
    private VerifiedPhotoDate(DateProjection projection) {
        Projection=projection;Text=projection.Text;int suffix=19;while(suffix<Text.Length&&(Text[suffix]=='.'||char.IsAsciiDigit(Text[suffix])))suffix++;
        Fraction=suffix>19?Text[19..suffix]:"";Offset=Text[suffix..];
    }
    internal string? InstantLimitation => Projection.Kind!="instant"?"时区不足":Projection.Nanoseconds%100!=0?"精度不足":Instant() is null?"平台范围不足":null;
    internal DateTimeOffset? Instant() {
        if(Projection.Kind!="instant"||Projection.Nanoseconds%100!=0)return null;
        try { return new DateTimeOffset(checked(DateTime.UnixEpoch.Ticks+checked(Projection.Seconds*TimeSpan.TicksPerSecond)+Projection.Nanoseconds/100),TimeSpan.Zero); }
        catch(ArgumentException){return null;}catch(OverflowException){return null;}
    }
    internal (long Seconds,int Nanoseconds) SortProjection=>(Projection.Seconds,Projection.Nanoseconds);
    internal static VerifiedPhotoDate FromValidation(string text,VerifiedMetadataDates proof)=>new(proof.Projection(text));
    internal static VerifiedPhotoDate FromPage(DatePagePreview preview,PhotoDocument document)=>FromValidation(preview.ValueFor(document),preview.Projections);
    internal static string Bridge(string text)=>text.Length>=19&&text[4]=='-'&&text[7]=='-'&&text[10]=='T'?text[..4]+":"+text[5..7]+":"+text[8..10]+" "+text[11..]:text;
    internal static async Task<IReadOnlyDictionary<string,VerifiedPhotoDate?>> InspectAsync(IEnumerable<string> values,CancellationToken token=default) {
        var texts=values.Where(x=>x.Length>0).Distinct(StringComparer.Ordinal).ToArray();
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
        DateResult[] results;try{results=await adapter.ComputeAsync(texts.Select((text,index)=>new DateJob(new WireItem(index.ToString(CultureInfo.InvariantCulture),"project",text))).ToArray(),0,()=>0,token);}catch(DateFailure)when(token.IsCancellationRequested){throw new OperationCanceledException(token);}
        token.ThrowIfCancellationRequested();return texts.Select((text,index)=>(text,value:results[index].Error is null?new VerifiedPhotoDate(results[index].Projection!):null)).ToDictionary(x=>x.text,x=>x.value,StringComparer.Ordinal);
    }
}
