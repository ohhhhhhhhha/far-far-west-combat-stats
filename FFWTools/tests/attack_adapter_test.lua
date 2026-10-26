package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib')
local loaded,Attack=pcall(require,'AttackAdapter')
local ITEM='/Game/Items/BP_Item.BP_Item_C:'
local BULLET='/Game/Items/Assets/BP_PlayerBullet.BP_PlayerBullet_C:'
local FL='/Game/Items/FL_Items.FL_Items_C:'
local SHOTGUN='/Game/Items/BP_Item_Shotgun.BP_Item_Shotgun_C:'
local MAG='currentMagazineAmmos_10_76E089514907BA2E4DDB1CA16CEC4B6B'
local TOTAL='currentTotalAmmos_17_DDF8963D42826C9B6D9A9E92E9563632'
local DATA_A='datasWepA_24_C099A0F04138D662182F8D9C94DCA8C6'
local DATA_B='datasWepB_25_EE50A5DA4381738DA8C10CB8353016D9'
-- Match UE4SS push_nameproperty(Operation::Set): native name parameters need
-- FName userdata, not Lua strings. The marker stands in for that native value.
local fnameType={}
FName=function(value) return setmetatable({value=value},fnameType) end
local function nameValue(value)
    assert(getmetatable(value)==fnameType,'native NameProperty requires FName')
    return value.value
end
local function object(key,fields)
    local o=fields or {};o.key=key
    function o:IsValid() return self.invalid~=true end
    function o:GetFullName() return self.key end
    function o:ActorHasTag(tag) nameValue(tag);return false end
    return o
end
local function array(values)
    return {ForEach=function(_,fn) for i,v in ipairs(values) do fn(i-1,{get=function() return v end}) end end}
