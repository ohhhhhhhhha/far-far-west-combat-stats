-- Exact identities from 0.3.0.7 DT_PlayerItems and item CDO itemCategory exports.
-- Unknown/new items require observed class metadata; never classify by a name prefix.
local C={}
local known={
    ['itemmelee']='melee',
    ['itembanjo']='secondary',
    ['itemboomerang']='secondary',
    ['itembow']='secondary',
    ['itemdualrevolver']='secondary',
    ['itemjetpack']='secondary',
    ['itemknuckles']='primary',
    ['itemlasso']='primary',
    ['itemlongranger']='primary',
    ['itemminigun']='primary',
    ['itempistol']='secondary',
    ['itemquadcylinder']='primary',
    ['itemsheriffstar']='secondary',
    ['itemshotgun']='primary',
    ['itemacid']='spell',
    ['itemcactus']='spell',
    ['itemelec']='spell',
    ['itemfire']='spell',
    ['itemice']='spell',
    ['itemvoodoo']='spell',
    ['itemwinchester']='primary',
}
local classes={
    ['itemdefaultgun']='/Game/Items/BP_Item_DefaultGun.BP_Item_DefaultGun_C',
    ['itemmelee']='/Game/Items/BP_Item_Melee.BP_Item_Melee_C',
    ['itemaxe']='/Game/Items/BP_Item_Axe.BP_Item_Axe_C',
    ['itemquadcylinder']='/Game/Items/BP_Item_QuadBarrel.BP_Item_QuadBarrel_C',
    ['itemshotgun']='/Game/Items/BP_Item_Shotgun.BP_Item_Shotgun_C',
    ['itemlongranger']='/Game/Items/BP_Item_LongRanger.BP_Item_LongRanger_C',
    ['itemminigun']='/Game/Items/BP_Item_Minigun.BP_Item_Minigun_C',
    ['itemwinchester']='/Game/Items/BP_Item_Winchester.BP_Item_Winchester_C',
    ['itemknuckles']='/Game/Items/BP_Item_Knuckles.BP_Item_Knuckles_C',
    ['itemlasso']='/Game/Items/BP_Item_Lasso.BP_Item_Lasso_C',
    ['itembanjo']='/Game/Items/BP_Item_Banjo.BP_Item_Banjo_C',
    ['itempistol']='/Game/Items/BP_Item_Pistol.BP_Item_Pistol_C',
    ['itembow']='/Game/Items/BP_Item_Bow.BP_Item_Bow_C',
    ['itemdualrevolver']='/Game/Items/BP_Item_DualRevolver.BP_Item_DualRevolver_C',
    ['itemboomerang']='/Game/Items/BP_Item_Boomerang.BP_Item_Boomerang_C',
    ['itemsheriffstar']='/Game/Items/BP_Item_SheriffStar.BP_Item_SheriffStar_C',
    ['itemjetpack']='/Game/Items/BP_Item_Jetpack.BP_Item_Jetpack_C',
    ['itemutilityammo']='/Game/Items/Grenades/BP_Item_Grenade_Ammos.BP_Item_Grenade_Ammos_C',
    ['itemutilityhealbottle']='/Game/Items/Grenades/BP_Item_Grenade_Heal.BP_Item_Grenade_Heal_C',
    ['itemutilityimpulse']='/Game/Items/Grenades/BP_Item_Grenade_Impulse.BP_Item_Grenade_Impulse_C',
    ['itemutilitybottlecrate']='/Game/Items/Grenades/BP_Item_Grenade_BottleCrate.BP_Item_Grenade_BottleCrate_C',
    ['itemhero']='/Game/Items/BP_Item_Hero.BP_Item_Hero_C',
    ['itemacid']='/Game/Items/BP_Item_SpellClass_Acid.BP_Item_SpellClass_Acid_C',
    ['itemelec']='/Game/Items/BP_Item_SpellClass_Elec.BP_Item_SpellClass_Elec_C',
    ['itemfire']='/Game/Items/BP_Item_SpellClass_Fire.BP_Item_SpellClass_Fire_C',
    ['itemvoodoo']='/Game/Items/BP_Item_SpellClass_Voodoo.BP_Item_SpellClass_Voodoo_C',
    ['itemcactus']='/Game/Items/BP_Item_SpellClass_Cactus.BP_Item_SpellClass_Cactus_C',
    ['itemice']='/Game/Items/BP_Item_SpellClass_Ice.BP_Item_SpellClass_Ice_C',
    ['itemspellacidbubble']='/Game/Spells/BP_Item_SpellCast_Acid_Bubble.BP_Item_SpellCast_Acid_Bubble_C',
    ['itemspellacidcontagion']='/Game/Spells/BP_Item_SpellCast_Acid_Contagion.BP_Item_SpellCast_Acid_Contagion_C',
    ['itemspellacidgeyser']='/Game/Spells/BP_Item_SpellCast_Acid_Geyser.BP_Item_SpellCast_Acid_Geyser_C',
    ['itemspellacidrain']='/Game/Spells/BP_Item_SpellCast_Acid_Rain.BP_Item_SpellCast_Acid_Rain_C',
    ['itemspellacidthrower']='/Game/Spells/BP_Item_SpellCast_Acid_Thrower.BP_Item_SpellCast_Acid_Thrower_C',
    ['itemspellcactusbetty']='/Game/Spells/BP_Item_SpellCast_Cactus_Betty.BP_Item_SpellCast_Cactus_Betty_C',
    ['itemspellcactusdecoy']='/Game/Spells/BP_Item_SpellCast_Cactus_Decoy.BP_Item_SpellCast_Cactus_Decoy_C',
    ['itemspellcactusturret']='/Game/Spells/BP_Item_SpellCast_Cactus_Turret.BP_Item_SpellCast_Cactus_Turret_C',
    ['itemspellcactuswall']='/Game/Spells/BP_Item_SpellCast_Cactus_Wall.BP_Item_SpellCast_Cactus_Wall_C',
    ['itemspellcactusulti']='/Game/Spells/BP_Item_SpellCast_Cactus_Ulti.BP_Item_SpellCast_Cactus_Ulti_C',
    ['itemspellelecportal']='/Game/Spells/BP_Item_SpellCast_Elec_Portal.BP_Item_SpellCast_Elec_Portal_C',
    ['itemspellelecstrike']='/Game/Spells/BP_Item_SpellCast_Elec_Strike.BP_Item_SpellCast_Elec_Strike_C',
    ['itemspellelecsuperjump']='/Game/Spells/BP_Item_SpellCast_Elec_SuperJump.BP_Item_SpellCast_Elec_SuperJump_C',
    ['itemspellelecswap']='/Game/Spells/BP_Item_SpellCast_Elec_Swap.BP_Item_SpellCast_Elec_Swap_C',
    ['itemspellelecthunderstrike']='/Game/Spells/BP_Item_SpellCast_Elec_ThunderStrike.BP_Item_SpellCast_Elec_ThunderStrike_C',
    ['itemspellfireball']='/Game/Spells/BP_Item_SpellCast_Fire_Ball.BP_Item_SpellCast_Fire_Ball_C',
    ['itemspellfirebeam']='/Game/Spells/BP_Item_SpellCast_Fire_Beam.BP_Item_SpellCast_Fire_Beam_C',
    ['itemspellfirefingergun']='/Game/Spells/BP_Item_SpellCast_Fire_Fingergun.BP_Item_SpellCast_Fire_Fingergun_C',
    ['itemspellfiresurcharge']='/Game/Spells/BP_Item_SpellCast_Fire_Surcharge.BP_Item_SpellCast_Fire_Surcharge_C',
    ['itemspellfirewisp']='/Game/Spells/BP_Item_SpellCast_Fire_Wisp.BP_Item_SpellCast_Fire_Wisp_C',
    ['itemspellvoodoocorruption']='/Game/Spells/BP_Item_SpellCast_Voodoo_Corruption.BP_Item_SpellCast_Voodoo_Corruption_C',
    ['itemspellvoodoodoll']='/Game/Spells/BP_Item_SpellCast_Voodoo_Doll.BP_Item_SpellCast_Voodoo_Doll_C',
    ['itemspellvoodoodrain']='/Game/Spells/BP_Item_SpellCast_Voodoo_Drain.BP_Item_SpellCast_Voodoo_Drain_C',
    ['itemspellvoodooheal']='/Game/Spells/BP_Item_SpellCast_Voodoo_Heal.BP_Item_SpellCast_Voodoo_Heal_C',
    ['itemspellvoodoohealarea']='/Game/Spells/BP_Item_SpellCast_Voodoo_HealArea.BP_Item_SpellCast_Voodoo_HealArea_C',
    ['itemspellicecube']='/Game/Spells/BP_Item_SpellCast_Ice_Cube.BP_Item_SpellCast_Ice_Cube_C',
    ['itemspellicelance']='/Game/Spells/BP_Item_SpellCast_Ice_Lance.BP_Item_SpellCast_Ice_Lance_C',
    ['itemspellicebreeze']='/Game/Spells/BP_Item_SpellCast_Ice_Breeze.BP_Item_SpellCast_Ice_Breeze_C',
    ['itemspelliceglaze']='/Game/Spells/BP_Item_SpellCast_Ice_Glaze.BP_Item_SpellCast_Ice_Glaze_C',
    ['itemspelliceblizzard']='/Game/Spells/BP_Item_SpellCast_Ice_Blizzard.BP_Item_SpellCast_Ice_Blizzard_C',
}
function C.category(item)
    if type(item)~='string' then return nil end
    local key=item:lower()
    if known[key] then return known[key] end
    local path=classes[key]
    if not path or type(StaticFindObject)~='function' then return nil end
    local ok,value=pcall(function()
        local class=StaticFindObject(path)
        if class and class:IsValid() then return class:GetCDO().itemCategory end
    end)
    local category=ok and ({[1]='primary',[2]='secondary',[4]='spell'})[value] or nil
    if category then known[key]=category end
    return category
end
return C
