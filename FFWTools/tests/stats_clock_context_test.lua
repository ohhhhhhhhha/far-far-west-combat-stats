package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local H=require('stats_engine_harness')
local function with(fn)
    local h=H.new{};local ok,err=pcall(function()
        local mod=h:load();local calls={}
        local gp=StaticFindObject('/Script/Engine.GameplayStatics')
        function gp:GetTimeSeconds(context) calls[#calls+1]={kind='game',context=context};return 12 end
        function gp:GetRealTimeSeconds(context) calls[#calls+1]={kind='real',context=context};return 25 end
        fn(h,mod.adapter,calls)
    end);h:restore();assert(ok,err)
end
T.test('event actors are never passed to the native clock even when IsValid succeeds',function()
    with(function(h,a,calls)
        local eventActor=h.e.object('Enemy');eventActor.world=h.e.controller.world
        T.eq(a:gameTime(eventActor),12)
        T.eq(#calls,1);T.eq(calls[1].context,h.e.controller,'clock context is the current local controller, not the event actor')
    end)
end)
T.test('an inaccessible event WorldContext sentinel never crosses the native-call boundary',function()
    with(function(h,a,calls)
        local inaccessible=h.e.object('UnavailableWorldContext');inaccessible.world=h.e.controller.world
        local gp=StaticFindObject('/Script/Engine.GameplayStatics');local native=gp.GetTimeSeconds
        local rejected=0
        function gp:GetTimeSeconds(context)
            if context==inaccessible then rejected=rejected+1;error('simulated inaccessible native WorldContext') end
            return native(self,context)
        end
        T.eq(inaccessible:IsValid(),true,'a stale wrapper can still report valid')
        T.eq(a:gameTime(inaccessible),12)
        T.eq(rejected,0);T.eq(calls[1].context,h.e.controller)
    end)
end)
T.test('a cached valid controller is replaced by a freshly selected local controller for both clocks',function()
    with(function(h,a,calls)
        local old=h.e.controller
        local pc=h.e.newController(false);h:controller(pc,true);h.candidates={pc}
        T.eq(old:IsValid(),true)
        T.eq(a:gameTime(old),12);T.eq(a:realClock(),25)
        T.eq(#calls,2);T.eq(calls[1].context,pc);T.eq(calls[2].context,pc)
    end)
end)
T.test('a valid controller with no world does not reach either native clock',function()
    with(function(h,a,calls)
        h.e.controller.world=nil
        T.eq(h.e.controller:IsValid(),true)
        T.eq(a:gameTime(),nil);T.eq(a:realClock(),nil)
        T.eq(#calls,0,'pcall is not a substitute for a valid world context')
        T.eq(h.mod.identityReady,false)
    end)
end)
T.test('an invalid world object is rejected before any native time function',function()
    with(function(h,a,calls)
        h.e.controller.world.destroyed=true
        T.eq(a:gameTime(),nil);T.eq(a:realClock(),nil);T.eq(#calls,0)
    end)
end)
T.test('OpeningCredits and title worlds do not perform gameplay clock reads',function()
    with(function(h,a,calls)
        for _,map in ipairs({'L_OpeningCredits','L_Map_TitleScreen'}) do
            h.e.controller.world=h.e.object('World /Game/Levels/'..map..'.'..map)
            T.eq(a:gameTime(),nil);T.eq(a:realClock(),nil)
        end
        T.eq(#calls,0)
    end)
end)
T.test('old event or manager parameters are not dereferenced merely to acquire a timestamp',function()
    with(function(h,a,calls)
        local old=h.e.object('RetiredManager');local oldReads=0
        old.GetWorld=function() oldReads=oldReads+1;error('retired actor method') end
        T.eq(a:gameTime(old),12);T.eq(oldReads,0)
        T.eq(calls[1].context,h.e.controller)
    end)
end)
T.test('a mission cannot start while no valid native clock context exists and can recover later',function()
    with(function(h,a,calls)
        local manager=h.e.object('/Game/L_Map_Desert.GameMaster');manager.world=h.e.controller.world
        h.e.controller.world=nil
        a:beginMission(manager,true);T.eq(a.active,false);T.eq(#calls,0)
        h.e.controller.world=manager.world
        a:beginMission(manager,true);T.eq(a.active,true);T.eq(a.anchor,12)
        T.eq(calls[1].context,h.e.controller)
    end)
end)
T.test('reselecting a new lobby controller cannot start a mission for an old manager',function()
    with(function(h,a,calls)
        local oldManager=h.e.object('/Game/L_Map_Desert.GameMaster');oldManager.world=h.e.controller.world
        local pc=h.e.newController(false);h:controller(pc,true)
        pc.world=h.e.object('World /Game/Levels/L_Lobby.L_Lobby');h.candidates={pc}
        local ps=h:player(h.localRawId,true);h.members={ps};pc.PlayerState=ps;h.gameState.world=pc.world
        a:beginMission(oldManager,true)
        T.eq(a.active,false);T.eq(h.mod.session.phase,'lobby')
        T.eq(#calls,0,'old manager is rejected before acquiring a new-world anchor')
    end)
end)
T.test('a manager without a valid world cannot establish a mission boundary',function()
    with(function(h,a,calls)
        local manager=h.e.object('/Game/L_Map_Desert.RetiredManager');manager.world=nil
        a:beginMission(manager,true);T.eq(a.active,false);T.eq(#calls,0)
    end)
end)
T.finish()
