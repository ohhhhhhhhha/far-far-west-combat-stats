-- Actual Stats entry, adapter, model and renderer; only Unreal/Steam boundaries
-- and scheduled game-thread work are substituted. All data is synthetic.
local H={}
function H.new(options)
    options=options or {}
    for _,name in ipairs({'last-mission.json','boot-epoch.txt','hud-settings.json'}) do
        for _,suffix in ipairs({'','.bak','.tmp'}) do os.remove('FFWTools/tests/Data/'..name..suffix) end
    end
    local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
    local h={e=e,keys={},queue={},loops={},logs={},wall=1000,engineTime=0,realTime=0,
        width=options.width or 1280,height=options.height or 720,dpi=options.dpi or 1,
        epochWritable=options.epochWritable~=false,nativeReady=options.nativeReady~=false}
    local oldFindAll,oldHelpers=FindAllOf,package.loaded.UEHelpers
    local psClass=StaticFindObject('/Game/Player/BP_PlayerState.BP_PlayerState_C')
    local gp=StaticFindObject('/Script/Engine.GameplayStatics')
    local mp=StaticFindObject('/Script/FarFarWest.MultiplayerStatics')
    local layout=StaticFindObject('/Script/UMG.WidgetLayoutLibrary')
    local nativeFind=StaticFindObject
    local hostPath='/Game/Interfaces/UI_Joker_Informations.UI_Joker_Informations_C'
    local fontPath='/Game/Materials/Fonts/Font_Text.Font_Text'
    h.loaded=options.assetsLoaded~=false
    _G.StaticFindObject=function(p)
        if not h.loaded and (p==hostPath or p==fontPath) then return nil end
        return nativeFind(p)
    end
    _G.LoadAsset=function(p) h.loaded=true;return nativeFind(p) end
    local lib=nativeFind('/Script/UMG.WidgetBlueprintLibrary')
    local create=lib.Create
    function lib:Create(context,class,pc)
        assert(class and class:IsValid(),'host class must be loaded before Create')
        assert(pc:IsLocalPlayerController(),'widgets require the verified local controller')
        local host=create(self,context,class,pc);host.world=pc.world
        return host
    end
    function gp:GetGameState(pc) assert(pc==e.controller,'roster must use local controller');return h.gameState end
    function gp:GetTimeSeconds(context) assert(context and context:IsValid(),'live world context required');return h.engineTime end
    function gp:GetRealTimeSeconds(context) assert(context and context:IsValid(),'live real-time context required');return h.realTime end
    function mp:MP_UniqueNetIdToString(id) return id end
    function layout:GetViewportSize() return {X=h.width,Y=h.height} end
    function layout:GetViewportScale() return h.dpi end
    function h:controller(pc,localPlayer)
        function pc:IsLocalPlayerController() return localPlayer end
        function pc:IsPlayerController() return true end
        function pc:HasAuthority() return options.host~=false end
        return pc
    end
    h:controller(e.controller,true)
    h.remote=h:controller(e.object('RemotePlayerController'),false);h.remote.world=e.controller.world
    h.candidates=options.remoteFirst and {h.remote,e.controller} or {e.controller}
    function h:player(id,host)
        local ps=e.object('PlayerState');ps.world=e.controller.world
        ps['Native Net ID']=id;ps.playerHeal=100;ps.isHost=host==true
        function ps:IsA(class) return class==psClass end
        function ps:GetPlayerName() return host and 'Host fixture' or 'Guest fixture' end
        local pawn=e.object('Pawn');pawn.world=ps.world;pawn.PlayerState=ps
        function pawn:IsA() return false end
        function pawn:IsLocallyControlled() return ps==e.controller.PlayerState end
        function ps:GetPawn() return pawn end
        return ps
    end
    h.localRawId=options.localRawId or '76561198000000001'
    h.nativeId=options.nativeId or '76561198000000001'
    h.members=options.emptyRoster and {} or {h:player(h.localRawId,options.host~=false)}
    e.controller.PlayerState=h.members[1]
    h.gameState=e.object('GameState');h.gameState.world=e.controller.world
    h.gameState.PlayerArray={ForEach=function(_,fn) for i,ps in ipairs(h.members) do fn(i,{get=function() return ps end}) end end}
    _G.FindAllOf=function(class)
        if class=='PlayerController' or class=='Controller' then return h.candidates end
        if class=='BP_Manager_GameMaster_C' then return h.managers or {} end
        return {}
    end
    package.loaded.UEHelpers={GetPlayerController=function() return h.candidates[1] end,
        GetActorFromHitResult=function(hit) return hit.actor end}
    local env=setmetatable({}, {__index=_G});env._G=env
    env.Key={F2='F2',F4='F4',F7='F7',F8='F8',F10='F10',PAGE_UP='PAGE_UP',PAGE_DOWN='PAGE_DOWN',HOME='HOME',END='END'}
    env.os=setmetatable({time=function() return h.wall end},{__index=os})
    env.io=setmetatable({open=function(p,mode)
        if not h.epochWritable and p:find('boot-epoch',1,true) and mode:find('w',1,true) then return nil,'read-only fixture' end
        return io.open(p,mode)
    end},{__index=io})
    env.RegisterKeyBind=function(key,fn) h.keys[key]=fn end
    env.ExecuteInGameThread=function(fn) h.queue[#h.queue+1]=fn end
    env.LoopInGameThreadWithDelay=function(delay,fn) h.loops[#h.loops+1]={delay=delay,run=fn};return #h.loops end
    env.CancelDelayedAction=function() h.cancelled=true end
    env.RegisterLoadMapPreHook=function(fn) h.preMap=fn end
    env.RegisterLoadMapPostHook=function(fn) h.postMap=fn end
    env.print=function(message) h.logs[#h.logs+1]=message end
    h.transport={apiVersion=1,channel=4605527,maxPayload=262144,
        localSteamId=function() if h.nativeReady then return h.nativeId end;return nil,'identity pending' end,
        send=function() h.sent=(h.sent or 0)+1;return true end,poll=function() end,close=function() return true end}
    if options.bridge~=false then env.FFWTeamSync=h.transport end
    env.loadfile=function(p,mode,scope)
        local leaf=p:match('([^/]+)$')
        local root=p:find('/Common/',1,true) and 'FFWTools/src/FFWStats/Scripts/' or 'FFWTools/src/FFWStats/Scripts/'
        return loadfile(root..leaf,mode,scope)
    end
    h.env=env
    function h:drain()
        local queue=self.queue;self.queue={};for _,fn in ipairs(queue) do fn() end
    end
    function h:load()
        local file=assert(io.open('FFWTools/src/FFWStats/Scripts/main.lua','rb'))
        local code=file:read('a');file:close()
        self.mod=assert(load(code,'@FFWTools/tests/Scripts/main.lua','t',env))();self:drain();return self.mod
    end
    function h:key(key) self.keys[key]();self:drain() end
    function h:tick(delta)
        self.wall=self.wall+delta;self.engineTime=self.engineTime+delta;self.realTime=self.realTime+delta
        self.loops[1].run();self:drain()
    end
    function h:restore()
        if self.mod then self.mod.stop();self:drain() end
        e.restore();FindAllOf=oldFindAll;package.loaded.UEHelpers=oldHelpers
    end
    return h
end
return H
