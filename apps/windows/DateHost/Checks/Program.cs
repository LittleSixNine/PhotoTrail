using System.Diagnostics;
using System.Globalization;
using PhotoTrail.Windows;
using System.Text.Json;

static class Program
{
    static readonly List<object> Evidence = [];
    static SourceIdentity Source = null!;
    static string Host = "", Base = "";
    static int Passed;
    static void Check(bool condition, string name) { if (!condition) throw new Exception(name); Passed++; Evidence.Add(new { name, passed = true }); }
    static DateJob Job(string id, string op, string text = "2024:01:01 00:00:00") => new(new(id, op, text));
    static DateAdapter Real(int size = 3000, int timeout = 30000) => new(Host, Source, ordinaryBatchSize: size, timeoutMs: timeout);
    static DateAdapter Fake(string mode, string counter = "", int size = 3000, int timeout = 30000) => new(Environment.ProcessPath!, Source,
        arguments: $"\"{typeof(Program).Assembly.Location}\" --fixture {mode} \"{Base}\" \"{counter}\"", ordinaryBatchSize: size, timeoutMs: timeout);
    static async Task Reject(string expected, Func<Task> operation, string name) {
        try { await operation(); } catch (DateFailure error) { Check(error.Code.StartsWith(expected, StringComparison.Ordinal), name + ":" + error.Code); return; }
        throw new Exception("Did not reject: " + name);
    }
    static void Clean(DateAdapter adapter, string name) {
        foreach (int pid in adapter.Pids) {
            try { using var process = Process.GetProcessById(pid); Check(process.HasExited, name + "-pid-" + pid); }
            catch (ArgumentException) { Check(true, name + "-pid-" + pid); }
        }
    }
    static string Actual(DateResult result) => result.Error is { } error ? "error:" + error.Code : result.Values![0];
    static async Task Cases()
    {
        using var vectors = JsonDocument.Parse(File.ReadAllText(Path.Combine(Base, "compatibility-vectors.json")));
        var jobs = new List<DateJob>(); var expected = new List<string>();
        foreach (var vector in vectors.RootElement.EnumerateArray()) {
            string op = vector.GetProperty("operation").GetString()!;
            var parameters = vector.GetProperty("parameters");
            long? Number(string key) => parameters.TryGetProperty(key, out var value) ? long.Parse(value.GetString()!, CultureInfo.InvariantCulture) : null;
            string? Text(string key) => parameters.TryGetProperty(key, out var value) ? value.GetString() : null;
            jobs.Add(new(new("v" + jobs.Count, op switch { "parse" => "normalize", _ => op }, vector.GetProperty("input").GetString(),
                Days: Number("days"), Seconds: Number("seconds") ?? Number("stepSeconds"), Component: Text("component"), Value: Number("value"), Count: Number("count"), Zone: Text("zone"))));
            expected.Add(vector.GetProperty("actual").GetString()!);
        }
        var adapter = Real(); var results = await adapter.ComputeAsync(jobs, 1, () => 1);
        for (int i = 0; i < results.Length; i++) Check(Actual(results[i]) == expected[i], "compatibility-vector-" + i);
        Clean(adapter, "vectors");
        string precise = "2024:01:15 10:20:30.123456+08:00";
        var additions = new (WireItem Item, string Expected)[] {
            (new("plus","offset",precise,Years:1,Months:1,Days:2,Hours:3,Minutes:4,Seconds:5),"2025:02:17 13:24:35.123456+08:00"),
            (new("minus","offset",precise,Years:-1,Months:-1,Days:-2,Hours:-3,Minutes:-4,Seconds:-5),"2022:12:13 07:16:25.123456+08:00"),
            (new("clamp-year","offset","2024:02:29 12:00:00",Years:1),"error:invalidDate"),
            (new("clamp-month","offset","2024:01:31 12:00:00",Months:1),"error:invalidDate"),
            (new("atomic-leap","replaceAtomic","2024:02:29 12:34:56.123456789Z",Components:new(){["year"]=2025,["day"]=28}),"2025:02:28 12:34:56.123456789Z"),
            (new("single-leap","replace","2024:02:29 12:34:56.123456789Z",Component:"year",Value:2025),"error:invalidDate"),
            (new("atomic-month","replaceAtomic","2024:01:31 12:34:56.1-00:00",Components:new(){["month"]=2,["day"]=29}),"2024:02:29 12:34:56.1-00:00"),
            (new("atomic-empty","replaceAtomic",precise,Components:new()),"error:emptyComponents"),
            (new("atomic-invalid","replaceAtomic",precise,Components:new(){["month"]=2,["day"]=30}),"error:invalidDate"),
            (new("fraction-one","normalize","2024:01:01 00:00:00.1+00:00"),"2024:01:01 00:00:00.1+00:00"),
            (new("wall","shift","2024:12:31 23:59:59",Seconds:1),"2025:01:01 00:00:00"),
            (new("fixed","shift","2024:03:09 12:00:00-05:00",Seconds:86400),"2024:03:10 12:00:00-05:00"),
            (new("gap","calendarDays","2024:03:09 02:30:00-05:00",Days:1,Zone:"America/New_York"),"error:invalidDate"),
            (new("spring","calendarDays","2024:03:09 12:00:00-05:00",Days:1,Zone:"America/New_York"),"2024:03:10 12:00:00-04:00"),
            (new("zone-missing-offset","calendarDays","2024:03:09 12:00:00",Days:1,Zone:"America/New_York"),"error:invalidDate"),
            (new("zone-mismatch","calendarDays","2024:03:09 12:00:00+08:00",Days:1,Zone:"America/New_York"),"error:invalidDate"),
            (new("zone-unknown","calendarDays",precise,Days:1,Zone:"No/Such_Zone"),"error:invalidDate"),
            (new("distribution","distribute","2024:01:01 00:00:00",Count:3,End:"2024:01:01 00:00:05"),"2024:01:01 00:00:00|2024:01:01 00:00:03|2024:01:01 00:00:05"),
            (new("sequence","sequence","2024:12:31 23:59:59",Seconds:2,Count:3),"2024:12:31 23:59:59|2025:01:01 00:00:01|2025:01:01 00:00:03"),
            (new("zero-count","sequence",precise,Seconds:1,Count:0),"error:invalidSequence"),
            (new("negative-sequence","sequence","2024:01:01 00:00:02.1Z",Seconds:-1,Count:3),"2024:01:01 00:00:02.1Z|2024:01:01 00:00:01.1Z|2024:01:01 00:00:00.1Z"),
            (new("single-distribute","distribute",precise,Count:1,End:precise),precise),
            (new("reversed","distribute","2024:01:02 00:00:00",Count:2,End:"2024:01:01 00:00:00"),"error:invalidSequence"),
            (new("fraction-mismatch","distribute","2024:01:01 00:00:00.1Z",Count:2,End:"2024:01:01 00:00:00.100Z"),"error:invalidSequence"),
            (new("offset-mismatch","distribute","2024:01:01 00:00:00Z",Count:2,End:"2024:01:01 00:00:00+00:00"),"error:invalidSequence"),
            (new("nine-digits","normalize","2024:01:01 00:00:00.123456789+14:00"),"2024:01:01 00:00:00.123456789+14:00"),
            (new("lf","normalize",precise+"\n"),"error:dateInput"),
            (new("crlf","normalize",precise+"\r\n"),"error:dateInput"),
            (new("lf-start","sequence",precise+"\n",Count:2,Seconds:1),"error:dateInput"),
            (new("lf-end","distribute",precise,Count:2,End:precise+"\n"),"error:dateInput"),
            (new("lf-source","replaceAtomic",precise+"\n",Components:new(){["day"]=1}),"error:dateInput"),
            (new("empty-date","normalize",""),"error:invalidDate"),
            (new("cutover-gap","normalize","1582:10:10 12:00:00"),"error:invalidDate"),
            (new("cutover-shift","shift","1582:10:04 12:00:00",Seconds:86400),"1582:10:15 12:00:00"),
            (new("int-max","offset",precise,Years:long.MaxValue),"error:invalidDate"),
            (new("int-min","offset",precise,Seconds:long.MinValue),"error:invalidDate")
        };
        adapter = Real(); results = await adapter.ComputeAsync(additions.Select(c => new DateJob(c.Item)).ToArray(), 1, () => 1);
        for (int i = 0; i < additions.Length; i++) {
            string actual = results[i].Error is { } error ? "error:"+error.Code : string.Join("|",results[i].Values!);
            Check(actual == additions[i].Expected, "approved-" + additions[i].Item.Id);
            Evidence.Add(new { input = additions[i].Item, expected = additions[i].Expected, actual });
        }
        foreach (int count in new[] { 1, 100, 3000 }) {
            adapter = Real(); results = await adapter.ComputeAsync(Enumerable.Range(0,count).Select(i => new DateJob(new("p"+i,"shift",precise,Seconds:1))).ToArray(), 5,()=>5);
            Check(results.Length==count && results.Select(r=>r.Id).SequenceEqual(Enumerable.Range(0,count).Select(i=>"p"+i)) && results.All(r=>r.Values![0]=="2024:01:15 10:20:31.123456+08:00"),"batch-"+count);
            Check(adapter.Pids.Count==1,"one-process-"+count); Evidence.Add(new { performanceCount=count, measurements=adapter.Measurements }); Clean(adapter,"batch");
        }
        adapter = Real(); results = await adapter.ComputeAsync([new(new("clear","normalize",""),Clear:true),new(new("missing","offset",null),State:SourceState.ConfirmedMissing)],1,()=>1);
        Check(results[0].Clear && results[1].Error?.Code=="missingDate" && adapter.Pids.Count==0,"clear-and-confirmed-missing-local");
        await Reject("sourceReadFailed",()=>Real().ComputeAsync([new(new("read","offset",null),State:SourceState.ReadFailed)],1,()=>1),"read-failure-not-missing");
        await Reject("invalidField",()=>Real().ComputeAsync([new(new("field","normalize",precise),Field:"EXIF:Other")],1,()=>1),"field-local");
        foreach(string op in new[]{"sequence","distribute"}) await Reject("resultLimit",()=>Real().ComputeAsync([new(new("big",op,precise,Seconds:1,Count:3001,End:precise))],1,()=>1),"global-limit-"+op);
        foreach(string number in new[]{"1.0","1e0","9223372036854775808"}) {
            string raw="{\"version\":\"date-isolated-v1\",\"id\":\"raw\",\"items\":[{\"id\":\"n\",\"op\":\"shift\",\"text\":\"2024:01:01 00:00:00\",\"seconds\":"+number+"}]}";
            await Reject("parameter:invalidInteger",()=>Real().RawAsync(raw,"raw"),"integer-"+number);
        }
        await Reject("inputLimit",()=>Real().RawAsync(new string('x',DateAdapter.MaxBytes+1),"raw"),"input-budget-before-start");
        await Reject("parameter:versionMismatch",()=>Real().RawAsync("{\"version\":\"wrong\",\"id\":\"raw\",\"items\":[]}","raw"),"host-request-version");
        await Reject("parameter:unknownMember",()=>Real().RawAsync("{\"version\":\"date-isolated-v1\",\"id\":\"raw\",\"items\":[{\"id\":\"x\",\"op\":\"normalize\",\"text\":\"2024:01:01 00:00:00\",\"unused\":1}]}","raw"),"host-item-unknown-member");
        foreach(string op in new[]{"sequence","distribute"}) {
            adapter=Real();results=await adapter.ComputeAsync([new(new("global",op,"2024:01:01 00:00:00.1Z",Seconds:1,Count:3000,End:"2024:01:01 00:49:59.1Z"))],1,()=>1);
            Check(results[0].Values!.Length==3000 && results[0].Values![0]=="2024:01:01 00:00:00.1Z" && results[0].Values![1499]=="2024:01:01 00:24:59.1Z" && results[0].Values![2999]=="2024:01:01 00:49:59.1Z" && adapter.Pids.Count==1,"global-3000-"+op);
            Evidence.Add(new{globalOperation=op,measurements=adapter.Measurements});Clean(adapter,"global");
        }
        var escaped=Enumerable.Range(0,3000).Select(i=>Job(new string('\u0001',55)+i,"normalize")).ToArray();
        adapter=Real();results=await adapter.ComputeAsync(escaped,1,()=>1);
        Check(adapter.Pids.Count>1 && results.Select(r=>r.Id).SequenceEqual(escaped.Select(j=>j.Item.Id)) && adapter.Measurements.All(m=>m.InputBytes<=DateAdapter.MaxBytes&&m.OutputBytes<=DateAdapter.MaxBytes),"byte-budget-split-global-association");
        Evidence.Add(new{byteBudgetSplit=true,measurements=adapter.Measurements});Clean(adapter,"byte-split");
    }
    static async Task Transport()
    {
        var jobs=Enumerable.Range(0,10).Select(i=>Job("j"+i,"normalize")).ToArray();
        var adapter=Real(size:3);var results=await adapter.ComputeAsync(jobs,1,()=>1);
        Check(results.Select(r=>r.Id).SequenceEqual(jobs.Select(j=>j.Item.Id)) && adapter.Pids.Count==4,"independent-chunks-global-order");Clean(adapter,"chunks");
        string counter=Path.Combine(Base,"evidence",Guid.NewGuid()+".counter");adapter=Fake("failSecond",counter,size:2);
        await Reject("malformedResponse",()=>adapter.ComputeAsync(jobs,1,()=>1),"later-batch-failure");Check(adapter.AcceptedFrames==1 && adapter.PublishedCalls==0,"no-partial-publication");Clean(adapter,"failed-chunk");
        foreach(string mode in new[]{"malformed","missingHeader","missing","duplicate","extra","order","version","source","request","duplicateMember","nonzero","oversize","emptyValue"}) {
            adapter=Fake(mode);await Reject(mode switch{"version"=>"versionMismatch","source"=>"sourceMismatch","request"=>"requestIDMismatch","nonzero"=>"nonzeroExit","oversize"=>"outputLimit","duplicateMember"=>"duplicateMember","duplicate" or "order"=>"resultIDMismatch","missing" or "extra"=>"resultCountMismatch","emptyValue"=>"malformedResult",_=>"malformedResponse"},()=>adapter.ComputeAsync(jobs[..2],1,()=>1),"protocol-"+mode);
            Check(adapter.PublishedCalls==0,"failed-not-published-"+mode);Clean(adapter,"fixture");
        }
        adapter=new DateAdapter(Host+".missing",Source);await Reject("startFailed",()=>adapter.ComputeAsync(jobs[..1],1,()=>1),"start-failure");
        string naked=Path.Combine(Base,"evidence","no-runtime");Directory.CreateDirectory(naked);File.Copy(Host,Path.Combine(naked,"DateHost.exe"),true);
        adapter=new DateAdapter(Path.Combine(naked,"DateHost.exe"),Source);await Reject("dependencyMissing",()=>adapter.ComputeAsync(jobs[..1],1,()=>1),"missing-side-by-side-runtime");Clean(adapter,"missing-dependency");
        adapter=new DateAdapter(Host,Source with{Sha256=new string('0',64)});await Reject("sourceMismatch",()=>adapter.ComputeAsync(jobs[..1],1,()=>1),"built-source-not-caller-controlled");Clean(adapter,"source-check");
        int revision=1;adapter=Real();adapter.CalculationStarted+=()=>Volatile.Write(ref revision,2);
        await Reject("staleRevision",()=>adapter.ComputeAsync(Enumerable.Range(0,3000).Select(i=>Job("s"+i,"normalize")).ToArray(),1,()=>Volatile.Read(ref revision)),"revision-during-computation");Check(adapter.PublishedCalls==0,"stale-not-published");Clean(adapter,"stale");
        using(var cancel=new CancellationTokenSource()) {
            adapter=Real();bool marked=false;adapter.CalculationStarted+=()=>{marked=true;cancel.CancelAfter(50);};
            await Reject("canceled",()=>adapter.ComputeAsync(Enumerable.Range(0,3000).Select(i=>Job("c"+i,"normalize")).ToArray(),1,()=>1,cancel.Token),"in-computation-cancel");Check(marked&&adapter.AcceptedFrames==0&&adapter.PublishedCalls==0,"cancel-after-marker-no-response");Clean(adapter,"canceled");
        }
        adapter=Real(timeout:500);bool timeoutMarked=false;adapter.CalculationStarted+=()=>timeoutMarked=true;
        await Reject("timeout",()=>adapter.ComputeAsync(Enumerable.Range(0,3000).Select(i=>Job("t"+i,"normalize")).ToArray(),1,()=>1),"in-computation-timeout");Check(timeoutMarked&&adapter.AcceptedFrames==0&&adapter.PublishedCalls==0,"timeout-after-marker-no-response");Clean(adapter,"timeout");
        adapter=Fake("noRead",timeout:150);await Reject("timeout",()=>adapter.RawAsync(new string('x',500000),"send"),"send-timeout");Clean(adapter,"send-timeout");
        int childPid=0;adapter=Fake("tree",timeout:1000);adapter.Diagnostic+=text=>{var match=System.Text.RegularExpressions.Regex.Match(text,@"CHILD_PID=(\d+)");if(match.Success)childPid=int.Parse(match.Groups[1].Value);};
        await Reject("timeout",()=>adapter.ComputeAsync(jobs[..1],1,()=>1),"tree-timeout");Clean(adapter,"tree-parent");
        Check(childPid!=0,"child-pid-recorded");try{using var child=Process.GetProcessById(childPid);Check(child.HasExited,"descendant-exited");}catch(ArgumentException){Check(true,"descendant-exited");}
    }
    static async Task Fixture(string mode,string counter)
    {
        if(mode=="noRead"){await Task.Delay(60000);return;}
        string input=await Console.In.ReadToEndAsync();using var doc=JsonDocument.Parse(input);var root=doc.RootElement;
        if(mode=="tree") {using var child=Process.Start(new ProcessStartInfo(Environment.ProcessPath!,$"\"{typeof(Program).Assembly.Location}\" --fixture noRead \"{Base}\" \"\""){UseShellExecute=false,CreateNoWindow=true});Console.Error.WriteLine("CHILD_PID="+child!.Id);await Task.Delay(60000);return;}
        if(mode=="nonzero"){Environment.Exit(17);return;}
        if(mode=="oversize"){Console.Write(new string('x',DateAdapter.MaxBytes+1));await Task.Delay(60000);return;}
        if(mode=="failSecond"){int count=File.Exists(counter)?int.Parse(File.ReadAllText(counter)):0;File.WriteAllText(counter,(count+1).ToString());if(count==1){Console.Write("{");return;}}
        if(mode=="malformed"){Console.Write("{");return;}
        var results=root.GetProperty("items").EnumerateArray().Select(item=>new DateResult(item.GetProperty("id").GetString()!,[item.GetProperty("text").GetString()!],null)).ToList();
        if(mode=="missing")results.RemoveAt(results.Count-1);
        if(mode=="duplicate")results[1]=results[0];
        if(mode=="extra")results.Add(new("extra",["2024:01:01 00:00:00"],null));
        if(mode=="order")results.Reverse();
        if(mode=="emptyValue")results[0]=results[0] with{Values=[""]};
        var frame=new Frame(mode=="version"?"wrong":"date-isolated-v1",mode=="request"?"wrong":root.GetProperty("id").GetString()!,mode=="source"?Source with{Sha256="wrong"}:Source,results.ToArray(),0,null);
        string json=JsonSerializer.Serialize(frame,DateAdapter.Json);
        if(mode=="missingHeader"){using var parsed=JsonDocument.Parse(json);json=JsonSerializer.Serialize(parsed.RootElement.EnumerateObject().Where(p=>p.Name!="computeMs").ToDictionary(p=>p.Name,p=>p.Value.Clone()));}
        if(mode=="duplicateMember")json=json.Insert(1,"\"version\":\"date-isolated-v1\",");
        Console.Write(json);
    }
    public static async Task<int> Main(string[] args)
    {
        // Minimal transport fixture for the isolated real-window checks; never used by production DateHost.
        if(args.Length==0){await Console.In.ReadToEndAsync();if(File.Exists(Path.Combine(AppContext.BaseDirectory,"fixture-hang")))await Task.Delay(60000);else Console.Write("{");return 0;}
        if(args[0]=="--fixture")Base=args[2];else Base=Path.GetFullPath(args[0]);
        using(var source=JsonDocument.Parse(File.ReadAllText(Path.Combine(Base,"source-lock.json")))) {var value=source.RootElement;Source=new(value.GetProperty("commit").GetString()!,value.GetProperty("path").GetString()!,value.GetProperty("sha256").GetString()!);}
        if(args[0]=="--fixture"){await Fixture(args[1],args[3]);return 0;}
        Host=Path.Combine(Base,"bin","DateHost.exe");
        try {await Cases();await Transport();File.WriteAllText(Path.Combine(Base,"check-results.json"),JsonSerializer.Serialize(new{passed=Passed,evidence=Evidence},new JsonSerializerOptions{WriteIndented=true}));Console.WriteLine("CHECKS_PASSED="+Passed);return 0;}
        catch(Exception error){File.WriteAllText(Path.Combine(Base,"evidence","failed-check.json"),JsonSerializer.Serialize(new{passed=Passed,error=error.ToString(),evidence=Evidence},new JsonSerializerOptions{WriteIndented=true}));Console.Error.WriteLine(error);return 1;}
    }
}
