local Json = require("Json")
local Stats = require("Stats")
local Store = {}
local function readOne(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local text = file:read("a"); file:close()
    local ok, snapshot = pcall(Json.decode, text)
    if not ok then return nil, snapshot end
    local stats, invalid = Stats.restore(snapshot)
    if not stats then return nil, invalid end
    return stats:snapshot(snapshot.time), nil, snapshot.syncCheckpoint
end
function Store.read(path)
    local snapshot, err, checkpoint = readOne(path)
    if snapshot then return snapshot, nil, checkpoint end
    local recovered, _, recoveredCheckpoint = readOne(path .. ".bak")
    if recovered then return recovered, "recovered previous complete snapshot", recoveredCheckpoint end
    return nil, err
end
-- Uses rename-overwrite where the OS supports it. Standard Lua on Windows needs
-- a recoverable .bak rotation; it cannot promise an atomic ReplaceFile operation.
function Store.write(path, snapshot, checkpoint)
    local stats, invalid = Stats.restore(snapshot)
    if not stats then return nil, invalid end
    local canonical = stats:snapshot(snapshot.time)
    -- Save the acknowledgement watermark in the SAME replacement as the totals
    -- it acknowledges. Two independent files can replay or lose client events.
    canonical.syncCheckpoint = checkpoint
    local ok, text = pcall(Json.encode, canonical)
    if not ok then return nil, text end
    return Store.writeText(path, text)
end
-- Also used for the monotonic boot epoch; failures prevent publishing an epoch.
function Store.writeText(path, text)
    local temp, backup = path .. ".tmp", path .. ".bak"
    local file, err = io.open(temp, "wb")
    if not file then return nil, err end
    local written, writeError = file:write(text)
    local closed, closeError = file:close()
    if not written or not closed then return nil, writeError or closeError end
    local replaced, replaceError = os.rename(temp, path)
    if replaced then os.remove(backup); return true end
    local old = io.open(path, "rb")
    if not old then return nil, replaceError end
    old:close()
    os.remove(backup)
    local moved, moveError = os.rename(path, backup)
    if not moved then return nil, moveError end
    replaced, replaceError = os.rename(temp, path)
    if not replaced then os.rename(backup, path); return nil, replaceError end
    os.remove(backup)
    return true
end
-- Invoke only on an explicit mission-start observation. Repeated observation of
-- the same stable ID must return the same object rather than clear its totals.
function Store.start(current, sessionId)
    if current and current._state.sessionId == sessionId then return current, false end
    return Stats.new(sessionId), true
end
-- Omit sessionId at application/lobby startup to show the retained last mission.
function Store.resume(path, sessionId)
    local snapshot, err = Store.read(path)
    if snapshot then
        local stats = assert(Stats.restore(snapshot))
        if not sessionId or snapshot.sessionId == sessionId then return stats, true end
        return Stats.new(sessionId), false
    end
    if sessionId then return Stats.new(sessionId), false, err end
    return nil, err
end
return Store
