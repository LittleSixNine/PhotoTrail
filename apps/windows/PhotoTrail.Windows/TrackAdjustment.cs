using System.Globalization;
using System.IO;
using System.Text;
using System.Xml;

namespace PhotoTrail.Windows;

public static class TrackAdjustment
{
    // shortcut: approved mean-radius sphere below 85° and up to 100km; use geodesics only if the contract expands.
    public static TrackData Adjust(TrackData source,double seconds,double east,double north,CancellationToken token=default)
    {
        double distance=double.Hypot(east,north);
        if(!double.IsFinite(seconds)||!double.IsFinite(east)||!double.IsFinite(north)||distance>100000||Math.Abs(seconds)>315576000)
            throw new ArgumentException("轨迹偏移须为有限数；距离最多100公里，时间最多315576000秒。");
        if(source.Segments.Count==0||source.Segments.Sum(s=>s.Count) is <1 or >1000000)throw new InvalidDataException("轨迹点数无效。");
        if(seconds!=0&&!source.Segments.Any(s=>s.Any(p=>p.Time is not null)))throw new ArgumentException("整条轨迹没有时间，不能调整时间。");
        double bearing=Math.Atan2(east,north),angular=distance/6371008.8,radians=Math.PI/180;
        long ticks=checked((long)Math.Round(seconds*TimeSpan.TicksPerSecond,MidpointRounding.AwayFromZero));
        var segments=new List<IReadOnlyList<TrackPoint>>();
        foreach(var segment in source.Segments) {
            var points=new List<TrackPoint>();
            foreach(var point in segment) {
                token.ThrowIfCancellationRequested();
                double latitude=point.Latitude,longitude=point.Longitude;
                if(!double.IsFinite(latitude)||!double.IsFinite(longitude)||Math.Abs(latitude)>90||Math.Abs(longitude)>180||point.Elevation is {} height&&!double.IsFinite(height))throw new InvalidDataException("轨迹点无效。");
                if(distance>0) {
                    if(Math.Abs(latitude)>=85)throw new InvalidDataException("空间调整的输入／输出纬度须在南北85度以内。");
                    double lat=latitude*radians,lon=longitude*radians;
                    double moved=Math.Asin(Math.Sin(lat)*Math.Cos(angular)+Math.Cos(lat)*Math.Sin(angular)*Math.Cos(bearing));
                    latitude=moved/radians;
                    longitude=(lon+Math.Atan2(Math.Sin(bearing)*Math.Sin(angular)*Math.Cos(lat),Math.Cos(angular)-Math.Sin(lat)*Math.Sin(moved)))/radians;
                    longitude=(longitude+540)%360-180;
                    if(!double.IsFinite(latitude)||!double.IsFinite(longitude)||Math.Abs(latitude)>=85)throw new InvalidDataException("空间调整输出纬度越界。");
                }
                DateTimeOffset? time=null;
                if(point.Time is {} original) {
                    try { time=original.AddTicks(ticks); }
                    catch(ArgumentOutOfRangeException error){throw new InvalidDataException("调整后的时间须在年份1至9999内。",error);}
                }
                points.Add(new(longitude,latitude,point.Elevation,time));
            }
            segments.Add(points);
        }
        token.ThrowIfCancellationRequested();return new(segments);
    }
    public static bool Equal(TrackData first,TrackData second)=>first.Segments.Count==second.Segments.Count&&first.Segments.Zip(second.Segments).All(pair=>pair.First.SequenceEqual(pair.Second));
    public static bool SameCoordinates(TrackData first,TrackData second)=>first.Segments.Count==second.Segments.Count&&first.Segments.Zip(second.Segments).All(pair=>pair.First.Count==pair.Second.Count&&pair.First.Zip(pair.Second).All(p=>p.First.Longitude==p.Second.Longitude&&p.First.Latitude==p.Second.Latitude));
    public static async Task ExportAsync(TrackData data,string source,string target,CancellationToken token=default)
    {
        source=Path.GetFullPath(source);target=Path.GetFullPath(target);
        if(source.Equals(target,StringComparison.OrdinalIgnoreCase)||File.Exists(target))throw new IOException("GPX另存不能覆盖源文件或已有目标。");
        if(!Path.GetExtension(target).Equals(".gpx",StringComparison.OrdinalIgnoreCase))throw new ArgumentException("导出目标须为新GPX文件。");
        _=Adjust(data,0,0,0,token);
        string temporary=Path.Combine(Path.GetDirectoryName(target)!,".track-export-"+Guid.NewGuid().ToString("N"));
        try {
            await Task.Run(()=>{
                using var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None);
                using(var xml=XmlWriter.Create(output,new XmlWriterSettings{Encoding=new UTF8Encoding(false),Indent=true,CloseOutput=false})) {
                    xml.WriteStartDocument();xml.WriteStartElement("gpx","http://www.topografix.com/GPX/1/1");xml.WriteAttributeString("version","1.1");xml.WriteAttributeString("creator","PhotoTrail Windows");xml.WriteStartElement("trk");
                    foreach(var segment in data.Segments){xml.WriteStartElement("trkseg");foreach(var point in segment){token.ThrowIfCancellationRequested();xml.WriteStartElement("trkpt");xml.WriteAttributeString("lat",point.Latitude.ToString("R",CultureInfo.InvariantCulture));xml.WriteAttributeString("lon",point.Longitude.ToString("R",CultureInfo.InvariantCulture));if(point.Elevation is {} elevation)xml.WriteElementString("ele",elevation.ToString("R",CultureInfo.InvariantCulture));if(point.Time is {} time)xml.WriteElementString("time",time.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",CultureInfo.InvariantCulture));xml.WriteEndElement();}xml.WriteEndElement();}
                    xml.WriteEndElement();xml.WriteEndElement();xml.WriteEndDocument();
                }
                output.Flush(true);
            },token);
            var read=await Task.Run(()=>TrackReader.ReadGpx(temporary,token),token);
            if(!Equal(data,read))throw new IOException("GPX回读不一致，未交付目标文件。");
            token.ThrowIfCancellationRequested();File.Move(temporary,target,overwrite:false);
        }finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
}
