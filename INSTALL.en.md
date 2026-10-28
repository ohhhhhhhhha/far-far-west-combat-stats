# Install the published 0.1.0-beta.3 release

**Use the game-specific [UE4SS for FarFarWest Nexus package](https://www.nexusmods.com/farfarwest/mods/2?tab=files). Beta.3 uses the Steam synchronization path; it does not provide LAN/IP transport. A new LAN component is in development and is not part of the current download.**

## Find the two destinations

Steam → Manage → Browse local files opens the game root containing FarFarWest.exe. The framework goes inside FarFarWest/Binaries/Win64, next to FarFarWest-Win64-Shipping.exe.

1. Fully exit the game. Back up the existing framework and needed Mod Data outside Mods before updating.
2. Download the Nexus player main file **UE4SS-FarFarWest 3.0.1.1183**, Frostburn / UE5.8, by anro / AnroG772 (inspected file ID 242). Do not select old UE5.7 or zDEV files.
3. Extract its root dwmapi.dll, ue4ss and accompanying files into that inner Win64 directory. Preserve the full Nexus settings and all three game signatures: FName_Constructor.lua, GNatives.lua and ProcessLocalScriptFunction.lua.
4. Check that the game reaches the title or saloon, then exit completely.
5. Extract the Stats beta.3 runtime ZIP to a temporary folder. **Copy only the two folders FFWStats and FFWTeamSync from GameRoot/FarFarWest/Binaries/Win64/ue4ss/Mods into the installed ue4ss/Mods.** Preserve FFWStats/Data if it exists.
6. **Do not merge the old beta.3 GameRoot wholesale. It includes a fallback ProcessLocalScriptFunction.lua that must not overwrite the working Nexus signature.** Do not replace the framework DLL, settings, signatures or mods.txt with files from another package.
7. Confirm FFWStats/Scripts/main.lua, FFWStats/enabled.txt, FFWStats/Data/, FFWTeamSync/dlls/main.dll and FFWTeamSync/enabled.txt. The marker must not be named enabled.txt.txt.
8. Restart and press F8 in the saloon. Mouse controls should select tabs, subitems, pages and HUD options.

## Multiplayer and controls

Install both components at the same version on the host and all participating guests. Beta.3 uses native Steam identities/messages; a LAN/IP room can have different identities and is not supported by this bridge. Installing it on every LAN PC does not remove that limitation. Do not substitute names, roster positions or invented Steam IDs.

F8 toggles the panel; PgUp/PgDn selects metrics, Home/End selects scope. **Beta.3 binds F10 for subpages, which conflicts with Nexus ConsoleEnabler. Use the mouse paging buttons.** To remove the Stats F10 binding in this version, with the game closed open FFWStats/Scripts/Config.lua in a text editor and change nextPage='F10' to nextPage=false. Keep the other bindings intact; restart afterward. This is an optional manual edit, not a batch command.

Metrics use observed events; unavailable and partial flags remain meaningful. A Steam handshake does not prove full event coverage. Last-mission statistics and HUD choices are saved in FFWStats/Data. Keep that whole directory during upgrades. Actual native-game/multiplayer acceptance remains documented in the release notes.

## Troubleshooting, migration and rollback

- Startup crash: verify the inner Win64 destination, Frostburn build and complete game signatures. Generic upstream GitHub archives alone are not the recommended complete setup.
- Old framework migration: back up dwmapi.dll, the entire ue4ss folder and needed Mod Data outside loading paths. Move/rename the old framework aside, install Nexus cleanly, install the two Stats folders, and restore only required Data. Do not restore old engine overrides/settings/signatures/caches. Never delete the old framework without preserving data.
- No F8: confirm runtime versus source ZIP, exact directory/marker names and a full restart. Keep the exact UE4SS.log error.
- Waiting for identity in LAN: this is a known beta.3 transport limitation; the new LAN component is not yet released.
- Save failure: Data must exist and be writable. Do not replace it while the game runs.
- Non-ASCII Lua path failure: use Steam storage management to move to an ASCII path; no system-locale change is required.
- Rollback: close the game, restore a matching backed-up Stats Lua/native component set and its Data, and preserve the working Nexus framework.
- Uninstall: back up Data, then remove/disable only FFWStats and FFWTeamSync. Keep UE4SS if other mods require it.

Published beta.3 ZIP attachments are unchanged. This guide corrects installation and support scope for those existing files. Do not publish personal saves, pairing codes or unredacted diagnostic archives when reporting a problem.
