-- Relative contribution from recorded mission totals. Never changes statistics.
local L=require('Locale')
local C={}
local groupSpecs={
    {'output','输出','Damage',40,'#DDAE66'},
    {'elimination','击杀/助攻','Eliminations',20,'#D88A70'},
    {'support','有效支援','Support',20,'#70C2A7'},
    {'rescue','救援','Revives',15,'#82B9DD'},
    {'survival','存活','Survival',5,'#BAA4D5'},
}
local criteria={
    {'damage','output',40},{'kills','elimination',10},{'eliteKills','elimination',3},
    {'bossKills','elimination',5},{'assists','elimination',2},
    {'teamHealing','support',12},{'selfHealing','support',3},{'shieldGranted','support',5},
    {'revives','rescue',15},{'survival','survival',5},
}
local function finite(v) return type(v)=='number' and v==v and v>=0 and v<math.huge end
local function metric(snapshot,id,player,key)
    local original=key=='survival' and 'aliveDuration' or key
    local coverage=(player.coverage or {})[original]
    local status=coverage and coverage.status or 'unavailable'
    local value=(player.metrics or {})[original]
    if key=='survival' then
        local state=snapshot.state and snapshot.state.players and snapshot.state.players[id]
        local joined=state and state.joinedAt
        local duration=finite(joined) and finite(snapshot.time) and snapshot.time-joined or 0
        value=finite(value) and duration>0 and math.min(1,value/duration) or nil
    end
    if not finite(value) or status=='unavailable' then value,status=nil,'unavailable' end
    return {value=value,status=status}
end
function C.build(snapshot,options)
    options=options or {}
    local board={rows={},groups={},activeWeight=0,partial=options.stale==true,stale=options.stale==true}
    for _,g in ipairs(groupSpecs) do
        board.groups[#board.groups+1]={id=g[1],label=L.choose(g[2],g[3]),weight=g[4],color=g[5]}
    end
    if not snapshot then board.message=L.choose('等待统计数据','Waiting for statistics');return board end
    for index,id in ipairs(snapshot.playerOrder or {}) do
        local p=(snapshot.players or {})[id]
        if p then
            local row={id=id,name=p.name or id,color=p.color or '#BCB1A3',connected=p.connected,
                isSelf=id==options.selfPlayerId,index=index,metrics={},missingMetrics={},groups={},points=0,hasActionData=false}
            for _,item in ipairs(criteria) do
                local m=metric(snapshot,id,p,item[1]);row.metrics[item[1]]=m
                if m.value~=nil then
                    row.groups[item[2]]=row.groups[item[2]] or 0
                    if item[1]~='survival' then row.hasActionData=true end
                else row.missingMetrics[item[1]]=true end
                if m.status~='complete' then board.partial=true end
            end
            board.rows[#board.rows+1]=row
        end
    end
    local actionActive=false
    local pools={}
    for _,item in ipairs(criteria) do
        local total=0
        for _,row in ipairs(board.rows) do
            local value=row.metrics[item[1]].value
            if value~=nil and (item[1]~='survival' or row.hasActionData) then total=total+value end
        end
        pools[item[1]]=total
        if item[1]~='survival' and total>0 then actionActive=true end
    end
    for _,item in ipairs(criteria) do
        local total=pools[item[1]]
        if total>0 and (item[1]~='survival' or actionActive) then
            board.activeWeight=board.activeWeight+item[3]
            for _,row in ipairs(board.rows) do
                local value=row.metrics[item[1]].value
                if value~=nil and row.hasActionData then
                    local points=item[3]*value/total
                    row.points=row.points+points
                    row.groups[item[2]]=(row.groups[item[2]] or 0)+points
                end
            end
        end
    end
    for _,row in ipairs(board.rows) do
        row.partial=board.partial
        if row.hasActionData then
            row.score=board.activeWeight>0 and row.points/board.activeWeight*100 or 0
            row.scoreText=string.format('%.2f',row.score)
            row.rounded=math.floor(row.score*100+.5)
            for group,points in pairs(row.groups) do row.groups[group]=board.activeWeight>0 and points/board.activeWeight*100 or 0 end
        else row.scoreText='—';row.groups={} end
    end
    table.sort(board.rows,function(a,b)
        if a.score==nil or b.score==nil then
            if a.score~=nil then return true elseif b.score~=nil then return false end
        elseif a.rounded~=b.rounded then return a.rounded>b.rounded end
        return a.index<b.index
    end)
    local prior,rank
    for i,row in ipairs(board.rows) do
        if row.score~=nil then
            if row.rounded~=prior then rank=i;prior=row.rounded end
            row.rank=rank
        end
    end
    if not actionActive then board.message=L.choose('等待贡献事件','Waiting for contribution events') end
    board.note=board.stale and L.choose('同步中，显示最近记录；* 表示暂列。','Syncing; showing the last received records. * means provisional.')
        or L.choose('按已记录数据计算队内加权占比；* 表示暂列。','Weighted share of recorded team data; * means provisional.')
    return board
end
return C
