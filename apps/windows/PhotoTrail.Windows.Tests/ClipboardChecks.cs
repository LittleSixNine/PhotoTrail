using PhotoTrail.Windows;

static class ClipboardChecks
{
    public static async Task RunGpsCopyAsync(ExifToolClient client,string fixtures,string root)
    {
        var folder=Path.Combine(root,"gps-clipboard-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var file=Path.Combine(folder,"target.jpg");File.Copy(Path.Combine(fixtures,"aligned.jpg"),file);
        await client.RunAsync(["-overwrite_original","-XMP-exif:GPSAltitude=25","-XMP-exif:GPSAltitudeRef=1","-XMP-exif:GPSDateTime=2026:10:10 01:00:00Z","--",file]);
        var target=await PhotoDocument.LoadAsync(client,file);
        var source=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));source.SetDraft(PhotoDocument.PositionChanges(new(135.7681,35.0116),12,"GPS"));
        var text=MetadataClipboard.CopyGps(source.Position()!);var point=MetadataClipboard.ReadGps(text);
        var count=0;void Check(bool value,string label){if(!value)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
        Check(point==new MapPoint(135.7681,35.0116),"GPS clipboard uses source draft coordinates");
        target.SetDraft(PhotoDocument.PositionChanges(point,null,"MANUAL"));
        var output=Path.Combine(folder,"copies");Directory.CreateDirectory(output);var saved=await MetadataCopy.SaveAsync(client,target,output);var metadata=await client.ReadAsync(saved);
        Check(Math.Abs(metadata.GetProperty("XMP-exif:GPSLatitude").GetDouble()-35.0116)<1e-8 && Math.Abs(metadata.GetProperty("XMP-exif:GPSLongitude").GetDouble()-135.7681)<1e-8,"GPS clipboard destination copy independently read back");
        Check(!metadata.TryGetProperty("XMP-exif:GPSAltitude",out _) && !metadata.TryGetProperty("XMP-exif:GPSAltitudeRef",out _) && !metadata.TryGetProperty("XMP-exif:GPSDateTime",out _),"coordinate-only paste clears old XMP altitude/reference/time");
        Check(await PhotoDocument.HashAsync(file)==target.SourceHash && await PhotoDocument.HashAsync(source.FilePath)==source.SourceHash,"source and destination originals unchanged");
        Check(await MetadataCopy.JpegPixelsAsync(saved)==await MetadataCopy.JpegPixelsAsync(file),"GPS clipboard copy preserves JPEG pixel payload");
        target.ClearDraft();Check(target.Draft.Count==0,"GPS clipboard draft undo restores source state");
        Console.WriteLine($"GPS clipboard copy checks complete: {count}; evidence {folder}");
    }
    public static void Run()
    {
        var count=0;
        void Check(bool ok,string label){if(!ok)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
        void Reject(Action action,string label){try{action();}catch(ArgumentException){Check(true,label);return;}throw new Exception(label);}
        Check(MetadataClipboard.CommonValue(new[]{"中文\n第二行","中文\n第二行"})=="中文\n第二行","identical raw text preserved");
        Check(MetadataClipboard.CommonValue(new[]{"2026:10:10 12:00:00.123456789Z"}).EndsWith("123456789Z"),"date precision and zone remain raw");
        foreach(var invalid in new[]{Array.Empty<string>(),new[]{""},new[]{"same","different"},new[]{"same",""},new[]{new string('a',8193)},new[]{"x\0y"}})Reject(()=>MetadataClipboard.CommonValue(invalid),"missing mixed or unsafe copy refused");
        var literal="=@literal, \"中文\"\r\n第二行";
        var prepared=MetadataClipboard.Prepare(literal,new[]{"XMP-dc:Title","XMP-dc:Description","XMP-dc:Title"});Check(prepared.Count==2 && prepared.Values.All(value=>value==literal.Replace("\r\n","\n")),"paste is literal and targets deduplicate");
        Check(MetadataClipboard.Prepare("",new[]{"XMP-dc:Title"})["XMP-dc:Title"]=="","explicit empty text can clear target");
        foreach(var tags in new[]{Array.Empty<string>(),new[]{"EXIF:Artist"},new[]{"XMP-exif:GPSLatitude"}})Reject(()=>MetadataClipboard.Prepare("0",tags),"unselected or unapproved target refused");
        foreach(var text in new[]{"invalid date","2023:02:29 00:00:00","2026:01:01 00:00:00+15:00"})Reject(()=>MetadataClipboard.Prepare(text,new[]{"XMP-dc:Title","XMP-exif:DateTimeOriginal"}),"invalid date refuses whole target set");
        Reject(()=>MetadataClipboard.Prepare("US",new[]{"XMP-dc:Title","XMP-iptcCore:CountryCode"}),"invalid country code refuses all targets");
        Reject(()=>MetadataClipboard.Prepare("x\ny",new[]{"XMP-dc:Title","XMP-photoshop:City"}),"region newline refuses all targets");
        Reject(()=>MetadataClipboard.Prepare(new string('a',8193),new[]{"XMP-dc:Title"}),"oversized literal refused");
        foreach(var point in new[]{new MapPoint(135.7681,35.0116),new MapPoint(-122.4,-37.2),new MapPoint(0,0),new MapPoint(180,90),new MapPoint(-180,-90)})
            Check(MetadataClipboard.ReadGps(MetadataClipboard.CopyGps(point))==point,"GPS coordinate literal round trip");
        foreach(var point in new[]{new MapPoint(181,0),new MapPoint(0,91),new MapPoint(double.NaN,0),new MapPoint(0,double.PositiveInfinity),new MapPoint(180.000000001,0),new MapPoint(0,90.000000001)})
            Reject(()=>MetadataClipboard.CopyGps(point),"invalid GPS copy refused before changing clipboard");
        var gps=MetadataClipboard.CopyGps(new(135.7681,35.0116));
        foreach(var text in new[]{"","{","[]","null",gps.Replace("GPS 1","GPS 2"),gps.Replace("35.0116","91"),gps.Replace("135.7681","181"),gps.Replace("135.7681","180.000000001"),gps.Replace("35.0116","90.000000001"),gps.Replace("35.0116","\"35.0116\""),gps.Replace("35.0116","true"),gps.Replace("35.0116","1e9999"),gps.Replace("\"latitude\":35.0116,",""),gps.Replace("\"latitude\":35.0116,","\"latitude\":35.0116,\"latitude\":0,"),gps.TrimEnd('}')+",\"path\":\"unapproved\"}",gps+new string(' ',4097)})
            Reject(()=>MetadataClipboard.ReadGps(text),"invalid ambiguous or oversized GPS clipboard refused");
        var positionChanges=PhotoDocument.PositionChanges(MetadataClipboard.ReadGps(gps),null,"MANUAL");
        Check(positionChanges["XMP-exif:GPSMapDatum"]=="WGS-84" && positionChanges["XMP-exif:GPSAltitude"]=="" && positionChanges["XMP-exif:GPSAltitudeRef"]=="" && positionChanges["XMP-exif:GPSDateTime"]=="","coordinate-only paste clears unknown XMP altitude and measurement time");        Console.WriteLine($"Clipboard checks complete: {count}");
    }
}