end
package.loaded.UEHelpers={GetActorFromHitResult=function(hit)
    if hit.unreadable then error('unreadable HitResult') end
    return hit.actor
end}
local function fixture(itemName)
    T.eq(loaded,true,'AttackAdapter loads')
    local ps=object('PlayerState',{playerRuntimeStats={}})
    local pawn=object('LocalPawn',{PlayerState=ps,localControlled=true})
    function pawn:IsLocallyControlled() return self.localControlled end
    local a={active=true,localId='local',players={['local']=ps},missionKey='mission-A',hooks={},events={},now=10}
    function a:bind(path,fn,native) self.hooks[path]=fn;T.eq(native,nil,'Blueprint uses post hook') end
    function a:playerId(actor) if actor==pawn or actor==ps then return 'local',ps end end
    function a:category(_,item) return item=='itemPistol' and 'secondary' or 'primary' end
    function a:gameTime() return self.now end
    function a:emit(e,localOnly) self.events[#self.events+1]=e;T.eq(localOnly,true,'local-only telemetry') end
    local item=object('HeldItem',{owningPlayer=pawn,itemName=itemName or 'itemLongRanger',itemCategory=1,lastShotConsumedAmmo=true})
    local bullet=object('PooledBullet',{owningPlayer=pawn,associatedItemName=item.itemName,isRicocheting=false,isLastOrUniqueShot=true,impacts=array({})})
    local f={a=a,ps=ps,pawn=pawn,item=item,bullet=bullet,state=Attack.install(a)}
    function f:call(path,...) T.eq(type(a.hooks[path]),'function','hook exists '..path);a.hooks[path](...) end
    function f:data(mag,total)
        local data={[MAG]=mag,[TOTAL]=total};ps.playerRuntimeStats[item.itemCategory==2 and DATA_B or DATA_A]=data;return data
    end
    function f:get(mag,total) self:data(mag,total);self:call(ITEM..'F_GetItemDatas',item,{[MAG]=mag,[TOTAL]=total}) end
    function f:consume(before,after,requested,camper)
        self:get(before,30);self:data(after,30);self:call(ITEM..'F_ConsumeAmmos',item,requested or 1,camper~=false,true)
    end
    function f:trace(hits)
        bullet.impacts=array(hits or {});self:call(BULLET..'F_TraceBullet',bullet)
    end
    function f:impact(hit,world)
        self:call(FL..'F_ApplyImpactDamages',object('FL_CDO'),40,item.itemName,false,hit,ps,1,true,world or bullet,40)
    end
    function f:finish(shield) self:call(BULLET..'F_ApplyDamages',bullet,false,shield==true,false) end
    function f:events(kind,mode)
        local result={};for _,e in ipairs(a.events) do if e.kind==kind and (not mode or e.accuracyMode==mode) then result[#result+1]=e end end;return result
    end
    function f:reload(beforeReserve,afterReserve)
        self:get(5,beforeReserve);self:data(5,afterReserve);self:call(ITEM..'F_ReloadAmmos',item,1,false)
    end
    return f
end
local function enemy(key)
    local e=object(key or 'Enemy',{health=20});function e:ActorHasTag(tag) return nameValue(tag)=='enemy' end;return e
end

T.test('DoT requires one of three verified exact class paths',function()
    T.eq(loaded,true)
    for _,element in ipairs({'Fire','Acid','Elec'}) do
        local path='/Game/Gamework/DamageTypes/BP_DamageType_Buff_'..element..'.BP_DamageType_Buff_'..element..'_C'
        T.eq(Attack.isDot(path),true);T.eq(Attack.isDot(object('BlueprintGeneratedClass '..path)),true)
    end
    for _,v in ipairs({8,'BP_DamageType_Buff_Fire_C','/Game/Unverified/BP_DamageType_Buff_Fire.BP_DamageType_Buff_Fire_C',
        '/Game/Gamework/DamageTypes/BP_DamageType_Buff_Shroom.BP_DamageType_Buff_Shroom_C',
        '/Game/Gamework/DamageTypes/BP_DamageType_Bullets.BP_DamageType_Bullets_C'}) do T.eq(Attack.isDot(v),false) end
    T.eq(Attack.isDot(nil),false)
end)
T.test('a pooled object gets a new attack ID for each completed activation',function()
    local f=fixture();local hit={actor=enemy()}
    f:trace({hit});T.eq(#f.a.events,0);f:impact(hit);f:finish();f:trace({});f:finish()
    local shots=f:events('shot');T.eq(#shots,2);T.eq(shots[1].accuracyMode,'ordinary');T.eq(shots[1].attackId==shots[2].attackId,false)
    T.eq(#f:events('hit'),1);T.eq(f:events('hit')[1].attackId,shots[1].attackId)
end)
T.test('native FName tag arguments keep nonempty completed traces in both shot and hit totals',function()
    local f=fixture()
    for _=1,4 do f:trace({});f:finish() end
    for i=1,6 do local hit={actor=enemy('Target-'..i)};f:trace({hit});f:impact(hit);f:finish() end
    T.eq(#f:events('shot'),10,'tag conversion cannot silently remove nonempty traces')
    T.eq(#f:events('hit'),6)
end)
T.test('piercing aggregates all impacts even if final output flag is false',function()
    local f=fixture();local h1,h2={actor=enemy('A')},{actor=enemy('B')}
    f:trace({h1,h2,{actor=object('Wall')}});f:impact(h1);f:impact(h2);f:finish()
    T.eq(#f:events('shot'),1);T.eq(#f:events('hit'),1)
end)
T.test('a killing impact survives actor becoming invalid after trace',function()
    local f=fixture();local target=enemy();local hit={actor=target};f:trace({hit});target.invalid=true;target.health=-100
    f:impact(hit);f:finish();T.eq(#f:events('hit'),1)
end)
T.test('arbitrary damage context and an enemy not in the trace cannot create hits',function()
    local f=fixture();local hit={actor=enemy()};f:trace({hit})
    f:impact(hit,object('Explosion'));f:impact({actor=enemy('DifferentEnemy')});f:finish();T.eq(#f:events('hit'),0)
end)
T.test('missing completion or unreadable trace does not invent a miss',function()
    local f=fixture();f:trace({});T.eq(#f:events('shot'),0)
    f:trace({{unreadable=true}});f:finish();T.eq(#f:events('shot'),0)
    f.bullet.impacts=nil;f:call(BULLET..'F_TraceBullet',f.bullet);f:finish();T.eq(#f:events('shot'),0)
end)
T.test('completed shield blocked trace is a shot but not an effective enemy hit',function()
    local f=fixture();f:trace({{actor=enemy()}});f:finish(true)
    T.eq(#f:events('shot'),1);T.eq(#f:events('hit'),0);T.eq(f:events('shot')[1].shieldBlocked,true)
end)
T.test('remote cosmetic bullets inactive missions and unknown guns remain uncounted',function()
    local f=fixture();f.pawn.localControlled=false;f:trace({});f:finish();T.eq(#f.a.events,0)
    f.pawn.localControlled=true;f.a.active=false;f:trace({});f:finish();T.eq(#f.a.events,0)
    f.a.active=true;f.bullet.associatedItemName='itemUnverified';f:trace({});f:finish();T.eq(#f.a.events,0)
end)
T.test('ricochets do not become additional initial trigger pulls',function()
    local f=fixture();f.bullet.isRicocheting=true;f:trace({});f:finish();T.eq(#f:events('shot'),0)
end)
T.test('repeated completion callback cannot count the same activation twice',function()
    local f=fixture();f:trace({});f:finish();f:finish();T.eq(#f:events('shot'),1)
end)
T.test('actual consumption uses the clamped difference not requested amount',function()
    local f=fixture();f:consume(1,0,3);T.eq(f:events('ammo')[1].amount,1)
end)
T.test('Camper free discharge emits zero actual ammo without a fresh getter',function()
    local f=fixture();f.item.lastShotConsumedAmmo=false;f:call(ITEM..'F_ConsumeAmmos',f.item,1,true,true)
    T.eq(f:events('ammo')[1].amount,0)
end)
T.test('disabled Camper check ignores stale lastShotConsumedAmmo false',function()
    local f=fixture();f.item.lastShotConsumedAmmo=false;f:consume(4,3,1,false);T.eq(f:events('ammo')[1].amount,1)
end)
T.test('secondary weapon consumes from the secondary runtime structure',function()
    local f=fixture('itemPistol');f.item.itemCategory=2;f.ps.playerRuntimeStats[DATA_A]={[MAG]=99,[TOTAL]=99}
    f:consume(6,5);T.eq(f:events('ammo')[1].amount,1)
end)
T.test('missing stale and already used getter snapshots never substitute requested ammo',function()
    local f=fixture();f:data(3,30);f:call(ITEM..'F_ConsumeAmmos',f.item,1,true,true);T.eq(#f:events('ammo'),0)
    f:get(4,30);f.a.now=11;f:data(3,30);f:call(ITEM..'F_ConsumeAmmos',f.item,1,true,true);T.eq(#f:events('ammo'),0)
    f:consume(3,2);f:data(1,30);f:call(ITEM..'F_ConsumeAmmos',f.item,1,true,true);T.eq(#f:events('ammo'),1)
end)
T.test('separate ammo and completed-shot telemetry remain independent of callback ordering',function()
    local f=fixture();f:trace({});f:finish();f:consume(3,2);T.eq(#f:events('shot'),1);T.eq(#f:events('ammo'),1)
    local p=fixture('itemPistol');p:consume(6,5);p:trace({});p:finish();T.eq(#p:events('shot'),1);T.eq(#p:events('ammo'),1)
end)
T.test('seven shotgun pellets produce one completed volley and one ammo consumed',function()
    local f=fixture('itemShotgun');f:consume(6,5)
    for n=1,7 do
        f.bullet.isLastOrUniqueShot=n==7;local hit=n==3 and {actor=enemy()} or nil
        f:trace(hit and {hit} or {});if hit then f:impact(hit) end;f:finish()
    end
    T.eq(#f:events('shot','ordinary'),0);T.eq(#f:events('shot','pellet'),7);T.eq(#f:events('shot','multi'),1)
    T.eq(f:events('shot','multi')[1].attackKind,'shotgun_volley');T.eq(#f:events('ammo'),1);T.eq(#f:events('hit'),2)
end)
T.test('OverBlast uses explicit last pellet not a hardcoded seven',function()
    local f=fixture('itemShotgun');f:consume(6,5)
    for n=1,10 do f.bullet.isLastOrUniqueShot=n==10;f:trace({});f:finish() end
    T.eq(#f:events('shot','pellet'),10);T.eq(#f:events('shot','multi'),1)
end)
T.test('incomplete shotgun volley does not imply a missed trigger pull',function()
    local f=fixture('itemShotgun');f:consume(6,5);f.bullet.isLastOrUniqueShot=false;f:trace({});f:finish()
    f.bullet.isLastOrUniqueShot=true;f:trace({}) -- completion callback never arrives
    T.eq(#f:events('shot','multi'),0)
end)
T.test('shotgun without observed consume has pellet data but no invented volley',function()
    local f=fixture('itemShotgun');f:trace({});f:finish();T.eq(#f:events('shot','pellet'),1);T.eq(#f:events('shot','multi'),0)
end)
T.test('reload needs actual reserve transfer and EndReload alone does not count',function()
    local f=fixture();f:call(ITEM..'F_EndReload',f.item);T.eq(#f:events('reload'),0)
    f:reload(30,30);T.eq(#f:events('reload'),0);f:reload(30,25);T.eq(#f:events('reload'),1)
end)
T.test('Pistol EndReload before commit still counts the real transfer',function()
    local f=fixture('itemPistol');f:call(ITEM..'F_EndReload',f.item);f:reload(30,24);T.eq(#f:events('reload'),1)
end)
T.test('reload still sees reserve transfer after low-ammo UI reads the new value twice',function()
    local f=fixture();f:get(1,30);f:get(5,30)
    f:get(5,26);f:get(5,26)
    f:call(ITEM..'F_ReloadAmmos',f.item,0,false)
    T.eq(#f:events('reload'),1);T.eq(f:events('reload')[1].transferredReserve,4)
end)
T.test('same-frame later reload cannot reuse an earlier reserve transition',function()
    local f=fixture();f:get(5,30);f:get(5,26);f:call(ITEM..'F_ReloadAmmos',f.item,0,false)
    f:get(5,26);f:get(5,26);f:call(ITEM..'F_ReloadAmmos',f.item,0,false)
    T.eq(#f:events('reload'),1)
    f:get(5,26);f:get(5,23);f:call(ITEM..'F_ReloadAmmos',f.item,0,false)
    T.eq(#f:events('reload'),2);T.eq(f:events('reload')[2].transferredReserve,3)
end)
T.test('shotgun inserts count once per explicit reload session',function()
    local f=fixture('itemShotgun');f:call(SHOTGUN..'F_Child_Reload',f.item)
    f:reload(30,29);f:reload(29,28);f:reload(28,27);T.eq(#f:events('reload'),1)
    f:call(ITEM..'F_EndReload',f.item);f:call(SHOTGUN..'F_Child_Reload',f.item);f:reload(27,26);T.eq(#f:events('reload'),2)
end)
T.test('unobserved shotgun reload start remains unavailable',function()
    local f=fixture('itemShotgun');f:reload(30,29);T.eq(#f:events('reload'),0)
end)
T.test('install is idempotent and a new mission discards pending activations',function()
    local f=fixture();T.eq(Attack.install(f.a),f.state);f:trace({});f.a.missionKey='mission-B';f:finish();T.eq(#f.a.events,0)
end)
T.test('adapter events retain Core separate accuracy modes and ordinary metrics',function()
    local f=fixture();local hit={actor=enemy()};f:trace({hit});f:impact(hit);f:finish();f:trace({});f:finish();f:consume(5,4);f:reload(30,25)
    local Stats=require('Stats');local s=Stats.new('mission-A')
    T.eq(s:apply({id='join',sessionId='mission-A',time=0,kind='player_join',sourcePlayerId='local',name='local'}),true)
    for i,e in ipairs(f.a.events) do e.id='event-'..i;e.sessionId='mission-A';e.time=1;local ok,err=s:apply(e);T.eq(ok,true,err) end
    local p=s:snapshot(2).players['local'];T.eq(p.metrics.shots,2);T.eq(p.metrics.hits,1);T.eq(p.metrics.ammo,1);T.eq(p.metrics.reloads,1)
end)
T.finish()
