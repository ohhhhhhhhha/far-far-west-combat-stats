package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local loaded,C=pcall(require,'Connection');assert(loaded,'connection controller must exist')
local room='0123456789abcdef0123456789abcdef';local host='lan:'..room..':7';local guest='lan:'..room..':43';local code='FFWLAN1|'..room..'|7|43|'..string.rep('a',64)
local function fixture(isHost)
 local f={rawId=isHost and '7' or '43',isHost=isHost,roster={},active=false,writes={},calls={update=0,stop=0,revoke=0}}
 local lan={apiVersion=1,channel=4605527,maxPayload=4096}
 function lan.configure(role,id,address,port,token)f.calls.configure={role,id,address,port,token};return true end
 function lan.localPlayerId()return isHost and host or guest end
 function lan.pair(id)f.calls.peer=id;return code end
 function lan.update()f.calls.update=f.calls.update+1 end
 function lan.stop()f.calls.stop=f.calls.stop+1 end
 function lan.status()return 'connected:1;port=46055;paired=1'end
 function lan.revoke(id)f.calls.revoke=f.calls.revoke+1;f.calls.revoked=id;return true end
 function lan.send()return true end;function lan.poll()end;function lan.close()return true end
 local bridge={apiVersion=1,lan=lan,localSteamId=function()return '76561198000000001'end}
 f.c=C.new{getBridge=function()return bridge end,getContext=function()return f end,isActive=function()return f.active end,path='fake.json',read=function()return nil end,write=function(_,raw)f.writes[#f.writes+1]=raw;return true end}
 return f
end
T.test('host binds explicit roster member and preserves pairing over a transient map roster gap',function()
 local f=fixture(true);assert(f.c:setMode('lan'));assert(f.c:start{port='46055'});T.eq(f.calls.configure[1],'host');T.eq(f.calls.configure[3],'0.0.0.0')
 f.roster={[host]={name='Same name'},[guest]={name='Same name'}};f.c:onRoster(f.roster,{missingIds=0,unmappedIds=0,duplicateIds=0})
 T.eq(f.c:pair('lan:'..room..':99'),false);assert(f.c:pair(guest));T.eq(f.calls.peer,guest);T.eq(f.c.pairingCode,code)
 f.c:onWorldChanged();f.c:onRoster({},{});T.eq(f.calls.revoke,0)
 f.c:onRoster({[host]={name='Host'}},{missingIds=0,unmappedIds=0,duplicateIds=0});T.eq(f.calls.revoke,0,'host-only travel roster is incomplete, not proof of departure')
 T.eq(f.c:model().rows[1].pending,true,'unsettled peer remains visible for explicit revoke')
 f.c:onRoster(f.roster,{missingIds=0,unmappedIds=0,duplicateIds=0});T.eq(f.calls.revoke,0)
 f.c:onRoster({[host]={name='Host'}},{missingIds=0,unmappedIds=0,duplicateIds=0});T.eq(f.calls.revoked,guest)
end)
T.test('guest rejects another PlayerId code and never saves pairing secrets',function()
 local f=fixture(false);assert(f.c:setMode('lan'));T.eq(f.c:start{address='127.0.0.1',port='46055',token=code:gsub('|43|','|44|')},false);T.eq(f.calls.configure,nil)
 assert(f.c:start{address='127.0.0.1',port='46055',token=code});T.eq(f.c:identity().hostId,host);T.eq(f.c:identity().room,room)
 for _,raw in ipairs(f.writes)do assert(not raw:find('FFWLAN1',1,true));assert(not raw:find(string.rep('a',64),1,true))end
end)
T.test('lobby pumps native handshake and title stops pairing even with no controller',function()
 local f=fixture(true);f.c:setMode('lan');f.c:start{port='46055'};f.c:update('room');T.eq(f.calls.update,1)
 f.c:update('loading');T.eq(f.c.configured,true);f.c:update('title');T.eq(f.c.configured,false);T.eq(f.calls.stop,1);T.eq(f.c.pairingCode,nil)
end)
T.test('active mission cannot change identity mode or restart a room',function()
 local f=fixture(true);f.active=true;T.eq(f.c:setMode('lan'),false);T.eq(f.c.mode,'steam');T.eq(f.c:start{port='46055'},false);T.eq(f.calls.configure,nil)
end)
T.test('confirmed inactive member and explicit revoke still clear pairing during travel',function()
 local f=fixture(true);f.c:setMode('lan');f.c:start{port='46055'};local roster={[host]={name='Host'},[guest]={name='Guest'}}
 f.c:onRoster(roster,{});f.c:pair(guest);f.c:onWorldChanged()
 f.c:onRoster({[host]={name='Host'}},{departedIds={[guest]=true}});T.eq(f.calls.revoked,guest)
 f.c:onRoster(roster,{});f.c:pair(guest);f.c:onWorldChanged();T.eq(type(f.c.revoke),'function');assert(f.c:revoke(guest));T.eq(f.c.issued[guest],nil)
end)
T.finish()
