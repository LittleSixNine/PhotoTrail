using PhotoTrail.Windows;

static class GpsChecks
{
    public static async Task RunAsync(ExifToolClient client,string fixtures,string evidence)
    {
        static void Check(bool value,string name) { if(!value)throw new Exception(name);Console.WriteLine("PASS "+name); }
        var folder=Path.Combine(evidence,"gps-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var photo=await PhotoDocument.LoadAsync(client,Path.Combine(fixtures,"aligned.jpg"));
        photo.SetDraft(PhotoDocument.PositionChanges(new(-135.77,-35.01),-12.5,"GPS"));
        Check(photo.Position() is {Latitude:-35.01,Longitude:-135.77},"GPS draft displays signed WGS84 coordinates");
        var saved=await MetadataCopy.SaveAsync(client,photo,folder);
        var metadata=await client.ReadAsync(saved);
        Check(Math.Abs(metadata.GetProperty("XMP-exif:GPSLatitude").GetDouble()+35.01)<0.00000001 && Math.Abs(metadata.GetProperty("XMP-exif:GPSLongitude").GetDouble()+135.77)<0.00000001,"GPS hemisphere signs independently read back");
        Check(metadata.GetProperty("XMP-exif:GPSAltitude").GetDouble()==12.5 && metadata.GetProperty("XMP-exif:GPSAltitudeRef").GetInt32()==1,"below-sea-level altitude magnitude and reference preserved");
        Check(metadata.GetProperty("XMP-exif:GPSMapDatum").ToString()=="WGS-84" && metadata.GetProperty("XMP-exif:GPSProcessingMethod").ToString()=="GPS","GPS datum and tracking method independently read back");
        Check(await PhotoDocument.HashAsync(photo.FilePath)==photo.SourceHash && await MetadataCopy.JpegPixelsAsync(saved)==await MetadataCopy.JpegPixelsAsync(photo.FilePath),"GPS copy preserves original and JPEG pixel payload");
        var reopened=await PhotoDocument.LoadAsync(client,saved);
        Check(reopened.Position() is {Latitude:-35.01,Longitude:-135.77},"saved GPS copy reopens with correct marker position");
        reopened.SetDraft(PhotoDocument.PositionChanges(new(0,0),null,"MANUAL"));
        var second=Path.Combine(folder,"manual");Directory.CreateDirectory(second);
        var manual=await MetadataCopy.SaveAsync(client,reopened,second);var cleared=await client.ReadAsync(manual);
        Check(!cleared.TryGetProperty("XMP-exif:GPSAltitude",out _) && !cleared.TryGetProperty("XMP-exif:GPSAltitudeRef",out _),"manual position clears stale XMP altitude when unknown");
        Check(cleared.GetProperty("XMP-exif:GPSLatitude").GetDouble()==0 && cleared.GetProperty("XMP-exif:GPSLongitude").GetDouble()==0,"zero coordinates are valid positions");
        foreach(var point in new[]{new MapPoint(181,0),new MapPoint(0,91),new MapPoint(double.NaN,0),new MapPoint(180.000000001,0),new MapPoint(0,90.000000001)})
        {
            try {PhotoDocument.PositionChanges(point,null,"MANUAL");throw new Exception("Invalid GPS accepted");}
            catch(ArgumentException){Console.WriteLine("PASS invalid GPS draft rejected before mutation");}
        }
        photo.ClearDraft();Check(photo.Draft.Count==0,"GPS undo clears all position drafts");
        Check(MapMessage.TryPhoto(MapMessage.Page,"{\"type\":\"select-photo\",\"id\":0,\"revision\":2}",out var id,out var revision) && id==0 && revision==2,"trusted photo marker selection parsed");
        Check(!MapMessage.TryPhoto("https://unexpected.invalid/","{\"type\":\"select-photo\",\"id\":0,\"revision\":2}",out _,out _),"foreign photo marker selection rejected");
        foreach(var json in new[]{"{}","[]","{\"type\":\"select-photo\",\"id\":-1,\"revision\":2}","{\"type\":\"select-photo\",\"id\":\"bad\",\"revision\":2}"})
            Check(!MapMessage.TryPhoto(MapMessage.Page,json,out _,out _),"invalid photo marker message rejected");
        Console.WriteLine("GPS copy and marker checks complete: "+folder);
    }
}
