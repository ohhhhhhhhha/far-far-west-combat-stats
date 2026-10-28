-- Persistent CanvasPanel/TextBlock/ProgressBar renderer. No OnPaint, frame hook or timer.
-- Primitive widget bindings were exercised by the manual runtime smoke.
-- Viewport-size/DPI queries still need the separate confirmation in stats-panel-notes.md.
local Panel = require("Panel")
local L = require('Locale')
local UMG = {}
-- Charcoal, leather and brass match the game's stylized western equipment;
-- player colors still carry the comparison data rather than decoration.
local palette = {background = '#28232D', text = '#F4E7CA', muted = '#BCB1A3', grid = '#51444B',
    accent = '#E2B969', frame = '#9A7349', shadow = '#17141D', wood = '#563E2E', button = '#44363B'}
local function short(text, length)
    text = tostring(text or "")
    local ok, count = pcall(utf8.len, text)
    if not ok or not count or count <= length then return text end
    return text:sub(1, utf8.offset(text, length + 1) - 1) .. "…"
end
local function number(value,integer)
    return string.format(integer and '%.0f' or '%.2f',value)
end
local function axisNumber(value)
    if value>=1000000 then return string.format('%.2fM',value/1000000) end
    if value>=10000 then return string.format('%.2fk',value/1000) end
    return number(value)
