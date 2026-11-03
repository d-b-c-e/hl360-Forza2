using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
// Only the caller's fresh fixture file. No input, process, display or device enumeration.
public static class Bo3SparseFixture {
 [DllImport("kernel32",SetLastError=true)]static extern bool DeviceIoControl(SafeFileHandle h,uint code,IntPtr a,uint b,IntPtr c,uint d,out uint used,IntPtr overlap);
 public static void Create(string path){using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)){uint n;if(!DeviceIoControl(f.SafeFileHandle,0x900c4,IntPtr.Zero,0,IntPtr.Zero,0,out n,IntPtr.Zero))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());f.SetLength(4*1024*1024);f.Position=0;f.Write(new byte[]{1,2,3,4},0,4);f.Position=4*1024*1024-4;f.Write(new byte[]{4,3,2,1},0,4);}}
}
