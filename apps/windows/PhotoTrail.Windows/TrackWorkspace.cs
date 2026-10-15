using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
namespace PhotoTrail.Windows;
internal sealed record TrackWorkspaceEntry(string Path,bool Visible=true);
internal sealed record TrackWorkspaceState(int Version,TrackWorkspaceEntry[] Entries,string? Selected=null) {
 internal void Validate(){if(Version!=1||Entries is null||Entries.Length>1000||Entries.Any(e=>e is null||!System.IO.Path.IsPathFullyQualified(e.Path)||e.Path.Length>2048||e.Path.Any(char.IsControl)||System.IO.Path.GetExtension(e.Path).ToLowerInvariant() is not(".gpx" or ".kml" or ".kmz"))||Entries.Select(e=>e.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=Entries.Length||Selected is not null&&!Entries.Any(e=>e.Path==Selected))throw new InvalidDataException("轨迹工作区版本/路径/选择无效，未覆盖。");}
}
internal sealed record TrackWorkspaceSnapshot(TrackWorkspaceState State,string Revision);
internal static class TrackWorkspace {
 internal static string DefaultPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_TRACK_WORKSPACE")??TrackHistory.DefaultPath+".workspace-v1.json";
 static readonly JsonSerializerOptions Json=new(){PropertyNamingPolicy=JsonNamingPolicy.CamelCase,AllowDuplicateProperties=false,RespectRequiredConstructorParameters=true,RespectNullableAnnotations=true,UnmappedMemberHandling=JsonUnmappedMemberHandling.Disallow};
 internal static TrackWorkspaceSnapshot Read(string path){if(!File.Exists(path))return new(new(1,[]),"missing");using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);if(stream.Length>1024*1024||(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("工作区文件过大或为链接。");using var memory=new MemoryStream();stream.CopyTo(memory);var bytes=memory.ToArray();var state=JsonSerializer.Deserialize<TrackWorkspaceState>(bytes,Json)??throw new InvalidDataException("工作区为空。");state.Validate();return new(state,Convert.ToHexString(SHA256.HashData(bytes)));}
 internal static async Task<TrackWorkspaceSnapshot> SaveAsync(string path,TrackWorkspaceSnapshot expected,TrackWorkspaceState state,CancellationToken token=default){state.Validate();return await Task.Run(()=>{Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path))!);if(File.Exists(path+".guard")&&(File.GetAttributes(path+".guard")&FileAttributes.ReparsePoint)!=0)throw new IOException("工作区锁为链接。");using var gate=new FileStream(path+".guard",FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);var current=Read(path);if(current.Revision!=expected.Revision)throw new IOException("另一实例改变工作区，当前轨迹保持；重新读取后处理冲突。");var bytes=JsonSerializer.SerializeToUtf8Bytes(state,Json);if(bytes.Length>1024*1024)throw new IOException("工作区超过1MiB。");token.ThrowIfCancellationRequested();SettingsPreference.WriteJson(path,JsonSerializer.SerializeToElement(state,Json));return new TrackWorkspaceSnapshot(state,Convert.ToHexString(SHA256.HashData(bytes)));},token);}
}
