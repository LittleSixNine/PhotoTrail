using PhotoTrail.Windows;
using System.Text;

static class UnicodeFilterChecks
{
    internal static void Run()
    {
        int count=0;
        void Check(bool value,string label){if(!value)throw new Exception(label);Console.WriteLine("PASS Unicode "+label);count++;}
        bool Match(string name,string comparison,string value,bool sensitive=true)=>RenameTransform.MatchesFilter(name,new("action"){Action="filter-following",CaseSensitive=sensitive,Filters=[new("name",comparison,value)]},null,null,null);
        foreach(bool sensitive in new[]{true,false})
        foreach(var pair in new[]{("é","e\u0301"),("가","\u1100\u1161"),("Å","A\u030A")})
        foreach(var (a,b) in new[]{pair,(pair.Item2,pair.Item1)}) {
            foreach(var op in new[]{"contains","equals","starts","ends"})Check(Match(a,op,b,sensitive),op+" canonical "+sensitive+" "+count);
            Check(!Match(a,"notContains",b,sensitive)&&!Match(a,"notEquals",b,sensitive),"negative canonical "+count);
        }
        Check(Match("e\u0301-early.jpeg","starts","é"),"P2 disk-name NFD prefix NFC");
        Check(!Match("É","equals","é")&&Match("É","equals","é",false),"case switch");
        Check(!Match("e","equals","é")&&!Match("е","equals","e"),"accent and Cyrillic remain distinct");
        Check(!Match("👩‍💻.jpeg","starts","👩")&&!Match("x👩‍💻.jpeg","contains","💻"),"no partial grapheme match");
        Check(Match("abc.jpg","starts","abc")&&Match("abc.jpg","ends",".jpg")&&!Match("abc.jpg","notContains","bc"),"ASCII");
        Check(Match("abc","contains","")&&Match("","equals","")&&!Match("abc","equals",""),"empty");
        Check(RenameTransform.MatchesFilter("a",new("action"){Action="filter-following",Filters=[new("comment","missing","")]},null,null,null),"missing metadata");
        if(Environment.GetEnvironmentVariable("PHOTOTRAIL_MAC_EXPORTS") is {} folder)foreach(var path in Directory.EnumerateFiles(folder,"*-mac-export.json")) {
            using var input=System.Text.Json.JsonDocument.Parse(File.ReadAllText(path));
            var scheme=RenameSchemeLibrary.Import(File.ReadAllText(path),"Mac actual");
            scheme=scheme with{Rules=RenamePlan.EncodeEditorRules(RenamePlan.ParseRules(scheme.Rules))};
            using var output=System.Text.Json.JsonDocument.Parse(MacRenamePreset.Export(scheme));
            var a=input.RootElement.GetProperty("rules").EnumerateArray().ToArray();var b=output.RootElement.GetProperty("rules").EnumerateArray().ToArray();
            Check(a.Length==b.Length,"actual export rule count "+Path.GetFileName(path));
            for(int i=0;i<a.Length;i++) {
                Check(Guid.Parse(a[i].GetProperty("id").GetString()!)==Guid.Parse(b[i].GetProperty("id").GetString()!),"actual rule UUID "+i);
                Check(a[i].GetProperty("filters").EnumerateArray().Select(f=>Guid.Parse(f.GetProperty("id").GetString()!)).SequenceEqual(b[i].GetProperty("filters").EnumerateArray().Select(f=>Guid.Parse(f.GetProperty("id").GetString()!))),"actual filter UUID "+i);
            }
            var natural=scheme with{Order=scheme.Order with{Sort="natural"}};
            Check(RenameSchemeLibrary.Import(MacRenamePreset.Export(natural),"natural").Order.Sort=="natural","natural import/export retained");
        }
        Console.WriteLine($"{count} Unicode filter checks passed.");
    }
}
