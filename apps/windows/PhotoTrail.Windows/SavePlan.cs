using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace PhotoTrail.Windows;

internal enum SaveMode { Copy, NewSidecar, Inplace }
internal enum SaveScope { All, Metadata, Map }
internal sealed record SaveItem(PhotoDocument Document,long Revision,IReadOnlyDictionary<string,string> Fields,string Target,string? Companion,string? TimeZone=null,SourceTimes? Times=null);
internal sealed record SidecarResult(string Path,string? Hash,PhotoDocument? Document,string State,string Detail,string? RecordId=null,Dictionary<string,double>? Timings=null);
internal sealed record SavePlan(SaveMode Mode,SaveScope Scope,SaveItem[] Items,string[] Skipped)
{
    internal static bool IsGps(string tag)=>tag.StartsWith("XMP-exif:GPS",StringComparison.Ordinal);
    internal static SavePlan Prepare(IEnumerable<PhotoDocument> documents,SaveMode mode,SaveScope scope,string output,IEnumerable<PhotoDocument> library) {
        var items=new List<SaveItem>();var skipped=new List<string>();
        foreach(var doc in documents) {
            var fields=doc.Draft.Where(p=>scope==SaveScope.All || IsGps(p.Key)==(scope==SaveScope.Map)).ToDictionary(p=>p.Key,p=>p.Value);
            MetadataFields.Require(doc,fields);
            if(fields.Count==0){skipped.Add(Path.GetFileName(doc.FilePath)+"：本范围无净草稿");continue;}
            string? reason=mode==SaveMode.NewSidecar?!doc.CanCreateSidecar?"已有旁车／独立XMP／类型未验；使用副本路径":!doc.NewSidecarEditing?"尚未显式选择新旁车":null:!doc.CanEdit?"此格式无图内副本写入资格":null;
            if(mode is SaveMode.NewSidecar or SaveMode.Inplace&&fields.Any(p=>p.Key is "XMP-exif:GPSLatitude" or "XMP-exif:GPSLongitude" && p.Value.Length==0)&&doc.Embedded.TryGetProperty("GPS:GPSLatitude",out _))reason="清空XMP坐标不能证明屏蔽原图EXIF GPS；需产品契约确认，草稿保留";
            if(mode==SaveMode.Inplace&&doc.SidecarPath is null&&doc.FileType!="XMP"&&File.Exists(Path.ChangeExtension(doc.FilePath,".xmp")))reason="新旁车／来源关系尚未核实，禁止升级原位目标";
            if(mode==SaveMode.Inplace&&!InplaceSave.Supported(doc))reason="本格式没有已验证的原位目标；无旁车RAW请显式新建旁车";
            InplaceHistory.RequireClear([doc.FilePath,doc.SidecarPath??doc.FilePath]);
            if(mode==SaveMode.Inplace){InplaceNative.Inspect(doc.SidecarPath??doc.FilePath);if(doc.SidecarPath is not null)InplaceNative.Inspect(doc.FilePath);}
            if((File.GetAttributes(doc.FilePath)&FileAttributes.ReparsePoint)!=0)reason="源为链接，本批未验证";
            if(reason is not null){skipped.Add(Path.GetFileName(doc.FilePath)+"：拒绝，"+reason);continue;}
            string target=mode==SaveMode.Inplace?doc.SidecarPath??doc.FilePath:mode==SaveMode.NewSidecar?Path.ChangeExtension(doc.FilePath,".xmp"):Path.Combine(Path.GetFullPath(output),Path.GetFileName(doc.FilePath));
            var companion=mode==SaveMode.Copy&&doc.SidecarPath is not null?Path.ChangeExtension(target,".xmp"):null;
            if(fields.Keys.Any(MetadataTimes.IsSystem)&&doc.Times!=SourceTimes.Read(doc.FilePath))throw new IOException("文件时间来源已改变，计划未准备。");
            items.Add(new(doc,doc.DraftRevision,fields,target,companion,fields.Keys.Any(MetadataTimes.IsSystem)?MetadataTimes.Zone:null,doc.Times));
        }
        var targets=items.SelectMany(i=>i.Companion is null?new[]{i.Target}:new[]{i.Target,i.Companion}).ToArray();
        var keys=targets.Select(SavePaths.Canonical).ToArray();
        if(keys.Distinct(StringComparer.OrdinalIgnoreCase).Count()!=keys.Length)throw new IOException("整批拒绝：多个照片映射到同一物理目标。");
        var inputs=library.SelectMany(d=>d.SidecarPath is null?new[]{d.FilePath}:new[]{d.FilePath,d.SidecarPath}).Select(SavePaths.Canonical).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if(mode==SaveMode.Inplace&&items.Any(i=>library.Any(d=>!ReferenceEquals(d,i.Document)&&new[]{d.FilePath,d.SidecarPath??d.FilePath}.Any(path=>SavePaths.Canonical(path).Equals(SavePaths.Canonical(i.Target),StringComparison.OrdinalIgnoreCase)))))throw new IOException("整批拒绝：实际写入目标也作为其他照片／独立旁车导入。");
        if(mode!=SaveMode.Inplace&&keys.Any(inputs.Contains))throw new IOException("整批拒绝：保存目标也是已导入来源。");
        if(mode!=SaveMode.Inplace&&targets.Any(t=>File.Exists(t)||Directory.Exists(t)))throw new IOException("整批拒绝：目标已存在，不会覆盖。");
        return new(mode,scope,items.ToArray(),skipped.ToArray());
    }
    internal string Summary=> $"模式：{(Mode==SaveMode.Copy?"副本":Mode==SaveMode.NewSidecar?"新建同目录XMP旁车":"原位保存（强制完整备份）")}\n照片：{Items.Length}；字段范围：{(Scope==SaveScope.All?"全部字段":Scope==SaveScope.Metadata?"元数据（非GPS）":"地图（整组GPS）")}\n新文件：{(Mode==SaveMode.Inplace?0:Items.Sum(i=>i.Companion is null?1:2))}\n"+string.Join("\n",Items.Select(i=>i.Target+(i.Companion is null?"":" + "+i.Companion)+$"（{i.Fields.Count}个技术字段：{string.Join(", ",i.Fields.Keys.Select(t=>MetadataFields.DateGroups.TryGetValue(t,out var parts)?t+" ["+string.Join(" + ",parts)+"]":t))}）"+(i.Document.Iptc?.PlanDescription(i.Fields)??"")+(i.TimeZone is null?"":"；原图系统时间；冻结时区="+TimeZoneInfo.FromSerializedString(i.TimeZone).Id+"；Windows精度100ns，无损设置="+string.Join(",",i.Fields.Where(p=>MetadataTimes.IsSystem(p.Key)).Select(p=>p.Key+"="+p.Value)))))+"\n"+string.Join("\n",Skipped);
    internal static void Require(SaveItem item,bool source=true) {
        if(item.TimeZone is not null&&(item.TimeZone!=MetadataTimes.Zone||source&&item.Times!=SourceTimes.Read(item.Document.FilePath)))throw new IOException("文件属性或本机时区改变，冻结计划失效。");
        if(item.Document.DraftRevision!=item.Revision||item.Fields.Any(p=>!item.Document.Draft.TryGetValue(p.Key,out var value)||value!=p.Value))throw new InvalidOperationException("草稿revision已改变，计划失效。");
    }
    internal static async Task<SidecarResult> CreateAsync(ExifToolClient client,SaveItem item,VerifiedMetadataDates proof,CancellationToken token) {
        Require(item);var photo=item.Document;
        if(!photo.NewSidecarEditing||!photo.CanCreateSidecar||item.Target!=Path.ChangeExtension(photo.FilePath,".xmp"))throw new InvalidOperationException("新旁车目标或模式失效。");
        string temporary=Path.Combine(Path.GetDirectoryName(item.Target)!,".phototrail-sidecar-"+Guid.NewGuid().ToString("N")+".xmp");
        bool delivered=false;string? hash=null;
        using var imageGuard=new FileStream(photo.FilePath,FileMode.Open,FileAccess.Read,FileShare.Read);
        using var directories=SavePaths.LockParents(item.Target);
        try {
            await photo.EnsureUnchangedAsync(token);Require(item);
            await MetadataXmp.ExportValidatedAsync(client,photo,temporary,item.Fields,proof,token);
            hash=await PhotoDocument.HashAsync(temporary,token);
            await photo.EnsureUnchangedAsync(token);Require(item);token.ThrowIfCancellationRequested();
            File.Move(temporary,item.Target,overwrite:false);delivered=true;
            // Cancellation after delivery cannot undo a file already visible on disk.
            token.ThrowIfCancellationRequested();
            var next=await PhotoDocument.LoadAsync(client,photo.FilePath,token,inspect:true);
            if(next.SourceHash!=photo.SourceHash||next.SidecarHash!=hash||next.InspectionError.Length>0)throw new IOException("创建后来源身份或完整读取未确认。");
            Require(item);
            var residual=photo.Draft.Where(p=>!item.Fields.ContainsKey(p.Key)).ToDictionary(p=>p.Key,p=>p.Value);
            foreach(var tag in residual.Keys) {
                var before=photo.Embedded.TryGetProperty(tag,out var value)?PhotoDocument.Text(value):"";
                if(next.Value(tag)!=before)throw new IOException("残余草稿的来源基准已变化，禁止盲写："+tag);
            }
            await next.SetDraftValidatedAsync(residual,proof,next.DraftRevision,token);
            await next.EnsureUnchangedAsync(token);Require(item);
            return new(item.Target,hash,next,"成功","新来源已完整确认；本次字段已更新保存基准，残余草稿保留。");
        }catch(Exception error)when(delivered) {
            string? actual=null;try{actual=await PhotoDocument.HashAsync(item.Target);}catch(IOException){}catch(UnauthorizedAccessException){}
            return new(item.Target,actual,null,"结果未知","旁车已交付；保留磁盘文件与旧草稿，禁止再次创建。需核对／明确放弃后手动重读："+error.Message);
        }finally {
            if(!delivered&&File.Exists(temporary))File.Delete(temporary);
        }
    }
}

