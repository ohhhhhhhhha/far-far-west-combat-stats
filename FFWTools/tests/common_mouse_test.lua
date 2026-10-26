local checks=0
local function eq(a,b,message) checks=checks+1;assert(a==b,(message or '')..' expected '..tostring(b)..', got '..tostring(a)) end
local E=dofile('FFWTools/tests/overlay_mouse_engine.lua')
local e=E.install()
local loaded,Mouse=pcall(dofile,'FFWTools/src/FFWStats/Scripts/MousePanel.lua')
eq(loaded,true,'native mouse helper is available')
local function panel(module,callback)
    return module.new({host=e.object('Host'),root=e.object('Canvas'),tree=e.object('Tree'),font=e.object('Font'),
        controller=e.controller,library=StaticFindObject('/Script/UMG.WidgetBlueprintLibrary'),onAction=callback})
end
local actions={}
local first=panel(Mouse,function(action,value) actions[#actions+1]={action,value} end)
first:button('row',{text='Card A',action='select',value=3,x=0,y=0,width=180,height=40})
local row=first.buttons.row
e.click(row.button);eq(#actions,0,'hidden native events cannot act')
eq(e.nativeRecentersMouse(),true,'native gameplay recenters the cursor')
first:show();eq(e.controller.bShowMouseCursor,true)
eq(e.nativeRecentersMouse(),false,'opening an overlay stops native recentering without Esc')
eq(e.controller.lookIgnores,1,'mouse navigation does not rotate the camera')
local modes=#e.modes;first:show();eq(#e.modes,modes,'refresh does not steal focus')
e.invoke(e.object('Unowned native template'),'F_ChildClick');eq(#actions,0,'game buttons never route to overlay actions')
e.click(row.button);eq(actions[1][1],'select');eq(actions[1][2],3)
first:button('row',{text='Card B',action='select',value=8,x=0,y=0,width=180,height=40})
eq(first.buttons.row,row,'paging reuses native button objects')
e.click(row.button);eq(actions[2][2],8,'reused rows select the current page item')
first:button('row',{text='Empty',action='select',value=9,x=0,y=0,width=180,height=40,enabled=false})
e.click(row.button);eq(#actions,2,'disabled controls ignore even queued native events')
-- Separate module loads represent independent UE4SS mod VMs sharing native primitives.
local Other=dofile('FFWTools/src/FFWStats/Scripts/MousePanel.lua')
local second=panel(Other,function() end)
first:button('row',{text='Card B',action='select',value=8,x=0,y=0,width=180,height=40})
second:show();e.click(row.button);eq(#actions,2,'superseded overlay cannot process a queued click')
first:hide();eq(e.controller.bShowMouseCursor,true,'older overlay closing cannot release the current cursor')
second:hide();eq(e.controller.bShowMouseCursor,false,'last overlay restores gameplay cursor after either key callback order')
eq(e.nativeRecentersMouse(),true,'last close restores the native gameplay flag')
eq(e.controller.lookIgnores,0,'cross-VM handoff releases exactly one look lock')
eq(e.modes[#e.modes].mode,'gameOnly')
first:show();second:show();second:hide();first:hide()
eq(e.controller.bShowMouseCursor,false,'reverse close order restores the same original cursor')
e.controller.bShowMouseCursor=true
first:show();local afterShow=#e.modes;first:hide()
eq(e.controller.bShowMouseCursor,true,'pre-existing menu cursor stays visible')
eq(e.modes[#e.modes].mode,'viewportFocus');eq(#e.modes,afterShow+1)
-- Esc/native menu opened while an overlay is visible must survive overlay close.
e.controller.bShowMouseCursor=false
first:show();e.controller.Pawn.refBpMenu.isMenuOpened=true
first:hide();eq(e.controller.bShowMouseCursor,true,'closing overlay retains a newly opened native menu')
eq(e.controller.Pawn.refBpMenu.isUiMode,true)
eq(e.modes[#e.modes].mode,'viewportFocus')
e.controller.Pawn.refBpMenu.isMenuOpened=false;e.controller.Pawn.refBpMenu.isUiMode=false
-- A pre-existing UI flag and look lock belong to the game, not this overlay.
e.controller.Pawn.refBpMenu.isUiMode=true;e.controller:SetIgnoreLookInput(true)
first:show();first:hide();eq(e.controller.Pawn.refBpMenu.isUiMode,true);eq(e.controller.lookIgnores,1)
e.controller.Pawn.refBpMenu.isUiMode=false;e.controller:SetIgnoreLookInput(false)
e.controller.bShowMouseCursor=false;first:show();local old=e.controller
e.newController(false);eq(first:isCurrent(e.controller),false,'travel invalidates old input owner')
first:dispose();eq(old.bShowMouseCursor,false);eq(row.host.Visibility,2,'disposed targets are collapsed')
e.click(row.button);eq(#actions,2,'disposed delegates cannot change selection')
second:dispose()
local travelClicks=0
local invalidated=panel(Mouse,function() travelClicks=travelClicks+1 end)
invalidated:button('close',{text='Close',action='close',x=0,y=0,width=100,height=32})
invalidated:show();e.controller.world=e.object('World');e.click(invalidated.buttons.close.button)
eq(travelClicks,0,'old-world button events are rejected before the next display refresh')
invalidated.buttons.close.host.destroyed=true
invalidated:dispose()
local listeners=0;for _,list in pairs(e.hooks) do for _,fn in ipairs(list) do if fn then listeners=listeners+1 end end end
eq(listeners,0,'travel must release routes and native hooks even after UObjects become invalid')
e.restore()
print('common_mouse_test: '..checks..' checks passed')
