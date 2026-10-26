package.path = "FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;" .. package.path
local T = require("stats_testlib")
local Sync, Stats, Json = require("Sync"), require("Stats"), require("Json")
local H, C, X = "76561198000000001", "76561198000000002", "76561198000000003"
local function copy(x) return Json.decode(Json.encode(x)) end
local function bus(limit)
    local b = {queues = {[H] = {}, [C] = {}, [X] = {}}, sent = {}, closed = {}}
    function b:endpoint(id)
        return {apiVersion = 1, channel = 4605527, maxPayload = limit or 262144,
            localSteamId = function() return id end,
            send = function(peer, channel, bytes)
                assert(channel == 4605527 and #bytes <= (limit or 262144), "native payload contract violated")
                self.sent[#self.sent + 1] = {sender = id, peer = peer, bytes = bytes, packet = Json.decode(bytes)}
                self.queues[peer][#self.queues[peer] + 1] = {sender = id, bytes = bytes}
                return true
            end,
            poll = function(channel)
                assert(channel == 4605527)
                local m = table.remove(self.queues[id], 1)
                if m then return m.sender, m.bytes end
            end,
            close = function(peer) self.closed[#self.closed + 1] = {id, peer}; return true end}
    end
    function b:inject(to, sender, packet) self.queues[to][#self.queues[to] + 1] = {sender = sender, bytes = Json.encode(packet)} end
    return b
end
local roster = {[H] = {playerId = "host"}, [C] = {playerId = "client"}, [X] = {playerId = "missing"}}
local function core(session, longName)
    local s = Stats.new(session or "A")
    for _, p in ipairs({"host", "client", "missing"}) do
        assert(s:apply({id = "join-" .. p, sessionId = session or "A", kind = "player_join", time = 0,
            sourcePlayerId = p, name = p == "host" and longName or p}))
    end
    return s
end
local function pair(options)
    options = options or {}
    local b, s = bus(options.limit), core("A", options.longName)
    local activeRoster = options.roster or roster
    local host = assert(Sync.new({transport = b:endpoint(H), localId = H, hostSteamId = H, sessionId = "A",
        epoch = 10, generation = 1, roster = activeRoster, stats = s}))
    local client = assert(Sync.new({transport = b:endpoint(C), localId = C, hostSteamId = H,
        epoch = 20, roster = activeRoster, onSession = options.onSession}))
    return b, s, host, client
end
local function cycle(host, client, now, mission)
    host:tick(now, mission); client:tick(now, mission); host:tick(now, mission); client:tick(now, mission)
end

T.test("unknown guest session binds only through trusted host hello and snapshots replace cumulatives", function()
    local bindings = {}
    local b, s, host, client = pair({onSession = function(session) bindings[#bindings + 1] = session end})
    T.eq(client:submit({id = "early", kind = "ammo", amount = 3}), false)
    b:inject(C, X, {wireVersion = 1, kind = "hello", senderId = H, authorityId = H,
        epoch = 999, generation = 99, sessionId = "spoof"})
    cycle(host, client, 0, 0)
    T.eq(client:status().sessionId, "A"); T.eq(bindings[1], "A"); T.eq(#bindings, 1)
    assert(s:apply({id = "d1", sessionId = "A", kind = "damage", sourcePlayerId = "host", targetId = "enemy", amount = 100, sourceCategory = "primary", time = 1}))
    cycle(host, client, 5, 5)
    T.eq(client:snapshot().players.host.metrics.damage, 100)
    cycle(host, client, 10, 10)
    T.eq(client:snapshot().players.host.metrics.damage, 100)
    T.eq(host:status().peers[X].state, "unavailable")
end)

T.test("host normalizes local events to receive clock and deduplicates replay without accepting damage", function()
    local b, s, host, client = pair()
    cycle(host, client, 0, 0)
    T.eq(client:submit({id = "shot", kind = "shot", attackId = "a", accuracyMode = "ordinary", time = 999}), true)
    T.eq(client:submit({id = "shot", kind = "shot", attackId = "a", accuracyMode = "ordinary", time = 999}), false)
    T.eq(client:submit({id = "hit", kind = "hit", attackId = "a", validTarget = true, time = -100}), true)
    T.eq(client:submit({id = "ammo", kind = "ammo", amount = 2}), true)
    T.eq(client:submit({id = "reload", kind = "reload"}), true)
    T.eq(client:submit({id = "fake-damage", kind = "damage", amount = 999, targetId = "e", sourceCategory = "spell"}), false)
    cycle(host, client, 1, 7)
    local view = s:snapshot(7)
    T.eq(view.players.client.metrics.shots, 1); T.eq(view.players.client.metrics.hits, 1)
    T.eq(view.players.client.metrics.ammo, 2); T.eq(view.players.client.metrics.reloads, 1)
    T.eq(view.players.client.metrics.damage, nil); T.eq(view.time, 7)
    local events
    for _, m in ipairs(b.sent) do if m.sender == C and m.packet.kind == "events" then events = m.packet end end
    assert(events); b:inject(H, C, events); host:tick(2, 8)
    T.eq(s:snapshot(8).players.client.metrics.ammo, 2)
    T.eq(client:status().pendingEvents, 0)
end)

T.test("large snapshots are fragmented below native payload limit and incomplete transfers never replace view", function()
    local b, s, host, client = pair({limit = 4096, longName = string.rep("长姓名", 3000)})
    cycle(host, client, 0, 0)
    T.eq(client:snapshot(), nil)
    for i = 1, 100 do cycle(host, client, i / 10, 0) end
    local snapshot = assert(client:snapshot())
    T.eq(snapshot.players.host.name, string.rep("长姓名", 3000))
    local fragments = 0
    for _, m in ipairs(b.sent) do if m.peer == C and m.packet.kind == "fragment" then fragments = fragments + 1; assert(#m.bytes <= 4096) end end
    assert(fragments > 1)
end)

T.test("new mission binding cannot roll back through delayed hellos and early local events stay gated", function()
    local changes = {}
    local b, _, host, client = pair({onSession = function(id, prior) changes[#changes + 1] = {id, prior} end})
    cycle(host, client, 0, 0)
    local oldHello
    for _, m in ipairs(b.sent) do if m.sender == H and m.packet.kind == "hello" then oldHello = copy(m.packet) end end
    client:awaitNextSession()
    b:inject(C, H, oldHello); client:tick(1, 0)
    T.eq(client:status().bound, false)
    T.eq(client:submit({id = "early-next", kind = "ammo", amount = 5}), false)
    local nextHost = Sync.new({transport = b:endpoint(H), localId = H, hostSteamId = H, sessionId = "B",
        epoch = 10, generation = 2, roster = roster, stats = core("B")})
    cycle(nextHost, client, 2, 0)
    T.eq(client:status().sessionId, "B"); T.eq(client:status().bound, true)
    b:inject(C, H, oldHello); client:tick(3, 0)
    T.eq(client:status().sessionId, "B"); T.eq(changes[2][2].oldSessionId, "A")
    T.eq(client:submit({id = "new-ammo", kind = "ammo", amount = 1}), true)
end)

T.test("waiting for the next mission cannot be satisfied by a reboot of the previous mission", function()
    local changes = {}
    local b, _, host, client = pair({onSession = function(id) changes[#changes + 1] = id end})
    cycle(host, client, 0, 0)
    client:awaitNextSession()
    b:inject(C, H, {wireVersion = 1, kind = "hello", senderId = H, authorityId = H,
        sessionId = "A", epoch = 11, authorityEpoch = 11, generation = 1})
    client:tick(1, 0)
    T.eq(client:status().bound, false)
    T.eq(client:status().sessionId, "A")
    T.eq(client:submit({id = "new-mission-ammo", kind = "ammo", amount = 4}), false)
    T.eq(#changes, 1)
    -- A changed counter alone is not a changed task, including generation.
    b:inject(C, H, {wireVersion = 1, kind = "hello", senderId = H, authorityId = H,
        sessionId = "A", epoch = 11, authorityEpoch = 11, generation = 2})
    client:tick(2, 0)
    T.eq(client:status().bound, false)
    b:inject(C, H, {wireVersion = 1, kind = "hello", senderId = H, authorityId = H,
        sessionId = "B", epoch = 11, authorityEpoch = 11, generation = 3})
    client:tick(3, 0)
    T.eq(client:status().bound, true); T.eq(client:status().sessionId, "B")
    T.eq(client:submit({id = "new-mission-ammo", kind = "ammo", amount = 4}), true)
    T.eq(#changes, 2); T.eq(changes[2], "B")
end)

T.test("paired checkpoints preserve totals and event dedup across both component restarts", function()
    local b, _, host, client = pair()
    cycle(host, client, 0, 0)
    assert(client:submit({id = "ammo-before-loss", kind = "ammo", amount = 2}))
    client:tick(1, 7); host:tick(1, 7)
    b.queues[C] = {} -- simulate missing ACK; pending event must be replayed after restart
    local hostSave, clientSave = copy(host:checkpoint()), copy(client:checkpoint())
    local restored = assert(Stats.restore(hostSave.hostSnapshot))
    host = Sync.new({transport = b:endpoint(H), localId = H, hostSteamId = H, sessionId = "A",
        epoch = 11, generation = 1, roster = roster, stats = restored, resume = hostSave})
    client = Sync.new({transport = b:endpoint(C), localId = C, hostSteamId = H,
        epoch = 21, roster = roster, resume = clientSave})
    cycle(host, client, 0, 7); cycle(host, client, 1, 7)
    T.eq(restored:snapshot(7).players.client.metrics.ammo, 2)
    T.eq(client:status().pendingEvents, 0)
    assert(client:submit({id = "ammo-after-resume", kind = "ammo", amount = 3}))
    cycle(host, client, 2, 8)
    T.eq(restored:snapshot(8).players.client.metrics.ammo, 5)
end)

T.test("authority reboot discards incomplete older epoch fragments before accepting new sequence one", function()
    local b, _, host, client = pair()
    cycle(host, client, 0, 0)
    b:inject(C, H, {wireVersion = 1, kind = "fragment", senderId = H, authorityId = H, sessionId = "A",
        epoch = 10, authorityEpoch = 10, generation = 1, sequence = 100, index = 1, count = 2, totalBytes = 2, data = "{"})
    client:tick(1, 0)
    local save = host:checkpoint()
    local rebooted = Sync.new({transport = b:endpoint(H), localId = H, hostSteamId = H, sessionId = "A",
        epoch = 11, generation = 1, roster = roster, stats = assert(Stats.restore(save.hostSnapshot)), resume = save})
    cycle(rebooted, client, 2, 0)
    T.eq(client:checkpoint().receiveSequence, 1)
end)

T.test("checkpoint samples current core clock after authoritative events between ticks", function()
    local _, s, host, client = pair(); cycle(host, client, 0, 0)
    assert(s:apply({id = "new-time", kind = "ammo", sessionId = "A", time = 4, sourcePlayerId = "host", amount = 1}))
    T.eq(host:checkpoint().hostSnapshot.time, 4)
end)

T.test("normal rapid fire event traffic drains without a sixteen-events-per-second backlog", function()
    local _, s, host, client = pair(); cycle(host, client, 0, 0)
    for i = 1, 80 do
        assert(client:submit({id = "shot-" .. i, kind = "shot", attackId = "attack-" .. i, accuracyMode = "ordinary"}))
        assert(client:submit({id = "ammo-" .. i, kind = "ammo", amount = 1}))
    end
    for i = 1, 6 do cycle(host, client, i * 0.25, i * 0.25) end
    T.eq(client:status().pendingEvents, 0)
    T.eq(s:snapshot(1.5).players.client.metrics.shots, 80)
    T.eq(s:snapshot(1.5).players.client.metrics.ammo, 80)
end)

T.test("same epoch reconnect retains snapshot barrier and paused mission clock does not advance", function()
    local b, _, host, client = pair(); cycle(host, client, 0, 0)
    cycle(host, client, 5, 0)
    local save = copy(client:checkpoint())
    T.eq(save.receiveSequence, 2)
    client = Sync.new({transport = b:endpoint(C), localId = C, hostSteamId = H, epoch = 20, roster = roster, resume = save})
    for _, m in ipairs(b.sent) do
        if m.sender == H and m.peer == C and (m.packet.kind == "hello" or m.packet.kind == "fragment") then b:inject(C, H, m.packet) end
    end
    client:tick(0, 0)
    T.eq(client:checkpoint().receiveSequence, 2)
    T.eq(client:snapshot().time, 0); T.eq(#client:snapshot().history, 1)
end)

T.test("missing components and removed peers remain explicit without deleting cumulative data", function()
    local b, s, host, client = pair(); cycle(host, client, 0, 0)
    assert(client:submit({id = "ammo", kind = "ammo", amount = 3})); cycle(host, client, 1, 1)
    host:tick(20, 20)
    T.eq(host:status().peers[C].state, "unavailable")
    T.eq(host:status().peers[C].eventCoverage.ammo, "unavailable")
    host:setRoster({[H] = "host", [X] = "missing"})
    T.eq(b.closed[#b.closed][2], C)
    T.eq(host:status().peers[C].state, "unavailable")
    assert(host:finish()); T.eq(host:finishStatus().peers[C].state, "missing")
    T.eq(s:snapshot(20).players.client.metrics.ammo, 3)
end)

T.test("additional local-only kinds require host delegation and authoritative damage remains forbidden", function()
    local b, s, host, client = pair()
    local delegated = copy(roster)
    delegated[C].localEventKinds = {incoming = true, damage = true}
    host:setRoster(delegated); client:setRoster(delegated)
    cycle(host, client, 0, 0)
    T.eq(client:submit({id = "incoming", kind = "incoming", hpLoss = 5, shieldAbsorbed = 4, sourceCategory = "enemy"}), true)
    T.eq(client:submit({id = "impersonation", kind = "incoming", targetPlayerId = "host", hpLoss = 100, shieldAbsorbed = 0, sourceCategory = "enemy"}), false)
    T.eq(client:submit({id = "damage", kind = "damage", sourcePlayerId = "client", targetId = "e", amount = 100, sourceCategory = "primary"}), false)
    cycle(host, client, 1, 2)
    T.eq(s:snapshot(2).players.client.metrics.incomingDamage, 9)
    T.eq(s:snapshot(2).players.host.metrics.incomingDamage, nil)
    T.eq(s:snapshot(2).players.client.metrics.damage, nil)
end)

T.test("host restores an older save point without stalling guest stream or reusing original event IDs", function()
    local b, _, host, client = pair(); cycle(host, client, 0, 0)
    assert(client:submit({id = "saved-one", kind = "ammo", amount = 2})); cycle(host, client, 1, 1)
    assert(client:submit({id = "saved-two", kind = "ammo", amount = 3})); cycle(host, client, 2, 2)
    local saved = copy(host:checkpoint())
    assert(client:submit({id = "after-save-acked", kind = "ammo", amount = 4})); cycle(host, client, 3, 3)
    assert(client:submit({id = "after-save-pending", kind = "ammo", amount = 5}))
    local restored = assert(Stats.restore(saved.hostSnapshot))
    host = Sync.new({transport = b:endpoint(H), localId = H, hostSteamId = H, sessionId = "A",
        epoch = 11, generation = 1, roster = roster, stats = restored, resume = saved})
    cycle(host, client, 4, 4); cycle(host, client, 4.5, 4.5)
    -- The previously acknowledged, unsaved 4 is outside the recovery point.
    -- The unacknowledged 5 must still be delivered, starting a fresh stream.
    T.eq(restored:snapshot(4.5).players.client.metrics.ammo, 10)
    T.eq(client:status().pendingEvents, 0)
    assert(client:submit({id = "new-after-restore", kind = "ammo", amount = 6}))
    cycle(host, client, 5, 5)
    T.eq(restored:snapshot(5).players.client.metrics.ammo, 16)
end)

T.test("end barrier waits for the guest final watermark then confirms the complete final snapshot", function()
    local b, s, host, client = pair({roster = {[H] = "host", [C] = "client"}})
    cycle(host, client, 0, 0)
    for i = 1, 150 do assert(client:submit({id = "last-ammo-" .. i, kind = "ammo", amount = 1})) end
    assert(host:finish()); assert(client:finish())
    host:tick(0.1, 5)
    local pending = host:finishStatus()
    T.eq(pending.ready, false); T.eq(pending.peers[C].state, "waiting_events")
    T.eq(pending.peers[C].lastSequence, 150); T.eq(pending.peers[C].acceptedThrough, 128)
    T.eq(client:submit({id = "late-after-finish", kind = "ammo", amount = 999}), false)
    cycle(host, client, 0.5, 5)
    T.eq(host:finishStatus().ready, true); T.eq(client:finishStatus().acknowledged, true)
    T.eq(s:snapshot(5).players.client.metrics.ammo, 150)
    assert(s:apply({id = "end", kind = "mission_end", sessionId = "A", time = 5}))
    assert(host:forceSnapshot())
    cycle(host, client, 0.75, 5)
    T.eq(client:snapshot().status, "ended"); T.eq(client:finishStatus().finalSnapshotReceived, true)
    T.eq(host:finishStatus().allSnapshotsAcknowledged, true)
end)

T.test("end timeout explicitly retains missing peer coverage and does not invent a zero report", function()
    local _, s, host, client = pair(); cycle(host, client, 0, 0)
    assert(host:finish()); assert(client:finish()); cycle(host, client, 0.25, 0)
    T.eq(host:finishStatus().peers[X].state, "missing")
    T.eq(host:finishStatus().peers[X].lastSequence, nil)
    T.eq(host:finishStatus().ready, false); T.eq(host:finishStatus().mayFinalize, false)
    host:tick(15.25, 0)
    T.eq(host:finishStatus().timedOut, true); T.eq(host:finishStatus().mayFinalize, true)
    T.eq(host:finishStatus().partial, true)
    T.eq(s:snapshot(0).players.missing.metrics.ammo, nil)
end)

T.test("a restarted guest must receive the final snapshot itself before its delivery is acknowledged", function()
    local b, s, host, client = pair({roster = {[H] = "host", [C] = "client"}})
    cycle(host, client, 0, 0)
    local activeCheckpoint = copy(client:checkpoint())
    assert(host:finish()); assert(client:finish()); cycle(host, client, 0.25, 1)
    assert(s:apply({id = "end", kind = "mission_end", sessionId = "A", time = 1}))
    assert(host:forceSnapshot()); cycle(host, client, 0.5, 1)
    T.eq(host:finishStatus().allSnapshotsAcknowledged, true)

    client = Sync.new({transport = b:endpoint(C), localId = C, hostSteamId = H, epoch = 21,
        roster = {[H] = "host", [C] = "client"}, resume = activeCheckpoint})
    client:tick(0.75, 1); host:tick(0.75, 1)
    -- Delay the new snapshot while allowing the new incarnation to handshake.
    local held, controls = {}, {}
    for _, message in ipairs(b.queues[C]) do
        if Json.decode(message.bytes).kind == "fragment" then held[#held + 1] = message
        else controls[#controls + 1] = message end
    end
    b.queues[C] = controls
    client:tick(1, 1); assert(client:finish()); host:tick(1, 1)
    T.eq(client:snapshot().status, "active")
    T.eq(client:finishStatus().finalSnapshotReceived, false)
    T.eq(host:finishStatus().ready, true)
    T.eq(host:finishStatus().allSnapshotsAcknowledged, false)
    assert(#held > 0, "new incarnation must receive a snapshot without waiting for the five-second cadence")
    for _, message in ipairs(held) do b.queues[C][#b.queues[C] + 1] = message end
    client:tick(1.25, 1); host:tick(1.25, 1)
    T.eq(client:snapshot().status, "ended")
    T.eq(host:finishStatus().allSnapshotsAcknowledged, true)
end)

T.finish()
