using System.IO;
using System.Text;
using System.Text.Json;
namespace PhotoTrail.Windows;
public static class ThemePreference
{
    public static string DefaultPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "Windows", "theme.json");
    public static int Read(string file)
    {
        if (!File.Exists(file)) return 0;
        using var input = new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read);
        if (input.Length > 4096) throw new InvalidDataException("外观偏好超过4KiB上限。");
        using var reader = new StreamReader(input,new UTF8Encoding(false,true),detectEncodingFromByteOrderMarks:true);
        using var json = JsonDocument.Parse(reader.ReadToEnd());var root = json.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != 2 ||
            !root.TryGetProperty("version",out var version) || !version.TryGetInt32(out var v) || v != 1 ||
            !root.TryGetProperty("theme",out var theme) || theme.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("外观偏好结构或版本无效。");
        return theme.GetString() switch { "system" => 0, "light" => 1, "dark" => 2, _ => throw new InvalidDataException("外观偏好值无效。") };
    }
    public static void Save(string file,int mode)
    {
        var theme = mode switch { 0 => "system", 1 => "light", 2 => "dark", _ => throw new ArgumentException("外观选择无效。") };
        _ = Read(file); // Preserve a detected corrupt preference instead of silently overwriting it.
        var folder = Path.GetDirectoryName(Path.GetFullPath(file))!;Directory.CreateDirectory(folder);
        var temporary = Path.Combine(folder,".theme-"+Guid.NewGuid().ToString("N"));
        try
        {
            using (var output = new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            { output.Write(JsonSerializer.SerializeToUtf8Bytes(new { version = 1,theme }));output.Flush(true); }
            // shortcut: simultaneous instances keep the last preference; there is only one setting to merge.
            File.Move(temporary,file,overwrite:true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
