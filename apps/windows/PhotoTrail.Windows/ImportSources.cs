using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PhotoTrail.Windows;

internal sealed record ImportSource(string Path,FileIdentity Identity,long Length,DateTime Created,DateTime Written,long Changed)
{
    [StructLayout(LayoutKind.Sequential)]struct Information {public uint Attributes;public System.Runtime.InteropServices.ComTypes.FILETIME Created,Accessed,Written;public uint Volume,SizeHigh,SizeLow,Links,High,Low;}
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle file,out Information information);
    [StructLayout(LayoutKind.Sequential)]struct BasicInformation{public long Created,Accessed,Written,Changed;public uint Attributes;}
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandleEx(SafeFileHandle file,int informationClass,out BasicInformation information,uint size);
    internal static ImportSource Read(string path)
    {
        path=System.IO.Path.GetFullPath(path);
        if(System.IO.Path.GetPathRoot(path) is not {Length:3} drive||drive[1]!=':'||new DriveInfo(drive).DriveType!=DriveType.Fixed)throw new IOException("网络／设备／非固定卷导入未验，未接纳。");
        using var parents=SavePaths.LockParents(path,true);
        if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("链接文件不接纳。");
        using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(!GetFileInformationByHandle(file.SafeFileHandle,out var info)||info.Links<1)throw new IOException("不能证明文件身份，未接纳。");
        if(!GetFileInformationByHandleEx(file.SafeFileHandle,0,out var basic,(uint)Marshal.SizeOf<BasicInformation>()))throw new IOException("实际文件版本不可读取，未接纳。");
        return new(path,new(info.Volume,info.High,info.Low),file.Length,DateTime.FromFileTimeUtc(basic.Created),DateTime.FromFileTimeUtc(basic.Written),basic.Changed);
    }
    internal void RequireCurrent(){if(Read(Path)!=this)throw new IOException("枚举／读取／接纳之间来源版本改变，未接纳。");}
    internal static readonly Dictionary<string,string> Types=new(StringComparer.OrdinalIgnoreCase){[".jpg"]="JPEG",[".jpeg"]="JPEG",[".png"]="PNG",[".heic"]="HEIC",[".dng"]="DNG",[".tif"]="TIFF",[".tiff"]="TIFF",[".xmp"]="XMP",[".arw"]="ARW",[".nef"]="NEF",[".raf"]="RAF",[".cr2"]="CR2",[".cr3"]="CR3",[".rw2"]="RW2",[".orf"]="ORF",[".pef"]="PEF"};
    internal static bool Raw(string type)=>type is "DNG" or "ARW" or "NEF" or "RAF" or "CR2" or "CR3" or "RW2" or "ORF" or "PEF";
    internal static string Stem(string path)=>System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path)!,System.IO.Path.GetFileNameWithoutExtension(path));
}

