using PhotoTrail.Windows;

static class DateChecks
{
    public static void Run()
    {
        var count = 0;
        void Check(bool ok, string label) { if (!ok) throw new Exception(label); count++; Console.WriteLine("PASS " + label); }
        void Reject(Action action, string label) { try { action(); } catch (ArgumentException) { Check(true, label); return; } throw new Exception(label); }
        foreach (var suffix in new[] { "", "Z", "+09:00", "-07:00", "+14:00", "-00:00", ".123456789+09:00" })
        {
            var date = MetadataDate.Parse("2024:02:28 23:59:59" + suffix);
            Check(date.Shift(0,0,0,0,0,2).Text == "2024:02:29 00:00:01" + suffix, "leap day rollover preserves suffix " + suffix);
            Check(date.WallTime.Kind == DateTimeKind.Unspecified, "timezone absent does not become local or UTC");
        }
        foreach (var invalid in new[] { "", "2023:02:29 00:00:00", "2024:04:31 00:00:00", "2024:01:01 24:00:00", "2024:01:01 00:00:60", "0000:01:01 00:00:00", "2024:01:01 00:00:00+14:01", "2024:01:01 00:00:00+00:60", "2024:01:01 00:00:00+15:00", "2024:01:01 00:00:00.1234567890", "2024:01:01 00:00:00\n" }) Reject(()=>MetadataDate.Parse(invalid), "invalid date/offset refused");
        Reject(()=>MetadataDate.Parse("2024:02:29 00:00:00").Shift(1,0,0,0,0,0), "year addition cannot silently clamp leap day");
        Reject(()=>MetadataDate.Parse("2024:01:31 00:00:00").Shift(0,1,0,0,0,0), "month addition cannot silently clamp 31st");
        Reject(()=>MetadataDate.Parse("9999:12:31 23:59:59").Shift(0,0,0,0,0,1), "year overflow refused");
        Reject(()=>MetadataDate.Parse("0001:01:01 00:00:00").Shift(0,0,0,0,0,-1), "year underflow refused");
        Reject(()=>MetadataDate.Sequence("2024:01:01 00:00:00",long.MaxValue,3000), "sequence multiplication overflow refused");
        Reject(()=>MetadataDate.Sequence("2024:01:01 00:00:00",1,0), "empty sequence refused");
        Check(MetadataDate.Sequence("2024:01:01 00:00:02.001Z", -1, 3).SequenceEqual(new[] { "2024:01:01 00:00:02.001Z", "2024:01:01 00:00:01.001Z", "2024:01:01 00:00:00.001Z" }), "negative sequence preserves fraction and UTC suffix");
        Check(MetadataDate.Parse("2024:01:01 00:00:00").Shift(1,1,1,1,1,1).Text == "2025:02:02 01:01:01", "component offsets applied in explicit order");
        PhotoDocument.ValidateChanges(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]="2024:02:29 00:00:00.123456789Z"}); Check(true,"draft validator accepts precise date without timezone inference");
        Check(MetadataDate.Parse("2024:01:01 00:00:00").Instant() is null, "wall-clock time cannot auto-match GPS instant");
        Check(MetadataDate.Parse("2024:01:01 00:00:00Z").Instant()!.Value.Offset == TimeSpan.Zero, "UTC suffix auto-matches explicit instant");
        Check(MetadataDate.Parse("2024:01:01 00:00:00+09:00").Instant()!.Value.Offset == TimeSpan.FromHours(9), "fixed offset auto-match retained");
        Check(MetadataDate.Parse("2024:01:01 00:00:00.123456700Z").Instant()!.Value.Ticks % TimeSpan.TicksPerSecond == 1234567, "representable fractional instant retained exactly");
        Check(MetadataDate.Parse("2024:01:01 00:00:00.123456789Z").Instant() is null, "sub-tick precision requires explicit match time rather than rounding");
        Check(MetadataDate.Parse("0001:01:01 00:00:00+14:00").Instant() is null, "instant outside native range not guessed");
        foreach (var suffix in new[] { "", "Z", "+09:00", "-07:00", ".123456789-00:00" })
        {
            var original = MetadataDate.Parse("2024:02:29 12:34:56" + suffix);
            Check(original.Replace(year:2025,day:28,hour:0).Text == "2025:02:28 00:34:56" + suffix, "component replacement keeps remaining components and exact suffix " + suffix);
            Check(original.Text == "2024:02:29 12:34:56" + suffix && original.Replace(second:0).WallTime.Kind == DateTimeKind.Unspecified, "replacement does not mutate original or infer timezone");
        }
        var leap = MetadataDate.Parse("2024:02:29 12:34:56.123456789Z");
        Reject(()=>leap.Replace(), "empty component replacement refused");
        Reject(()=>leap.Replace(year:2025), "leap component replacement refuses silent clamping");
        Reject(()=>MetadataDate.Parse("2024:01:31 00:00:00").Replace(month:2), "component month refuses silent 31st clamping");
        foreach (var value in new[] {-1,0,10000}) Reject(()=>leap.Replace(year:value), "invalid replacement year refused");
        foreach (var value in new[] {0,13}) Reject(()=>leap.Replace(month:value), "invalid replacement month refused");
        foreach (var value in new[] {0,32}) Reject(()=>leap.Replace(day:value), "invalid replacement day refused");
        Reject(()=>leap.Replace(hour:24), "invalid replacement hour refused");
        Reject(()=>leap.Replace(minute:60), "invalid replacement minute refused");
        Reject(()=>leap.Replace(second:60), "invalid replacement second refused");
        Check(leap.Replace(year:2025,month:1,day:31,hour:0,minute:0,second:0).Text == "2025:01:31 00:00:00.123456789Z", "components replaced together rather than invalid sequential mutation");
        foreach (var suffix in new[] { "", "Z", "+09:00", "-00:00", ".123456789+09:00" })
        {
            var distributed = MetadataDate.Distribute("2024:12:31 23:59:58" + suffix, "2025:01:01 00:00:03" + suffix, 3);
            Check(distributed.SequenceEqual(new[]{"2024:12:31 23:59:58" + suffix,"2025:01:01 00:00:01" + suffix,"2025:01:01 00:00:03" + suffix}), "distribution rounds half up and preserves endpoints/suffix " + suffix);
        }
        Reject(()=>MetadataDate.Distribute("2024:01:02 00:00:00", "2024:01:01 00:00:00",2), "reversed distribution refused");
        Reject(()=>MetadataDate.Distribute("2024:01:01 00:00:00Z", "2024:01:01 00:00:01+00:00",2), "distribution offset spelling mismatch refused");
        Reject(()=>MetadataDate.Distribute("2024:01:01 00:00:00.1Z", "2024:01:01 00:00:01.10Z",2), "distribution fraction precision mismatch refused");
        Reject(()=>MetadataDate.Distribute("2024:01:01 00:00:00", "2024:01:01 00:00:01",0), "empty distribution refused");
        Reject(()=>MetadataDate.Distribute("2024:01:01 00:00:00", "2024:01:01 00:00:01",3001), "over-limit distribution refused");
        Check(MetadataDate.Distribute("2024:01:01 00:00:00", "2024:01:01 00:00:01",1).Single() == "2024:01:01 00:00:00", "single distribution uses first endpoint");
        Check(MetadataDate.Distribute("2024:01:01 00:00:00Z", "2024:01:01 00:00:00Z",3).Distinct().Count()==1, "zero interval may assign identical dates");
        Check(MetadataDate.Distribute("2024:01:01 00:00:00", "2024:01:01 00:00:01",3).SequenceEqual(new[]{"2024:01:01 00:00:00","2024:01:01 00:00:01","2024:01:01 00:00:01"}), "short interval duplicates are explicit rather than invented sub-seconds");
        var widest = MetadataDate.Distribute("0001:01:01 00:00:00.123456789Z","9999:12:31 23:59:59.123456789Z",3000);
        Check(widest.Length == 3000 && widest[0]=="0001:01:01 00:00:00.123456789Z" && widest[^1]=="9999:12:31 23:59:59.123456789Z", "3000 distribution across full date range keeps endpoints without overflow");
        Check(widest.Zip(widest.Skip(1)).All(pair=>MetadataDate.Parse(pair.First).WallTime <= MetadataDate.Parse(pair.Second).WallTime), "wide distribution remains monotonic");
        var filenamePattern = @"([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})";
        var filenameTemplate = "$1:$2:$3 $4:$5:$6";
        var filenames = MetadataDate.FromFilenames(["旅行_20240229_123456.jpg","20230229_123456.jpg","no-date.jpg"],filenamePattern,filenameTemplate);
        Check(filenames.SequenceEqual(new string?[]{"2024:02:29 12:34:56",null,null}), "filename candidates preserve positions and skip invalid/unmatched dates");
        Check(MetadataDate.FromFilenames(["20240101_000000.jpg"],filenamePattern,filenameTemplate+".123456789-00:00")[0]=="2024:01:01 00:00:00.123456789-00:00", "filename template keeps explicit precision/offset");
        Check(MetadataDate.FromFilenames(["20240101_000000.jpg"],filenamePattern,"$7")[0] is null, "missing capture cannot invent date");
        Check(MetadataDate.FromFilenames(["20240101_000000_20250101_000000.jpg"],filenamePattern,filenameTemplate)[0]=="2024:01:01 00:00:00", "filename uses first match consistently");
        Reject(()=>MetadataDate.FromFilenames([],filenamePattern,filenameTemplate), "empty filename batch refused");
        Reject(()=>MetadataDate.FromFilenames(Enumerable.Repeat("a",3001).ToArray(),filenamePattern,filenameTemplate), "over-limit filename batch refused");
        Reject(()=>MetadataDate.FromFilenames([new string('a',256)],filenamePattern,filenameTemplate), "over-limit filename refused");
        Reject(()=>MetadataDate.FromFilenames(["a\n"],filenamePattern,filenameTemplate), "filename control character refused");
        Reject(()=>MetadataDate.FromFilenames(["a"],"(",filenameTemplate), "invalid filename regex refused");
        Reject(()=>MetadataDate.FromFilenames(["a"],"(?=a)",filenameTemplate), "backtracking-only regex refused explicitly");
        Reject(()=>MetadataDate.FromFilenames(["a"],new string('a',1025),filenameTemplate), "over-limit filename regex refused");
        Reject(()=>MetadataDate.FromFilenames(["a"],"a",new string('a',513)), "over-limit date template refused");
        Check(MetadataDate.FromFilenames(Enumerable.Repeat(new string('a',250)+"!",3000).ToArray(),"(a+)+$",filenameTemplate).All(value=>value is null), "3000 pathological backtracking inputs complete with native linear engine");
        Console.WriteLine($"Date checks complete: {count}");
    }
    public static async Task RunCopyAsync(ExifToolClient client, string fixtures, string output)
    {
        foreach (var suffix in new[] { "+09:00", ".123456789Z", "" })
        {
            var folder = Path.Combine(output, "date-copy-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
            var photo = await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
            var value = MetadataDate.Parse("2024:02:28 23:59:59" + suffix).Shift(0,0,0,0,0,2).Text;
            photo.SetDraft(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=value});
            var saved = await MetadataCopy.SaveAsync(client,photo,folder); var result = await PhotoDocument.LoadAsync(client,saved);
            if(result.Value("XMP-exif:DateTimeOriginal")!=value || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Date copy mismatch");
            Console.WriteLine("PASS date copy independent reload/source unchanged: " + suffix);
            photo.ClearDraft(); if(photo.Draft.Count!=0)throw new Exception("Undo failed");Console.WriteLine("PASS date copy undo");
            var replacement = MetadataDate.Parse("2024:02:29 23:59:59" + suffix).Replace(year:2025,day:28,hour:0).Text;
            photo.SetDraft(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=replacement});
            var replacedFolder = Path.Combine(folder,"component-replacement");Directory.CreateDirectory(replacedFolder);
            var replaced = await MetadataCopy.SaveAsync(client,photo,replacedFolder);var reread = await PhotoDocument.LoadAsync(client,replaced);
            if(reread.Value("XMP-exif:DateTimeOriginal")!=replacement || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Component copy mismatch");
            Console.WriteLine("PASS component replacement copy preserves suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Component undo failed");Console.WriteLine("PASS component replacement undo");
            var distributedValue = MetadataDate.Distribute("2024:02:29 23:59:59" + suffix,"2024:03:01 00:00:04" + suffix,3)[1];
            photo.SetDraft(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=distributedValue});
            var distributedFolder=Path.Combine(folder,"distribution");Directory.CreateDirectory(distributedFolder);
            var distributedCopy=await MetadataCopy.SaveAsync(client,photo,distributedFolder);var distributedRead=await PhotoDocument.LoadAsync(client,distributedCopy);
            if(distributedRead.Value("XMP-exif:DateTimeOriginal")!=distributedValue || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Distribution copy mismatch");
            Console.WriteLine("PASS distributed date copy preserves suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Distribution undo failed");Console.WriteLine("PASS distributed date undo");
            var filenameValue=MetadataDate.FromFilenames(["旅行_20240229_123456.jpg"],@"([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})","$1:$2:$3 $4:$5:$6"+suffix)[0]!;
            photo.SetDraft(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=filenameValue});
            var filenameFolder=Path.Combine(folder,"filename-date");Directory.CreateDirectory(filenameFolder);
            var filenameCopy=await MetadataCopy.SaveAsync(client,photo,filenameFolder);var filenameRead=await PhotoDocument.LoadAsync(client,filenameCopy);
            if(filenameRead.Value("XMP-exif:DateTimeOriginal")!=filenameValue || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Filename date copy mismatch");
            Console.WriteLine("PASS filename date copy preserves explicit suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Filename date undo failed");Console.WriteLine("PASS filename date undo");
            Console.WriteLine("Evidence " + folder);
        }
    }
}
