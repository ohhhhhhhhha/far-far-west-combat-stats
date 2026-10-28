package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local Panel,UMG=require('Panel'),require('PanelUmg')
local checks=0
local function eq(a,b,message) checks=checks+1;assert(a==b,(message or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local e=dofile('FFWTools/tests/overlay_mouse_engine.lua').install()
local renderer,panel
renderer=UMG.new({getController=function() return e.controller end,
    viewport=function() return {width=1024,height=768,dpiScale=1} end,
    onAction=function(action) panel:mouse(action) end})
panel=Panel.new({render=function(model) renderer:render(model) end})
local sources={};for i=1,8 do sources['enemy'..i]=i end
local player={id='a',name='A',color='#56B4E9',connected=true,metrics={damage=10,incomingDamage=36},
    incomingBySource=sources,coverage={damage={status='complete'},incomingDamage={status='partial'}}}
panel:update({schemaVersion=1,sessionId='A',time=10,status='active',playerOrder={'a'},players={a=player},history={},
    encounters={boss={name='Boss',startTime=1,duration=4,playerOrder={'a'},players={a=player},history={}}}})
eq(type(panel.mouse),'function','Stats controller accepts owned mouse actions')
eq(panel:mouse('nextMetric'),false,'hidden events cannot change Stats selection')
panel:toggle();eq(e.controller.bShowMouseCursor,true)
eq(e.nativeRecentersMouse(),false,'F8 is mouse-operable without opening Esc')
local native=renderer.mouse
e.click(native.buttons.nextMetric.button);eq(panel.metric,'teamContribution')
e.click(native.buttons.previousMetric.button);eq(panel.metric,'overview')
e.click(native.buttons.nextScope.button);eq(panel.scopeId,'boss')
e.click(native.buttons.previousScope.button);eq(panel.scopeId,'mission')
panel:selectMetric('incomingSources');eq(panel:model().pageCount,2)
e.click(native.buttons.nextPage.button);eq(panel:model().page,2)
e.click(native.buttons.previousPage.button);eq(panel:model().page,1)
e.click(native.buttons.previousPage.button);eq(panel:model().page,2,'previous page wraps using visible page count')
local count=e.constructed;panel:refresh();eq(e.constructed,count,'cached refresh does not allocate buttons')
require('Locale').setCulture('en');panel:refresh()
eq(native.buttons.close.label.text,'Close','language changes refresh existing native buttons')
eq(native.buttons.nextMetric.label.text,'Metric >');eq(e.constructed,count)
e.click(native.buttons.close.button);eq(panel.visible,false);eq(renderer.attached,false);eq(e.controller.bShowMouseCursor,false)
e.click(native.buttons.nextMetric.button);eq(panel.metric,'incomingSources')
panel:toggle();local old=e.controller;local oldCalls=0
old.SetIgnoreLookInput=function() oldCalls=oldCalls+1;error('retired controller') end
e.newController(false);panel:refresh()
eq(oldCalls,0,'replaced controller is not used for native cleanup');eq(e.controller.bShowMouseCursor,true)
eq(native~=renderer.mouse,true)
local current=renderer.mouse;e.controller.world=e.object('World');panel:refresh();eq(renderer.mouse~=current,true,'world check precedes model cache shortcut')
panel:mouse('close');eq(e.controller.bShowMouseCursor,false)
e.controller.bShowMouseCursor=true;panel:toggle();panel:mouse('close');eq(e.controller.bShowMouseCursor,true,'closing Stats preserves menu cursor')
e.restore();print('stats_mouse_test: '..checks..' checks passed')
