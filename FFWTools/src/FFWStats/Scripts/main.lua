-- UE4SS production entry. Install the mod's Data directory before loading.
-- Only the engine adapter reads gameplay state; this module owns scheduling/UI.
local previous=_G.FFWStats
if previous and previous.enabled then return previous end
local source=debug.getinfo(1,'S').source
local directory=assert(source:gsub('^@',''):gsub('\\','/'):match('^(.*)/'),'file-backed FFWStats entry required')
local names={Config=true,Session=true,Stats=true,Store=true,Sync=true,Protocol=true,Json=true,
    GameAdapter=true,AttackAdapter=true,EventBuffer=true,Events=true,Panel=true,PanelUmg=true,Hud=true,HudSettings=true,CanvasView=true,SourceCatalog=true,Contribution=true,Locale=true,MousePanel=true}
local modules,environment={},nil
local globalRequire=require
environment=setmetatable({require=function(name)
    if not names[name] then return globalRequire(name) end
    if not modules[name] then modules[name]=assert(loadfile(directory..'/'..name..'.lua','t',environment))() end
    return modules[name]
end},{__index=_G})
local Config=environment.require('Config')
local L=environment.require('Locale')
local Session,Adapter=environment.require('Session'),environment.require('GameAdapter')
local Panel,UMG=environment.require('Panel'),environment.require('PanelUmg')
local Hud=environment.require('Hud')
local S={enabled=true,errors={},keyActions={},keysInstalled=previous and previous.keysInstalled or {}}
_G.FFWStats=S
local function report(message)
    message=tostring(message)
    if not S.errors[message] then S.errors[message]=true;print('[FFWStats] '..message..'\n') end
end
local function protected(callback)
    local ok,err=pcall(callback)
    if not ok then report(err) end
    return ok,err
end
S.paths=Config.paths(source)
local epoch,epochError=Config.nextEpoch(S.paths.epoch)
if not epoch then report('统计采集未启动：无法保存启动序号。请确认 Data 目录存在：'..tostring(epochError)) end
local transport=_G.FFWTeamSync
local transportReady=type(transport)=='table' and transport.apiVersion==1
    and type(transport.localSteamId)=='function' and type(transport.poll)=='function'
    and type(transport.send)=='function' and type(transport.close)=='function'
if not transportReady then report('统计同步桥 FFWTeamSync 不可用；保留已保存的上一局。') end
local bootTime=os.time()
local wall=0
local function wallClock() wall=math.max(wall,os.time()-bootTime);return wall end
local adapter
S.hudSettings=environment.require('HudSettings').new{path=S.paths.root..'/Data/hud-settings.json',enabled=Config.hudEnabled~=false}
S.hud=Hud.new({settings=S.hudSettings,isStale=function()
    local session=S.session
    if session and session.isHost then return false end
    return not session or not session.sync or session.sync:status().snapshotStale==true
end})
S.hudRenderer=UMG.new({getController=function() return adapter and adapter.controller or nil end,
    passive=true,layout=Hud.layout,zOrder=9800})
local function refreshHud()
    if S.session and S.session.phase=='active' and S.identityReady and not S.panel.visible then
        local ok,err=S.hudRenderer:render(S.hud:model())
        if ok==nil and err then report('实时统计：'..tostring(err)) end
    else S.hudRenderer:hide() end
end
S.renderer=UMG.new({getController=function() return adapter and adapter.controller or nil end,
    onAction=function(action,value) if S.enabled then S.panel:mouse(action,value) end end})
S.panel=Panel.new({hudSettings=S.hudSettings,hotkeys=Config.hotkeys,refreshSeconds=Config.viewSeconds,clock=wallClock,isStale=S.hud.options.isStale,
    render=function(model)
        protected(function()
            local ok,err=S.renderer:render(model)
            if ok==nil and err then report('面板：'..tostring(err)) end
            refreshHud()
        end)
    end})
