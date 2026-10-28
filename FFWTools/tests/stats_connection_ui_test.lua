package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local H=require('stats_engine_harness');local Panel=require('Panel');local UMG=require('PanelUmg')
T.test('F8 connection controls read actual text fields and are usable with no mission snapshot',function()
 local called={};local connection={model=function()return {mode='lan',isHost=false,port='46055',address='',revision=1,rows={},page=1,pageCount=1,message='fixture'}end,start=function(_,v)called=v;return true end}
 local p=Panel.new{connection=connection,readInput=function(id)return ({['network-address']='127.0.0.1',['network-port']='46055',['network-token']='assigned-code'})[id]end}
 p:toggle();assert(p:mouse('toggleConnection'));assert(p:model().connection);assert(p:mouse('networkStart'));T.eq(called.address,'127.0.0.1');T.eq(called.token,'assigned-code')
 local scene=UMG.layout(p:model(),{width=1024,height=720});local ids={}
 for _,c in ipairs(scene.commands)do if c.id then ids[c.id]=c end;if c.kind=='input'or c.kind=='button'then assert(c.x>=0 and c.y>=0 and c.x+c.width<=scene.width and c.y+c.height<=scene.height)end end
 T.eq(ids['network-address'].kind,'input');T.eq(ids['network-token'].kind,'input');T.eq(ids.networkStart.action,'networkStart')
end)
T.test('production entry connects LAN in lobby without Steam identity and preserves F10 for Nexus',function()
 local h=H.new{localRawId='LAN',nativeId=''};h.members[1].PlayerId=27
 function h.e.controller.world:GetFullName()return 'World /Game/Levels/L_Lobby.L_Lobby'end
 local room='0123456789abcdef0123456789abcdef';local active=false;local updates=0
 h.transport.lan={apiVersion=1,channel=4605527,maxPayload=4096,configure=function()active=true;return true end,localPlayerId=function()if active then return 'lan:'..room..':27'end end,send=function()return true end,poll=function()end,close=function()return true end,stop=function()active=false end,status=function()return active and 'listening:0' or 'off'end,update=function()updates=updates+1 end}
 local m=h:load();T.eq(type(m.connection),'table');assert(m.connection:setMode('lan'));assert(m.connection:start{port='46055'});h:tick(2)
 T.eq(m.identityReady,true);T.eq(m.session.localId,'lan:'..room..':27');assert(updates>0);T.eq(h.keys.F10,nil)
 h:key('F8');assert(m.panel:mouse('toggleConnection'));T.eq(m.panel:model().connection.configured,true);h:restore()
end)
T.test('gameplay without a verified transport remains configuration-locked',function()
 local h=H.new{localRawId='LAN',nativeReady=false};h.members[1].PlayerId=27;local m=h:load()
 T.eq(m.session.phase,'lobby','statistics has not started')
 local world=h.e.controller.world;function world:GetFullName()return 'World /Game/Levels/L_Desert.L_Desert'end
 local manager=h.e.object('GameMaster');manager.world=world;h.managers={manager};h:tick(2)
 T.eq(m.connection:setMode('lan'),false);T.eq(m.connection:start{port='46055'},false);T.eq(m.connection:stop(),false)
 h:restore()
end)
T.finish()
