using System.IO;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace PhotoTrail.Windows;

record SourceIdentity([property: JsonRequired] string Commit, [property: JsonRequired] string Path, [property: JsonRequired] string Sha256);
record KernelError(string Scope, string Code);
record WireItem(string Id, string Op, string? Text = null, long? Years = null, long? Months = null, long? Days = null,
    long? Hours = null, long? Minutes = null, long? Seconds = null, string? Component = null, long? Value = null,
    Dictionary<string, long>? Components = null, long? Count = null, string? End = null, string? Zone = null);
enum SourceState { Present, ConfirmedMissing, ReadFailed }
record DateJob(WireItem Item, string Field = "XMP-exif:DateTimeOriginal", SourceState State = SourceState.Present, bool Clear = false);
record DateResult([property: JsonRequired] string Id, string[]? Values, KernelError? Error, bool Clear = false);
record Frame([property: JsonRequired] string Version, [property: JsonRequired] string Id, [property: JsonRequired] SourceIdentity Source,
    [property: JsonRequired] DateResult[] Results, [property: JsonRequired] double ComputeMs, KernelError? JobError);
record Measurement(int Pid, int Items, int InputBytes, int OutputBytes, double TotalMs, double ComputeMs);
sealed class DateFailure(string code, Exception? inner = null) : Exception(code, inner) { public string Code { get; } = code; }

