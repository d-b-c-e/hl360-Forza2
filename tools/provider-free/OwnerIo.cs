using System;
using System.IO;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
// File handles only, after PowerShell's root/type/reparse checks. Never opens
// a volume, controller, display or input device. Preserve sparse allocation.
public static class Bo3OwnerIo {
 public sealed class Range {public long offset,length;}
 [DllImport("kernel32",SetLastError=true)]static extern bool DeviceIoControl(SafeFileHandle h,uint code,IntPtr input,uint inputSize,IntPtr output,uint outputSize,out uint used,IntPtr overlap);
 static void Sparse(SafeFileHandle h,bool enabled){IntPtr p=Marshal.AllocHGlobal(1);try{Marshal.WriteByte(p,enabled?(byte)1:(byte)0);uint used;if(!DeviceIoControl(h,0x900c4,p,1,IntPtr.Zero,0,out used,IntPtr.Zero))throw new Win32Exception(Marshal.GetLastWin32Error(),"File sparse flag");}finally{Marshal.FreeHGlobal(p);}}
 public static void SetSparse(string path,bool enabled){using(var f=new FileStream(path,FileMode.Open,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)){Sparse(f.SafeFileHandle,enabled);}}
 public static Range[] Ranges(string path){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){return Ranges(f);}}
 static Range[] Ranges(FileStream f){
  var rows=new List<Range>();IntPtr input=Marshal.AllocHGlobal(16),output=Marshal.AllocHGlobal(16384);
  try{long cursor=0;while(cursor<f.Length){Marshal.WriteInt64(input,cursor);Marshal.WriteInt64(input,8,f.Length-cursor);uint used;bool ok=DeviceIoControl(f.SafeFileHandle,0x940cf,input,16,output,16384,out used,IntPtr.Zero);int error=Marshal.GetLastWin32Error();if(!ok&&error!=234)throw new Win32Exception(error,"File allocated ranges");if(used%16!=0||used>16384)throw new IOException("Invalid allocated-range response");if(used==0)break;
   long next=cursor;for(int i=0;i<used;i+=16){long start=Marshal.ReadInt64(output,i),size=Marshal.ReadInt64(output,i+8);if(start<cursor||size<=0||start>f.Length-size)throw new IOException("Allocated range escapes file");rows.Add(new Range{offset=start,length=size});next=start+size;if(rows.Count>65536)throw new IOException("Sparse range bound exceeded");}if(next<=cursor)throw new IOException("Sparse range cursor stalled");cursor=next;if(ok)break;
  }return rows.ToArray();}finally{Marshal.FreeHGlobal(input);Marshal.FreeHGlobal(output);}
 }
 public static void CopySparse(string source,string destination,bool overwrite){
  using(var input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
   Range[] ranges=Ranges(input);FileMode mode=overwrite&&File.Exists(destination)?FileMode.Open:FileMode.CreateNew;
   using(var output=new FileStream(destination,mode,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)){
    // Truncate only this already-validated target, then explicitly set sparse;
    // CREATE_ALWAYS/.NET WriteAllText can drop it, and SetAttributes cannot set it.
    output.SetLength(0);Sparse(output.SafeFileHandle,true);output.SetLength(input.Length);byte[] buffer=new byte[262144];
    foreach(var range in ranges){input.Position=output.Position=range.offset;long left=range.length;while(left>0){int n=input.Read(buffer,0,(int)Math.Min(buffer.Length,left));if(n<=0)throw new EndOfStreamException();output.Write(buffer,0,n);left-=n;}}
   }
  }
 }
}
