package.path = "FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;" .. package.path
local T = require("stats_testlib")
local loaded, Panel = pcall(require, "Panel")
local function module() T.eq(loaded, true, "panel module available"); return Panel end
local function player(id, name, color, damage, status)
    return {id = id, name = name, color = color, connected = true,
        metrics = {damage = damage}, coverage = {damage = {status = status or "complete"}},
        damageBySource = {}, incomingBySource = {}, accuracyByMode = {}}
end
local function fixture()
    return {schemaVersion = 1, sessionId = "A", time = 15, status = "active", playerOrder = {"a", "b", "c"},
        players = {a = player("a", "队友甲", "#56B4E9", 1000), b = player("b", "队友乙", "#E69F00", 500, "partial"),
            c = player("c", "队友丙", "#009E73", nil, "unavailable")},
        history = {
            {time = 0, players = {a = {damage = 0, rollingDps = 0, averageDps = 0, coverage = "complete"}}},
            {time = 5, players = {a = {damage = 100, rollingDps = 20, averageDps = 20, coverage = "complete"}, b = {damage = 50, rollingDps = 10, averageDps = 10, coverage = "partial"}}},
            {time = 10, players = {b = {damage = 150, rollingDps = 20, averageDps = 15, coverage = "partial"}}},
            {time = 15, players = {a = {damage = 200, rollingDps = 10, averageDps = 13.333333333333, coverage = "partial"}}},
        }, encounters = {}}
end

-- Catches converting an unknown value to a measured zero or normalizing each bar to itself.
T.test("team bars share zero and scale while unavailable values have no bar", function()
    local m = module().build(fixture(), {metric = "damage"})
    local chart = m.charts[1]
    T.eq(chart.zero, 0); T.eq(chart.maximum, 1000)
    T.eq(chart.rows[1].fraction, 1); T.eq(chart.rows[2].fraction, 0.5)
    T.eq(chart.rows[3].fraction, nil); T.eq(chart.rows[3].text, "不可用")
    T.eq(chart.rows[2].quality, "部分数据"); T.eq(chart.rows[1].exactText, "1000")
    T.eq(chart.rows[1].color, m.trends.rolling.series[1].color)
end)

