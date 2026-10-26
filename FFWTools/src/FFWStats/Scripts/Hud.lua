-- Small passive view of the existing statistics snapshot. No hooks, timer or I/O.
local L,Contribution=require('Locale'),require('Contribution')
local Settings=require('HudSettings')
local Hud={}
local View={};View.__index=View
local colors={background='#28232D',text='#F4E7CA',muted='#BCB1A3',grid='#51444B',frame='#9A7349',
    dps='#59D4C7',incoming='#F28B82',shield='#72B7EA',partial='#E2B969'}
local function finite(v) return type(v)=='number' and v==v and v>=0 and v<math.huge end
local function compact(v)
    if not finite(v) then return '—' end
    if v>=1000000 then return string.format('%.2fM',v/1000000) end
    if v>=10000 then return string.format('%.2fk',v/1000) end
    return string.format('%.2f',v)
end
local function short(text,count)
    text=tostring(text or '')
    local ok,length=pcall(utf8.len,text)
    if ok and length and length>count then return text:sub(1,utf8.offset(text,count+1)-1)..'…' end
    return text
end
local function metric(player,key)
    local coverage=(player.coverage or {})[key]
    if not coverage and key=='rollingDps' then coverage=(player.coverage or {}).damage end
    local status=coverage and coverage.status or 'unavailable'
    local value=(player.metrics or {})[key]
    if not finite(value) or status=='unavailable' then value,status=nil,'unavailable' end
    return {value=value,text=compact(value),status=status}
end
function Hud.new(options)
    return setmetatable({options=options or {},previous=false},View)
end
function View:peaks(snapshot,id,current)
    local history=snapshot.history or {}
    if self.peakSession~=snapshot.sessionId or self.peakPlayer~=id or #history<(self.processed or 0) then
        self.peakSession,self.peakPlayer,self.missionPeak,self.processed=snapshot.sessionId,id,nil,0
    end
    -- One initial history pass, then only new samples plus the mutable last sample.
    for i=math.max(1,self.processed or 0),#history do
        local entry=history[i].players and history[i].players[id]
        if entry and finite(entry.rollingDps) and entry.coverage~='unavailable' then
            self.missionPeak=math.max(self.missionPeak or 0,entry.rollingDps)
        end
    end
    self.processed=#history
    if current.value~=nil then self.missionPeak=math.max(self.missionPeak or 0,current.value) end
    local maximum=current.value
    local start=(snapshot.time or 0)-30
    for i=#history,1,-1 do
        local sample=history[i]
        if sample.time<=start then break end
        local entry=sample.players and sample.players[id]
        if sample.time<=(snapshot.time or 0) and entry and finite(entry.rollingDps) and entry.coverage~='unavailable' then
            maximum=math.max(maximum or 0,entry.rollingDps)
        end
    end
    return {value=maximum,text=compact(maximum)}, {value=self.missionPeak,text=compact(self.missionPeak)}
end
function View:update(snapshot,display)
    self.snapshot,self.previous=snapshot,display and display.previous==true or false
end
function View:model()
    local snapshot=self.snapshot
    if self.options.enabled==false or self.previous or not snapshot or snapshot.status~='active' or snapshot.schemaVersion~=1 then return nil end
    local preferences=self.options.settings and self.options.settings.values or Settings.defaults()
    if preferences.enabled==false then return nil end
    local stale=self.options.isStale and self.options.isStale()==true or false
    local model={rows={},stale=stale,preferences=preferences,
        leaderboard=Contribution.build(snapshot,{selfPlayerId=self.options.selfPlayerId,stale=stale})}
    local id=self.options.selfPlayerId
    local player=id and snapshot.players and snapshot.players[id]
    if not player then model.message=L.choose('等待本机统计','Waiting for local stats');return model end
    local row={id=id,name=player.name,color=player.color,dps=metric(player,'rollingDps'),
        incoming=metric(player,'incomingDamage'),hp=metric(player,'hpLoss'),shield=metric(player,'shieldAbsorbed')}
    row.recentPeak,row.missionPeak=self:peaks(snapshot,id,row.dps)
    if model.stale or player.connected==false then
        row.dps={value=nil,text='—',status='unavailable'};row.recentPeak={value=nil,text='—'}
    end
    row.partial=preferences.hpBreakdown==true and (row.hp.status=='partial' or row.shield.status=='partial')
    if row.incoming.value~=nil and row.hp.value~=nil and row.shield.value~=nil then
        local total=row.hp.value+row.shield.value
        row.hpFraction=total>0 and row.hp.value/total or 0
        row.shieldFraction=total>0 and row.shield.value/total or 0
    end
    row.tiles={}
    for _,d in ipairs(Settings.definitions) do
        if preferences[d[1]] and (d[5] or d[1]=='recentPeak' or d[1]=='missionPeak') then
            local value=d[1]=='recentPeak' and row.recentPeak or d[1]=='missionPeak' and row.missionPeak or metric(player,d[5])
            if d[1]=='rollingDps' then value=row.dps end
            if d[1]=='recentPeak' or d[1]=='missionPeak' then value.status=metric(player,'damage').status end
            if value.status=='partial' then row.partial=true end
            row.tiles[#row.tiles+1]={id=d[1],label=L.choose(d[2],d[3]),value=value.value,
                text=d[6] and value.value~=nil and string.format('%.0f',value.value) or value.text,
                color=d[1]=='incoming' and colors.incoming or d[1]=='missionPeak' and colors.partial or colors.dps}
        end
    end
    model.rows[1]=row
    return model