internal static class SavePaths
{
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,StringBuilder path,uint length,uint flags);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateDirectoryW(string path,IntPtr security);
    internal static void CreateOwnedDirectory(string path){if(!CreateDirectoryW(path,IntPtr.Zero))throw new IOException("唯一暂存／备份目录不能创建，不接管已有内容；Win32="+Marshal.GetLastWin32Error());}
    static SafeFileHandle OpenDirectory(string path,bool protectMetadata=false) {
        var handle=CreateFileW(path,0,protectMetadata?1u:3u,IntPtr.Zero,3,protectMetadata?0x02200000u:0x02000000u,IntPtr.Zero);
        if(handle.IsInvalid){handle.Dispose();throw new IOException("目录缺失、占用或无权访问："+path);}return handle;
    }
    internal static string Canonical(string path) {
        path=Path.GetFullPath(path);using var guard=OpenDirectory(Path.GetDirectoryName(path)!);
        var result=new StringBuilder(32768);var length=GetFinalPathNameByHandleW(guard,result,(uint)result.Capacity,0);
        if(length==0||length>=result.Capacity)throw new IOException("无法确认物理目录身份。");
        return result.ToString().TrimEnd('\\')+"\\"+Path.GetFileName(path);
    }
    internal static IDisposable LockParents(string path,bool protectMetadata=false) {
        var handles=new List<SafeFileHandle>();
        try { for(var parent=new DirectoryInfo(Path.GetDirectoryName(Path.GetFullPath(path))!);parent is not null;parent=parent.Parent) {
            if((parent.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("来源目录为链接；本批未授权此目标。");var handle=OpenDirectory(parent.FullName,protectMetadata);handles.Add(handle);if(protectMetadata)InplaceNative.RequirePlainDirectory(handle);
        }return new Guards(handles); }catch{foreach(var handle in handles)handle.Dispose();throw;}
    }
    sealed record Guards(List<SafeFileHandle> Handles):IDisposable{public void Dispose(){foreach(var handle in Handles)handle.Dispose();}}
}