-- Catches connecting DPS across a missing sample, and using one player's scale for another.
T.test("both DPS trends share axes and split at missing observations", function()
    local m = module().build(fixture(), {metric = "overview"})
    T.eq(#m.charts, 6)
    T.eq(m.trends.rolling.minimumTime, 0); T.eq(m.trends.rolling.maximumTime, 15)
    T.eq(m.trends.rolling.maximum, 20); T.eq(m.trends.average.maximum, 20)
    local a = m.trends.rolling.series[1]
    T.eq(#a.segments, 2); T.eq(#a.segments[1].points, 2); T.eq(#a.segments[2].points, 1)
    T.eq(a.segments[1].points[2].time, 5); T.eq(a.segments[2].points[1].time, 15)
    T.eq(#m.trends.rolling.series[3].segments, 0)
end)

-- Catches drawing whole-mission damage in a Boss view or using absolute mission time as Boss elapsed time.
T.test("Boss selection uses its own totals and relative time and preserves player colors", function()
    local snap = fixture()
    snap.encounters.boss = {id = "boss", name = "沙漠首领", startTime = 4, endTime = 8, duration = 4,
        playerOrder = {"a"}, players = {a = player("a", "队友甲", "#56B4E9", 200)},
        history = {{time = 6, players = {a = {damage = 200, rollingDps = 100, averageDps = 100, coverage = "complete"}}}}}
    local m = module().build(snap, {scopeId = "boss", metric = "damage"})
    T.eq(m.charts[1].rows[1].value, 200); T.eq(m.scopeLabel, "沙漠首领")
    T.eq(m.duration, 4); T.eq(m.trends.rolling.maximumTime, 4)
    T.eq(m.trends.rolling.series[1].segments[1].points[1].time, 2)
    T.eq(m.charts[1].rows[1].color, "#56B4E9")
end)

-- Catches presenting a percentage without its denominator or rounding away the precise table value.
T.test("accuracy displays its actual numerator denominator and precise underlying value", function()
    local snap = fixture()
    snap.players.a.metrics.shots, snap.players.a.metrics.hits, snap.players.a.metrics.accuracy = 3, 1, 1 / 3
    snap.players.a.coverage.shots, snap.players.a.coverage.hits = {status = "complete"}, {status = "complete"}
    local m = module().build(snap, {metric = "accuracy"})
    T.eq(m.charts[1].rows[1].numerator, 1); T.eq(m.charts[1].rows[1].denominator, 3)
    T.eq(m.charts[1].rows[1].text, "33.33%（1 / 3）")
    T.near(m.charts[1].rows[1].value, 1 / 3)
    T.eq(m.charts[1].rows[3].text, "不可用")
end)

-- Catches attributing source damage to the wrong player, or inventing known source zeroes for an unknown player.
T.test("damage sources retain player colors values and percentages", function()
    local snap = fixture()
    snap.players.a.damageBySource = {primary = 750, spell = 250}
    snap.players.b.damageBySource = {primary = 500}
    local m = module().build(snap, {metric = "damageSources"})
    T.eq(m.charts[1].key, "source:primary")
    T.eq(m.charts[1].rows[1].value, 750); T.eq(m.charts[1].rows[1].share, 0.75)
    T.eq(m.charts[1].rows[2].color, "#E69F00"); T.eq(m.charts[1].rows[3].value, nil)
end)

-- Catches excessive long-run geometry while retaining isolated peaks and missing-data breaks.
T.test("trend reduction preserves a spike endpoints and observation gaps", function()
    local snap = fixture(); snap.time = 100; snap.history = {}
    for i = 0, 100 do
        snap.history[#snap.history + 1] = {time = i, players = {a = {damage = 0, rollingDps = i == 51 and 1000 or 0, averageDps = 0, coverage = "complete"}}}
    end
    snap.history[31].players.a = nil
    local m = module().build(snap, {metric = "damage"}, {trendPointBudget = 12})
    local segments = m.trends.rolling.series[1].segments
    T.eq(#segments, 2)
    T.eq(segments[1].points[1].time, 0); T.eq(segments[2].points[#segments[2].points].time, 100)
    local peak, count = false, 0
    for _, segment in ipairs(segments) do for _, point in ipairs(segment.points) do count = count + 1; if point.value == 1000 then peak = true end end end
    T.eq(peak, true); T.eq(count <= 12, true)
end)

-- Catches hidden-state work, stale selected Boss state after a new mission, and key callbacks that don't change the view.
T.test("controller stays hidden until F8 and preserves valid selection across updates", function()
    local panel = module().new({selfPlayerId = "a"})
    panel:update(fixture()); T.eq(panel:model(), nil)
    local callbacks = {}
    panel:bindKeys({Key = {F8 = 119, PAGE_UP = 33, PAGE_DOWN = 34, HOME = 36, END = 35, TAB = 9},
        register = function(key, callback) callbacks[key] = callback end, execute = function(callback) callback() end})
    callbacks[119](); T.eq(panel:model().visible, true); T.eq(panel:model().legend[1].isSelf, true)
    local cached = panel:model(); T.eq(panel:model(), cached)
    callbacks[34](); T.eq(panel:model().metric, "teamContribution")
    callbacks[119](); T.eq(panel:model(), nil)
    local fresh = fixture(); fresh.sessionId = "B"; fresh.status = "ended"
    panel:update(fresh); callbacks[119](); T.eq(panel:model().missionLabel, "上一局")
end)

-- Catches a heavily interrupted run allocating one UMG object for every raw point.
T.test("many gaps remain disconnected within a finite geometry budget", function()
    local snap = fixture(); snap.time = 300; snap.history = {}
    for i = 0, 300 do
        snap.history[#snap.history + 1] = {time = i, players = i % 2 == 0 and {a = {damage = 0, rollingDps = i == 150 and 999 or 1, averageDps = 1, coverage = "partial"}} or {}}
    end
    local m = module().build(snap, {}, {trendPointBudget = 24})
    local series, count, peak = m.trends.rolling.series[1], 0, false
    for _, segment in ipairs(series.segments) do
        T.eq(#segment.points, 1)
        for _, point in ipairs(segment.points) do count = count + 1; if point.value == 999 then peak = true end end
    end
    T.eq(count <= 24, true); T.eq(peak, true); T.eq(#snap.history, 301)
    T.eq(series.reduced, true)
end)

-- Catches silently hiding the separately recorded pellet/multi/DoT attack measurements.
T.test("accuracy details keep pellet measurements separate from ordinary shots", function()
    local snap = fixture(); snap.players.a.accuracyByMode.pellet = {shots = 4, hits = 3}
    local m = module().build(snap, {metric = "accuracy"})
    T.eq(m.charts[4].key, "accuracyMode:pellet")
    T.eq(m.charts[4].rows[1].numerator, 3); T.eq(m.charts[4].rows[1].denominator, 4)
    T.eq(m.charts[4].rows[1].text, "75.00%（3 / 4）")
    T.eq(m.charts[1].rows[1].value, nil)
end)

-- Catches allocating only segment endpoints and silently discarding all short isolated peaks.
T.test("sampling preserves a peak when many continuous segments share the budget", function()
    local snap = fixture(); snap.time = 99; snap.history = {}
    for i = 0, 99 do
        snap.history[#snap.history + 1] = {time = i, players = i % 10 == 9 and {} or {a = {
            damage = 0, rollingDps = i == 44 and 999 or 0, averageDps = 0, coverage = "complete"}}}
    end
    local m = module().build(snap, {}, {trendPointBudget = 24})
    local peak, count = false, 0
    for _, segment in ipairs(m.trends.rolling.series[1].segments) do
        for _, point in ipairs(segment.points) do count = count + 1; if point.value == 999 then peak = true end end
    end
    T.eq(peak, true); T.eq(count <= 24, true)
end)

-- Catches an event-frequency update stream rebuilding persistent charts every frame.
T.test("visible data refreshes at most once per second while selection stays immediate", function()
    local rendered, now = {}, 0
    local panel = module().new({clock = function() return now end, render = function(model) if model and model.charts[1] then rendered[#rendered + 1] = model.charts[1].rows[1].value end end})
    local snap = fixture(); snap.time = 0; snap.players.a.metrics.damage = 1
    panel:update(snap); panel:toggle()
    for _, pair in ipairs({{0.25, 2}, {0.5, 3}, {1, 4}}) do
        now = pair[1]
        local nextSnap = fixture(); nextSnap.time = pair[1]; nextSnap.players.a.metrics.damage = pair[2]
        panel:update(nextSnap)
    end
    T.eq(#rendered, 2); T.eq(rendered[1], 1); T.eq(rendered[2], 4)
    panel:selectMetric("damage"); T.eq(#rendered, 3)
end)

-- Catches freezing coverage/connection UI while the separate mission clock is paused.
T.test("paused mission time still permits a later coverage display refresh", function()
    local displayed, now = {}, 0
    local panel = module().new({clock = function() return now end, render = function(model)
        if model and model.charts[1] then displayed[#displayed + 1] = model.charts[1].rows[1].quality end
    end})
    panel:update(fixture()); panel:toggle()
    local changed = fixture(); changed.players.a.coverage.damage.status = "partial"
    now = 2; panel:update(changed)
    T.eq(#displayed, 2); T.eq(displayed[2], "部分数据")
end)

T.test("retained interrupted mission is labelled previous without rewriting its saved status", function()
    local snap = fixture(); snap.status = "active"
    local panel = module().new()
    panel:update(snap, {previous = true}); panel:toggle()
    T.eq(panel:model().missionLabel, "上一局")
    T.eq(panel:model().scopes[1].name, "上一局")
    T.eq(snap.status, "active")
    panel:update(snap, {previous = false})
    T.eq(panel:model().missionLabel, "本局")
end)

T.finish()
