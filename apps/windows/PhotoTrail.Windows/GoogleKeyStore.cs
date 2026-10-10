using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace PhotoTrail.Windows;

public static class GoogleKeyStore
{
    private static readonly byte[] entropy = Encoding.UTF8.GetBytes("PhotoTrail.Windows.GoogleApiKey.v1");
    public static string DefaultPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhotoTrail", "Windows", "google-key.dat");
    private static string Validate(string value)
    {
        var key = value.Trim();
        if (key.Length is < 20 or > 256 || key.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new ArgumentException("密钥须为20至256位英文字母、数字、横线或下划线；不会联网校验。");
        return key;
    }
    public static void Save(string path, string value)
    {
        var plaintext = Encoding.UTF8.GetBytes(Validate(value));
        byte[] encrypted;
        try { encrypted = ProtectedData.Protect(plaintext, entropy, DataProtectionScope.CurrentUser); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
        var full = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        var temporary = full + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(encrypted); file.Flush(true); }
            File.Move(temporary, full, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public static string? Load(string path)
    {
        if (!File.Exists(path)) return null;
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length is < 1 or > 4096) throw new InvalidDataException("密钥文件无效，请重新保存密钥。");
        var encrypted = new byte[(int)file.Length]; file.ReadExactly(encrypted);
        var plaintext = ProtectedData.Unprotect(encrypted, entropy, DataProtectionScope.CurrentUser);
        try { return Validate(Encoding.UTF8.GetString(plaintext)); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }
    public static void Clear(string path) => File.Delete(path);
}
