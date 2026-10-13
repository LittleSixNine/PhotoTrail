using System.IO;
namespace PhotoTrail.Windows;

// A request-local proof binds exact text to the pinned host; it never substitutes a calendar.
internal sealed class VerifiedMetadataDates
{
    readonly IReadOnlyDictionary<string,DateProjection> accepted;
    internal DateProjection Projection(string text)=>accepted.TryGetValue(text,out var value)?value:throw new InvalidOperationException("日期不属于本请求验证。");
    internal bool Contains(string text)=>accepted.ContainsKey(text);
    internal IReadOnlyList<Measurement> Measurements { get; }
    internal int CandidateCount { get; }
    private VerifiedMetadataDates(IReadOnlyDictionary<string,DateProjection> accepted,IReadOnlyList<Measurement> measurements,int count) { this.accepted=accepted;Measurements=measurements;CandidateCount=count; }
    internal static bool IsDate(string tag)=>tag is "XMP-exif:DateTimeOriginal" or "XMP-exif:DateTimeDigitized" or "XMP-xmp:CreateDate" or "XMP-xmp:ModifyDate";
    internal void Require(IReadOnlyDictionary<string,string> changes) {
        foreach(var (tag,value) in changes)if(IsDate(tag)&&value.Length>0&&!accepted.ContainsKey(value))throw new InvalidOperationException("日期不属于本次共享验证结果。");
    }
    internal static async Task<VerifiedMetadataDates> CreateAsync(IEnumerable<KeyValuePair<string,string>> candidates,CancellationToken token=default,Action<DateAdapter>? observe=null) {
        var input=candidates.Where(p=>IsDate(p.Key)&&p.Value.Length>0).ToArray();
        foreach(var pair in input)PhotoDocument.ValidateChanges(new Dictionary<string,string>{{pair.Key,pair.Value}});
        var texts=input.Select(p=>p.Value).Distinct(StringComparer.Ordinal).ToArray();
        var jobs=texts.Select((text,index)=>new DateJob(new WireItem(index.ToString(System.Globalization.CultureInfo.InvariantCulture),"project",text))).ToArray();
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);observe?.Invoke(adapter);
        DateResult[] results;try{results=await adapter.ComputeAsync(jobs,0,()=>0,token);}catch(DateFailure)when(token.IsCancellationRequested){throw new OperationCanceledException(token);}
        foreach(var result in results)if(result.Error is {} error)throw new ArgumentException("共享日期验证拒绝："+error.Code);
        token.ThrowIfCancellationRequested();return new(results.ToDictionary(x=>x.Projection!.Text,x=>x.Projection!,StringComparer.Ordinal),adapter.Measurements.ToArray(),input.Length);
    }
}