S.session=Session.new({path=S.paths.save,epoch=epoch,transport=transport,
    nextEpoch=function() return Config.nextEpoch(S.paths.epoch) end,
    verifiedHostMetrics=Config.verifiedHostMetrics,localTracking=Config.localTracking,
    saveInterval=Config.saveSeconds,viewInterval=Config.viewSeconds,report=report,
    onSnapshot=function(snapshot,display)
        S.hud:update(snapshot,display);S.panel:update(snapshot,display)
    end})
local function beginPending()
    local pending=S.pendingStart
    if not pending then return end
    if not epoch or not S.identityReady then
        pending.observedLate=true
        report('任务统计等待可用的角色表、本机身份与持久启动序号。')
        return
    end
    local ok,err=S.session:begin(pending.worldKey,pending.fresh,S.session.localId==S.session.hostId,pending.observedLate)
    if ok or not err then S.pendingStart=nil else report(err) end
end
adapter=Adapter.new({
    onRoster=function(roster,localId,hostId)
        local nativeId,nativeError
        if transportReady then nativeId,nativeError=transport.localSteamId() end
        S.identityReady=nativeId~=nil and nativeId==localId and roster[localId]~=nil and hostId~=nil and roster[hostId]~=nil
        if not S.identityReady then
            if nativeError then report(nativeError)
            elseif nativeId and localId and nativeId~=localId then report('本机控制器身份与 Steam 同步桥不一致，等待角色刷新。') end
            return
        end
        S.panel.options.selfPlayerId=localId;S.panel.dirty=true
        S.hud.options.selfPlayerId=localId
        S.session:setRoster(roster,localId,hostId,adapter:clock())
        beginPending()
    end,
    onStart=function(worldKey,fresh,isHost)
        S.pendingStart={worldKey=worldKey,fresh=fresh,isHost=isHost};beginPending()
    end,
    onEvent=function(event,time,localOnly)
        if S.identityReady and S.session.phase=='active' then S.session:ingest(event,time,localOnly) end
    end,
    onEnd=function(time) S.pendingStart=nil;S.session:finish(time) end,
})
S.adapter=adapter
local nextPoll,nextRender,nextLanguage=0,0,0
function S.update()
    if not S.enabled then return false end
    return protected(function()
        local now=wallClock()
        if now>=nextLanguage then L.refresh();nextLanguage=now+1 end
        -- Flush before poll: its roster callback can advance Stats' event clock.
        -- Flush after poll: lobby/end observations finalize only after queued hits.
        adapter:flush()
        if now>=nextPoll then adapter:poll();nextPoll=now+Config.rosterSeconds end
        adapter:flush()
        S.session:tick(now,adapter:clock())
        if now>=nextRender then
            if S.panel.visible then S.panel:refresh() end
            refreshHud();nextRender=now+Config.viewSeconds
        end
    end)
end
function S.stop()
    ExecuteInGameThread(function()
        if not S.enabled then return end
        protected(function() adapter:flush();S.session:publish() end)
        S.enabled=false
        if S.loopHandle then CancelDelayedAction(S.loopHandle) end
        protected(function() adapter:stop() end)
        protected(function() S.renderer:hide() end)
        protected(function() S.hudRenderer:hide() end)
    end)
end
local function bind(key,callback)
    S.keyActions[key]=callback
    if not S.keysInstalled[key] then
        RegisterKeyBind(key,function()
            local current=_G.FFWStats
            if current and current.enabled and current.keyActions[key] then current.keyActions[key]() end
        end)
        S.keysInstalled[key]=true
    end
end
S.panel:bindKeys({Key=Key,execute=ExecuteInGameThread,register=bind})
for _,key in ipairs({Key.F2,Key.F4,Key.F7}) do
    bind(key,function()
        ExecuteInGameThread(function()
            if S.panel.visible then S.panel.visible=false;S.panel:refresh() end
        end)
    end)
end
ExecuteInGameThread(function() protected(function() adapter:install() end) end)
S.loopHandle=LoopInGameThreadWithDelay(Config.loopMilliseconds,S.update)
print('[FFWStats] 已加载。F8 开关详情，可点击标签；新增团队贡献页。左上角显示自身 DPS 峰值、承伤和团队排行。PgUp/PgDn 指标；Home/End 区间；F10 分项页。覆盖保持部分数据/不可用。\n')
return S