// One concrete process adapter; local revision/field/source state never enter the wire DTO.
sealed class DateAdapter(string executable, SourceIdentity expectedSource, string version = "date-isolated-v1",
    string arguments = "", int ordinaryBatchSize = 3000, int timeoutMs = 30000)
{
    internal const int MaxBytes = 1_048_576;
    internal static readonly JsonSerializerOptions Json = new() {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
    static readonly HashSet<string> Fields = ["XMP-exif:DateTimeOriginal", "XMP-exif:DateTimeDigitized", "XMP-xmp:CreateDate", "XMP-xmp:ModifyDate"];
    static readonly Regex OutputText = new(@"\A[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?(?:Z|[+-][0-9]{2}:[0-9]{2})?\z", RegexOptions.CultureInvariant);
    public event Action? CalculationStarted;
    public event Action<string>? Diagnostic;
    public List<int> Pids { get; } = [];
    public List<Measurement> Measurements { get; } = [];
    public int AcceptedFrames { get; private set; }
    public int PublishedCalls { get; private set; }
    public bool LastChildExited { get; private set; }
    static bool Global(WireItem item) => item.Op is "sequence" or "distribute";
    static int Cost(WireItem item) => Global(item) ? checked((int)Math.Max(1, item.Count ?? 0)) : 1;
    string Encode(string id, IReadOnlyList<WireItem> items) => JsonSerializer.Serialize(new { version, id, items }, Json);

    public async Task<DateResult[]> ComputeAsync(IReadOnlyList<DateJob> jobs, int revision, Func<int> currentRevision, CancellationToken cancellation = default)
    {
        void Current() { if (cancellation.IsCancellationRequested) throw new DateFailure("canceled"); if (revision != currentRevision()) throw new DateFailure("staleRevision"); }
        Current();
        if (ordinaryBatchSize is < 1 or > 3000) throw new DateFailure("batchConfiguration");
        if (jobs.Select(j => j.Item.Id).Distinct(StringComparer.Ordinal).Count() != jobs.Count) throw new DateFailure("duplicateInputID");
        var byId = new Dictionary<string, DateResult>(StringComparer.Ordinal);
        var pending = new List<WireItem>();
        foreach (var job in jobs)
        {
            if (!Fields.Contains(job.Field)) throw new DateFailure("invalidField");
            if (!Enum.IsDefined(job.State)) throw new DateFailure("sourceState");
            if (job.State == SourceState.ReadFailed) throw new DateFailure("sourceReadFailed");
            if (job.Clear) { if (job.Item.Op != "normalize") throw new DateFailure("invalidClear"); byId.Add(job.Item.Id, new(job.Item.Id, null, null, true)); continue; }
            if (job.State == SourceState.ConfirmedMissing && job.Item.Op is not ("sequence" or "distribute")) {
                byId.Add(job.Item.Id, new(job.Item.Id, null, new("business", "missingDate"))); continue;
            }
            if (Global(job.Item) && job.Item.Count > 3000) throw new DateFailure("resultLimit");
            pending.Add(job.Item);
        }
        for (int index = 0; index < pending.Count;)
        {
            Current();
            int count = Global(pending[index]) ? 1 : Math.Min(ordinaryBatchSize, pending.Count - index);
            for (int i = 1; i < count; i++) if (Global(pending[index + i])) { count = i; break; }
            string requestId = Guid.NewGuid().ToString("N");
            WireItem[] batch; string input;
            while (true) {
                batch = pending.GetRange(index, count).ToArray(); input = Encode(requestId, batch);
                if (Encoding.UTF8.GetByteCount(input) <= MaxBytes) break;
                if (count == 1 || Global(batch[0])) throw new DateFailure("inputLimit");
                count = Math.Max(1, count / 2); // Split independent items only; never global generation.
            }
            var frame = await ExchangeAsync(input, requestId, batch, cancellation);
            Current();
            foreach (var result in frame.Results) byId.Add(result.Id, result);
            index += count;
        }
        Current();
        var complete = jobs.Select(j => byId[j.Item.Id]).ToArray();
        PublishedCalls++; return complete; // A transport failure never returns the earlier batches.
    }

    internal async Task<Frame> RawAsync(string json, string requestId, CancellationToken cancellation = default) => await ExchangeAsync(json, requestId, null, cancellation);
    async Task<string> ReadBoundedAsync(StreamReader reader, int limit, CancellationToken token, Action<string>? observer = null)
    {
        var text = new StringBuilder(); char[] buffer = new char[4096]; int read;
        while ((read = await reader.ReadAsync(buffer.AsMemory(), token)) != 0) {
            text.Append(buffer, 0, read);
            if (text.Length > limit || Encoding.UTF8.GetByteCount(text.ToString()) > limit) throw new DateFailure("outputLimit");
            observer?.Invoke(text.ToString());
        }
        return text.ToString();
    }
    static void UniqueMembers(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object) {
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var member in element.EnumerateObject()) { if (!keys.Add(member.Name)) throw new DateFailure("duplicateMember"); UniqueMembers(member.Value); }
        } else if (element.ValueKind == JsonValueKind.Array) foreach (var child in element.EnumerateArray()) UniqueMembers(child);
    }
    async Task<Frame> ExchangeAsync(string input, string requestId, WireItem[]? items, CancellationToken cancellation)
    {
        if (Encoding.UTF8.GetByteCount(input) > MaxBytes) throw new DateFailure("inputLimit");
        using var deadline = new CancellationTokenSource(timeoutMs);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, deadline.Token);
        using var process = new Process { StartInfo = new ProcessStartInfo(executable, arguments) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        }};
        bool started = false, marked = false;
        Task<string>? output = null, diagnostics = null;
        Task? sender = null;
        var clock = Stopwatch.StartNew();
        try {
            linked.Token.ThrowIfCancellationRequested();
            try { started = process.Start(); if (!started) throw new DateFailure("startFailed"); }
            catch (System.ComponentModel.Win32Exception error) { throw new DateFailure(error.NativeErrorCode is 126 or 127 or 14001 ? "dependencyMissing" : "startFailed", error); }
            Pids.Add(process.Id); LastChildExited = false;
            output = ReadBoundedAsync(process.StandardOutput, MaxBytes, linked.Token);
            diagnostics = ReadBoundedAsync(process.StandardError, 65536, linked.Token, text => {
                Diagnostic?.Invoke(text);
                if (!marked && text.Contains("CALC_STARTED:first_item_computed", StringComparison.Ordinal)) { marked = true; CalculationStarted?.Invoke(); }
            });
            async Task Send() { await process.StandardInput.WriteAsync(input.AsMemory(), linked.Token); process.StandardInput.Close(); }
            sender = Send(); Task wait = process.WaitForExitAsync(linked.Token);
            var tasks = new List<Task> { sender, wait, output, diagnostics };
            // Fail fast on bounded-reader faults instead of waiting for an unresponsive child.
            while (tasks.Count > 0) { Task done = await Task.WhenAny(tasks); await done; tasks.Remove(done); }
            linked.Token.ThrowIfCancellationRequested();
            if (process.ExitCode != 0) throw new DateFailure(process.ExitCode == unchecked((int)0xc0000135) ? "dependencyMissing" : "nonzeroExit:" + process.ExitCode);
            Frame frame;
            try { using var doc = JsonDocument.Parse(await output); UniqueMembers(doc.RootElement); frame = JsonSerializer.Deserialize<Frame>(doc.RootElement, Json) ?? throw new DateFailure("emptyResponse"); }
            catch (JsonException error) { throw new DateFailure("malformedResponse", error); }
            if (frame.Version != version) throw new DateFailure("versionMismatch");
            if (frame.Source != expectedSource) throw new DateFailure("sourceMismatch");
            if (frame.Id != requestId) throw new DateFailure("requestIDMismatch");
            if (!double.IsFinite(frame.ComputeMs) || frame.ComputeMs < 0 || frame.Results is null) throw new DateFailure("malformedResponse");
            if (frame.JobError is { } jobError) throw new DateFailure(jobError.Scope + ":" + jobError.Code);
            if (items is not null) {
                if (frame.Results.Length != items.Length) throw new DateFailure("resultCountMismatch");
                var seen = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 0; i < items.Length; i++) {
                    var result = frame.Results[i];
                    if (result is null || result.Id != items[i].Id || !seen.Add(result.Id)) throw new DateFailure("resultIDMismatch");
                    if (result.Clear || (result.Values is null) == (result.Error is null)) throw new DateFailure("malformedResult");
                    if (result.Error is { } error && (error.Scope is not ("business" or "parameter" or "boundary") || string.IsNullOrEmpty(error.Code))) throw new DateFailure("malformedResult");
                    if (result.Values is { } values && (values.Length != Cost(items[i]) || values.Any(v => v is null || Encoding.UTF8.GetByteCount(v) > 128 || !OutputText.IsMatch(v)))) throw new DateFailure("malformedResult");
                }
            }
            linked.Token.ThrowIfCancellationRequested();
            AcceptedFrames++;
            Measurements.Add(new(process.Id, items?.Length ?? 0, Encoding.UTF8.GetByteCount(input), Encoding.UTF8.GetByteCount(await output), clock.Elapsed.TotalMilliseconds, frame.ComputeMs));
            return frame;
        } catch (OperationCanceledException error) { throw new DateFailure(cancellation.IsCancellationRequested ? "canceled" : "timeout", error); }
        finally {
            deadline.Cancel();
            if (started) {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync(); LastChildExited = process.HasExited;
            }
            if (output is not null) try { await output; } catch { }
            if (diagnostics is not null) try { await diagnostics; } catch { }
            if (sender is not null) try { await sender; } catch { }
        }
    }
}
