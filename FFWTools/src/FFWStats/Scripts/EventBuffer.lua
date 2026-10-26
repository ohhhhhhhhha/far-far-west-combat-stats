-- Blueprint hooks are post callbacks. Delay dispatch until the game-thread poll
-- so nested server inputs can classify the already-observed final settlement.
-- A mismatched/unbalanced group preserves damage and the source already proved
-- by feedback (unknown only when feedback did not provide enough evidence).
local B={};B.__index=B
function B.new() return setmetatable({events={},groups={}},B) end
function B:push(event,time,localOnly)
    self.events[#self.events+1]={event=event,time=time,localOnly=localOnly==true}
end
function B:group(target,stamp)
    if target==nil or stamp==nil then return nil end
    local targets=self.groups[target] or {};self.groups[target]=targets
    local g=targets[stamp]
    if not g then g={stack={},pairs={},bad=false};targets[stamp]=g end
    return g
end
function B:damage(event,time,stamp,metadata)
    self:push(event,time,false)
    local g=self:group(event.targetId,stamp)
    if g then g.stack[#g.stack+1]={event=event,item=metadata.item,element=metadata.element} end
end
function B:settlement(target,stamp,input)
    local g=self:group(target,stamp);if not g then return end
    local observed=table.remove(g.stack)
    if not observed or observed.event.sourcePlayerId~=input.owner or observed.item~=input.item or observed.element~=input.element then
        g.bad=true;return
    end
    g.pairs[#g.pairs+1]={event=observed.event,category=input.category}
end
function B:flush(consume)
    for _,targets in pairs(self.groups) do
        for _,g in pairs(targets) do
            if not g.bad and #g.stack==0 then
                for _,pair in ipairs(g.pairs) do
                    -- A verified tick may refine the source, but incomplete
                    -- paired metadata must not erase the final feedback item.
                    if pair.category=='dot' or not pair.event.sourceCategory or pair.event.sourceCategory=='unknown' then
                        pair.event.sourceCategory=pair.category or 'unknown'
                    end
                end
            end
        end
    end
    local pending=self.events;self.events={};self.groups={}
    for _,r in ipairs(pending) do consume(r.event,r.time,r.localOnly) end
    return #pending
end
return B
