package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local Sync,Stats=require('Sync'),require('Stats')
local room='0123456789abcdef0123456789abcdef'
local host='lan:'..room..':7'
local transport={maxPayload=4096,localPlayerId=function()return host end,send=function()return true end,poll=function()end,close=function()return true end}
local ok,sync=pcall(Sync.new,{transport=transport,localId=host,hostSteamId=host,epoch=1,sessionId='lan-fixture',generation=1,stats=Stats.new('lan-fixture'),roster={[host]={playerId=host}}})
assert(ok,'LAN transport identity must be accepted without a Steam method: '..tostring(sync))
assert(sync.localId==host)
print('generic LAN identity: passed')
