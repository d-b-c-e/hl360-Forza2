// Adapted from napo F-Zero GO501973 helper SHA2562C3F39BBF9560DFC0623ECE55241039768F52593979B852E736A2126252F8368.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Observation hooks are live-only. Explicit CPU/cheap executors also use the
// own-job/identity APIs for inert tools; they do not start input hooks.
public static class CannonballLive {
 public sealed class Identity { public int pid; public long birth, hwnd; public string image, kind; public string Key {get{return pid+":"+birth+":"+hwnd+":"+image;}} }
 public sealed class Event {public string utc,kind;public uint flags,tick;public bool injected;}
 public sealed class State {public string utc,abortReason,displayInitial,displayCurrent;public bool hooksActive,hooksReleased,threadJoined,pendingRaw,activationReset,hookThreadLive,monitorThreadLive;public int physical,injected,startupResets,heartbeat,hookHeartbeat;public Identity initial,current,activated;public Event[] events;public uint initialRaw,currentRaw;}
 [StructLayout(LayoutKind.Sequential)]struct Rect{public int l,t,r,b;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct MonitorInfo{public int size;public Rect monitor,work;public uint flags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string device;}
 delegate bool MonitorProc(IntPtr monitor,IntPtr dc,IntPtr rect,IntPtr data);
 [StructLayout(LayoutKind.Sequential)]struct Point{public int x,y;}
 [StructLayout(LayoutKind.Sequential)]struct Msg{public IntPtr h;public uint m;public UIntPtr w;public IntPtr l;public uint time;public Point p;public uint pad;}
 [StructLayout(LayoutKind.Sequential)]struct KeyData{public uint key,scan,flags,time;public UIntPtr extra;}
 [StructLayout(LayoutKind.Sequential)]struct MouseData{public Point p;public uint data,flags,time;public UIntPtr extra;}
 [StructLayout(LayoutKind.Sequential)]struct LastInfo{public uint size,tick;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct Startup {public uint size;public string reserved,desktop,title;public uint x,y,w,h,cx,cy,fill,flags;public ushort show,cb;public IntPtr ptr,input,output,error;}
 [StructLayout(LayoutKind.Sequential)]struct ProcessInfo{public IntPtr process,thread;public uint pid,tid;}
 [StructLayout(LayoutKind.Sequential)]struct BasicLimit{public long processTime,jobTime;public uint flags;public UIntPtr min,max;public uint active;public UIntPtr affinity;public uint priority,scheduling;}
 [StructLayout(LayoutKind.Sequential)]struct Io{public ulong read,write,other,readBytes,writeBytes,otherBytes;}
 [StructLayout(LayoutKind.Sequential)]struct ExtendedLimit{public BasicLimit basic;public Io io;public UIntPtr processMemory,jobMemory,peakProcess,peakJob;}
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct ProcessEntry{public uint size,usage,pid;public UIntPtr heap;public uint module,threads,parent;public int priority;public uint flags;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string name;}
 delegate IntPtr Hook(int code,IntPtr w,IntPtr l);
 static Hook keyHook=OnKey,mouseHook=OnMouse;static IntPtr kh,mh,job;static uint hookTid;static Thread pump,monitor;static ManualResetEvent ready=new ManualResetEvent(false);static object sync=new object();static List<IntPtr> heldProcessHandles=new List<IntPtr>();
 static List<Event> events=new List<Event>();static volatile string abort;static volatile bool active,stop,cleanup;static bool released,joined,reset,pending;static int physical,injected,startupResets,heartbeat,hookHeartbeat;static long lastHookBeat;static long ownedBirth;static int ownedPid;static Identity initial,current,activated;static string expectedImage;static long launchUtc,activationAt;static uint initialRaw,observed,pendingTick;static long pendingAt;
 static string displayInitial,displayCurrent;
 [DllImport("user32.dll")]static extern bool EnumDisplayMonitors(IntPtr dc,IntPtr clip,MonitorProc callback,IntPtr data);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetMonitorInfo(IntPtr h,ref MonitorInfo info);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool EnumDisplaySettings(string device,int mode,byte[] devmode);
 [DllImport("user32.dll",SetLastError=true)]static extern IntPtr SetWindowsHookEx(int id,Hook hook,IntPtr module,uint tid);
 [DllImport("user32.dll")]static extern bool UnhookWindowsHookEx(IntPtr h);
 [DllImport("user32.dll")]static extern IntPtr CallNextHookEx(IntPtr h,int code,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]static extern int GetMessage(out Msg m,IntPtr h,uint lo,uint hi);
 [DllImport("user32.dll")]static extern bool PeekMessage(out Msg m,IntPtr h,uint lo,uint hi,uint flags);
 [DllImport("user32.dll")]static extern bool PostThreadMessage(uint tid,uint m,UIntPtr w,IntPtr l);
 [DllImport("user32.dll")]static extern bool GetLastInputInfo(ref LastInfo info);
 [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")]static extern bool GetClientRect(IntPtr h,out Rect r);
 public static int[] ClientSize(long hwnd,int pid){uint owner;GetWindowThreadProcessId(new IntPtr(hwnd),out owner);Rect r;if(owner!=pid||!GetClientRect(new IntPtr(hwnd),out r))throw new Exception("Client identity unavailable");return new[]{r.r-r.l,r.b-r.t};}
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder text,int size);
 [DllImport("user32.dll",SetLastError=true)]public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("kernel32.dll")]static extern uint GetCurrentThreadId();
 [DllImport("kernel32.dll")]static extern IntPtr GetModuleHandle(string name);
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr CreateJobObject(IntPtr a,string name);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool SetInformationJobObject(IntPtr h,int kind,ref ExtendedLimit info,int size);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool QueryInformationJobObject(IntPtr h,int kind,IntPtr info,int size,out int used);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool AssignProcessToJobObject(IntPtr h,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true,CharSet=CharSet.Unicode)]static extern bool CreateProcess(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Startup startup,out ProcessInfo process);
 [DllImport("kernel32.dll")]static extern uint ResumeThread(IntPtr h);
 [DllImport("kernel32.dll")]static extern bool TerminateProcess(IntPtr h,uint code);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder name,ref int size);
 [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint pid);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool Process32First(IntPtr h,ref ProcessEntry entry);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool Process32Next(IntPtr h,ref ProcessEntry entry);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool inside);
 static void Fail(string why){if(abort==null)abort=why;}
 public static Identity ProcessIdentity(int pid){using(var p=Process.GetProcessById(pid)){var name=new StringBuilder(32768);int size=name.Capacity;if(!QueryFullProcessImageName(p.Handle,0,name,ref size))throw new Exception("Process image unreadable");return new Identity{pid=pid,birth=p.StartTime.ToUniversalTime().Ticks,image=name.ToString(),kind="process"};}}
 public static Identity Foreground(){var h=GetForegroundWindow();uint pid;GetWindowThreadProcessId(h,out pid);if(h==IntPtr.Zero||pid==0)throw new Exception("Unknown foreground");var i=ProcessIdentity((int)pid);i.hwnd=h.ToInt64();var text=new StringBuilder(256);GetClassName(h,text,256);i.kind=text.ToString();return i;}
 static uint Raw(){var i=new LastInfo{size=8};if(!GetLastInputInfo(ref i))throw new Exception("Last-input read failed");return i.tick;}
 public static double IdleSeconds(){return unchecked((uint)Environment.TickCount-Raw())/1000.0;}
 public static string DisplayIdentity(){var rows=new List<string>();bool ok=true;MonitorProc callback=(h,dc,rect,data)=>{var i=new MonitorInfo{size=Marshal.SizeOf(typeof(MonitorInfo))};if(!GetMonitorInfo(h,ref i)){ok=false;return false;}var mode=new byte[220];mode[68]=220;if(!EnumDisplaySettings(i.device,-1,mode)){ok=false;return false;}rows.Add(i.device+":"+i.monitor.l+","+i.monitor.t+","+i.monitor.r+","+i.monitor.b+":"+i.flags+":"+BitConverter.ToInt32(mode,184)+":"+BitConverter.ToInt32(mode,84));return true;};if(!EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,callback,IntPtr.Zero)||!ok||rows.Count==0)throw new Exception("Display identity unavailable");rows.Sort(StringComparer.Ordinal);return String.Join("|",rows);}
 public static void VerifyDisplay(){if(displayInitial!=null&&DisplayIdentity()!=displayInitial)throw new Exception("Display mode/topology differs; retain custody");}
 // Pure foreground policy: one exact owned natural transition, then fixed. No activation request exists here.
 public static bool ForegroundAllowed(string baseline,string now,string activatedKey,bool exactNewGame){bool activated=!String.IsNullOrEmpty(activatedKey);return now==baseline&&!activated||activated&&now==activatedKey||!activated&&exactNewGame;}
 public static bool ExplainReset(int count,int physicalCount,int injectedCount,long ageMs,bool allowedForeground){return count<3&&physicalCount==0&&injectedCount==0&&ageMs>=0&&ageMs<=90000&&allowedForeground;}
 static void Record(string kind,uint flags,uint tick,bool injectedEvent){lock(sync){if(events.Count>=512){Fail("event-budget");return;}events.Add(new Event{utc=DateTime.UtcNow.ToString("o"),kind=kind,flags=flags,tick=tick,injected=injectedEvent});if(injectedEvent)injected++;else physical++;}Fail(injectedEvent?"injected-os-input":"physical-input");}
 static IntPtr OnKey(int code,IntPtr w,IntPtr l){try{if(code>=0){var k=(KeyData)Marshal.PtrToStructure(l,typeof(KeyData));Record("keyboard",k.flags,k.time,(k.flags&0x10)!=0);}}catch{Fail("keyboard-hook-error");}return CallNextHookEx(kh,code,w,l);}
 static IntPtr OnMouse(int code,IntPtr w,IntPtr l){try{if(code>=0){var m=(MouseData)Marshal.PtrToStructure(l,typeof(MouseData));Record("mouse",m.flags,m.time,(m.flags&1)!=0);}}catch{Fail("mouse-hook-error");}return CallNextHookEx(mh,code,w,l);}
 static void Pump(){try{hookTid=GetCurrentThreadId();Msg m;PeekMessage(out m,IntPtr.Zero,0,0,0);kh=SetWindowsHookEx(13,keyHook,GetModuleHandle(null),0);mh=SetWindowsHookEx(14,mouseHook,GetModuleHandle(null),0);if(kh==IntPtr.Zero||mh==IntPtr.Zero)throw new Exception();active=true;lastHookBeat=Environment.TickCount64;ready.Set();while(GetMessage(out m,IntPtr.Zero,0,0)>0){if(m.m==0x8001){Interlocked.Increment(ref hookHeartbeat);Interlocked.Exchange(ref lastHookBeat,Environment.TickCount64);}}if(!stop)Fail("hook-pump-ended");}catch{Fail("hook-startup-error");ready.Set();}finally{released=(kh==IntPtr.Zero||UnhookWindowsHookEx(kh))&(mh==IntPtr.Zero||UnhookWindowsHookEx(mh));active=false;}}
 static void Monitor(){long displayAt=0;while(!stop){try{var fg=Foreground();lock(sync){current=fg;}long now=Environment.TickCount64;uint raw=Raw();heartbeat++;if(!active)Fail("hook-pump-not-active");
    if(now-lastHookBeat>3000)Fail("hook-heartbeat-stalled");if(now-displayAt>=1000){if(!PostThreadMessage(hookTid,0x8001,UIntPtr.Zero,IntPtr.Zero))Fail("hook-heartbeat-post-failed");displayCurrent=DisplayIdentity();displayAt=now;if(!cleanup&&displayCurrent!=displayInitial)Fail("display-mode-or-topology-changed");}
    if(!cleanup){bool game=ownedPid>0&&fg.pid==ownedPid&&fg.birth==ownedBirth&&String.Equals(fg.image,expectedImage,StringComparison.OrdinalIgnoreCase);
      if(!ForegroundAllowed(initial.Key,fg.Key,activated==null?null:activated.Key,game))Fail("foreign-foreground-or-second-transition");
      if(activated==null&&fg.Key!=initial.Key&&game){lock(sync){activated=fg;activationAt=now;}}
      if(raw!=observed){pending=true;pendingTick=raw;pendingAt=now;
        if(ExplainReset(startupResets,physical,injected,(DateTime.UtcNow.Ticks-ownedBirth)/10000,ownedBirth>0&&(fg.Key==initial.Key||game))){startupResets++;reset=true;observed=raw;pendingTick=0;pending=false;lock(sync){events.Add(new Event{utc=DateTime.UtcNow.ToString("o"),kind="game-startup-zero-LL-reset",tick=raw});}}
        else Fail("unexplained-last-input-tick");}
    }
   }catch{Fail("observer-identity-error");}Thread.Sleep(25);}}
 public static void Start(string image){expectedImage=image;displayInitial=displayCurrent=DisplayIdentity();initial=current=Foreground();initialRaw=observed=Raw();pump=new Thread(Pump);pump.IsBackground=true;pump.Start();if(!ready.WaitOne(3000)||!active)throw new Exception("Hooks not active");monitor=new Thread(Monitor);monitor.IsBackground=true;monitor.Start();}
 public static void MarkLaunch(){launchUtc=DateTime.UtcNow.Ticks;}
 public static State Snapshot(){lock(sync){return new State{utc=DateTime.UtcNow.ToString("o"),abortReason=abort,displayInitial=displayInitial,displayCurrent=displayCurrent,hooksActive=active,hookThreadLive=pump!=null&&pump.IsAlive,monitorThreadLive=monitor!=null&&monitor.IsAlive,hooksReleased=released,threadJoined=joined,pendingRaw=pending,activationReset=reset,physical=physical,injected=injected,startupResets=startupResets,heartbeat=heartbeat,hookHeartbeat=hookHeartbeat,initial=initial,current=current,activated=activated,events=events.ToArray(),initialRaw=initialRaw,currentRaw=Raw()};}}
 public static void BeginCleanup(){cleanup=true;}
 public static void Stop(){stop=true;if(monitor!=null&&!monitor.Join(3000))Fail("monitor-join-failed");if(pump!=null){PostThreadMessage(hookTid,0x12,UIntPtr.Zero,IntPtr.Zero);joined=pump.Join(3000);}else{released=joined=kh==IntPtr.Zero&&mh==IntPtr.Zero;}if(!released||!joined)throw new Exception("Native hook cleanup unknown");}
 static void CreateOwnedJob(){if(job!=IntPtr.Zero)throw new Exception("Job already held");job=CreateJobObject(IntPtr.Zero,null);if(job==IntPtr.Zero)throw new Exception("Job creation failed");var limits=new ExtendedLimit();limits.basic.flags=0x2000;if(!SetInformationJobObject(job,9,ref limits,Marshal.SizeOf(limits))){CloseHandle(job);job=IntPtr.Zero;throw new Exception("Job limit failed");}}
 // Suspended launch puts the exact new PID in our job before it can run or fork; never adopt by process name.
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateFile(string name,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool TerminateJobObject(IntPtr h,uint code);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool WriteFile(IntPtr h,byte[] data,uint count,out uint written,IntPtr overlapped);
 [DllImport("kernel32.dll",SetLastError=true)]static extern uint WaitForSingleObject(IntPtr h,uint milliseconds);
 static void RefuseLaunch(ProcessInfo pi,IntPtr log,Identity id,string reason,int error){var bytes=Encoding.UTF8.GetBytes("[rejected-own-launch] pid="+id.pid+" birth="+id.birth+" image="+id.image+" reason="+reason+" win32="+error+"\n");uint written;if(!WriteFile(log,bytes,(uint)bytes.Length,out written,IntPtr.Zero)||written!=bytes.Length)throw new Exception("Cannot persist rejection; suspended own process retained: "+id.Key);TerminateProcess(pi.process,1);throw new Exception(reason+" win32="+error+"; suspended own PID terminated: "+id.Key);}
 [DllImport("user32.dll")]static extern bool EnumWindows(WindowProc callback,IntPtr parameter);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 delegate bool WindowProc(IntPtr h,IntPtr parameter);
 public static long Window(int pid,long birth){if(ProcessIdentity(pid).birth!=birth)throw new Exception("Window PID reused");var found=new List<long>();WindowProc callback=(h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);if(owner==pid&&IsWindowVisible(h)){var name=new StringBuilder(256);GetClassName(h,name,256);if(name.ToString()=="SDL_app")found.Add(h.ToInt64());}return true;};if(!EnumWindows(callback,IntPtr.Zero))throw new Exception("Window census failed");if(found.Count>1)throw new Exception("Ambiguous SDL windows");return found.Count==1?found[0]:0;}
 public static Identity Launch(string exe,string cwd,string commandLine,string stdout,string stderr,bool game){if(job==IntPtr.Zero)CreateOwnedJob();var startup=new Startup();startup.size=(uint)Marshal.SizeOf(startup);startup.flags=0x100;var handles=new List<IntPtr>();ProcessInfo pi;
   try{startup.output=CreateFile(stdout,0x40000000,3,IntPtr.Zero,1,0x80,IntPtr.Zero);startup.error=CreateFile(stderr,0x40000000,3,IntPtr.Zero,1,0x80,IntPtr.Zero);startup.input=CreateFile("NUL",0x80000000,3,IntPtr.Zero,3,0x80,IntPtr.Zero);handles.Add(startup.output);handles.Add(startup.error);handles.Add(startup.input);foreach(var h in handles){if(h==new IntPtr(-1)||!SetHandleInformation(h,1,1))throw new Exception("Log handle setup failed");}
   if(!CreateProcess(exe,new StringBuilder(commandLine),IntPtr.Zero,IntPtr.Zero,true,4|0x08000000,IntPtr.Zero,cwd,ref startup,out pi))throw new Exception("CreateProcess failed: "+Marshal.GetLastWin32Error());
   try{Identity id=ProcessIdentity((int)pi.pid);id.kind="suspended-process";if(!AssignProcessToJobObject(job,pi.process))RefuseLaunch(pi,startup.error,id,"Job assignment failed",Marshal.GetLastWin32Error());if(!String.Equals(id.image,exe,StringComparison.OrdinalIgnoreCase))RefuseLaunch(pi,startup.error,id,"Requested executable is an alias",0);if(game){ownedBirth=id.birth;ownedPid=id.pid;}if(ResumeThread(pi.thread)==0xffffffff)RefuseLaunch(pi,startup.error,id,"Resume failed",Marshal.GetLastWin32Error());return id;}finally{CloseHandle(pi.thread);heldProcessHandles.Add(pi.process);}}
   finally{foreach(var h in handles)if(h!=new IntPtr(-1))CloseHandle(h);}}
 public static void KillOwned(){if(job!=IntPtr.Zero&&!TerminateJobObject(job,98))throw new Exception("Owned job termination failed");}
 public static int[] JobPids(){if(job==IntPtr.Zero)return new int[0];int bytes=4096;while(bytes<=1048576){var data=Marshal.AllocHGlobal(bytes);try{int used;if(QueryInformationJobObject(job,3,data,bytes,out used)){int n=Marshal.ReadInt32(data,4);if(n<0||8+n*IntPtr.Size>bytes)throw new Exception("Invalid job census");var ids=new int[n];for(int i=0;i<n;i++)ids[i]=(int)(IntPtr.Size==8?Marshal.ReadInt64(data,8+i*8):Marshal.ReadInt32(data,8+i*4));return ids;}if(Marshal.GetLastWin32Error()!=234)throw new Exception("Job census failed");}finally{Marshal.FreeHGlobal(data);}bytes*=2;}throw new Exception("Job census exceeded bound");}
 public static int RetainedProcessHandles(){return heldProcessHandles.Count;}
 public static void ReleaseJob(){if(JobPids().Length!=0)throw new Exception("Owned children still active");foreach(var h in heldProcessHandles)if(WaitForSingleObject(h,0)!=0)throw new Exception("Own launched process still active/uncontained; custody retained");foreach(var h in heldProcessHandles)CloseHandle(h);heldProcessHandles.Clear();if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}}
}
