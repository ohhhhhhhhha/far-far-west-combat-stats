# UE4SS 框架安装与更新（Far Far West）

本项目的玩家安装入口是 [Nexus：UE4SS for FarFarWest](https://www.nexusmods.com/farfarwest/mods/2?tab=files)，作者 anro / AnroG772。当前核对的是 Main files 中的 **UE4SS-FarFarWest 3.0.1.1183**（Frostburn、UE 5.8，文件 ID 242）。选择玩家主文件；旧版 UE 5.7 包和 zDEV 开发包不作为本指南的安装基线。游戏核验版本为 0.3.0.7。

这个包带有游戏专用签名和配置。仅下载上游 GitHub 的通用 UE4SS 压缩包，不等于完成本游戏的框架安装。模组源码与发布文件仍在各自 GitHub 仓库，框架请从上述 Nexus 页面下载。

## 先分清两个目录

在 Steam 中右键游戏，选择“管理 → 浏览本地文件”。打开的文件夹称为游戏根目录，里面有 FarFarWest.exe。

| 要安装的内容 | 复制到哪里 | 目标目录的识别文件 |
| --- | --- | --- |
| Nexus 框架 ZIP 中的 dwmapi.dll、ue4ss 等内容 | 游戏根目录内的 FarFarWest/Binaries/Win64 | FarFarWest-Win64-Shipping.exe |
| 本 Mod ZIP 的 GameRoot 文件夹里面的内容 | Steam 打开的游戏根目录 | FarFarWest.exe |

不要把 GameRoot 文件夹本身复制进游戏目录，也不要多套一层解压文件夹。

## 首次安装

1. 完全退出游戏；只返回标题画面不算退出。
2. 下载 Nexus 主文件并在临时目录解压。它的根目录可直接看到 dwmapi.dll 和 ue4ss 文件夹。
3. 打开含 FarFarWest-Win64-Shipping.exe 的 Win64 目录，将框架内容复制到这里。
4. 核对 Win64/dwmapi.dll、Win64/ue4ss/UE4SS.dll、UE4SS-settings.ini，以及 UE4SS_Signatures 中的 FName_Constructor.lua、GNatives.lua、ProcessLocalScriptFunction.lua。
5. 先正常启动一次游戏，确认能进入标题或酒馆。需要排查时打开 ue4ss/UE4SS.log，确认引擎识别为 5.8、ProcessLocalScriptFunction 使用 Lua Script 签名、事件循环已开始。外部调试窗口默认关闭，不以是否弹出黑色窗口判断成功。
6. 完全退出游戏，再安装对应 Mod 的运行 ZIP。将其 GameRoot 内的内容合并到游戏根目录，完整重启后使用对应快捷键。

本说明对应的新内容包不会替换框架 DLL、设置或签名。旧内容包可能带有兼容签名，不要用旧包覆盖已经正常工作的 Nexus 签名；选用当前 Nexus 适配安装包。

## 从旧框架迁移

先把原 ue4ss 文件夹、dwmapi.dll，以及需要保留的各 Mod Data 文件夹备份到 Mods 目录以外。记录正在使用的其他 Mod 和快捷键。不要在 Mods 内保存带 enabled.txt 的旧副本，框架可能把它也加载起来。

在游戏完全退出后移开旧框架，再按首次安装步骤放入 Nexus 框架。不要把旧 UE4SS-settings.ini、旧签名、缓存或版本强制配置复制回去。安装当前版本的各个 Mod 后，仅恢复它们各自需要的 Data；其他 Mod 请按其作者说明重新安装。这样可保留设置和统计记录，同时避免旧的引擎版本覆盖影响新框架。不要未备份就删除整个 ue4ss。

## 启用与核对

Lua 模组的入口应在 ue4ss/Mods/模组名/Scripts/main.lua，同级模组目录中应有随包提供的 enabled.txt。统计包还需要 FFWTeamSync/dlls/main.dll 与其 enabled.txt，两端都要安装完整统计包。框架支持 Lua 和 C++ 模组使用 enabled.txt，无需为本套 Mod 覆盖整个 mods.txt。

框架正确不等于每项 Mod 功能已生效；继续按各组件的安装说明检查版本日志、面板、应用结果或连接状态。Nexus 框架的 F10 可打开控制台，组件快捷键以该组件说明为准，统计操作可使用面板中的鼠标按钮。

## 排错与回滚

- 启动即报错：先核对目标 Win64 目录、Frostburn 版本和三个签名是否完整；混用旧的 5.7 强制设置时应重新进行框架迁移。
- 模组没有加载：检查是否多套目录、下载了源码包、enabled.txt 扩展名错误，或没有完全重启。
- 只有一个功能失败：保留具体面板提示，按该组件的排错章节处理，不要通过替换整套框架或随意删除 Data 掩盖问题。
- 非 ASCII 路径下框架无法读取 Lua 文件：使用 Steam 存储管理将游戏移动到普通英文路径后再核验；本项目没有修改系统区域设置。
- 回滚：退出游戏，恢复已备份的匹配版本框架和模组。游戏存档与 Mod Data 是不同内容，修改器已经保存的进度不会因卸载而撤销。

卸载某个内容 Mod 时只处理该组件；其他 Mod 仍依赖 UE4SS 时保留框架。完整框架卸载前先备份 Data 和相关配置，再按框架作者说明移除。

## 核验记录

本次 Nexus 主文件 ZIP 的 SHA-256 为 87c1d83576e43324c2310f8a7fd3961d71dcab07d75f4b1fbf3bb0c2c226b375。此值用于确认本次核验的文件，不适用于作者以后更新的包。原生桥的实际版本兼容范围和联机模式以统计组件说明为准。
