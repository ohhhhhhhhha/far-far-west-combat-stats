# Installation and updates

Install the official framework and the included game-specific signature before the first launch. The archive places ProcessLocalScriptFunction.lua in FarFarWest/Binaries/Win64/ue4ss/UE4SS_Signatures. Keep this shared file if another installed component still needs it. See UE4SS-COMPATIBILITY.en.md.

Non-ASCII paths: extraction is tested with Node and virtual Lua paths. Native Windows Lua uses narrow file APIs; compatibility with every Windows system encoding is not established. If framework/script loading fails in a non-ASCII library path, use an ASCII-named Steam library. No system locale or registry changes are required.

Windows / Steam, with separately installed UE4SS build 1181 (3.0.1-1181-g83330635). The game data version used during development was 0.3.0.7. The native bridge targets that UE4SS ABI; a different UE4SS build is not automatically interchangeable.

1. Completely close the game.
2. Open the runtime ZIP, then open `GameRoot`. Copy its contents into the game installation folder shown by Steam > Manage > Browse local files.
3. The final folders are:

```text
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/Scripts/main.lua
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/enabled.txt
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWStats/Data/
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWTeamSync/dlls/main.dll
FarFarWest/Binaries/Win64/ue4ss/Mods/FFWTeamSync/enabled.txt
```

Both components are required in solo and multiplayer. The empty `enabled.txt` markers enable the mods on the pinned UE4SS build. No replacement `mods.txt` is included. If an earlier configuration explicitly disables either component, enable it in your existing UE4SS configuration.

Start the game normally and press F8. Open HUD options to customize the HUD. No command line, batch file or installer is required.

To update, close the game and replace only the package's files. Keep the existing `FFWStats/Data` folder so preferences and the previous mission remain available. The ZIP contains no personal preferences or mission records.

To uninstall, close the game and remove FFWStats and FFWTeamSync from `ue4ss/Mods`; remove only their entries if you added them to `mods.txt`. Back up Data first if you want to keep your records. Other mods and UE4SS can stay installed.

[UE4SS project](https://github.com/UE4SS-RE/RE-UE4SS)
