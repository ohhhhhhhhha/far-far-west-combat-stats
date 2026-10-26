-- Deterministic statistics. Times are mission seconds from a clock that excludes pause.
-- This module observes normalized events; it contains no engine bindings or transport.
local Stats = {}
Stats.__index = Stats
Stats.VERSION = 1
Stats.METRICS = {
    "damage", "incomingDamage", "hpLoss", "shieldAbsorbed", "largestHit",
    "kills", "eliteKills", "bossKills", "assists", "healing", "selfHealing",
    "teamHealing", "healingAttempted", "overhealing", "shieldGained", "shieldGranted",
    "shieldOvergain", "shots", "hits", "ammo", "reloads", "revives", "deaths",
    "downs", "rescued", "downDuration", "aliveDuration",
}
local knownMetrics = {}
for _, key in ipairs(Stats.METRICS) do knownMetrics[key] = true end
local colors = {"#56B4E9", "#E69F00", "#009E73", "#CC79A7", "#F0E442", "#D55E00", "#0072B2"}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function identifier(value) return type(value) == "string" and value ~= "" end
local function player(state, id, name, time)
    local p = state.players[id]
    if not p then
        p = {id = id, name = name or id, color = colors[(#state.playerOrder % #colors) + 1],
            connected = true, joinedAt = time, lifeState = "alive", totals = {}, coverage = {},
            damageBySource = {}, incomingBySource = {}, rolling = {}, shotsById = {}, accuracyByMode = {}}
        for _, key in ipairs(Stats.METRICS) do
            p.totals[key] = 0
            p.coverage[key] = {status = "unavailable", tracking = false, intervals = {}}
        end
        state.players[id] = p
        state.playerOrder[#state.playerOrder + 1] = id
    end
    return p
end
local function observe(p, metric, time)
    local c = p.coverage[metric]
    if c.status == "unavailable" then c.status = "partial" end
    if not c.tracking then
        c.tracking = true
        c.intervals[#c.intervals + 1] = {from = time}
    end
end
local function add(p, metric, amount, time)
    p.totals[metric] = p.totals[metric] + amount
    observe(p, metric, time)
end
local function advance(s, now)
    local elapsed = now - s.time
    for _, p in pairs(s.players) do
        if p.connected and elapsed > 0 then
            if p.lifeState == "alive" then add(p, "aliveDuration", elapsed, s.time)
            elseif p.lifeState == "down" then add(p, "downDuration", elapsed, s.time) end
        end
        local kept = {}
        for _, d in ipairs(p.rolling) do if d.time > now - 5 then kept[#kept + 1] = d end end
        p.rolling = kept
    end
    for _, encounter in pairs(s.encounters) do
        local stop = encounter.endTime or now
        for id, p in pairs(encounter.players) do
            local main = s.players[id]
            if not encounter.endTime then
                p.connected, p.lifeState = main.connected, main.lifeState
                if main.connected and elapsed > 0 then
                    if main.lifeState == "alive" then add(p, "aliveDuration", elapsed, s.time)
                    elseif main.lifeState == "down" then add(p, "downDuration", elapsed, s.time) end
                end
            end
            local kept = {}
            for _, d in ipairs(p.rolling) do if d.time > stop - 5 then kept[#kept + 1] = d end end
            p.rolling = kept
        end
    end
    s.time = now
end
local function setCoverage(p, metric, status, time, from)
    local c = p.coverage[metric]
    if status == "unavailable" then
        if c.tracking then c.intervals[#c.intervals].to = time end
        c.tracking = false
        if c.status ~= "unavailable" then c.status = "partial" end
    else
        if from and from <= p.joinedAt then c.intervals = {{from = from}}; c.tracking = true
        else observe(p, metric, from or time) end
        c.status = status == "complete" and #c.intervals == 1 and c.intervals[1].from <= p.joinedAt and "complete" or "partial"
    end
end
local function metrics(p, now, duration)
    local result = {}
    for _, key in ipairs(Stats.METRICS) do
        if p.coverage[key].status ~= "unavailable" then result[key] = p.totals[key] end
    end
    if result.damage ~= nil then
        local sum = 0
        for _, d in ipairs(p.rolling) do if d.time > now - 5 and d.time <= now then sum = sum + d.amount end end
        if p.connected and p.coverage.damage.tracking then result.rollingDps = duration > 0 and sum / math.min(5, duration) or 0 end
        result.averageDps = duration > 0 and result.damage / duration or 0
    end
    if result.shots ~= nil and result.hits ~= nil and result.shots > 0 then result.accuracy = result.hits / result.shots end
    return result
end
local function scopePlayer(encounter, p, time)
    if encounter.players[p.id] then return encounter.players[p.id] end
    local ep = player(encounter, p.id, p.name, time)
    ep.color, ep.connected, ep.lifeState = p.color, p.connected, p.lifeState
    for _, key in ipairs(Stats.METRICS) do
        if p.coverage[key].tracking then setCoverage(ep, key, p.coverage[key].status, time, time) end
    end
    return ep
end
function Stats.new(sessionId)
    assert(identifier(sessionId), "sessionId must be a nonempty stable string")
    return setmetatable({_state = {sessionId = sessionId, time = 0, status = "active", players = {},
        playerOrder = {}, seen = {}, history = {}, encounters = {}, contributors = {}, killedTargets = {}, assistCredits = {}}}, Stats)
end
local kinds = {
    player_join = true, player_leave = true, coverage = true, damage = true, incoming = true,
    kill = true, assist = true, heal = true, shield_gain = true, shot = true, hit = true,
    ammo = true, reload = true, down = true, death = true, revive_complete = true,
    respawn = true, encounter_start = true, encounter_end = true, mission_end = true,
}
local sourceKinds = {player_join = true, player_leave = true, coverage = true, damage = true,
    kill = true, assist = true, heal = true, shield_gain = true, shot = true, hit = true,
    ammo = true, reload = true, revive_complete = true}
local targetKinds = {incoming = true, heal = true, shield_gain = true, down = true, death = true, respawn = true, revive_complete = true}
local function nonnegative(value) return finite(value) and value >= 0 end
local function validate(s, e)
    if not kinds[e.kind] then return "unsupported event kind" end
    if s.status ~= "active" then return "mission has ended" end
    if sourceKinds[e.kind] and not identifier(e.sourcePlayerId) then return "sourcePlayerId required" end
    if targetKinds[e.kind] and not identifier(e.targetPlayerId) then return "targetPlayerId required" end
    if e.name ~= nil and type(e.name) ~= "string" then return "name must be text" end
    if e.kind == "revive_complete" and e.sourcePlayerId == e.targetPlayerId then return "revive_complete is a teammate action; use respawn for self recovery" end
    if e.kind == "damage" then
        if not nonnegative(e.amount) or not identifier(e.sourceCategory) or not identifier(e.targetId) then return "final damage, targetId and sourceCategory required" end
    elseif e.kind == "incoming" then
        if not nonnegative(e.hpLoss) or not nonnegative(e.shieldAbsorbed) or not identifier(e.sourceCategory) then return "actual health loss, shield absorption and sourceCategory required" end
    elseif e.kind == "heal" or e.kind == "shield_gain" then
        if not nonnegative(e.amount) or not nonnegative(e.effectiveAmount) or e.effectiveAmount > e.amount then return "attempted and effective amounts required" end
    elseif e.kind == "coverage" then
        if not knownMetrics[e.metric] or (e.status ~= "complete" and e.status ~= "partial" and e.status ~= "unavailable") then return "invalid coverage" end
        if e.from ~= nil and (not nonnegative(e.from) or e.from > e.time) then return "invalid coverage start" end
    elseif e.kind == "kill" or e.kind == "assist" then
        if not identifier(e.targetId) then return "targetId must uniquely identify this enemy life" end
        if e.assistPlayerIds ~= nil then
            if type(e.assistPlayerIds) ~= "table" then return "assistPlayerIds must be an array" end
            for _, id in ipairs(e.assistPlayerIds) do if not identifier(id) then return "invalid assist player" end end
        end
    elseif e.kind == "shot" then
        if not identifier(e.attackId) or (e.accuracyMode ~= "ordinary" and e.accuracyMode ~= "pellet" and e.accuracyMode ~= "multi" and e.accuracyMode ~= "dot") then return "stable attackId and accuracyMode required" end
    elseif e.kind == "hit" then
        local p = s.players[e.sourcePlayerId]
        if not identifier(e.attackId) or type(e.validTarget) ~= "boolean" or not p or not p.shotsById[e.attackId] then return "hit requires a prior shot and validTarget" end
    elseif e.kind == "ammo" then
        if not nonnegative(e.amount) then return "spent ammo amount required" end
    elseif e.kind == "encounter_start" or e.kind == "encounter_end" then
        if not identifier(e.encounterId) then return "encounterId required" end
        if e.kind == "encounter_start" and s.encounters[e.encounterId] then return "encounter already started" end
        if e.kind == "encounter_end" and (not s.encounters[e.encounterId] or s.encounters[e.encounterId].endTime) then return "encounter is not active" end
    end
    if e.encounterId and e.kind ~= "encounter_start" and e.kind ~= "encounter_end" then
        local encounter = s.encounters[e.encounterId]
        if not encounter or encounter.endTime then return "encounter is not active" end
    end
end
local function record(s, p, key, amount, e)
    add(p, key, amount, e.time)
    for id, encounter in pairs(s.encounters) do
        if not encounter.endTime and (not e.encounterId or e.encounterId == id) then
            local ep = scopePlayer(encounter, p, e.time)
            add(ep, key, amount, e.time)
            if key == "damage" then
                ep.rolling[#ep.rolling + 1] = {time = e.time, amount = amount}
                ep.damageBySource[e.sourceCategory] = (ep.damageBySource[e.sourceCategory] or 0) + amount
            elseif key == "incomingDamage" then ep.incomingBySource[e.sourceCategory] = (ep.incomingBySource[e.sourceCategory] or 0) + amount end
        end
    end
end
local function creditAssist(s, id, targetId, e)
    s.assistCredits[targetId] = s.assistCredits[targetId] or {}
    if not s.assistCredits[targetId][id] and s.killedTargets[targetId] ~= id then
        s.assistCredits[targetId][id] = true
        record(s, player(s, id, nil, e.time), "assists", 1, e)
    end
end
function Stats:apply(e)
    local s = self._state
    if type(e) ~= "table" or not identifier(e.id) then return false, "event ID required" end
    if e.sessionId ~= s.sessionId then return false, "wrong session" end
    if s.seen[e.id] then return false, "duplicate event" end
    if not finite(e.time) or e.time < s.time then return false, "event time precedes the mission clock" end
    local invalid = validate(s, e)
    if invalid then return false, invalid end
    advance(s, e.time)
    local p = sourceKinds[e.kind] and player(s, e.sourcePlayerId, e.name, e.time) or nil
    local target = targetKinds[e.kind] and player(s, e.targetPlayerId, nil, e.time) or nil
    if e.kind == "player_join" then
        p.connected = true
        if e.name then p.name = e.name end
        observe(p, "aliveDuration", e.time); observe(p, "downDuration", e.time)
        for _, encounter in pairs(s.encounters) do if not encounter.endTime then scopePlayer(encounter, p, e.time) end end
    elseif e.kind == "player_leave" then
        p.connected = false
        for key in pairs(p.coverage) do setCoverage(p, key, "unavailable", e.time) end
        for _, encounter in pairs(s.encounters) do
            local ep = encounter.players[p.id]
            if not encounter.endTime and ep then
                ep.connected = false
                for key in pairs(ep.coverage) do setCoverage(ep, key, "unavailable", e.time) end
            end
        end
    elseif e.kind == "coverage" then
        setCoverage(p, e.metric, e.status, e.time, e.from)
        for _, encounter in pairs(s.encounters) do
            if not encounter.endTime then
                local ep = scopePlayer(encounter, p, e.time)
                setCoverage(ep, e.metric, e.status, e.time, e.from and math.max(e.from, encounter.startTime) or nil)
            end
        end
    elseif e.kind == "damage" then
        record(s, p, "damage", e.amount, e)
        p.damageBySource[e.sourceCategory] = (p.damageBySource[e.sourceCategory] or 0) + e.amount
        p.rolling[#p.rolling + 1] = {time = e.time, amount = e.amount}
        if e.amount > 0 and not s.killedTargets[e.targetId] then
            s.contributors[e.targetId] = s.contributors[e.targetId] or {}
            s.contributors[e.targetId][p.id] = true
        end
    elseif e.kind == "incoming" then
        local total = e.hpLoss + e.shieldAbsorbed
        record(s, target, "hpLoss", e.hpLoss, e); record(s, target, "shieldAbsorbed", e.shieldAbsorbed, e)
        record(s, target, "incomingDamage", total, e)
        target.totals.largestHit = math.max(target.totals.largestHit, total); observe(target, "largestHit", e.time)
        target.incomingBySource[e.sourceCategory] = (target.incomingBySource[e.sourceCategory] or 0) + total
        for id, encounter in pairs(s.encounters) do
            if not encounter.endTime and (not e.encounterId or e.encounterId == id) then
                local ep = encounter.players[target.id]
                ep.totals.largestHit = math.max(ep.totals.largestHit, total); observe(ep, "largestHit", e.time)
            end
        end
    elseif e.kind == "kill" then
        if not s.killedTargets[e.targetId] then
            s.killedTargets[e.targetId] = p.id
            record(s, p, "kills", 1, e)
            if e.targetClass == "regular" or e.targetClass == "elite" or e.targetClass == "boss" then
                record(s, p, "eliteKills", e.targetClass == "elite" and 1 or 0, e)
                record(s, p, "bossKills", e.targetClass == "boss" and 1 or 0, e)
            end
            if e.assistPlayerIds then
                for _, id in ipairs(e.assistPlayerIds) do creditAssist(s, id, e.targetId, e) end
            else
                for id in pairs(s.contributors[e.targetId] or {}) do creditAssist(s, id, e.targetId, e) end
            end
            s.contributors[e.targetId] = nil
        end
    elseif e.kind == "assist" then creditAssist(s, p.id, e.targetId, e)
    elseif e.kind == "heal" then
        record(s, p, "healingAttempted", e.amount, e); record(s, p, "healing", e.effectiveAmount, e)
        record(s, p, "overhealing", e.amount - e.effectiveAmount, e)
        record(s, p, p.id == target.id and "selfHealing" or "teamHealing", e.effectiveAmount, e)
    elseif e.kind == "shield_gain" then
        record(s, p, "shieldGranted", e.amount, e); record(s, p, "shieldOvergain", e.amount - e.effectiveAmount, e)
        record(s, target, "shieldGained", e.effectiveAmount, e)
    elseif e.kind == "shot" then
        if not p.shotsById[e.attackId] then
            p.shotsById[e.attackId] = {mode = e.accuracyMode, hit = false}
            local mode = p.accuracyByMode[e.accuracyMode] or {shots = 0, hits = 0}
            p.accuracyByMode[e.accuracyMode] = mode; mode.shots = mode.shots + 1
            if e.accuracyMode == "ordinary" then record(s, p, "shots", 1, e); record(s, p, "hits", 0, e) end
        end
    elseif e.kind == "hit" then
        local shot = p.shotsById[e.attackId]
        if e.validTarget and not shot.hit then
            shot.hit = true
            p.accuracyByMode[shot.mode].hits = p.accuracyByMode[shot.mode].hits + 1
            if shot.mode == "ordinary" then record(s, p, "hits", 1, e) end
        end
    elseif e.kind == "ammo" then record(s, p, "ammo", e.amount, e)
    elseif e.kind == "reload" then record(s, p, "reloads", 1, e)
    elseif e.kind == "down" then
        if target.lifeState ~= "down" then record(s, target, "downs", 1, e); target.lifeState = "down" end
    elseif e.kind == "death" then
        if target.lifeState ~= "dead" then record(s, target, "deaths", 1, e); target.lifeState = "dead" end
    elseif e.kind == "revive_complete" then
        record(s, p, "revives", 1, e); record(s, target, "rescued", 1, e); target.lifeState = "alive"
    elseif e.kind == "respawn" then target.lifeState = "alive"
    elseif e.kind == "encounter_start" then
        s.encounters[e.encounterId] = {id = e.encounterId, name = e.name or e.encounterId,
            startTime = e.time, players = {}, playerOrder = {}, history = {}}
        for _, id in ipairs(s.playerOrder) do scopePlayer(s.encounters[e.encounterId], s.players[id], e.time) end
    elseif e.kind == "encounter_end" then s.encounters[e.encounterId].endTime = e.time
    elseif e.kind == "mission_end" then
        s.status, s.endTime = "ended", e.time
        for _, encounter in pairs(s.encounters) do if not encounter.endTime then encounter.endTime = e.time end end
    end
    s.seen[e.id] = true
    return true
end
local function playerView(p, now, duration)
    local view = {id = p.id, name = p.name, color = p.color, connected = p.connected,
        metrics = metrics(p, now, duration), coverage = copy(p.coverage), damageBySource = copy(p.damageBySource),
        incomingBySource = copy(p.incomingBySource), accuracyByMode = copy(p.accuracyByMode), damageSourceShares = {}}
    view.coverage.rollingDps = copy(p.coverage.damage)
    view.coverage.averageDps = copy(p.coverage.damage)
    if not p.connected or not p.coverage.damage.tracking then view.coverage.rollingDps.status = "unavailable" end
    if view.metrics.damage and view.metrics.damage > 0 then
        for source, value in pairs(p.damageBySource) do view.damageSourceShares[source] = value / view.metrics.damage end
    end
    return view
end
local function sampleHistory(history, players, now)
    local sample = {time = now, players = {}}
    for id, view in pairs(players) do
        if view.metrics.rollingDps ~= nil then
            sample.players[id] = {damage = view.metrics.damage, rollingDps = view.metrics.rollingDps,
                averageDps = view.metrics.averageDps, coverage = view.coverage.damage.status}
        end
    end
    if #history > 0 and history[#history].time == now then history[#history] = sample else history[#history + 1] = sample end
end
local function teamView(players, order)
    local total, count, available, complete = 0, 0, 0, true
    for _, id in ipairs(order) do
        local p = players[id]
        count = count + 1
        if p.metrics.damage ~= nil then total = total + p.metrics.damage; available = available + 1 end
        if p.coverage.damage.status ~= "complete" then complete = false end
    end
    complete = complete and count > 0
    for _, p in pairs(players) do
        p.coverage.damageShare = {status = complete and total > 0 and "complete" or "unavailable"}
        if count==1 then
            p.metrics.damageShare=1;p.damageShareSolo=true
            p.coverage.damageShare.status=complete and 'complete' or 'partial'
        elseif complete and total > 0 then p.metrics.damageShare = p.metrics.damage / total
        end
    end
    return {metrics = {damage = available > 0 and total or nil}, coverage = {damage = {
        status = complete and "complete" or available > 0 and "partial" or "unavailable"}}}
end
function Stats:snapshot(now)
    local s = self._state
    now = s.endTime or now or s.time
    assert(finite(now) and now >= s.time, "snapshot time must not move backward")
    advance(s, now)
    local result = {schemaVersion = Stats.VERSION, sessionId = s.sessionId, time = now, status = s.status,
        players = {}, playerOrder = copy(s.playerOrder), encounters = {}}
    for id, p in pairs(s.players) do
        result.players[id] = playerView(p, now, now)
    end
    for id, encounter in pairs(s.encounters) do
        local stop = encounter.endTime or now
        local view = {id = id, name = encounter.name, startTime = encounter.startTime, endTime = encounter.endTime,
            duration = stop - encounter.startTime, players = {}, playerOrder = copy(encounter.playerOrder)}
        for playerId, p in pairs(encounter.players) do
            view.players[playerId] = playerView(p, stop, view.duration)
        end
        view.team = teamView(view.players, view.playerOrder)
        sampleHistory(encounter.history, view.players, stop)
        view.history = copy(encounter.history)
        result.encounters[id] = view
    end
    result.team = teamView(result.players, result.playerOrder)
    sampleHistory(s.history, result.players, now)
    result.history = copy(s.history)
    result.state = copy(s)
    return result
end
local function validPlayer(p)
    if type(p) ~= "table" or not identifier(p.id) or type(p.name) ~= "string" or type(p.color) ~= "string"
        or type(p.connected) ~= "boolean" or not nonnegative(p.joinedAt)
        or (p.lifeState ~= "alive" and p.lifeState ~= "down" and p.lifeState ~= "dead") then return false end
    for _, field in ipairs({"totals", "coverage", "damageBySource", "incomingBySource", "rolling", "shotsById", "accuracyByMode"}) do
        if type(p[field]) ~= "table" then return false end
    end
    for _, key in ipairs(Stats.METRICS) do
        local c = p.coverage[key]
        if not nonnegative(p.totals[key]) or type(c) ~= "table" or type(c.tracking) ~= "boolean" or type(c.intervals) ~= "table"
            or (c.status ~= "complete" and c.status ~= "partial" and c.status ~= "unavailable") then return false end
        for _, interval in ipairs(c.intervals) do
            if type(interval) ~= "table" or not nonnegative(interval.from) or (interval.to and (not finite(interval.to) or interval.to < interval.from)) then return false end
        end
        if c.tracking and (#c.intervals == 0 or c.intervals[#c.intervals].to ~= nil) then return false end
    end
    for _, map in ipairs({p.damageBySource, p.incomingBySource}) do
        for key, amount in pairs(map) do if not identifier(key) or not nonnegative(amount) then return false end end
    end
    for _, d in ipairs(p.rolling) do if type(d) ~= "table" or not nonnegative(d.time) or not nonnegative(d.amount) then return false end end
    for _, mode in pairs(p.accuracyByMode) do
        if type(mode) ~= "table" or not nonnegative(mode.shots) or not nonnegative(mode.hits) or mode.hits > mode.shots then return false end
    end
    for id, shot in pairs(p.shotsById) do
        if not identifier(id) or type(shot) ~= "table" or type(shot.hit) ~= "boolean" or not p.accuracyByMode[shot.mode] then return false end
    end
    return true
end
local function validHistory(history, players, firstTime, lastTime)
    if type(history) ~= "table" then return false end
    local previous = firstTime - 1
    for _, point in ipairs(history) do
        if type(point) ~= "table" or not finite(point.time) or point.time < firstTime or point.time <= previous
            or point.time > lastTime or type(point.players) ~= "table" then return false end
        previous = point.time
        for id, values in pairs(point.players) do
            if not players[id] or type(values) ~= "table" or not nonnegative(values.damage) or not nonnegative(values.rollingDps) or not nonnegative(values.averageDps)
                or (values.coverage ~= "complete" and values.coverage ~= "partial") then return false end
        end
    end
    return true
end
local function validState(s)
    if type(s) ~= "table" or not identifier(s.sessionId) or not nonnegative(s.time) or (s.status ~= "active" and s.status ~= "ended") then return false end
    if s.status == "ended" and s.endTime ~= s.time then return false end
    for _, key in ipairs({"players", "playerOrder", "seen", "history", "encounters", "contributors", "killedTargets", "assistCredits"}) do
        if type(s[key]) ~= "table" then return false end
    end
    local found = {}
    for _, id in ipairs(s.playerOrder) do
        if found[id] or not s.players[id] then return false end
        found[id] = true
    end
    for id, p in pairs(s.players) do if not validPlayer(p) or p.id ~= id or not found[id] then return false end end
    for id, seen in pairs(s.seen) do if not identifier(id) or seen ~= true then return false end end
    for _, mapping in ipairs({s.contributors, s.assistCredits}) do
        for id, members in pairs(mapping) do
            if not identifier(id) or type(members) ~= "table" then return false end
            for playerId, present in pairs(members) do if not s.players[playerId] or present ~= true then return false end end
        end
    end
    for id, killer in pairs(s.killedTargets) do if not identifier(id) or not s.players[killer] then return false end end
    if not validHistory(s.history, s.players, 0, s.time) then return false end
    for id, encounter in pairs(s.encounters) do
        if type(encounter) ~= "table" or encounter.id ~= id or not nonnegative(encounter.startTime) or encounter.startTime > s.time
            or type(encounter.name) ~= "string" or type(encounter.players) ~= "table" or type(encounter.playerOrder) ~= "table" or type(encounter.history) ~= "table"
            or (encounter.endTime and (not finite(encounter.endTime) or encounter.endTime < encounter.startTime or encounter.endTime > s.time)) then return false end
        local encounterOrder = {}
        for _, playerId in ipairs(encounter.playerOrder) do
            if encounterOrder[playerId] or not encounter.players[playerId] then return false end
            encounterOrder[playerId] = true
        end
        for playerId, p in pairs(encounter.players) do
            if not encounterOrder[playerId] or not s.players[playerId] or not validPlayer(p) or p.id ~= playerId then return false end
        end
        if not validHistory(encounter.history, encounter.players, encounter.startTime, encounter.endTime or s.time) then return false end
    end
    return true
end
function Stats.restore(snapshot)
    if type(snapshot) ~= "table" or snapshot.schemaVersion ~= Stats.VERSION or not validState(snapshot.state)
        or snapshot.sessionId ~= snapshot.state.sessionId or snapshot.time ~= snapshot.state.time or snapshot.status ~= snapshot.state.status then
        return nil, "incomplete or incompatible statistics snapshot"
    end
    return setmetatable({_state = copy(snapshot.state)}, Stats)
end
return Stats
