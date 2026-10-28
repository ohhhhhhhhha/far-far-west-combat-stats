# Installation and team setup (0.2.0-beta.1 beta)

This is a beta Combat Stats release using UE4SS. Install both FFWStats and FFWTeamSync. Native loopback host-plus-two-guest tests passed. In-game single-instance host listening, mission damage data and retained saloon results were confirmed by the user; real two-PC LAN event coverage remains pending.

[Project](https://github.com/ohhhhhhhhha/far-far-west-combat-stats) · [Download 0.2.0-beta.1](https://github.com/ohhhhhhhhha/far-far-west-combat-stats/releases/tag/v0.2.0-beta.1)

## Locate the destinations

Steam → Far Far West → Manage → Browse local files opens the game root containing FarFarWest.exe.

| Archive contents | Destination |
| --- | --- |
| Nexus framework: dwmapi.dll, ue4ss and accompanying files | FarFarWest/Binaries/Win64 inside the game root, beside FarFarWest-Win64-Shipping.exe |
| Contents inside this Mod archive's GameRoot folder | The game root opened by Steam |

Copy the contents, without an extra GameRoot or FarFarWest wrapper folder.

## Install the game-specific framework

1. Fully exit the game; returning to its title screen does not reload mods.
2. Download the player main file **UE4SS-FarFarWest 3.0.1.1183** from [UE4SS for FarFarWest on Nexus](https://www.nexusmods.com/farfarwest/mods/2?tab=files), by anro / AnroG772. The inspected Frostburn / UE5.8 file is ID 242. Do not select the older UE5.7 archives or zDEV developer packages.
3. Extract it to a temporary directory. Copy its root dwmapi.dll, ue4ss and accompanying files into the Win64 destination above.
4. Verify ue4ss/UE4SS.dll, ue4ss/UE4SS-settings.ini, and all three UE4SS_Signatures files: FName_Constructor.lua, GNatives.lua, ProcessLocalScriptFunction.lua.
5. Launch normally and reach the title/saloon, then exit completely. This checks framework startup only.

The game-specific signatures and settings are part of this dependency. A generic upstream GitHub archive alone is not the complete framework setup.

## Install Combat Stats on every participant's PC

1. Use the runtime ZIP, not the source ZIP.
2. Merge the contents of GameRoot into the Steam game root.
3. Confirm the resulting layout:

~~~text
FarFarWest/Binaries/Win64/ue4ss/Mods/
  FFWStats/
    enabled.txt
    Scripts/main.lua
    Scripts/Connection.lua
    Data/                 (empty on a first installation)
  FFWTeamSync/
    enabled.txt
    dlls/main.dll
~~~

Both enabled.txt markers must exist with the correct extension. They enable the Lua and native components; the package does not replace your mods.txt. Restart the game, enter the saloon and press F8. Use the mouse to select tabs, page through items, close the panel or change HUD options. Connection settings work before a mission begins.

This release contains no framework DLL, global settings or signature replacement. Preserve all Nexus framework files.

## Solo and Steam rooms

Solo can retain the default Steam mode. In Steam multiplayer, install the matching full Stats package on the host and every teammate who needs synchronized statistics, then join the same game room. The existing Steam transport is used when its identities are available.

For LAN/IP rooms follow the next steps. Having a Steam account does not establish a Steam mapping for the game's LAN PlayerState.

## LAN / direct IP — host

Create the game's LAN room and let teammates join the saloon first. Everyone needs the same FFWStats and FFWTeamSync version.

1. F8 → Connection → LAN / direct IP.
2. Confirm the displayed role is Host and a local PlayerId is available. Wait for the game roster if it is missing; do not invent an ID.
3. Choose a statistics TCP port, default **46055**, and select Start host sync. This port is independent of the game's own connection port.
4. Give teammates your LAN IPv4 address and this statistics port. The host does not enter an address; it listens on this PC's network interfaces.
5. Match the teammate's displayed PlayerId to the current roster row. Select Generate / view for that row. Identical display names do not affect identity binding.
6. Select all and copy the code from the field below, and give it only to that assigned teammate. Each teammate uses a separate code.
7. Wait for the authenticated connection count to increase before starting the mission.

Codes are held in memory for this room. During travel, the roster can arrive incrementally; absent paired peers remain marked roster pending. If a peer has actually left, the host can use Revoke on that row. Normal map travel keeps pairing and reconnects automatically. Leaving the room, returning to title, stopping synchronization, restarting the host, or changing PlayerId requires new pairing.

## LAN / direct IP — guest

1. Join the host's game LAN room and enter the saloon.
2. F8 → Connection → LAN / direct IP. Confirm Guest and tell the host your displayed PlayerId.
3. Enter the host's LAN IPv4 address and matching statistics port.
4. Paste the code generated specifically for your PlayerId and select Connect to host. Another teammate's code is rejected.
5. Wait for Authenticated connections: 1, then let the host start the mission. Temporary disconnects retry automatically.

Mode, host address and port are saved; pairing codes are not. Changing identity mode or rebuilding a room is restricted to the saloon. A successful network handshake proves connectivity, not complete gameplay-event coverage.

## Verify data and saved results

- Start a new mission. Have host and guest each damage an enemy, then inspect F8 Damage and Damage sources. Clients should receive the same host-authored snapshot after the short transport/UI refresh delay.
- Reload once and verify attribution to the player who performed it. Revives, healing and other fields only count events the game adapter can establish.
- Unavailable means unobserved. An asterisk means partial data. Missing components/events/disconnected intervals are not estimated as accurate zeroes.
- Returning to the saloon retains the last mission. The next mission switches the display to the new run. FFWStats/Data/last-mission.json is saved periodically with temporary-file and backup replacement.
- Each PC has an independent save. Host-only observations reach a guest save only after synchronization. New room pairing isolates old queues even when numeric PlayerIds are reused.
- hud-settings.json stores HUD choices; connection-settings.json stores nonsecret connection preferences; boot-epoch.txt stores the persistent synchronization epoch. Preserve the entire Data directory rather than editing these files independently.
- F8 toggles the panel; PgUp/PgDn selects metrics; Home/End selects scope. Use mouse buttons for subpages. Stats does not bind F10 by default because the Nexus ConsoleEnabler may use it.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Startup crash | Correct inner Win64 destination, Nexus Frostburn player main file, all signatures/settings; remove mixed old UE5.7 settings through the backed-up migration below. |
| F8 does nothing | Runtime versus source ZIP, both component directories, enabled.txt extension and a full restart. Keep the exact UE4SS.log error. |
| Native component unavailable | Matching FFWTeamSync/dlls/main.dll and Lua version. The old beta.3 bridge has no LAN API. |
| Missing or duplicate PlayerId | Wait for the roster and confirm the same game room. Do not substitute a name, Steam ID or roster position. Rejoin and pair again if it persists. |
| Invalid pairing code | Get a fresh code for your current PlayerId, not another teammate or previous room. |
| Stuck connecting | Host listener is started, IPv4/port match, PCs can reach each other, and existing network access policy permits it. The Mod does not change firewall rules. |
| Connected but no mission data | The saloon does not create a mission. Enter a new mission, check matching components, current roster and coverage indicators. |
| Save failure | Data exists and is writable; do not replace it while the game runs. |
| Lua path error with non-ASCII installation path | Move the game using Steam storage management to an ASCII path and retry. No system-locale change is required. |

For a report provide version, host/guest role, connection mode and exact error. Do not publicly upload saves, the whole Data folder, pairing codes or raw logs containing personal information.

## Upgrade, migrate, roll back or uninstall

**Mod update:** close the game, back up both components and FFWStats/Data outside Mods, then replace the two component directories with the new version while preserving Data. Update all participants together and pair again. An enabled backup kept inside Mods may load twice.

**Old framework migration:** back up dwmapi.dll, the entire ue4ss directory and every needed Mod Data folder outside the game's loading paths. Move/rename the old framework aside, install the Nexus package cleanly, install current content packages, then restore only required Data. Do not restore old global settings, caches, signatures or forced engine-version overrides. Never delete the entire framework without preserving needed data.

**Currently published beta.3:** its archive contains a fallback signature. If you continue using beta.3, copy only FFWStats and FFWTeamSync from GameRoot/FarFarWest/Binaries/Win64/ue4ss/Mods. Preserve the Nexus signatures/settings; do not merge the old archive's UE4SS_Signatures. Beta.3 uses the Steam path and does not establish LAN/IP support.

**Rollback:** exit, restore a matching backed-up Lua/native component set and its Data. Old versions cannot use the new LAN transport. Keep the complete Nexus framework. 

**Uninstall:** close the game, back up Data, then remove/disable only FFWStats and FFWTeamSync. Keep UE4SS if other mods need it. Stats does not modify permanent game progression.
