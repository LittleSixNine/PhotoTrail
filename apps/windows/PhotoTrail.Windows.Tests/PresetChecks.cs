using PhotoTrail.Windows;

static class PresetChecks
{
    public static async Task RunCopyAsync(ExifToolClient client, string fixtures, string output)
    {
        var folder = Path.Combine(output,"preset-copy-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var photo = await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
        var preset = MetadataPreset.Create("旅行预设",new Dictionary<string,string>{["XMP-dc:Creator"]="六九\n另一个作者",["XMP-dc:Title"]="预设,中文\n第二行",["XMP-dc:Subject"]="旅行\n风景\n旅行",["XMP-photoshop:City"]="",["XMP-exif:DateTimeOriginal"]="2026:10:10 12:00:00.123456789Z"});
        var path = Path.Combine(folder,"preset.json");MetadataCsv.WriteNew(path,preset.Encode());var loaded = MetadataPreset.Decode(File.ReadAllText(path));
        photo.SetDraft(loaded.Changes);var copy = await MetadataCopy.SaveAsync(client,photo,folder);var result = await PhotoDocument.LoadAsync(client,copy);
        foreach(var field in loaded.Changes) { if(result.Value(field.Key)!=field.Value)throw new Exception("Preset mismatch "+field.Key);Console.WriteLine("PASS preset copy reload " + field.Key); }
        if(await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Preset changed source");Console.WriteLine("PASS preset source unchanged");
        photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Undo failed");Console.WriteLine("PASS preset undo");Console.WriteLine("Evidence " + folder);
    }

    public static void Run()
    {
        var count = 0;
        void Check(bool ok, string label) { if(!ok)throw new Exception(label);count++;Console.WriteLine("PASS " + label); }
        void Reject(Action action, string label) { try { action(); } catch(ArgumentException) { Check(true,label);return; }throw new Exception(label); }
        var fields = new Dictionary<string,string>{["XMP-dc:Creator"]="六九\n第二作者",["XMP-dc:Title"]="中文, \"引号\"\n第二行",["XMP-dc:Description"]="@clear",["XMP-dc:Subject"]="旅行\n风景",["XMP-exif:DateTimeOriginal"]="2026:10:10 12:00:00.123456789Z",["XMP-photoshop:City"]="",["XMP-iptcCore:CountryCode"]="CHN"};
        var preset = MetadataPreset.Create("  中文预设  ",fields);var text = preset.Encode();var loaded = MetadataPreset.Decode(text);
        Check(loaded.Name == "中文预设" && loaded.Changes.OrderBy(pair=>pair.Key).SequenceEqual(fields.OrderBy(pair=>pair.Key)),"all supported value types encode/decode exactly");
        Check(text.Contains("XMP-dc:Title-x-default") && text.Contains("replaceAuthors") && text.Contains("remove"),"Mac version1 operation shape and aliases emitted");
        fields["XMP-dc:Title"]="mutated";Check(preset.Changes["XMP-dc:Title"]!="mutated","preset freezes caller dictionary");
        Check(MetadataPreset.Decode("\ufeff"+text).Changes.Count==7,"BOM accepted");
        foreach(var name in new[]{"",new string('a',81),"line\nname"})Reject(()=>MetadataPreset.Create(name,new Dictionary<string,string>{["XMP-dc:Title"]="a"}),"invalid name refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>()),"empty preset refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["GPS:GPSLatitude"]="0"}),"unapproved field refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-iptcCore:CountryCode"]="US"}),"invalid country code refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="a\n\nb"}),"empty author item refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="a\rb"}),"author carriage return refused");
        var keyword = MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Subject"]="A\na\nA"});Check(keyword.Changes["XMP-dc:Subject"]=="A\na","keywords deduplicate exact text preserving order and case");
        var author = MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="A\nA"});Check(author.Changes["XMP-dc:Creator"]=="A\nA","author order and duplicates preserved");
        string Raw(string operations) => "{\"version\":1,\"name\":\"x\",\"operations\":"+operations+"}";
        string Op(string tag,string action)=>"{\"tag\":\""+tag+"\",\"action\":"+action+"}";
        foreach(var invalid in new[]{"{", "[]",text.Replace("\"version\": 1","\"version\": 2"),Raw("[]"),Raw("null"),Raw("["+Op("XMP-dc:Title-x-default","{\"appendText\":{\"_0\":\"x\"}}")+"]"),Raw("["+Op("GPS:GPSLatitude","{\"setText\":{\"_0\":\"0\"}}")+"]"),Raw("["+Op("XMP-dc:Title","{\"setText\":{\"_0\":1}}")+"]"),Raw("["+Op("XMP-dc:Creator","{\"setText\":{\"_0\":\"x\"}}")+"]"),Raw("["+Op("XMP-dc:Creator","{\"replaceAuthors\":{\"_0\":[1]}}")+"]"),Raw("["+Op("XMP-dc:Title","{\"remove\":{\"extra\":1}}")+"]")})Reject(()=>MetadataPreset.Decode(invalid),"invalid version/schema/action rejected as a whole");
        var one=Op("XMP-dc:Title","{\"remove\":{}}");var alias=Op("XMP-dc:Title-x-default","{\"remove\":{}}");
        Reject(()=>MetadataPreset.Decode(Raw("["+one+","+alias+"]")),"duplicate effective field rejected");
        Reject(()=>MetadataPreset.Decode("{\"version\":1,\"version\":1,\"name\":\"x\",\"operations\":[]}"),"duplicate root properties refused");
        Reject(()=>MetadataPreset.Decode(Raw("["+Op("XMP-dc:Title","{\"setText\":{\"_0\":\"a\",\"_0\":\"b\"}}")+"]")),"duplicate action payload refused");
        Reject(()=>MetadataPreset.Decode(new string('a',MetadataPreset.MaximumBytes+1)),"oversized preset refused");
        Check(MetadataPreset.Decode(Raw("["+one+"]")).Changes["XMP-dc:Title"]=="","clear action decoded explicitly");
        Console.WriteLine($"Preset checks complete: {count}");
    }
}
