# Far Far West 战斗统计

[下载本测试版](https://github.com/ohhhhhhhhha/far-far-west-combat-stats/releases/tag/v0.2.0-beta.1) · [English](README.md) · [完整安装与联机指南](INSTALL.zh-CN.md)

中英双语统计面板和紧凑 HUD，随游戏语言切换。F8 打开详情，可用鼠标选择标签、分项和翻页；“显示设置”勾选游戏画面中显示的项目。统计包括含过量的结算伤害、来源分类、承伤、DPS 峰值、击杀、治疗、弹药、生存及团队贡献。未采集的数据保留“不可用”，部分覆盖明确标记。

**0.2.0-beta.1 为测试版。** 本机单实例 LAN 房主监听、任务伤害数据与回酒馆保留已由用户确认正常；实际两台电脑的 LAN 事件覆盖仍待验收。 新增 LAN/IP 配对同步，保留 Steam 路径。房主及客机均安装 FFWStats 和 FFWTeamSync，在 F8“联机设置”填写端口、房主 IPv4 和专属配对码。实际 PlayerId 对应玩家，昵称不用于身份绑定。生产 Session/Sync/Protocol/Store 已通过原生回环测试，覆盖丢帧、重连、切图、换局和独立保存。

## 安装入口

框架使用 [Nexus 游戏专用 UE4SS](https://www.nexusmods.com/farfarwest/mods/2?tab=files) 的 3.0.1.1183 Frostburn / UE5.8 玩家主文件。框架复制到 Steam 游戏根目录内的 FarFarWest/Binaries/Win64；本 Mod 的 GameRoot 内容合并到 Steam 游戏根目录。保留 Nexus 签名、配置和原有 Mod Data。双方 LAN 配置、连接验证、升级及回退请按[完整指南](INSTALL.zh-CN.md)操作。

F8 开关详情，鼠标点击标题与标签、使用分页按钮；PgUp/PgDn 切换指标，Home/End 切换区间。Stats 默认不占用 Nexus ConsoleEnabler 的 F10。当前局自动保存，回酒馆后保留上一局，下一局开始时切换。

团队贡献榜是依据已记录事件计算的加权参考，不是对玩家水平的客观评判。真实双机 LAN 事件覆盖仍需游戏内验收。此前公开的 beta.3 依赖 Steam，单独安装旧版不提供 LAN/IP 传输。

## 项目范围

本仓库只包含统计 Mod 和同步组件，不含修改器、刷卡功能、个人存档、采集到的玩家数据或 UE4SS 运行库。源码与运行包分开提供。参阅[开发说明](DEVELOPMENT.md)、[原生构建](NATIVE-BUILD.md)、[许可证](LICENSE)与[第三方声明](THIRD-PARTY-NOTICES.md)。