end
local function duration(seconds) return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60)) end
function UMG.layout(model, viewport)
    viewport = viewport or {width = 1024, height = 768, dpiScale = 1}
    -- Keep controls on a usable design canvas; CanvasView scales the entire
    -- scene into smaller physical windows instead of creating negative slots.
    local width, height = math.min(1180, math.max(1024,viewport.width) - 48), math.min(760, math.max(720,viewport.height) - 48)
    local scene = {width = width, height = height, margin = 24, dpiScale = viewport.dpiScale or 1, commands = {}}
    local commands = scene.commands
    local function text(value, x, y, w, size, tint, role)
        local _,breaks=tostring(value):gsub('\n','')
        commands[#commands + 1] = {kind = "text", text = value, x = x, y = y, width = w, height = size * 1.6 * (breaks+1), size = size, color = tint or palette.text, role = role}
    end
    local function bar(x, y, w, h, fraction, tint, role, alpha)
        commands[#commands + 1] = {kind = "bar", x = x, y = y, width = w, height = h, fraction = fraction, color = tint, role = role, alpha = alpha or 1}
    end
    local function line(x, y, endX, endY, tint, role, alpha)
        commands[#commands + 1] = {kind = "line", x = x, y = y, endX = endX, endY = endY, width = math.sqrt((endX - x)^2 + (endY - y)^2), height = 2,
            color = tint, role = role, alpha = alpha or 1}
    end
    local function button(id,label,x,y,w,enabled,extra)
        local command={kind='button',id=id,action=id,text=label,x=x,y=y,width=w,height=36,size=14,enabled=enabled~=false}
        for key,value in pairs(extra or {}) do command[key]=value end
        command.backgroundColor=command.selected and palette.accent or palette.button
        command.textColor=command.selected and palette.shadow or palette.text
        commands[#commands+1]=command
    end
    bar(0,0,width,height,1,palette.shadow,'background',.98)
    bar(2,2,width-4,height-4,1,palette.frame,'brass-frame')
    bar(6,6,width-12,height-12,1,palette.background,'panel-field',.98)
    bar(6,6,width-12,52,1,palette.wood,'wood-header')
    bar(6,58,width-12,2,1,palette.accent,'header-edge',.7)
    bar(6,height-58,width-12,52,1,palette.shadow,'footer-field',.75)
    for _,point in ipairs({{8,8},{width-12,8},{8,height-12},{width-12,height-12}}) do
        bar(point[1],point[2],4,4,1,palette.accent,'frame-pin',.8)
    end
    text(L.text("战斗统计"), 20, 10, 180, 22, palette.text, "title")
    button('close',L.choose('关闭','Close'),width-104,14,84)
    button('toggleSettings',L.choose('显示设置','HUD options'),width-245,14,128,true,{selected=model and model.settings~=nil})
    if model and model.settings then
        local settings=model.settings
        text(L.choose('左上角显示项目','Corner HUD contents'),20,84,width-40,20,palette.accent)
        local cell=(width-58)/2
        for i,row in ipairs(settings.rows) do
            local x=20+((i-1)%2)*(cell+18);local y=128+math.floor((i-1)/2)*44
            button('hud-'..row.id,(row.selected and '[x] ' or '[ ] ')..row.label,x,y,cell,true,
                {action='toggleHud',value=row.id,selected=row.selected,height=38,size=15})
        end
        button('previousPage',L.choose('< 上一页','< Previous'),20,height-108,144,settings.page>1)
        button('nextPage',L.choose('下一页 >','Next >'),172,height-108,144,settings.page<settings.pageCount)
        text(string.format('%d / %d',settings.page,settings.pageCount),334,height-101,140,14,palette.muted)
        button('resetHud',L.choose('恢复默认','Reset defaults'),width-192,height-108,172)
        text(settings.message,20,height-48,width-40,13,palette.muted)
        return scene
    end
    local available=model and (model.trends~=nil or model.contribution~=nil)
    button('previousMetric',L.choose('< 指标','< Metric'),20,68,104,available)
    button('nextMetric',L.choose('指标 >','Metric >'),130,68,104,available)
    button('previousScope',L.choose('< 区间','< Scope'),254,68,104,available and not model.scopeLocked)
    button('nextScope',L.choose('区间 >','Scope >'),364,68,104,available and not model.scopeLocked)
    local paging=available and (model.pageCount or 1)>1
    button('previousPage',L.choose('< 分项页','< Page'),488,68,104,paging)
    button('nextPage',L.choose('分项页 >','Page >'),598,68,104,paging)
    text(string.format('%d / %d',model and model.page or 1,model and model.pageCount or 1),718,75,width-738,14,palette.muted,'page-number')
    local inner, gap = width - 40, 18
    local tabs = model and model.tabs or Panel.metricTabs(model and model.metric or 'overview')
    local tabColumns, tabGap, tabTop = 6, 6, 114
    local tabWidth = (inner - (tabColumns - 1) * tabGap) / tabColumns
    for i,tab in ipairs(tabs) do
        button('tab_'..tab.id,tab.label,20+((i-1)%tabColumns)*(tabWidth+tabGap),
            tabTop+math.floor((i-1)/tabColumns)*38,tabWidth,available,
            {action='selectMetric',value=tab.id,selected=tab.selected,height=32,size=13,role='metric-tab'})
    end
    local legendTop = tabTop + math.ceil(#tabs / tabColumns) * 38 + 8
    if not model or model.message and not model.trends and not model.contribution then
        text(model and model.message or L.text("尚无任务统计"), 20, legendTop + 8, width - 40, 18)
        return scene
    end
    text(model.metricLabel, 200, 18, 200, 16, palette.accent)
    text(short(model.scopeLabel, 16) .. "  " .. duration(model.duration), width - 470, 18, 210, 16)
    if model.contribution then
        local board=model.contribution
        text(L.choose('团队贡献参考占比','Recorded team contribution'),20,legendTop,inner,18,palette.accent)
        text(board.message or string.format(L.choose('已启用权重 %d / 100','Active weights: %d / 100'),board.activeWeight),width-270,legendTop+3,250,12,palette.muted)
        local groupWidth=inner/5
        for i,g in ipairs(board.groups) do
            local x=20+(i-1)*groupWidth
            bar(x,legendTop+34,9,9,1,g.color,'contribution-legend')
            text(g.label..' '..g.weight..'%',x+15,legendTop+29,groupWidth-18,12,palette.text)
        end
        local first=((model.page or 1)-1)*4+1
        local count=math.min(4,#board.rows-first+1)
        local rowHeight=math.min(74,math.floor((height-legendTop-209)/math.max(1,count)))
        for i=0,count-1 do
            local row=board.rows[first+i]
            local y=legendTop+64+i*rowHeight
            text(row.rank and tostring(row.rank) or '—',22,y,30,20,palette.accent,'contribution-rank')
            text(short(row.name,12)..(row.isSelf and L.choose('（你）',' (you)') or '')..(row.connected==false and L.choose(' 离线',' offline') or ''),
                62,y+2,inner-210,16,row.color,'player-name')
            text(row.scoreText..(row.score and '%' or '')..(row.score and row.partial and '*' or ''),width-160,y-2,140,22,palette.text,'contribution-score')
            local x,w=62,inner-200
            bar(x,y+29,w,10,1,palette.grid,'contribution-track')
            local offset,detail=0,{}
            for _,g in ipairs(board.groups) do
                local points=row.groups[g.id]
                if points and points>0 then bar(x+offset,y+29,w*points/100,10,1,g.color,'contribution-segment');offset=offset+w*points/100 end
                detail[#detail+1]=g.label..' '..(points and string.format('%.2f',points) or '—')
            end
            text(table.concat(detail,'  /  '),62,y+46,inner-44,12,palette.muted)
        end
        text(L.choose('伤害沿用结算值（含过量）；DPS 峰值采用5秒窗口、每秒采样。',
            'Damage includes overkill. DPS peaks use a 5-second window, sampled once per second.'),20,height-135,inner,12,palette.muted)
        text(L.choose('击杀10 / 精英3 / Boss5 / 助攻2；队友治疗12 / 自疗3 / 给予护盾5；复活15。',
            'Kills 10 / elites 3 / bosses 5 / assists 2; team healing 12 / self healing 3 / shields granted 5; revives 15.'),20,height-113,inner,12,palette.muted)
        text(L.choose('承伤、溢出治疗、弹药和 DPS 峰值不加分；死亡/倒地通过存活占比体现。',
            'Damage taken, overhealing, ammo and peak DPS add no points. Survival reflects time alive.'),20,height-91,inner,12,palette.muted)
        text(board.note,20,height-49,inner,12,palette.muted)
        text(model.controls or L.text('F8 隐藏'),20,height-26,inner,12,palette.accent)
        return scene
    end
    local legendWidth = inner / math.max(1, #model.legend)
    for i, p in ipairs(model.legend) do
        text(short(p.name, 10) .. (p.isSelf and L.text("（你）") or "") .. (p.connected == false and L.text(" 离线") or ""),
            20 + (i - 1) * legendWidth, legendTop, legendWidth - 6, 14, p.color, "legend")
    end
    local trendTop = height - math.min(204, math.max(150, height - 516))
    local chartTop = legendTop + 32
    local chartHeight = trendTop - chartTop - 16
    local perPage=model.chartsPerPage or 6
    local first = ((model.page or 1) - 1) * perPage + 1
    local count = math.min(perPage, #model.charts - first + 1)
    local columns = count == 1 and 1 or (width >= 1100 and count > 4 and 3 or 2)
    local cellWidth = (inner - gap * (columns - 1)) / columns
    local cellHeight = chartHeight / math.max(1, math.ceil(count / columns))
    for index = 0, count - 1 do
        local chart = model.charts[first + index]
        local x = 20 + (index % columns) * (cellWidth + gap)
        local y = chartTop + math.floor(index / columns) * cellHeight
        if chart.selectMetric then
            button('chartTitle_'..(index+1),chart.label,x,y,cellWidth-135,true,
                {action='selectMetric',value=chart.selectMetric,selected=model.metric==chart.selectMetric,
                    height=32,size=13,role='metric-heading'})
        else text(chart.label, x, y, cellWidth - 135, 14, palette.text) end
        local maximum = chart.unit == "%" and number(chart.maximum * 100) .. "%" or number(chart.maximum,chart.integer) .. " " .. chart.unit
        text("0 → " .. maximum, x + cellWidth - 130, y + 8, 130, 12, palette.muted)
        local rowHeight = math.min(26, math.floor((cellHeight - 40) / math.max(1, #chart.rows)))
        for i, row in ipairs(chart.rows) do
            local rowY = y + 40 + (i - 1) * rowHeight
            text(short(row.name, 5), x, rowY, 104, 12, row.color, "player-name")
            if row.fraction ~= nil then bar(x + 108, rowY + 4, cellWidth - 252, 9, row.fraction, row.color, "metric-bar", row.status == "partial" and 0.65 or 1) end
            local valueText = row.text
            if type(valueText) ~= "string" then valueText = row.exactText or L.text('不可用') end
            if row.status == "partial" then valueText = valueText .. " *" end
            text(valueText, x + cellWidth - 132, rowY, 132, 12, row.status == "unavailable" and palette.muted or palette.text, "metric-value")
        end
    end
    if model.message then text(model.message, 20, chartTop, inner, 16, palette.muted) end
    local simplified = false
    for index, key in ipairs({"rolling", "average"}) do
        local trend = model.trends[key]
        local boxWidth = (inner - gap) / 2
        local x = 20 + (index - 1) * (boxWidth + gap)
        text(trend.label .. L.text("（点/秒）"), x, trendTop, boxWidth, 14)
        local left, top, plotWidth = x + 62, trendTop + 31, boxWidth - 72
        local plotHeight = math.max(24, height - trendTop - 117)
        line(left, top + plotHeight, left + plotWidth, top + plotHeight, palette.grid, "axis")
        line(left, top, left, top + plotHeight, palette.grid, "axis")
        text(axisNumber(trend.maximum), x, top - 6, 56, 12, palette.muted)
        text("0", x + 35, top + plotHeight - 12, 25, 12, palette.muted)
        text("00:00", left, top + plotHeight + 8, 55, 12, palette.muted)
        text(duration(trend.maximumTime), left + plotWidth - 55, top + plotHeight + 8, 55, 12, palette.muted)
        local function position(point)
            return left + point.time / math.max(1, trend.maximumTime) * plotWidth,
                top + plotHeight - point.value / math.max(1, trend.maximum) * plotHeight
        end
        local viewportBudget = math.max(12, math.min(48, math.floor(plotWidth / 18)))
        for _, rawSeries in ipairs(trend.series) do
            local series = Panel.sampleSeries(rawSeries, viewportBudget)
            simplified = simplified or series.reduced
            for _, segment in ipairs(series.segments) do
                if #segment.points == 1 then
                    local px, py = position(segment.points[1]); bar(px - 1.5, py - 1.5, 3, 3, 1, series.color, "trend-point")
                else
                    for i = 2, #segment.points do
                        local ax, ay = position(segment.points[i - 1]); local bx, by = position(segment.points[i])
                        line(ax, ay, bx, by, series.color, "trend-line", segment.status == "partial" and 0.6 or 1)
                    end
                end
            end
        end
    end
    text(L.text("* 部分数据；不可用表示未采集。未观测区间断开。" .. (simplified and " 图表已抽样，完整记录仍保存。" or "")), 20, height - 49, inner, 12, palette.muted)
    text(model.controls or L.text("F8 隐藏"), 20, height - 26, inner, 12, palette.accent)
    return scene
end

local Canvas=require('CanvasView')
function UMG.new(options)
    options.layout=options.layout or UMG.layout
    return Canvas.new(options)
end
return UMG
