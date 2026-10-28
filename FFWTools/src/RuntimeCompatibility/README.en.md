# Far Far West UE4SS startup signature

All three components use the same ProcessLocalScriptFunction.lua. Runtime archives install it at `GameRoot/FarFarWest/Binaries/Win64/ue4ss/UE4SS_Signatures/`. Merge GameRoot into the game directory before the first UE4SS launch. Starting the official loader without this game-specific override can select the wrong function entry.

The verified game baseline is Far Far West 0.3.0.7, CL 2852, UE 5.8.1, Windows x64. Installed build 1181 (83330635) logs show this override in use. The supplied report describes a successful startup repair with build 1183; that does not validate the native statistics bridge ABI on 1183.

The signature scans wildcard bytes and resolves the current address on each run. It contains no absolute process addresses, Steam IDs, personal paths or machine settings. Drive letters, spaces/non-ASCII installation paths and ASLR do not require edits. Other game revisions require verification.

This patch preserves the official loader, proxy DLL, UE4SS-settings.ini and mods.txt. It does not claim to resolve the separate GPU or native reflection/access violations in report B02, B07 or B08.

Exit the game and back up an existing same-name override before updating. Each component must ship identical signature bytes. Keep the shared override when uninstalling a component if another installed component still needs it.

Source: [halu103/farfarwest-frostburn-modkit](https://github.com/halu103/farfarwest-frostburn-modkit/blob/main/config/ue4ss/UE4SS_Signatures/ProcessLocalScriptFunction.lua). MIT license; the complete notice is in `licenses/FrostburnModKit.txt`. [Official UE4SS signature API](https://docs.ue4ss.com/dev/guides/fixing-compatibility-problems.html).
