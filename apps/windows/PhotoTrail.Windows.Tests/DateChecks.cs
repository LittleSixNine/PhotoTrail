using System.IO;
using PhotoTrail.Windows;
static class DateChecks
{
    static async Task<string[]> Kernel(WireItem item) {
        var adapter=new DateAdapter(Path.Combine(AppContext.BaseDirectory,"DateHost","DateHost.exe"),DatePagePreview.Source);
        var result=(await adapter.ComputeAsync(new[]{new DateJob(item)},0,()=>0))[0];
        if(result.Error is {} error)throw new ArgumentException(error.Code);return result.Values!;
    }
    public static async Task RunAsync() {
        int passed=0;void Check(bool value,string name){if(!value)throw new Exception(name);passed++;}
        var tags=new[]{"XMP-exif:DateTimeOriginal","XMP-exif:DateTimeDigitized","XMP-xmp:CreateDate","XMP-xmp:ModifyDate"};
        foreach(var tag in tags)foreach(var suffix in new[]{"","Z","+09:00","-00:00","+14:00","-14:00"}.Concat(Enumerable.Range(1,9).Select(n=>"."+new string('1',n)+"-00:00"))) {
            var value="2024:02:29 01:02:03"+suffix;var proof=await VerifiedMetadataDates.CreateAsync(new Dictionary<string,string>{{tag,value}});proof.Require(new Dictionary<string,string>{{tag,value}});Check(proof.Measurements.Count==1,"real pinned host field validation "+tag+suffix);
        }
        foreach(var value in new[]{"2023:02:29 00:00:00","2024:04:31 00:00:00","2024:01:01 24:00:00","2024:01:01 00:00:00+14:01","2024:01:01 00:00:00+15:00","2024:01:01 00:00:00.1234567890","2024:01:01 00:00:00\n"," 2024:01:01 00:00:00"}) {
            try{_=await VerifiedMetadataDates.CreateAsync(new Dictionary<string,string>{{tags[0],value}});throw new Exception("invalid date accepted");}catch(ArgumentException){passed++;}
        }
        var projections=await VerifiedPhotoDate.InspectAsync(new[]{"2024:01:01 01:02:03+09:00","2024:01:01 01:02:03-00:00","2024:01:01 01:02:03.123456700Z","2024:01:01 01:02:03.123456789Z","2024:01:01 01:02:03"});
        Check(projections["2024:01:01 01:02:03+09:00"]!.Instant()!.Value.Offset==TimeSpan.FromHours(9),"explicit offset projection");Check(projections["2024:01:01 01:02:03-00:00"]!.Instant()!.Value.Offset==TimeSpan.Zero,"negative zero projection text retained");Check(projections["2024:01:01 01:02:03.123456700Z"]!.Instant()!.Value.Ticks%TimeSpan.TicksPerSecond==1234567,"exact native ticks");Check(projections["2024:01:01 01:02:03.123456789Z"]!.Instant() is null,"sub-tick match not rounded");Check(projections["2024:01:01 01:02:03"]!.Instant() is null,"wall clock not absolute");
        var clear=await VerifiedMetadataDates.CreateAsync(new Dictionary<string,string>{{tags[0],""}});Check(clear.Measurements.Count==0,"clear is not normalize");
        var many=await VerifiedMetadataDates.CreateAsync(tags.Select(tag=>new KeyValuePair<string,string>(tag,"2024:01:01 00:00:00.123456789Z")));Check(many.CandidateCount==4&&many.Measurements.Count==1,"four fields one pinned host request");
        foreach(var text in new[]{"1582:10:04 00:00:00","1582:10:05 00:00:00","1582:10:14 00:00:00","1582:10:15 00:00:00","1500:02:29 00:00:00"}) {
            var result=await VerifiedPhotoDate.InspectAsync(new[]{text});Console.WriteLine("OBSERVED "+text+" shared="+(result[text] is null?"invalid":"valid")+" projection="+(result[text]?.WallProjection is null?"unsupported":"native modern"));passed++;
        }
        Console.WriteLine("SHARED_ENTRY_DATE_CHECKS="+passed+"; historical observations separate; retired independent C# 92 check baseline is historical");
    }
    public static async Task RunCopyAsync(ExifToolClient client, string fixtures, string output)
    {
        foreach (var suffix in new[] { "+09:00", ".123456789Z", "" })
        {
            var folder = Path.Combine(output, "date-copy-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
            var photo = await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
            var value = (await Kernel(new WireItem("copy","shift","2024:02:28 23:59:59"+suffix,Seconds:2)))[0];
            await photo.SetDraftAsync(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=value});
            var saved = await MetadataCopy.SaveAsync(client,photo,folder); var result = await PhotoDocument.LoadAsync(client,saved);
            if(result.Value("XMP-exif:DateTimeOriginal")!=value || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Date copy mismatch");
            Console.WriteLine("PASS date copy independent reload/source unchanged: " + suffix);
            photo.ClearDraft(); if(photo.Draft.Count!=0)throw new Exception("Undo failed");Console.WriteLine("PASS date copy undo");
            var replacement = (await Kernel(new WireItem("copy","replaceAtomic","2024:02:29 23:59:59"+suffix,Components:new(){["year"]=2025,["day"]=28,["hour"]=0})))[0];
            await photo.SetDraftAsync(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=replacement});
            var replacedFolder = Path.Combine(folder,"component-replacement");Directory.CreateDirectory(replacedFolder);
            var replaced = await MetadataCopy.SaveAsync(client,photo,replacedFolder);var reread = await PhotoDocument.LoadAsync(client,replaced);
            if(reread.Value("XMP-exif:DateTimeOriginal")!=replacement || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Component copy mismatch");
            Console.WriteLine("PASS component replacement copy preserves suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Component undo failed");Console.WriteLine("PASS component replacement undo");
            var distributedValue = (await Kernel(new WireItem("copy","distribute","2024:02:29 23:59:59"+suffix,Count:3,End:"2024:03:01 00:00:04"+suffix)))[1];
            await photo.SetDraftAsync(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=distributedValue});
            var distributedFolder=Path.Combine(folder,"distribution");Directory.CreateDirectory(distributedFolder);
            var distributedCopy=await MetadataCopy.SaveAsync(client,photo,distributedFolder);var distributedRead=await PhotoDocument.LoadAsync(client,distributedCopy);
            if(distributedRead.Value("XMP-exif:DateTimeOriginal")!=distributedValue || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Distribution copy mismatch");
            Console.WriteLine("PASS distributed date copy preserves suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Distribution undo failed");Console.WriteLine("PASS distributed date undo");
            var filenameValue=(await Kernel(new WireItem("copy","normalize",MetadataDate.ExtractFilenames(["旅行_20240229_123456.jpg"],@"([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})","$1:$2:$3 $4:$5:$6"+suffix)[0])))[0];
            await photo.SetDraftAsync(new Dictionary<string,string>{["XMP-exif:DateTimeOriginal"]=filenameValue});
            var filenameFolder=Path.Combine(folder,"filename-date");Directory.CreateDirectory(filenameFolder);
            var filenameCopy=await MetadataCopy.SaveAsync(client,photo,filenameFolder);var filenameRead=await PhotoDocument.LoadAsync(client,filenameCopy);
            if(filenameRead.Value("XMP-exif:DateTimeOriginal")!=filenameValue || await PhotoDocument.HashAsync(photo.FilePath)!=photo.SourceHash)throw new Exception("Filename date copy mismatch");
            Console.WriteLine("PASS filename date copy preserves explicit suffix/source: " + suffix);
            photo.ClearDraft();if(photo.Draft.Count!=0)throw new Exception("Filename date undo failed");Console.WriteLine("PASS filename date undo");
            Console.WriteLine("Evidence " + folder);
        }
    }
}
