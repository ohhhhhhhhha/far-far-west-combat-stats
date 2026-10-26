-- Bindings verified against Far Far West 0.3.0.7 / CL2852. See research/bindings.md.
-- Hooks observe settlement outputs and never return overrides or call gameplay actions.
local Events=require('Events')
local EventBuffer=require('EventBuffer')
local AttackAdapter=require('AttackAdapter')
local A={};A.__index=A
local PS='/Game/Player/BP_PlayerState.BP_PlayerState_C'
local PLAYER='/Game/Player/BP_Player.BP_Player_C'
local ENEMY='/Game/Enemies/BP_Enemy.BP_Enemy_C'
local SHIELD='/Game/Player/AC_PlayerState_Shield.AC_PlayerState_Shield_C'
local MASTER='/Game/Gamework/BP_Manager_GameMaster.BP_Manager_GameMaster_C'
local function valid(o)
    if not o then return false end
    local ok,v=pcall(function() return o:IsValid() end);return ok and v==true
end
local function field(o,k)
    local ok,v=pcall(function() return o[k] end)
    if ok and not tostring(v):match('^TrivialObject:') then return v end
end
local function str(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function() return v:ToString() end);if ok then return s end
end
local function name(o)
    -- Post hooks may receive a pawn/ghost just marked pending-kill. Its recorded
    -- identity remains usable without reading gameplay properties from it.
    local ok,n=pcall(function() return o:GetFullName() end)
    if ok and type(n)=='string' then return n end
end
local function authority(o)
    local ok,v=pcall(function() return o:HasAuthority() end);return ok and v==true
end
local function each(array,fn)
    if array then array:ForEach(function(_,v) fn(v:get()) end) end
end
local function count(array,wanted)
    local result=0;each(array,function(v) if str(v)==wanted then result=result+1 end end);return result
end
local function cdo(path)
    local cls=StaticFindObject(path);if valid(cls) then return cls:GetCDO() end
end
local selection={
    primary='wepA_2_C099A0F04138D662182F8D9C94DCA8C6',secondary='wepB_4_EE50A5DA4381738DA8C10CB8353016D9',
    'spellA_8_D8F383D94883A467CF929A9E452C176D','spellB_10_CA70EE57499218F37A2F3F93523EDEC8','spellC_14_C211B06A4A281EC29108A48303174C4C',
}
function A.new(options)
    return setmetatable({options=options or {},hooks={},definitions={},players={},pawnPlayers={},health={},healthChanges={},
        shieldEvents={},deaths={},revived={},respawns={},bosses={},active=false,lastClock=0,errors={},buffer=EventBuffer.new()},A)
end
function A:report(message)
    if not self.errors[message] then self.errors[message]=true;print('[FFWStats] '..message..'\n') end
end
function A:gameTime(context)
    if not valid(self.gp) then self.gp=cdo('/Script/Engine.GameplayStatics') end
    if not valid(self.gp) then return nil end
    local t=self.gp:GetTimeSeconds(context or self.controller)
    return type(t)=='number' and t or nil
end
function A:clock()
    if self.active then
        local t=self:gameTime();if t and self.anchor then self.lastClock=math.max(self.lastClock,t-self.anchor) end
    end
    return self.lastClock
end
function A:playerId(object)
    local cached=self.pawnPlayers[name(object)];if cached then return cached end
    if not valid(object) then return nil end
    if not valid(self.psClass) or not valid(self.mp) then return nil end
    local ps
    if object:IsA(self.psClass) then ps=object
    else ps=field(object,'PlayerState') end
    if not valid(ps) or not ps:IsA(self.psClass) then return nil end
    local id=str(self.mp:MP_UniqueNetIdToString(ps['Native Net ID']))
    if not id or not id:match('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$') then return nil end
    self.pawnPlayers[name(object)]=id
    return id,ps
