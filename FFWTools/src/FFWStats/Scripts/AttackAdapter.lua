-- Read-only post hooks verified against 0.3.0.7. Evidence: research/attack-bindings.md.
-- Deliberately limited to the three weapon call graphs inspected in that evidence.
local A={}
local ITEM='/Game/Items/BP_Item.BP_Item_C:'
local BULLET='/Game/Items/Assets/BP_PlayerBullet.BP_PlayerBullet_C:'
local FL='/Game/Items/FL_Items.FL_Items_C:'
local SHOTGUN='/Game/Items/BP_Item_Shotgun.BP_Item_Shotgun_C:'
local MAG='currentMagazineAmmos_10_76E089514907BA2E4DDB1CA16CEC4B6B'
local TOTAL='currentTotalAmmos_17_DDF8963D42826C9B6D9A9E92E9563632'
local DATA={
    [1]='datasWepA_24_C099A0F04138D662182F8D9C94DCA8C6',
    [2]='datasWepB_25_EE50A5DA4381738DA8C10CB8353016D9',
}
local supported={itemLongRanger=true,itemPistol=true,itemShotgun=true}
local dots={}
for _,n in ipairs({'Fire','Acid','Elec'}) do
    dots['/Game/Gamework/DamageTypes/BP_DamageType_Buff_'..n..'.BP_DamageType_Buff_'..n..'_C']=true
end
local function field(o,k)
    local ok,v=pcall(function() return o[k] end)
    if ok and not tostring(v):match('^TrivialObject:') then return v end
end
local function str(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function() return v:ToString() end);if ok then return s end
end
local function key(o)
    -- A traced enemy can become pending-kill before the nested impact post hook.
    local ok,s=pcall(function() return o:GetFullName() end)
    if ok and type(s)=='string' then return s end
end
local function valid(o)
    local ok,v=pcall(function() return o:IsValid() end);return ok and v==true
end
function A.isDot(damageType)
    local path=type(damageType)=='string' and damageType or key(damageType)
    if not path then return false end
    path=path:gsub('^BlueprintGeneratedClass ','')
    return dots[path]==true
