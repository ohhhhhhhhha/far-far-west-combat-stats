package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local T=dofile('FFWTools/tests/stats_testlib.lua')
local Adapter=require('GameAdapter')
local enemyPath='/Game/Enemies/BP_Enemy.BP_Enemy_C:'
local fixtureWorld={IsValid=function() return true end,GetFullName=function() return 'World fixture' end,
    GetAddress=function() return 'fixture-world' end}
local function object(key,props)
    local o=props or {};o.key=key
    function o:IsValid() return true end
    function o:GetFullName() return self.key end
    function o:GetAddress() return self.address or self.key end
    function o:GetWorld() return self.world or fixtureWorld end
    function o:HasAuthority() return self.authoritative~=false end
    return o
end
local function setup()
    local events,ends={},{}
    local a=Adapter.new({onEvent=function(e,t,own) events[#events+1]={e=e,t=t,own=own} end,
        onEnd=function(t,r) ends[#ends+1]={time=t,reason=r,eventCount=#events} end})
    a.localId='a';a.hostSteamId='a';a.engineTime=10;a.worldKey='World fixture@fixture-world'
    function a:refreshRoster() return true end
    function a:registerHooks() end
    function a:gameTime() return self.engineTime end
    function a:playerId(o) return o and o.playerId end
    function a:category(_,__,___,dot) return dot and 'dot' or 'primary' end
    a:install();a:beginMission(object('mission-1'),true)
    local function call(path,...) return a.definitions[path].callback(...) end
    return a,events,ends,call
end
T.test('game adapter retains attack ordering and final amount until a safe flush',function()
    local a,e,_,call=setup();a.engineTime=11
    local player=object('player',{playerId='a'});local enemy=object('enemy',{health=-163.75,lastHitCauser=player})
    call(enemyPath..'F_DamageFeedback_Multicast',enemy,183.75,player,nil,'itemLongRanger',1)
    call(enemyPath..'F_DestroyEnemy',enemy)
    call(enemyPath..'F_ServerDamages',enemy,200,nil,player,1,'itemLongRanger')
    T.eq(#e,0);a:flush();T.eq(#e,2)
    T.eq(e[1].e.amount,183.75);T.eq(e[1].e.sourceCategory,'primary');T.eq(e[1].t,1)
    T.eq(e[2].e.kind,'kill')
end)
T.test('final feedback metadata classifies damage even without a balanced server-input pair',function()
    local a,events,_,call=setup();a.category=nil;a.players={}
    local player=object('player',{playerId='a'});local enemy=object('enemy')
    call(enemyPath..'F_DamageFeedback_Multicast',enemy,90.083335682884521,player,nil,'itemLongRanger',1)
    a:flush();T.eq(events[1].e.sourceCategory,'primary');T.eq(events[1].e.amount,90.083335682884521)
    call(enemyPath..'F_DamageFeedback_Multicast',enemy,12,player,nil,'itemDualRevolver',1)
    a:flush();T.eq(events[2].e.sourceCategory,'secondary')
    call(enemyPath..'F_DamageFeedback_Multicast',enemy,20,player,nil,'itemIce',6)
    a:flush();T.eq(events[3].e.sourceCategory,'spell')
end)
T.test('mission end drains old events before reporting the frozen end',function()
    local a,e,ends=setup();a.engineTime=12
    a:emit({kind='ammo',amount=1},true);a:endMission('finished')
    a.engineTime=20;a:emit({kind='ammo',amount=99},true);a:endMission('lobby')
    T.eq(#ends,0);a:flush()
    T.eq(#e,1);T.eq(e[1].own,true);T.eq(ends[1].eventCount,1);T.eq(ends[1].time,2)
    T.eq(a.active,false);a:flush();T.eq(#ends,1)
end)
T.test('final server metadata can close a damage group after end requested',function()
    local a,e,_,call=setup();a.engineTime=11
    local p=object('player',{playerId='a'});local enemy=object('enemy')
    call(enemyPath..'F_DamageFeedback_Multicast',enemy,2,p,nil,'itemLongRanger',2)
    a:endMission('finished')
    call(enemyPath..'F_ServerDamages',enemy,2,'/Game/Gamework/DamageTypes/BP_DamageType_Buff_Fire.BP_DamageType_Buff_Fire_C',p,2,'itemLongRanger')
    a:flush();T.eq(e[1].e.sourceCategory,'dot')
end)
T.test('guest enemy feedback is never counted as authoritative damage',function()
    local a,e,_,call=setup();local p=object('player',{playerId='a'})
    call(enemyPath..'F_DamageFeedback_Multicast',object('enemy',{authoritative=false}),99,p,nil,'itemLongRanger',1)
    a:flush();T.eq(#e,0)
end)
T.test('new mission drains prior mission before resetting its clock',function()
    local a,e,ends=setup();a.engineTime=14;a:emit({kind='ammo',amount=1},true)
    a:beginMission(object('mission-2'),true)
    T.eq(#e,1);T.eq(e[1].t,4);T.eq(ends[1].reason,'new_mission');T.eq(a:clock(),0)
    a:beginMission(object('mission-2'),true);T.eq(#ends,1)
end)
T.test('attack adapter owns reload binding instead of unconditional reload count',function()
    local a=setup();T.eq(type(a._attackAdapter),'table')
    T.eq(type(a.definitions['/Game/Items/Assets/BP_PlayerBullet.BP_PlayerBullet_C:F_TraceBullet']),'table')
end)
T.test('pending-kill pawn still resolves a previously observed player identity',function()
    local a=setup();local pawn=object('old-pawn');function pawn:IsValid() return false end
    a.pawnPlayers['old-pawn']='a'
    T.eq(Adapter.playerId(a,pawn),'a')
end)
T.test('revive post can match a destroyed ghost to the completed possession',function()
    local a,e,_,call=setup();local ghost=object('old-ghost');function ghost:IsValid() return false end
    a.respawns['old-ghost']='b'
    call('/Game/Player/BP_PlayerState.BP_PlayerState_C:F_RevivePlayer',object('rescuer',{playerId='a'}),ghost)
    a:flush();T.eq(#e,1);T.eq(e[1].e.kind,'revive_complete');T.eq(e[1].e.targetPlayerId,'b')
end)
T.test('explicit next mission with the same persistent actor name gets a new run',function()
    local starts={};local a=setup();a.options.onStart=function(key) starts[#starts+1]=key end
    a:endMission('finished');a:flush()
    a:beginMission(object('mission-1',{address=222}),true)
    T.eq(a.active,true);T.eq(#starts,1)
    local key=starts[1]
    a:endMission('finished');a:flush();a:beginMission(object('mission-1',{address=222}),true)
    T.eq(#starts,2);T.eq(starts[2]~=key,true)
end)
T.test('poll does not restart a finished manager that is still present',function()
    local a,e,ends=setup();a:endMission('finished');a:flush()
    a:beginMission(object('mission-1'),false);T.eq(a.active,false);T.eq(#ends,1)
end)
T.test('feedback carries its own exact category without a second server callback',function()
 local a,e,_,call=setup();a.category=Adapter.category;a.players.a={}
 local p=object('player',{playerId='a'});local enemy=object('enemy')
 call(enemyPath..'F_DamageFeedback_Multicast',enemy,42,p,nil,'itemDualRevolver',1)
 a:flush();T.eq(e[1].e.amount,42);T.eq(e[1].e.sourceCategory,'secondary')
end)
T.finish()
