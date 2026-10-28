-- Peer identities and mission boundaries come from GameAdapter, never from names
-- or self-reported JSON. This module owns no timer, files, or Unreal hooks.
local Protocol, Json = require("Protocol"), require("Json")
local Sync = {VERSION = 1}
Sync.__index = Sync
local MAX_INTEGER, MAX_SNAPSHOT = 9007199254740991, 64 * 1024 * 1024
local EVENT_BATCH, EVENT_INTERVAL = 128, 0.25
local defaults = {shot = true, hit = true, ammo = true, reload = true}
local delegatable = {shot = true, hit = true, ammo = true, reload = true, incoming = true,
    heal = true, shield_gain = true, down = true, death = true, respawn = true, revive_complete = true}
local metricKinds = {shot = {"shots"}, hit = {"hits"}, ammo = {"ammo"}, reload = {"reloads"},
    incoming = {"incomingDamage", "hpLoss", "shieldAbsorbed", "largestHit"},
    heal = {"healing", "selfHealing", "teamHealing", "healingAttempted", "overhealing"},
    shield_gain = {"shieldGranted", "shieldGained", "shieldOvergain"},
    down = {"downs"}, death = {"deaths"}, respawn = {}, revive_complete = {"revives", "rescued"}}
local function text(v) return type(v) == "string" and v ~= "" end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function integer(v, zero) return finite(v) and v >= (zero and 0 or 1) and v <= MAX_INTEGER and v % 1 == 0 end
local function nonnegative(v) return finite(v) and v >= 0 end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
end
local function kinds(value)
    if value == nil then return copy(defaults) end
    local out = {}
    for k, v in pairs(value) do
        local kind = type(k) == "number" and v or k
        if v and delegatable[kind] then out[kind] = true end
    end
    return out
