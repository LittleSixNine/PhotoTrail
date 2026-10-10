using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PhotoTrail.Windows;

public record RenameOutcome(string Source,string Target,string Current,string Hash,string State)
{
    public string OriginalName => Path.GetFileName(Source);
    public string NewName => Path.GetFileName(Current);
    public string Status => State;
}
public record RenameResult(string Journal,IReadOnlyList<RenameOutcome> Files,bool Complete,string? Error);
public static class RenameExecutor
{
    private record Entry(string Source,string Target,string Temporary,string Hash);
    private record Header(int Version,string Id,Entry[] Files);
    private record Step(int Index,int State);
    public static async Task<RenameResult> ExecuteAsync(RenamePlan plan,string journalDirectory,CancellationToken cancellation=default,Action<int,int>? progress=null)
    {
        if(plan.Files.Count is < 1 or > 6000)throw new ArgumentException("计划为空或过大。");
        var sources=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var targets=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var file in plan.Files)
        {
            if(!sources.Add(file.Source)||!targets.Add(file.Target)||Path.GetDirectoryName(file.Source)!=Path.GetDirectoryName(file.Target)||!RenamePlan.ValidName(Path.GetFileName(file.Target)))throw new ArgumentException("冻结计划边界无效。");
        }
        foreach(var file in plan.Files)
        {
            if(Path.GetExtension(file.Source).Equals(".xmp",StringComparison.OrdinalIgnoreCase)||Path.GetExtension(file.Source).Equals(".tmp",StringComparison.OrdinalIgnoreCase))continue;
            var sidecar=Path.ChangeExtension(file.Source,".xmp");
            if(File.Exists(sidecar)&&!sources.Contains(sidecar))throw new IOException("冻结后出现未纳入计划的同名旁车，未执行。");
        }
        var id=Guid.NewGuid().ToString("N");
        var entries=plan.Files.Where(file=>file.Source!=file.Target).Select((file,index)=>new Entry(file.Source,file.Target,Path.Combine(Path.GetDirectoryName(file.Source)!,$".phototrail-rename-{id}-{index}.tmp"),file.Hash)).ToArray();
        var header=new Header(1,id,entries);var states=new int[entries.Length];var locks=new Dictionary<string,FileStream>(StringComparer.OrdinalIgnoreCase);
        string? journal=null;
        try
        {
            foreach(var file in plan.Files)
            {
                cancellation.ThrowIfCancellationRequested();
                if((File.GetAttributes(file.Source)&FileAttributes.ReparsePoint)!=0)throw new IOException("源文件变为链接，未执行。");
                if(Directory.Exists(file.Target)||(File.Exists(file.Target)&&!sources.Contains(file.Target)))throw new IOException("目标在冻结后被占用，未执行。");
                var stream=WindowsRename.Open(file.Source);
                locks.Add(file.Source,stream);
                if(Convert.ToHexString(await SHA256.HashDataAsync(stream,cancellation))!=file.Hash)throw new IOException("源内容在冻结后改变，未执行。");
            }
            if(entries.Length==0)return new("",[],true,null);
            var headerBytes=Encoding.UTF8.GetBytes(JsonSerializer.Serialize(header)+"\n");
            if(headerBytes.Length>15*1024*1024)throw new ArgumentException("计划路径过长，执行记录超出恢复上限。");
            Directory.CreateDirectory(journalDirectory);journal=Path.Combine(journalDirectory,"rename-"+id+".jsonl");
            using var log=new FileStream(journal,FileMode.CreateNew,FileAccess.Write,FileShare.Read);
            void Write(object value){var bytes=Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value)+"\n");log.Write(bytes);log.Flush(true);}
            log.Write(headerBytes);log.Flush(true);
            try
            {
                for(var phase=0;phase<2;phase++)for(var index=0;index<entries.Length;index++)
                {
                    cancellation.ThrowIfCancellationRequested();var entry=entries[index];
                    states[index]=phase==0?1:3;Write(new Step(index,states[index]));
                    WindowsRename.Move(locks[entry.Source],phase==0?entry.Temporary:entry.Target);
                    states[index]++;Write(new Step(index,states[index]));
                    progress?.Invoke(phase*entries.Length+index+1,entries.Length*3);
                }
                for(var index=0;index<entries.Length;index++)
                {
                    cancellation.ThrowIfCancellationRequested();var stream=locks[entries[index].Source];stream.Position=0;
                    if(Convert.ToHexString(await SHA256.HashDataAsync(stream,cancellation))!=entries[index].Hash)throw new IOException("更名后内容核验失败；保留实际名称，须人工核对。");
                    progress?.Invoke(entries.Length*2+index+1,entries.Length*3);
                }
                Write(new Step(-1,5));
                return Result(header,states,journal,true,null);
            }
            catch(Exception error) when(error is IOException or UnauthorizedAccessException or OperationCanceledException)
            {
                return Result(header,states,journal,false,error is OperationCanceledException?"已取消；按记录恢复实际名称。":error.Message);
            }
        }
        finally{foreach(var stream in locks.Values)stream.Dispose();}
    }
    private static RenameResult Result(Header header,int[] states,string journal,bool complete,string? error)
    {
        var outcomes=header.Files.Select((entry,index)=>
        {
            var state=states[index];
            var current=state switch{0=>entry.Source,1=>File.Exists(entry.Temporary)?entry.Temporary:entry.Source,2=>entry.Temporary,3=>File.Exists(entry.Temporary)?entry.Temporary:entry.Target,_=>entry.Target};
            return new RenameOutcome(entry.Source,entry.Target,current,entry.Hash,state==4?"已更名":state==0?"未执行":"待恢复");
        }).ToArray();
        return new(journal,Array.AsReadOnly(outcomes),complete,error);
    }
    public static RenameResult ReadJournal(string path)
    {
        using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(file.Length is < 1 or > 16*1024*1024)throw new InvalidDataException("执行记录体积无效。");
        file.Seek(-1,SeekOrigin.End);var terminated=file.ReadByte()==10;file.Position=0;
        using var reader=new StreamReader(file,Encoding.UTF8,detectEncodingFromByteOrderMarks:true);
        var header=JsonSerializer.Deserialize<Header>(reader.ReadLine()??"")??throw new InvalidDataException("执行记录缺少头部。");
        if(header.Version!=1||!Guid.TryParseExact(header.Id,"N",out _)||header.Files is null||header.Files.Length is < 1 or > 6000)throw new InvalidDataException("执行记录版本或条目数无效。");
        var sources=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var targets=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for(var index=0;index<header.Files.Length;index++)
        {
            var entry=header.Files[index];
            if(entry is null||entry.Source is null||entry.Target is null||entry.Temporary is null||entry.Hash is null)throw new InvalidDataException("执行记录字段缺失。");
            var parent=Path.GetDirectoryName(entry.Source);
            if(Path.GetFullPath(entry.Source)!=entry.Source||Path.GetDirectoryName(entry.Target)!=parent||!RenamePlan.ValidName(Path.GetFileName(entry.Target))||entry.Temporary!=Path.Combine(parent!,$".phototrail-rename-{header.Id}-{index}.tmp")||entry.Hash.Length!=64||entry.Hash.Any(c=>!char.IsAsciiHexDigit(c))||!sources.Add(entry.Source)||!targets.Add(entry.Target))throw new InvalidDataException("执行记录路径或哈希边界无效。");
        }
        var states=new int[header.Files.Length];var verified=false;string? line;
        while((line=reader.ReadLine())is not null)
        {
            Step step;
            try{step=JsonSerializer.Deserialize<Step>(line)??throw new InvalidDataException("执行记录步骤无效。");}
            catch(JsonException) when(!terminated&&reader.EndOfStream){break;}
            if(step.Index==-1&&step.State==5&&states.All(s=>s==4)&&!verified){verified=true;continue;}
            if(verified)throw new InvalidDataException("核验完成后存在非法记录。");
            if(step.Index<0||step.Index>=states.Length||step.State!=states[step.Index]+1||step.State>4||(step.State==3&&states.Any(s=>s<2)))throw new InvalidDataException("执行记录顺序无效。");
            states[step.Index]=step.State;
        }
        return Result(header,states,path,verified,null);
    }
    public static async Task<RenameResult> RestoreAsync(string journal,string journalDirectory,CancellationToken cancellation=default)
    {
        var previous=ReadJournal(journal);var files=new List<RenameFile>();
        foreach(var outcome in previous.Files)
        {
            cancellation.ThrowIfCancellationRequested();
            if(!File.Exists(outcome.Current)||await PhotoDocument.HashAsync(outcome.Current,cancellation)!=outcome.Hash)throw new IOException("待恢复文件缺失或内容改变，未恢复。");
            if(outcome.Current!=outcome.Source)files.Add(new(outcome.Current,outcome.Source,outcome.Hash));
        }
        if(files.Count==0)return new(journal,[],true,null);
        return await ExecuteAsync(new(Array.AsReadOnly(files.ToArray())),journalDirectory,cancellation);
    }
}
