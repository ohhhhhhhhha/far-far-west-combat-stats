# Changelog

## 0.2.0-beta.1 — beta

- Native paired LAN/IP transport and bilingual F8 Connection settings.
- Room-scoped replicated PlayerId; no Steam requirement on the LAN path.
- Real socket loss/reconnect/travel/save coverage and unauthenticated-inbox regression.
- Nexus2 framework installation contract; no framework/signature payload.
- Default F10 left to ConsoleEnabler; mouse paging retained.

## 0.1.0-beta.3 — 2026-10-29

- Native clock calls use a freshly selected local controller with a valid world; event actors/managers are never forwarded.
- Skip OpeningCredits/title/missing worlds and recheck manager world/generation before mission start.
- Ten clock-context regressions reproduced on beta.2; 27-file isolated suite. Original B08 dump confirms an inaccessible WorldContext argument, while live-game crash verification remains pending.
- Original diagnostic files and the 1183 DLL are now available for local analysis; no raw logs, dumps or player data are redistributed.

## 0.1.0-beta.2 — 2026-10-29

- Verify local UI ownership and load panel resources without depending on another Mod.
- Retry unavailable bridge/epoch initialization and expose distinct identity diagnostics.
- Retire old-world callbacks and controls before rebuilding; cancel queued input on travel/stop.
- Retain and retry immutable snapshots independently per peer, including lost ACK recovery.
- Reflow on resolution/DPI changes, handle minimized windows and use measured real-time scheduling.
- Include the shared game startup signature and its original MIT notice.
- 26 Lua test files; 33 focused scenarios, including host plus two guests. New live acceptance and full native networking remain pending.

## 0.1.0-beta.1 — 2026-10-27

First independent statistics release, extracted from the local FFWTools project.

- F8 metric tabs, clickable subheadings, mouse navigation and game-styled panel.
- Configurable HUD with persistent choices, 30-second/mission peak DPS and team contribution ranking.
- Source classification from settlement metadata and the item catalog; solo damage share displays 100%.
- Two-decimal measurements, corrected panel text alignment and saved last-mission statistics.
- Includes the pinned UE4SS native Steam bridge. Full multiplayer collection validation remains pending.

Latest solo acceptance covered classification, solo percentage, text layout and preference persistence.
