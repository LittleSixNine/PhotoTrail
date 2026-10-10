using System.IO;
using System.Text;
using System.Security.Cryptography;
using System.Text.Json;
namespace PhotoTrail.Windows;
public static class TrackHistory
{
    public const int MaximumBytes = 128 * 1024;
    public static string DefaultPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "Windows", "recent-tracks.json");
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