end
function A.install(adapter)
    if adapter._attackAdapter then return adapter._attackAdapter end
    local state={sequence=0,getterSequence=0,activations={},getters={},reserveChanges={},usedGetters={},volleys={},reloads={},
        coverage={weapons={'itemLongRanger','itemPistol','itemShotgun'},status='partial',
            unresolved={'other weapon call graphs','ricochet parent IDs','reload sessions already in progress'}}}
    adapter._attackAdapter=state
    local prefix='activation:'..tostring(state)..':'
    local function nextId(id)
        state.sequence=state.sequence+1;return prefix..id..':'..state.sequence
    end
    local function active()
        if not adapter.active or state.mission~=adapter.missionKey then
            state.activations={};state.getters={};state.reserveChanges={};state.usedGetters={};state.volleys={};state.reloads={}
            state.mission=adapter.missionKey
        end
        return adapter.active==true
    end
    local function localOwner(o)
        if not active() then return end
        local pawn=field(o,'owningPlayer')
        local ok,controlled=pcall(function() return pawn:IsLocallyControlled() end)
        if not ok or controlled~=true then return end
        local id,ps=adapter:playerId(pawn)
        if id and id==adapter.localId then return id,ps or adapter.players[id] end
    end
    local function itemOwner(item)
        local id,ps=localOwner(item);local n=str(field(item,'itemName'));local k=key(item)
        if id and k and supported[n] then return id,ps,n,k end
    end
    local function runtime(item,ps)
        local slot=DATA[field(item,'itemCategory')]
        if slot then return field(field(ps,'playerRuntimeStats'),slot) end
    end
    local function stamp(context) return adapter:gameTime(context) end
    local function takeGetter(item,k)
        local before=state.getters[k]
        if not before or before.sequence==(state.usedGetters[k] or 0) then return end
        state.usedGetters[k]=before.sequence
        local now=stamp(item)
        if now~=nil and now==before.stamp then return before end
    end
    local function emitShot(r)
        adapter:emit({kind='shot',sourcePlayerId=r.playerId,attackId=r.id,accuracyMode=r.mode,
            attackKind=r.kind,itemName=r.item,sourceCategory=adapter:category(r.playerId,r.item,1,false),
            shieldBlocked=r.shieldBlocked},true)
        if r.hit then adapter:emit({kind='hit',sourcePlayerId=r.playerId,attackId=r.id,validTarget=true},true) end
    end
    local function actorFromHit(hit)
        return require('UEHelpers').GetActorFromHitResult(hit)
    end
    adapter:bind(BULLET..'F_TraceBullet',function(bullet)
        local k=key(bullet);if not k then return end
        state.activations[k]=nil
        local id=localOwner(bullet);local item=str(field(bullet,'associatedItemName'))
        if not id or not supported[item] or field(bullet,'isRicocheting')~=false then return end
        local r={id=nextId(id),playerId=id,item=item,mode=item=='itemShotgun' and 'pellet' or 'ordinary',
            kind=item=='itemShotgun' and 'shotgun_pellet' or 'initial_bullet',targets={},
            last=field(bullet,'isLastOrUniqueShot')==true,hit=false}
        if item=='itemShotgun' then
            r.volley=state.volleys[id..':'..item]
            if r.volley then r.volley.pending=r.volley.pending+1 end
        end
        -- Parse the complete trace before using an empty result as an explicit miss.
        local ok=pcall(function()
            local impacts=field(bullet,'impacts')
            impacts:ForEach(function(_,param)
                local actor=actorFromHit(param:get())
                if valid(actor) then
                    local tagged=actor:ActorHasTag(FName('enemy'))
                    local health=field(actor,'health')
                    if tagged==true and type(health)=='number' and health>0 then r.targets[key(actor)]=true end
                end
            end)
        end)
        r.readable=ok
        if r.volley and not ok then r.volley.incomplete=true end
        state.activations[k]=r
    end)
    adapter:bind(FL..'F_ApplyImpactDamages',function(_,base,item,critical,hit,causer,element,last,context)
        if not active() then return end
        local r=state.activations[key(context)]
        if not r or not r.readable or str(item)~=r.item or adapter:playerId(causer)~=r.playerId then return end
        local ok,actor=pcall(actorFromHit,hit)
        if ok and r.targets[key(actor)] then r.hit=true end
    end)
    adapter:bind(BULLET..'F_ApplyDamages',function(bullet,critical,shieldBlocked)
        if not active() then return end
        local k=key(bullet);local r=k and state.activations[k];if not r then return end
        state.activations[k]=nil
        if localOwner(bullet)~=r.playerId then return end
        r.shieldBlocked=shieldBlocked==true
        if r.readable then emitShot(r) end
        local volley=r.volley
        if volley then
            volley.pending=volley.pending-1;volley.hit=volley.hit or r.hit
            if r.last then
                if volley.pending==0 and not volley.incomplete then emitShot(volley) end
                state.volleys[r.playerId..':'..r.item]=nil
            end
        end
    end)
    adapter:bind(ITEM..'F_GetItemDatas',function(item,datas)
        local id,_,__,k=itemOwner(item);if not id then return end
        state.getterSequence=state.getterSequence+1
        local previous=state.getters[k]
        local observed={magazine=field(datas,MAG),reserve=field(datas,TOTAL),
            stamp=stamp(item),sequence=state.getterSequence}
        if previous and previous.stamp==observed.stamp and type(previous.reserve)=='number'
            and type(observed.reserve)=='number' and previous.reserve~=observed.reserve then
            state.reserveChanges[k]={before=previous.reserve,after=observed.reserve,
                stamp=observed.stamp,sequence=observed.sequence,previousSequence=previous.sequence}
        end
        state.getters[k]=observed
    end)
    adapter:bind(ITEM..'F_ConsumeAmmos',function(item,amount,canApplyCamper)
        local id,ps,n,k=itemOwner(item);if not id then return end
        state.reloads[k]=nil
        -- Shotgun consumes once before its variable-length pellet loop. The flag
        -- on the last pellet closes the volley; no hardcoded pellet count is used.
        if n=='itemShotgun' then state.volleys[id..':'..n]={id=nextId(id),playerId=id,item=n,
            mode='multi',kind='shotgun_volley',pending=0,hit=false} end
        local before=takeGetter(item,k)
        local actual
        if canApplyCamper==true and field(item,'lastShotConsumedAmmo')==false then actual=0
        elseif before then
            local after=field(runtime(item,ps),MAG)
            if type(before.magazine)=='number' and type(after)=='number' and before.magazine>=after then
                actual=before.magazine-after
            end
        end
        if actual then adapter:emit({kind='ammo',sourcePlayerId=id,amount=actual,itemName=n},true) end
    end)
    adapter:bind(SHOTGUN..'F_Child_Reload',function(item)
        local id,_,n,k=itemOwner(item)
        if id and n=='itemShotgun' then state.reloads[k]={counted=false} end
    end)
    adapter:bind(ITEM..'F_EndReload',function(item)
        local _,_,__,k=itemOwner(item);if k then state.reloads[k]=nil end
    end)
    adapter:bind(ITEM..'F_ReloadAmmos',function(item,specificAmount,wasteWholeMag)
        local id,ps,n,k=itemOwner(item);if not id then return end
        -- F_UpdateLowAmmoIcon can read the new reserve twice before this post.
        -- Retain that observed transition; do not substitute requested ammo.
        local used=state.usedGetters[k] or 0
        local before=takeGetter(item,k);local after=field(runtime(item,ps),TOTAL)
        if not before or type(before.reserve)~='number' or type(after)~='number' then return end
        local reserve=before.reserve
        if reserve==after then
            local change=state.reserveChanges[k]
            if change and change.stamp==before.stamp and change.previousSequence>used and change.after==after then
                reserve=change.before
            end
        end
        if reserve<=after then return end
        if n=='itemShotgun' then
            local session=state.reloads[k];if not session or session.counted then return end
            session.counted=true
        end
        adapter:emit({kind='reload',sourcePlayerId=id,itemName=n,transferredReserve=reserve-after,
            commitKind=n=='itemShotgun' and 'first_shell_in_session' or 'reserve_transfer'},true)
    end)
    return state
end
return A
