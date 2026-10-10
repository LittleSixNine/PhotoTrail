using PhotoTrail.Windows;
using System.Security.Cryptography;
using System.Text;

static class KeyChecks
{
    public static void Run()
    {
        var output = Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Set private test output");
        var folder = Path.Combine(output, "key-checks-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder); var path = Path.Combine(folder, "fake-key.dat");
        var passed = 0;
        void Check(bool value) { if (!value) throw new Exception("Key store assertion failed"); passed++; }
        const string first = "FAKE_TEST_ONLY_NOT_A_GOOGLE_KEY_123456789";
        const string second = "FAKE_TEST_ONLY_REPLACEMENT_KEY_987654321";
        Check(GoogleKeyStore.Load(path) is null);
        GoogleKeyStore.Save(path, first);
        Check(GoogleKeyStore.Load(path) == first);
        Check(!Encoding.UTF8.GetString(File.ReadAllBytes(path)).Contains(first));
        var before = File.ReadAllBytes(path);
        foreach (var invalid in new[] { "", "short", first + "\ninside", new string('a',257), first + "汉" })
        {
            try { GoogleKeyStore.Save(path, invalid); throw new Exception("Invalid key accepted"); }
            catch (ArgumentException) { Check(File.ReadAllBytes(path).SequenceEqual(before)); }
        }
        GoogleKeyStore.Save(path, second); Check(GoogleKeyStore.Load(path) == second);
        Check(Directory.GetFiles(folder).Length == 1);
        File.WriteAllBytes(path, new byte[4097]);
        try { GoogleKeyStore.Load(path); throw new Exception("Oversized key accepted"); }
        catch (InvalidDataException) { Check(true); }
        File.WriteAllBytes(path, [1,2,3]);
        try { GoogleKeyStore.Load(path); throw new Exception("Corrupted key accepted"); }
        catch (CryptographicException) { Check(true); }
        GoogleKeyStore.Clear(path); Check(!File.Exists(path)); Check(GoogleKeyStore.Load(path) is null);
        GoogleKeyStore.Clear(path); Check(true);
        var occupied = Path.Combine(folder, "occupied"); Directory.CreateDirectory(occupied);
        try { GoogleKeyStore.Save(occupied, first); throw new Exception("Directory target accepted"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { Check(Directory.Exists(occupied)); Check(Directory.GetFiles(folder).Length == 0); }
        Console.WriteLine($"{passed} DPAPI key-store assertions passed using fake keys; no Google request or real credential used.");
    }
}
