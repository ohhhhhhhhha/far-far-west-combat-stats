# UE4SS installation and updates for Far Far West

Use [UE4SS for FarFarWest on Nexus](https://www.nexusmods.com/farfarwest/mods/2?tab=files), by anro / AnroG772. The inspected player main file is **UE4SS-FarFarWest 3.0.1.1183**, marked Frostburn / UE 5.8, file ID 242. The checked game is 0.3.0.7. Old UE 5.7 archives and zDEV developer packages are not this installation baseline.

The Nexus package contains the game-specific signatures and settings. The generic upstream GitHub archive alone does not complete the game's framework setup. GitHub remains the source/download location for each content Mod; obtain the framework from the Nexus page above.

## Locate the two destinations

Steam > Manage > Browse local files opens the game root, containing FarFarWest.exe.

| Archive content | Destination | File that identifies the destination |
| --- | --- | --- |
| Nexus framework: dwmapi.dll, ue4ss and accompanying files | FarFarWest/Binaries/Win64 inside the game root | FarFarWest-Win64-Shipping.exe |
| Contents inside a content Mod archive's GameRoot folder | The game root opened by Steam | FarFarWest.exe |

Copy the contents, without an extra GameRoot or outer extraction folder.

## First installation

1. Fully exit the game. Returning to its title screen is insufficient.
2. Download the Nexus player main file and extract it to a temporary directory. Its root contains dwmapi.dll and ue4ss directly.
3. Copy those framework files into the directory containing FarFarWest-Win64-Shipping.exe.
4. Confirm dwmapi.dll, ue4ss/UE4SS.dll, UE4SS-settings.ini and all three signature files: FName_Constructor.lua, GNatives.lua and ProcessLocalScriptFunction.lua.
5. Launch normally and check that the title/saloon is reachable. For diagnosis, inspect ue4ss/UE4SS.log for engine 5.8, the Lua Script ProcessLocalScriptFunction scan and event-loop startup. The external debug console is disabled by default.
6. Exit completely. Install the selected Mod's runtime ZIP by merging the contents of GameRoot into the game root, then restart and follow its controls.

Current Nexus-compatible content packages preserve framework DLLs, settings and signatures. Older content archives can contain a fallback signature; do not overwrite the working Nexus files with those older archives.

## Migrate an older framework

Back up the existing ue4ss directory, dwmapi.dll and each Mod's Data outside Mods. Record other installed mods and custom bindings. A backup left inside Mods with enabled.txt may be loaded as another mod.

With the game closed, move the old framework aside and install the Nexus package cleanly. Do not restore old global settings, signatures, caches or forced engine-version overrides. Install current component packages, then restore only their required Data. Reinstall other mods according to their authors' instructions. Never delete the entire old framework without preserving the data you need.

## Enable and verify

A Lua component should have ue4ss/Mods/Component/Scripts/main.lua and its supplied enabled.txt. Combat Stats also requires FFWTeamSync/dlls/main.dll and enabled.txt; participants must install the complete statistics package. Both Lua and C++ components can use enabled.txt, so these packages do not replace the user's entire mods.txt.

Verify each component's version log and actual UI/action/connection results. Framework startup is only the first check. The Nexus console can use F10; follow the component's binding instructions and use mouse controls for statistics navigation where appropriate.

## Troubleshooting and rollback

- Startup failure: verify the inner Win64 destination, Frostburn build and complete signatures. Mixed old engine-5.7 settings require a clean framework migration.
- No mod: check nested directories, runtime versus source ZIP, the actual enabled.txt extension and a complete restart.
- One failed action: retain its exact UI message and follow that component's diagnosis. Keep Data while investigating.
- Lua path errors under non-ASCII Windows paths: use Steam storage management to move the game to an ASCII path and retry. No system-locale changes are required by these mods.
- Rollback: close the game and restore the matching backed-up framework/component set. Game saves and Mod Data are different; uninstalling the trainer does not undo saved progression.

Remove only the intended content component when other mods still need UE4SS. Back up Data and settings before a complete framework uninstall.

## Inspected dependency

The inspected Nexus archive SHA-256 is 87c1d83576e43324c2310f8a7fd3961d71dcab07d75f4b1fbf3bb0c2c226b375. A later author update has a different digest. Native bridge compatibility and supported network modes are documented by Combat Stats.
