# Attribution / 来源与授权范围

Original FFWTools code and documentation are provided under the included MIT license. This is an unofficial community mod; it does not claim endorsement by the game developer, publisher, Valve or UE4SS maintainers.

FFWTools 原创代码和文档采用随附的 MIT 许可证。这是非官方社区 Mod，不声称获得游戏开发者、发行商、Valve 或 UE4SS 维护者背书。

## Game text and data / 游戏文本与数据

`CardText.lua` and the source catalog contain a selected static catalog of Far Far West card names, descriptions, identifiers, numeric values and curves, based on game data version 0.3.0.7. English names and descriptions use retained official game text. Those game-derived portions are attributed to Far Far West and their respective rights holders. The project's MIT license does not relicense those portions or grant rights in game assets or trademarks. Raw extracted game assets are not distributed in these packages.

`CardText.lua` 与来源目录 包含基于游戏 0.3.0.7 数据整理的卡牌名称、描述、标识、数值和曲线。英文名称及描述使用保留的游戏原文。这些游戏来源内容归 Far Far West 及其相应权利人所有，项目的 MIT 许可不对它们重新授权，也不授予游戏素材或商标的权利。发布包不包含原始游戏资源导出文件。

## UE4SS

Players install the game-specific [Nexus UE4SS package](https://www.nexusmods.com/farfarwest/mods/2). [UE4SS upstream](https://github.com/UE4SS-RE/RE-UE4SS) is credited as the framework source. This bridge uses pinned headers from source commit `8333063595fa3c49ad307f3b0f732accbb760d25`. [UE4SS is MIT licensed](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/LICENSE), copyright (c) 2022 Narknon. Its DLL, proxy loader and SDK are not bundled. The applicable notice is preserved in `licenses/UE4SS.txt` because the bridge uses its headers/API.

玩家安装 Nexus 游戏专用 UE4SS 3.0.1.1183；原生桥使用上述固定提交的头文件，所需 28 个导出均已在该 Nexus DLL 中核对。发布包不附带 UE4SS DLL、代理加载器或 SDK；对应版权声明保留在 `licenses/UE4SS.txt`。

## Native build headers / 原生构建头文件

FFWTeamSync uses Steam networking interfaces and `{fmt}` headers through its build dependencies. Their applicable notices are preserved in `licenses/SteamNetworkingSockets.txt` (Valve Corporation, BSD 3-Clause notice from the used networking headers) and `licenses/fmt.txt` (Victor Zverovich and contributors, MIT). No Steam runtime, Steamworks SDK, Steam account data or vendor tree is distributed. See `NATIVE-BUILD.md` in the source bundle for dependency paths.

FFWTeamSync 的构建依赖使用 Steam 网络接口及 `{fmt}` 头文件，相应声明分别保留在 `licenses/SteamNetworkingSockets.txt` 和 `licenses/fmt.txt`。发布包不包含 Steam 运行库、Steamworks SDK、Steam 账户资料或第三方依赖目录。源码包中的 `NATIVE-BUILD.md` 说明依赖路径。

No external save-editor implementation is included or licensed by this project. Synthetic IDs in offline test fixtures are test inputs, not captured player records.

本项目未包含外部存档编辑器的实现。离线测试中的合成 ID 是测试输入，并非采集的玩家记录。

## Development-only packaging

JSZip 3.10.1 is a separately installed development dependency (MIT or GPLv3); Wasmoon 1.16.0 provides the development Lua test host (MIT). Neither is bundled in the game runtime.

## Historical startup-signature attribution

This release ships no framework signature override. The Nexus dependency owns the signatures. Earlier project releases used ProcessLocalScriptFunction.lua from [halu103/farfarwest-frostburn-modkit](https://github.com/halu103/farfarwest-frostburn-modkit/blob/main/config/ue4ss/UE4SS_Signatures/ProcessLocalScriptFunction.lua), MIT. The complete original notice is retained in licenses/FrostburnModKit.txt. The framework and game binaries are not redistributed.
