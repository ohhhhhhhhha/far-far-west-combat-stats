package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib');local Settings=require('HudSettings');local Hud=require('Hud');local Panel=require('Panel');local UMG=require('PanelUmg')
T.test('HUD preferences are saved only on selection and survive restart',function()
 local text,writes=nil,0
 local opts={path='prefs',read=function() return text end,write=function(_,t) writes=writes+1;text=t;return true end}
 local s=Settings.new(opts);T.eq(writes,0);T.eq(s.values.recentPeak,true);T.eq(s.values.damage,false)
 T.eq(s:toggle('damage'),true);T.eq(writes,1);T.eq(Settings.new(opts).values.damage,true)
 s.options.write=function() return nil,'denied' end;T.eq(s:toggle('damage'),false);T.eq(s.values.damage,true)
 T.eq(s:toggle('notAMetric'),false)
end)
T.test('HUD selection changes rendered data and the master switch hides the HUD',function()
 local s=Settings.new{};s.values={enabled=true,damage=true,ranking=false,hpBreakdown=false}
 local h=Hud.new{selfPlayerId='p',settings=s};h:update({schemaVersion=1,sessionId='s',status='active',time=1,playerOrder={'p'},history={},
 players={p={name='P',metrics={damage=120.25},coverage={damage={status='partial'}}}}})
 local scene=Hud.layout(h:model(),{width=1280,height=720,dpiScale=1});local found=false
 for _,c in ipairs(scene.commands) do if c.role=='hud-damage' then found=true;T.eq(c.text,'120.25') end;T.eq(c.role=='hud-rank-score',false);T.eq(c.role=='hud-recent-peak',false) end
 T.eq(found,true);s.values.enabled=false;T.eq(h:model(),nil)
end)
T.test('display settings open before a mission and do not change metric selection',function()
 local s=Settings.new{};local p=Panel.new{hudSettings=s};p:toggle();p:mouse('toggleSettings');local m=p:model();T.eq(m.settings~=nil,true)
 local scene=UMG.layout(m,{width=1280,height=720,dpiScale=1});local found=false
 for _,c in ipairs(scene.commands) do if c.action=='toggleHud' and c.value=='damage' then found=true end end
 T.eq(found,true);p:mouse('toggleHud','damage');T.eq(s.values.damage,true);p:mouse('toggleSettings');T.eq(p.metric,'overview')
end)
T.test('all HUD values and settings pages fit the supported 720p canvas',function()
 local s=Settings.new{};for _,d in ipairs(Settings.definitions) do s.values[d[1]]=true end
 local players={};for i=1,4 do players[tostring(i)]={name='Player '..i,metrics={damage=100},coverage={damage={status='partial'}}} end
 local h=Hud.new{selfPlayerId='1',settings=s};h:update({schemaVersion=1,sessionId='s',status='active',time=1,playerOrder={'1','2','3','4'},players=players,history={}})
 local scene=Hud.layout(h:model(),{width=1280,height=720,dpiScale=1})
 T.eq(scene.height<=688,true)
 for _,c in ipairs(scene.commands) do T.eq(c.x+c.width<=scene.width+.1 and c.y+c.height<=scene.height+.1,true) end
 for page=1,2 do
  local model={settings=s:model(page)};scene=UMG.layout(model,{width=1280,height=720,dpiScale=1})
  for _,c in ipairs(scene.commands) do T.eq(c.x+c.width<=scene.width+.1 and c.y+c.height<=scene.height+.1,true) end
 end
end)
T.test('HUD tile labels and numbers occupy separate native line-height bands',function()
 local s=Settings.new{};s.values={enabled=true,recentPeak=true,missionPeak=true,damage=true,incoming=true,ranking=false,hpBreakdown=false}
 local h=Hud.new{selfPlayerId='p',settings=s};h:update({schemaVersion=1,sessionId='s',status='active',time=1,playerOrder={'p'},history={},
 players={p={name='P',metrics={damage=100,incomingDamage=20,rollingDps=50},coverage={damage={status='partial'},incomingDamage={status='partial'}}}}})
 local scene=Hud.layout(h:model(),{width=1280,height=720,dpiScale=1})
 local bands={}
 for _,c in ipairs(scene.commands) do
  if c.kind=='text' and c.x==14 and c.y>=30 then bands[#bands+1]=c end
 end
 table.sort(bands,function(a,b) return a.y<b.y end)
 for i=2,#bands do T.eq(bands[i-1].y+bands[i-1].height<=bands[i].y,true,'numeric text must not collide with its label or next tile') end
end)
T.test('legacy HUD default is used only when no saved choice exists',function()
 T.eq(Settings.new({enabled=false}).values.enabled,false)
 T.eq(Settings.new({enabled=false,path='p',read=function() return '{"enabled":true}' end}).values.enabled,true)
end)
T.test('native settings clicks save choices without losing panel mouse ownership',function()
 local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
 local ok,err=pcall(function()
  local writes=0;local s=Settings.new({path='prefs',read=function() return nil end,write=function() writes=writes+1;return true end})
  local panel,renderer
  renderer=UMG.new({getController=function() return e.controller end,viewport=function() return {width=1280,height=720,dpiScale=1} end,
   onAction=function(action,value) panel:mouse(action,value) end})
  panel=Panel.new({hudSettings=s,render=function(model) renderer:render(model) end});panel:toggle()
  e.click(renderer.mouse.buttons.toggleSettings.button);T.eq(panel.showSettings,true)
  e.click(renderer.mouse.buttons['hud-damage'].button);T.eq(s.values.damage,true);T.eq(writes,1)
  T.eq(e.controller.bShowMouseCursor,true)
  e.click(renderer.mouse.buttons.nextPage.button);T.eq(panel:model().page,2)
  e.click(renderer.mouse.buttons['hud-ranking'].button);T.eq(s.values.ranking,false);T.eq(writes,2)
  e.click(renderer.mouse.buttons.close.button);T.eq(e.controller.bShowMouseCursor,false)
 end)
 e.restore();if not ok then error(err,0) end
end)
T.test('HUD quality follows selected metrics rather than hidden baseline metrics',function()
 local s=Settings.new{};s.values={enabled=true,teamHealing=true,ranking=false,hpBreakdown=false}
 local p={name='P',metrics={teamHealing=25,kills=2},coverage={teamHealing={status='partial'},kills={status='complete'}}}
 local h=Hud.new{selfPlayerId='p',settings=s};h:update({schemaVersion=1,sessionId='s',status='active',time=1,playerOrder={'p'},history={},players={p=p}})
 T.eq(h:model().rows[1].partial,true,'selected support data retains partial coverage')
 s.values.teamHealing=false;s.values.kills=true
 p.metrics.damage=100;p.metrics.rollingDps=20;p.coverage.damage={status='partial'}
 T.eq(h:model().rows[1].partial,false,'hidden partial DPS must not mark a complete selected count')
end)
T.finish()
