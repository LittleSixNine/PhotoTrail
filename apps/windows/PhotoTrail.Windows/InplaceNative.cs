using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;
namespace PhotoTrail.Windows;

internal sealed record FileIdentity(uint Volume,uint High,uint Low);
internal sealed record FileProperties(FileIdentity Identity,FileAttributes Attributes,DateTime Created,DateTime Written,string Security,DateTime Accessed);
internal static class InplaceNative
{
    [StructLayout(LayoutKind.Sequential)]struct Information { public uint Attributes;public System.Runtime.InteropServices.ComTypes.FILETIME Created,Accessed,Written;public uint Volume,SizeHigh,SizeLow,Links,High,Low; }
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle file,out Information information);
    internal static void RequirePlainDirectory(SafeFileHandle handle){if(!GetFileInformationByHandle(handle,out var information)||(information.Attributes&(uint)FileAttributes.ReparsePoint)!=0)throw new IOException("目录句柄为链接或身份无法确认，拒绝。");}
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct StreamInformation{public long Size;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=296)]public string Name;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr FindFirstStreamW(string path,int level,out StreamInformation information,uint flags);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool FindNextStreamW(IntPtr find,out StreamInformation information);
    [DllImport("kernel32.dll")]static extern bool FindClose(IntPtr find);
    [DllImport("KtmW32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateTransaction(IntPtr security,IntPtr guid,uint options,uint level,uint flags,uint timeout,string description);
    [DllImport("KtmW32.dll",SetLastError=true)]static extern bool CommitTransaction(SafeFileHandle transaction);
    [DllImport("KtmW32.dll",SetLastError=true)]static extern bool RollbackTransaction(SafeFileHandle transaction);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFileTransactedW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template,SafeFileHandle transaction,IntPtr mini,IntPtr extended);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool MoveFileTransactedW(string from,string to,IntPtr progress,IntPtr data,uint flags,SafeFileHandle transaction);
    [StructLayout(LayoutKind.Sequential)]struct BasicInformation {public long Created,Accessed,Written,Changed;public uint Attributes;}
    [DllImport("kernel32.dll",SetLastError=true)]static extern bool SetFileInformationByHandle(SafeFileHandle file,int informationClass,ref BasicInformation information,uint size);
    internal static void RequireLocalVolume(string path) {
        var root=Path.GetPathRoot(Path.GetFullPath(path))!;
        if(root.Length!=3||root[1]!=':')throw new IOException("网络／设备路径未验证，拒绝访问原位事务材料。");
        var drive=new DriveInfo(root);
        if(drive.DriveType!=DriveType.Fixed||drive.DriveFormat!="NTFS")throw new IOException("原位仅支持已验证的本地固定NTFS卷；其他边界拒绝。");
    }
    internal static FileProperties Inspect(string path) {
        RequireLocalVolume(path);
        using var directories=SavePaths.LockParents(path,true);
        using var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
        if(!GetFileInformationByHandle(file.SafeFileHandle,out var i)||i.Links!=1)throw new IOException("无法确认唯一文件身份，硬链接拒绝。");
        var attributes=(FileAttributes)i.Attributes;
        if((attributes&(FileAttributes.ReparsePoint|FileAttributes.ReadOnly|FileAttributes.Encrypted|FileAttributes.Compressed|FileAttributes.SparseFile))!=0)throw new IOException("链接、只读、加密、压缩或稀疏目标未验，拒绝。");
        RequireSingleStream(path);
        var security=new FileInfo(path).GetAccessControl(AccessControlSections.Access|AccessControlSections.Owner|AccessControlSections.Group);
        if(security.GetAccessRules(true,false,typeof(System.Security.Principal.SecurityIdentifier)).Count>0)throw new IOException("自定义显式ACL目标未验证；保守拒绝原位操作。");
        return new(new(i.Volume,i.High,i.Low),attributes,SourceTimes.FromFileTime(i.Created),SourceTimes.FromFileTime(i.Written),Security(path),SourceTimes.FromFileTime(i.Accessed));
    }
    internal static void ApplyProperties(string path,FileProperties properties) {
        var security=new FileSecurity();security.SetSecurityDescriptorSddlForm(properties.Security,AccessControlSections.Access|AccessControlSections.Owner|AccessControlSections.Group);
        new FileInfo(path).SetAccessControl(security);
        File.SetLastAccessTimeUtc(path,properties.Accessed);File.SetCreationTimeUtc(path,properties.Created);File.SetLastWriteTimeUtc(path,properties.Written);File.SetAttributes(path,properties.Attributes);
        if(Inspect(path).Security!=properties.Security||SourceTimes.Read(path)!=new SourceTimes(properties.Created,properties.Written))throw new IOException("暂存权限与原目标不一致，拒绝提交。");
    }
    internal sealed class Replacement:IDisposable {
        readonly SafeFileHandle transaction;readonly string security;bool committed;
        internal Replacement(string target,FileProperties properties,string hash) {
            security=properties.Security;
            transaction=CreateTransaction(IntPtr.Zero,IntPtr.Zero,0,0,0,0,"PhotoTrail mandatory-backup replacement");
            try {
                if(transaction.IsInvalid)throw Failure("文件事务不可用");
                LockFile(target,properties,hash,false);
            }catch{Dispose();throw;}
        }
        void LockFile(string path,FileProperties properties,string hash,bool preserveProperties) {
            using var handle=CreateFileTransactedW(path,0xc0010000,5,IntPtr.Zero,3,0x00200080,IntPtr.Zero,transaction,IntPtr.Zero,IntPtr.Zero);
            if(handle.IsInvalid)throw Failure("无法排他保护文件");
            using var file=new FileStream(handle,FileAccess.ReadWrite);
            if(!GetFileInformationByHandle(handle,out var identity)||identity.Links!=1||(identity.Attributes&(uint)FileAttributes.ReparsePoint)!=0||properties.Identity!=new FileIdentity(identity.Volume,identity.High,identity.Low))throw new IOException("文件身份已改变。");
            RequireSingleStream(path);
            long Stamp(System.Runtime.InteropServices.ComTypes.FILETIME time)=>((long)(uint)time.dwHighDateTime<<32)|(uint)time.dwLowDateTime;
            if(Stamp(identity.Created)!=properties.Created.ToFileTimeUtc()||Stamp(identity.Written)!=properties.Written.ToFileTimeUtc()||identity.Attributes!=(uint)properties.Attributes)throw new IOException("事务句柄的创建／修改时间或属性改变，拒绝提交。");
            // The same-byte transactional write keeps the isolation lock after this handle closes.
            int first=file.ReadByte();if(first<0)throw new IOException("空目标拒绝。");file.Position=0;file.WriteByte((byte)first);file.Flush(true);file.Position=0;
            if(Convert.ToHexString(SHA256.HashData(file))!=hash||Security(path)!=security)throw new IOException("文件SHA或权限已改变，拒绝提交。");
            if(preserveProperties){var basic=new BasicInformation{Created=properties.Created.ToFileTimeUtc(),Accessed=properties.Accessed.ToFileTimeUtc(),Written=properties.Written.ToFileTimeUtc(),Attributes=(uint)properties.Attributes};if(!SetFileInformationByHandle(handle,0,ref basic,(uint)Marshal.SizeOf<BasicInformation>()))throw Failure("事务内暂存属性未确认");file.Flush(true);}
        }
        internal void Commit(string stage,string target,FileProperties stageProperties,string stageHash) {
            LockFile(stage,stageProperties,stageHash,true);
            if(Security(target)!=security||Security(stage)!=security)throw new IOException("权限已改变，拒绝替换。");
            if(!MoveFileTransactedW(stage,target,IntPtr.Zero,IntPtr.Zero,1,transaction))throw Failure("原生暂存替换失败");
            if(!CommitTransaction(transaction))throw Failure("原生提交结果未确认");committed=true;
        }
        public void Dispose(){if(!transaction.IsInvalid&&!committed)RollbackTransaction(transaction);transaction.Dispose();}
    }
    static string Security(string path)=>new FileInfo(path).GetAccessControl(AccessControlSections.Access|AccessControlSections.Owner|AccessControlSections.Group).GetSecurityDescriptorSddlForm(AccessControlSections.Access|AccessControlSections.Owner|AccessControlSections.Group);
    static void RequireSingleStream(string path) {
        var find=FindFirstStreamW(path,0,out var information,0);if(find==new IntPtr(-1))throw Failure("无法确认数据流边界");
        try{do{if(information.Name!="::$DATA")throw new IOException("附加NTFS数据流未验证，拒绝原位替换以保留内容。");}while(FindNextStreamW(find,out information));if(Marshal.GetLastWin32Error()!=38)throw Failure("数据流枚举未确认");}finally{FindClose(find);}
    }
    static IOException Failure(string message)=>new(message+"；Win32="+Marshal.GetLastWin32Error());
    internal static async Task CopyDurable(string from,string to,CancellationToken token) {
        await using var input=new FileStream(from,FileMode.Open,FileAccess.Read,FileShare.Read,81920,FileOptions.Asynchronous);
        await using var output=new FileStream(to,FileMode.CreateNew,FileAccess.Write,FileShare.None,81920,FileOptions.Asynchronous);
        await input.CopyToAsync(output,token);output.Flush(true);
    }
    internal static void Flush(string path){using var file=new FileStream(path,FileMode.Open,FileAccess.ReadWrite,FileShare.Read);file.Flush(true);}
}