end
function A:refreshRoster()
    local helpers=require('UEHelpers');self.controller=helpers.GetPlayerController()
    if not valid(self.controller) then return false end
    self.gp=self.gp or cdo('/Script/Engine.GameplayStatics')
    self.mp=self.mp or cdo('/Script/FarFarWest.MultiplayerStatics')
    self.psClass=self.psClass or StaticFindObject(PS)
    if not valid(self.gp) or not valid(self.mp) or not valid(self.psClass) then return false end
    self.gameState=self.gp:GetGameState(self.controller)
    if not valid(self.gameState) then return false end
    local roster,players={},{};self.hostSteamId=nil
    each(self.gameState.PlayerArray,function(ps)
        local id=self:playerId(ps)
        if id then
            local pawn=ps:GetPawn();if valid(pawn) then
                local pawnName=name(pawn);self.pawnPlayers[pawnName]=id
                self.currentPawn=self.currentPawn or {};self.currentPawn[id]=pawnName
            end
            players[id]=ps
            roster[id]={playerId=id,name=str(ps:GetPlayerName()) or '玩家',isHost=field(ps,'isHost')==true}
            if roster[id].isHost then self.hostSteamId=id end
            if type(ps.playerHeal)=='number' and self.health[id]==nil then self.health[id]=ps.playerHeal end
        end
    end)
    self.localId=self:playerId(field(self.controller,'PlayerState'))
    self.players=players;self.roster=roster
    if self.options.onRoster then self.options.onRoster(roster,self.localId,self.hostSteamId) end
    return true
end
function A:category(id,item,element,verifiedDot)
    local ps=self.players[id];local r={itemName=item,element=element,spells={},verifiedDot=verifiedDot}
    local direct=Events.sourceCategory(r)
    if direct~='unknown' then return direct end
    if ps then
        local selected=field(ps,'selectedPlayerItemsServer')
        local function itemName(key)
            local cls=field(selected,key);return valid(cls) and str(field(cls:GetCDO(),'itemName')) or nil
        end
        r.primary=itemName(selection.primary);r.secondary=itemName(selection.secondary)
        for _,key in ipairs(selection) do local n=itemName(key);if n then r.spells[n]=true end end
    end
    return Events.sourceCategory(r)
end
function A:emit(event,localOnly)
    if event and self.active and not self.endRequested then self.buffer:push(event,self:clock(),localOnly) end
end
function A:flush()
    local n=self.buffer:flush(function(event,time,localOnly)
        if self.options.onEvent then self.options.onEvent(event,time,localOnly) end
    end)
    if self.endRequested then
        local ending=self.endRequested;self.endRequested=nil;self.active=false
        if self.options.onEnd then self.options.onEnd(ending.time,ending.reason) end
    end
    return n
end
function A:beginMission(manager,fromStartEvent)
    local key=name(manager)
    if not key or key:find('/L_Lobby',1,true) then return end
    local token=key..':'..tostring(manager:GetAddress())
    if self.managerToken==token and (self.active or not fromStartEvent) then return end
    if self.active then self:endMission('new_mission') end
    self:flush()
    self:refreshRoster()
    if not self.localId then return end
    self.missionSequence=(self.missionSequence or 0)+1
    self.managerToken=token;self.missionKey=token..':run:'..self.missionSequence
    self.anchor=self:gameTime(manager);self.lastClock=0;self.active=true
    self.deaths={};self.revived={};self.respawns={};self.bosses={};self.encounterId=nil;self.healthChanges={};self.shieldEvents={}
    if self.options.onStart then self.options.onStart(self.missionKey,fromStartEvent==true,self.localId==self.hostSteamId) end
end
function A:endMission(reason)
    if not self.active or self.endRequested then return end
    self.endRequested={time=self:clock(),reason=reason}
end
function A:bossContact(enemy)
    if field(enemy,'isBoss')~=true then return end
    local id=name(enemy);if not id then return end
    self.bosses[id]=true
    if not self.encounterId then
        self.encounterId='boss:'..id
        self:emit({kind='encounter_start',encounterId=self.encounterId,name='Boss 战'})
    end
end
function A:bind(path,callback,native)
    self.definitions[path]={callback=callback,native=native}
