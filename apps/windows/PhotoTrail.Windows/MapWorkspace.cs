using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
namespace PhotoTrail.Windows;
public sealed record FavoriteLocation(Guid Id,string Name,string Note,MapPoint Point) {
 public override string ToString()=>Name+(Note.Length>0?" · "+Note:"");
 internal void Validate(){if(Id==Guid.Empty||Point is null||!MapWorkspace.Valid(Point))throw new ArgumentException("收藏身份或WGS84坐标无效。");RenameSchemeLibrary.Label(Name,false,100);RenameSchemeLibrary.Label(Note,true,1000);}
}
public sealed record MapViewport(double Longitude,double Latitude,double Zoom) {
 internal bool Valid=>MapWorkspace.Valid(new(Longitude,Latitude))&&double.IsFinite(Zoom)&&Zoom is >=0 and <=22;
}
public sealed record MapWorkspaceState(string Format,int Version,FavoriteLocation[] Favorites,bool SelectedOnly=false,string GoogleLayer="roadmap",MapViewport? OpenView=null,bool StartWithDevice=true) {
 internal void Validate(){if(Format!="phototrail-windows-map-workspace"||Version!=1||Favorites is null||Favorites.Length>1000||Favorites.Any(f=>f is null)||Favorites.Select(f=>f.Id).Distinct().Count()!=Favorites.Length||GoogleLayer is not("roadmap" or "satellite" or "hybrid" or "terrain")||OpenView is {} v&&!v.Valid)throw new InvalidDataException("收藏或地图偏好结构无效；未覆盖。");foreach(var f in Favorites)f.Validate();}
}
public sealed record MapWorkspaceSnapshot(MapWorkspaceState State,string Revision);
public static class MapWorkspace {
 public static string DefaultPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_MAP_WORKSPACE")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","map-workspace-v1.json");
 public static bool Valid(MapPoint p)=>double.IsFinite(p.Longitude)&&double.IsFinite(p.Latitude)&&Math.Abs(p.Longitude)<=180&&Math.Abs(p.Latitude)<=90;
 static readonly JsonSerializerOptions Json=new(){PropertyNamingPolicy=JsonNamingPolicy.CamelCase};
 static string Revision(string path)=>File.Exists(path)?Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))):"missing";
 static void CheckFile(string path){if(!File.Exists(path))return;if(new FileInfo(path).Length>1024*1024||(File.GetAttributes(path)&(FileAttributes.ReparsePoint|FileAttributes.ReadOnly))!=0)throw new IOException("收藏文件过大、只读或链接，未覆盖。");}
 public static MapWorkspaceSnapshot Read(string path){CheckFile(path);if(!File.Exists(path))return new(new("phototrail-windows-map-workspace",1,[]),"missing");using var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);using var reader=new StreamReader(input,new System.Text.UTF8Encoding(false,true),false);var text=reader.ReadToEnd();var state=RenameSchemeLibrary.Decode<MapWorkspaceState>(text);state.Validate();return new(state,Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text))));}
 public static MapWorkspaceSnapshot Save(string path,MapWorkspaceSnapshot expected,MapWorkspaceState state){state.Validate();var bytes=JsonSerializer.SerializeToUtf8Bytes(state,Json);if(bytes.Length>1024*1024)throw new ArgumentException("收藏文件超过1MiB。");var full=Path.GetFullPath(path);Directory.CreateDirectory(Path.GetDirectoryName(full)!);CheckFile(full+".guard");using var gate=new FileStream(full+".guard",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);CheckFile(full);var current=Read(full);if(current.Revision!=expected.Revision)throw new IOException("另一实例改变了收藏/偏好；当前输入保留，请重读后处理冲突。");SettingsPreference.WriteJson(full,JsonSerializer.SerializeToElement(state,Json));return new(state,Revision(full));}
 public static FavoriteLocation[] Upsert(FavoriteLocation[] entries,FavoriteLocation value){value.Validate();return entries.Any(f=>f.Id==value.Id)?entries.Select(f=>f.Id==value.Id?value:f).ToArray():entries.Append(value).ToArray();}
 // Only our exact local page and known epoch may report view/system-location results.
 internal static bool Message(string source,string json,out string kind,out int epoch,out MapViewport? view){kind="";epoch=-1;view=null;if(source is not(MapMessage.Page or MapMessage.GooglePage)||json.Length>1024)return false;try{using var doc=JsonDocument.Parse(json);var r=doc.RootElement;var fields=r.EnumerateObject().ToArray();kind=r.GetProperty("type").GetString()!;epoch=r.GetProperty("epoch").GetInt32();if(epoch<0||fields.Select(p=>p.Name).Distinct().Count()!=fields.Length)return false;string[] keys=kind is "view" or "located"?["type","epoch","longitude","latitude","zoom"]:kind is "view-moved" or "location-error"?["type","epoch"]:[];if(keys.Length==0||fields.Length!=keys.Length||fields.Any(p=>!keys.Contains(p.Name)))return false;if(keys.Length==5){view=new(r.GetProperty("longitude").GetDouble(),r.GetProperty("latitude").GetDouble(),r.GetProperty("zoom").GetDouble());if(!view.Valid)return false;}return true;}catch(Exception e)when(e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException){return false;}}
}
