# Changes: 0.2.0-beta.1

Adds real native LAN/IP transmission alongside Steam, using replicated PlayerId plus a random room namespace and explicit per-peer pairing. F8 gains a bilingual connection page. New room identity prevents restoring another room's queues when numeric IDs are reused. Lobby handshakes run independently of mission creation; normal map travel can reconnect without replacing pairing. Returning to title clears pairing.

The native bridge now retains legitimate queued messages when an unrelated unauthenticated socket fails its proof, and when replacing a disconnected socket. Explicit close/revoke/stop retain their admission-clearing behavior. A real socket regression failed before this fix and passed afterward.

The runtime contains no framework replacement. Follow the Nexus game-specific installation guide; default Stats F10 paging is disabled to avoid ConsoleEnabler. Existing HUD choices and last-mission Data are preserved.

The beta.3 clock-context safeguards remain. Local single-instance LAN host listening, mission damage data and retained saloon results have been confirmed in game. Two-PC LAN event coverage remains pending.

Winsock initialization is now lazy in explicit configure. LAN ownership belongs to the runtime Mod object rather than a DLL global; explicit stop and normal owner disposal balance cleanup. The lifecycle regression fails on eager construction and passes after this change.