end
local function sortedKeys(t) local a = {}; for k in pairs(t) do a[#a + 1] = k end; table.sort(a); return a end

function Sync.new(o)
    assert(type(o) == "table" and type(o.transport) == "table", "native transport required")
    local nativeId, nativeError = o.transport.localSteamId()
    assert(text(nativeId), nativeError or "Steam ID unavailable")
    assert(o.localId == nil or o.localId == nativeId, "local ID does not match native Steam identity")
    assert(text(o.hostSteamId) and integer(o.epoch), "trusted host ID and persistent local epoch required")
    local isHost = nativeId == o.hostSteamId
    assert(not isHost or (text(o.sessionId) and integer(o.generation) and o.stats), "host requires confirmed mission, generation, and Stats object")
    local self = setmetatable({transport = o.transport, localId = nativeId, hostSteamId = o.hostSteamId,
        isHost = isHost, epoch = o.epoch, sessionId = o.sessionId, generation = isHost and o.generation or nil,
        authorityEpoch = isHost and o.epoch or nil, bound = isHost, stats = o.stats, peers = {}, roster = {}, transfers = {},
        pending = {}, submitted = {}, attacks = {}, eventSequence = 0, originSequence = 0, lastAck = 0,
        now = 0, missionTime = 0, nextHello = 0, nextSnapshot = 0, lastEventSend = -math.huge,
        tracking = copy(o.localTracking or {}), onSession = o.onSession, onStatus = o.onStatus,
        errors = {}, maxPayload = o.transport.maxPayload or 262144}, Sync)
    assert(self.maxPayload >= 4096, "transport payload limit must be at least 4096 bytes")
    self.chunkBytes = math.min(48 * 1024, math.floor((self.maxPayload - 1024) / 2))
    self:setRoster(o.roster or {})
    assert(self.roster[self.localId] and self.roster[self.hostSteamId], "trusted roster must include self and host")
    if o.localEventKinds then self.roster[self.localId].localEventKinds = kinds(o.localEventKinds) end
    if isHost then self.sender = Protocol.sender(self.sessionId, self.localId, self.epoch) end
    local r = o.resume
    if r then
        assert(r.schemaVersion == 1 and r.localId == self.localId and r.hostSteamId == self.hostSteamId, "incompatible sync checkpoint")
        assert(integer(r.localEpoch) and self.epoch >= r.localEpoch, "stale local boot epoch")
        assert(not isHost or r.sessionId == self.sessionId, "host checkpoint belongs to another mission")
        self.sessionId = self.sessionId or r.sessionId
        if self.sessionId == r.sessionId then
            self.submitted, self.attacks = copy(r.submitted or {}), copy(r.attacks or {})
            self.pending = copy(r.pending or {})
            self.eventSequence, self.lastAck = r.eventSequence or 0, r.lastAck or 0
            self.originSequence = r.originSequence or self.eventSequence
            assert(integer(self.eventSequence, true) and integer(self.originSequence, true) and integer(self.lastAck, true), "invalid event checkpoint")
            if self.epoch > r.localEpoch then
                self.eventSequence, self.lastAck = #self.pending, 0
                for i, event in ipairs(self.pending) do event.sequence = i end
            end
            for id, prior in pairs(r.peers or {}) do
                if not self.peers[id] and text(prior.playerId) then
                    self.peers[id] = {playerId = prior.playerId, localEventKinds = kinds(prior.localEventKinds), tracking = {}, observed = {}}
                end
                if self.peers[id] then
                    self.peers[id].epoch, self.peers[id].eventSequence = prior.epoch, prior.eventSequence or 0
                    self.peers[id].finishWatermark, self.peers[id].everReady = prior.finishWatermark, prior.everReady
                    self.peers[id].snapshotSequence, self.peers[id].rejectedEvents = prior.snapshotSequence, prior.rejectedEvents or 0
                    if isHost and self.epoch > r.localEpoch then
                        self.peers[id].eventSequence, self.peers[id].finishWatermark, self.peers[id].snapshotSequence = 0, nil, nil
                    end
                    self.peers[id].observed = copy(prior.observed or {})
                end
            end
            self.finishing, self.finishStarted = r.finishing, r.finishing and 0 or nil
            self.finishWatermark = r.finishing and self.eventSequence or nil
            self.finishAcknowledged = self.epoch == r.localEpoch and r.finishAcknowledged or false
            self.finalSnapshotSequence = self.epoch == r.localEpoch and r.finalSnapshotSequence or nil
            if isHost then
                if self.epoch == r.localEpoch then self.sender.sequence = r.snapshotSequence or 0 end
            elseif integer(r.authorityEpoch) and integer(r.generation) then
                self.authorityEpoch, self.generation = r.authorityEpoch, r.generation
                self.receiver = Protocol.receiver(self.sessionId, self.hostSteamId, self.authorityEpoch)
                if r.currentSnapshot then
                    local ok, why = self.receiver:accept({protocolVersion = Protocol.VERSION, kind = "snapshot",
                        sessionId = self.sessionId, senderId = self.hostSteamId, epoch = self.authorityEpoch,
                        sequence = r.receiveSequence, snapshot = r.currentSnapshot})
                    assert(ok, why)
                end
                self.waitingNew = r.waitingNew
                self.finalSnapshotReceived = r.currentSnapshot and r.currentSnapshot.status == "ended" or false
            end
        end
    end
    return self
end

function Sync:setRoster(roster)
    local nextRoster = {}
    for steamId, value in pairs(roster) do
        assert(text(steamId), "Steam ID roster keys must be strings")
        local record = type(value) == "string" and {playerId = value} or value
        assert(type(record) == "table" and text(record.playerId), "stable PlayerId required")
        nextRoster[steamId] = {playerId = record.playerId, localEventKinds = kinds(record.localEventKinds)}
        self.peers[steamId] = self.peers[steamId] or {eventSequence = 0, observed = {}, tracking = {}}
        self.peers[steamId].playerId, self.peers[steamId].localEventKinds = record.playerId, nextRoster[steamId].localEventKinds
    end
    for id in pairs(self.roster) do
        if not nextRoster[id] and id ~= self.localId then
            self.transport.close(id)
            self.peers[id].ready = false
            self.transfers[id]=nil
        end
    end
    self.roster = nextRoster
end

function Sync:setLocalTracking(tracking) self.tracking = copy(tracking or {}) end
function Sync:_error(message)
    self.errors[#self.errors + 1] = tostring(message)
    if #self.errors > 16 then table.remove(self.errors, 1) end
end
function Sync:_envelope(kind)
    return {wireVersion = 1, kind = kind, senderId = self.localId, authorityId = self.hostSteamId,
        sessionId = self.sessionId, epoch = self.epoch, authorityEpoch = self.authorityEpoch, generation = self.generation}
end
function Sync:_send(peer, packet)
    local bytes = Json.encode(packet)
    if #bytes > self.maxPayload then self:_error("control packet exceeds native payload limit"); return false end
    local ok, err = self.transport.send(peer, self.transport.channel, bytes)
    if not ok then self:_error(err or "native send failed") end
    return not not ok
end
function Sync:_hello(peer)
    local hello = self:_envelope("hello"); hello.tracking = self.tracking
    return self:_send(peer, hello)
end
function Sync:_connected(peer)
    local p = self.peers[peer]
    return p and p.ready and self.roster[peer] and self.now - (p.lastSeen or -math.huge) <= 15
end
function Sync:_binding(packet)
    return packet.sessionId == self.sessionId and packet.authorityId == self.hostSteamId
        and packet.authorityEpoch == self.authorityEpoch and packet.generation == self.generation
end

function Sync:_receiveHello(sender, packet)
    if not integer(packet.epoch) then return false end
    local peer = self.peers[sender]
    if self.isHost then
        if peer.epoch and packet.epoch < peer.epoch then return false end
        local changed = not peer.ready or peer.epoch ~= packet.epoch
        if peer.epoch ~= packet.epoch then
            peer.epoch, peer.eventSequence, peer.finishWatermark, peer.snapshotSequence = packet.epoch, 0, nil, nil
        end
        peer.ready, peer.everReady, peer.lastSeen, peer.tracking = true, true, self.now, kinds(packet.tracking or {})
        if changed then
            self:_hello(sender)
            if self.transfers[sender] then self.transfers[sender].index,self.transfers[sender].retryAt=1,nil
            else self.nextSnapshot = self.now end
        end
        return true
    end
    if sender ~= self.hostSteamId or not text(packet.sessionId) or not integer(packet.generation)
        or packet.authorityEpoch ~= packet.epoch then return false end
    local oldEpoch, oldGeneration = self.authorityEpoch or 0, self.generation or 0
    if packet.epoch < oldEpoch or (packet.epoch == oldEpoch and packet.generation < oldGeneration) then return false end
    local newer = packet.epoch > oldEpoch or packet.generation > oldGeneration
    if packet.epoch == oldEpoch and packet.generation == oldGeneration and self.sessionId ~= packet.sessionId then return false end
    -- A newer authority instance can still be serving the previous mission.
    -- Explicit local next-mission gating requires a different session as well.
    if self.waitingNew and (not newer or packet.sessionId == self.sessionId) then return false end
    local changedSession = packet.sessionId ~= self.sessionId
    local previous = (changedSession or newer) and self:snapshot() or nil
    local previousSession = self.sessionId
    -- Fragment sequence numbers belong to an authority incarnation, just like
    -- Protocol's barrier. A newer boot must not inherit an older partial frame.
    if newer then self.assembly = nil end
    if changedSession then
        self.pending, self.submitted, self.attacks, self.eventSequence, self.originSequence, self.lastAck = {}, {}, {}, 0, 0, 0
        self.receiver, self.assembly, self.hostPeerCoverage = nil, nil, nil
        self.finishing, self.finishStarted, self.finishWatermark, self.finishAcknowledged, self.finalSnapshotReceived = false, nil, nil, false, false
        for id, prior in pairs(self.peers) do
            if not self.roster[id] then self.peers[id] = nil
            else prior.observed, prior.finishWatermark, prior.snapshotSequence, prior.rejectedEvents = {}, nil, nil, 0 end
        end
    elseif packet.epoch > oldEpoch then
        -- A restored host may have an older ACK watermark than the live guest.
        -- Rebase the delivery stream, retaining each event's original identity.
        self.eventSequence, self.lastAck = #self.pending, 0
        for i, event in ipairs(self.pending) do event.sequence = i end
        self.lastEventSend = -math.huge
        if self.finishing then self.finishWatermark, self.finishAcknowledged, self.lastFinishSend = self.eventSequence, false, -math.huge end
        self.finalSnapshotReceived = false
    end
    self.sessionId, self.authorityEpoch, self.generation = packet.sessionId, packet.epoch, packet.generation
    self.receiver = self.receiver or Protocol.receiver(self.sessionId, self.hostSteamId, self.authorityEpoch)
    self.receiver:reconnect(self.authorityEpoch)
    self.bound, self.waitingNew = true, false
    peer.ready, peer.lastSeen, peer.epoch = true, self.now, packet.epoch
    if changedSession or newer then
        self:_hello(sender)
        if self.onSession then self.onSession(self.sessionId, {oldSessionId = previousSession, oldSnapshot = previous,
            authorityEpoch = self.authorityEpoch, generation = self.generation}) end
    end
    return true
end

local function normalize(self, sender, raw, attackEpoch)
    local record = self.roster[sender]
    if type(raw) ~= "table" or not record or not record.localEventKinds[raw.kind] or not delegatable[raw.kind] then
        return nil, "event kind is not delegated to this player"
    end
    local kind, playerId = raw.kind, record.playerId
    if raw.sourcePlayerId and raw.sourcePlayerId ~= playerId then return nil, "source does not match authenticated player" end
    local event = {kind = kind}
    if kind == "incoming" or kind == "down" or kind == "death" or kind == "respawn" then
        if raw.targetPlayerId and raw.targetPlayerId ~= playerId then return nil, "target does not match authenticated player" end
        event.targetPlayerId = playerId
    else event.sourcePlayerId = playerId end
    if kind == "shot" or kind == "hit" then
        if not text(raw.attackId) or not integer(attackEpoch) then return nil, "stable local attack required" end
        event.attackId = "ffw-attack:" .. sender .. ":" .. attackEpoch .. ":" .. raw.attackId
        if kind == "shot" then
            if raw.accuracyMode ~= "ordinary" and raw.accuracyMode ~= "pellet" and raw.accuracyMode ~= "multi" and raw.accuracyMode ~= "dot" then return nil, "accuracy mode required" end
            event.accuracyMode = raw.accuracyMode
        else
            if type(raw.validTarget) ~= "boolean" then return nil, "verified hit target required" end
            event.validTarget = raw.validTarget
        end
    elseif kind == "ammo" then
        if not nonnegative(raw.amount) then return nil, "spent ammo required" end
        event.amount = raw.amount
    elseif kind == "incoming" then
        if not nonnegative(raw.hpLoss) or not nonnegative(raw.shieldAbsorbed) or not text(raw.sourceCategory) then return nil, "actual incoming components required" end
        event.hpLoss, event.shieldAbsorbed, event.sourceCategory = raw.hpLoss, raw.shieldAbsorbed, raw.sourceCategory
    elseif kind == "heal" or kind == "shield_gain" or kind == "revive_complete" then
        local targetKnown = false
        for _, member in pairs(self.roster) do if member.playerId == raw.targetPlayerId then targetKnown = true end end
        if not targetKnown then return nil, "target is not in trusted roster" end
        event.targetPlayerId = raw.targetPlayerId
        if kind == "revive_complete" then
            if raw.targetPlayerId == playerId then return nil, "teammate revive required" end
        else
            if not nonnegative(raw.amount) or not nonnegative(raw.effectiveAmount) or raw.effectiveAmount > raw.amount then return nil, "attempted and effective amounts required" end
            event.amount, event.effectiveAmount = raw.amount, raw.effectiveAmount
        end
    end
    return event
end

function Sync:submit(raw)
    if self.isHost then return false, "host applies local events directly to its Stats object" end
    if not self.bound or self.waitingNew then return false, "mission session is not bound" end
    if self.finishing then return false, "local event stream is finished" end
    if type(raw) ~= "table" or not text(raw.id) then return false, "stable local event ID required" end
    if self.submitted[raw.id] then return false, "duplicate local event" end
    if not integer(self.eventSequence + 1) or not integer(self.originSequence + 1) then return false, "local event sequence exhausted" end
    local attackEpoch = self.attacks[raw.attackId]
    if raw.kind == "shot" then attackEpoch = attackEpoch or self.epoch end
    if raw.kind == "hit" and not attackEpoch then return false, "buffer hit until its shot has been submitted" end
    local normalized, err = normalize(self, self.localId, raw, attackEpoch)
    if not normalized then return false, err end
    local body = copy(normalized)
    if raw.attackId then body.attackId = raw.attackId end
    if #Json.encode(body) > self.maxPayload - 2048 then return false, "local event exceeds transport limit" end
    self.eventSequence = self.eventSequence + 1
    self.originSequence = self.originSequence + 1
    self.pending[#self.pending + 1] = {sequence = self.eventSequence, originEpoch = self.epoch,
        originSequence = self.originSequence, attackEpoch = attackEpoch, event = body}
    self.submitted[raw.id] = true
    if raw.kind == "shot" then self.attacks[raw.attackId] = attackEpoch end
    return true
end

function Sync:_receiveEvents(sender, packet)
    local peer = self.peers[sender]
    if not self.isHost or not self:_connected(sender) or not self:_binding(packet) or packet.epoch ~= peer.epoch
        or type(packet.events) ~= "table" or #packet.events > EVENT_BATCH then return false end
    local rejected = {}
    for _, entry in ipairs(packet.events) do
        if type(entry) ~= "table" or not integer(entry.sequence) then return false end
        if entry.sequence > peer.eventSequence then
            if peer.finishWatermark and entry.sequence > peer.finishWatermark then self:_error("event exceeds declared finish watermark"); break end
            if entry.sequence ~= peer.eventSequence + 1 then break end
            local event, why
            if integer(entry.originEpoch) and entry.originEpoch <= packet.epoch and integer(entry.originSequence)
                and (entry.attackEpoch == nil or (integer(entry.attackEpoch) and entry.attackEpoch <= packet.epoch)) then
                event, why = normalize(self, sender, entry.event, entry.attackEpoch)
            else why = "invalid event origin" end
            if event then
                event.id = "ffw-sync:" .. sender .. ":" .. entry.originEpoch .. ":" .. entry.originSequence
                event.sessionId, event.time = self.sessionId, self.missionTime
                local accepted; accepted, why = self.stats:apply(event)
                if accepted or why == "duplicate event" then peer.observed[event.kind] = true; why = nil end
            end
            if why then
                rejected[#rejected + 1] = {sequence = entry.sequence, reason = why}
                peer.rejectedEvents = (peer.rejectedEvents or 0) + 1; self:_error(why)
            end
            peer.eventSequence = entry.sequence
        end
    end
    peer.lastSeen = self.now
    self:_ack(sender, rejected)
    return true
end
function Sync:_receiveAck(sender, packet)
    if self.isHost or sender ~= self.hostSteamId or not self.bound or not self:_binding(packet)
        or packet.clientEpoch ~= self.epoch or not integer(packet.acceptedThrough, true)
        or packet.acceptedThrough > self.eventSequence or packet.acceptedThrough < self.lastAck then return false end
    self.lastAck = packet.acceptedThrough
    local kept = {}; for _, event in ipairs(self.pending) do if event.sequence > self.lastAck then kept[#kept + 1] = event end end
    self.pending = kept
    for _, reject in ipairs(type(packet.rejected) == "table" and packet.rejected or {}) do self:_error("host rejected local event: " .. tostring(reject.reason)) end
    self.peers[sender].lastSeen = self.now
    if self.finishing and packet.finishedThrough == self.finishWatermark and self.lastAck >= self.finishWatermark then self.finishAcknowledged = true end
    return true
end
function Sync:_sendEvents(force)
    if self.isHost or not self.bound or not self:_connected(self.hostSteamId) or #self.pending == 0
        or (not force and self.now - self.lastEventSend < EVENT_INTERVAL) then return end
    local packet = self:_envelope("events"); packet.events = {}
    local bytes = #Json.encode(packet)
    for i = 1, math.min(EVENT_BATCH, #self.pending) do
        local addedBytes = #Json.encode(self.pending[i]) + (#packet.events > 0 and 1 or 0)
        if bytes + addedBytes > self.maxPayload then break end
        packet.events[#packet.events + 1] = self.pending[i]
        bytes = bytes + addedBytes
    end
    if #packet.events > 0 then self:_send(self.hostSteamId, packet) end
    self.lastEventSend = self.now
end

function Sync:_ack(sender, rejected)
    local peer, ack = self.peers[sender], self:_envelope("ack")
    ack.clientEpoch, ack.acceptedThrough, ack.rejected = peer.epoch, peer.eventSequence, rejected or {}
    if peer.finishWatermark and peer.eventSequence >= peer.finishWatermark then ack.finishedThrough = peer.finishWatermark end
    self:_send(sender, ack)
end
function Sync:_sendFinish(force)
    if self.isHost or not self.finishing or self.finishAcknowledged or not self.bound or not self:_connected(self.hostSteamId)
        or (not force and self.now - (self.lastFinishSend or -math.huge) < 1) then return end
    local packet = self:_envelope("finish"); packet.lastSequence = self.finishWatermark
    self:_send(self.hostSteamId, packet); self.lastFinishSend = self.now
end
function Sync:_receiveFinish(sender, packet)
    local peer = self.peers[sender]
    if not self.isHost or not self:_connected(sender) or not self:_binding(packet) or packet.epoch ~= peer.epoch
        or not integer(packet.lastSequence, true) or packet.lastSequence < peer.eventSequence
        or (peer.finishWatermark and peer.finishWatermark ~= packet.lastSequence) then return false end
    peer.finishWatermark, peer.lastSeen = packet.lastSequence, self.now
    self:_ack(sender)
    return true
end
function Sync:finish()
    if not self.bound then return false, "mission session is not bound" end
    if not self.finishing then
        self.finishing, self.finishStarted = true, self.now
        if not self.isHost then self.finishWatermark, self.finishAcknowledged = self.eventSequence, false end
    end
    self:_sendEvents(true); self:_sendFinish(true)
    return true
end
function Sync:forceSnapshot()
    if not self.isHost then return false, "only the authority sends snapshots" end
    self.transfers, self.nextSnapshot, self.finalSnapshotSequence = {}, self.now, nil
    return true
end
function Sync:_receiveSnapshotAck(sender, packet)
    local peer = self.peers[sender]
    if not self.isHost or not self:_connected(sender) or not self:_binding(packet) or packet.epoch ~= peer.epoch
        or not integer(packet.snapshotSequence) or packet.snapshotSequence > self.sender.sequence then return false end
    peer.snapshotSequence, peer.lastSeen = math.max(peer.snapshotSequence or 0, packet.snapshotSequence), self.now
    return true
end

local function splitRanges(bytes, size)
    local ranges, first = {}, 1
    while first <= #bytes do
        local last = math.min(#bytes, first + size - 1)
        while last < #bytes and bytes:byte(last + 1) >= 128 and bytes:byte(last + 1) < 192 do last = last - 1 end
        ranges[#ranges + 1] = {first, last}; first = last + 1
    end
    return ranges
end
function Sync:_startSnapshot()
    if not self.isHost or self.now < self.nextSnapshot then return end
    local targets = {}
    for id in pairs(self.roster) do
        if id ~= self.localId and self:_connected(id) and not self.transfers[id]
            and (not self.finalSnapshotSequence or (self.peers[id].snapshotSequence or 0)<self.finalSnapshotSequence) then
            targets[#targets+1]=id
        end
    end
    if #targets==0 then return end
    self.nextSnapshot = self.now + 5
    local snapshot = self.stats:snapshot(self.missionTime)
    local packet, error = self.sender:packet(snapshot)
    if not packet then self:_error(error); return end
    local bytes = Json.encode({packet = packet, peerCoverage = self:status().peers})
    if #bytes > MAX_SNAPSHOT then self:_error("snapshot exceeds 64 MiB assembly limit; remote view is stale"); return end
    if self.finishing and snapshot.status == "ended" and not self.finalSnapshotSequence then self.finalSnapshotSequence = packet.sequence end
    local frame={bytes=bytes,ranges=splitRanges(bytes,self.chunkBytes),sequence=packet.sequence}
    for _,peer in ipairs(targets) do self.transfers[peer]={frame=frame,index=1} end
end
function Sync:_sendChunks()
    -- Each peer retains at most one immutable frame. A slow peer can fill its
    -- missing fragments while acknowledged peers receive fresh snapshots.
    for peer,delivery in pairs(self.transfers) do
        if not self:_connected(peer) or (self.peers[peer].snapshotSequence or 0)>=delivery.frame.sequence then
            self.transfers[peer]=nil
        elseif delivery.index>#delivery.frame.ranges then
            if not delivery.retryAt then delivery.retryAt=self.now+2
            elseif self.now>=delivery.retryAt then delivery.index,delivery.retryAt=1,nil end
        end
    end
    local budget = 4
    while budget > 0 do
        local progressed = false
        for _, peer in ipairs(sortedKeys(self.transfers)) do
            local delivery=self.transfers[peer]
            local transfer,index=delivery.frame,delivery.index
            if self:_connected(peer) and index <= #transfer.ranges and budget > 0 then
                local range = transfer.ranges[index]
                local packet = self:_envelope("fragment")
                packet.sequence, packet.index, packet.count, packet.totalBytes = transfer.sequence, index, #transfer.ranges, #transfer.bytes
                packet.data = transfer.bytes:sub(range[1], range[2])
                budget = budget - 1
                if self:_send(peer, packet) then delivery.index = index + 1; progressed = true end
            end
        end
        if not progressed then break end
    end
end
function Sync:_receiveFragment(sender, packet)
    if self.isHost or sender ~= self.hostSteamId or not self.bound or not self:_binding(packet)
        or packet.epoch ~= self.authorityEpoch or not integer(packet.sequence)
        or not integer(packet.index) or not integer(packet.count) or packet.count > 65536 or packet.index > packet.count
        or not integer(packet.totalBytes) or packet.totalBytes > MAX_SNAPSHOT or type(packet.data) ~= "string" then return false end
    if packet.sequence<=self.receiver.sequence then
        if packet.sequence==self.receiver.sequence and packet.index==1 then
            -- The complete frame may have arrived but its ACK was lost.
            local ack=self:_envelope('snapshot_ack');ack.snapshotSequence=packet.sequence;self:_send(sender,ack)
        end
        return false
    end
    local a = self.assembly
    if a and packet.sequence < a.sequence then return false end
    if not a or packet.sequence > a.sequence then
        a = {sequence = packet.sequence, count = packet.count, totalBytes = packet.totalBytes, parts = {}, received = 0, bytes = 0, started = self.now}
        self.assembly = a
    end
    if a.count ~= packet.count or a.totalBytes ~= packet.totalBytes then self.assembly = nil; return false end
    if a.parts[packet.index] then
        if a.parts[packet.index] ~= packet.data then self.assembly = nil; return false end
        return true
    end
    a.parts[packet.index], a.received, a.bytes = packet.data, a.received + 1, a.bytes + #packet.data
    if a.bytes > a.totalBytes then self.assembly = nil; return false end
    self.peers[sender].lastSeen = self.now
    if a.received == a.count then
        self.assembly = nil
        if a.bytes ~= a.totalBytes then return false end
        local ok, bundle = pcall(Json.decode, table.concat(a.parts))
        if not ok or type(bundle) ~= "table" or type(bundle.packet) ~= "table" or bundle.packet.sequence ~= a.sequence then return false end
        local accepted = self.receiver:accept(bundle.packet)
        if accepted then
            self.hostPeerCoverage, self.lastSnapshotAt = copy(bundle.peerCoverage or {}), self.now
            self.finalSnapshotReceived = bundle.packet.snapshot.status == "ended"
            local ack = self:_envelope("snapshot_ack"); ack.snapshotSequence = a.sequence
            self:_send(sender, ack)
        end
        return accepted
    end
    return true
end

function Sync:_receive(sender, bytes)
    if sender == self.localId or not self.roster[sender] or type(bytes) ~= "string" or #bytes > self.maxPayload then return false end
    local ok, packet = pcall(Json.decode, bytes)
    if not ok or type(packet) ~= "table" or packet.wireVersion ~= 1 or packet.senderId ~= sender or packet.authorityId ~= self.hostSteamId then return false end
    if packet.kind == "hello" then return self:_receiveHello(sender, packet)
    elseif packet.kind == "events" then return self:_receiveEvents(sender, packet)
    elseif packet.kind == "ack" then return self:_receiveAck(sender, packet)
    elseif packet.kind == "fragment" then return self:_receiveFragment(sender, packet)
    elseif packet.kind == "finish" then return self:_receiveFinish(sender, packet)
    elseif packet.kind == "snapshot_ack" then return self:_receiveSnapshotAck(sender, packet) end
    return false
end

function Sync:tick(wallNow, missionTime)
    assert(nonnegative(wallNow) and wallNow >= self.now, "monotonic wall clock required")
    assert(not self.isHost or nonnegative(missionTime), "host mission clock required")
    self.now, self.missionTime = wallNow, missionTime or 0
    if self.now >= self.nextHello then
        if self.isHost then
            for _, id in ipairs(sortedKeys(self.roster)) do if id ~= self.localId then self:_hello(id) end end
        elseif self.roster[self.hostSteamId] then self:_hello(self.hostSteamId) end
        self.nextHello = self.now + 2
    end
    for _ = 1, 32 do
        local sender, bytes, error = self.transport.poll(self.transport.channel)
        if error then self:_error(error) end
        if not sender then break end
        self:_receive(sender, bytes)
    end
    if self.assembly and self.now - self.assembly.started > 60 then self.assembly = nil end
    if self.onStatus then self.onStatus(self:status(), self.missionTime) end
    self:_sendEvents()
    self:_sendFinish()
    self:_startSnapshot()
    self:_sendChunks()
    return self:status()
end

function Sync:snapshot() return self.receiver and self.receiver:snapshot() or nil end
function Sync:awaitNextSession()
    assert(not self.isHost, "host starts a new Sync instance for a confirmed new mission")
    self.waitingNew, self.bound = true, false
end
function Sync:status()
    local peers = {}
    for id, p in pairs(self.peers) do
        if id ~= self.localId and p.playerId then
            local record, connected = self.roster[id] or p, self:_connected(id)
            local coverage = {}
            for kind in pairs(record.localEventKinds) do
                for _, metric in ipairs(metricKinds[kind] or {}) do
                    coverage[metric] = connected and (p.observed[kind] or p.tracking[kind]) and "partial" or "unavailable"
                end
            end
            peers[id] = {playerId = record.playerId, state = connected and "connected" or "unavailable",
                lastSeen = p.lastSeen, eventCoverage = coverage, trackingKinds = copy(p.tracking), acceptedEventSequence = p.eventSequence}
        end
    end
    return {role = self.isHost and "host" or "client", sessionId = self.sessionId, bound = self.bound,
        authorityEpoch = self.authorityEpoch, generation = self.generation, peers = peers,
        hostPeerCoverage = copy(self.hostPeerCoverage), pendingEvents = #self.pending, lastSnapshotAt = self.lastSnapshotAt,
        snapshotStale = not self.isHost and (not self.lastSnapshotAt or self.now - self.lastSnapshotAt > 15),
        errors = copy(self.errors)}
end
function Sync:finishStatus()
    if not self.isHost then
        return {requested = not not self.finishing, lastSequence = self.finishWatermark, acceptedThrough = self.lastAck,
            acknowledged = not not self.finishAcknowledged, pendingEvents = #self.pending,
            finalSnapshotReceived = not not self.finalSnapshotReceived}
    end
    local peers, missing, ready, allAck, rejected = {}, {}, true, true, false
    for id, p in pairs(self.peers) do
        if id ~= self.localId and p.playerId then
            local complete = p.finishWatermark ~= nil and p.eventSequence >= p.finishWatermark
            local state = not self:_connected(id) and "missing" or (not p.finishWatermark and "waiting_finish" or (complete and "complete" or "waiting_events"))
            local ack = self.finalSnapshotSequence ~= nil and (p.snapshotSequence or 0) >= self.finalSnapshotSequence
            peers[id] = {state = state, lastSequence = p.finishWatermark, acceptedThrough = p.eventSequence,
                reportsComplete = complete, rejectedEvents = p.rejectedEvents or 0, snapshotAcknowledged = ack}
            if state == "missing" then missing[#missing + 1] = id end
            if not complete then ready = false end
            if not ack then allAck = false end
            if (p.rejectedEvents or 0) > 0 then rejected = true end
        end
    end
    local timedOut = self.finishing and self.now - self.finishStarted >= 15 or false
    return {requested = not not self.finishing, ready = ready, timedOut = timedOut,
        mayFinalize = not not self.finishing and (ready or timedOut), partial = not ready or #missing > 0 or rejected,
        peers = peers, missingPeers = missing, finalSnapshotSequence = self.finalSnapshotSequence,
        allSnapshotsAcknowledged = allAck}
end
function Sync:checkpoint()
    local peers = {}
    for id, peer in pairs(self.peers) do peers[id] = {epoch = peer.epoch, eventSequence = peer.eventSequence,
        observed = copy(peer.observed), finishWatermark = peer.finishWatermark, everReady = peer.everReady,
        snapshotSequence = peer.snapshotSequence, rejectedEvents = peer.rejectedEvents,
        playerId = peer.playerId, localEventKinds = copy(peer.localEventKinds)} end
    return {schemaVersion = 1, localId = self.localId, hostSteamId = self.hostSteamId, localEpoch = self.epoch,
        sessionId = self.sessionId, authorityEpoch = self.authorityEpoch, generation = self.generation,
        snapshotSequence = self.sender and self.sender.sequence, receiveSequence = self.receiver and self.receiver.sequence,
        currentSnapshot = self:snapshot(), hostSnapshot = self.isHost and self.stats:snapshot() or nil,
        pending = copy(self.pending), submitted = copy(self.submitted), attacks = copy(self.attacks),
        eventSequence = self.eventSequence, originSequence = self.originSequence, lastAck = self.lastAck, peers = peers, waitingNew = self.waitingNew,
        finishing = self.finishing, finishAcknowledged = self.finishAcknowledged, finalSnapshotSequence = self.finalSnapshotSequence}
end
return Sync
