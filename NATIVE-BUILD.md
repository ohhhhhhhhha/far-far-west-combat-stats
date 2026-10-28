# Native bridge build / 原生构建

Players use the runtime ZIP; compiling is unnecessary for installation. 开发者构建只生成本地产物，不安装、不启动游戏，也不改防火墙。

## Inputs / 输入

- Windows x64; Visual Studio 2022 C++ v143 tools and Windows SDK 10.0.26100.0. Projects use C++20, /MD and one MSBuild node without parallel compiler jobs.
- For the API route, installed .NET Framework 4.8 and .NET8, node-api-dotnet 0.9.31 and Node.js with Worker support. Roslyn and MSBuild are the installed Visual Studio assemblies.
- The working Nexus mods/2 player 3.0.1.1183 framework DLL. The inspected SHA-256 is c273e7228687b647226fd63d7ca65888d313ece6be18996ec1320d00a5efe1f8. Do not redistribute the framework DLL in this project.
- Separately obtain the pinned [UE4SS source headers](https://github.com/UE4SS-RE/RE-UE4SS/tree/8333063595fa3c49ad307f3b0f732accbb760d25), fmt 11.2.0 and compatible Steam networking headers with their licenses. The archive does not include these SDKs.

~~~text
<repository>/FFWTools/vendor/team-sync-ue4ss-1181/
  source/RE-UE4SS-8333063595fa3c49ad307f3b0f732accbb760d25/
    UE4SS/include/...
    deps/first/{File,Input,String,LuaMadeSimple,LuaRaw}/include/...
  fmt/fmt-11.2.0/include/...
  steam/steamnetworkingtypes.h (and referenced headers)
~~~

## No-shell API route / 无 shell 构建接口

Import buildNative from FFWTools/src/FFWTeamSync/build-via-api.mjs in a Node JavaScript host. Call it with root (repository folder), frameworkDll (the Nexus DLL path), and optionally visualStudio and dotnetPackageDirectory. This is a JavaScript API, not a shell command.

The helper:

1. Verifies the framework digest and its 28 required imports, generates the import definition from the actual export table, and prepares the pinned header override. Only GUITab.hpp's unused circular GUI.hpp include is omitted; declarations are unchanged.
2. Uses the in-process Roslyn API on .NET8 to emit the managed build helper. It then creates an isolated .NET Framework AppDomain with the installed MSBuild.exe.config dependency redirects.
3. Calls the public BuildManager API with a single node. The audited project uses standard C++ compiler/librarian/linker tasks; it contains no Exec, pre/post-build command, shell or batch step.
4. Builds build-lan/runtime/main.dll and, by default, build-lan/tests/LanTransportTests.dll. Existing build/main.dll is preserved. Nothing is deployed or launched.

在支持 Node JavaScript 的开发环境中导入上述 buildNative 函数并传入路径即可。没有批处理安装器，也不会调用 PowerShell、cmd 或远程 CI。MSBuild 标准任务会运行已安装的 C++ 编译器和链接器。

## Visual Studio route / IDE 路线

Call prepareNative from prepare-native.mjs with root and frameworkDll to prepare the same verified inputs. Then open FFWTeamSyncLan.vcxproj in Visual Studio, select Release / x64 and use Build. Open LanTransportTests.vcxproj similarly for the native test library. No command-line invocation is required.

## Tests / 测试

The LAN test DLL contains the exact production LanTransport.cpp behind a test-only C ABI (FFWTools/tests/lan_transport_api.cpp). NativeHarness.cs loads that test DLL in-process. The JavaScript runners under FFWTools/tests/lan use real loopback TCP connections and independent Wasmoon Lua profiles running production Session/Sync/Protocol/Store. Their TCP proxy drops/duplicates actual framed bytes and disconnects real sockets; it is not a substitute transport.

The source includes the original Steam transport tests and the new 31-file Lua regression suite. Native binaries, SDKs, generated import libraries, build logs, synthetic evidence files and local Data are not included in the source ZIP.

Static resolution of the UE4SS imports and loopback transmission do not establish two-PC in-game compatibility or complete gameplay-event coverage. The new connection UI and real game LAN run remain acceptance items.
