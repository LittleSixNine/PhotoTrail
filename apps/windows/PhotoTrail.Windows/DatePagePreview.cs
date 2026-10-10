using System.IO;
namespace PhotoTrail.Windows;

internal sealed record DatePageOptions(int Mode, long Years = 0, long Months = 0, long Days = 0, long Hours = 0,
    long Minutes = 0, long Seconds = 0, Dictionary<string,long>? Components = null, string Start = "", string End = "",
    string Pattern = "", string Template = "");

// Only a successful pinned adapter call can construct this capability; no arbitrary date bypass switch.
internal sealed class DatePagePreview
{
    internal const string Field = "XMP-exif:DateTimeOriginal";
    internal static readonly SourceIdentity Source = new("3593051e21e3af2c060a061aeaa888dee24c3bb4",
        "Packages/ImageData/Sources/ImageData/MetadataDateEdit.swift", "593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc");
    readonly PhotoDocument[] documents;
    readonly long[] drafts;
    readonly string[] before;
    readonly string?[] after;
    bool consumed;
    internal IReadOnlyList<string?> Values => Array.AsReadOnly(after);
    internal IReadOnlyList<Measurement> Measurements { get; }
    DatePagePreview(PhotoDocument[] documents, long[] drafts, string[] before, string?[] after, IReadOnlyList<Measurement> measurements)
    { this.documents=documents; this.drafts=drafts; this.before=before; this.after=after; Measurements=measurements; }

    internal static async Task<DatePagePreview> CreateAsync(IReadOnlyList<PhotoDocument> selection, DatePageOptions options,
        int revision, Func<int> currentRevision, CancellationToken token)
    {
        var docs=selection.ToArray();
        if(docs.Length is < 1 or > 3000 || docs.Distinct().Count()!=docs.Length || docs.Any(d=>!d.CanEdit))
            throw new InvalidOperationException("请选择1至3000个不同的可编辑文件。");
        var drafts=docs.Select(d=>d.DraftRevision).ToArray();
        var before=docs.Select(d=>d.Value(Field)).ToArray();
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),Source);
        var jobs=new List<DateJob>();
        string?[]? extracted=null;
        if(options.Mode==4) extracted=MetadataDate.ExtractFilenames(docs.Select(d=>Path.GetFileName(d.FilePath)).ToArray(),options.Pattern,options.Template);
        // Preserve existing Windows input ranges without using its date/calendar calculation.
        if(options.Mode==0 && (options.Years is < -9999 or > 9999 || options.Months is < -120000 or > 120000 ||
            options.Days is < -3660000 or > 3660000 || options.Hours is < -87840000 or > 87840000 ||
            options.Minutes is < -int.MaxValue or > int.MaxValue || options.Seconds is < -316224000000 or > 316224000000))
            throw new ArgumentException("时间调整超出支持范围。");
        if(options.Mode is 1 or 3) jobs.Add(new(new("global",options.Mode==1?"sequence":"distribute",options.Start,
            Seconds:options.Seconds,Count:docs.Length,End:options.End)));
        else for(int i=0;i<docs.Length;i++) {
            if(options.Mode==4 && extracted![i] is null) continue;
            string text=options.Mode==4?extracted![i]!:before[i];
            var item=options.Mode switch {
                0=>new WireItem(i.ToString(),"offset",text,options.Years,options.Months,options.Days,options.Hours,options.Minutes,options.Seconds),
                2=>new WireItem(i.ToString(),"replaceAtomic",text,Components:options.Components),
                4=>new WireItem(i.ToString(),"normalize",text),
                _=>throw new ArgumentException("日期模式无效。")
            };
            jobs.Add(new(item,State:options.Mode!=4&&text.Length==0?SourceState.ConfirmedMissing:SourceState.Present));
        }
        var result=await adapter.ComputeAsync(jobs,revision,currentRevision,token);
        var values=new string?[docs.Length];
        if(options.Mode is 1 or 3) {
            if(result[0].Error is { } error) throw new InvalidOperationException("日期计算失败："+error.Code);
            for(int i=0;i<values.Length;i++)values[i]=result[0].Values![i];
        } else foreach(var item in result) {
            if(item.Error is { } error) {
                if(options.Mode==4 && error.Scope=="business" && error.Code=="invalidDate")continue;
                throw new InvalidOperationException("日期计算失败："+error.Code);
            }
            values[int.Parse(item.Id,System.Globalization.CultureInfo.InvariantCulture)]=item.Values![0];
        }
        var preview=new DatePagePreview(docs,drafts,before,values,adapter.Measurements.ToArray());
        preview.ValidateAll();return preview;
    }
    void Current(int i) {
        if(consumed || !documents[i].CanEdit || documents[i].DraftRevision!=drafts[i] || documents[i].Value(Field)!=before[i])
            throw new InvalidOperationException("照片或草稿状态已改变，请重新预览。");
    }
    internal void ValidateAll() {
        for(int i=0;i<documents.Length;i++) { Current(i); if(after[i] is { } value) PhotoDocument.ValidateDatePageShape(Field,value); }
    }
    internal string ValueFor(PhotoDocument document) {
        int index=Array.IndexOf(documents,document);
        if(index<0 || after[index] is null)throw new InvalidOperationException("照片不属于本次验证结果。");
        Current(index);return after[index]!;
    }
    internal void Apply() {
        ValidateAll(); // Caller stays on the UI thread: no await between all-batch validation and mutations.
        for(int i=0;i<documents.Length;i++)if(after[i] is not null)documents[i].ApplyDatePage(this);
        consumed=true;
    }
}
