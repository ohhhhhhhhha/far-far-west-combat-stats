package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local A=require('GameAdapter');local E=require('Events')
T.test('settlement identity classifies shipped weapons when server loadout is absent',function()
 local a=A.new{};a.players.p={}
 T.eq(a:category('p','itemLongRanger',1,false),'primary')
 T.eq(a:category('p','itemDualRevolver',1,false),'secondary')
 T.eq(a:category('p','itemPistol',8,false),'secondary','elemental bullets are not DoT')
 T.eq(a:category('p','itemPistol',8,true),'dot')
 T.eq(a:category('p','none',4,false),'melee')
 T.eq(a:category('p','itemFutureUnknown',1,false),'unknown')
 T.eq(a:category('p','itemSpellImaginary',8,false),'unknown','name prefixes cannot invent an item category')
end)
T.test('known spell identities use loaded class metadata without loading assets',function()
 local previous=StaticFindObject;local calls=0
 StaticFindObject=function(path)
  calls=calls+1;T.eq(path,'/Game/Spells/BP_Item_SpellCast_Fire_Ball.BP_Item_SpellCast_Fire_Ball_C')
  return {IsValid=function() return true end,GetCDO=function() return {itemCategory=4} end}
 end
 local a=A.new{};T.eq(a:category('p','itemSpellFireball',8,false),'spell');T.eq(calls,1)
 T.eq(a:category('p','itemSpellFireball',8,false),'spell');T.eq(calls,1,'verified category cached')
 T.eq(a:category('p','itemSpellImaginary',8,false),'unknown');T.eq(calls,1)
 StaticFindObject=previous
end)
T.finish()
