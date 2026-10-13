using System.Text.Json;
using System.Text.Json.Nodes;
using PhotoTrail.Windows;

static partial class Program
{
    static async Task ProjectionCases()
    {
        using var fixture=JsonDocument.Parse(File.ReadAllText(Path.Combine(Base,"evidence","date-projection-v2.json")));
        var entries=fixture.RootElement.GetProperty("entries").EnumerateArray().ToArray();
        Check(entries.Length==38,"projection-fixture-count");
        var jobs=entries.Select(e=>Job(e.GetProperty("id").GetString()!,"project",e.GetProperty("input").GetString()!)).ToArray();
        var adapter=Real();var results=await adapter.ComputeAsync(jobs,0,()=>0);
        for(int i=0;i<entries.Length;i++) {
            var e=entries[i];var actual=results[i];bool matches;
            if(e.TryGetProperty("error",out var error))matches=actual.Error is {Scope:"business"} && actual.Error.Code==error.GetString() && actual.Projection is null;
            else {
                var expected=e.GetProperty("expected");var p=actual.Projection;
                matches=p is not null && p.Text==jobs[i].Item.Text && p.Kind==expected.GetProperty("kind").GetString() &&
                    p.Seconds==expected.GetProperty("seconds").GetInt64() && p.Nanoseconds==expected.GetProperty("nanoseconds").GetInt32() &&
                    p.OffsetMinutes==(expected.TryGetProperty("offsetMinutes",out var offset)?offset.GetInt32():(int?)null);
            }
            Evidence.Add(new{projectionVector=jobs[i].Item.Id,input=jobs[i].Item.Text,reference=e.Clone(),actual});
            Check(matches,"projection-"+jobs[i].Item.Id);
        }
        Clean(adapter,"projection-vectors");
        foreach(string suffix in new[]{"\n","\r","\r\n"}) {
            var r=await Real().ComputeAsync([Job("newline","project","1970:01:01 00:00:00Z"+suffix)],0,()=>0);
            Check(r[0].Error?.Code=="dateInput","project-real-newline-rejected");
        }
        foreach(string extra in new[]{",\"seconds\":0",",\"zone\":null",",\"text\":\"1970:01:01 00:00:00Z\""}) {
            string raw="{\"version\":\"date-core-v2\",\"id\":\"raw\",\"items\":[{\"id\":\"p\",\"op\":\"project\",\"text\":\"1970:01:01 00:00:00Z\""+extra+"}]}";
            await Reject(extra.StartsWith(",\"text")?"parameter:duplicateMember":"parameter:unknownMember",()=>Real().RawAsync(raw,"raw"),"project-request-shape");
        }
        foreach(string mode in new[]{"seconds-decimal","seconds-exponent","seconds-overflow","seconds-null","nano-negative","nano-large","nano-wrong","nano-decimal","offset-null","offset-wrong","offset-large","kind-wrong","text-wrong","unknown","missing","duplicate","values","error-null","wall-offset","instant-missing"}) {
            adapter=Fake("projection-"+mode);
            string text=mode=="wall-offset"?"1970:01:01 00:00:00.1":"1970:01:01 00:00:00.1Z";
            try { await adapter.ComputeAsync([Job("p","project",text)],0,()=>0);throw new Exception("accepted projection fault "+mode); }
            catch(DateFailure failure){Check(adapter.PublishedCalls==0,"project-fault-"+mode+":"+failure.Code);}
            Clean(adapter,"projection-fault");
        }
        // Exact two-direction protocol mismatch using the retained real R01b host.
        string? old=Environment.GetEnvironmentVariable("PHOTOTRAIL_PROJECTION_OLD_HOST");
        if(old is not null) {
            var oldSource=new SourceIdentity("63fb9404ec5f0862df90a000f5dd1c4b81509900",Source.Path,"593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc");
            await Reject("versionMismatch",()=>new DateAdapter(old,Source).ComputeAsync([Job("p","project")],0,()=>0),"v2-client-v1-host");
            await Reject("versionMismatch",()=>new DateAdapter(Host,oldSource,"date-isolated-v1").ComputeAsync([Job("p","normalize")],0,()=>0),"v1-client-v2-host");
        }
        using var cancellation=new CancellationTokenSource();adapter=Real();bool marked=false;
        adapter.CalculationStarted+=()=>{marked=true;cancellation.Cancel();};
        await Reject("canceled",()=>adapter.ComputeAsync(Enumerable.Range(0,3000).Select(i=>Job("p"+i,"project","1500:02:29 00:00:00.123456789Z")).ToArray(),0,()=>0,cancellation.Token),"project-compute-cancel");
        Check(marked && adapter.AcceptedFrames==0 && adapter.PublishedCalls==0,"project-marker-before-response");Clean(adapter,"project-cancel");
    }
    static async Task ProjectionFixture(string mode)
    {
        var request=JsonNode.Parse(await Console.In.ReadToEndAsync())!;var item=request["items"]![0]!;
        string text=item["text"]!.GetValue<string>();
        var p=new JsonObject{["text"]=text,["kind"]=text.EndsWith('Z')?"instant":"wall",["seconds"]=0,["nanoseconds"]=100000000};
        if(text.EndsWith('Z'))p["offsetMinutes"]=0;
        var result=new JsonObject{["id"]=item["id"]!.GetValue<string>(),["projection"]=p};
        switch(mode[11..]) {
            case "seconds-decimal":p["seconds"]=JsonNode.Parse("0.0");break;
            case "seconds-exponent":p["seconds"]=JsonNode.Parse("0e0");break;
            case "seconds-overflow":p["seconds"]=JsonNode.Parse("9223372036854775808");break;
            case "seconds-null":p["seconds"]=null;break;
            case "nano-negative":p["nanoseconds"]=-1;break;
            case "nano-large":p["nanoseconds"]=1000000000;break;
            case "nano-wrong":p["nanoseconds"]=1;break;
            case "nano-decimal":p["nanoseconds"]=JsonNode.Parse("100000000.0");break;
            case "offset-null":p["offsetMinutes"]=null;break;
            case "offset-wrong":p["offsetMinutes"]=60;break;
            case "offset-large":p["offsetMinutes"]=841;break;
            case "kind-wrong":p["kind"]="wall";break;
            case "text-wrong":p["text"]="1970:01:01 00:00:00.100Z";break;
            case "unknown":p["extra"]=0;break;
            case "missing":p.Remove("seconds");break;
            case "values":result["values"]=new JsonArray(text);break;
            case "error-null":result["error"]=null;break;
            case "wall-offset":p["offsetMinutes"]=0;break;
            case "instant-missing":p.Remove("offsetMinutes");break;
        }
        var frame=new JsonObject{["version"]="date-core-v2",["source"]=JsonSerializer.SerializeToNode(Source,DateAdapter.Json),["id"]=request["id"]!.GetValue<string>(),["results"]=new JsonArray(result),["computeMs"]=0};
        string output=frame.ToJsonString();if(mode=="projection-duplicate")output=output.Replace("\"seconds\":0","\"seconds\":0,\"seconds\":0");Console.Write(output);
    }
}
