-- LAN configuration and trusted pairing, independent of the mission Session.
-- Persistent preferences never contain a pairing key or a player identifier.
local L,Json,Store=require('Locale'),require('Json'),require('Store')
local C={};local Controller={};Controller.__index=Controller
local function rawId(value)return type(value)=='string' and value:match('^%d+$') and (#value==1 or value:sub(1,1)~='0') and tonumber(value)<=2147483647 end
local function ipv4(value)
 if type(value)~='string' then return false end
 local a,b,c,d=value:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
 if not a then return false end
 for _,n in ipairs({a,b,c,d})do if tonumber(n)>255 or (#n>1 and n:sub(1,1)=='0') then return false end end
 return value~='0.0.0.0'
end
function C.token(value)
 if type(value)~='string' then return nil end
 local room,host,guest,key=value:match('^FFWLAN1|([0-9a-f]+)|(%d+)|(%d+)|([0-9a-f]+)$')
 if not room or #room~=32 or #key~=64 or not rawId(host) or not rawId(guest) or host==guest then return nil end
 return {room=room,hostId='lan:'..room..':'..host,rawGuest=guest}
end
local function read(path)local f=io.open(path,'rb');if not f then return nil end;local raw=f:read('a');f:close();return raw end
function C.new(options)
 options=options or {};local self=setmetatable({options=options,mode='steam',address='',port=46055,revision=1,roster={},issued={},page=1},Controller)
 local raw=options.path and (options.read or read)(options.path)
 if raw then local ok,v=pcall(Json.decode,raw);if ok and type(v)=='table' then
  if v.mode=='lan' then self.mode='lan' end
  if ipv4(v.address) then self.address=v.address end
  if type(v.port)=='number' and v.port>=1 and v.port<=65535 and v.port%1==0 then self.port=v.port end
 end end
 return self
end
function Controller:bridge()local b=self.options.getBridge and self.options.getBridge();return type(b)=='table' and b or nil end
function Controller:transport()local b=self:bridge();if self.mode=='lan' then return b and b.lan end;return b end
function Controller:identity()return {mode=self.mode,room=self.room,hostId=self.hostId}end
function Controller:locked()return self.options.isActive and self.options.isActive()==true end
function Controller:fail(code,detail)self.error=code;self.detail=detail;return false end
function Controller:save(mode,address,port)
 local data={mode=mode,address=address,port=port}
 if self.options.path then local ok,err=(self.options.write or Store.writeText)(self.options.path,Json.encode(data));if not ok then return self:fail('save_failed',err)end end
 self.mode,self.address,self.port=mode,address,port;return true
end
function Controller:changed(identityChanged)
 self.revision=self.revision+1
 if self.options.onChanged then self.options.onChanged(identityChanged==true)end
end
function Controller:setMode(mode)
 if mode~='steam' and mode~='lan' then return false end
 if self.mode==mode then return true end
 if self:locked() then return self:fail('mode_locked')end
 local prior=self.mode;if not self:save(mode,self.address,self.port)then return false end
 if prior=='lan' then self:stop(true)end
 self.error,self.detail=nil,nil;self:changed(true);return true
end
function Controller:start(values)
 if self:locked() then return self:fail('mode_locked')end
 if self.mode~='lan' then return self:fail('choose_lan')end
 local native=self:transport()
 if not native or native.apiVersion~=1 or type(native.configure)~='function' then return self:fail('bridge_pending')end
 local context=self.options.getContext and self.options.getContext()
 if not context or not rawId(context.rawId) then return self:fail('identity_pending')end
 values=values or {};local port=tonumber(values.port or self.port);local address=values.address or self.address
 if not port or port%1~=0 or port<1 or port>65535 then return self:fail('port_invalid')end
 local token=values.token or '';local parsed
 if not context.isHost then
  if not ipv4(address) then return self:fail('address_invalid')end
  parsed=C.token(token);if not parsed or parsed.rawGuest~=context.rawId then return self:fail('code_invalid')end
 end
 if not self:save(self.mode,address,port) then return false end
 local ok,err=native.configure(context.isHost and 'host' or 'guest',context.rawId,context.isHost and '0.0.0.0' or address,port,token)
 if not ok then return self:fail('native_failed',err)end
 local id=native.localPlayerId();local room,raw
 if type(id)=='string' then room,raw=id:match('^lan:([0-9a-f]+):(%d+)$') end
 if not room or #room~=32 or raw~=context.rawId or (parsed and parsed.room~=room) then native.stop();return self:fail('identity_pending')end
 self.configured=true;self.localId=id;self.rawId=context.rawId;self.room=room;self.hostId=context.isHost and id or parsed.hostId
 self.isHost=context.isHost==true;self.issued={};self.peerNames={};self.roster={};self.waitingPeers={};self.transition=false;self.pairingCode=nil;self.error,self.detail=nil,nil;self:changed(true);return true
end
function Controller:stop(force)
 if not force and self:locked() then return self:fail('mode_locked')end
 if self.configured then local bridge=self:bridge();local native=bridge and bridge.lan;if native and native.stop then native.stop()end end
 self.configured=false;self.room,self.hostId,self.localId,self.rawId,self.pairingCode=nil,nil,nil,nil,nil
 self.roster,self.issued,self.waitingPeers={},{},{};self.transition=false;self:changed(true);return true
end
function Controller:onWorldChanged()
 self.transition=true;self.waitingPeers={}
 for id in pairs(self.issued)do self.waitingPeers[id]=true end
end
function Controller:revoke(id)
 if not self.configured or not self.isHost or not self.issued[id] then return false end
 local ok,err=self:transport().revoke(id);if not ok then return self:fail('native_failed',err)end
 self.issued[id]=nil;if self.waitingPeers then self.waitingPeers[id]=nil end
 if self.selectedPeer==id then self.pairingCode=nil end
 self:changed();return true
end
function Controller:onRoster(roster,diagnostics)
 self.roster=roster or {};diagnostics=diagnostics or {}
 if not self.configured or not self.isHost or not self.roster[self.localId] then return end
 if (diagnostics.missingIds or 0)>0 or (diagnostics.unmappedIds or 0)>0 or (diagnostics.duplicateIds or 0)>0 or diagnostics.hostConflict or (diagnostics.hostFlags or 0)>1 then return end
 for id in pairs(diagnostics.departedIds or {})do if self.issued[id] then self:revoke(id)end end
 if self.transition then
  for id in pairs(self.waitingPeers or {})do if self.roster[id] then self.waitingPeers[id]=nil end end
  if next(self.waitingPeers or {}) then return end
  self.transition=false
 end
 for id in pairs(self.issued)do if not self.roster[id] then self:revoke(id)end end
end
function Controller:pair(id)
 if not self.configured or not self.isHost or id==self.localId or not self.roster[id] then return self:fail('not_roster')end
 local context=self.options.getContext and self.options.getContext();if not context or not context.isHost or context.rawId~=self.rawId then return self:fail('identity_pending')end
 local code,err=self:transport().pair(id);if not code then return self:fail('native_failed',err)end
 self.selectedPeer,self.pairingCode=id,code;self.issued[id]=true;self.peerNames=self.peerNames or {};self.peerNames[id]=self.roster[id].name;self.error,self.detail=nil,nil;self:changed();return true
end
function Controller:update(worldState)
 if self.mode~='lan' or not self.configured then return end
 if worldState=='title' then self:stop(true);return end
 local context=self.options.getContext and self.options.getContext()
 if context and context.rawId and (context.rawId~=self.rawId or (context.isHost==true)~=self.isHost) then self:stop(true);self:fail('room_changed');return end
 local native=self:transport();if native and native.update then native.update()end
end
function Controller:nextPage(step)self.page=math.max(1,self.page+(step or 1))end
local messages={
 mode_locked={'请在酒馆且上一局统计保存完成后配置；任务内自动重连。','Configure in the saloon after prior statistics finish saving. Mission reconnects are automatic.'},
 choose_lan={'先选择 LAN/IP 直连。','Select LAN/IP first.'},bridge_pending={'请安装同版本 FFWTeamSync 原生组件并重启。','Install the matching FFWTeamSync native component and restart.'},
 identity_pending={'等待当前角色的有效 PlayerId。','Waiting for the current replicated PlayerId.'},port_invalid={'端口须为 1–65535。','Port must be between 1 and 65535.'},
 address_invalid={'填写游戏房主的 IPv4 地址。','Enter the game host IPv4 address.'},code_invalid={'配对码格式错误，或属于另一名玩家。','Invalid pairing code, or assigned to another player.'},
 save_failed={'连接偏好未能保存。','Connection preferences could not be saved.'},native_failed={'连接组件返回错误：','Connection component error: '},
 not_roster={'只能为当前角色表中的队友生成配对码。','Pair only a teammate in the current roster.'},room_changed={'当前角色或房主已改变，请在酒馆重新配对。','Player or host changed; pair again in the saloon.'},
}
function Controller:model()
 local ctx=self.options.getContext and self.options.getContext() or {};local native=self:transport();local status='off'
 if self.mode=='lan' and native and native.status then status=native.status() or 'off'end
 local count=tonumber(status:match('^[^:]+:(%d+)')) or 0
 local statusText=self.mode=='steam' and L.choose('使用游戏的 Steam 身份与传输。','Using game Steam identities and transport.') or
  status:match('^connected:') and string.format(L.choose('已认证连接：%d','Authenticated connections: %d'),count) or
  status:match('^listening:') and L.choose('房主已监听，等待队友配对。','Host listening; waiting for paired teammates.') or
  status:match('^connecting:') and L.choose('连接中；失败后会自动重试。','Connecting; retries are automatic.') or L.choose('尚未启动 LAN 连接。','LAN connection is stopped.')
 if self.error then local msg=messages[self.error] or messages.native_failed;statusText=L.choose(msg[1],msg[2])..(self.detail and ' '..tostring(self.detail) or '')end
 local members={};for id,p in pairs(self.roster)do if id~=self.localId then members[#members+1]={id=id,name=p.name,rawId=id:match(':(%d+)$'),paired=self.issued[id]==true}end end
 for id in pairs(self.issued)do if not self.roster[id] then members[#members+1]={id=id,name=(self.peerNames or {})[id],rawId=id:match(':(%d+)$'),paired=true,pending=true}end end
 table.sort(members,function(a,b)return a.id<b.id end)
 local pages=math.max(1,math.ceil(#members/4));self.page=math.min(self.page,pages);local rows={}
 for i=(self.page-1)*4+1,math.min(self.page*4,#members)do rows[#rows+1]=members[i]end
 return {mode=self.mode,address=self.address,port=tostring(self.port),configured=self.configured==true,locked=self:locked(),
  isHost=self.configured and self.isHost or ctx.isHost==true,rawId=ctx.rawId,rows=rows,page=self.page,pageCount=pages,
  pairingCode=self.pairingCode or '',revision=self.revision,message=statusText,error=self.error~=nil}
end
return C
