-- Mission lifecycle, cumulative synchronization, and the one retained save.
-- The adapter alone identifies starts/ends; lobby/startup never creates a mission.
local Stats,Store,Sync=require('Stats'),require('Store'),require('Sync')
local S={};S.__index=S
local function copy(value)
    if type(value)~='table' then return value end
    local out={};for key,item in pairs(value) do out[key]=copy(item) end;return out
end
local function candidateMatches(candidate,sessionId)
    if not candidate then return true end
    if candidate.sessionId then return candidate.sessionId==sessionId end
    return candidate.afterSessionId~=sessionId
end
function S.new(options)
    local latest,_,checkpoint=Store.read(options.path)
    local self=setmetatable({options=options,latest=latest,retainedSnapshot=latest,restoredCheckpoint=checkpoint,epoch=options.epoch,
        generation=0,sequence=0,phase='lobby',time=0,wall=0,roster={},known={},coverage={},pendingLocal={},
        nextSave=0,nextView=0,clockBase=0,previous=latest~=nil,errors={}},S)
    if options.onSnapshot then options.onSnapshot(latest,{previous=self.previous}) end
    return self
end
function S:report(message)
    if not self.errors[message] then
        self.errors[message]=true
        if self.options.report then self.options.report(message) end
    end
end
function S:id()
    self.sequence=self.sequence+1
    return tostring(self.localId)..':'..self.epoch..':'..self.sequence
end
function S:apply(event,time)
    event.id=event.id or self:id();event.sessionId=self.sessionId;event.time=time or self.time
    local ok,err=self.run:apply(event)
    if not ok and err~='duplicate event' then self:report('event rejected: '..tostring(err)) end
    return ok,err
end
function S:setCoverage(id,metric,status,time,from)
    local key=id..'/'..metric
    if self.coverage[key]==status then return end
    if self:apply({kind='coverage',sourcePlayerId=id,metric=metric,status=status,from=from},time) then self.coverage[key]=status end
