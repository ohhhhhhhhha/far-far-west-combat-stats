package.path = "FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;" .. package.path
local T = require("stats_testlib")
local Stats, Json = require("Stats"), require("Json")
local haveProtocol, Protocol = pcall(require, "Protocol")
local function core()
    local s = Stats.new("A")
    assert(s:apply({id = "host", sessionId = "A", kind = "player_join", time = 0, sourcePlayerId = "host"}))
    assert(s:apply({id = "guest", sessionId = "A", kind = "player_join", time = 0, sourcePlayerId = "guest"}))
    assert(s:apply({id = "d1", sessionId = "A", kind = "damage", time = 1, sourcePlayerId = "host", targetId = "enemy", sourceCategory = "primary", amount = 100}))
    return s
end
local function protocols(epoch)
    T.eq(haveProtocol, true, "protocol available")
    return Protocol.sender("A", "host", epoch or 1), Protocol.receiver("A", "host", epoch or 1)
end
local function wire(packet) return Json.decode(Json.encode(packet)) end

-- Catches treating cumulative snapshots as additive deltas and loses to real JSON serialization bugs.
T.test("guest replaces cumulative snapshots and agrees with the host after serialization", function()
    local send, receive = protocols()
    local s = core()
    local first = send:packet(s:snapshot(2))
    T.eq(receive:accept(wire(first)), true)
    assert(s:apply({id = "d2", sessionId = "A", kind = "damage", time = 3, sourcePlayerId = "host", targetId = "enemy2", sourceCategory = "spell", amount = 50}))
    local host = s:snapshot(4)
    local second = send:packet(host)
    T.eq(receive:accept(wire(second)), true)
    local guest = receive:snapshot()
    T.eq(guest.players.host.metrics.damage, 150); T.eq(guest.players.host.metrics.averageDps, 37.5)
    T.eq(guest.history[1].players.host.damage, 100); T.eq(guest.history[2].players.host.damage, 150)
    T.eq(guest.players.guest.metrics.damage, nil); T.eq(guest.players.guest.coverage.damage.status, "unavailable")
    T.eq(receive:accept(first), false); T.eq(receive:accept(second), false)
    T.eq(receive:snapshot().players.host.metrics.damage, 150)
end)

-- Catches accepting another mission/authority or consuming its sequence barrier.
T.test("wrong session wrong sender and malformed snapshots cannot replace current data", function()
    local send, receive = protocols()
    local packet = send:packet(core():snapshot(2))
    local wrong = wire(packet); wrong.sessionId = "B"; wrong.sequence = 99
    T.eq(receive:accept(wrong), false)
    wrong = wire(packet); wrong.senderId = "peer"; wrong.sequence = 99
    T.eq(receive:accept(wrong), false)
    wrong = wire(packet); wrong.snapshot.state.players.host.totals.damage = nil; wrong.sequence = 99
    T.eq(receive:accept(wrong), false)
    T.eq(receive:accept(packet), true)
    T.eq(receive:snapshot().players.host.metrics.damage, 100)
end)

-- Catches automatic epoch switching from reordered packets and sequence reset on same-epoch reconnect.
T.test("trusted reconnect advances epoch without accepting delayed old packets", function()
    local send, receive = protocols()
    local snapshot = core():snapshot(2)
    local old = send:packet(snapshot)
    T.eq(receive:accept(old), true)
    T.eq(receive:reconnect(1), true); T.eq(receive:accept(old), false)
    local nextSender = Protocol.sender("A", "host", 2)
    local current = nextSender:packet(snapshot)
    T.eq(receive:accept(current), false)
    T.eq(receive:reconnect(2), true); T.eq(receive:accept(current), true)
    old.sequence = 100
    T.eq(receive:accept(old), false); T.eq(receive:reconnect(1), false)
    T.eq(receive:snapshot().players.host.metrics.damage, 100)
    local callerCopy = receive:snapshot(); callerCopy.players.host.metrics.damage = 9000
    T.eq(receive:snapshot().players.host.metrics.damage, 100)
end)

T.finish()
