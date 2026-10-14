using System.IO;
namespace PhotoTrail.Windows;

internal sealed record DatePageOptions(int Mode, long Years = 0, long Months = 0, long Days = 0, long Hours = 0,
    long Minutes = 0, long Seconds = 0, Dictionary<string,long>? Components = null, string Start = "", string End = "",
    string Pattern = "", string Template = "", string? Target = null, string? Zone = null);

// Only a successful pinned adapter call can construct this capability; no arbitrary date bypass switch.
internal sealed class DatePagePreview
{
    internal static readonly SourceIdentity Source = new("a0299e6f6c956f66ace2b85449b54db5e2eeeee4",
        "Packages/PhotoTrailDateCore/Sources/PhotoTrailDateCore/MetadataDateEdit.swift", "15e1f395ac379552b4c43892f6d70321e3c2f0fd6e0dc9d8ccadacc7bb607dc8");
    readonly PhotoDocument[] documents;
    readonly string[] targets;
    readonly long[] drafts;
    readonly string[] before;
    readonly string?[] after;
    readonly bool strictDate;
    internal double ProjectionHostMs=>Projections.Measurements.Sum(m=>m.TotalMs);
    internal int ProjectionRequests=>Projections.Measurements.Count;
    internal VerifiedMetadataDates Projections {get;private set;}=null!;
    bool consumed;
    internal IReadOnlyList<string?> Values => Array.AsReadOnly(after);
    internal double SourceCheckMs { get; private set; }
    internal int FilenameMismatchCount {get;private set;}
    internal int FilenameInvalidCount {get;private set;}
    internal int MissingCount { get; }
    internal int UnchangedCount { get; }
    internal IReadOnlyList<Measurement> Measurements { get; }
    DatePagePreview(PhotoDocument[] documents, string[] targets, long[] drafts, string[] before, string?[] after, IReadOnlyList<Measurement> measurements, int missing, int unchanged, bool strictDate)
    { this.documents=documents;this.targets=targets; this.drafts=drafts; this.before=before; this.after=after; Measurements=measurements; MissingCount=missing; UnchangedCount=unchanged; this.strictDate=strictDate; }
    internal string SkippedText(int index) => before[index].Length==0 ? "缺失时间，已跳过" : "无变化，保留原草稿";

