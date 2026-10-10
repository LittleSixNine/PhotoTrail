using System.Text.Json;
using PhotoTrail.Windows;

static class CsvChecks
{
    public static async Task RunCopyAsync(ExifToolClient client, string fixtures, string output)
    {
        var folder = Path.Combine(output, "csv-copy-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
        var photo = await PhotoDocument.LoadAsync(client, Path.Combine(fixtures, "aligned.jpg"));
        var snapshot = MetadataCsv.Snapshot([photo]);
        void Check(bool result, string label) { if (!result) throw new Exception(label); Console.WriteLine("PASS " + label); }
        Check(MetadataCsv.Load(MetadataCsv.Export(snapshot), snapshot).Changes.Count == 0, "real metadata roundtrip is no-op");
        var changed = snapshot[0] with { Cells = new Dictionary<string,string> { ["XMP-dc:Title"] = JsonSerializer.Serialize("CSV中文,引号\"\n第二行"), ["XMP-dc:Creator"] = JsonSerializer.Serialize(new[] { "甲", "乙" }) } };
        var text = MetadataCsv.Export([changed]); var csv = Path.Combine(folder, "import.csv"); MetadataCsv.WriteNew(csv, text);
        Check(File.ReadAllText(csv) == text, "atomic UTF8 CSV export roundtrip");
        try { MetadataCsv.WriteNew(csv, "changed"); throw new Exception("overwrite accepted"); } catch (IOException) { Check(File.ReadAllText(csv) == text, "existing CSV not overwritten"); }
        Check(!Directory.EnumerateFiles(folder, "*.tmp").Any(), "failed export leaves no own temporary file");
        var changes = MetadataCsv.Load(File.ReadAllText(csv), snapshot).Changes[snapshot[0].Id];
        photo.SetDraft(changes); var saved = await MetadataCopy.SaveAsync(client, photo, folder); var result = await PhotoDocument.LoadAsync(client, saved);
        Check(result.Value("XMP-dc:Title") == "CSV中文,引号\"\n第二行" && result.Value("XMP-dc:Creator") == "甲\n乙", "CSV draft copy saved and independently reloaded");
        Check(await PhotoDocument.HashAsync(photo.FilePath) == photo.SourceHash, "CSV leaves source hash unchanged");
        photo.ClearDraft(); Check(photo.Draft.Count == 0, "CSV draft undo restores imported context");
        Check(MetadataCsv.Load(MetadataCsv.Export(snapshot), MetadataCsv.Snapshot([result])).Changes.Count == 0, "different output path identity not authorized");
        Console.WriteLine("CSV copy evidence: " + folder);
    }

    public static void Run()
    {
        var count = 0;
        void Check(bool result, string label) { if (!result) throw new Exception(label); Console.WriteLine("PASS " + label); count++; }
        void Reject(Action action, string label) { try { action(); } catch (Exception error) when (error is ArgumentException or InvalidDataException) { Check(true, label); return; } throw new Exception(label); }
        string Q(string value) => "\"" + value.Replace("\"", "\"\"") + "\"";
        string Csv(string[] header, params string[][] rows) => string.Join("\r\n", new[] { header }.Concat(rows).Select(row => string.Join(',', row.Select(Q)))) + "\r\n";
        var id = new string('a', 64); var otherId = new string('b', 64);
        var record = new CsvRecord(id, "旅途/照片.jpg", new Dictionary<string, string> { ["XMP-dc:Title"] = JsonSerializer.Serialize("原标题"), ["XMP-dc:Creator"] = JsonSerializer.Serialize(new[] { "Alice", "Bob" }), ["XMP-iptcCore:CountryCode"] = JsonSerializer.Serialize("US") });
        var allowed = new[] { record }; var header = new[] { "PhotoTrail CSV 1", "RelativePath", "XMP-dc:Title-x-default", "XMP-dc:Creator" };
        CsvImport Load(params string[][] rows) => MetadataCsv.Load(Csv(header, rows), allowed);
        Check(MetadataCsv.Load(MetadataCsv.Export(allowed), allowed).Changes.Count == 0, "unchanged export imports as no-op including legacy country code");
        var title = "中文, \"quoted\"\n第二行";
        var imported = Load([id, record.RelativePath, JsonSerializer.Serialize(title), JsonSerializer.Serialize(new[] { "甲", "乙" })]);
        Check(imported.Changes[id]["XMP-dc:Title"] == title && imported.Changes[id]["XMP-dc:Creator"] == "甲\n乙", "JSON text quotes newline and ordered list preserved");
        Check(MetadataCsv.Load("\ufeff" + Csv(header, [id, record.RelativePath, JsonSerializer.Serialize(title), ""]), allowed).Changes[id]["XMP-dc:Title"] == title, "UTF8 BOM accepted");
        Check(Load([id, record.RelativePath, "", ""]).Changes.Count == 0, "empty cells mean no operation");
        Check(Load([id, record.RelativePath, "@clear", "[]"]).Changes[id].Values.All(value => value == ""), "explicit clear and empty list clear existing fields");
        Check(Load([id, record.RelativePath, JsonSerializer.Serialize("@clear"), ""]).Changes[id]["XMP-dc:Title"] == "@clear", "JSON clear token remains literal text");
        foreach (var invalid in new[] { "not JSON", "123", "null", "{}", "[1]" })
            Check(Load([id, record.RelativePath, invalid, JsonSerializer.Serialize(new[] { "changed" })]).Changes.Count == 0, "invalid scalar discards entire row: " + invalid);
        foreach (var invalid in new[] { "[1]", "null", "\"text\"", "[\"line\\ninside\"]", "[\"\"]", JsonSerializer.Serialize(Enumerable.Repeat("a", 257)) })
            Check(Load([id, record.RelativePath, JsonSerializer.Serialize("valid"), invalid]).Changes.Count == 0, "invalid list discards entire row");
        Check(Load([otherId, record.RelativePath, JsonSerializer.Serialize("changed"), ""]).Warnings.Count == 1, "unauthorized identity skipped");
        foreach (var path in new[] { "../照片.jpg", "/照片.jpg", "旅途\\照片.jpg", "旅途//照片.jpg", "旅途/./照片.jpg", "C:/照片.jpg", "different.jpg" })
            Check(Load([id, path, JsonSerializer.Serialize("changed"), ""]).Changes.Count == 0, "unsafe or mismatched relative path skipped");
        Reject(() => Load([id, record.RelativePath, "", ""], [id, "second.jpg", "", ""]), "duplicate identity invalidates input");
        Reject(() => Load([id, record.RelativePath, "", ""], [otherId, record.RelativePath.ToUpperInvariant(), "", ""]), "case-folded duplicate path invalidates input");
        Reject(() => Load([id, record.RelativePath, ""]), "wrong row shape rejected");
        Reject(() => MetadataCsv.Load(Csv(["PhotoTrail CSV 1", "RelativePath", "XMP-dc:Title", "XMP-dc:Title-x-default"], [id, record.RelativePath, "", ""]), allowed), "duplicate effective alias rejected");
        Check(MetadataCsv.Load(Csv(["PhotoTrail CSV 1", "RelativePath", "unknown", "XMP-dc:Title-x-default"], [id, record.RelativePath, "anything", JsonSerializer.Serialize(title)]), allowed).Changes[id]["XMP-dc:Title"] == title, "unknown column ignored while supported column previews");
        Reject(() => MetadataCsv.Load(MetadataCsv.Export(allowed, true), allowed), "display CSV cannot import");
        Reject(() => MetadataCsv.Load("\"PhotoTrail CSV 1\",\"RelativePath\"\r\n\"unterminated", allowed), "unterminated quoted CSV refused");
        Reject(() => MetadataCsv.Load(new string('a', MetadataCsv.MaximumBytes + 1), allowed), "oversized CSV refused");
        Reject(() => MetadataCsv.Load(Csv(header, Enumerable.Repeat(new[] { id, record.RelativePath, "", "" }, 3001).ToArray()), allowed), "over 3000 rows refused");
        foreach (var prefix in new[] { "=", "+", "-", "@", "\t", "\r", "\n" })
        {
            var unsafeRecord = record with { Cells = new Dictionary<string,string> { ["XMP-dc:Title"] = JsonSerializer.Serialize(prefix + "formula") } };
            Check(MetadataCsv.Export([unsafeRecord], true).Contains("'" + prefix + "formula"), "display metadata formula prefix protected");
        }
        var formulaPath = record with { RelativePath = "=formula.jpg" };
        Check(MetadataCsv.Export([formulaPath], true).Contains("'=formula.jpg"), "display path formula protected");
        Reject(() => MetadataCsv.Export([formulaPath]), "unsafe roundtrip filename refused without identity rewrite");
        Check(MetadataCsv.Identity(@"C:\Photos\照片.jpg").Length == 64 && MetadataCsv.Identity(@"C:\Photos\照片.jpg") != MetadataCsv.Identity(@"D:\Photos\照片.jpg"), "identity remains path-bound SHA256");
        var legacy = record with { Cells = new Dictionary<string,string> { ["XMP-dc:Creator"] = JsonSerializer.Serialize(new[] { "embedded\nnewline" }) } };
        Check(MetadataCsv.Load(MetadataCsv.Export([legacy]), [legacy]).Changes.Count == 0, "unchanged legacy list identity preserved without flattening");
        Check(MetadataCsv.Load(Csv(["PhotoTrail CSV 1", "RelativePath", "XMP-iptcCore:CountryCode"], [id, record.RelativePath, JsonSerializer.Serialize("CHN")]), allowed).Changes[id]["XMP-iptcCore:CountryCode"] == "CHN", "valid country code previews");
        Check(MetadataCsv.Load(Csv(["PhotoTrail CSV 1", "RelativePath", "XMP-iptcCore:CountryCode"], [id, record.RelativePath, JsonSerializer.Serialize("XX")]), allowed).Changes.Count == 0, "invalid country code rejected");
        Console.WriteLine($"CSV checks complete: {count}");
    }
}