end
function S:joinCurrent(time)
    if not self.run or self.run._state.status~='active' then return end
    local ids={};for id in pairs(self.roster) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do
        local member=self.roster[id]
        if not self.known[id] then
            self.known[id]=true
            self:apply({kind='player_join',sourcePlayerId=member.playerId,name=member.name},time)
            for _,metric in ipairs(self.options.verifiedHostMetrics or {}) do
                self:setCoverage(member.playerId,metric,self.fresh and 'complete' or 'partial',time,self.fresh and time or nil)
            end
        end
    end
    for id in pairs(self.known) do
        if not self.roster[id] and self.phase=='active' then
            self:apply({kind='player_leave',sourcePlayerId=id},time);self.known[id]=nil
            for key in pairs(self.coverage) do if key:sub(1,#id+1)==id..'/' then self.coverage[key]=nil end end
        end
    end
end
function S:setRoster(roster,localId,hostId,time)
    self.roster,self.localId,self.hostId=roster,localId,hostId
    if not localId or not hostId or not roster[localId] or not roster[hostId] then return end
    if self.sync and self.sync.hostSteamId==hostId then self.sync:setRoster(roster) end
    if self.run and self.isHost then self:joinCurrent(self.endTime or math.max(self.time,self.clockBase+(time or 0))) end
end
function S:syncOptions()
    return {transport=self.options.transport,localId=self.localId,hostSteamId=self.hostId,epoch=self.epoch,
        roster=self.roster,localTracking=self.options.localTracking or {},onStatus=function(status,time)
            if self.run and self.isHost and self.run._state.status=='active' then
                for _,peer in pairs(status.peers) do
                    for metric,quality in pairs(peer.eventCoverage) do self:setCoverage(peer.playerId,metric,quality,time) end
                end
            end
        end}
end
function S:begin(worldKey,fresh,isHost,observedLate)
    if self.worldKey==worldKey then return false end
    assert(self.localId and self.hostId,'game roster must be known before starting statistics')
    local old=self.sync and self:checkpoint() or self.restoredCheckpoint
    if old and (old.localId~=self.localId or old.hostSteamId~=self.hostId) then old=nil end
    local saved=old and old.lifecycle
    local prior=self.latest
    if old and old.currentSnapshot then self.retainedSnapshot=old.currentSnapshot end
    -- A local disconnect can finish this client's stream while the authority's
    -- mission is still active. Only an explicit start or authoritative ended
    -- snapshot establishes that the old mission must no longer be adopted.
    local boundary=saved and saved.sessionId or (prior and prior.sessionId)
    local authorityAdvanced=old and boundary and old.sessionId and old.sessionId~=boundary
    local waitingNew=(fresh==true and not authorityAdvanced) or (old and old.waitingNew)
        or (old and prior and prior.sessionId==old.sessionId and prior.status=='ended')
    if not isHost and old and not waitingNew and old.finishing then
        if self.epoch<=old.localEpoch then
            local nextEpoch,err
            if self.options.nextEpoch then nextEpoch,err=self.options.nextEpoch() end
            if not nextEpoch or nextEpoch<=old.localEpoch then
                return false,err or 'persist a newer local epoch before reopening the finished event stream'
            end
            self.epoch=nextEpoch
        end
        old.finishing,old.finishAcknowledged,old.finalSnapshotSequence=false,false,nil
    end
    local resumeHost=isHost and not fresh and saved and saved.worldKey==worldKey
        and (saved.phase=='active' or saved.phase=='finishing') and prior and prior.status=='active'
    local pending,candidate={},nil
    if not isHost and not fresh and saved then
        pending=copy(saved.pendingLocal or {});candidate=copy(saved.pendingCandidate)
    end
    if not candidate then
        candidate=waitingNew and {afterSessionId=boundary or (old and old.sessionId)} or {sessionId=old and old.sessionId}
    end
    self.worldKey,self.phase,self.fresh,self.isHost=worldKey,'active',fresh==true and not observedLate,isHost==true
    self.time,self.endTime,self.previous,self.pendingLocal,self.known,self.coverage=0,nil,false,pending,{},{}
    self.pendingCandidate=candidate
    self.latest=nil;self.clockBase=0;self.savedEnded=false;self.generation=self.generation+1
    local o=self:syncOptions()
    if self.isHost then
        if resumeHost then
            self.run=assert(Stats.restore(prior));self.sessionId=prior.sessionId
            self.generation=old.generation;self.clockBase=prior.time;self.time=prior.time
            self.sequence=saved.sequence or 0;self.phase=saved.phase
            self.endTime=self.phase=='finishing' and self.time or nil
            for id,p in pairs(self.run._state.players) do
                if p.connected then self.known[id]=true end
                for metric,c in pairs(p.coverage) do
                    if c.status~='unavailable' then self:setCoverage(id,metric,'partial',self.time) end
                end
            end
            o.resume=old
        else
            self.sessionId=self.hostId..':'..self.epoch..':'..self.generation
            self.run=Stats.new(self.sessionId)
        end
        self:joinCurrent(self.time)
        o.sessionId,o.generation,o.stats=self.sessionId,self.generation,self.run
    else
        self.run=nil;self.sessionId=nil
        if old then o.resume=old end
        -- Sync may learn the authority's next mission before this client sees its
        -- local start. Keep the current lifecycle identity until begin() changes it.
        o.onSession=function(id)
            if not self.sessionId and self.pendingCandidate.afterSessionId~=id then self.sessionId=id end
        end
    end
    self.sync=Sync.new(o);self.restoredCheckpoint=nil
    if not self.isHost and old and waitingNew then self.sync:awaitNextSession() end
    self.nextSave,self.nextView=self.wall,self.wall
    if self.options.onSnapshot then self.options.onSnapshot(nil,{previous=false}) end
    return true
end
function S:ingest(event,time,localOnly)
    if self.phase~='active' then return false,'mission is not collecting events' end
    self.time=math.max(self.time,self.clockBase+time)
    if self.isHost then return self:apply(event,self.time) end
    if not localOnly then return false,'guest does not authoritatively count this event' end
    event.id=event.id or self:id()
    if self.sync and self.sync.bound and self.sync.sessionId==self.sessionId then return self.sync:submit(event) end
    self.pendingLocal[#self.pendingLocal+1]=event
    return true
end
function S:finish(time)
    if self.phase~='active' then return false end
    self.time=math.max(self.time,self.clockBase+time);self.endTime=self.time;self.phase='finishing'
    -- Pending local events must be submitted before the final watermark is fixed.
    if self.sync and self.sync.sessionId==self.sessionId and #self.pendingLocal==0 then self.sync:finish() end
    return true
end
function S:refresh()
    local snapshot
    if self.isHost and self.run then snapshot=self.run:snapshot(self.endTime or self.time)
    elseif self.sync and self.sync.bound and not self.sync.waitingNew and self.sync.sessionId==self.sessionId then snapshot=self.sync:snapshot() end
    if not snapshot then return false end
    self.latest,self.retainedSnapshot=snapshot,snapshot
    if self.options.onSnapshot then self.options.onSnapshot(snapshot,{previous=self.previous or self.phase=='ended'}) end
    return true
end
function S:checkpoint()
    if not self.sync then return nil end
    local checkpoint=self.sync:checkpoint()
    checkpoint.lifecycle={worldKey=self.worldKey,sessionId=self.sessionId,phase=self.phase,time=self.time,sequence=self.sequence,
        pendingLocal=copy(self.pendingLocal),pendingCandidate=copy(self.pendingCandidate)}
    return checkpoint
end
function S:publish()
    local refreshed=self:refresh()
    -- While a hello is outstanding, retain the last real authority snapshot in
    -- the same file as the local candidate queue. It stays hidden from this
    -- active lifecycle until a matching authoritative snapshot arrives.
    local snapshot=refreshed and self.latest or (self.sync and self.retainedSnapshot)
    if not snapshot then return false end
    local checkpoint=self:checkpoint()
    local ok,err=Store.write(self.options.path,snapshot,checkpoint)
    if not ok then self:report('save failed: '..tostring(err)) end
    if ok and refreshed and self.phase=='ended' then self.savedEnded=true end
    return ok
end
function S:tick(wallNow,missionTime)
    self.wall=math.max(self.wall,wallNow)
    if not self.sync then return end
    if self.phase=='active' then self.time=math.max(self.time,self.clockBase+missionTime) end
    local now=self.endTime or self.time
    self.sync:tick(self.wall,now)
    if not self.isHost and self.sync.bound and not self.sessionId and self.pendingCandidate.afterSessionId~=self.sync.sessionId then
        self.sessionId=self.sync.sessionId
    end
    if not self.isHost and self.sync.bound and self.sync.sessionId==self.sessionId then
        if #self.pendingLocal>0 then
            local pending=self.pendingLocal;self.pendingLocal={}
            if candidateMatches(self.pendingCandidate,self.sessionId) then
                for _,event in ipairs(pending) do
                    local ok,err=self.sync:submit(event);if not ok then self:report('local event rejected: '..tostring(err)) end
                end
            end
        end
        self.pendingCandidate={sessionId=self.sessionId}
        if self.phase=='finishing' and not self.sync.finishing then self.sync:finish() end
        local received=self.sync:snapshot()
        if received and received.status=='ended' and self.phase~='ended' then
            self.phase='ended';self.endTime=received.time;self.nextSave=self.wall
        end
    end
    if self.isHost and self.phase=='finishing' then
        local finish=self.sync:finishStatus()
        if finish.mayFinalize then
            self:apply({kind='mission_end'},now);self.phase='ended'
            self.sync:forceSnapshot();self.nextSave=self.wall
        end
    end
    if self.wall>=self.nextSave and not self.savedEnded then
        self:publish();self.nextSave=self.wall+(self.options.saveInterval or 5)
        self.nextView=self.wall+(self.options.viewInterval or 1)
    elseif self.wall>=self.nextView then
        if self.phase~='ended' then self:refresh() end
        self.nextView=self.wall+(self.options.viewInterval or 1)
    end
end
function S:snapshot() return self.latest end
return S
