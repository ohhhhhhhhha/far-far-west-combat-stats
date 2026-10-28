package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local T=dofile('FFWTools/tests/stats_testlib.lua')
local Stats,Store=require('Stats'),require('Store')
local source='FFWTools/src/FFWStats/Scripts/'
local save,epoch='FFWTools/tests/Data/last-mission.json','FFWTools/tests/Data/boot-epoch.txt'
local function clean()
    for _,path in ipairs({save,epoch}) do os.remove(path);os.remove(path..'.tmp');os.remove(path..'.bak') end
end
-- These doubles replace only Unreal/native boundaries. Session, Sync, Stats,
-- persistence, configuration and the panel view model execute their real code.
local function harness()
    local h={now=0,mission=0,hostVisible=true,nativeReady=true,keys={},loops={},trace={},renders={},hudRenders={},logs={}}
    local members={host={playerId='host',name='房主',isHost=true}}
    local Adapter={new=function(options)
        local a={options=options,localId='host',controller={IsValid=function() return true end},events={}}
        function a:install() options.onRoster(members,self.localId,h.hostVisible and 'host' or nil) end
        function a:clock() return h.mission end
        function a:poll()
            h.trace[#h.trace+1]='roster';options.onRoster(members,self.localId,h.hostVisible and 'host' or nil)
            if h.endOnPoll then self.ending=true;h.endOnPoll=false end
        end
        function a:flush()
            h.trace[#h.trace+1]='flush'
            local events=self.events;self.events={}
            for _,event in ipairs(events) do options.onEvent(event,0.5,false) end
            if self.ending then self.ending=false;options.onEnd(h.mission,'lobby') end
        end
        function a:stop() h.adapterStopped=true end
        h.adapter=a;return a
    end}
    local Renderer={new=function(options)
        if options.passive then
            h.hudOptions=options
            return {render=function(_,model) h.hudRenders[#h.hudRenders+1]=model;h.hudHidden=model==nil;return true end,
                hide=function() h.hudHidden=true end}
        end
        h.rendererOptions=options
        return {render=function(_,model)
            if model then assert(options.getController(),'verified local controller expected') end
            h.renders[#h.renders+1]={model=model};return true
        end,hide=function() h.hidden=true end}
    end}
    local env=setmetatable({}, {__index=_G});env._G=env
    env.os=setmetatable({time=function() return 1000+h.now end},{__index=os})
    env.Key={F2='F2',F4='F4',F7='F7',F8='F8',F10='F10',PAGE_UP='PAGE_UP',PAGE_DOWN='PAGE_DOWN',HOME='HOME',END='END',TAB='TAB'}
    env.RegisterKeyBind=function(key,fn) assert(not h.keys[key],'duplicate key binding');h.keys[key]=fn end
    env.ExecuteInGameThread=function(fn) fn() end
    env.LoopInGameThreadWithDelay=function(delay,fn) h.loops[#h.loops+1]={delay=delay,run=fn};return #h.loops end
    env.CancelDelayedAction=function(handle) h.cancelled=handle;return true end
    env.print=function(message) h.logs[#h.logs+1]=message end
    env.FFWTeamSync={apiVersion=1,channel=4605527,maxPayload=262144,localSteamId=function()
        if h.nativeReady then return 'host' end
        return nil,'Steam identity not available yet'
    end,
        poll=function() h.trace[#h.trace+1]='transport' end,send=function() return true end,close=function() return true end}
    env.loadfile=function(path,mode,moduleEnvironment)
        local leaf=path:match('([^/]+)$')
        if path:find('/Common/',1,true) then return loadfile('FFWTools/src/FFWStats/Scripts/'..leaf,mode,moduleEnvironment) end
        if leaf=='GameAdapter.lua' then return function() return Adapter end end
        if leaf=='PanelUmg.lua' then return function() return Renderer end end
        return loadfile(source..leaf,mode,moduleEnvironment)
    end
    function h:load()
        local file=assert(io.open(source..'main.lua','rb'),'production entry point required')
        local text=file:read('a');file:close()
        local chunk=assert(load(text,'@FFWTools/tests/Scripts/main.lua','t',env))
        self.mod=chunk();return self.mod
    end
    function h:tick(now,mission) self.now,self.mission=now,mission or self.mission;self.loops[1].run() end
    return h
end
T.test('boot retains interrupted totals hidden until F8 and isolates generic module names',function()
    clean()
    local old=Stats.new('previous')
    assert(old:apply({id='join',sessionId='previous',kind='player_join',sourcePlayerId='host',time=0}))
    assert(old:apply({id='hit',sessionId='previous',kind='damage',sourcePlayerId='host',targetId='enemy',amount=183.75,sourceCategory='primary',time=1}))
    assert(Store.write(save,old:snapshot(5)))
    local sentinel={otherMod=true};local oldPanel=package.loaded.Panel;package.loaded.Panel=sentinel
    local h=harness();local mod=h:load()
    T.eq(package.loaded.Panel,sentinel);package.loaded.Panel=oldPanel
    T.eq(mod.panel:model(),nil);T.eq(#h.renders,0)
    h:tick(1,0);h.keys.F8()
    T.eq(h.renders[#h.renders].model.missionLabel,'上一局')
    T.eq(h.renders[#h.renders].model.charts[1].rows[1].value,183.75)
    T.eq(Store.read(save).sessionId,'previous')
end)
T.test('queued final damage is flushed before roster clock and end finalization',function()
    clean();local h=harness();local mod=h:load()
    h.adapter.options.onStart('mission',true,true)
    h.adapter.events={{kind='damage',sourcePlayerId='host',targetId='enemy',amount=183.75,sourceCategory='primary'}}
    h.endOnPoll=true;h.trace={};h:tick(1,1)
    T.eq(h.trace[1],'flush');T.eq(h.trace[2],'roster');T.eq(h.trace[3],'flush');T.eq(h.trace[4],'transport')
    local snapshot=Store.read(save)
    T.eq(snapshot.status,'ended');T.eq(snapshot.players.host.metrics.damage,183.75)
    T.eq(snapshot.players.host.coverage.damage.status,'partial')
    T.eq(snapshot.players.host.metrics.shots,nil)
end)
T.test('one low-frequency game-thread loop polls roster every two seconds without Joker hotkeys',function()
    clean();local h=harness();h:load()
    T.eq(#h.loops,1);T.eq(h.loops[1].delay,250)
    h.trace={}
    for i=1,9 do h:tick(i/4,0) end
    local polls,flushes=0,0
    for _,operation in ipairs(h.trace) do
        if operation=='roster' then polls=polls+1 elseif operation=='flush' then flushes=flushes+1 end
    end
    T.eq(polls,2);T.eq(flushes,18)
    T.eq(h.keys.F5,nil);T.eq(h.keys.F6,nil)
    T.eq(h.keys.TAB,nil,'Tab belongs to the game card hover menu');T.eq(h.keys.F10,nil,'F10 belongs to the Nexus ConsoleEnabler component')
    T.eq(type(h.keys.PAGE_UP),'function');T.eq(type(h.keys.HOME),'function')
end)
T.test('opening another mod panel hides statistics without stopping capture',function()
    clean();local h=harness();local mod=h:load()
    for _,key in ipairs({'F2','F4','F7'}) do
        h.keys.F8();T.eq(mod.panel.visible,true)
        h.keys[key]();T.eq(mod.panel.visible,false);T.eq(mod.enabled,true)
    end
end)
T.test('native mouse actions reach the real controller without changing capture state',function()
    clean();local h=harness();local mod=h:load()
    h.keys.F8();h.rendererOptions.onAction('nextMetric');T.eq(mod.panel.metric,'teamContribution')
    h.rendererOptions.onAction('close');T.eq(mod.panel.visible,false);T.eq(mod.enabled,true)
    h.rendererOptions.onAction('nextMetric');T.eq(mod.panel.metric,'teamContribution')
end)
T.test('native metric title forwards its selection value to the actual panel',function()
    clean();local h=harness();local mod=h:load();h.keys.F8()
    h.rendererOptions.onAction('selectMetric','incomingDamage')
    T.eq(mod.panel.metric,'incomingDamage')
end)
T.test('corner HUD updates with F8 hidden and hides for menus and completed missions',function()
    clean();local h=harness();local mod=h:load()
    T.eq(type(h.hudOptions),'table','entry creates a passive HUD renderer')
    h:tick(0,0);T.eq(#h.hudRenders,0,'retained/lobby data must not look live')
    h.adapter.options.onStart('mission',true,true)
    h.adapter.events={{kind='damage',sourcePlayerId='host',targetId='enemy',amount=100,sourceCategory='primary'}}
    h:tick(1,1)
    T.eq(mod.panel.visible,false);T.eq(#h.loops,1)
    T.eq(h.hudRenders[#h.hudRenders].rows[1].recentPeak.value,100)
    h:tick(7,7);T.eq(h.hudRenders[#h.hudRenders].rows[1].recentPeak.value,100,'recent peak survives a short idle period')
    h:tick(40,40);T.eq(h.hudRenders[#h.hudRenders].rows[1].recentPeak.value,0)
    T.eq(h.hudRenders[#h.hudRenders].rows[1].missionPeak.value,100)
    h.keys.F8();T.eq(h.hudHidden,true)
    h.keys.F8();T.eq(h.hudHidden,false)
    h.adapter.options.onEnd(40,'lobby');h:tick(41,40);T.eq(h.hudHidden,true)
    T.eq(mod.session:snapshot().players.host.metrics.damage,100)
    mod.stop();T.eq(h.hudHidden,true)
end)
T.test('loading the entry twice does not install duplicate hooks timers or boot epochs',function()
    clean();local h=harness();local first=h:load()
    local file=assert(io.open(epoch,'rb'));local before=file:read('a');file:close()
    T.eq(h:load(),first);T.eq(#h.loops,1)
    file=assert(io.open(epoch,'rb'));T.eq(file:read('a'),before);file:close()
    first.stop();T.eq(h.adapterStopped,true);T.eq(h.hidden,true);T.eq(h.cancelled,1)
    h.trace={};h:tick(10,10);T.eq(#h.trace,0)
end)
T.test('a mission start waits for a trusted host roster then observes the remaining mission',function()
    clean();local h=harness();h.hostVisible=false;local mod=h:load()
    h.adapter.options.onStart('mission',true,true)
    T.eq(mod.session.phase,'lobby')
    h:tick(0,0)
    h.hostVisible=true;h:tick(2,2)
    T.eq(mod.session.phase,'active')
    h.adapter.events={{kind='damage',sourcePlayerId='host',targetId='enemy',amount=44.1,sourceCategory='primary'}}
    h:tick(3,3)
    T.near(mod.session:snapshot().players.host.metrics.damage,44.1)
    T.eq(mod.session:snapshot().players.host.coverage.damage.status,'partial')
end)
T.test('saved mission remains viewable while native identity is temporarily unavailable',function()
    clean();local old=Stats.new('previous')
    assert(old:apply({id='j',sessionId='previous',kind='player_join',sourcePlayerId='host',time=0}))
    assert(old:apply({id='d',sessionId='previous',kind='damage',sourcePlayerId='host',targetId='enemy',amount=44.1,sourceCategory='primary',time=1}))
    assert(Store.write(save,old:snapshot(2)))
    local h=harness();h.nativeReady=false;local mod=h:load();h.keys.F8()
    T.eq(mod.identityReady,false);T.eq(#h.renders,1)
    T.eq(h.renders[1].model.missionLabel,'上一局');T.near(h.renders[1].model.charts[1].rows[1].value,44.1)
    h.adapter.options.onStart('next',true,true);T.eq(mod.session.phase,'lobby')
end)
clean()
T.finish()
