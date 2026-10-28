-- Unreal boundary for the actual overlay controllers/renderers. Native events
-- enter registered UFunction hooks; Lua callbacks are never delegate bindings.
local E={}
function E.install()
    local e={objects={},hosts={},hooks={},shared={},modes={},constructed=0,serial=0}
    local names={'StaticFindObject','StaticConstructObject','FText','RegisterHook','UnregisterHook','ModRef','LoadAsset'}
    local saved={};for _,name in ipairs(names) do saved[name]=_G[name] end
    local methods={}
    function methods:IsValid() return not self.destroyed end
    function methods:GetAddress() return self.address end
    function methods:GetFullName() return self.name end
    function methods:GetWorld() return self.world end
    function methods:GetCDO() return self end
    function methods:SetVisibility(v) self.Visibility=v end
    function methods:SetIsEnabled(v) self.enabled=v end
    function methods:SetText(v) self.text=v end
    function methods:GetText() return self.text or '' end
    function methods:SetHintText(v) self.hint=v end
    function methods:SetFont(v) self.Font=v end
    function methods:SetAutoWrapText(v) self.AutoWrapText=v end
    function methods:SetTextOverflowPolicy(v) self.TextOverflowPolicy=v end
    function methods:SetJustification(v) self.justification=v end
    function methods:SetHorizontalAlignment(v) self.horizontalAlignment=v end
    function methods:SetVerticalAlignment(v) self.verticalAlignment=v end
    function methods:SetColorAndOpacity(v) self.ColorAndOpacity=v end
    function methods:SetForegroundColor(v) self.foreground=v end
    function methods:SetBackgroundColor(v) self.background=v end
    function methods:SetPercent(v) self.percent=v end
    function methods:SetFillColorAndOpacity(v) self.fill=v end
    function methods:SetPosition(v) self.position=v end
    function methods:SetSize(v) self.size=v end
    function methods:SetPadding(v) self.padding=v end
    function methods:SetRenderTransformPivot(v) self.pivot=v end
    function methods:SetRenderTransformAngle(v) self.angle=v end
    function methods:SetDesiredSizeInViewport(v) self.desired=v end
    function methods:SetPositionInViewport(v) self.position=v end
    function methods:SetScrollOffset(v) self.scrollOffset=v end
    function methods:SetUserFocus(pc) self.focusController=pc end
    function methods:SetIgnoreLookInput(value) self.lookIgnores=math.max(0,(self.lookIgnores or 0)+(value and 1 or -1)) end
    function methods:AddToViewport() self.onScreen=true end
    function methods:RemoveFromParent() self.onScreen=false;if self.parent then self.parent:RemoveChild(self) end end
    function e.object(kind)
        e.serial=e.serial+1
        local o=setmetatable({address=e.serial,name=(kind or 'Object')..' Test_'..e.serial,kind=kind,Visibility=0,enabled=true,
            children={},Font={Size=18},ColorAndOpacity={SpecifiedColor={}},WidgetStyle={TextStyle={Font={}},BackgroundColor={SpecifiedColor={}}}}, {
                __index=methods,
                __newindex=function(object,key,value)
                    assert(not (kind=='/Script/UMG.TextBlock' and key=='OverflowPolicy'),
                        'UTextBlock has TextOverflowPolicy, not OverflowPolicy')
                    rawset(object,key,value)
                end,
            })
        o.OnClicked={bindings={}}
        function o.OnClicked:Add(target,name)
            assert(type(target)=='table' and type(name)=='string','native delegate requires UObject + function name')
            self.bindings[#self.bindings+1]={target=target,name=name}
        end
        function o.OnClicked:Remove(target,name)
            for i=#self.bindings,1,-1 do if self.bindings[i].target==target and self.bindings[i].name==name then table.remove(self.bindings,i) end end
        end
        return o
    end
    function methods:AddChild(child)
        child.parent=self;self.children[#self.children+1]=child
        child.Slot=e.object('Slot');return child.Slot
    end
    methods.AddChildToCanvas=methods.AddChild
    function methods:RemoveChild(child)
        for i,v in ipairs(self.children) do if v==child then table.remove(self.children,i);child.parent=nil;return true end end
    end
    function methods:Create(_,class,pc)
        local o=e.object(class.path);o.controller=pc;o.WidgetTree=e.object('WidgetTree');o.WidgetTree.RootWidget=e.object('OriginalRoot')
        if class.path:find('UI_Joker_Informations',1,true) then e.hosts[#e.hosts+1]=o end
        return o
    end
    function methods:SetInputMode_GameAndUIEx(pc,focus,lock,hide,flush)
        assert(lock==0 and hide==false and flush==false)
        e.modes[#e.modes+1]={mode='gameAndUI',controller=pc};focus.focusController=pc
    end
    function methods:SetInputMode_GameOnly(pc,flush)
        assert(flush==false);e.modes[#e.modes+1]={mode='gameOnly',controller=pc}
    end
    function methods:SetFocusToGameViewport() e.modes[#e.modes+1]={mode='viewportFocus'} end
    _G.StaticFindObject=function(path) if not e.objects[path] then local o=e.object('Class');o.path=path;e.objects[path]=o end;return e.objects[path] end
    _G.StaticConstructObject=function(class,outer) e.constructed=e.constructed+1;local o=e.object(class.path);o.outer=outer;return o end
    _G.FText=function(v) return v end
    _G.RegisterHook=function(path,fn) e.hooks[path]=e.hooks[path] or {};local n=#e.hooks[path]+1;e.hooks[path][n]=fn;return n,n end
    _G.UnregisterHook=function(path,pre) e.hooks[path][pre]=false end
    _G.ModRef={SetSharedVariable=function(_,k,v) e.shared[k]=v end,GetSharedVariable=function(_,k) return e.shared[k] end}
    _G.LoadAsset=function(path) return StaticFindObject(path) end
    function e.invoke(target,name)
        local path='/Game/Interfaces/UI_Template_Button.UI_Template_Button_C:'..name
        for _,fn in ipairs(e.hooks[path] or {}) do if fn then fn({get=function() return target end}) end end
    end
    function e.click(button)
        local bindings={};for _,v in ipairs(button.OnClicked.bindings) do bindings[#bindings+1]=v end
        for _,v in ipairs(bindings) do e.invoke(v.target,v.name) end
    end
    function e.newController(cursor)
        local pc=e.object('PlayerController');pc.bShowMouseCursor=cursor==true;pc.world=e.object('World')
        pc.Pawn=e.object('Pawn');pc.Pawn.refBpMenu=e.object('BP_Manager_Menu')
        local menu=pc.Pawn.refBpMenu;menu.isUiMode=false;menu.isAnySpecialMenuOpened=false;menu.isMenuOpened=false
        menu.ref_Chat=e.object('Chat');menu.ref_Chat.chatOpen=false
        e.controller=pc;return pc
    end
    -- BP_Manager_Menu ReceiveTick -> graph @13199..13419 -> delay -> @1757:
    -- the native game recenters the cursor unless one of its UI flags is set.
    function e.nativeRecentersMouse(pc)
        local m=(pc or e.controller).Pawn.refBpMenu
        return not (m.isUiMode or m.isAnySpecialMenuOpened or m.isMenuOpened or m.ref_Chat.chatOpen)
    end
    e.newController(false)
    function e.restore() for _,name in ipairs(names) do _G[name]=saved[name] end end
    return e
end
return E