end
function Hud.layout(model,viewport)
    viewport=viewport or {width=1024,height=768,dpiScale=1}
    local width=math.min(316,viewport.width-32);local row=model.rows[1]
    local preferences=model.preferences or Settings.defaults()
    local board=model.leaderboard or {rows={}};local rankCount=math.min(4,#board.rows)
    local tileCount=row and #row.tiles or 0
    local metricHeight=math.floor(tileCount/2)*56+(tileCount%2==1 and 32 or 0)
    local height=row and (34+metricHeight+(preferences.hpBreakdown and 34 or 0)+(preferences.ranking and 24+math.max(1,rankCount)*20 or 0)) or 58
    local scene={width=width,height=height,margin=16,dpiScale=viewport.dpiScale or 1,commands={}}
    local commands=scene.commands
    local function text(value,x,y,w,size,color,role)
        commands[#commands+1]={kind='text',text=value,x=x,y=y,width=w,height=size*1.6,size=size,color=color or colors.text,role=role}
    end
    local function bar(x,y,w,h,fraction,color,role,alpha)
        commands[#commands+1]={kind='bar',x=x,y=y,width=w,height=h,fraction=fraction,color=color,role=role,alpha=alpha or 1}
    end
    bar(0,0,width,height,1,colors.frame,'hud-frame',.9);bar(1,1,width-2,height-2,1,colors.background,'hud-background',.94)
    if not row then text(model.message or L.choose('等待统计','Waiting for stats'),14,15,width-28,14,colors.muted);return scene end
    text(short(row.name,6)..L.choose('（你）',' (you)'),14,7,width-120,13,row.color or colors.text,'hud-player')
    text(model.stale and L.choose('同步中','Syncing') or row.partial and L.choose('* 部分','* Partial') or '',width-102,7,88,12,colors.partial,'hud-quality')
    local half=(width-42)/2
    for i,tile in ipairs(row.tiles) do
        local role=tile.id=='recentPeak' and 'hud-recent-peak' or tile.id=='missionPeak' and 'hud-mission-peak' or 'hud-'..tile.id
        local x=14+((i-1)%2)*(half+14);local y=32+math.floor((i-1)/2)*56
        if i==tileCount and tileCount%2==1 then
            text(tile.label,14,y+4,half,12,colors.muted)
            text(tile.text,width/2+7,y,half,20,tile.value and tile.color or colors.muted,role)
        else
            text(tile.label,x,y,half,12,colors.muted)
            text(tile.text,x,y+22,half,20,tile.value and tile.color or colors.muted,role)
        end
    end
    local y=32+metricHeight
    if preferences.hpBreakdown then
        text(L.choose('损血 ','HP ')..row.hp.text..L.choose('  护盾 ','  Shield ')..row.shield.text,14,y,width-28,12,colors.muted,'hud-breakdown')
        bar(14,y+24,width-28,4,1,colors.grid,'hud-incoming-base')
        if row.hpFraction then
            if row.hpFraction>0 then bar(14,y+24,(width-28)*row.hpFraction,4,1,colors.incoming,'hud-hp-share') end
            if row.shieldFraction>0 then bar(14+(width-28)*row.hpFraction,y+24,(width-28)*row.shieldFraction,4,1,colors.shield,'hud-shield-share') end
        end
        y=y+34
    end
    if preferences.ranking then
        text(L.choose('团队贡献 %','Contribution %')..(board.partial and ' *' or ''),14,y,176,12,colors.partial)
        text(L.choose('F8 详情','F8 details'),width-100,y,86,12,colors.muted);y=y+23
        for i=1,rankCount do
            local ranked=board.rows[i];local ry=y+(i-1)*20
            text(ranked.rank and tostring(ranked.rank) or '—',14,ry,24,12,ranked.isSelf and colors.partial or colors.text)
            text(short(ranked.name,5),42,ry,104,12,ranked.color,'player-name')
            if ranked.score~=nil then
                bar(149,ry+7,76,5,1,colors.grid,'hud-rank-track');bar(149,ry+7,76,5,ranked.score/100,ranked.color,'hud-rank-bar')
            end
            text(ranked.scoreText..(ranked.score and ranked.partial and '*' or ''),width-76,ry,62,12,colors.text,'hud-rank-score')
        end
        if rankCount==0 then text(board.message or L.choose('等待贡献数据','Waiting for contribution'),14,y,width-28,12,colors.muted) end
    end
    return scene
end
return Hud
