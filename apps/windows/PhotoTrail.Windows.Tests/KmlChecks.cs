using System.IO.Compression;
using System.Text;
using PhotoTrail.Windows;

static class KmlChecks
{
    public static void Run()
    {
        static void Check(bool value,string name) { if (!value) throw new Exception(name);Console.WriteLine("PASS "+name); }
        static string Wrap(string body) => "<kml xmlns='http://www.opengis.net/kml/2.2' xmlns:gx='http://www.google.com/kml/ext/2.2'><Document><Placemark>"+body+"</Placemark></Document></kml>";
        static TrackData Parse(string xml) => TrackReader.ReadKml(new MemoryStream(Encoding.UTF8.GetBytes(xml)));
        static MemoryStream Archive(params (string Name,string Text)[] entries)
        {
            var stream=new MemoryStream();
            using(var zip=new ZipArchive(stream,ZipArchiveMode.Create,leaveOpen:true))
                foreach(var (name,text) in entries) { using var writer=new StreamWriter(zip.CreateEntry(name).Open(),new UTF8Encoding(false));writer.Write(text); }
            stream.Position=0;return stream;
        }
        const string timed="<gx:Track><altitudeMode>absolute</altitudeMode><when>2026-10-04T08:00:00.125+08:00</when><when>2026-10-04T00:01:00.125Z</when><gx:coord>120 30 10</gx:coord><gx:coord>122 32 30</gx:coord></gx:Track>";
        var route=Parse(Wrap(timed));
        var middle=route.Match(DateTimeOffset.Parse("2026-10-04T00:00:30.125Z"));
        Check(middle.Status=="matched" && middle.Point!.Latitude==31 && middle.Point.Longitude==121 && middle.Point.Elevation==20,"KML times preserve fractions and UTC offsets for interpolation");
        var lines=Parse(Wrap("<TimeStamp><when>2026-10-04T00:00:00Z</when></TimeStamp><MultiGeometry><LineString><coordinates>120,30,100 121,31,101</coordinates></LineString><LineString><altitudeMode>relativeToGround</altitudeMode><coordinates>122,32,50 123,33,60</coordinates></LineString></MultiGeometry>"));
        Check(lines.Segments.Count==2 && lines.Segments.SelectMany(s=>s).All(p=>p.Time is null && p.Elevation is null),"LineString remains untimed and relative altitude is not invented as sea-level altitude");
        Check(lines.Match(DateTimeOffset.Parse("2026-10-04T00:00:00Z")).Status=="unmatched","feature timestamp cannot enable point matching");
        var gaps=Parse(Wrap("<gx:Track><when>2026-10-04T00:00:00Z</when><when>2026-10-04T00:01:00Z</when><when>2026-10-04T00:02:00Z</when><gx:coord>120 30 0</gx:coord><gx:coord/><gx:coord>122 32 0</gx:coord></gx:Track>"));
        Check(gaps.Segments.Count==2 && gaps.Match(DateTimeOffset.Parse("2026-10-04T00:01:00Z")).Status=="unmatched","empty gx coordinate preserves a real segment gap");
        var external=Parse(Wrap("<NetworkLink><Link><href>https://must-not-load.invalid/x</href></Link></NetworkLink><LineString><coordinates>120,30 121,31</coordinates></LineString>"));
        Check(external.Segments[0].Count==2,"KML external links never fetched");
        foreach(var (xml,name) in new[] {
            (Wrap(""),"empty KML rejected"),("<kml>","damaged KML rejected"),
            (Wrap(timed.Replace("<when>2026-10-04T00:01:00.125Z</when>","")),"point/time count mismatch rejected"),
            (Wrap(timed.Replace("120 30 10","120 91 10")),"KML coordinate outside range rejected"),
            (Wrap(timed.Replace("120 30 10","NaN 30 10")),"nonfinite KML coordinate rejected"),
            ("<!DOCTYPE kml [<!ENTITY data SYSTEM 'file:///not-read'>]><kml>&data;</kml>","KML external entity declaration rejected") })
        {
            try { Parse(xml);throw new Exception("accepted: "+name); }
            catch(Exception error) when(error is InvalidDataException or System.Xml.XmlException) { Console.WriteLine("PASS "+name); }
        }
        using(var archive=Archive(("doc.kml",Wrap(timed)))) Check(TrackReader.ReadKmz(archive).Segments[0].Count==2,"KMZ main KML parsed without disk extraction");
        using(var archive=Archive(("doc.kml",Wrap(timed)),("other.kml",Wrap("")))) Check(TrackReader.ReadKmz(archive).Segments[0].Count==2,"KMZ root doc.kml has explicit priority");
        using(var archive=Archive(("nested/route.kml",Wrap(timed)))) Check(TrackReader.ReadKmz(archive).Segments[0].Count==2,"single nested KML accepted unambiguously");
        foreach(var (entries,name) in new[] {
            (new[]{("../doc.kml",Wrap(timed))},"KMZ traversal path rejected"),
            (new[]{("C:/doc.kml",Wrap(timed))},"KMZ absolute drive path rejected"),
            (new[]{("doc.kml",Wrap(timed)),("DOC.KML",Wrap(timed))},"KMZ duplicate folded names rejected"),
            (new[]{("a.kml",Wrap(timed)),("b.kml",Wrap(timed))},"KMZ ambiguous main document rejected"),
            (new[]{("doc.kml",new string(' ',300000))},"KMZ excessive compression ratio rejected"),
            (Enumerable.Range(0,1025).Select(i=>($"file-{i}.txt","")).ToArray(),"KMZ excessive entry count rejected") })
        {
            using var archive=Archive(entries);
            try { TrackReader.ReadKmz(archive);throw new Exception("accepted: "+name); }
            catch(InvalidDataException) { Console.WriteLine("PASS "+name); }
        }
        using(var archive=new MemoryStream(Encoding.UTF8.GetBytes("not a zip")))
        {
            try { TrackReader.ReadKmz(archive);throw new Exception("Damaged archive accepted"); }
            catch(InvalidDataException) { Console.WriteLine("PASS damaged KMZ rejected"); }
        }
        using(var cancel=new CancellationTokenSource())
        using(var archive=Archive(("doc.kml",Wrap(timed))))
        {
            cancel.Cancel();try { TrackReader.ReadKmz(archive,cancel.Token);throw new Exception("Cancellation ignored"); }
            catch(OperationCanceledException) { Console.WriteLine("PASS KMZ cancellation honored"); }
        }
        Console.WriteLine("KML/KMZ checks complete; GPS writing and real UI remain separate gates.");
        using var split=System.Text.Json.JsonDocument.Parse(TrackMapPayload.Build(new TrackData(new[]{(IReadOnlyList<TrackPoint>)new[]{new TrackPoint(179,10,null,null),new TrackPoint(-179,12,null,null)}}),"date line"));
        var features=split.RootElement.GetProperty("geojson").GetProperty("features");
        Check(features.GetArrayLength()==2 && features[0].GetProperty("geometry").GetProperty("coordinates")[1][0].GetDouble()==180 && features[1].GetProperty("geometry").GetProperty("coordinates")[0][0].GetDouble()==-180,"map lines split at antimeridian without changing canonical track points");
        using var empty=System.Text.Json.JsonDocument.Parse(TrackMapPayload.Build(null,""));
        Check(empty.RootElement.GetProperty("geojson").GetProperty("features").GetArrayLength()==0,"cleared track sends empty geometry");
    }
}
