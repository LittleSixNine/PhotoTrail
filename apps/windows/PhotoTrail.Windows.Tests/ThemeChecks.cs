using PhotoTrail.Windows;
static class ThemeChecks
{
    public static void Run()
    {
        var folder = Path.Combine(Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT")??Path.GetTempPath(),"theme-checks-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var file = Path.Combine(folder,"theme.json");var count = 0;
        void Check(bool value,string label) { if (!value) throw new Exception(label);count++;Console.WriteLine("PASS "+label); }
        void Reject(Action action,string label) { try { action(); } catch (Exception e) when (e is ArgumentException or InvalidDataException or System.Text.Json.JsonException or InvalidOperationException) { Check(true,label);return; }throw new Exception(label); }
        Check(ThemePreference.Read(file)==0 && !File.Exists(file),"missing theme defaults to system without writing");
        foreach(var mode in new[]{1,2,0}) { ThemePreference.Save(file,mode);Check(ThemePreference.Read(file)==mode,"theme roundtrip "+mode); }
        var before=File.ReadAllBytes(file);Reject(()=>ThemePreference.Save(file,3),"invalid theme refuses write");Check(before.SequenceEqual(File.ReadAllBytes(file)),"invalid save preserves preference");
        foreach(var text in new[]{"{","null","[]","{\"version\":2,\"theme\":\"dark\"}","{\"version\":1,\"theme\":7}","{\"version\":1,\"theme\":\"unknown\"}","{\"version\":1,\"version\":1}","{\"version\":1,\"theme\":\"dark\",\"extra\":0}",new string(' ',4097)})
        { File.WriteAllText(file,text);Reject(()=>ThemePreference.Read(file),"corrupt/over-limit theme refused");Reject(()=>ThemePreference.Save(file,1),"corrupt theme not overwritten");Check(File.ReadAllText(file)==text,"original corrupt config preserved"); }
        Check(Directory.GetFiles(folder,".theme-*").Length==0,"no temporary preference remains");
        Console.WriteLine($"Theme checks complete: {count}; {folder}");
    }
}
