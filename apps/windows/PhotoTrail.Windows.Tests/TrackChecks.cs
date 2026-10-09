using System.Text;
using PhotoTrail.Windows;

static class TrackChecks
{
    public static void Run()
    {
        static void Check(bool value,string name) { if (!value) throw new Exception(name); Console.WriteLine("PASS " + name); }
        static TrackData Parse(string body) => TrackReader.ReadGpx(new MemoryStream(Encoding.UTF8.GetBytes(body)));
        static string Wrap(string body) => "<gpx xmlns='http://www.topografix.com/GPX/1/1'><trk>" + body + "</trk></gpx>";
        const string a="<trkpt lat='10' lon='179'><ele>100</ele><time>2024-02-29T00:00:00Z</time></trkpt>";
        const string b="<trkpt lat='12' lon='-179'><ele>200</ele><time>2024-02-29T00:02:00Z</time></trkpt>";
        var time=DateTimeOffset.Parse("2024-02-29T00:01:00Z");
        var track=Parse(Wrap("<trkseg>"+a+b+"</trkseg>"));
        Check(track.Segments[0].Count==2,"GPX retains two points");
        var middle=track.Match(time);
        Check(middle.Status=="matched" && middle.Point!.Latitude==11 && Math.Abs(middle.Point.Longitude)==180 && middle.Point.Elevation==150,"same-segment interpolation crosses antimeridian safely");
        Check(track.Match(time.AddMinutes(-1)).Method=="recorded","exact timestamp prefers recorded point");
        Check(track.Match(time.AddMinutes(-2)).Status=="unmatched","no extrapolation before track");
        Check(track.Match(time.AddMinutes(2)).Status=="unmatched","no extrapolation after track");
        Check(track.Match(time,TimeSpan.FromSeconds(30)).Status=="unmatched","long gap refuses interpolation");
        Check(track.Match(time,TimeSpan.Zero).Status=="unmatched","invalid maximum gap rejected");
        var split=Parse(Wrap("<trkseg>"+a+"</trkseg><trkseg>"+b+"</trkseg>"));
        Check(split.Segments.Count==2 && split.Match(time).Status=="unmatched","never bridge segment boundaries");
        var missing=Parse(Wrap("<trkseg>"+a+"<trkpt lat='11' lon='180'/>"+b+"</trkseg>"));
        Check(missing.Match(time).Status=="unmatched","missing point time remains a matching break");
        var reverse=Parse(Wrap("<trkseg>"+b+a+"</trkseg>"));
        Check(reverse.Match(time).Status=="unmatched","backward time refuses interpolation");
        var overlap=Parse(Wrap("<trkseg>"+a+b+"</trkseg><trkseg>"+a.Replace("lat='10'","lat='20'")+b.Replace("lat='12'","lat='22'")+"</trkseg>"));
        Check(overlap.Match(time).Status=="ambiguous","different simultaneous positions are ambiguous");
        var untimed=Parse(Wrap("<trkseg><trkpt lat='0' lon='0'/><trkpt lat='1' lon='1'/></trkseg>"));
        Check(untimed.Segments[0].Count==2 && untimed.Match(time).Status=="unmatched","untimed geometry retained only for display");
        var offset=Parse(Wrap("<trkseg>"+a.Replace("00:00:00Z","09:00:00+09:00")+b+"</trkseg>"));
        Check(offset.Match(time).Status=="matched","UTC offsets align across day/timezone parsing");
        foreach(var (xml,name) in new[] {
            ("<gpx/>","empty GPX rejected"), ("<gpx>","malformed XML rejected"),
            (Wrap("<trkseg>"+a.Replace("lat='10'","lat='91'")+"</trkseg>"),"latitude outside range rejected"),
            (Wrap("<trkseg>"+a.Replace("lon='179'","lon='NaN'")+"</trkseg>"),"nonfinite coordinate rejected"),
            (Wrap("<trkseg>"+a.Replace("2024-02-29","2024-02-30")+"</trkseg>"),"invalid calendar date rejected"),
            (Wrap("<trkseg>"+a.Replace("00:00:00Z","00:00:00")+"</trkseg>"),"missing timestamp timezone rejected"),
            ("<!DOCTYPE gpx [<!ENTITY file SYSTEM 'file:///not-read'>]><gpx>&file;</gpx>","XML external entity declaration rejected") })
        {
            try { Parse(xml); throw new Exception("accepted: " + name); }
            catch(Exception error) when(error is System.Xml.XmlException or InvalidDataException) { Console.WriteLine("PASS " + name); }
        }
        using var cancel=new CancellationTokenSource();cancel.Cancel();
        try { TrackReader.ReadGpx(new MemoryStream(Encoding.UTF8.GetBytes(Wrap("<trkseg>"+a+b+"</trkseg>"))),cancel.Token);throw new Exception("Cancellation ignored"); }
        catch(OperationCanceledException) { Console.WriteLine("PASS GPX cancellation honored"); }
        var fixtures=Environment.GetEnvironmentVariable("PHOTOTRAIL_TRACK_FIXTURES");
        if (!string.IsNullOrWhiteSpace(fixtures))
        {
            foreach(var (name,segments,points) in new[]{("TestTrack.GPX",1,3813),("MultiSeg.GPX",29,9999)})
            {
                var path=Path.Combine(fixtures,name);
                var before=System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path));
                var parsed=TrackReader.ReadGpx(path);
                Check(parsed.Segments.Count==segments && parsed.Segments.Sum(segment=>segment.Count)==points,name+" matches existing Mac fixture geometry counts");
                Check(before.SequenceEqual(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path))),name+" source unchanged");
            }
            foreach(var name in new[]{"NoTrack.GPX","BadTrack.GPX"})
            {
                try { TrackReader.ReadGpx(Path.Combine(fixtures,name));throw new Exception("Invalid fixture accepted: "+name); }
                catch(Exception error) when(error is InvalidDataException or System.Xml.XmlException) { Console.WriteLine("PASS "+name+" rejected"); }
            }
            var real=TrackReader.ReadGpx(Path.Combine(fixtures,"MultiSeg.GPX"));
            Check(real.Match(DateTimeOffset.Parse("2008-04-19T01:20:32Z"),TimeSpan.FromMinutes(1)).Status=="matched","existing Mac fixture inside-coverage match agrees");
            Check(real.Match(DateTimeOffset.Parse("2008-04-18T14:20:00Z"),TimeSpan.FromMinutes(10)).Status=="unmatched","existing Mac fixture outside-coverage match agrees");
        }
        Console.WriteLine("GPX/matching core checks complete; UI, KML/KMZ and GPS write remain pending.");
    }
}
