using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Text.Json;
namespace PhotoTrail.Windows;
public static class TrackHistory
{
    public const int MaximumBytes = 128 * 1024;
    public static string DefaultPath => Environment.GetEnvironmentVariable("PHOTOTRAIL_TRACK_HISTORY")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "Windows", "recent-tracks.json");
    private static string[] Validate(IEnumerable<string> paths)
    {
        var list = paths.ToArray();
        if (list.Length > 20 || list.Any(path => path.Length is < 1 or > 2048 || path.Any(char.IsControl) || !Path.IsPathFullyQualified(path) || Path.GetExtension(path).ToLowerInvariant() is not (".gpx" or ".kml" or ".kmz"))) throw new InvalidDataException("轨迹历史路径无效。");
        var full = list.Select(Path.GetFullPath).ToArray();
        if (full.Distinct(StringComparer.OrdinalIgnoreCase).Count() != full.Length) throw new InvalidDataException("轨迹历史路径重复。");
        return full;
    }
    public static string[] Read(string file)
    {
        if (!File.Exists(file)) return [];
        using var input = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (input.Length > MaximumBytes) throw new InvalidDataException("轨迹历史超过128KiB上限。");
        using var reader = new StreamReader(input, new UTF8Encoding(false,true), detectEncodingFromByteOrderMarks:true);
        var paths = JsonSerializer.Deserialize<string[]>(reader.ReadToEnd()) ?? throw new InvalidDataException("轨迹历史格式无效。");
        if (paths.Any(path => path is null)) throw new InvalidDataException("轨迹历史路径缺失。");
        return Validate(paths);
    }
    public static string[] Remember(IEnumerable<string> existing, string path) => Validate(new[] { Path.GetFullPath(path) }.Concat(existing.Where(item => !Path.GetFullPath(item).Equals(Path.GetFullPath(path),StringComparison.OrdinalIgnoreCase))).Take(20));
    public static string[] RememberAndSave(string file, string path)
    {
        file = Path.GetFullPath(file);
        // shortcut: separate Windows sessions do not share this mutex; use a file lock if histories span sessions.
        var name = "Local\\PhotoTrail.TrackHistory." + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(file.ToUpperInvariant())));
        using var gate = new Mutex(false, name);
        var acquired = false;
        try
        {
            try { acquired = gate.WaitOne(TimeSpan.FromSeconds(5)); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) throw new IOException("另一实例正在保存轨迹历史，请稍后重试。");
            var updated = Remember(Read(file), path);
            Save(file, updated);
            return updated;
        }
        finally { if (acquired) gate.ReleaseMutex(); }
    }
    public static void Save(string file, IEnumerable<string> paths)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(Validate(paths));
        if (bytes.Length > MaximumBytes) throw new InvalidDataException("轨迹历史超过128KiB上限。");
        var folder = Path.GetDirectoryName(Path.GetFullPath(file))!; Directory.CreateDirectory(folder);
        var temporary = Path.Combine(folder, ".recent-tracks-" + Guid.NewGuid().ToString("N"));
        try
        {
            using (var output = new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { output.Write(bytes); output.Flush(true); }
            if (File.Exists(file)) File.Replace(temporary,file,destinationBackupFileName:null);
            else File.Move(temporary,file);
        }
        finally { if(File.Exists(temporary))File.Delete(temporary); }
    }
}

public sealed record TrackSnapshot(string Path,string SourceHash,TrackData Data,TrackData? Original=null);
public static class TrackSnapshots
{
    sealed record Archive(int Version,TrackSnapshot[] Records);
    public static string DefaultPath=>TrackHistory.DefaultPath+".adjustments-v1.json";
    const int MaximumBytes=128*1024*1024;
    public static TrackSnapshot[] Read(string file)
    {
        if(!File.Exists(file))return [];
        using var input=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read|FileShare.Delete);
        if(input.Length>MaximumBytes)throw new InvalidDataException("轨迹调整记录过大，未覆盖。");
        var archive=JsonSerializer.Deserialize<Archive>(input,new JsonSerializerOptions{AllowDuplicateProperties=false,RespectRequiredConstructorParameters=true,UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow})??throw new InvalidDataException("轨迹调整记录损坏，未覆盖。");
        if(archive.Version!=1||archive.Records is null||archive.Records.Any(r=>r is null)||archive.Records.Select(r=>r.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=archive.Records.Length)throw new InvalidDataException("轨迹调整记录无效，未覆盖。");
        foreach(var record in archive.Records){if(!System.IO.Path.IsPathFullyQualified(record.Path)||record.SourceHash.Length!=64||record.SourceHash.Any(c=>!Uri.IsHexDigit(c)))throw new InvalidDataException("轨迹调整来源无效。");_=TrackAdjustment.Adjust(record.Data,0,0,0);if(record.Original is {} original)_=TrackAdjustment.Adjust(original,0,0,0);}
        return archive.Records;
    }
    public static async Task<TrackSnapshot> ReadSourceAsync(string path,CancellationToken token=default)
    {
        path=System.IO.Path.GetFullPath(path);
        using var guard=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        string hash=Convert.ToHexString(await SHA256.HashDataAsync(guard,token));
        var data=await Task.Run(()=>TrackReader.Read(path,token),token);
        return new(path,hash,data);
    }
    public static async Task EnsureSourceAsync(TrackSnapshot record,CancellationToken token=default)
    {
        if(await PhotoDocument.HashAsync(record.Path,token)!=record.SourceHash)throw new IOException("原轨迹已变化，请显式恢复原轨迹后重新调整或匹配。");
    }
    public static async Task SaveAsync(string file,TrackSnapshot updated,TrackSnapshot expected,CancellationToken token=default)
    {
        // Keep the source read-locked through persistence; a failed commit never replaces the effective in-memory track.
        using var guard=new FileStream(updated.Path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(Convert.ToHexString(await SHA256.HashDataAsync(guard,token))!=updated.SourceHash)throw new IOException("原轨迹已变化，请恢复原轨迹。");
        await Task.Run(()=>{
            using var gate=new Mutex(false,"Local\\PhotoTrail.TrackAdjustments."+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(file).ToUpperInvariant()))));
            bool acquired=false;
            try {
                try{acquired=gate.WaitOne(TimeSpan.FromSeconds(5));}catch(AbandonedMutexException){acquired=true;}
                if(!acquired)throw new IOException("另一实例正在保存轨迹调整。");
                var existing=Read(file);var saved=existing.FirstOrDefault(r=>r.Path.Equals(updated.Path,StringComparison.OrdinalIgnoreCase));if(saved is not null&&(saved.SourceHash!=expected.SourceHash||!TrackAdjustment.Equal(saved.Data,expected.Data)))throw new IOException("调整状态已被另一实例改变，请重新读取。");
                var records=existing.Where(r=>!r.Path.Equals(updated.Path,StringComparison.OrdinalIgnoreCase)).Append(updated).ToArray();
                var bytes=JsonSerializer.SerializeToUtf8Bytes(new Archive(1,records));if(bytes.Length>MaximumBytes)throw new IOException("轨迹调整记录过大。");
                string folder=System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(file))!;Directory.CreateDirectory(folder);string temporary=System.IO.Path.Combine(folder,".track-adjustment-"+Guid.NewGuid().ToString("N"));
                try{using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){output.Write(bytes);output.Flush(true);}token.ThrowIfCancellationRequested();if(File.Exists(file))File.Replace(temporary,file,null);else File.Move(temporary,file);}
                finally{if(File.Exists(temporary))File.Delete(temporary);}
            }finally{if(acquired)gate.ReleaseMutex();}
        },token);
    }
}
