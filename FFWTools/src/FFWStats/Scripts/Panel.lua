-- Chinese, engine-independent view model/controller for Stats snapshots.
-- Importing this module registers no keys and creates no engine objects.
local Panel = {}
local L = require('Locale')
local Contribution=require('Contribution')
local Controller = {}; Controller.__index = Controller
local definitions = {
    damage = {"造成伤害", "点"}, incomingDamage = {"累计承伤", "点"}, kills = {"击杀", "次"},
    healing = {"有效治疗", "点"}, revives = {"复活队友", "次"}, deaths = {"死亡", "次"},
    rollingDps = {"最近 5 秒 DPS", "点/秒"}, averageDps = {"本局平均 DPS", "点/秒"}, damageShare = {"团队伤害占比", "%", true},
    hpLoss = {"实际生命损失", "点"}, shieldAbsorbed = {"护盾吸收", "点"}, largestHit = {"最高单次承伤", "点"},
    eliteKills = {"精英击杀", "次"}, bossKills = {"Boss 击杀", "次"}, assists = {"助攻", "次"},
    selfHealing = {"自疗", "点"}, teamHealing = {"治疗队友", "点"}, healingAttempted = {"发生治疗", "点"}, overhealing = {"溢出治疗", "点"},
    shieldGained = {"获得有效护盾", "点"}, shieldGranted = {"给予护盾", "点"}, shieldOvergain = {"溢出护盾", "点"},
    accuracy = {"普通射击命中率", "%", true}, shots = {"普通射击次数", "次"}, hits = {"有效命中次数", "次"},
    ammo = {"消耗弹药", "发"}, reloads = {"换弹", "次"}, downs = {"幽灵/倒地次数", "次"}, rescued = {"被救", "次"},
    downDuration = {"幽灵/倒地时长", "秒"}, aliveDuration = {"存活时长", "秒"},
}
local groups = {
    overview = {"概览", "damage", "incomingDamage", "kills", "healing", "revives", "deaths"},
    teamContribution = {'团队贡献'},
    damage = {"伤害", "damage", "rollingDps", "averageDps", "damageShare"},
    incomingDamage = {"承伤", "incomingDamage", "hpLoss", "shieldAbsorbed", "largestHit"},
    kills = {"击杀与助攻", "kills", "eliteKills", "bossKills", "assists"},
    healing = {"治疗", "healing", "selfHealing", "teamHealing", "healingAttempted", "overhealing"},
    shieldGained = {"护盾", "shieldGained", "shieldGranted", "shieldOvergain"},
    accuracy = {"命中", "accuracy", "shots", "hits"}, ammo = {"弹药", "ammo", "reloads"},
    revives = {"生存与救援", "revives", "deaths", "downs", "rescued", "downDuration", "aliveDuration"},
    damageSources = {"伤害来源"}, incomingSources = {"承伤来源"},
}
Panel.metricOrder = {"overview", "teamContribution", "damage", "damageSources", "incomingDamage", "incomingSources", "kills", "healing", "shieldGained", "accuracy", "ammo", "revives"}
Panel.defaultHotkeys = {toggle = "F8", previousMetric = "PAGE_UP", nextMetric = "PAGE_DOWN", previousScope = "HOME", nextScope = "END", nextPage = false}
local function metricGroup(metric)
    local selected = groups[metric] and metric or nil
    if not selected then
        for _, id in ipairs(Panel.metricOrder) do
            if id ~= 'overview' then
                for i = 2, #groups[id] do if groups[id][i] == metric then selected = id; break end end
            end
            if selected then break end
        end
    end
    return selected or 'overview'
