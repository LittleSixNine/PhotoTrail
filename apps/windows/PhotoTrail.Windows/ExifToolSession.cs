using System.Diagnostics;
using System.IO;
using System.Numerics;
using System.Text;

namespace PhotoTrail.Windows;

// A batch owns one worker. File proofs, write staging and rereads remain per request.
internal sealed class ExifToolSession(string executable,Action closed) : IAsyncDisposable
{
    readonly SemaphoreSlim gate=new(1,1);
    Process? process;
    bool disposed;
    internal async Task<string> RunAsync(IEnumerable<string> arguments,CancellationToken cancellation,TimeSpan? timeout,bool rejectWarnings) {
        var args=arguments.ToArray();
        if(args.Any(a=>a.IndexOfAny(['\r','\n','\0'])>=0))throw new ArgumentException("工具参数不能包含换行或NUL；多行元数据通过值文件传递。");
        if(args.Any(a=>a.StartsWith("-execute",StringComparison.OrdinalIgnoreCase)||a is "-stay_open" or "-@" or "-echo3" or "-echo4"))throw new ArgumentException("请求不能改变元数据会话协议。");
        int boundary=Array.IndexOf(args,"--");
        // -- also disables ExifTool's execute delimiter. Absolute paths cannot become options.
        if(boundary>=0){if(args.Skip(boundary+1).Any(a=>!Path.IsPathFullyQualified(a)))throw new ArgumentException("会话文件参数必须为绝对路径。");args=args.Where((_,i)=>i!=boundary).ToArray();}
        await gate.WaitAsync(cancellation);
        try {
            ObjectDisposedException.ThrowIf(disposed,this);cancellation.ThrowIfCancellationRequested();
            using var deadline=CancellationTokenSource.CreateLinkedTokenSource(cancellation);deadline.CancelAfter(timeout??TimeSpan.FromSeconds(30));
            try {
                if(process is null){
                    var info=new ProcessStartInfo(executable){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardInputEncoding=new UTF8Encoding(false),StandardOutputEncoding=new UTF8Encoding(false,true),StandardErrorEncoding=Encoding.UTF8};
                    foreach(var key in new[]{"LC_ALL","LC_CTYPE","LANG"})info.Environment[key]="C";
                    foreach(var arg in new[]{"-stay_open","True","-@","-"})info.ArgumentList.Add(arg);
                    process=Process.Start(info)??throw new IOException("无法启动元数据工具。");Interlocked.Increment(ref ExifToolClient.StartedProcesses);
                }
                string id=new BigInteger(Guid.NewGuid().ToByteArray(),isUnsigned:true).ToString(System.Globalization.CultureInfo.InvariantCulture),marker="PhotoTrail-status-"+id+":";
                var output=ReadUntil(process.StandardOutput,"{ready"+id+"}",deadline.Token);
                var error=ReadUntil(process.StandardError,marker,deadline.Token,status:true);
                Interlocked.Increment(ref ExifToolClient.RequestCount);
                foreach(var arg in new[]{"-echo4",marker+"${status}"}.Concat(args).Append("-execute"+id))await process.StandardInput.WriteLineAsync(arg.AsMemory(),deadline.Token);
                await process.StandardInput.FlushAsync(deadline.Token);await Task.WhenAll(output,error);
                string stderr=await error;int separator=stderr.LastIndexOf('\n');string code=stderr[(separator+1)..];stderr=separator<0?"":stderr[..separator];
                if(code!="0")throw new IOException("元数据工具失败（"+code+"）："+stderr.Trim());
                if(rejectWarnings&&stderr.Trim().Length>0)throw new IOException("IPTC工具警告，拒绝交付："+stderr.Trim());
                return await output;
            }catch {
                // A canceled/failed protocol is never reused. Only this owned metadata worker is stopped.
                if(process is not null){if(!process.HasExited)process.Kill(entireProcessTree:true);await process.WaitForExitAsync();process.Dispose();process=null;}
                if(deadline.IsCancellationRequested&&!cancellation.IsCancellationRequested)throw new TimeoutException("元数据工具读取超时。");
                throw;
            }
        }finally{gate.Release();}
    }
    static async Task<string> ReadUntil(StreamReader reader,string marker,CancellationToken token,bool status=false) {
        var text=new StringBuilder();
        while(await reader.ReadLineAsync(token)is {} line){
            if(status?line.StartsWith(marker,StringComparison.Ordinal):line==marker)return status?text+line[marker.Length..]:text.ToString();
            text.Append(line).Append('\n');if(text.Length>32*1024*1024)throw new InvalidDataException("元数据工具输出超过32MiB；未交付结果。");
        }
        throw new IOException("元数据工具会话提前结束，未确认本次结果。");
    }
    public async ValueTask DisposeAsync(){
        await gate.WaitAsync();try{if(disposed)return;disposed=true;closed();if(process is null)return;
            using var stop=new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try{await process.StandardInput.WriteLineAsync("-stay_open\nFalse".AsMemory(),stop.Token);await process.StandardInput.FlushAsync(stop.Token);process.StandardInput.Close();await process.WaitForExitAsync(stop.Token);}
            catch{if(!process.HasExited)process.Kill(entireProcessTree:true);await process.WaitForExitAsync();}
            finally{process.Dispose();process=null;}
        }finally{gate.Release();}
    }
}
