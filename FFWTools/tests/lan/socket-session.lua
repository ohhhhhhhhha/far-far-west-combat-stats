package.path='/scripts/?.lua;'..package.path
local rename=os.rename
os.rename=function(a,b)local f=io.open(b,'rb');if f then f:close();return nil,'destination exists',17 end;return rename(a,b)end
Json=require('Json');Session=require('Session');Store=require('Store')
local function success(s)if s:sub(1,1)=='!' then return nil,s:sub(2) end;return true end
transport={apiVersion=1,channel=4605527,maxPayload=4096,localPlayerId=function()local id=nativeId();if id:sub(1,1)=='!' then return nil,id:sub(2) end;return id end,
 send=function(peer,channel,bytes)return success(nativeSend(peer,channel,bytes))end,
 close=function(peer)return success(nativeClose(peer))end,
 poll=function(channel)local raw=nativePoll(channel);if raw==''then return end;if raw:sub(1,1)=='!'then return nil,nil,raw:sub(2)end;local i=assert(raw:find('\n',1,true));return raw:sub(1,i-1),raw:sub(i+1)end}
logs={}
function createSession(epoch)
 session=Session.new{path='/profile/last-mission.json',epoch=epoch,transport=transport,nextEpoch=function()epoch=epoch+1;return epoch end,report=function(s)logs[#logs+1]=s end,localTracking={shot=true,hit=true,ammo=true,reload=true}}
end
function setRoster(json,id,host)session:setRoster(Json.decode(json),id,host,0)end
function snapshot()session:refresh();return Json.encode(session:snapshot())end
function tick(wall,mission)session:tick(wall,mission)end
function saved()local f=assert(io.open('/profile/last-mission.json','rb'));local s=f:read('a');f:close();return s end