// Waiting paths are bounded separately from the session's deduplication identities.
internal sealed class ImportQueue : IDisposable
{
    internal const int Capacity=64, BatchSize=16, MaximumFiles=100000;
    readonly object sync=new();readonly List<ImportSource> waiting=[];readonly SemaphoreSlim slots=new(Capacity);
    bool complete;string? priority;
    internal int Discovered,Skipped,DirectoryFailures,FileFailures;internal readonly List<string> Errors=[];
    internal readonly Dictionary<string,string> KnownFailures=new(StringComparer.OrdinalIgnoreCase);
    internal bool Paused {get;set;}
    internal bool EnumerationComplete {get{lock(sync)return complete;}}
    internal ImportSource[] Waiting {get{lock(sync)return waiting.ToArray();}}
    internal void Prioritize(string? path){lock(sync)priority=path;}
    internal void Error(string text,bool directory){lock(sync){if(directory)DirectoryFailures++;else FileFailures++;if(Errors.Count<50)Errors.Add(text);}}
    internal async Task Enqueue(ImportSource source,CancellationToken token){await slots.WaitAsync(token);lock(sync){waiting.Add(source);Discovered++;}}
    internal async Task<ImportSource[]> TakeAsync(CancellationToken token)
    {
        while(true){token.ThrowIfCancellationRequested();lock(sync){if(waiting.Count>0&&!Paused){var ordered=waiting.OrderByDescending(s=>s.Path.Equals(priority,StringComparison.OrdinalIgnoreCase)).Take(BatchSize).ToArray();foreach(var s in ordered){waiting.Remove(s);slots.Release();}return ordered;}if(complete&&waiting.Count==0)return [];}
            await Task.Delay(30,token);
        }
    }
    internal async Task EnumerateAsync(IEnumerable<string> inputs,bool recursive,IEnumerable<string> known,CancellationToken token,IReadOnlyDictionary<string,FileIdentity>? remembered=null)
    {
        var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var identities=new HashSet<FileIdentity>();var directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try{
            foreach(var path in known){try{var source=ImportSource.Read(path);paths.Add(source.Path);identities.Add(source.Identity);}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error("既有来源身份不可重核；旧快照保留："+e.Message,false);KnownFailures[path]=e.Message;paths.Add(System.IO.Path.GetFullPath(path));if(remembered?.TryGetValue(path,out var identity)==true)identities.Add(identity);else throw new IOException("既有来源物理身份未知，不能证明新增目标唯一性，本次停止。",e);}}
            foreach(var input in inputs){token.ThrowIfCancellationRequested();foreach(var file in Walk(input,0)){
                token.ThrowIfCancellationRequested();if(paths.Count>=MaximumFiles)throw new IOException("本次身份集合超过100000项资源上限，停止枚举；已接纳保留。");
                var extension=System.IO.Path.GetExtension(file);if(!ImportSource.Types.ContainsKey(extension)){Interlocked.Increment(ref Skipped);continue;}
                ImportSource? source=null;try{source=ImportSource.Read(file);if(!paths.Add(source.Path)||!identities.Add(source.Identity)){Interlocked.Increment(ref Skipped);source=null;}}catch(Exception e)when(e is IOException or UnauthorizedAccessException or ArgumentException){Error(System.IO.Path.GetFileName(file)+"："+e.Message,false);}
                if(source is not null)await Enqueue(source,token);
            }}
        }finally{lock(sync){complete=true;}}
        IEnumerable<string> Walk(string input,int depth)
        {
            string? full=null;FileAttributes attributes=default;
            try{full=System.IO.Path.GetFullPath(input);attributes=File.GetAttributes(full);if((attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("重解析点／链接跳过，不跟随。");if(depth>128||directories.Count>=MaximumFiles)throw new IOException("目录深度／数量超过资源上限。");}
            catch(Exception e)when(e is IOException or UnauthorizedAccessException or ArgumentException){full=null;Error(System.IO.Path.GetFileName(input)+"："+e.Message,true);}
            if(full is null)yield break;
            if((attributes&FileAttributes.ReparsePoint)!=0)yield break;
            if((attributes&FileAttributes.Directory)==0){yield return full;yield break;}
            if(!directories.Add(full))yield break;
            var drive=System.IO.Path.GetPathRoot(full);if(drive is not {Length:3}||drive[1]!=':'||new DriveInfo(drive).DriveType!=DriveType.Fixed){Error("网络／设备目录未验，未枚举。",true);yield break;}
            IEnumerator<string>? iterator=null;try{iterator=Directory.EnumerateFileSystemEntries(full).GetEnumerator();}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error(System.IO.Path.GetFileName(full)+"："+e.Message,true);}
            if(iterator is null)yield break;
            using(iterator){while(true){token.ThrowIfCancellationRequested();bool next=false;try{next=iterator.MoveNext();}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error(System.IO.Path.GetFileName(full)+"："+e.Message,true);}if(!next)break;var child=iterator.Current;bool directory=false;try{directory=(File.GetAttributes(child)&FileAttributes.Directory)!=0;}catch(Exception e)when(e is IOException or UnauthorizedAccessException){Error(System.IO.Path.GetFileName(child)+"："+e.Message,false);continue;}
                if(directory&&!recursive){Interlocked.Increment(ref Skipped);continue;}foreach(var path in Walk(child,depth+1))yield return path;
            }}
        }
    }
    public void Dispose()=>slots.Dispose();
}