end
function A:registerHooks()
    for path,definition in pairs(self.definitions) do
        local fn=StaticFindObject(path)
        if valid(fn) then
            local pointer=fn:GetAddress();local old=self.hooks[path]
            if not old or old.pointer~=pointer then
                if old then pcall(UnregisterHook,path,old.pre,old.post) end
                local wrapped=function(context,...)
                    local args={};for i,param in ipairs({...}) do args[i]=param:get() end
                    local ok,err=pcall(definition.callback,context:get(),table.unpack(args,1,select('#',...)))
                    if not ok then self:report(path..': '..tostring(err)) end
                end
                local ok,pre,post
                if definition.native then ok,pre,post=pcall(RegisterHook,path,function() end,wrapped)
                else ok,pre,post=pcall(RegisterHook,path,wrapped) end
                if ok then self.hooks[path]={pointer=pointer,pre=pre,post=post} else self:report(tostring(pre)) end
            end
        end
    end
end
function A:install()
    self:refreshRoster()
    self:bind(MASTER..':F_StartGame',function(manager) self:beginMission(manager,true) end)
    self:bind('/Game/Player/BP_GameState.BP_GameState_C:OnRep_hasFinishedMission',function(gs)
        if gs.hasFinishedMission==true then self:endMission('finished') end
    end)
    self:bind(PS..':F_GoToLobby_Server',function() self:endMission('return_to_lobby') end)
    self:bind(ENEMY..':F_DamageFeedback_Multicast',function(enemy,amount,owner,damageType,item,element)
        if not self.active or self.endRequested or not authority(enemy) then return end
        local id=self:playerId(owner);if not id then return end
        self:bossContact(enemy)
        local event=Events.enemyDamage({active=true,authority=true,sourcePlayerId=id,targetId=name(enemy),amount=amount,
            category=self:category(id,str(item),element,AttackAdapter.isDot(damageType))})
        if event then self.buffer:damage(event,self:clock(),self:gameTime(enemy),{item=str(item),element=element}) end
    end)
    self:bind(ENEMY..':F_ServerDamages',function(enemy,_,damageType,owner,element,item)
        if not self.active or not authority(enemy) then return end
        local id=self:playerId(owner)
        self.buffer:settlement(name(enemy),self:gameTime(enemy),{owner=id,item=str(item),element=element,
            category=id and self:category(id,str(item),element,AttackAdapter.isDot(damageType)) or 'unknown'})
    end)
    self:bind(ENEMY..':F_DestroyEnemy',function(enemy)
        if not self.active or not authority(enemy) or type(enemy.health)~='number' or enemy.health>0 then return end
        local id=self:playerId(field(enemy,'lastHitCauser'));if not id then return end
        local target=name(enemy);if not target then return end
        local classification=enemy.isBoss==true and 'boss' or (enemy.isElite==true and 'elite' or 'regular')
        self:emit({kind='kill',sourcePlayerId=id,targetId=target,targetClass=classification})
        self.bosses[target]=nil
        if self.encounterId and next(self.bosses)==nil then
            self:emit({kind='encounter_end',encounterId=self.encounterId});self.encounterId=nil
        end
    end)
    self:bind(SHIELD..':F_ConsumeShield_Server',function(component,currentHp,damages,remaining)
        local ps=field(component,'owningPlayerState')
        if not self.active or not authority(ps) then return end
        local id=self:playerId(ps);if not id then return end
        local list=self.shieldEvents[id] or {};self.shieldEvents[id]=list
        list[#list+1]={targetPlayerId=id,currentPlayerHeal=ps.playerHeal,damages=damages,outputHeal=remaining,stamp=self:gameTime(ps)}
    end)
    self:bind(PLAYER..':F_ServerDamages',function(player,_,__,causer)
        if not self.active or not authority(player) then return end
        local id=self:playerId(player);local list=id and self.shieldEvents[id]
        if not list or #list==0 then return end
        local r=table.remove(list)
        if r.stamp~=self:gameTime(player) then return end
        local source=self:playerId(causer)
        r.sourceCategory=source and '队友/自身' or (valid(causer) and causer:GetClass():GetFName():ToString() or '环境')
        r.isTutorial=field(player,'isTutorial')==true
        if valid(causer) then self:bossContact(causer) end
        self:emit(Events.incoming(r))
    end)
    self:bind(PS..':OnRep_playerHeal',function(ps)
        local id=self:playerId(ps);if not id or type(ps.playerHeal)~='number' then return end
        local old=self.health[id];self.health[id]=ps.playerHeal
        if self.active and authority(ps) and old and old>=0 then
            self.healthChanges[id]={before=old,after=ps.playerHeal,stamp=self:gameTime(ps)}
        end
    end)
    self:bind(PS..':F_HealSelf_Server',function(ps,amount,_,source)
        if not self.active or not authority(ps) or amount<=0 then return end
        local targetId=self:playerId(ps);local sourceId=self:playerId(source)
        local change=targetId and self.healthChanges[targetId]
        if not sourceId or not change or change.stamp~=self:gameTime(ps) or change.after~=ps.playerHeal then return end
        local pawn=ps:GetPawn();if not valid(pawn) or name(pawn):find('BP_PlayerGhost',1,true) then return end
        local gameplay=cdo('/Game/Gamework/BPFL_Gameplay.BPFL_Gameplay_C')
        local active={};gameplay:F_IsModifierActive(FName('modifierDrought'),ps,active)
        if type(active.Active)~='boolean' then return end
        local attempted=amount*(active.Active and 0.75 or 1)
        local n=count(ps.itemHeroJokers,'jokerThickSkin')
        if n>0 then
            local curve=StaticFindObject('/Game/Spells/Jokers/JokerCurve/C_Joker_ThickSkin_Heal.C_Joker_ThickSkin_Heal')
            if not valid(curve) then return end
            attempted=attempted*curve:GetFloatValue(n)
        end
        self.healthChanges[targetId]=nil
        self:emit(Events.heal({sourcePlayerId=sourceId,targetPlayerId=targetId,amount=attempted,effectiveAmount=math.max(0,change.after-change.before)}))
    end)
    self:bind('/Script/Engine.Controller:Possess',function(controller,newPawn)
        if not valid(newPawn) then return end
        local id=self:playerId(field(controller,'PlayerState'));if not id then return end
        local old=self.currentPawn and self.currentPawn[id]
        self.currentPawn=self.currentPawn or {};self.currentPawn[id]=name(newPawn);self.pawnPlayers[name(newPawn)]=id
        if self.active and authority(controller) and old and old:find('BP_PlayerGhost',1,true) and not name(newPawn):find('BP_PlayerGhost',1,true) then
            self.respawns[old]=id;self:emit({kind='respawn',targetPlayerId=id})
        end
    end,true)
    self:bind(PLAYER..':F_Die_Server',function(pawn)
        if not self.active or not authority(pawn) then return end
        local key=name(pawn);local id=self:playerId(pawn)
        if not key or not id or self.deaths[key] then return end
        self.deaths[key]=true
        -- This game changes a dead character into a revivable ghost immediately.
        self:emit({kind='death',targetPlayerId=id});self:emit({kind='down',targetPlayerId=id})
    end)
    self:bind(PS..':F_RevivePlayer',function(rescuer,ghost)
        if not self.active or not authority(rescuer) then return end
        local key=name(ghost);local target=key and self.respawns[key];local source=self:playerId(rescuer)
        if target and source and target~=source and not self.revived[key] then
            self.revived[key]=true;self:emit({kind='revive_complete',sourcePlayerId=source,targetPlayerId=target})
        end
    end)
    AttackAdapter.install(self)
    self:registerHooks()
end
function A:poll()
    self:registerHooks()
    if not self:refreshRoster() then return end
    local location=name(self.controller) or ''
    if location:find('/L_Lobby',1,true) or location:find('/L_Map_TitleScreen',1,true) then
        self:endMission('lobby');self.managerToken=nil;return
    end
    if self.gameState.hasFinishedMission==true then self:endMission('finished');return end
    -- A mod loaded after the explicit start can observe the remainder, but its
    -- coverage is partial. A connected guest adopts the host's whole snapshot.
    if not self.active then
        for _,manager in ipairs(FindAllOf('BP_Manager_GameMaster_C') or {}) do
            if field(manager,'gameRunning')==true then self:beginMission(manager,false) end
        end
    end
end
function A:stop()
    for path,h in pairs(self.hooks) do pcall(UnregisterHook,path,h.pre,h.post) end
    self.hooks={}
end
A.valid=valid;A.field=field;A.string=str
return A
