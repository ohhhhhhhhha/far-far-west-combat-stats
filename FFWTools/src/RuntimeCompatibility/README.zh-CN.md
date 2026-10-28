# Far Far West 的 UE4SS 启动签名

三个组件共用同一份 ProcessLocalScriptFunction.lua。运行包将它放在 `GameRoot/FarFarWest/Binaries/Win64/ue4ss/UE4SS_Signatures/`。安装时合并 GameRoot 内容，先安装这份游戏签名，再第一次启动 UE4SS；只装官方框架后直接启动可能命中错误的函数入口。

## 适用范围

本次核验基线是 Far Far West 0.3.0.7、CL 2852、UE 5.8.1 的 Windows x64 版本。本机 UE4SS 1181（83330635）日志已确认此签名被加载。用户报告指出同类签名解决了 1183 的一次启动扫描复现；这不代表统计原生桥已验证 1183 的 ABI。

签名按通配字节扫描，每次启动解析实际地址，不包含进程绝对地址、Steam ID、个人路径或机器配置。安装盘符、中文目录和地址随机化无需修改它。其他游戏更新仍需重新验证，不能保证任意版本兼容。

本目录不替换 UE4SS.dll、代理 DLL、UE4SS-settings.ini 或 mods.txt。不要把加载器故障、显卡崩溃和失效对象调用混为一种错误。本补丁不声称修复报告 B02、B07 或 B08。

## 更新与回滚

退出游戏，备份已有的同名签名文件，再复制新版。三个组件的签名字节必须一致；更新其中一个组件即可补齐。移除某个组件时不要删掉仍被其他组件使用的共享签名。

## 来源

签名来自 [halu103/farfarwest-frostburn-modkit](https://github.com/halu103/farfarwest-frostburn-modkit/blob/main/config/ue4ss/UE4SS_Signatures/ProcessLocalScriptFunction.lua)，按 MIT 许可证分发，完整授权见 `licenses/FrostburnModKit.txt`。[UE4SS 官方签名接口说明](https://docs.ue4ss.com/dev/guides/fixing-compatibility-problems.html)。
