using PhotoTrail.Windows;

static class PresetChecks
{
    public static async Task RunCopyAsync(ExifToolClient client, string fixtures, string output)
    {
        var folder = Path.Combine(output,"preset-copy-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var photo = await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
        var preset = MetadataPreset.Create("旅行预设",new Dictionary<string,string>{["XMP-dc:Creator"]="六九\n另一个作者",["XMP-dc:Title"]="预设,中文\n第二行",["XMP-dc:Subject"]="旅行\n风景\n旅行",["XMP-photoshop:City"]="",["XMP-exif:DateTimeOriginal"]="2026:10:10 12:00:00.123456789Z"});
        var path = Path.Combine(folder,"preset.json");MetadataCsv.WriteNew(path,preset.Encode());var loaded = MetadataPreset.Decode(File.ReadAllText(path));
        await loaded.ApplyAsync(photo);var copy = await MetadataCopy.SaveAsync(client,photo,folder);var result = await PhotoDocument.LoadAsync(client,copy);
        foreach(var field in loaded.Operations.Select(op => new KeyValuePair<string,string>(op.Tag,op.Value))) { if(result.Value(field.Key)!=field.Value)throw new Exception("Preset mismatch "+field.Key);Console.WriteLine("PASS preset copy reload " + field.Key); }
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
        Check(loaded.Name == "中文预设" && loaded.Operations.Select(op=>new KeyValuePair<string,string>(op.Tag,op.Value)).OrderBy(pair=>pair.Key).SequenceEqual(fields.OrderBy(pair=>pair.Key)),"all supported value types encode/decode exactly");
        Check(text.Contains("XMP-dc:Title-x-default") && text.Contains("replaceAuthors") && text.Contains("remove"),"Mac version1 operation shape and aliases emitted");
        fields["XMP-dc:Title"]="mutated";Check(preset.Operations.Single(op=>op.Tag=="XMP-dc:Title").Value!="mutated","preset freezes caller dictionary");
        Check(MetadataPreset.Decode("\ufeff"+text).Operations.Count==7,"BOM accepted");
        foreach(var name in new[]{"",new string('a',81),"line\nname"})Reject(()=>MetadataPreset.Create(name,new Dictionary<string,string>{["XMP-dc:Title"]="a"}),"invalid name refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>()),"empty preset refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["GPS:GPSLatitude"]="0"}),"unapproved field refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-iptcCore:CountryCode"]="US"}),"invalid country code refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="a\n\nb"}),"empty author item refused");
        Reject(()=>MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="a\rb"}),"author carriage return refused");
        var keyword = MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Subject"]="A\na\nA"});Check(keyword.Operations[0].Value=="A\na","keywords deduplicate exact text preserving order and case");
        var author = MetadataPreset.Create("x",new Dictionary<string,string>{["XMP-dc:Creator"]="A\nA"});Check(author.Operations[0].Value=="A\nA","author order and duplicates preserved");
        string Raw(string operations) => "{\"version\":1,\"name\":\"x\",\"operations\":"+operations+"}";
        string Op(string tag,string action)=>"{\"tag\":\""+tag+"\",\"action\":"+action+"}";
        foreach(var invalid in new[]{"{", "[]",text.Replace("\"version\": 1","\"version\": 2"),Raw("[]"),Raw("null"),Raw("["+Op("XMP-exif:DateTimeOriginal","{\"appendText\":{\"_0\":\"x\"}}")+"]"),Raw("["+Op("GPS:GPSLatitude","{\"setText\":{\"_0\":\"0\"}}")+"]"),Raw("["+Op("XMP-dc:Title","{\"setText\":{\"_0\":1}}")+"]"),Raw("["+Op("XMP-dc:Creator","{\"setText\":{\"_0\":\"x\"}}")+"]"),Raw("["+Op("XMP-dc:Creator","{\"replaceAuthors\":{\"_0\":[1]}}")+"]"),Raw("["+Op("XMP-dc:Title","{\"remove\":{\"extra\":1}}")+"]")})Reject(()=>MetadataPreset.Decode(invalid),"invalid version/schema/action rejected as a whole");
        var one=Op("XMP-dc:Title","{\"remove\":{}}");var alias=Op("XMP-dc:Title-x-default","{\"remove\":{}}");
        Check(MetadataPreset.Decode(Raw("["+one+","+alias+"]")).Operations.Count==2,"duplicate effective fields preserve operations");
        Reject(()=>MetadataPreset.Decode("{\"version\":1,\"version\":1,\"name\":\"x\",\"operations\":[]}"),"duplicate root properties refused");
        Reject(()=>MetadataPreset.Decode(Raw("["+Op("XMP-dc:Title","{\"setText\":{\"_0\":\"a\",\"_0\":\"b\"}}")+"]")),"duplicate action payload refused");
        Reject(()=>MetadataPreset.Decode(new string('a',MetadataPreset.MaximumBytes+1)),"oversized preset refused");
        Check(MetadataPreset.Decode(Raw("["+one+"]")).Operations[0].Value=="","clear action decoded explicitly");
        Ordered(Check,Reject);Console.WriteLine($"Preset checks complete: {count}");
    }
    static void Ordered(Action<bool,string> check,Action<Action,string> reject)
    {
        const string title="XMP-dc:Title",description="XMP-dc:Description",author="XMP-dc:Creator",keywords="XMP-dc:Subject";
        PhotoDocument Doc(string json) {
            using var data=System.Text.Json.JsonDocument.Parse(json);
            return (PhotoDocument)typeof(PhotoDocument).GetConstructors(System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance).Single().Invoke(new object?[]{"synthetic.jpg",null,data.RootElement.Clone(),null,"hash",null});
        }
        MetadataPreset Plan(params MetadataOperation[] ops)=>MetadataPreset.Create("ordered",ops);
        var doc=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Title\":\"original\",\"XMP-dc:Description\":\"own source\"}");
        doc.SetDraft(new Dictionary<string,string>{{"XMP-dc:Rights","earlier rights"}});
        Plan(new MetadataOperation(title,"setText","A"),new MetadataOperation(title,"appendText","B")).Apply(doc);check(doc.Value(title)=="AB"&&doc.Value("XMP-dc:Rights")=="earlier rights","ordered same-target preserves earlier draft");
        doc.ClearDraft();Plan(new MetadataOperation(title,"appendText","B"),new MetadataOperation(title,"setText","A")).Apply(doc);check(doc.Value(title)=="A","exchanged order differs");
        Plan(new MetadataOperation(title,"remove"),new MetadataOperation(title,"fillMissingText","filled")).Apply(doc);check(doc.Value(title)=="filled","explicit clear immediately missing");
        Plan(new MetadataOperation(description,"setText","new source"),new MetadataOperation(title,"copy",description)).Apply(doc);check(doc.Value(title)=="new source","copy uses preceding result");
        Plan(new MetadataOperation(title,"setText","original")).Apply(doc);check(!doc.Draft.ContainsKey(title),"net cancellation drops only target draft");
        var second=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Description\":\"second source\"}");Plan(new MetadataOperation(title,"copy",description)).Apply(second);check(second.Value(title)=="second source","each photo uses own source no broadcast");
        var blank=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Title\":\" \"}");Plan(new MetadataOperation(title,"fillMissingText","fill")).Apply(blank);check(blank.Draft.Count==0,"whitespace is present not missing");
        var missing=Doc("{\"File:FileType\":\"JPEG\"}");check(Plan(new MetadataOperation(title,"copy",description)).Apply(missing)==1&&missing.Draft.Count==0,"confirmed missing copy skips");
        Plan(new MetadataOperation(author,"fillMissingAuthors","A\nA\nB")).Apply(missing);check(missing.Value(author)=="A\nA\nB","author order duplicates retained");
        Plan(new MetadataOperation(author,"fillMissingAuthors","X")).Apply(missing);check(missing.Value(author)=="A\nA\nB","author fill does not replace existing");
        Plan(new MetadataOperation(keywords,"replaceKeywords","A\na\né\né"),new MetadataOperation(keywords,"appendKeywords","A\nZ"),new MetadataOperation(keywords,"removeKeywords","a")).Apply(missing);check(missing.Value(keywords)=="A\né\né\nZ","keywords exact case and Unicode no normalization");
        var keywordPlan=Plan(new MetadataOperation(keywords,"appendKeywords","Z"));var before=missing.Draft.ToArray();keywordPlan.Apply(missing);check(missing.Draft.SequenceEqual(before),"keyword repeat no net change");
        Plan(new MetadataOperation(keywords,"removeKeywords","A\né\né\nZ")).Apply(missing);check(missing.Value(keywords)=="","removing all clears");
        Plan(new MetadataOperation(title,"appendText","!")).Apply(missing);Plan(new MetadataOperation(title,"appendText","!")).Apply(missing);check(missing.Value(title)=="!!","text append repeats exactly without separator");
        Plan(new MetadataOperation(keywords,"replaceKeywords","")).Apply(missing);check(missing.Value(keywords)=="","empty replacement keywords clears");
        var emptySource=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Description\":\"\",\"XMP-dc:Title\":\"old\"}");check(Plan(new MetadataOperation(title,"copy",description)).Apply(emptySource)==0&&emptySource.Value(title)=="","present empty scalar copy is not missing and clears target");
        var typed=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Title\":3}");reject(()=>Plan(new MetadataOperation(title,"fillMissingText","X")).Apply(typed),"wrong scalar type not missing");
        var typedList=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Creator\":\"not list\"}");reject(()=>Plan(new MetadataOperation(author,"fillMissingAuthors","X")).Apply(typedList),"wrong author type not missing");
        var failed=Doc("{\"File:FileType\":\"JPEG\",\"ExifTool:Error\":\"failure\"}");reject(()=>Plan(new MetadataOperation(title,"fillMissingText","X")).Apply(failed),"read error not missing");
        var huge=Doc("{\"File:FileType\":\"JPEG\",\"XMP-dc:Description\":\""+new string('x',257)+"\"}");reject(()=>Plan(new MetadataOperation(title,"setText","first"),new MetadataOperation("XMP-photoshop:City","copy",description)).Apply(huge),"copy target overflow rejects all steps");check(huge.Draft.Count==0,"model failure leaves complete draft untouched");
        foreach(var restricted in new[]{"XMP-exif:DateTimeOriginal","XMP-xmp:Rating","XMP-exif:ISO","XMP-exif:ExposureProgram","XMP-exif:WhiteBalance","XMP-iptcCore:CountryCode"})reject(()=>Plan(new MetadataOperation(restricted,"appendText","1")),"restricted append rejected "+restricted);
        foreach(var bad in new[]{"a\n\nb","a\rb","a\tb","a\0b"})reject(()=>Plan(new MetadataOperation(author,"replaceAuthors",bad)),"bad list item rejected");
        reject(()=>Plan(new MetadataOperation(title,"copy",author)),"incompatible copy types rejected");reject(()=>Plan(new MetadataOperation(title,"copy",title)),"copy excludes self");
        reject(()=>Plan(new MetadataOperation(title,"appendText","")),"empty append rejected");reject(()=>Plan(new MetadataOperation(title,"setText",new string('x',8193))),"scalar length bound");
        reject(()=>Plan(Enumerable.Repeat(new MetadataOperation(title,"remove"),28).ToArray()),"operation limit counts repeated targets");
        check(Plan(Enumerable.Repeat(new MetadataOperation(title,"remove"),27).ToArray()).Operations.Count==27,"operation bound inclusive");
        var round=Plan(new MetadataOperation(title,"setText","A"),new MetadataOperation(title,"appendText","B"),new MetadataOperation(title,"copy",description),new MetadataOperation(keywords,"replaceKeywords","A\na"));check(MetadataPreset.Decode(round.Encode()).Operations.SequenceEqual(round.Operations),"ordered repeated targets and copy roundtrip");
        foreach(var action in new[]{"offsetDate","sequence","distribute","filenameDate","calendarDays","unknown"})reject(()=>MetadataPreset.Decode("{\"version\":1,\"name\":\"x\",\"operations\":[{\"tag\":\"XMP-exif:DateTimeOriginal\",\"action\":{\""+action+"\":{\"_0\":\"x\"}}}]}"),"unsupported date/unknown action rejects entire JSON");
        reject(()=>Plan(new MetadataOperation(title,"copy",description)).Apply(typed),"wrong copy destination type refuses application");
        foreach(var fixture in new[]{"legacy-v1.json","ordered-subset-v1.json"}){var loaded=MetadataPreset.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"fixtures","presets",fixture)));var saved=MetadataPreset.Decode(loaded.Encode());check(saved.Name==loaded.Name&&saved.Operations.SequenceEqual(loaded.Operations),"static fixture roundtrip "+fixture);}
        using var cancellation=new CancellationTokenSource();cancellation.Cancel();try{Plan(new MetadataOperation(title,"setText","cancel")).Apply(doc,cancellation.Token);throw new Exception("cancel accepted");}catch(OperationCanceledException){check(doc.Value(title)=="original","canceled calculation untouched");}
    }
}
