using System.Windows.Media.Imaging;

namespace PhotoTrail.Windows;

internal sealed record ThumbnailKey(string Path,string Hash,string Version,int Orientation,int Pixels,double Dpi,bool Preview);
internal sealed class ThumbnailLoader
{
    internal const int MaximumItems=384;internal const long MaximumBytes=64L*1024*1024;
    sealed class Job(ThumbnailKey key,Func<Task<BitmapSource>> load){internal ThumbnailKey Key=key;internal Func<Task<BitmapSource>> Load=load;internal TaskCompletionSource<BitmapSource> Completion=new(TaskCreationOptions.RunContinuationsAsynchronously);internal int Consumers;internal bool Started;}
    sealed record Entry(BitmapSource Image,long Bytes,long Used);
    readonly object sync=new();readonly Dictionary<ThumbnailKey,Job> jobs=[];readonly Dictionary<ThumbnailKey,Entry> cache=[];int running;long clock;
    internal int Decodes,PeakConcurrent,Coalesced,CancelledWaiting,CacheHits;
    internal (int SmallItems,long SmallBytes,int PreviewItems,long PreviewBytes,int Running,int Waiting) Statistics {get{lock(sync)return(cache.Count(p=>!p.Key.Preview),cache.Where(p=>!p.Key.Preview).Sum(p=>p.Value.Bytes),cache.Count(p=>p.Key.Preview),cache.Where(p=>p.Key.Preview).Sum(p=>p.Value.Bytes),running,jobs.Values.Count(j=>!j.Started));}}
    internal static int Pixels(double logical,double dpi,bool strip)=>strip?new[]{160,256,384,512,768,1024}.FirstOrDefault(n=>n>=Math.Ceiling(logical*dpi),1024):Math.Clamp((int)Math.Ceiling(80*dpi),80,1024);
    internal async Task<BitmapSource> GetAsync(ThumbnailKey key,Func<Task<BitmapSource>> load,CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        Job job;lock(sync){if(cache.TryGetValue(key,out var entry)){cache[key]=entry with{Used=++clock};CacheHits++;return entry.Image;}if(jobs.TryGetValue(key,out job!))Coalesced++;else {job=new(key,load);jobs.Add(key,job);}job.Consumers++;Pump();}
        try{return await job.Completion.Task.WaitAsync(token);}finally{lock(sync){job.Consumers--;if(job.Consumers==0&&!job.Started){jobs.Remove(key);job.Completion.TrySetCanceled();CancelledWaiting++;}Pump();}}
    }
    void Pump()
    {
        while(running<2){var job=jobs.Values.Where(j=>!j.Started&&j.Consumers>0).OrderByDescending(j=>j.Key.Preview).FirstOrDefault();if(job is null)return;job.Started=true;running++;PeakConcurrent=Math.Max(PeakConcurrent,running);_ = Task.Run(()=>Run(job));}
    }
    async Task Run(Job job)
    {
        try{var image=await job.Load();if(!image.IsFrozen)image.Freeze();lock(sync){Decodes++;long bytes=checked(((long)image.PixelWidth*Math.Max(32,image.Format.BitsPerPixel)+7)/8*image.PixelHeight*2);if(bytes<=MaximumBytes){cache[job.Key]=new(image,bytes,++clock);while(cache.Count(p=>p.Key.Preview==job.Key.Preview)>MaximumItems||cache.Where(p=>p.Key.Preview==job.Key.Preview).Sum(p=>p.Value.Bytes)>MaximumBytes){var oldest=cache.Where(p=>p.Key.Preview==job.Key.Preview).MinBy(p=>p.Value.Used);cache.Remove(oldest.Key);}}}job.Completion.TrySetResult(image);}
        catch(Exception error){job.Completion.TrySetException(error);}
        finally{lock(sync){jobs.Remove(job.Key);running--;Pump();}}
    }
}
