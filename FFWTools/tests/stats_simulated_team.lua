-- Independent clients running production Session/Sync/Protocol/Store. This is
-- a deterministic Steam API boundary simulation, never a native-network test.
local Session,Config,Json=require('Session'),require('Config'),require('Json')
local M={}
local ids={host='76561198000000001',one='76561198000000002',two='76561198000000003'}
function M.new(options)
    options=options or {}
    local b={time=0,nodes={},pending={},roster={},serial=0,dropped=0,duplicated=0,closed=0,accepted=0,files={},world='mission-a',options=options}
    for label,id in pairs(ids) do
        b.roster[id]={playerId=id,name='Fixture '..label,isHost=label=='host'}
        for _,suffix in ipairs({'.json','.epoch'}) do
            local p='FFWTools/tests/team-'..label..suffix
            b.files[#b.files+1]=p
            for _,extra in ipairs({'','.bak','.tmp'}) do os.remove(p..extra) end
        end
    end
    function b:rosterFor(labels)
        local r={};for _,label in ipairs(labels) do r[ids[label]]=self.roster[ids[label]] end;return r
    end
    function b:make(label,members)
        local id=ids[label]
        local node={id=id,label=label,inbox={},allowed={},mission=0,born=self.time,
            offset=label=='host' and 4000 or label=='one' and 90000 or 0,logs={}}
        local transport={apiVersion=1,channel=4605527,maxPayload=4096,localSteamId=function() return id end}
        function transport.send(peer,channel,bytes)
            assert(channel==4605527 and type(bytes)=='string' and #bytes<=4096,'native boundary contract')
            node.allowed[peer]=true;b.serial=b.serial+1
            local packet=Json.decode(bytes)
            if b.options.blackhole==peer and packet.kind=='fragment' then b.dropped=b.dropped+1;return true end
            local wire={from=id,to=peer,bytes=bytes,kind=packet.kind,serial=b.serial,at=b.time+.02+(b.serial%3)*.03}
            if b.options.loss and b.serial%7==0 then b.dropped=b.dropped+1;return true end
            b.pending[#b.pending+1]=wire
            if b.options.duplicates and b.serial%4==0 then
                b.duplicated=b.duplicated+1
                b.pending[#b.pending+1]={from=id,to=peer,bytes=bytes,kind=packet.kind,serial=b.serial,at=wire.at+.1}
            end
            return true
        end
        function transport.poll(channel)
            assert(channel==4605527)
            while #node.inbox>0 do
                local p=table.remove(node.inbox,1)
                if node.allowed[p.from] then b.accepted=b.accepted+1;return p.from,p.bytes end
            end
        end
        function transport.close(peer) node.allowed[peer]=nil;b.closed=b.closed+1;return true end
        local file='FFWTools/tests/team-'..label..'.json'
        local epochPath='FFWTools/tests/team-'..label..'.epoch'
        local epoch=assert(Config.nextEpoch(epochPath,1000+math.floor(b.time)))
        local session=Session.new({path=file,epoch=epoch,transport=transport,
            nextEpoch=function() return Config.nextEpoch(epochPath,1000+math.floor(b.time)) end,
            report=function(message) node.logs[#node.logs+1]=message end,
            localTracking={shot=true,hit=true,ammo=true,reload=true}})
        node.session,node.transport,node.file=session,transport,file
        session:setRoster(members or b.roster,id,ids.host,0)
        b.nodes[label]=node
        return node
    end
    function b:start(label,world,fresh)
        local n=self.nodes[label];n.mission=0
        return n.session:begin(world or self.world,fresh~=false,label=='host')
    end
    function b:pump()
        local rest,ready={},{}
        for _,p in ipairs(self.pending) do if p.at<=self.time then ready[#ready+1]=p else rest[#rest+1]=p end end
        self.pending=rest
        if self.options.reorder then table.sort(ready,function(a,z) return a.serial>z.serial end) end
        for _,p in ipairs(ready) do
            for _,n in pairs(self.nodes) do if n.id==p.to then n.inbox[#n.inbox+1]=p end end
        end
    end
    function b:step(dt)
        self.time=self.time+dt;self:pump()
        for _,label in ipairs({'two','host','one'}) do
            local n=self.nodes[label]
            if n then
                if not n.paused then n.mission=n.mission+dt end
                n.session:tick(self.time-n.born+n.offset,n.mission)
            end
        end
    end
    function b:advance(seconds,dt)
        dt=dt or .25
        local finish=self.time+seconds
        while self.time<finish-.0000001 do self:step(math.min(dt,finish-self.time)) end
    end
    function b:damage(label,amount,target)
        local n=self.nodes.host
        return n.session:ingest({kind='damage',sourcePlayerId=ids[label],targetId=target or 'enemy-'..label,
            amount=amount,sourceCategory='primary'},n.mission,false)
    end
    function b:localEvent(label,event)
        local n=self.nodes[label];event.sourcePlayerId=event.sourcePlayerId or n.id
        return n.session:ingest(event,n.mission,true)
    end
    function b:restore()
        for _,p in ipairs(self.files) do for _,extra in ipairs({'','.bak','.tmp'}) do os.remove(p..extra) end end
    end
    return b
end
M.ids=ids
return M
