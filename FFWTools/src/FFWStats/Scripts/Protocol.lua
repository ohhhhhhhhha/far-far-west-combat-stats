-- Cumulative snapshot reconciliation only. The caller supplies an authenticated
-- authority, session and monotonically increasing epoch using its transport.
local Stats = require("Stats")
local Protocol = {VERSION = 1}
local Sender, Receiver = {}, {}
Sender.__index, Receiver.__index = Sender, Receiver
local function id(value) return type(value) == "string" and value ~= "" end
local function positiveInteger(value)
    return type(value) == "number" and value >= 1 and value <= 9007199254740991 and value % 1 == 0
end
local function canonical(snapshot)
    local stats, err = Stats.restore(snapshot)
    if not stats then return nil, err end
    return stats:snapshot(snapshot.time)
end
local function validateBinding(sessionId, senderId, epoch)
    assert(id(sessionId) and id(senderId), "stable session and authority IDs required")
    assert(positiveInteger(epoch), "positive, exactly representable epoch required")
end
function Protocol.sender(sessionId, senderId, epoch)
    validateBinding(sessionId, senderId, epoch)
    return setmetatable({sessionId = sessionId, senderId = senderId, epoch = epoch, sequence = 0}, Sender)
end
function Sender:packet(snapshot)
    local value, err = canonical(snapshot)
    if not value then return nil, err end
    if value.sessionId ~= self.sessionId then return nil, "wrong session" end
    if not positiveInteger(self.sequence + 1) then return nil, "sequence exhausted; establish a new epoch" end
    self.sequence = self.sequence + 1
    return {protocolVersion = Protocol.VERSION, kind = "snapshot", sessionId = self.sessionId,
        senderId = self.senderId, epoch = self.epoch, sequence = self.sequence, snapshot = value}
end
function Protocol.receiver(sessionId, authorityId, epoch)
    validateBinding(sessionId, authorityId, epoch)
    return setmetatable({sessionId = sessionId, authorityId = authorityId, epoch = epoch, sequence = 0}, Receiver)
end
function Receiver:accept(packet)
    if type(packet) ~= "table" or packet.protocolVersion ~= Protocol.VERSION or packet.kind ~= "snapshot" then return false, "incompatible packet" end
    if packet.sessionId ~= self.sessionId then return false, "wrong session" end
    if packet.senderId ~= self.authorityId then return false, "wrong authority" end
    if packet.epoch ~= self.epoch then return false, "unbound epoch" end
    if not positiveInteger(packet.sequence) or packet.sequence <= self.sequence then return false, "stale sequence" end
    local snapshot, err = canonical(packet.snapshot)
    if not snapshot then return false, err end
    if snapshot.sessionId ~= self.sessionId then return false, "snapshot belongs to another session" end
    self.current, self.sequence = snapshot, packet.sequence
    return true
end
function Receiver:reconnect(epoch)
    if not positiveInteger(epoch) or epoch < self.epoch then return false, "stale epoch" end
    if epoch > self.epoch then self.epoch, self.sequence = epoch, 0 end
    -- Keep the last complete view while waiting for a new authoritative snapshot.
    return true
end
function Receiver:snapshot()
    if not self.current then return nil end
    return canonical(self.current)
end
return Protocol
