-- UE4SS production entry. Install the mod's Data directory before loading.
-- Only the engine adapter reads gameplay state; this module owns scheduling/UI.
local previous=_G.FFWStats
if previous and previous.enabled then return previous end
local source=debug.getinfo(1,'S').source
local directory=assert(source:gsub('^@',''):gsub('\\','/'):match('^(.*)/'),'file-backed FFWStats entry required')
local names={Connection=true,Config=true,Session=true,Stats=true,Store=true,Sync=true,Protocol=true,Json=true,
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
local S={enabled=true,errors={},keyActions={},keysInstalled=previous and previous.keysInstalled or {},
    mapHooksInstalled=previous and previous.mapHooksInstalled,inputGeneration=0,
    captureStatus={reason='starting'},uiTrace={keyCallbacks=0,executed=0}}
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
local statusMessages={
    starting={'等待本机游戏界面。','Waiting for the local game interface.'},
    ready={'身份已核对，等待或记录当前任务。','Identity verified; ready for the current mission.'},
    bridge_unavailable={'同步桥尚未就绪；仍可查看面板。','Sync bridge is not ready; the panel remains available.'},
    native_identity_pending={'等待本机传输身份；LAN 请先打开联机设置。','Waiting for transport identity; configure LAN in Connection settings.'},
    identity_mismatch={'传输身份与当前角色不一致，暂停团队同步。','Transport and current player identity differ; team sync is suspended.'},
    unmapped_roster_id={'当前为非 Steam 身份；局域网请打开联机设置选择 LAN。','Non-Steam player identity; select LAN in Connection settings for LAN/IP games.'},
    roster_pending={'等待本机角色进入当前角色表。','Waiting for the local player in the current roster.'},
    duplicate_ids={'角色表存在重复 PlayerId，暂停团队同步。','Duplicate replicated PlayerIds; team sync is suspended.'},
    host_conflict={'配对房主与游戏房主标记不一致，请重新配对。','Paired host conflicts with the game host. Pair again.'},
    host_pending={'等待已确认的房主身份。','Waiting for a confirmed host identity.'},
    ambiguous_host={'角色表存在多个房主标记，暂停团队同步。','Multiple host flags; team sync is suspended.'},
    epoch_unwritable={'无法保存启动序号；请检查 Mod 的 Data 目录权限，程序会重试。','Cannot persist the boot epoch. Check the mod Data directory permissions; retrying.'},
    world_transition={'正在换图，已释放旧界面与事件引用。','World transition: retired UI and event references released.'},
}
local function captureMessage()
    local messages=statusMessages[S.captureStatus.reason] or statusMessages.starting
    return L.choose(messages[1],messages[2])
end
local function captureStatus(reason,details)
    local changed=S.captureStatus.reason~=reason
    S.captureStatus=details or {};S.captureStatus.reason=reason
    if S.panel then S.panel.dirty=true end
    if changed then print('[FFWStats] capture='..reason..' '..captureMessage()..'\n') end
end
S.paths=Config.paths(source)
local epoch,epochError=Config.nextEpoch(S.paths.epoch)
if not epoch then report('统计采集未启动：无法保存启动序号。请确认 Data 目录存在：'..tostring(epochError)) end
local transport,transportReady
local function refreshTransport()
    if S.connection then transport=S.connection:transport() else transport=_G.FFWTeamSync end
    transportReady=type(transport)=='table' and transport.apiVersion==1
        and type(transport.localPlayerId or transport.localSteamId)=='function' and type(transport.poll)=='function'
        and type(transport.send)=='function' and type(transport.close)=='function'
    if S.session and transportReady then S.session.options.transport=transport end
end
refreshTransport()
if not transportReady then report('统计同步桥 FFWTeamSync 不可用；保留已保存的上一局。') end
local adapter
local wall,lastSystem,lastReal,lastClockWorld=0,os.time(),nil,nil
local function wallClock()
    local system=os.time()
    local real,key
    if adapter and adapter.realClock then real,key=adapter:realClock() end
    local delta=math.max(0,system-lastSystem)
    if real and lastReal and key==lastClockWorld then delta=math.max(0,real-lastReal) end
    wall=wall+delta;lastSystem,lastReal,lastClockWorld=system,real,key
    return wall
end
local function uiController()
    if not adapter then return nil end
    local controller=adapter.uiController and adapter:uiController() or adapter.controller
    S.uiTrace.controllerReady=controller~=nil
    return controller
end
S.hudSettings=environment.require('HudSettings').new{path=S.paths.root..'/Data/hud-settings.json',enabled=Config.hudEnabled~=false}
S.hud=Hud.new({settings=S.hudSettings,isStale=function()
    local session=S.session
    if session and session.isHost then return false end
    return not session or not session.sync or session.sync:status().snapshotStale==true
end})
S.hudRenderer=UMG.new({getController=uiController,
    passive=true,layout=Hud.layout,zOrder=9800})
local function refreshHud()
    if S.session and S.session.phase=='active' and S.identityReady and not S.panel.visible then
        local ok,err=S.hudRenderer:render(S.hud:model())
        if ok==nil and err then report('实时统计：'..tostring(err)) end
    else S.hudRenderer:hide() end
end
S.renderer=UMG.new({getController=uiController,
    onAction=function(action,value) if S.enabled then S.panel:mouse(action,value) end end})
S.panel=Panel.new({hudSettings=S.hudSettings,hotkeys=Config.hotkeys,refreshSeconds=Config.viewSeconds,clock=wallClock,isStale=S.hud.options.isStale,
    emptyMessage=function() return L.text('尚无任务统计')..'\n'..captureMessage() end,
    render=function(model)
        protected(function()
            local ok,err=S.renderer:render(model)
            S.uiTrace.visible=S.panel.visible;S.uiTrace.attached=S.renderer.attached==true
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
S.connection=environment.require('Connection').new{
    path=S.paths.root..'/Data/connection-settings.json',getBridge=function()return _G.FFWTeamSync end,
    getContext=function()return adapter and adapter:localIdentityContext() end,
    isActive=function()
        if not adapter or adapter:roomState()~='saloon' then return true end
        return S.session.phase=='active' or S.session.phase=='finishing'
    end,
    onChanged=function(identityChanged)
        if not S.enabled then return end
        if identityChanged then
            refreshTransport();S.identityReady=false
            if adapter then adapter.pawnPlayers={};adapter:refreshRoster() end
        end
        if S.panel then S.panel.dirty=true end
    end,
}
S.panel.options.connection=S.connection
S.panel.options.readInput=function(id)return S.renderer:input(id)end

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
local function retryEpoch()
    if epoch then return end
    epoch,epochError=Config.nextEpoch(S.paths.epoch)
    if epoch then S.session.epoch=epoch;S.session.options.epoch=epoch end
end
adapter=Adapter.new({
    identity=function()return S.connection:identity()end,
    onRoster=function(roster,localId,hostId,diagnostics)
        S.connection:onRoster(roster,diagnostics)
        refreshTransport();retryEpoch()
        local nativeId,nativeError
        if transportReady then nativeId,nativeError=(transport.localPlayerId or transport.localSteamId)() end
        S.identityReady=type(nativeId)=='string' and nativeId==localId and roster[localId]~=nil and hostId~=nil and roster[hostId]~=nil
            and (not diagnostics or ((diagnostics.duplicateIds or 0)==0 and not diagnostics.hostConflict))
        local details={epochReady=epoch~=nil,nativeReady=type(nativeId)=='string',
            localInRoster=localId~=nil and roster[localId]~=nil,hostInRoster=hostId~=nil and roster[hostId]~=nil,
            observedMembers=diagnostics and diagnostics.members,unmappedIds=diagnostics and diagnostics.unmappedIds}
        local reason='ready'
        if not transportReady then reason='bridge_unavailable'
        elseif type(nativeId)~='string' then reason='native_identity_pending'
        elseif diagnostics and diagnostics.unmappedIds>0 and not localId then reason='unmapped_roster_id'
        elseif localId and nativeId~=localId then reason='identity_mismatch'
        elseif diagnostics and (diagnostics.duplicateIds or 0)>0 then reason='duplicate_ids'
        elseif diagnostics and diagnostics.hostConflict then reason='host_conflict'
        elseif not details.localInRoster then reason='roster_pending'
        elseif diagnostics and diagnostics.hostFlags>1 then reason='ambiguous_host'
        elseif not details.hostInRoster then reason='host_pending'
        elseif not epoch then reason='epoch_unwritable' end
        captureStatus(reason,details)
        if not S.identityReady then
            S.session:setRoster({},nil,nil,adapter:clock())
            if nativeError then report(nativeError)
            elseif nativeId and localId and nativeId~=localId then report('本机控制器身份与同步桥不一致，等待角色刷新。') end
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
    onWorldChanged=function()
        if S.connection then S.connection:onWorldChanged()end
        S.inputGeneration=S.inputGeneration+1;S.identityReady=false;S.pendingStart=nil
        S.session:setRoster({},nil,nil)
        S.renderer:hide(true);S.hudRenderer:hide(true)
        captureStatus('world_transition')
    end,
})
S.adapter=adapter
local nextPoll,nextRender,nextLanguage=0,0,0
function S.update()
    if not S.enabled then return false end
    return protected(function()
        if adapter.uiController then adapter:uiController() end
        local now=wallClock()
        if S.connection.mode=='lan' then S.connection:update(adapter:roomState())end
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
    if not S.enabled then return end
    S.enabled=false
    ExecuteInGameThread(function()
        protected(function() adapter:flush();S.session:publish() end)
        if S.loopHandle then CancelDelayedAction(S.loopHandle) end
        protected(function() S.connection:stop(true) end)
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
            if current and current.enabled and current.keyActions[key] then
                if key==Key.F8 then current.uiTrace.keyCallbacks=current.uiTrace.keyCallbacks+1 end
                current.keyActions[key]()
            end
        end)
        S.keysInstalled[key]=true
    end
end
local function executeInput(callback)
    local generation=S.inputGeneration
    ExecuteInGameThread(function()
        if S.enabled and adapter.uiController then adapter:uiController() end
        if S.enabled and generation==S.inputGeneration and not adapter.loading then
            S.uiTrace.executed=S.uiTrace.executed+1;protected(callback)
            print(string.format('[FFWStats] ui keys=%d executed=%d visible=%s controller=%s attached=%s\n',
                S.uiTrace.keyCallbacks,S.uiTrace.executed,tostring(S.panel.visible),
                tostring(S.uiTrace.controllerReady==true),tostring(S.renderer.attached==true)))
        end
    end)
end
S.panel:bindKeys({Key=Key,execute=executeInput,register=bind})
for _,key in ipairs({Key.F2,Key.F4,Key.F7}) do
    bind(key,function()
        executeInput(function()
            if S.panel.visible then S.panel.visible=false;S.panel:refresh() end
        end)
    end)
end
if not S.mapHooksInstalled and type(RegisterLoadMapPreHook)=='function' and type(RegisterLoadMapPostHook)=='function' then
    -- These official callbacks return nil: they never override game travel.
    RegisterLoadMapPreHook(function()
        local current=_G.FFWStats
        if current and current.enabled then current.adapter:retireWorld('map_load',true) end
    end)
    RegisterLoadMapPostHook(function()
        local current=_G.FFWStats
        if current and current.enabled then current.adapter.loading=false end
    end)
    S.mapHooksInstalled=true
end
ExecuteInGameThread(function() if S.enabled then protected(function() adapter:install() end) end end)
S.loopHandle=LoopInGameThreadWithDelay(Config.loopMilliseconds,S.update)
print('[FFWStats] 已加载。F8 开关详情，可点击标签；新增团队贡献页。左上角显示自身 DPS 峰值、承伤和团队排行。PgUp/PgDn 指标；Home/End 区间；鼠标翻分项页；联机设置可配置 LAN/IP。覆盖保持部分数据/不可用。\n')
return S
