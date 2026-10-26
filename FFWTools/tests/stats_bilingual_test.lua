package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local L,P,U=require('Locale'),require('Panel'),require('PanelUmg')
local checks=0
local function eq(a,b,m) checks=checks+1;assert(a==b,(m or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local name='伤害玩家'
local p={id='local',name=name,color='#56B4E9',connected=true,metrics={damage=42},coverage={damage={status='complete'}},damageBySource={}}
local snapshot={schemaVersion=1,sessionId='test',time=5,status='ended',playerOrder={'local'},players={['local']=p},history={},encounters={}}
local panel=P.new({selfPlayerId='local'});panel:update(snapshot);panel:toggle()
eq(panel:model().title,'战斗统计')
L.setCulture('en-US')
local m=panel:model()
eq(m.title,'Combat Stats','cached model refreshes on culture change')
eq(m.legend[1].name,name,'player names are never translated')
eq(m.missionLabel,'Previous mission')
eq(m.charts[1].rows[1].name,name)
for _,chart in ipairs(m.charts) do
    for _,code in utf8.codes(chart.label..chart.unit) do eq(code<0x4e00 or code>0x9fff,true,'chart labels and units are translated') end
end
local scene=U.layout(m)
for _,cmd in ipairs(scene.commands) do
    if cmd.kind=='text' then
        if cmd.role=='legend' or cmd.role=='player-name' then eq(cmd.text:find('伤害',1,true)~=nil,true)
        else for _,code in utf8.codes(cmd.text) do eq(code<0x4e00 or code>0x9fff,true,'rendered English UI contains no Chinese fragments') end end
    end
end
L.setCulture('zh-CN');eq(panel:model().title,'战斗统计')
eq(snapshot.players['local'].name,name)
print('stats_bilingual_test: '..checks..' checks passed')