    internal static async Task<DatePagePreview> CreateAsync(IReadOnlyList<PhotoDocument> selection, DatePageOptions options,
        int revision, Func<int> currentRevision, CancellationToken token, Action? calculationStarted=null, Action<DateAdapter>? observeAdapter=null)
    {
        var preview=await CalculateAsync(selection,options,revision,currentRevision,token,calculationStarted,observeAdapter);
        var clock=System.Diagnostics.Stopwatch.StartNew();
        if(options.Mode is 0 or 2 or 5 or 6)foreach(var doc in selection)await doc.EnsureUnchangedAsync(token);
        preview.SourceCheckMs=clock.Elapsed.TotalMilliseconds;token.ThrowIfCancellationRequested();
        if(revision!=currentRevision())throw new DateFailure("staleRevision");
        preview.ValidateAll();return preview;
    }
    // Direct application uses detached request snapshots; its caller verifies all live sources before committing.
    internal static async Task<DatePagePreview> CalculateAsync(IReadOnlyList<PhotoDocument> selection, DatePageOptions options,
        int revision, Func<int> currentRevision, CancellationToken token, Action? calculationStarted=null, Action<DateAdapter>? observeAdapter=null)
    {
        var docs=selection.ToArray();var targets=docs.Select(d=>options.Target??d.MainDateTag).ToArray();
        ValidateOptions(options);
        if(targets.Any(t=>!VerifiedMetadataDates.IsDate(t)&&!MetadataTimes.IsSystem(t)))throw new ArgumentException("日期目标未开放。");
        if(docs.Length is < 1 or > 3000 || docs.Distinct().Count()!=docs.Length || docs.Select(d=>d.SidecarPath??d.FilePath).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=docs.Length || docs.Select((d,i)=>!MetadataFields.CanEdit(d,targets[i])).Any(x=>x))
            throw new InvalidOperationException("请选择1至3000个不同的可编辑文件。");
        var drafts=docs.Select(d=>d.DraftRevision).ToArray();
        var before=docs.Select((d,i)=>options.Mode is 0 or 2 or 5 or 6?OffsetValue(d,targets[i]):d.Value(targets[i])).ToArray();
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),Source);
        if(calculationStarted is not null)adapter.CalculationStarted+=calculationStarted;
        observeAdapter?.Invoke(adapter);
        var jobs=new List<DateJob>();
        string?[]? extracted=null;
        if(options.Mode==4) extracted=MetadataDate.ExtractFilenames(docs.Select(d=>Path.GetFileName(d.FilePath)).ToArray(),options.Pattern,options.Template);
        if(options.Mode is 1 or 3) jobs.Add(new(new("global",options.Mode==1?"sequence":"distribute",options.Start,
            Seconds:options.Seconds,Count:docs.Length,End:options.End)));
        else for(int i=0;i<docs.Length;i++) {
            if(options.Mode==4 && extracted![i] is null) continue;
            string text=options.Mode==4?extracted![i]!:before[i];
            var item=options.Mode switch {
                0=>new WireItem(i.ToString(),"offset",text,options.Years,options.Months,options.Days,options.Hours,options.Minutes,options.Seconds),
                2=>new WireItem(i.ToString(),"replaceAtomic",text,Components:options.Components),
                5=>new WireItem(i.ToString(),"shift",text,Seconds:options.Seconds),
                6=>new WireItem(i.ToString(),"calendarDays",text,Days:options.Days,Zone:options.Zone),
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
                if(options.Mode is 0 or 2 or 5 or 6 && before[int.Parse(item.Id,System.Globalization.CultureInfo.InvariantCulture)].Length==0 && error.Scope=="business" && error.Code=="missingDate")continue;
                if(options.Mode==4 && error.Scope=="business" && error.Code=="invalidDate")continue;
                throw new InvalidOperationException("日期计算失败："+error.Code);
            }
            values[int.Parse(item.Id,System.Globalization.CultureInfo.InvariantCulture)]=item.Values![0];
        }
        int missing=0,unchanged=0;
        for(int i=0;i<docs.Length;i++) {
            if(options.Mode is 0 or 2 or 5 or 6 && before[i].Length==0)missing++;
            else if(values[i] is not null && values[i]==before[i]) { values[i]=null; unchanged++; }
        }
        var projection=await VerifiedMetadataDates.CreateAsync(values.Select((v,i)=>new KeyValuePair<string,string>(targets[i],v??"")),token);
        token.ThrowIfCancellationRequested();if(revision!=currentRevision())throw new DateFailure("staleRevision");
        var preview=new DatePagePreview(docs,targets,drafts,before,values,adapter.Measurements.Concat(projection.Measurements).ToArray(),missing,unchanged,options.Mode is 0 or 2 or 5 or 6){Projections=projection};
        if(options.Mode==4){preview.FilenameMismatchCount=extracted!.Count(v=>v is null);preview.FilenameInvalidCount=values.Count(v=>v is null)-preview.FilenameMismatchCount-unchanged;}
        preview.ValidateAll();return preview;
    }
    internal static void ValidateOptions(DatePageOptions options) {
        // Preserve existing Windows input ranges without using its date/calendar calculation.
        if(options.Mode==0 && (options.Years is < -9999 or > 9999 || options.Months is < -120000 or > 120000 ||
            options.Days is < -3660000 or > 3660000 || options.Hours is < -87840000 or > 87840000 ||
            options.Minutes is < -5270400000 or > 5270400000 || options.Seconds is < -316224000000 or > 316224000000))
            throw new ArgumentException("时间调整超出支持范围。");
        if(options.Mode==2) {
            if(options.Components is null || options.Components.Count==0)throw new ArgumentException("请填写至少一个日期组件。");
            foreach(var (name,value) in options.Components) {
                var (minimum,maximum)=name switch {
                    "year"=>(1,9999),"month"=>(1,12),"day"=>(1,31),
                    "hour"=>(0,23),"minute" or "second"=>(0,59),_=>throw new ArgumentException("日期组件无效。")
                };
                if(value<minimum || value>maximum)throw new ArgumentException("日期组件超出支持范围。");
            }
        }

        if(options.Mode is 1 or 5 && options.Seconds is < -315537897599 or > 315537897599)throw new ArgumentException("秒参数超范围。");
        if(options.Mode==6) { if(options.Days is < -3652058 or > 3652058)throw new ArgumentException("日历天数超范围。"); if(options.Zone is {} zone)_=TimeZoneInfo.FindSystemTimeZoneById(zone); }
        if(options.Mode is 1 or 3) { PhotoDocument.ValidateDatePageShape("XMP-xmp:CreateDate",options.Start);if(options.Mode==3)PhotoDocument.ValidateDatePageShape("XMP-xmp:CreateDate",options.End); }
        if(options.Mode==4)_=MetadataDate.ExtractFilenames(["parameter-check.jpg"],options.Pattern,options.Template);
        if(options.Mode is <0 or >6)throw new ArgumentException("日期模式未知。");
    }
    static string OffsetValue(PhotoDocument document,string tag) => MetadataTimes.IsSystem(tag)?document.Value(tag):MetadataFields.DateText(document,tag);
    internal string TargetFor(PhotoDocument document) {int i=Array.IndexOf(documents,document);if(i<0)throw new InvalidOperationException("照片不属于日期计划。");Current(i);return targets[i];}
    void Current(int i) {
        if(consumed || !MetadataFields.CanEdit(documents[i],targets[i]) || documents[i].DraftRevision!=drafts[i] || (strictDate?OffsetValue(documents[i],targets[i]):documents[i].Value(targets[i]))!=before[i])
            throw new InvalidOperationException("照片或草稿状态已改变，请重新预览。");
    }
    internal void ValidateAll() {
        for(int i=0;i<documents.Length;i++) { Current(i); if(after[i] is { } value) if(MetadataTimes.IsSystem(targets[i]))_=MetadataTimes.Parse(value);else PhotoDocument.ValidateDatePageShape(targets[i],value); }
    }
    internal string ValueFor(PhotoDocument document) {
        int index=Array.IndexOf(documents,document);
        if(index<0 || after[index] is null)throw new InvalidOperationException("照片不属于本次验证结果。");
        Current(index);return after[index]!;
    }
    internal void Apply() {
        ValidateAll(); // Caller stays on the UI thread: no await between all-batch validation and mutations.
        for(int i=0;i<documents.Length;i++)if(after[i] is not null)if(MetadataTimes.IsSystem(targets[i]))documents[i].StageDraft(new Dictionary<string,string>{{targets[i],after[i]!}});else documents[i].ApplyDatePage(this);
        consumed=true;
    }
}
