# 已发布 0.1.0-beta.3 安装指南

**框架优先使用 [Nexus 游戏专用 UE4SS](https://www.nexusmods.com/farfarwest/mods/2?tab=files)。beta.3 同步依赖 Steam，不提供 LAN/IP 传输。新的 LAN 组件仍在开发中，不属于当前下载文件。**

## 目录与安装顺序

Steam → 管理 → 浏览本地文件，打开的是包含 FarFarWest.exe 的游戏根目录。框架目标目录为其内的 FarFarWest/Binaries/Win64，与 FarFarWest-Win64-Shipping.exe 同层。

1. 完全退出游戏；更新前将旧框架和需要的 Mod Data 备份到 Mods 之外。
2. 下载 Nexus 的玩家主文件 **UE4SS-FarFarWest 3.0.1.1183**，Frostburn / UE5.8，作者 anro / AnroG772（已核验文件 ID 242）。不要选旧 UE5.7 或 zDEV 开发包。
3. 将框架压缩包根部 dwmapi.dll、ue4ss 及随附文件复制到上述 Win64 目录。保留 Nexus 的完整配置和 FName_Constructor.lua、GNatives.lua、ProcessLocalScriptFunction.lua 三个签名。
4. 先确认能进入标题或酒馆，再完全退出。
5. 将 Stats beta.3 运行 ZIP 解压到临时目录。**只复制 GameRoot/FarFarWest/Binaries/Win64/ue4ss/Mods 内的 FFWStats、FFWTeamSync 两个文件夹到已安装的 ue4ss/Mods。** 已有 FFWStats/Data 时予以保留。
6. **不要整份合并旧 beta.3 的 GameRoot。旧包包含一个兼容 ProcessLocalScriptFunction.lua，不能覆盖正常工作的 Nexus 签名。** 不替换框架 DLL、配置、签名或整份 mods.txt。
7. 确认 FFWStats/Scripts/main.lua、FFWStats/enabled.txt、FFWStats/Data/、FFWTeamSync/dlls/main.dll、FFWTeamSync/enabled.txt 均存在，标记文件扩展名不是 .txt.txt。
8. 重启进入酒馆，按 F8。鼠标可选择标签、分项、翻页和 HUD 显示设置。

## 联机与按键

房主与参与同步的客机均安装同版本两个组件。beta.3 使用原生 Steam 身份及消息通道；LAN/IP 房间可能使用不同身份，当前桥接组件不支持。双方都安装旧组件也不能解除这个限制。不能以昵称、玩家顺序或虚构 Steam ID 代替实际身份。

F8 开关面板，PgUp/PgDn 切换指标，Home/End 切换区间。**beta.3 的 F10 分项页与 Nexus ConsoleEnabler 控制台冲突，请使用鼠标分页按钮。** 如要解除 Stats 的 F10 绑定，关闭游戏后，用文本编辑器打开 FFWStats/Scripts/Config.lua，把 nextPage='F10' 改为 nextPage=false，保留其他按键并重启。这是可选文本编辑，不需要批处理。

统计只使用观察到的事件；“不可用”和“部分数据”不能视为准确零值。Steam 握手成功不代表游戏事件已完整覆盖。上一局统计和 HUD 选择保存在 FFWStats/Data；升级时保留整个目录。游戏内及实际联机验收范围以发行说明为准。

## 排错、迁移与回退

- 启动崩溃：核对内层 Win64、Frostburn 主文件和完整签名。通用 GitHub 框架包不能代替推荐的完整游戏适配步骤。
- 旧框架迁移：备份 dwmapi.dll、整个 ue4ss 与所需 Data 到加载范围之外，移开或重命名旧框架，干净安装 Nexus，再装两个 Stats 文件夹并只恢复必要 Data。不要恢复旧引擎覆盖、全局设置、签名或缓存；不要未经备份删除整个框架。
- F8 无反应：检查运行包与源码包、路径层级、启用标记和完全重启；保留 UE4SS.log 中的具体错误。
- LAN 中等待身份：属于 beta.3 的已知传输限制；新 LAN 组件尚未发布。
- 无法保存：Data 必须存在并可写，不要在游戏运行时替换它。
- 非英文路径报 Lua 文件错误：可通过 Steam 存储管理移到英文路径，无需改系统区域。
- 回退：退出游戏，恢复匹配版本的 Stats Lua/原生组件与备份 Data，保留正常的 Nexus 框架。
- 卸载：备份 Data，只移除或停用 FFWStats、FFWTeamSync；其他 Mod 仍依赖 UE4SS 时保留框架。

已发布 beta.3 ZIP 附件保持不变，本指南修正它们的安装方法与支持范围。反馈问题时不要公开个人存档、配对码或未脱敏诊断压缩包。
