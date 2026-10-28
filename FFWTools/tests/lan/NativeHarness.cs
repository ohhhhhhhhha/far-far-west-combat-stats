using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Text;
namespace FFW.LanTests {
public sealed class Native:IDisposable {
[DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr LoadLibraryW(string p);
[DllImport("kernel32",CharSet=CharSet.Ansi)]static extern IntPtr GetProcAddress(IntPtr m,string n);
[DllImport("kernel32")]static extern bool FreeLibrary(IntPtr m);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr CreateFn();
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate void VoidFn(IntPtr h);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate int IntFn(IntPtr h);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr GetFn(IntPtr h);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr PeerFn(IntPtr h,[MarshalAs(UnmanagedType.LPUTF8Str)]string p);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr ConfigureFn(IntPtr h,[MarshalAs(UnmanagedType.LPUTF8Str)]string role,[MarshalAs(UnmanagedType.LPUTF8Str)]string id,[MarshalAs(UnmanagedType.LPUTF8Str)]string address,int port,[MarshalAs(UnmanagedType.LPUTF8Str)]string token);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr SendFn(IntPtr h,[MarshalAs(UnmanagedType.LPUTF8Str)]string peer,int channel,[MarshalAs(UnmanagedType.LPUTF8Str)]string text);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr PollFn(IntPtr h,int channel);
IntPtr module;Dictionary<int,IntPtr> handles=new Dictionary<int,IntPtr>();int sequence;
T Fn<T>(string n) where T:class {var p=GetProcAddress(module,n);if(p==IntPtr.Zero)throw new InvalidOperationException("Missing export "+n);return (T)(object)Marshal.GetDelegateForFunctionPointer(p,typeof(T));}
static string Text(IntPtr p){if(p==IntPtr.Zero)return "";int n=0;while(Marshal.ReadByte(p,n)!=0)n++;var b=new byte[n];Marshal.Copy(p,b,0,n);return Encoding.UTF8.GetString(b);}
public Native(string dll){module=LoadLibraryW(dll);if(module==IntPtr.Zero)throw new InvalidOperationException("LoadLibrary failed: "+Marshal.GetLastWin32Error());}
public int Create(){var n=++sequence;handles[n]=Fn<CreateFn>("lan_create")();return n;}
public string Configure(int h,string role,string id,string address,int port,string token){return Text(Fn<ConfigureFn>("lan_configure")(handles[h],role,id,address,port,token));}
public string Pair(int h,string peer){return Text(Fn<PeerFn>("lan_pair")(handles[h],peer));}
public string Id(int h){return Text(Fn<GetFn>("lan_id")(handles[h]));} public string Status(int h){return Text(Fn<GetFn>("lan_status")(handles[h]));} public int Port(int h){return Fn<IntFn>("lan_port")(handles[h]);}
public string Send(int h,string peer,int channel,string body){return Text(Fn<SendFn>("lan_send")(handles[h],peer,channel,body));}
public string Poll(int h,int channel){return Text(Fn<PollFn>("lan_poll")(handles[h],channel));}
public string Close(int h,string peer){return Text(Fn<PeerFn>("lan_close")(handles[h],peer));}public string Revoke(int h,string peer){return Text(Fn<PeerFn>("lan_revoke")(handles[h],peer));}
public void Update(int h){Fn<VoidFn>("lan_update")(handles[h]);}public void Stop(int h){Fn<VoidFn>("lan_stop")(handles[h]);}
public void Dispose(){if(module!=IntPtr.Zero){foreach(var h in handles.Values)Fn<VoidFn>("lan_destroy")(h);handles.Clear();FreeLibrary(module);module=IntPtr.Zero;}}
}}
