# 安装与更新

首次启动前，必须先安装官方框架和包内游戏签名。压缩包把 ProcessLocalScriptFunction.lua 放在 FarFarWest/Binaries/Win64/ue4ss/UE4SS_Signatures。其他已装组件仍依赖它时，卸载单个组件请保留该共享文件。参见 UE4SS-COMPATIBILITY.zh-CN.md。

中文路径：已检查 Node 解压和 Lua 虚拟路径；原生 Windows Lua 使用窄字符文件 API，尚未验证所有系统编码。若中文库路径导致框架/脚本无法加载，可使用纯 ASCII 名称的 Steam 库路径，无需修改系统区域或注册表。

适用于 Windows / Steam，需要另行安装 UE4SS build 1181（3.0.1-1181-g83330635）。开发时使用的游戏数据版本为0.3.0.7。原生桥依赖此 UE4SS ABI，其他版本不可直接视为兼容。

1. 完全退出游戏。
2. 打开运行包中的 `GameRoot`，将其内容复制到 Steam「管理 > 浏览本地文件」打开的游戏目录。
3. 最终应存在以下文件：

```text
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/Scripts/main.lua
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/enabled.txt
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/Data/
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWTeamSync/dlls/main.dll
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWTeamSync/enabled.txt
```

单人和联机均需两个组件。包内的空白 `enabled.txt` 在指定版本中启用 Mod，不提供覆盖用的 `mods.txt`。如果原配置显式禁用了某个组件，请在现有 UE4SS 配置中启用它。

正常启动游戏，按 F8 打开面板，点击「显示设置」自定义 HUD。无需命令行、批处理或安装程序。

更新时完全退出游戏，仅替换包内文件；保留现有 `FFWStats/Data` 文件夹，以保留偏好和上一局记录。压缩包没有附带个人设置或对局数据。

卸载时关闭游戏，删除 `ue4ss/Mods` 中的 FFWStats、FFWTeamSync；若曾手动加入 `mods.txt`，仅删除对应条目。需要保留记录时先备份 Data。其他 Mod 和 UE4SS 无需删除。

[UE4SS 项目](https://github.com/UE4SS-RE/RE-UE4SS)
