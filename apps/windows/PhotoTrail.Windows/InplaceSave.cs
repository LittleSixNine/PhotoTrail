using System.Diagnostics;
using System.IO;
using System.Globalization;
namespace PhotoTrail.Windows;

internal static class InplaceSave
{
    internal static async Task<SidecarResult> SaveAsync(ExifToolClient client,SaveItem item,string backupRoot,VerifiedMetadataDates dates,CancellationToken token) {
        SavePlan.Require(item);var photo=item.Document;
        InplaceHistory.RequireClear([photo.FilePath,item.Target]);
        if(item.Target!=(photo.SidecarPath??photo.FilePath)||!Supported(photo))throw new IOException("原位实际目标或样本资格失效。");
        InplaceNative.RequireLocalVolume(backupRoot);
        if(!Directory.Exists(backupRoot))throw new IOException("必须先选择可用的既有备份目录；目标未改写。");
        var properties=InplaceNative.Inspect(item.Target);string original=photo.SidecarHash??photo.SourceHash;
        using var parents=SavePaths.LockParents(item.Target,true);using var backupParents=SavePaths.LockParents(Path.Combine(backupRoot,"boundary"),true);
        using var imageGuard=photo.SidecarPath is null?null:new FileStream(photo.FilePath,FileMode.Open,FileAccess.Read,FileShare.Read);
        using var targetGuard=new FileStream(item.Target,FileMode.Open,FileAccess.Read,FileShare.Read);
        await photo.EnsureUnchangedAsync(token);SavePlan.Require(item);
        string id=Guid.NewGuid().ToString("N"),folder=Path.Combine(Path.GetFullPath(backupRoot),id),stage=Path.Combine(Path.GetDirectoryName(item.Target)!,".phototrail-inplace-"+id);
        SavePaths.CreateOwnedDirectory(folder);
        using var ownBackup=SavePaths.LockParents(Path.Combine(folder,"boundary"),true);
        var record=new InplaceRecord(item.Fields.Keys.Any(MetadataTimes.IsSystem)?2:1,id,photo.FilePath,item.Target,SavePaths.Canonical(item.Target),Path.GetFullPath(backupRoot),Path.Combine(folder,Path.GetFileName(item.Target)+".backup"),stage,original,properties,item.Revision,new(item.Fields),"prepared",SourceHash:photo.SourceHash,SourceIdentity:InplaceNative.Inspect(photo.FilePath).Identity);
        InplaceHistory.Append(record,true);bool commitAttempted=false;var clock=Stopwatch.StartNew();var timings=new Dictionary<string,double>();
        try {
            await InplaceNative.CopyDurable(item.Target,record.Backup,token);InplaceNative.ApplyProperties(record.Backup,properties);InplaceNative.Flush(record.Backup);
            using var backupGuard=new FileStream(record.Backup,FileMode.Open,FileAccess.Read,FileShare.Read);
            if(await PhotoDocument.HashAsync(record.Backup,token)!=original)throw new IOException("完整备份SHA不一致；目标未改写。");
            record=record with{Phase="backed-up"};InplaceHistory.Append(record);timings["backupMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            SavePaths.CreateOwnedDirectory(stage);
            using var ownStage=SavePaths.LockParents(Path.Combine(stage,"boundary"),true);
            await MetadataCopy.SaveValidatedAsync(client,photo,stage,item.Fields,dates,token,id);
            string writable=Path.Combine(stage,Path.GetFileName(item.Target));
            var requested=MetadataTimes.Requested(properties,item.Fields);
            InplaceNative.ApplyProperties(writable,requested);InplaceNative.Flush(writable);
            string hash=await PhotoDocument.HashAsync(writable,token);var newIdentity=InplaceNative.Inspect(writable).Identity;
            record=record with{Phase="staged",NewHash=hash,NewIdentity=newIdentity,SavedProperties=record.Version==2?requested with{Identity=newIdentity}:null};InplaceHistory.Append(record);timings["stageMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            await photo.EnsureUnchangedAsync(token);SavePlan.Require(item);await InplaceHistory.VerifyCurrent(record,original,properties.Identity,token);token.ThrowIfCancellationRequested();
            targetGuard.Dispose();
            using var replacement=new InplaceNative.Replacement(item.Target,properties,original);
            record=record with{Phase="committing"};InplaceHistory.Append(record);commitAttempted=true;
            replacement.Commit(writable,item.Target,requested with{Identity=newIdentity},hash);timings["commitMs"]=clock.Elapsed.TotalMilliseconds;clock.Restart();
            token.ThrowIfCancellationRequested();
            // Exact staged-byte equality plus independent real-source reads verifies both target and non-target contents.
            await InplaceHistory.VerifyCurrent(record,hash,newIdentity,token);
            var next=await PhotoDocument.LoadAsync(client,photo.FilePath,token,inspect:true);
            if(next.InspectionError.Length>0||(photo.SidecarPath is not null&&next.SourceHash!=photo.SourceHash)||next.SidecarPath!=photo.SidecarPath||InplaceNative.Inspect(item.Target).Security!=properties.Security)throw new IOException("真实来源、原图字节或权限未确认。");
            foreach(var field in item.Fields)if(!MetadataFields.Matches(field.Key,next.Value(field.Key),field.Value))throw new IOException("真实目标字段回读不一致："+field.Key);
            var residual=photo.Draft.Where(p=>!item.Fields.ContainsKey(p.Key)).ToDictionary(p=>p.Key,p=>p.Value);
            var before=photo.BatchSnapshot();before.ReplaceDraft(new Dictionary<string,string>());
            foreach(var tag in residual.Keys)if(before.Value(tag)!=next.Value(tag))throw new IOException("残余草稿的原基准改变；保留草稿并禁止盲写："+tag);
            await next.SetDraftValidatedAsync(residual,dates,next.DraftRevision,token);await next.EnsureUnchangedAsync(token);SavePlan.Require(item,source:false);
            record=record with{Phase="readback"};InplaceHistory.Append(record);timings["readbackMs"]=clock.Elapsed.TotalMilliseconds;
            return new(item.Target,hash,next,"待接纳","真实目标已独立核验；备份及记录保留，尚待界面确认。",id,timings);
        }catch(Exception error) {
            string phase=commitAttempted?"unknown":error is OperationCanceledException?"cancelled":"failed";
            if(commitAttempted){try{await InplaceHistory.VerifyCurrent(record,original,properties.Identity,CancellationToken.None);phase=error is OperationCanceledException?"cancelled":"failed";}catch(Exception){}}
            try{InplaceHistory.Append(record with{Phase=phase,Detail=error.Message});}catch(Exception logError){return new(item.Target,null,null,"结果未知","恢复日志未能持久更新；保留目标、备份、记录和草稿："+logError.Message,id,timings);}
            return new(item.Target,null,null,phase=="unknown"?"结果未知":phase=="cancelled"?"取消":"失败",error.Message+"；备份、暂存、记录和草稿保留。",id,timings);
        }
    }
    internal static bool Supported(PhotoDocument photo)=>photo.SidecarPath is not null?photo.FileType is "JPEG" or "DNG":photo.FileType is "JPEG" or "XMP";
}
