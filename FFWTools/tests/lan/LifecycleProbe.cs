using System;using System.Runtime.InteropServices;
namespace FFW.LanLifecycle {public sealed class Probe:IDisposable {
 [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr LoadLibraryW(string path);
 [DllImport("kernel32",CharSet=CharSet.Ansi)]static extern IntPtr GetProcAddress(IntPtr m,string n);
 [DllImport("kernel32")]static extern bool FreeLibrary(IntPtr m);
 [UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate int ReadFn();IntPtr module;
 public Probe(string path){module=LoadLibraryW(path);if(module==IntPtr.Zero)throw new InvalidOperationException("Load failed");}
 public int Read(string name){var p=GetProcAddress(module,name);if(p==IntPtr.Zero)throw new InvalidOperationException("Missing counter");return ((ReadFn)Marshal.GetDelegateForFunctionPointer(p,typeof(ReadFn)))();}
 public void Dispose(){if(module!=IntPtr.Zero){FreeLibrary(module);module=IntPtr.Zero;}}
}}
