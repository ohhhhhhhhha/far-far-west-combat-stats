# 安装与联机设置（0.2.0-beta.1 测试版）

本包为统计 Mod 测试版本。使用 UE4SS；需要 FFWStats 与 FFWTeamSync 两个组件。真实回环 TCP 房主加两客机测试已通过；本机单实例房主监听、任务伤害与回酒馆保留已由用户确认正常。两台电脑的 LAN 事件覆盖仍待验收。

[项目仓库](https://github.com/ohhhhhhhhha/far-far-west-combat-stats) · [下载 0.2.0-beta.1](https://github.com/ohhhhhhhhha/far-far-west-combat-stats/releases/tag/v0.2.0-beta.1)

## 1. 找到游戏根目录

在 Steam 中选择 Far Far West → 管理 → 浏览本地文件。打开的目录包含 FarFarWest.exe，以下称为“游戏根目录”。

两种压缩包的复制位置不同：

| 内容 | 复制到 |
| --- | --- |
| Nexus 框架包中的 dwmapi.dll、ue4ss 及随附文件 | 游戏根目录内的 FarFarWest/Binaries/Win64，与 FarFarWest-Win64-Shipping.exe 同层 |
| 本 Mod 包内 GameRoot 文件夹里的内容 | Steam 打开的游戏根目录 |

不要把 GameRoot 文件夹本身复制进去，也不要多套一层 FarFarWest。

## 2. 安装游戏专用 UE4SS

1. 完全退出游戏。仅回标题不会重新加载 Mod。
2. 从 [Nexus：UE4SS for FarFarWest](https://www.nexusmods.com/farfarwest/mods/2?tab=files) 下载玩家主文件 **UE4SS-FarFarWest 3.0.1.1183**（Frostburn / UE 5.8，已核验文件 ID 242，作者 anro / AnroG772）。不要选旧 UE5.7 包或 zDEV 开发包。
3. 先解压到临时目录，再将根部 dwmapi.dll、ue4ss 等文件复制到上述 Win64 目录。
4. 确认存在 ue4ss/UE4SS.dll、ue4ss/UE4SS-settings.ini，以及 UE4SS_Signatures 下的 FName_Constructor.lua、GNatives.lua、ProcessLocalScriptFunction.lua 三个文件。
5. 先正常启动一次并进入标题或酒馆，再完全退出。此步骤只验证框架能够启动。

游戏专用签名和配置是这套依赖的一部分。通用 GitHub UE4SS 压缩包不能代替以上完整适配步骤。

## 3. 安装统计组件

1. 下载本版本的运行 ZIP，而非 source 源码 ZIP。
2. 合并运行 ZIP 内 GameRoot 的内容到游戏根目录。
3. 检查以下文件存在：

~~~text
FarFarWest/Binaries/Win64/ue4ss/Mods/
  FFWStats/
    enabled.txt
    Scripts/main.lua
    Scripts/Connection.lua
    Data/                 （初次安装为空）
  FFWTeamSync/
    enabled.txt
    dlls/main.dll
~~~

4. 两个 enabled.txt 都应存在，且文件扩展名不是 .txt.txt。本包通过启用标记加载，不替换整份 mods.txt。
5. 重启游戏进入酒馆，按 F8 打开面板；鼠标可选择标签、翻页、关闭以及修改“显示设置”。“联机设置”在右上角，未开始任务也能使用。

本版本不包含框架 DLL、框架设置或签名。安装时应保留 Nexus 提供的全部框架文件。

## 4. 单人和 Steam 房间

单人可保留默认 Steam 模式。Steam 联机时，房主及需要接收统计的队友都安装同版本的完整统计包，然后进入同一个游戏房间。身份可用后沿用 Steam 消息通道。

LAN/IP 房间应使用下节步骤。拥有一个 Steam 账号并不表示当前 LAN 角色可以用 Steam ID 映射。

## 5. LAN / IP 直连：房主

先在游戏中建立 LAN 房间，让队友进入酒馆。每台电脑都需要安装同版本 FFWStats 和 FFWTeamSync。

1. 房主按 F8 → 联机设置 → LAN / IP 直连。
2. 面板应识别“房主”，并显示本机 PlayerId。尚未出现身份时等待游戏角色加载；不要手填或猜测玩家 ID。
3. 设置端口，默认 **46055（TCP）**，点击“开启房主同步”。端口只用于统计，和游戏自己的联机端口独立。
4. 告诉队友这台电脑的局域网 IPv4 地址及统计端口。房主自己无需填写地址；监听在本机网络接口上。
5. 在当前队友列表中，核对队友面板显示的 PlayerId，点击该行“生成 / 查看”。即使昵称相同，也以 PlayerId 对应行绑定。
6. 下方文本框全选、复制配对码，只发送给该行对应队友。每名队友使用自己的码。
7. 等待“已认证连接”数量增加。所有所需队友连接后再开始任务。

配对码在本次房间内有效，不写入磁盘配置。切图时角色表可能逐步到齐，暂时缺席的队友保留“等待角色表”行；如果该队友确已离开，可点击该行“撤销”。正常切图保持配对并自动重连；玩家离房、返回标题、停止同步、房主重启或 PlayerId 改变后需要重新配对。

## 6. LAN / IP 直连：客机

1. 先进入房主的游戏 LAN 房间及酒馆。
2. F8 → 联机设置 → LAN / IP 直连。确认显示“客机”，将面板上的 PlayerId 告诉房主。
3. 填写房主局域网 IPv4 地址和相同的统计端口。
4. 粘贴房主专门为你的 PlayerId 生成的配对码，点击“连接房主”。其他队友的码不能使用。
5. 显示“已认证连接：1”后，由房主开始任务。暂时断网后会自动重试；不需要重复点击连接。

模式、房主地址和端口可以保存；配对码不保存。任务中不能切换身份模式或重建房间，需回酒馆再配置。网络握手成功只说明传输已连接，不等于所有游戏事件都有完整覆盖。

## 7. 验证数据与保存

- 进入新任务后，房主和客机分别造成一次伤害，再查看 F8“伤害”和“伤害来源”。各端应逐步收到同一份房主统计；传输和面板存在短暂刷新间隔。
- 测试一次换弹，检查它归属实际执行的队友。复活、治疗等条目只记录游戏事件能够确认的数值。
- 不可用表示尚未采集；星号表示部分数据。缺少组件、漏掉事件或断线区间不会被估成准确的零。
- 返回酒馆后保留上一局。下次任务开始后显示新局，定期自动保存到 FFWStats/Data/last-mission.json，写入时使用临时文件及备份替换。
- 每台电脑保存自己的副本。只在房主处有的事件需要同步后，客机副本才会更新。新房间重新配对，不会把旧房间相同数字 PlayerId 的同步队列套给新队友。
- HUD 勾选项目保存在 hud-settings.json；连接偏好保存在 connection-settings.json；boot-epoch.txt 用于持久同步序号。保留整个 Data 文件夹，不单独编辑这些文件。
- F8 开关详情；PgUp/PgDn 切换指标，Home/End 切换区间，分项页用鼠标按钮。Stats 默认不占用 F10，Nexus ConsoleEnabler 可能使用该键。

## 8. 常见问题

| 现象 | 检查方式 |
| --- | --- |
| 启动就崩溃 | 先核对 Win64 目录、Nexus Frostburn 主文件、完整签名和配置；不要混入旧 UE5.7 设置。必要时按下节备份迁移框架。 |
| F8 无反应 | 确认下载运行包、两个组件路径正确、enabled.txt 扩展名正确，并已完全退出重启。保留 ue4ss/UE4SS.log 中的具体错误。 |
| 提示原生组件未就绪 | 检查 FFWTeamSync/dlls/main.dll 与 Lua 同版本；旧 beta.3 原生桥没有 LAN 功能。 |
| 等待 PlayerId / 出现重复 ID | 等待角色表加载，确认已进入同一游戏房间。不能用昵称、Steam ID 或列表顺序填补。仍重复时重新进入房间并重配。 |
| 配对码无效 | 核对自己的 PlayerId，向房主取得对应行的新码；不要使用之前房间或其他队友的码。 |
| 一直连接中 | 确认房主已开启统计监听，IPv4 与端口正确、两端在可互通网络；检查现有网络访问策略。Mod 不自动改变防火墙。 |
| 已连接但无任务数字 | 酒馆不创建新任务统计；进入新任务后核对双方组件版本、角色表与具体覆盖状态。 |
| 无法保存 | 确认 Data 目录存在且可写；不要在游戏运行时替换 Data。 |
| 中文安装路径报 Lua 文件错误 | 可通过 Steam 存储管理移动游戏到纯英文路径后重试；无需改系统区域。 |

提交问题时先给版本、房主或客机、连接方式和具体错误。不要公开上传存档、完整 Data、配对码或含个人信息的原始日志。

## 9. 升级、迁移、回退和卸载

**升级本 Mod：** 完全退出游戏，备份两个组件及 FFWStats/Data 到 Mods 之外；覆盖本版本的两个组件目录，保留 Data；两端一起更新并重新配对。备份若仍在 Mods 内且带 enabled.txt，可能被当作重复 Mod 加载。

**迁移旧框架：** 备份 dwmapi.dll、整个 ue4ss 和各 Mod 的 Data 到游戏加载范围之外。将旧框架移开或重命名，干净安装 Nexus 专用框架，再安装当前内容包并仅恢复所需 Data。不要恢复旧全局设置、缓存、签名或强制引擎版本覆盖。不要未经备份删除整个 ue4ss。

**从已发布 beta.3 过渡：** 旧运行 ZIP 含一个兼容签名。若暂时继续用 beta.3，仅复制其 GameRoot/FarFarWest/Binaries/Win64/ue4ss/Mods 下 FFWStats、FFWTeamSync 两个目录；不要把旧包的 UE4SS_Signatures 覆盖到 Nexus 框架。beta.3 的同步路径依赖 Steam，不能据此宣称支持 LAN/IP。

**回退：** 关闭游戏，恢复同版本的 Lua 和原生组件，保留此前备份的 Data。旧版不能使用新 LAN 传输；保持 Nexus 框架的完整文件。

**卸载：** 关闭游戏，备份 Data 后仅移除或停用 FFWStats 与 FFWTeamSync。其他 Mod 仍依赖 UE4SS 时保留框架。本 Mod 不修改游戏永久进度。
