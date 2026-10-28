package.path = "FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;" .. package.path
local T = require("stats_testlib")
local Panel = require("Panel")
local loaded, UMG = pcall(require, "PanelUmg")
local function scene()
    local p = {id = "a", name = "队友甲", color = "#56B4E9", connected = true,
        metrics = {damage = 1000}, coverage = {damage = {status = "complete"}}, damageBySource = {primary = 1000}}
    local m = Panel.build({schemaVersion = 1, sessionId = "A", time = 10, status = "active", players = {a = p}, playerOrder = {"a"}, encounters = {},
        history = {{time = 0, players = {a = {damage = 0, rollingDps = 0, averageDps = 0, coverage = "complete"}}},
            {time = 5, players = {}}, {time = 10, players = {a = {damage = 1000, rollingDps = 200, averageDps = 100, coverage = "complete"}}}}}, {metric = "damage"})
    T.eq(loaded, true, "UMG layout module available")
    return UMG.layout(m, {width = 1024, height = 768, dpiScale = 1})
end

-- Catches placing controls outside the user's real low-resolution viewport.
T.test("panel layout fits 1024 by 768 and keeps Chinese text readable", function()
    local s = scene()
    T.eq(s.width + 2 * s.margin <= 1024, true); T.eq(s.height + 2 * s.margin <= 768, true)
    for _, command in ipairs(s.commands) do
        T.eq(command.x >= 0 and command.y >= 0, true)
        if command.kind ~= "line" then T.eq(command.x + command.width <= s.width + 0.01, true); T.eq(command.y + command.height <= s.height + 0.01, true) end
        if command.kind == "text" then T.eq(command.size >= 12, true) end
    end
end)

-- Catches rendering a single continuous segment across deliberately missing DPS samples.
T.test("renderer geometry preserves trend gaps and accurate damage labels", function()
    local s, points, lines, value = scene(), 0, 0, false
    for _, command in ipairs(s.commands) do
        if command.role == "trend-point" then points = points + 1 end
        if command.role == "trend-line" then lines = lines + 1 end
        if command.role == "metric-value" and command.text == "1000.00" then value = true end
    end
    T.eq(points, 4); T.eq(lines, 0); T.eq(value, true)
end)

-- Catches a high-resolution model producing thousands of persistent line widgets at 1024x768.
T.test("viewport sampling imposes a finite line budget even for a dense model", function()
    T.eq(loaded, true)
    local points = {}
    for i = 0, 500 do points[#points + 1] = {time = i, value = i == 250 and 1000 or i % 7} end
    local graph = {label = "DPS", maximum = 1000, maximumTime = 500,
        series = {{id = "a", color = "#56B4E9", originalPoints = 501, segments = {{status = "complete", points = points}}}}}
    local m = {metricLabel = "伤害", scopeLabel = "本局", duration = 500, legend = {}, charts = {},
        trends = {rolling = graph, average = graph}, controls = "F8 隐藏"}
    local s, lines = UMG.layout(m, {width = 1024, height = 768, dpiScale = 1}), 0
    for _, c in ipairs(s.commands) do if c.role == "trend-line" then lines = lines + 1 end end
    T.eq(lines <= 50, true); T.eq(#points, 501)
end)

-- A recording UMG boundary models only the native calls captured by the runtime
-- smoke test. Assertions inspect the resulting scene/lifecycle, not mock call presence.
local function withEngine(run)
    local engine=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
    local ok, err = pcall(run, engine)
    engine.restore()
    if not ok then error(err, 0) end
end
local function simpleModel(amount)
    return Panel.build({schemaVersion = 1, sessionId = "A", time = 1, status = "active", playerOrder = {"a"}, encounters = {}, history = {},
        players = {a = {id = "a", name = "甲", color = "#56B4E9", connected = true, metrics = {damage = amount}, coverage = {damage = {status = "complete"}}}}}, {metric = "damage"})
end

T.test("persistent renderer reuses nodes across data updates and removes the hidden host", function()
    withEngine(function(engine)
        local renderer = UMG.new({getController = function() return engine.controller end, viewport = function() return {width = 1024, height = 768, dpiScale = 1} end})
        local first = simpleModel(1000)
        T.eq(renderer:render(first), true)
        local count = engine.constructed
        T.eq(engine.hosts[1].onScreen, true)
        T.eq(renderer:render(first), false); T.eq(engine.constructed, count)
        renderer:render(simpleModel(2000)); T.eq(engine.constructed, count)
        local found = false
        for _, entry in ipairs(renderer.textPool) do if entry.widget.text == "2000.00" then found = true end end
        T.eq(found, true)
        renderer:hide(); T.eq(engine.hosts[1].onScreen, false)
        renderer:render(first); T.eq(engine.constructed, count); T.eq(engine.hosts[1].onScreen, true)
    end)
end)

-- Catches retaining a widget owned by the previous map's local player controller.
T.test("map owner changes rebuild the host even when the displayed last mission is unchanged", function()
    withEngine(function(engine)
        local renderer = UMG.new({getController = function() return engine.controller end, viewport = function() return {width = 1024, height = 768, dpiScale = 1} end})
        local model = simpleModel(1000)
        renderer:render(model)
        local oldCalls=0;local old=renderer.host
        old.SetVisibility=function() oldCalls=oldCalls+1;error('retired widget') end
        old.RemoveFromParent=old.SetVisibility
        engine.newController()
        renderer:render(model)
        T.eq(#engine.hosts, 2);T.eq(oldCalls,0)
        T.eq(engine.hosts[2].controller, engine.controller); T.eq(engine.hosts[2].onScreen, true)
    end)
end)
T.test('sRGB design colors become linear values at the native Slate boundary',function()
    withEngine(function(engine)
        local renderer=UMG.new({getController=function() return engine.controller end,passive=true,
            viewport=function() return {width=1024,height=768,dpiScale=1} end,
            layout=function() return {width=100,height=30,margin=16,dpiScale=1,commands={
                {kind='bar',x=0,y=0,width=100,height=30,fraction=1,color='#808080',alpha=1}}} end})
        renderer:render({})
        T.near(renderer.barPool[1].widget.fill.R,0.21586050011389926,'sRGB gray is converted to linear red')
        T.near(renderer.barPool[1].widget.fill.G,0.21586050011389926,'sRGB gray is converted to linear green')
    end)
end)
T.test('native captions have padding clearance and are aligned only on creation',function()
    withEngine(function(engine)
        local renderer=UMG.new({getController=function() return engine.controller end,
            viewport=function() return {width=1280,height=720,dpiScale=1} end})
        renderer:render(simpleModel(100))
        local entry=renderer.mouse.buttons.chartTitle_1
        T.eq(entry.label.Slot.padding.Top,0);T.eq(entry.label.Slot.padding.Bottom,0)
        T.eq(entry.captionAligned,true)
        T.eq(entry.slot.size.Y>=entry.label.Font.Size*1.6+8,true,'button height must clear the game font line box')
    end)
end)

T.finish()
