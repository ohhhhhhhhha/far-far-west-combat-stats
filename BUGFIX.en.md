# 0.1.0-beta.3 validation and limits

This candidate changes the Lua statistics component. The native FFWTeamSync binary is unchanged.

## Added in beta.3: native clock context

The original B08 minidump confirms that GetTimeSeconds received an inaccessible WorldContext: the first native argument equals the read-fault address. This identifies the native function and argument failure, not the originating Lua instance.

Both game-time and real-time calls now reselect a unique local controller and require its valid world immediately before the native call. Event actors and managers are never passed as WorldContext. OpeningCredits/title worlds and missing worlds are skipped. Mission start rechecks the saved manager-world identity and callback generation after roster refresh and clock acquisition; a retired manager cannot start a run in a replacement lobby world. Ten boundary regressions fail against beta.2 and pass with these changes, including an explicit inaccessible-context sentinel. The native boundary is simulated; no native AV is deliberately executed.

## Reproduced defects and changes

- F8 could use the first remote PlayerController or assume the Joker UI class/font had already loaded. It now selects a unique local controller and loads its own resources. An empty panel remains available when roster, Steam identity or storage is not ready.
- A failed initial boot-epoch write or a bridge arriving after Lua startup could leave collection waiting indefinitely. These conditions are retried; the panel reports the specific missing condition. An unsaved epoch is never published.
- PlayerState identity was cached before its native ID settled. Live PlayerState identity is now read again; conflicting host flags and overlapping local controllers revoke the old binding. A native Steam ID must still match the current Unreal roster.
- Travel invalidates callback generations before parameters are unwrapped, clears world-bound caches and abandons retired UI objects. Current-world cleanup handles Lua binding failures individually. Input queued before travel or shutdown cannot recreate a retired panel.
- Incomplete snapshots were replaced with newer sequences before missing fragments could arrive. Each peer now retains its own immutable frame until acknowledged, retries missing delivery, and repeats a lost snapshot ACK. One blocked peer does not prevent other peers receiving new data.
- Viewport/DPI changes invalidate the render cache. Small windows scale a usable design canvas; a zero-sized/minimized viewport does not create widgets. Scheduling uses observed world real-time deltas while available, avoiding a freeze after a system-clock correction.
- Runtime archives now include the shared game-specific ProcessLocalScriptFunction signature. Install the official framework and this signature before the first launch.

## Repeatable evidence

The isolated Lua 5.4 suite runs 27 test files, including 43 focused new scenarios. Failures were reproduced on the saved original source before the fixes. Engine, native transport and thread scheduling are boundary doubles; the entry point, adapter, panel model, renderer, Session, Sync, Protocol, Stats and Store execute production code.

The multi-client suite uses a host and two guests with independent clocks, profiles and queues. It covers distinct per-machine world keys, late join, packet loss, duplicate/reordered fragments, blocked peers, guest process restart, same-world host component restart, a host process observing a different world, reconnect, new missions, return to lobby, revoked roster admission, forged sender IDs and partially installed teams. Hand-checked totals converge without duplicate credit. A non-Steam/EOS ID is not converted into a fabricated Steam account.

Static inspection resolves all 28 UE4SS imports and nine Steam flat-API symbols against the installed pinned 1181 binaries. The official 1181-to-1183 source comparison changes no public headers or submodules. This is useful source-level evidence; an 1183 native bridge binary run has not been performed.

## Still requiring live verification

- F8 and input handoff in the actual game after the new fixes, including seamless travel and returning to the title screen.
- Multiple real Steam accounts: native message delivery, complete event coverage and the native C++ ABI on each loader build.
- The original reported GPU and native reflection/access violations. Lua protected calls do not catch C++ access violations, and this candidate does not claim those crashes are eliminated.
- An actual LAN/non-Steam roster that has no verifiable Steam mapping. LAN flags alone neither establish nor disprove Steam identity. The panel explains the unavailable mapping and does not send to guessed accounts.
- Windows systems whose Lua narrow-file APIs cannot open a non-ASCII installation path. Node extraction into paths containing spaces/Chinese characters and Lua virtual-path tests are not native Windows encoding validation. Use an ASCII-named Steam library path if framework/script loading fails there; do not change the system locale or registry for this Mod.

The original diagnostic directories and Win64 archive arrived after beta.2 was frozen. The received main/adapter/config/sync sources match the beta.1 baseline, and the bridge DLL matches the distributed binary. The 1183 x64 DLL resolves all 28 bridge imports. The logs contain the combined wait message but no separate local/native/roster/host/epoch values, so the exact B06 gate still needs fresh runtime diagnostics. These files were inspected locally and are not redistributed.
