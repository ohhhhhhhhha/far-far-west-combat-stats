# Changelog

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
