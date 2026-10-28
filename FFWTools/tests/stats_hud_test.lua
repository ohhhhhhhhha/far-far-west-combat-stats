package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib')
local UMG,Panel=require('PanelUmg'),require('Panel')
local loaded,Hud=pcall(require,'Hud')
local function snapshot(time,dps)
    local a={id='a',name='自己',color='#56B4E9',connected=true,
        metrics={rollingDps=dps or 120,damage=900,incomingDamage=180,hpLoss=120,shieldAbsorbed=60},
        coverage={damage={status='partial'},rollingDps={status='partial'},incomingDamage={status='partial'},hpLoss={status='partial'},shieldAbsorbed={status='partial'}}}
    local b={id='b',name='队友',color='#E69F00',connected=true,metrics={rollingDps=999,incomingDamage=5},coverage=a.coverage}
    local history={}
    for i=0,time or 30 do
        history[#history+1]={time=i,players=i==15 and {} or {a={rollingDps=i==8 and 500 or 120,coverage='partial'}}}
    end
    return {schemaVersion=1,sessionId='A',status='active',time=time or 30,players={a=a,b=b},playerOrder={'b','a'},history=history,encounters={}}
end
T.test('corner HUD uses local data and retains unknown and partial coverage',function()
    T.eq(loaded,true,'HUD model is available')
    local hud=Hud.new({selfPlayerId='a',clock=function() return 0 end})
    local s=snapshot();hud:update(s,{previous=false})
    local model=hud:model();T.eq(#model.rows,1)
    local row=model.rows[1];T.eq(row.id,'a');T.eq(row.dps.value,120);T.eq(row.incoming.value,180)
    T.eq(row.dps.status,'partial');T.near(row.hpFraction,2/3);T.near(row.shieldFraction,1/3)
    s.players.a.metrics.shieldAbsorbed=nil
    hud:update(s,{previous=false});T.eq(hud:model().rows[1].hpFraction,nil,'missing shield is not a measured zero')
    s.players.a.coverage.incomingDamage.status='unavailable'
    hud:update(s,{previous=false});T.eq(hud:model().rows[1].incoming.value,nil)
    s.history={};s.players.a.metrics.rollingDps=nil;hud:update(s,{previous=false})
    T.eq(hud:model().rows[1].recentPeak.value,nil,'missing observations do not produce a zero peak')
end)
T.test('HUD displays the last thirty-second peak and retains the mission peak',function()
    T.eq(loaded,true)
    local hud=Hud.new({selfPlayerId='a',clock=function() return 0 end})
    hud:update(snapshot(),{previous=false})
    T.eq(hud:model().rows[1].recentPeak.value,500)
    T.eq(hud:model().rows[1].missionPeak.value,500)
    T.eq(hud:model().rows[1].missionPeak.text,'500.00')
    hud:update(snapshot(38),{previous=false})
    T.eq(hud:model().rows[1].recentPeak.value,120)
    T.eq(hud:model().rows[1].missionPeak.value,500)
    local nextRun=snapshot(3);nextRun.sessionId='B';hud:update(nextRun,{previous=false})
    T.eq(hud:model().rows[1].missionPeak.value,120,'a new mission resets the peak')
end)
T.test('stalled snapshots do not pretend frozen DPS is live and idle updates can show zero',function()
    T.eq(loaded,true)
    local now,stale=0,false
    local hud=Hud.new({selfPlayerId='a',clock=function() return now end,isStale=function() return stale end})
    local s=snapshot();hud:update(s,{previous=false});T.eq(hud:model().rows[1].dps.value,120)
    now,stale=4,true;hud:update(s,{previous=false})
    T.eq(hud:model().stale,true);T.eq(hud:model().rows[1].dps.value,nil)
    T.eq(hud:model().rows[1].incoming.value,180)
    stale=false;hud:update(snapshot(36,0),{previous=false});T.eq(hud:model().rows[1].dps.value,0)
    T.eq(hud:model().stale,false)
    hud:update(snapshot(),{previous=true});T.eq(hud:model(),nil)
    s.status='ended';hud:update(s,{previous=false});T.eq(hud:model(),nil)
end)
T.test('a paused but current snapshot uses transport freshness rather than elapsed mission time',function()
    T.eq(loaded,true)
    local now=0
    local hud=Hud.new({selfPlayerId='a',clock=function() return now end,isStale=function() return false end})
    local s=snapshot();hud:update(s,{previous=false});now=20;hud:update(s,{previous=false})
    T.eq(hud:model().stale,false);T.eq(hud:model().rows[1].dps.value,120)
end)
T.test('HUD geometry fits the upper-left corner with a finite widget budget',function()
    T.eq(loaded,true)
    local hud=Hud.new({selfPlayerId='a',clock=function() return 0 end})
    hud:update(snapshot(),{previous=false})
    local scene=Hud.layout(hud:model(),{width=1024,height=768,dpiScale=1})
    T.eq(scene.width<=340 and scene.height<=220,true);T.eq(scene.margin<=24,true)
    T.eq(#scene.commands<70,true)
    local ranks,peaks=0,0
    for _,command in ipairs(scene.commands) do
        T.eq(command.role=='hud-trend',false,'team ranking replaces the corner sparkline')
        if command.role=='hud-rank-score' then ranks=ranks+1 end
        if command.role=='hud-recent-peak' or command.role=='hud-mission-peak' then peaks=peaks+1 end
        T.eq(command.kind=='button',false,'HUD must remain passive')
        T.eq(command.x>=0 and command.y>=0,true)
        if command.kind~='line' then
            T.eq(command.x+command.width<=scene.width+.01,true)
            T.eq(command.y+command.height<=scene.height+.01,true)
            if command.kind=='text' then T.eq(command.size>=12,true) end
        end
    end
    T.eq(ranks,2);T.eq(peaks,2)
end)
T.test('passive renderer never takes mouse ownership and follows controller travel',function()
    local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
    local ok,err=pcall(function()
        local model=Panel.build(snapshot(),{metric='damage'})
        local renderer=UMG.new({getController=function() return e.controller end,passive=true,
            viewport=function() return {width=1024,height=768,dpiScale=1} end})
        renderer:render(model)
        T.eq(e.controller.bShowMouseCursor,false,'passive statistics cannot enable the cursor')
        T.eq(e.controller.lookIgnores or 0,0);T.eq(e.nativeRecentersMouse(),true)
        T.eq(renderer.mouse,nil);T.eq(renderer.host.Visibility,3)
        local first=renderer.host;local oldCalls=0
        first.SetVisibility=function() oldCalls=oldCalls+1;error('retired widget') end
        first.RemoveFromParent=first.SetVisibility
        e.newController();renderer:render(model)
        T.eq(oldCalls,0);T.eq(renderer.host~=first,true);T.eq(renderer.host.controller,e.controller)
        renderer:hide();T.eq(e.controller.bShowMouseCursor,false)
    end)
    e.restore();if not ok then error(err,0) end
end)
T.finish()
