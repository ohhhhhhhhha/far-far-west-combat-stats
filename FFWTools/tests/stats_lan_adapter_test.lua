package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local H=require('stats_engine_harness')
local room='0123456789abcdef0123456789abcdef'
T.test('LAN PlayerId works without Steam ID and rejects duplicate replicated identities',function()
 local h=H.new{localRawId='LOCAL-LAN',nativeId='NO-STEAM'};h.members[1].PlayerId=27
 local m=h:load();m.adapter.options.identity=function()return {mode='lan',room=room,hostId='lan:'..room..':27'}end
 local roster,localId,host,diagnostics;m.adapter.options.onRoster=function(r,l,h,d)roster,localId,host,diagnostics=r,l,h,d end
 m.adapter:refreshRoster();T.eq(localId,'lan:'..room..':27');T.eq(host,localId);T.eq(roster[localId]~=nil,true)
 h.members[2]=h:player('ANOTHER-LAN',false);h.members[2].PlayerId=27;m.adapter:refreshRoster();T.eq(diagnostics.duplicateIds,1);T.eq(next(roster),nil)
 h:restore()
end)
T.test('LAN trusted pairing host is used only if present and never overrides conflicting host flag',function()
 local h=H.new{host=false,localRawId='GUEST-LAN'};h.members[1].PlayerId=43
 h.members[2]=h:player('HOST-LAN',false);h.members[2].PlayerId=7
 local m=h:load();local wanted='lan:'..room..':7';m.adapter.options.identity=function()return {mode='lan',room=room,hostId=wanted}end
 local found,diag;m.adapter.options.onRoster=function(_,_,host,d)found,diag=host,d end;m.adapter:refreshRoster();T.eq(found,wanted)
 h.members[1].isHost=true;m.adapter:refreshRoster();T.eq(found,nil);T.eq(diag.hostConflict,true)
 h:restore()
end)
T.test('title detection without a PlayerController uses one verified GameInstance world',function()
 local h=H.new{};local m=h:load();h.candidates={};local old=FindAllOf
 local instance=h.e.object('GameInstance');local world=h.e.object('World');function world:GetFullName()return 'World /Game/Maps/L_Map_TitleScreen.L_Map_TitleScreen'end;instance.world=world
 FindAllOf=function(class)if class=='BP_CanyonGameInstance_C'then return {instance}end;return old(class)end
 T.eq(type(m.adapter.roomState),'function','title observation method exists');T.eq(m.adapter:roomState(),'title');FindAllOf=old;h:restore()
end)
T.test('inactive current-world PlayerState is a confirmed departure signal',function()
 local h=H.new{localRawId='LAN'};h.members[1].PlayerId=7;h.members[2]=h:player('PEER',false);h.members[2].PlayerId=43;h.members[2].bIsInactive=true
 local m=h:load();m.adapter.options.identity=function()return {mode='lan',room=room,hostId='lan:'..room..':7'}end
 local roster,diag;m.adapter.options.onRoster=function(r,_,_,d)roster,diag=r,d end;m.adapter:refreshRoster()
 T.eq(roster['lan:'..room..':43'],nil);T.eq((diag.departedIds or {})['lan:'..room..':43'],true);h:restore()
end)
T.finish()