end
function Panel.metricTabs(metric)
    local selected,tabs=metricGroup(metric),{}
    for _, id in ipairs(Panel.metricOrder) do
        tabs[#tabs + 1] = {id = id, label = id=='teamContribution' and L.choose('团队贡献','Contribution') or L.text(groups[id][1]), selected = id == selected}
    end
    return tabs
end
local sourceOrder = {"primary", "secondary", "spell", "melee", "dot", "unknown"}
local sourceLabels = {primary = "主武器", secondary = "副武器", spell = "法术", melee = "近战", dot = "持续伤害", unknown = "来源未分类"}
local function number(value) return type(value) == "number" and value == value and value >= 0 and value < math.huge end
local function exact(value) return string.format("%.17g", value) end
local function display(value,integer)
    return string.format(integer and '%.0f' or '%.2f',value)
end
local function coverage(p, key)
    local c = (p.coverage or {})[key]
    if c then return c.status or "unavailable" end
    if key == "rollingDps" or key == "averageDps" then return coverage(p, "damage") end
    if key == "accuracy" then
        local a, b = coverage(p, "shots"), coverage(p, "hits")
        if a == "unavailable" or b == "unavailable" then return "unavailable" end
        return a == "complete" and b == "complete" and "complete" or "partial"
    end
    return "unavailable"
end
local function row(p, key, source, incoming)
    local m = p.metrics or {}
    local value, status = m[key], coverage(p, key)
    local numerator, denominator, share
    if key == "accuracy" then
        numerator, denominator = m.hits, m.shots
        value = number(numerator) and number(denominator) and denominator > 0 and numerator / denominator or nil
    end
    if source then
        local map = incoming and p.incomingBySource or p.damageBySource
        value = number(m[key]) and map and (map[source] or 0) or nil
        if number(value) and m[key] > 0 then share = value / m[key] end
    end
    if not number(value) or status == "unavailable" then value, status = nil, "unavailable" end
    local text = "不可用"
    if value ~= nil then
        if key == "accuracy" then text = string.format(L.choose('%.2f%%（%s / %s）','%.2f%% (%s / %s)'), value * 100, display(numerator,true), display(denominator,true))
        elseif key == "damageShare" then text = p.damageShareSolo and '100%' or string.format("%.2f%%", value * 100)
        else text = display(value,definitions[key][2]=='次' or definitions[key][2]=='发') end
        if share then text = text .. string.format(L.choose('（%.2f%%）',' (%.2f%%)'), share * 100) end
    end
    return {id = p.id, name = p.name, color = p.color, value = value, text = text,
        exactText = value ~= nil and exact(value) or "不可用", status = status,
        quality = status == "partial" and "部分数据" or status == "unavailable" and "不可用" or "完整",
        numerator = numerator, denominator = denominator, share = share}
end
local function chart(scope, key, source, incoming)
    local def = definitions[key]
    local result = {key = source and "source:" .. source or key, label = source and (sourceLabels[source] or source) or def[1],
        unit = def[2], zero = 0, maximum = 0, rows = {}, selectMetric = not source and key or nil,
        integer = def[2]=='次' or def[2]=='发'}
    for _, id in ipairs(scope.playerOrder or {}) do
        local p = scope.players[id]
        if p then
            local r = row(p, key, source, incoming); result.rows[#result.rows + 1] = r
            if r.value and r.value > result.maximum then result.maximum = r.value end
        end
    end
    if def[3] and not source then result.maximum = 1 end
    for _, r in ipairs(result.rows) do if r.value ~= nil then r.fraction = result.maximum > 0 and r.value / result.maximum or 0 end end
    return result
end
local function reduce(points, limit)
    if #points <= limit then return points end
    local result = {points[1]}
    if limit == 3 then
        local peak = 2
        for i = 3, #points - 1 do if points[i].value > points[peak].value then peak = i end end
        result[#result + 1] = points[peak]
    elseif limit >= 4 then
        local buckets = math.floor((limit - 2) / 2)
        for bucket = 1, buckets do
            local first = 2 + math.floor((bucket - 1) * (#points - 2) / buckets)
            local last = 1 + math.floor(bucket * (#points - 2) / buckets)
            local low, high = first, first
            for i = first + 1, last do
                if points[i].value < points[low].value then low = i end
                if points[i].value > points[high].value then high = i end
            end
            if low > high then low, high = high, low end
            result[#result + 1] = points[low]
            if high ~= low then result[#result + 1] = points[high] end
        end
    end
    result[#result + 1] = points[#points]
    return result
end
local function thinSegments(segments, limit)
    if #segments <= limit then return segments end
    local result = {segments[1]}
    local function peak(segment)
        local maximum = 0
        for _, p in ipairs(segment.points) do maximum = math.max(maximum, p.value) end
        return maximum
    end
    for bucket = 1, limit - 2 do
        local first = 2 + math.floor((bucket - 1) * (#segments - 2) / (limit - 2))
        local last = 1 + math.floor(bucket * (#segments - 2) / (limit - 2))
        local best = first
        for i = first + 1, last do if peak(segments[i]) > peak(segments[best]) then best = i end end
        result[#result + 1] = segments[best]
    end
    result[#result + 1] = segments[#segments]
    return result
end
function Panel.sampleSeries(source, budget)
    budget = math.max(12, math.floor(budget or 24))
    local series = {id = source.id, name = source.name, color = source.color, originalPoints = source.originalPoints, segments = {}}
    local availablePoints = 0
    for _, segment in ipairs(source.segments) do
        series.segments[#series.segments + 1] = {status = segment.status, points = segment.points}
        availablePoints = availablePoints + #segment.points
    end
    series.originalPoints = series.originalPoints or availablePoints
    -- Reserve first/peak/last for every selected continuous span. Selecting whole
    -- spans can omit detail, but never draws a line over a real observation gap.
    series.segments = thinSegments(series.segments, math.floor(budget / 3))
    local allocated, keptPoints = 0, 0
    for _, segment in ipairs(series.segments) do keptPoints = keptPoints + #segment.points end
    for _, segment in ipairs(series.segments) do
        segment.limit = math.min(#segment.points, math.max(3, math.floor(budget * #segment.points / math.max(1, keptPoints))))
        allocated = allocated + segment.limit
    end
    while allocated > budget do
        local largest
        for _, segment in ipairs(series.segments) do
            if segment.limit > 3 and (not largest or segment.limit > largest.limit) then largest = segment end
        end
        if not largest then break end
        largest.limit = largest.limit - 1; allocated = allocated - 1
    end
    local rendered = 0
    for _, segment in ipairs(series.segments) do segment.points = reduce(segment.points, segment.limit); segment.limit = nil; rendered = rendered + #segment.points end
    series.reduced = source.reduced or rendered < series.originalPoints
    return series
end
local function trend(scope, key, start, duration, budget)
    local result = {key = key, label = key == "rollingDps" and "最近 5 秒 DPS" or "本局平均 DPS", unit = "点/秒",
        minimum = 0, maximum = 0, minimumTime = 0, maximumTime = duration, series = {}}
    for _, id in ipairs(scope.playerOrder or {}) do
        local p = scope.players[id]
        if p then
            local series = {id = id, name = p.name, color = p.color, segments = {}, originalPoints = 0}
            local current
            for _, sample in ipairs(scope.history or {}) do
                local v = sample.players and sample.players[id]
                if v and number(v[key]) and sample.time >= start and sample.time <= start + duration then
                    local status = v.coverage or "partial"
                    if not current or current.status ~= status then current = {status = status, points = {}}; series.segments[#series.segments + 1] = current end
                    current.points[#current.points + 1] = {time = sample.time - start, value = v[key]}
                    series.originalPoints = series.originalPoints + 1
                    if v[key] > result.maximum then result.maximum = v[key] end
                else current = nil end
            end
            result.series[#result.series + 1] = Panel.sampleSeries(series, budget)
        end
    end
    return result
end
local function scopes(snapshot, previous)
    local result = {{id = "mission", name = (previous or snapshot.status == "ended") and "上一局" or "本局", startTime = 0}}
    local list = {}
    for id, encounter in pairs(snapshot.encounters or {}) do list[#list + 1] = {id = id, name = encounter.name, startTime = encounter.startTime} end
    table.sort(list, function(a, b) return a.startTime == b.startTime and a.id < b.id or a.startTime < b.startTime end)
    for _, entry in ipairs(list) do result[#result + 1] = entry end
    return result
end
function Panel.build(snapshot, selection, options)
    selection, options = selection or {}, options or {}
    local metric = selection.metric or "overview"
    local result = {visible = true, title = "战斗统计", metric = metric, tabs = Panel.metricTabs(metric),
        legend = {}, charts = {}, scopeId = selection.scopeId or "mission"}
    if metric=='teamContribution' then result.scopeId='mission';result.scopeLocked=true end
    if not snapshot then
        result.title=L.text(result.title)
        result.message=options.emptyMessage and options.emptyMessage() or L.text("尚无任务统计")
        return result
    end
    if snapshot.schemaVersion ~= 1 then result.title=L.text(result.title);result.message = L.text("统计数据格式不可用"); return result end
    local scope = result.scopeId == "mission" and snapshot or (snapshot.encounters or {})[result.scopeId]
    if not scope then scope, result.scopeId = snapshot, "mission" end
    result.sessionId, result.missionLabel = snapshot.sessionId, (options.previous or snapshot.status == "ended") and "上一局" or "本局"
    result.scopeLabel = result.scopeId == "mission" and result.missionLabel or scope.name
    result.duration = result.scopeId == "mission" and snapshot.time or scope.duration
    result.scopes, result.metricLabel = scopes(snapshot, options.previous), (groups[metric] or definitions[metric] or {"指标不可用"})[1]
    if metric=='teamContribution' then result.metricLabel=L.choose('团队贡献','Team contribution') end
    for _, id in ipairs(scope.playerOrder or {}) do
        local p = scope.players[id]
        if p then result.legend[#result.legend + 1] = {id = id, name = p.name, color = p.color, isSelf = id == options.selfPlayerId, connected = p.connected} end
    end
    if metric=='teamContribution' then
        result.contribution=Contribution.build(snapshot,{selfPlayerId=options.selfPlayerId,
            stale=not options.previous and snapshot.status=='active' and options.isStale and options.isStale()==true or false})
    elseif metric == "damageSources" or metric == "incomingSources" then
        local incoming, categories, found = metric == "incomingSources", {}, {}
        if not incoming then for _, source in ipairs(sourceOrder) do categories[#categories + 1] = source; found[source] = true end end
        local extra = {}
        for _, p in pairs(scope.players or {}) do
            for source in pairs((incoming and p.incomingBySource or p.damageBySource) or {}) do if not found[source] then found[source] = true; extra[#extra + 1] = source end end
        end
        table.sort(extra); for _, source in ipairs(extra) do categories[#categories + 1] = source end
        for _, source in ipairs(categories) do result.charts[#result.charts + 1] = chart(scope, incoming and "incomingDamage" or "damage", source, incoming) end
        if #result.charts == 0 then result.message = "承伤来源不可用" end
    elseif groups[metric] then
        for i = 2, #groups[metric] do result.charts[#result.charts + 1] = chart(scope, groups[metric][i]) end
    elseif definitions[metric] then result.charts[1] = chart(scope, metric)
    else result.message = "指标不可用" end
    if metric == "accuracy" then
        for _, mode in ipairs({{"pellet", "散弹有效攻击"}, {"multi", "多段有效攻击"}, {"dot", "持续攻击记录"}}) do
            local detail = {key = "accuracyMode:" .. mode[1], label = mode[2], unit = "%", zero = 0, maximum = 1, rows = {}}
            for _, id in ipairs(scope.playerOrder or {}) do
                local p = scope.players[id]
                local r = row(p, "accuracy")
                local counts = (p.accuracyByMode or {})[mode[1]]
                r.value, r.fraction, r.numerator, r.denominator, r.status, r.quality, r.text, r.exactText = nil, nil, nil, nil, "unavailable", "不可用", "不可用", "不可用"
                if counts and number(counts.hits) and number(counts.shots) and counts.shots > 0 then
                    r.value, r.numerator, r.denominator = counts.hits / counts.shots, counts.hits, counts.shots
                    r.fraction, r.status, r.quality = r.value, "partial", "部分数据"
                    r.text, r.exactText = string.format(L.choose('%.2f%%（%s / %s）','%.2f%% (%s / %s)'), r.value * 100, display(counts.hits,true), display(counts.shots,true)), exact(r.value)
                end
                detail.rows[#detail.rows + 1] = r
            end
            result.charts[#result.charts + 1] = detail
        end
    end
    local start = result.scopeId == "mission" and 0 or scope.startTime
    local budget = math.max(12, options.trendPointBudget or 24)
    if not result.contribution then
        result.trends = {rolling = trend(scope, "rollingDps", start, result.duration, budget), average = trend(scope, "averageDps", start, result.duration, budget)}
        if result.scopeId ~= "mission" then result.trends.average.label = "Boss 平均 DPS" end
    end
    result.page = selection.page or 1
    result.chartsPerPage=#result.legend>4 and 2 or #result.legend>2 and 4 or 6
    result.pageCount = math.max(1, math.ceil(result.contribution and #result.contribution.rows/4 or #result.charts/result.chartsPerPage))
    result.page = ((result.page - 1) % result.pageCount) + 1
    local keys = options.hotkeys or {}
    result.controls = string.format(L.text("%s 隐藏   %s/%s 指标   %s/%s 区间   %s 分项页 %d/%d"),
        keys.toggle or "F8", keys.previousMetric or "PgUp", keys.nextMetric or "PgDn", keys.previousScope or "Home", keys.nextScope or "End", keys.nextPage or L.choose('鼠标','Mouse'), result.page, result.pageCount)
    if result.contribution then
        result.controls=string.format(L.choose('%s 隐藏   %s/%s 指标   %s 排行页 %d/%d',
            '%s hide   %s/%s metrics   %s ranking page %d/%d'),keys.toggle or 'F8',
            keys.previousMetric or 'PgUp',keys.nextMetric or 'PgDn',keys.nextPage or L.choose('鼠标','Mouse'),result.page,result.pageCount)
    end
    for _,key in ipairs({'title','metricLabel','missionLabel','controls','message'}) do
        if result[key] then result[key]=L.text(result[key]) end
    end
    if result.scopeId=='mission' then result.scopeLabel=L.text(result.scopeLabel) end
    for _,scopeEntry in ipairs(result.scopes or {}) do
        if scopeEntry.id=='mission' then scopeEntry.name=L.text(scopeEntry.name) end
    end
    for _,c in ipairs(result.charts) do
        c.label=L.text(c.label);c.unit=L.text(c.unit)
        for _,r in ipairs(c.rows) do
            r.text=L.text(r.text);r.exactText=L.text(r.exactText);r.quality=L.text(r.quality)
        end
    end
    for _,t in pairs(result.trends or {}) do t.label=L.text(t.label);if t.unit then t.unit=L.text(t.unit) end end
    return result
end
function Panel.new(options)
    return setmetatable({options = options or {}, visible = false, metric = "overview", scopeId = "mission", page = 1, dirty = true}, Controller)
end
function Controller:model()
    if not self.visible then return nil end
    if self.showConnection and self.options.connection then
        local connection=self.options.connection:model()
        return {connection=connection,page=connection.page,pageCount=connection.pageCount,metric=self.metric}
    end
    if self.showSettings and self.options.hudSettings then
        local settings=self.options.hudSettings:model(self.settingsPage or 1)
        return {settings=settings,page=settings.page,pageCount=settings.pageCount,metric=self.metric}
    end
    local stale=self.metric=='teamContribution' and not self.options.previous and self.snapshot and self.snapshot.status=='active'
        and self.options.isStale and self.options.isStale()==true or false
    if self.dirty or self.localeRevision~=L.revision or self.lastStale~=stale then
        self.cached = Panel.build(self.snapshot, self, self.options); self.dirty = false;self.localeRevision=L.revision
        self.lastStale=stale
    end
    return self.cached
end
function Controller:refresh()
    if self.options.render then self.options.render(self:model()) end
    if self.visible and self.snapshot then self.lastRefresh = {wallTime = (self.options.clock or os.time)(), sessionId = self.snapshot.sessionId, status = self.snapshot.status} end
end
function Controller:update(snapshot, display)
    local previous = display and display.previous == true or false
    local labelChanged = self.options.previous ~= previous
    if self.snapshot == snapshot and not labelChanged then return false end
    self.options.previous = previous
    self.snapshot, self.dirty = snapshot, true
    if self.scopeId ~= "mission" and (not snapshot or not (snapshot.encounters or {})[self.scopeId]) then self.scopeId = "mission" end
    local last = self.lastRefresh
    local now = (self.options.clock or os.time)()
    if self.visible and (labelChanged or not snapshot or not last or snapshot.sessionId ~= last.sessionId or snapshot.status ~= last.status
        or now < last.wallTime or now - last.wallTime >= math.max(1, self.options.refreshSeconds or 1)) then self:refresh() end
    return true
end
function Controller:toggle()
    self.visible = not self.visible; self:refresh(); return self.visible
end
function Controller:selectMetric(metric)
    if not groups[metric] and not definitions[metric] then return false end
    if metric=='teamContribution' then self.scopeId='mission' end
    self.showSettings=false;self.showConnection=false
    self.metric, self.page, self.dirty = metric, 1, true; self:refresh(); return true
end
function Controller:cycleMetric(step)
    local index = 1
    local group=metricGroup(self.metric)
    for i, key in ipairs(Panel.metricOrder) do if key == group then index = i end end
    return self:selectMetric(Panel.metricOrder[((index - 1 + step) % #Panel.metricOrder) + 1])
end
function Controller:selectScope(id)
    if self.metric=='teamContribution' and id~='mission' then return false end
    if id ~= "mission" and (not self.snapshot or not (self.snapshot.encounters or {})[id]) then return false end
    self.scopeId, self.page, self.dirty = id, 1, true; self:refresh(); return true
end
function Controller:cycleScope(step)
    if not self.snapshot then return false end
    local list, index = scopes(self.snapshot, self.options.previous), 1
    for i, entry in ipairs(list) do if entry.id == self.scopeId then index = i end end
    return self:selectScope(list[((index - 1 + step) % #list) + 1].id)
end
function Controller:nextPage(step)
    local model=self:model()
    if self.showConnection then self.options.connection:nextPage(step);self:refresh();return end
    if self.showSettings then
        self.settingsPage=((model.page or 1)-1+(step or 1))%model.pageCount+1;self:refresh();return
    end
    self.page, self.dirty = ((model and model.page or self.page)-1+(step or 1)) % (model and model.pageCount or 1)+1, true
    self:refresh()
end
function Controller:mouse(action,value)
    if not self.visible then return false end
    if action=='toggleConnection' and self.options.connection then self.showConnection=not self.showConnection;self.showSettings=false;self:refresh()
    elseif action=='networkMode' and self.options.connection then self.options.connection:setMode(value);self:refresh()
    elseif action=='networkStart' and self.options.connection then
        local read=self.options.readInput or function()end
        self.options.connection:start{address=read('network-address'),port=read('network-port'),token=read('network-token')};self:refresh()
    elseif action=='networkStop' and self.options.connection then self.options.connection:stop();self:refresh()
    elseif action=='networkPair' and self.options.connection then self.options.connection:pair(value);self:refresh()
    elseif action=='networkRevoke' and self.options.connection then self.options.connection:revoke(value);self:refresh()
    elseif action=='toggleSettings' and self.options.hudSettings then self.showSettings=not self.showSettings;self.showConnection=false;self:refresh()
    elseif action=='toggleHud' and self.options.hudSettings then self.options.hudSettings:toggle(value);self:refresh()
    elseif action=='resetHud' and self.options.hudSettings then self.options.hudSettings:reset();self:refresh()
    elseif action=='selectMetric' then return self:selectMetric(value)
    elseif action=='close' then self.visible=false;self:refresh()
    elseif action=='previousMetric' then self:cycleMetric(-1)
    elseif action=='nextMetric' then self:cycleMetric(1)
    elseif action=='previousScope' then self:cycleScope(-1)
    elseif action=='nextScope' then self:cycleScope(1)
    elseif action=='previousPage' then self:nextPage(-1)
    elseif action=='nextPage' then self:nextPage(1)
    else return false end
    return true
end
function Controller:bindKeys(binding)
    if self.keysBound then return false, "keys already bound" end
    local hotkeys = {}
    for action, name in pairs(Panel.defaultHotkeys) do hotkeys[action] = name end
    for action, name in pairs(self.options.hotkeys or {}) do hotkeys[action] = name end
    local actions = {toggle = function() self:toggle() end, previousMetric = function() self:cycleMetric(-1) end,
        nextMetric = function() self:cycleMetric(1) end, previousScope = function() self:cycleScope(-1) end,
        nextScope = function() self:cycleScope(1) end, nextPage = function() self:nextPage() end}
    for action, name in pairs(hotkeys) do
        if name and actions[action] then
            assert(binding.Key[name], "unknown key " .. tostring(name))
            binding.register(binding.Key[name], function()
                if action == "toggle" or self.visible then binding.execute(actions[action]) end
            end)
        end
    end
    self.keysBound = true; return true
end
return Panel
