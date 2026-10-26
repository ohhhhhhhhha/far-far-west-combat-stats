# FFWTeamSync native build / 原生构建

The source archive does not include the UE4SS SDK, Steamworks SDK, vendor sources or compiled binaries. The Lua mods and offline Lua tests can be used without compiling this bridge.

源码包不附带 UE4SS SDK、Steamworks SDK、第三方源码或编译产物。Lua 组件及离线 Lua 测试不依赖此桥接模块的编译。

## Current supported build inputs

`FFWTools/src/FFWTeamSync/build.ps1` is the retained Windows build recipe. It currently uses the following relative dependency layout. Obtain the dependencies separately and place them in this layout, or adapt the paths in your own build environment. This document does not claim an out-of-the-box SDK-free native build.

`build.ps1` 是保留的 Windows 构建脚本，使用以下相对依赖布局。需自行取得依赖并按此放置，或在自己的构建环境中调整路径；此说明不声称无需 SDK 即可直接编译。

```text
<working root>/
  FFWTools/
    src/FFWTeamSync/{Bridge.cpp,Transport.cpp,Transport.hpp,SteamBinding.cpp,build.ps1}
    tests/{transport_test.cpp,transport_abi_test.cpp}
    vendor/
      ue4ss-1181/ue4ss/UE4SS.dll
      team-sync-ue4ss-1181/
        source/RE-UE4SS-8333063595fa3c49ad307f3b0f732accbb760d25/
          UE4SS/include/...
          deps/first/{File,Input,String,LuaMadeSimple,LuaRaw}/include/...
        fmt/fmt-11.2.0/include/...
        steam/steamnetworkingtypes.h (and the headers it includes)
  Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll
```

- Visual Studio 2022 with C++ x64 tools and a Windows SDK. The script imports the Visual Studio developer shell; supply `-VisualStudio` if installed outside its default Community path.
- [UE4SS source](https://github.com/UE4SS-RE/RE-UE4SS/tree/8333063595fa3c49ad307f3b0f732accbb760d25) at the pinned commit, including the listed first-party dependency headers. Match the UE4SS runtime binary to build 1181.
- Required UE4SS DLL SHA-256: `ce5e3c46a920cc00b2817ac61e438c9162830290379d0b5b9c4dfc2b29459290`. The build script enforces this. Changing the runtime requires a matching-header/ABI rebuild and validation.
- `{fmt}` 11.2.0 headers and Steam networking headers compatible with the API types in `Transport.hpp`. Use your lawful SDK/header source and retain its license; do not add the entire SDK or vendor tree to the release manifest.
- The game's own `Steamv157` `steam_api64.dll` at the path shown above is used by the ABI test. Do not redistribute it. The build script derives `<working root>` from the parent of `FFWTools`; a clone outside the game directory must supply the expected file or adapt the build recipe locally.

构建需要 Visual Studio 2022 的 C++ x64 工具及 Windows SDK、上述固定版本的 UE4SS 头文件和 DLL、`fmt` 11.2.0 头文件、与 `Transport.hpp` 接口类型匹配的 Steam 网络头文件。ABI 测试读取游戏自身的 Steamv157 DLL，不应重新分发它。脚本以 `FFWTools` 的父目录作为工作根；源码克隆在其他位置时，需要自行提供对应路径或调整本地构建脚本。

## Build recipe

From the bundle root / 在源码包根目录：

Use the retained build.ps1 recipe in a configured Visual Studio C++ environment. It is a developer helper, not an installer.

The first command runs the native transport and ABI tests. The second also builds `FFWTools/src/FFWTeamSync/build/main.dll`. Both require the pinned dependencies because the script validates the framework before compilation. It does not deploy the bridge or launch the game. `package.mjs` packages only `main.dll` for the Stats runtime; `.obj`, `.lib`, `.exp`, executables and generated header overrides stay out of the source/runtime archives.

第一条运行原生传输及 ABI 测试；第二条还生成 `main.dll`。两条都需要固定依赖，因为脚本会在编译前验证框架。脚本不部署模块，也不启动游戏。发布构建仅将 `main.dll` 放入 Stats 运行包，不携带其他编译产物或生成的头文件覆盖目录。

Native unit/ABI tests verify their declared boundaries. They do not prove multiplayer delivery, complete event capture or live game compatibility. Full-team runtime validation remains outstanding for this experimental release.

原生单元及 ABI 测试只验证其覆盖的边界，不能证明多人传输、完整事件采集或游戏内兼容性；本实验版仍缺少全队运行验证。
