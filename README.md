# Far Far West Combat Stats

[简体中文](README.zh-CN.md) · [Downloads](https://github.com/ohhhhhhhhha/far-far-west-combat-stats/releases)

Combat statistics, a configurable in-game HUD and a team contribution ranking for **Far Far West** on Windows (Steam). This repository contains the statistics Mod and its native synchronization bridge.

**Version 0.1.0-beta.3 — beta.** Includes the beta.2 startup/synchronization fixes plus verified native clock contexts: time reads use a freshly selected local controller and valid world, never an event actor. The new fixes pass the isolated 27-file suite and three-client simulation; they have not yet received a new in-game acceptance run. [Validation and remaining limits](BUGFIX.en.md).

## Install

1. Fully exit and back up Mod Data. Install **UE4SS-FarFarWest 3.0.1.1183 Frostburn / UE5.8** from [Nexus mods/2](https://www.nexusmods.com/farfarwest/mods/2?tab=files) into FarFarWest/Binaries/Win64 under Steam’s game root.
2. Extract Stats beta.3 to a temporary folder. **Copy only FFWStats and FFWTeamSync from GameRoot/FarFarWest/Binaries/Win64/ue4ss/Mods into installed Mods**, preserving Data.
3. **Do not merge old beta.3 GameRoot wholesale.** Its fallback signature must not overwrite the Nexus signature. Preserve all framework files and settings.
4. Check both enabled.txt markers and component files, restart, then press F8.

[Complete installation, migration and rollback guide](INSTALL.en.md). Published ZIP attachments are unchanged. **Beta.3 does not provide LAN/IP transport.** A new LAN component is being developed and is not in the current download.

## Controls and display

- **F8** opens/closes the detailed panel. Click tab titles, metric headings, paging controls and Close with the mouse.
- **Page Up / Page Down** change metrics; **Home / End** change scope. Use mouse paging: beta.3 F10 conflicts with Nexus ConsoleEnabler. See the installation guide for an optional Config.lua rebind.
- **HUD options** in the panel select HUD values, breakdowns and the leaderboard. Choices are saved locally and survive restarts.
- The compact HUD shows your own statistics and, optionally, the top four recorded team contributions. It does not take mouse focus during play.
- English and Simplified Chinese follow the game language. Measurements use two decimals; event counts remain integers.

## What is measured

Damage and its source, incoming damage and HP/shield breakdown, kills/elite kills/boss kills/assists, effective healing, shields granted, hits/critical hits, ammunition/reloads, survival, revives and deaths have dedicated views when events are available. Unobserved metrics remain unavailable.

Damage uses the attack settlement amount, including overkill. DPS uses a **five-second rolling damage window**, sampled once per second. The HUD's **30s peak** is the highest sampled rolling DPS in the last 30 seconds; **mission peak** is the highest sample this mission. The detailed panel retains rolling/average DPS plots and adds a dedicated **Team contribution** page.

Primary weapon, secondary weapon, spell, melee and damage-over-time classification uses observed settlement metadata and a verified item catalog. Unresolved events remain unclassified. Existing historical unclassified totals cannot be reconstructed. In a solo mission, the team damage share reads 100%; this does not assert complete event coverage.

## Contribution score

Each available category allocates its weight in proportion to the recorded team total. Positive observed categories activate their weights; the active weights are normalized to 100%.

| Category | Weight |
| --- | ---: |
| Damage | 40 |
| Kills | 10 |
| Elite kills | 3 |
| Boss kills | 5 |
| Assists | 2 |
| Effective healing to teammates | 12 |
| Effective self healing | 3 |
| Shields granted | 5 |
| Revives | 15 |
| Alive-time fraction since joining | 5 |

No score is awarded simply for taking damage. Missing or stale coverage makes results provisional. Unknown players are not assigned invented scores. These weights are a reference for the recorded run, not a definitive assessment of player skill.

## Saved data and multiplayer

The latest mission remains available until a new mission begins. The Mod creates local files under `Mods/FFWStats/Data`, including the mission snapshot and `hud-settings.json`. Mission records can contain player names and Steam IDs. They are **not included in this download or source repository**. Keep this folder when updating; do not attach it publicly without removing personal information.

The included `FFWTeamSync` bridge uses the game's Steam networking for synchronized statistics. Every participant whose data should be synchronized needs both components. There is no web telemetry endpoint. Full guest-side team coverage remains pending live multiplayer validation in this beta.

## Source and attribution

[Development](DEVELOPMENT.md) · [Native build dependencies](NATIVE-BUILD.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

Original code is MIT licensed. Game-derived text/identifiers and third-party dependencies retain their original rights; see [notices](THIRD-PARTY-NOTICES.md). UE4SS is the runtime framework. BepInEx is not used.
