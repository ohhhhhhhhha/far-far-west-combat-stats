package.path = "FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;" .. package.path
local T = require("stats_testlib")
local Stats = require("Stats")
local haveJson, Json = pcall(require, "Json")
local haveStore, Store = pcall(require, "Store")
local path = "FFWTools/tests/stats_persistence_test.json"
local function cleanup()
    os.remove(path); os.remove(path .. ".tmp"); os.remove(path .. ".bak")
end
local function fixture()
    local s = Stats.new("A")
    assert(s:apply({id = "p", sessionId = "A", kind = "player_join", time = 0, sourcePlayerId = "host", name = "队友 \"甲\"\n😀"}))
    assert(s:apply({id = "c", sessionId = "A", kind = "coverage", time = 0, sourcePlayerId = "host", metric = "damage", status = "complete", from = 0}))
    assert(s:apply({id = "d1", sessionId = "A", kind = "damage", time = 1, sourcePlayerId = "host", targetId = "enemy", sourceCategory = "primary", amount = 100}))
    return s
end

-- Catches escaping/number corruption in the actual serialization used for names and graph points.
T.test("JSON preserves UTF-8 names escaped text booleans arrays and fractional times", function()
    T.eq(haveJson, true, "JSON codec available")
    local encoded = Json.encode({name = "队友 \"甲\"\n😀", points = {0, 1.25, -2}, enabled = false})
    local decoded = Json.decode(encoded)
    T.eq(decoded.name, "队友 \"甲\"\n😀"); T.eq(decoded.points[2], 1.25); T.eq(decoded.enabled, false)
    T.eq(Json.decode([["\uD83D\uDE00"]]), "😀")
    T.eq(pcall(Json.decode, '{"points":[1,2'), false)
    T.eq(pcall(Json.decode, '{"value":1}junk'), false)
end)

-- Catches dropping dedup state/history or silently replacing an existing file with stale values.
T.test("actual file replacement and restart retain history totals and duplicate protection", function()
    T.eq(haveStore, true, "snapshot store available")
    cleanup()
    local s = fixture()
    assert(Store.write(path, s:snapshot(2)))
    local restored = assert(Store.resume(path, "A"))
    T.eq(restored:apply({id = "d1", sessionId = "A", kind = "damage", time = 1, sourcePlayerId = "host", targetId = "enemy", sourceCategory = "primary", amount = 100}), false)
    assert(restored:apply({id = "d2", sessionId = "A", kind = "damage", time = 3, sourcePlayerId = "host", targetId = "enemy2", sourceCategory = "spell", amount = 50}))
    assert(Store.write(path, restored:snapshot(4)))
    local disk = assert(Store.read(path))
    T.eq(disk.players.host.metrics.damage, 150); T.eq(disk.players.host.metrics.averageDps, 37.5)
    T.eq(disk.players.host.name, "队友 \"甲\"\n😀"); T.eq(#disk.history, 2)
    T.eq(disk.history[1].players.host.damage, 100); T.eq(disk.history[2].players.host.damage, 150)
    T.eq(io.open(path .. ".tmp", "rb"), nil)
    cleanup()
end)

-- Catches resets in lobby/app startup and resets that recur for one stable mission identifier.
T.test("last mission survives lobby restart and only a different mission ID resets", function()
    T.eq(haveStore, true, "snapshot store available")
    cleanup()
    local s = fixture()
    assert(s:apply({id = "end", sessionId = "A", kind = "mission_end", time = 8}))
    assert(Store.write(path, s:snapshot(100)))
    local previous = assert(Store.resume(path))
    local last = previous:snapshot(200)
    T.eq(last.status, "ended"); T.eq(last.time, 8); T.eq(last.players.host.metrics.damage, 100)
    local same, sameReset = Store.start(previous, "A")
    T.eq(same, previous); T.eq(sameReset, false)
    local nextRun, didReset = Store.start(previous, "B")
    T.eq(didReset, true); T.eq(nextRun:snapshot(0).sessionId, "B"); T.eq(next(nextRun:snapshot(0).players), nil)
    local sameNext, resetTwice = Store.start(nextRun, "B")
    T.eq(sameNext, nextRun); T.eq(resetTwice, false)
    cleanup()
end)

-- Catches accepting a truncated/mismatched snapshot as a zero-valued valid run.
T.test("restore rejects incomplete or incompatible persisted state", function()
    T.eq(type(Stats.restore), "function", "restore available")
    local snap = fixture():snapshot(2)
    snap.schemaVersion = 99
    T.eq(Stats.restore(snap), nil)
    snap.schemaVersion = 1; snap.state.players.host.totals.damage = nil
    T.eq(Stats.restore(snap), nil)
end)

-- Catches the Windows replace gap losing the only complete snapshot after interruption.
T.test("backup recovery retains the last complete file during an interrupted replace", function()
    T.eq(haveStore, true, "snapshot store available")
    cleanup()
    assert(Store.write(path, fixture():snapshot(2)))
    assert(os.rename(path, path .. ".bak"))
    local partial = assert(io.open(path .. ".tmp", "wb")); partial:write('{"schemaVersion":'); partial:close()
    local recovered = assert(Store.read(path))
    T.eq(recovered.players.host.metrics.damage, 100)
    cleanup()
end)

-- Catches a valid outer JSON object hiding corrupt graph data in a nested boss interval.
T.test("restore rejects malformed boss history instead of returning broken chart samples", function()
    local s = fixture()
    assert(s:apply({id = "boss", sessionId = "A", kind = "encounter_start", encounterId = "boss", time = 2}))
    local snap = s:snapshot(3)
    snap.state.encounters.boss.history[1].players.host.damage = "missing"
    T.eq(Stats.restore(snap), nil)
end)

T.test("corrupt boss roster is rejected and the paired backup can recover", function()
    cleanup()
    local s = fixture()
    assert(s:apply({id = "boss", sessionId = "A", kind = "encounter_start", encounterId = "boss", time = 2}))
    local snap = s:snapshot(3)
    assert(Store.write(path .. ".bak", snap))
    snap.state.encounters.boss.playerOrder = {"missing-player"}
    local file = assert(io.open(path, "wb")); file:write(Json.encode(snap)); file:close()
    T.eq(Stats.restore(snap), nil)
    T.eq(assert(Store.read(path)).players.host.metrics.damage, 100)
    snap.state.encounters.boss.playerOrder = {"host", "host"}
    T.eq(Stats.restore(snap), nil)
    snap.state.encounters.boss.playerOrder = {}
    T.eq(Stats.restore(snap), nil)
    cleanup()
end)
cleanup()
T.finish()
