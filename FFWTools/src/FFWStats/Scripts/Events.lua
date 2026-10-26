-- Engine observations -> core events. Amounts come from the inspected settlement
-- functions; caller supplies the identity, session, monotonic clock and event ID.
local SourceCatalog=require('SourceCatalog')
local E={}
local function number(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function id(x) return type(x)=='string' and #x>0 end
function E.sourceCategory(r)
    if r.verifiedDot==true then return 'dot' end
    if r.element==4 then return 'melee' end
    if id(r.itemName) and r.itemName:lower()~='none' then
        local item=r.itemName:lower()
        if id(r.primary) and item==r.primary:lower() then return 'primary' end
        if id(r.secondary) and item==r.secondary:lower() then return 'secondary' end
        for spell,present in pairs(r.spells or {}) do
            if present and id(spell) and spell:lower()==item then return 'spell' end
        end
    end
    return SourceCatalog.category(r.itemName) or 'unknown'
end
function E.enemyDamage(r)
    if r.active~=true or r.authority~=true or not id(r.sourcePlayerId) then return nil end
    if not number(r.amount) or r.amount<0 then return nil end
    return {kind='damage',sourcePlayerId=r.sourcePlayerId,targetId=r.targetId,
        amount=r.amount,sourceCategory=r.category or 'unknown'}
end
function E.incoming(r)
    if not id(r.targetPlayerId) or not number(r.currentPlayerHeal) or not number(r.damages) or not number(r.outputHeal) then return nil end
    if r.damages<0 or r.outputHeal<0 or r.outputHeal>r.damages then return nil end
    -- BP_Player clamps remaining HP to 1 in the tutorial and 0 otherwise.
    local floor=r.isTutorial==true and 1 or 0
    return {kind='incoming',targetPlayerId=r.targetPlayerId,
        hpLoss=math.min(math.max(0,r.currentPlayerHeal-floor),r.outputHeal),
        shieldAbsorbed=r.damages-r.outputHeal,sourceCategory=r.sourceCategory or 'unknown'}
end
function E.heal(r)
    if not id(r.sourcePlayerId) or not id(r.targetPlayerId) then return nil end
    if not number(r.amount) or not number(r.effectiveAmount) or r.amount<0 or r.effectiveAmount<0 then return nil end
    local effective=r.effectiveAmount
    if effective>r.amount then
        if effective-r.amount>math.max(1,r.amount)*1e-9 then return nil end
        effective=r.amount
    end
    return {kind='heal',sourcePlayerId=r.sourcePlayerId,targetPlayerId=r.targetPlayerId,amount=r.amount,effectiveAmount=effective}
end
return E
