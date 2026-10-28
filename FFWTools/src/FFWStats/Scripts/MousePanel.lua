-- Native UMG buttons with per-instance routing, plus a cursor lease shared by
-- independently installed mods/UE4SS Lua VMs. No polling or global input hooks.
local M={}
local Panel={};Panel.__index=Panel
local template='/Game/Interfaces/UI_Template_Button.UI_Template_Button_C'
local clickName='F_ChildClick'
local clickPath=template..':'..clickName
local routes,hook={},nil
local prefix='FFWTools.MousePanel.v1.'
local function valid(o)
    local ok,value=pcall(function() return o and o:IsValid() end);return ok and value==true
end
local function identity(o)
    if not valid(o) then return nil end
    return o:GetFullName()..'@'..tostring(o:GetAddress())
end
local function world(o)
    local ok,value=pcall(function() return o:GetWorld() end)
    return ok and identity(value) or nil
end
local function field(o,key)
    local ok,value=pcall(function() return o and o[key] end)
    return ok and value or nil
end
local function menuFor(controller)
    local menu=field(field(controller,'Pawn'),'refBpMenu')
    return valid(menu) and menu or nil
end
local function nativeMenuOpen(menu)
    return valid(menu) and (field(menu,'isAnySpecialMenuOpened')==true or field(menu,'isMenuOpened')==true
        or field(field(menu,'ref_Chat'),'chatOpen')==true) or false
end
local function shared(key,value,write)
    -- ModRef is supplied by UE4SS; only primitive values cross Lua VMs. Never
    -- store transient controller/widget pointers in its shared-variable map.
    if write then ModRef:SetSharedVariable(prefix..key,value)
    else return ModRef:GetSharedVariable(prefix..key) end
end
local function color(r,g,b,a) return {R=r,G=g,B=b,A=a or 1} end
local function install()
    local class=StaticFindObject(template)
    if not valid(class) then LoadAsset(template);class=StaticFindObject(template) end
    assert(valid(class),'mouse button template unavailable')
    local fn=StaticFindObject(clickPath)
    assert(valid(fn),'mouse click function unavailable')
    local address=fn:GetAddress()
    if not hook or hook.address~=address then
        if hook then pcall(UnregisterHook,clickPath,hook.pre,hook.post) end
        -- 0.3.0.7 UI_Template_Button F_ChildClick has no parameters, is not a
        -- delegate signature, and jumps straight to return (bytecode @1728).
        -- UE4SS OnClicked:Add requires UObject + existing UFunction, not Lua.
        local pre,post=RegisterHook(clickPath,function(context)
            if not next(routes) then return end
            local object=context:get();local route=routes[identity(object)]
            if not route then return end
            local owner,entry=route.owner,route.entry
            local controller=owner.options.controller
            if owner.options.getController then
                local ok,current=pcall(owner.options.getController);controller=ok and current or nil
            end
            if owner.active and entry.visible and entry.enabled and owner:ownsInput() and owner:isCurrent(controller) then
                if owner.options.onAction then owner.options.onAction(entry.action,entry.value) end
            end
        end)
        hook={address=address,pre=pre,post=post}
    end
    return class
end
function M.new(options)
    assert(valid(options.controller) and valid(options.host),'mouse panel needs a local controller and host')
    return setmetatable({options=options,buttons={},token=identity(options.host),controllerKey=identity(options.controller),
        worldKey=world(options.controller),active=false},Panel)
end
function Panel:ownsInput() return shared('owner')==self.token end
function Panel:isCurrent(controller)
    return identity(controller)==self.controllerKey and world(controller)==self.worldKey and valid(self.options.host)
end
function Panel:button(id,spec)
    local entry=self.buttons[id]
    if not entry then
        local class=install()
        local host=self.options.library:Create(self.options.controller,class,self.options.controller)
        assert(valid(host),'mouse control host creation failed')
        host.bHasScriptImplementedPaint=false;host.bHasScriptImplementedTick=false;host.bIsFocusable=false
        host.playerHoverSound=false
        local button=StaticConstructObject(StaticFindObject('/Script/UMG.Button'),host.WidgetTree)
        local label=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),host.WidgetTree)
        assert(valid(button) and valid(label),'mouse control creation failed')
        button.IsFocusable=false
        host.WidgetTree.RootWidget=button
        label:SetVisibility(3);label:SetAutoWrapText(false);label:SetTextOverflowPolicy(1)
        local labelSlot=button:AddChild(label)
        labelSlot:SetHorizontalAlignment(0);labelSlot:SetVerticalAlignment(2)
        labelSlot:SetPadding({Left=8,Top=2,Right=8,Bottom=2})
        local slot=self.options.root:AddChildToCanvas(host)
        entry={host=host,button=button,label=label,slot=slot,routeKey=identity(host)};self.buttons[id]=entry
        routes[entry.routeKey]={owner=self,entry=entry}
        button.OnClicked:Add(host,clickName)
    end
    entry.action,entry.value=spec.action,spec.value
    entry.visible,entry.enabled=spec.visible~=false,spec.enabled~=false
    entry.slot:SetPosition({X=spec.x,Y=spec.y});entry.slot:SetSize({X=spec.width,Y=spec.height})
    entry.label:SetText(FText(spec.text or ''))
    local font=entry.label.Font;font.FontObject=self.options.font;font.Size=spec.size or 15;entry.label:SetFont(font)
    local tint=entry.label.ColorAndOpacity;tint.SpecifiedColor=color(.94,.95,.97);entry.label:SetColorAndOpacity(tint)
    entry.button:SetBackgroundColor(spec.selected and color(.32,.23,.1) or color(.08,.13,.18))
    entry.button:SetIsEnabled(entry.enabled)
    entry.host:SetVisibility(self.active and entry.visible and 4 or 2)
    return entry
