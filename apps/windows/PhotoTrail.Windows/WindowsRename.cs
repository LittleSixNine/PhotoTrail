using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace PhotoTrail.Windows;

public static class WindowsRename
{
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,ExactSpelling=true)]
    private static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true,ExactSpelling=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle,int information,IntPtr buffer,uint size);
    public static FileStream Open(string path)
    {
        var full=Path.GetFullPath(path);
        if(!full.StartsWith(@"\\?\"))full=full.StartsWith(@"\\")?@"\\?\UNC\"+full[2..]:@"\\?\"+full;
        // Deny other writers/deleters; rename the same verified handle instead of reopening its path.
        var handle=CreateFileW(full,0x80010000,1,IntPtr.Zero,3,0x08000000,IntPtr.Zero);
        if(handle.IsInvalid){var error=Marshal.GetLastWin32Error();handle.Dispose();throw new IOException("无法锁定待更名文件。",new Win32Exception(error));}
        try{return new FileStream(handle,FileAccess.Read,81920,isAsync:false);}
        catch{handle.Dispose();throw;}
    }
    public static void Move(FileStream file,string target)
    {
        var name=Encoding.Unicode.GetBytes(Path.GetFullPath(target));
        var lengthOffset=IntPtr.Size*2;var nameOffset=lengthOffset+4;
        var bytes=new byte[nameOffset+name.Length+2];
        BitConverter.GetBytes(name.Length).CopyTo(bytes,lengthOffset);name.CopyTo(bytes,nameOffset);
        var memory=Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes,0,memory,bytes.Length);
            if(!SetFileInformationByHandle(file.SafeFileHandle,3,memory,(uint)bytes.Length))throw new IOException("文件更名失败；目标不覆盖。",new Win32Exception(Marshal.GetLastWin32Error()));
        }
        finally{Marshal.FreeHGlobal(memory);}
    }
}
