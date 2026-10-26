package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib')
local Panel,UMG=require('Panel'),require('PanelUmg')
local function snapshot()
    local p={id='a',name='甲',color='#56B4E9',connected=true,
        metrics={damage=100,incomingDamage=40,hpLoss=30,shieldAbsorbed=10,rollingDps=20,averageDps=10},
        coverage={damage={status='complete'},incomingDamage={status='complete'},hpLoss={status='complete'},shieldAbsorbed={status='complete'}}}
    return {schemaVersion=1,sessionId='A',status='active',time=10,playerOrder={'a'},players={a=p},history={},encounters={}}
end
T.test('clicking metric tabs and chart headings selects their data without cycling',function()
    local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
    local ok,err=pcall(function()
        local panel,renderer
        renderer=UMG.new({getController=function() return e.controller end,
            viewport=function() return {width=1024,height=768,dpiScale=1} end,
            onAction=function(action,value) panel:mouse(action,value) end})
        panel=Panel.new({render=function(model) renderer:render(model) end})
        panel:update(snapshot());panel:toggle()
        local tab=renderer.mouse.buttons.tab_incomingDamage
        T.eq(type(tab),'table','incoming tab is a native clickable control')
        e.click(tab.button);T.eq(panel.metric,'incomingDamage')
        T.eq(panel:model().charts[1].key,'incomingDamage')
        local heading=renderer.mouse.buttons.chartTitle_2
        T.eq(heading.value,'hpLoss')
        e.click(heading.button);T.eq(panel.metric,'hpLoss')
        T.eq(#panel:model().charts,1);T.eq(panel:model().charts[1].rows[1].value,30)
        T.eq(heading.visible,false,'unused chart headings must no longer intercept clicks')
        e.click(heading.button);T.eq(panel.metric,'hpLoss')
        T.eq(panel:mouse('selectMetric','not-a-metric'),false)
        panel:mouse('close');e.click(tab.button);T.eq(panel.metric,'hpLoss')
        T.eq(e.controller.bShowMouseCursor,false)
    end)
    e.restore();if not ok then error(err,0) end
end)
T.test('tabs remain on screen and identify the selected section in both languages',function()
    local locale=require('Locale')
    for _,language in ipairs({'zh','en'}) do
        locale.setCulture(language)
        local model=Panel.build(snapshot(),{metric='shieldAbsorbed'})
        local scene=UMG.layout(model,{width=1024,height=768,dpiScale=1})
        local count,selected=0,nil
        for _,command in ipairs(scene.commands) do
            if command.role=='metric-tab' then
                count=count+1
                T.eq(command.x>=0 and command.y>=0,true)
                T.eq(command.x+command.width<=scene.width,true)
                if command.selected then selected=command.value end
            end
        end
        T.eq(count,12);T.eq(selected,'incomingDamage')
    end
    locale.setCulture('zh')
end)
T.test('keyboard cycling continues from the section of a clicked submetric',function()
    local panel=Panel.new();panel:update(snapshot());panel:toggle()
    panel:selectMetric('hpLoss');panel:cycleMetric(1);T.eq(panel.metric,'incomingSources')
    panel:selectMetric('hpLoss');panel:cycleMetric(-1);T.eq(panel.metric,'damageSources')
end)
T.test('native tab and metric captions remain single-line and centered',function()
    local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
    local ok,err=pcall(function()
        local renderer=UMG.new({getController=function() return e.controller end,
            viewport=function() return {width=1024,height=768,dpiScale=1} end})
        renderer:render(Panel.build(snapshot(),{metric='incomingDamage'}))
        for _,id in ipairs({'tab_damageSources','tab_incomingSources','chartTitle_1','chartTitle_2'}) do
            local label=renderer.mouse.buttons[id].label
            T.eq(label.AutoWrapText,false,'button titles must not wrap into the chart rows')
            T.eq(label.justification,1)
            T.eq(label.Slot.horizontalAlignment,0)
            T.eq(label.Slot.verticalAlignment,2)
        end
    end)
    e.restore();if not ok then error(err,0) end
end)
T.test('on-screen values omit floating-point noise while the numeric model stays exact',function()
    local s=snapshot();s.players.a.metrics.incomingDamage=90.083335682884521
    s.players.a.coverage.incomingDamage.status='partial'
    local model=Panel.build(s,{metric='incomingDamage'})
    local found=false
    for _,command in ipairs(UMG.layout(model,{width=1024,height=768,dpiScale=1}).commands) do
        if command.role=='metric-value' and command.text=='90.08 *' then found=true end
    end
    T.eq(found,true);T.eq(model.charts[1].rows[1].value,90.083335682884521)
end)
T.test('team contribution has a dedicated whole-mission page',function()
    local panel=Panel.new();panel:update(snapshot());panel:toggle()
    T.eq(panel:selectMetric('teamContribution'),true)
    local model=panel:model();T.eq(type(model.contribution),'table');T.eq(model.trends,nil)
    T.eq(model.scopeId,'mission');T.eq(model.scopeLocked,true)
    local scene=UMG.layout(model,{width=1024,height=768,dpiScale=1})
    local ranks,lines=0,0
    for _,cmd in ipairs(scene.commands) do
        if cmd.role=='contribution-score' then ranks=ranks+1 end
        if cmd.role=='trend-line' then lines=lines+1 end
    end
    T.eq(ranks,1);T.eq(lines,0)
end)
T.test('contribution freshness changes invalidate an otherwise unchanged panel',function()
    local stale=false
    local panel=Panel.new({isStale=function() return stale end})
    panel:update(snapshot());panel:toggle();panel:selectMetric('teamContribution')
    T.eq(panel:model().contribution.stale,false)
    stale=true;panel:refresh();T.eq(panel:model().contribution.stale,true)
    stale=false;panel:refresh();T.eq(panel:model().contribution.stale,false)
end)
T.test('retained and ended mission rankings do not wait for a live connection',function()
    local panel=Panel.new({isStale=function() return true end})
    local s=snapshot();panel:update(s,{previous=true});panel:toggle();panel:selectMetric('teamContribution')
    T.eq(panel:model().contribution.stale,false)
    s.status='ended';panel:update(s,{previous=false});T.eq(panel:model().contribution.stale,false)
end)
T.test('measurements retain two decimals while event counts stay integers',function()
    local s=snapshot();s.players.a.metrics.kills=3;s.players.a.coverage.kills={status='complete'}
    local model=Panel.build(s,{metric='overview'})
    T.eq(model.charts[1].rows[1].text,'100.00')
    T.eq(model.charts[3].rows[1].text,'3')
end)
T.test('four-player contribution pages fit both supported low-load viewport sizes',function()
    local s=snapshot()
    for i=2,4 do
        local id='p'..i;s.playerOrder[i]=id
        s.players[id]={id=id,name='队友'..i,color='#56B4E9',metrics={damage=100*i},coverage={damage={status='partial'}}}
    end
    for _,viewport in ipairs({{width=1024,height=768,dpiScale=1},{width=1280,height=720,dpiScale=1}}) do
        local scene=UMG.layout(Panel.build(s,{metric='teamContribution'}),viewport)
        for _,cmd in ipairs(scene.commands) do
            T.eq(cmd.x>=0 and cmd.y>=0,true)
            if cmd.kind~='line' then T.eq(cmd.x+cmd.width<=scene.width+.01,true);T.eq(cmd.y+cmd.height<=scene.height+.01,true) end
        end
    end
end)
T.test('toolbar controls share one baseline and native captions have room',function()
 local scene=UMG.layout(Panel.build(snapshot(),{metric='overview'}),{width=1280,height=720,dpiScale=1})
 local ids={previousMetric=true,nextMetric=true,previousScope=true,nextScope=true,previousPage=true,nextPage=true}
 for _,c in ipairs(scene.commands) do
  if ids[c.id] then T.eq(c.y,68);T.eq(c.height,36) end
  if c.role=='metric-heading' then T.eq(c.height>=32,true) end
 end
end)
T.finish()
