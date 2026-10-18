using System.Diagnostics;
using System.IO;
using System.Text.Json;
namespace PhotoTrail.Windows;

internal sealed record InplaceRecord(int Version,string Id,string Photo,string Target,string Canonical,string BackupRoot,string Backup,string Stage,string OriginalHash,FileProperties Original,long Revision,Dictionary<string,string> Fields,string Phase,string? NewHash=null,FileIdentity? NewIdentity=null,string? RestoreHash=null,FileIdentity? RestoreIdentity=null,string? Detail=null,string? SourceHash=null,FileIdentity? SourceIdentity=null,FileProperties? SavedProperties=null,FileProperties? BeforeRestoreProperties=null,string? BeforeRestorePath=null);
internal static class InplaceHistory
{
    internal static string DirectoryPath=>Environment.GetEnvironmentVariable("PHOTOTRAIL_INPLACE_HISTORY")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PhotoTrail","Windows","InplaceHistory");
    internal static string PathFor(string id)=>Path.Combine(DirectoryPath,"inplace-"+id+".jsonl");
    internal static bool Pending(InplaceRecord record)=>record.Phase is not("saved" or "restored" or "failed" or "cancelled");
    internal static InplaceRecord[] ReadAll() {
        if(!Directory.Exists(DirectoryPath))return [];
        var records=Directory.EnumerateFiles(DirectoryPath,"inplace-*.jsonl").Select(path=>Read(path,inspectPaths:false)).ToArray();
        // One discovery validates every record, but a shared volume/root needs only one physical query.
        foreach(var root in records.SelectMany(r=>new[]{r.Target,r.Photo,r.BackupRoot}).Select(path=>Path.GetPathRoot(Path.GetFullPath(path))!).Distinct(StringComparer.OrdinalIgnoreCase))InplaceNative.RequireLocalVolume(root);
        foreach(var group in records.GroupBy(r=>r.BackupRoot,StringComparer.OrdinalIgnoreCase)) {
            using var parents=SavePaths.LockParents(Path.Combine(group.Key,"boundary"),true);
            var canonical=SavePaths.Canonical(Path.Combine(group.Key,"boundary"));
            if(group.Any(r=>r.Canonical==canonical))throw new InvalidDataException("备份与目标冲突。");
        }
        return records.OrderByDescending(r=>File.GetCreationTimeUtc(PathFor(r.Id))).ToArray();
    }
    internal static InplaceRecord Read(string path,bool inspectPaths=true) {
        using var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite);
        if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("链接恢复记录拒绝。 ");
        if(input.Length is 0 or >2097152)throw new InvalidDataException("恢复记录为空或过大；不得当作没有待处理事务。");
        using var reader=new StreamReader(input);InplaceRecord? last=null;
        while(reader.ReadLine() is {} line){var next=JsonSerializer.Deserialize<InplaceRecord>(line)??throw new InvalidDataException("恢复记录损坏。");if(last is not null&&(last.Photo!=next.Photo||last.Canonical!=next.Canonical||last.BackupRoot!=next.BackupRoot||last.Stage!=next.Stage||last.SourceHash!=next.SourceHash||last.SourceIdentity!=next.SourceIdentity||last.Version!=next.Version||last.NewHash is not null&&last.NewHash!=next.NewHash||last.NewIdentity is not null&&last.NewIdentity!=next.NewIdentity||last.SavedProperties is not null&&last.SavedProperties!=next.SavedProperties||last.Id!=next.Id||last.Target!=next.Target||last.Backup!=next.Backup||last.OriginalHash!=next.OriginalHash||last.Original!=next.Original||last.Revision!=next.Revision||!last.Fields.OrderBy(p=>p.Key).SequenceEqual(next.Fields.OrderBy(p=>p.Key))))throw new InvalidDataException("恢复记录身份改变。");Validate(next,path,inspectPaths:inspectPaths&&last is null);last=next;}
        if(last is null)throw new InvalidDataException("恢复记录无有效阶段。");
        // Paths are invariant across every validated phase; inspect them again at the read boundary.
        Validate(last,path,inspectPaths);return last;
    }
    static void Validate(InplaceRecord r,string path,bool inspectPaths=true) {
        if(inspectPaths){InplaceNative.RequireLocalVolume(r.Target);InplaceNative.RequireLocalVolume(r.Photo);InplaceNative.RequireLocalVolume(r.BackupRoot);}
        bool Hash(string? value)=>value is {Length:64}&&value.All(Uri.IsHexDigit);
        if(r.Version is not(1 or 2)||!Guid.TryParseExact(r.Id,"N",out _)||Path.GetFullPath(path)!=Path.GetFullPath(PathFor(r.Id))||!Hash(r.OriginalHash)||r.NewHash is not null&&!Hash(r.NewHash)||r.RestoreHash is not null&&!Hash(r.RestoreHash))throw new InvalidDataException("恢复记录版本／任务／SHA无效。");
        if(r.Photo!=r.Target&&!r.Target.Equals(Path.ChangeExtension(r.Photo,".xmp"),StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("原图与实际旁车目标关系不匹配。");
        if(!Path.IsPathFullyQualified(r.Target)||!Path.IsPathFullyQualified(r.Photo)||!Path.IsPathFullyQualified(r.BackupRoot)||Path.GetFullPath(r.Backup)!=Path.Combine(Path.GetFullPath(r.BackupRoot),r.Id,Path.GetFileName(r.Target)+".backup")||Path.GetFullPath(r.Stage)!=Path.Combine(Path.GetDirectoryName(r.Target)!,".phototrail-inplace-"+r.Id))throw new InvalidDataException("恢复记录路径边界无效。");
        if(inspectPaths&&SavePaths.Canonical(r.BackupRoot+Path.DirectorySeparatorChar+"boundary") == r.Canonical||Path.GetFullPath(r.Target)==Path.GetFullPath(r.Backup))throw new InvalidDataException("备份与目标冲突。");
        if(r.Phase is not("prepared" or "backed-up" or "staged" or "committing" or "readback" or "saved" or "unknown" or "failed" or "cancelled" or "restoring" or "restore-committing" or "restored"))throw new InvalidDataException("恢复记录阶段未知。");
        if(r.Version==1&&(r.Fields.Keys.Any(MetadataTimes.IsSystem)||r.SavedProperties is not null)||r.Version==2&&!r.Fields.Keys.Any(MetadataTimes.IsSystem)||r.Version==2&&r.NewIdentity is not null&&(r.SavedProperties is null||r.SavedProperties.Identity!=r.NewIdentity))throw new InvalidDataException("恢复版本／保存后属性缺失或不匹配。");
        if(r.SavedProperties is not null&&r.SavedProperties with{Identity=r.Original.Identity}!=MetadataTimes.Requested(r.Original,r.Fields))throw new InvalidDataException("保存后属性不符合冻结字段请求。");
        if(r.BeforeRestorePath is not null&&(r.BeforeRestoreProperties is null||Path.GetDirectoryName(Path.GetFullPath(r.BeforeRestorePath))!=Path.GetDirectoryName(r.Backup)||!Path.GetFileName(r.BeforeRestorePath).StartsWith("before-restore-",StringComparison.Ordinal)))throw new InvalidDataException("恢复前材料路径／属性不匹配。");
        PhotoDocument.ValidateChanges(r.Fields);
    }
    internal static void Append(InplaceRecord record,bool create=false) {
        Directory.CreateDirectory(DirectoryPath);var path=PathFor(record.Id);Validate(record,path);
        using var output=new FileStream(path,create?FileMode.CreateNew:FileMode.Append,FileAccess.Write,FileShare.Read);
        output.Write(JsonSerializer.SerializeToUtf8Bytes(record));output.WriteByte(10);output.Flush(true);
    }
    internal static void RequireClear(IEnumerable<string> paths,string? except=null,string? counterReservation=null) {
        paths=paths.ToArray();RenameCounters.RequireClear(paths,counterReservation);
        var records=ReadAll();var targets=paths.Select(SavePaths.Canonical).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if(records.Any(r=>r.Id!=except&&Pending(r)&&(targets.Contains(r.Canonical)||targets.Contains(SavePaths.Canonical(r.Photo)))))throw new IOException("目标存在持久待核对／恢复记录；禁止盲写、重读重绑定或改名。");
    }
    internal static async Task VerifyCurrent(InplaceRecord r,string hash,FileIdentity identity,CancellationToken token) {
        var properties=InplaceNative.Inspect(r.Target);
        var expected=identity==r.NewIdentity&&identity!=r.RestoreIdentity?r.SavedProperties??r.Original:r.Original;
        if(SavePaths.Canonical(r.Target)!=r.Canonical||properties.Identity!=identity||properties.Created!=expected.Created||properties.Written!=expected.Written||properties.Attributes!=expected.Attributes||properties.Security!=expected.Security||await PhotoDocument.HashAsync(r.Target,token)!=hash)throw new IOException("当前目标路径、文件身份或SHA不匹配；保留全部材料，拒绝覆盖。");
    }
    internal static async Task<Dictionary<string,double>> RestoreAsync(ExifToolClient client,InplaceRecord record,CancellationToken token) {
        var clock=Stopwatch.StartNew();var timings=new Dictionary<string,double>();
        var r=Read(PathFor(record.Id));RequireClear([r.Target],r.Id);
        InplaceNative.Inspect(r.Backup);using var originalBackupGuard=new FileStream(r.Backup,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(r.Photo!=r.Target&&(InplaceNative.Inspect(r.Photo).Identity!=r.SourceIdentity||await PhotoDocument.HashAsync(r.Photo,token)!=r.SourceHash))throw new IOException("原图身份或内容变化，拒绝恢复旁车。 ");
        using var imageGuard=r.Photo==r.Target?null:new FileStream(r.Photo,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(await PhotoDocument.HashAsync(r.Backup,token)!=r.OriginalHash)throw new IOException("备份损坏，拒绝恢复。");
        string current=r.NewHash??r.OriginalHash;var identity=r.NewIdentity??r.Original.Identity;
        if(r.Phase=="restored") {await VerifyCurrent(r,r.OriginalHash,r.RestoreIdentity??throw new IOException("恢复身份缺失。"),token);throw new InvalidOperationException("已恢复；没有再次写入。");}
        if(r.Phase is "failed" or "cancelled" or "prepared" or "backed-up" or "staged"){current=r.OriginalHash;identity=r.Original.Identity;}
        await VerifyCurrent(r,current,identity,token);
        string Kind(System.Text.Json.JsonElement metadata)=>!metadata.TryGetProperty("ExifTool:Error",out _)&&!metadata.TryGetProperty("Error",out _)&&metadata.TryGetProperty("File:FileType",out var type)?type.GetString()??"":"";
        string originalKind=Kind(await client.ReadAsync(r.Backup,token));string currentKind=Kind(await client.ReadAsync(r.Target,token));
        if(originalKind!=currentKind||originalKind is not("JPEG" or "XMP")||r.Photo!=r.Target&&(originalKind!="XMP"||Kind(await client.ReadAsync(r.Photo,token)) is not("JPEG" or "DNG")))throw new IOException("备份、真实目标或原图格式不符已验范围；拒绝恢复。");
        var properties=InplaceNative.Inspect(r.Target);
        using var parents=SavePaths.LockParents(r.Target,true);using var backupParents=SavePaths.LockParents(r.Backup,true);
        using var targetGuard=new FileStream(r.Target,FileMode.Open,FileAccess.Read,FileShare.Read);
        var folder=Path.Combine(r.Stage,"restore-"+Guid.NewGuid().ToString("N"));SavePaths.CreateOwnedDirectory(folder);
        using var ownStage=SavePaths.LockParents(Path.Combine(folder,"boundary"),true);
        var stage=Path.Combine(folder,Path.GetFileName(r.Target));var previous=Path.Combine(Path.GetDirectoryName(r.Backup)!,"before-restore-"+Guid.NewGuid().ToString("N")+".backup");
        r=r with{Phase="restoring",BeforeRestoreProperties=properties,BeforeRestorePath=previous,Detail="当前版本保留："+previous};Append(r);
        await InplaceNative.CopyDurable(r.Target,previous,token);InplaceNative.ApplyProperties(previous,properties);InplaceNative.Flush(previous);using var currentBackupGuard=new FileStream(previous,FileMode.Open,FileAccess.Read,FileShare.Read);if(await PhotoDocument.HashAsync(previous,token)!=current)throw new IOException("恢复前当前版本备份未核验。");
        timings["backupMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
        await InplaceNative.CopyDurable(r.Backup,stage,token);InplaceNative.ApplyProperties(stage,r.Original);InplaceNative.Flush(stage);
        if(await PhotoDocument.HashAsync(stage,token)!=r.OriginalHash)throw new IOException("恢复暂存SHA不匹配。");
        var restoredIdentity=InplaceNative.Inspect(stage).Identity;timings["stageMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
        await VerifyCurrent(r,current,identity,token);token.ThrowIfCancellationRequested();
        targetGuard.Dispose();
        using var replacement=new InplaceNative.Replacement(r.Target,properties,current);
        r=r with{Phase="restore-committing",RestoreHash=r.OriginalHash,RestoreIdentity=restoredIdentity};Append(r);
        replacement.Commit(stage,r.Target,r.Original with{Identity=restoredIdentity},r.OriginalHash);timings["commitMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
        await VerifyCurrent(r,r.OriginalHash,restoredIdentity,CancellationToken.None);
        if(InplaceNative.Inspect(r.Target).Security!=r.Original.Security||SourceTimes.Read(r.Target)!=new SourceTimes(r.Original.Created,r.Original.Written)||File.GetAttributes(r.Target)!=r.Original.Attributes)throw new IOException("恢复属性或权限未确认。");
        timings["readbackMs"]=clock.Elapsed.TotalMilliseconds;return timings;
        // UI independently rereads and accepts the source before completing this record.
    }
}
