# Development

Source lives under FFWTools/src/FFWStats and FFWTools/src/FFWTeamSync. The statistics repository does not include the trainer or card tools.

GameAdapter reads confirmed engine fields and settlement events. main.lua owns the existing 250ms game-thread loop, 2-second roster observation, 1-second view refresh and periodic saves. Connection owns explicit LAN setup and independently pumps handshakes in the saloon. It does not consume application packets. The production Session/Sync/Protocol/Store stack owns mission boundaries, authoritative snapshots, acknowledgements, deduplication, retries and paired save/checkpoint replacement.

LAN peers use lan:<random room>:<replicated PlayerId>. Per-peer random pairing keys bind mutual challenge authentication to the actual roster ID; sequenced HMAC frames reject alteration and replay. Keys remain in memory. Ordinary socket failures retain already authenticated inbox messages; explicit close/revoke/stop remove queued data according to admission/lifecycle intent. Titles stop the room, normal map travel suspends roster admission, and a fresh room namespace prevents old checkpoints from claiming reused numeric IDs.

The existing Steam facade is retained. Sync accepts localPlayerId or the legacy localSteamId method; IDs must still agree with the current game roster. Display names and row positions are never identity evidence. Unavailable gameplay metrics are never estimated.

[Native build](NATIVE-BUILD.md) describes the tested no-shell API and Visual Studio routes. run-tests.mjs exports runTests for isolated Lua checks; package.mjs exports buildRelease with an explicit package manifest. No test opens live Mod Data or launches another game. Runtime installation is tested by first staging the actual Nexus dependency, then merging the Mod and verifying all framework files and a seeded local Data file remain unchanged.

Build/test results are specific to their boundaries. Changes to engine bindings still require a single manual game acceptance pass; native loopback success is not a two-PC gameplay claim.
