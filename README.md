# Far Far West Combat Stats

[Download this beta](https://github.com/ohhhhhhhhha/far-far-west-combat-stats/releases/tag/v0.2.0-beta.1) · [中文说明](README.zh-CN.md) · [Detailed installation](INSTALL.en.md)

An English/Chinese statistics panel and compact HUD for Far Far West. F8 opens the mouse-operated panel; HUD options select the fields shown during play. Metrics include overkill-inclusive damage, damage sources, damage taken, DPS peaks, kills, healing, ammo, survival and team contribution. Unobserved values remain unavailable and partial coverage is marked.

**0.2.0-beta.1 is a beta release.** Local single-instance LAN host listening, mission damage data and retained saloon results have been confirmed in game. Two-PC LAN event coverage remains pending. It adds paired LAN/IP synchronization alongside the existing Steam path. The host and each guest install both FFWStats and FFWTeamSync. F8 Connection provides host port, guest IPv4/code entry and per-PlayerId pairing. Real native loopback tests use production Session/Sync/Protocol/Store, including loss, reconnect, travel, new rooms and independent saves.

## Install

Use [UE4SS for FarFarWest on Nexus](https://www.nexusmods.com/farfarwest/mods/2?tab=files), player main file 3.0.1.1183 Frostburn / UE5.8. Copy that framework into FarFarWest/Binaries/Win64 under Steam's game root. Then merge the contents of this Mod's GameRoot into the Steam game root. Preserve Nexus signatures/settings and existing Mod Data. See the [step-by-step guide](INSTALL.en.md) for both-side LAN setup, connection checks, upgrades and rollback.

F8 toggles details. Click headings/tabs and paging buttons. PgUp/PgDn selects metrics; Home/End selects scope. Stats leaves F10 to the Nexus ConsoleEnabler. The current mission is saved automatically and remains available until the next mission starts.

The team contribution ranking is a weighted reference derived from recorded events, not an objective rating of player skill. Actual two-PC gameplay event coverage still needs acceptance. The previously published beta.3 is Steam-dependent; installing it alone does not provide LAN/IP transport.

## Source and distribution

This project contains the statistics Mod and synchronization bridge only. It has no trainer, card spawning, personal saves, captured player data or bundled UE4SS runtime. Source and runtime ZIPs are separate. See [development](DEVELOPMENT.md), [native build](NATIVE-BUILD.md), [license](LICENSE) and [third-party notices](THIRD-PARTY-NOTICES.md).