end
function Panel:show(focus)
    if self.active then return end
    local controller=self.options.controller
    assert(self:isCurrent(controller),'mouse panel owner changed')
    local inherited=shared('owner') and shared('controller')==self.controllerKey
    local cursor=controller.bShowMouseCursor==true
    if inherited then cursor=shared('cursor')==true end
    self.priorCursor=cursor
    self.menu=menuFor(controller)
    self.menuKey=identity(self.menu)
    self.priorUiMode=field(self.menu,'isUiMode')==true
    if inherited and shared('menu')==self.menuKey then self.priorUiMode=shared('uiMode')==true end
    -- BP_Manager_Menu's tick recenters the mouse every 0.1s unless its own
    -- UI state is set. UE input mode/cursor visibility alone do not stop it.
    if self.menu then self.menu.isUiMode=true end
    self.ownsLook=inherited and shared('lookLock')==true
    if not self.ownsLook then controller:SetIgnoreLookInput(true);self.ownsLook=true end
    shared('menu',self.menuKey,true);shared('uiMode',self.priorUiMode,true);shared('lookLock',self.ownsLook,true)
    shared('controller',self.controllerKey,true);shared('cursor',cursor,true);shared('owner',self.token,true)
    self.active=true
    controller.bShowMouseCursor=true
    focus=focus or self.options.host
    if cursor then focus:SetUserFocus(controller)
    else self.options.library:SetInputMode_GameAndUIEx(controller,focus,0,false,false) end
    for _,entry in pairs(self.buttons) do entry.host:SetVisibility(entry.visible and 4 or 2) end
end
function Panel:hide(abandon)
    if self.active then
        self.active=false
        if self:ownsInput() then
            -- The later-opened overlay inherits the original cursor baseline.
            -- A delayed hide from the older overlay must not release its input.
            local controller,menu=self.options.controller,self.menu
            if abandon then
                controller,menu=nil,nil
                -- Seamless travel may keep the same PlayerController. Release
                -- only our input lock through a freshly resolved current owner;
                -- never recover input by dereferencing the cached old owner.
                if self.options.getController then
                    local ok,current=pcall(self.options.getController)
                    if ok and identity(current)==self.controllerKey and world(current) then
                        controller,menu=current,menuFor(current)
                    end
                end
            end
            if controller then
                local otherUi=nativeMenuOpen(menu)
                if valid(menu) and (not abandon or identity(menu)==self.menuKey) and field(menu,'isUiMode')==true then
                    pcall(function() menu.isUiMode=self.priorUiMode or otherUi end)
                end
                if valid(controller) then
                    if self.ownsLook then pcall(function() controller:SetIgnoreLookInput(false) end) end
                    pcall(function()
                        if self.priorCursor or otherUi then self.options.library:SetFocusToGameViewport()
                        else self.options.library:SetInputMode_GameOnly(controller,false) end
                    end)
                    pcall(function() controller.bShowMouseCursor=self.priorCursor or otherUi end)
                end
            end
            shared('owner',nil,true);shared('controller',nil,true);shared('cursor',nil,true)
            shared('menu',nil,true);shared('uiMode',nil,true);shared('lookLock',nil,true)
        end
    end
    if not abandon then
        for _,entry in pairs(self.buttons) do
            pcall(function() if valid(entry.host) then entry.host:SetVisibility(2) end end)
        end
    end
end
function Panel:dispose(abandon)
    self:hide(abandon)
    for _,entry in pairs(self.buttons) do
        routes[entry.routeKey]=nil
        if not abandon then
            pcall(function() if valid(entry.button) and valid(entry.host) then entry.button.OnClicked:Remove(entry.host,clickName) end end)
            pcall(function() if valid(entry.host) then entry.host:RemoveFromParent() end end)
        end
    end
    self.buttons={}
    if not next(routes) and hook then
        pcall(UnregisterHook,clickPath,hook.pre,hook.post);hook=nil
    end
end
return M
