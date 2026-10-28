-- Shared native Canvas renderer. Per-mod copy; no frame hook or timer.
local Canvas={}
local Renderer={};Renderer.__index=Renderer
local function valid(object)
    local ok,value=pcall(function() return object and object:IsValid() end);return ok and value==true
end
local function identity(object)
    if not valid(object) then return nil end
    local ok,key=pcall(function() return object:GetFullName()..'@'..tostring(object:GetAddress()) end)
    return ok and key or nil
end
local function world(object)
    local ok,value=pcall(function() return object:GetWorld() end)
    return ok and identity(value) or nil
end
local function tint(hex, alpha)
    local function linear(byte)
        local value=tonumber(byte,16)/255
        return value<=.04045 and value/12.92 or ((value+.055)/1.055)^2.4
    end
    -- Slate consumes linear FLinearColor; palette/player hex values are sRGB.
    return {R=linear(hex:sub(2,3)),G=linear(hex:sub(4,5)),B=linear(hex:sub(6,7)),A=alpha or 1}
end
local requiredFunctions = {
    "/Script/UMG.Widget:RemoveFromParent", "/Script/UMG.Widget:SetRenderTransformAngle", "/Script/UMG.Widget:SetRenderTransformPivot",
    "/Script/UMG.CanvasPanel:AddChildToCanvas", "/Script/UMG.CanvasPanelSlot:SetPosition", "/Script/UMG.CanvasPanelSlot:SetSize",
    "/Script/UMG.TextBlock:SetText", "/Script/UMG.TextBlock:SetFont", "/Script/UMG.TextBlock:SetColorAndOpacity",
    "/Script/UMG.ProgressBar:SetPercent", "/Script/UMG.ProgressBar:SetFillColorAndOpacity",
}
local function asset(path)
    local object=StaticFindObject(path)
    if not valid(object) then LoadAsset(path);object=StaticFindObject(path) end
    assert(valid(object),'panel asset unavailable: '..path)
    return object
end
function Canvas.new(options)
    assert(options and options.getController, "getController must return the verified local player controller")
    return setmetatable({options = options, textPool = {}, barPool = {}, attached = false}, Renderer)
end
function Renderer:_create(controller)
    for _, path in ipairs(requiredFunctions) do assert(valid(StaticFindObject(path)), "missing UMG binding " .. path) end
    controller = controller or self.options.getController()
    assert(valid(controller), "local controller unavailable")
    local hostClass = asset("/Game/Interfaces/UI_Joker_Informations.UI_Joker_Informations_C")
    local font = asset("/Game/Materials/Fonts/Font_Text.Font_Text")
    local library = StaticFindObject("/Script/UMG.WidgetBlueprintLibrary"):GetCDO()
    local host = library:Create(controller, hostClass, controller)
    assert(valid(host), "independent panel host creation failed")
    host.bHasScriptImplementedPaint, host.bIsFocusable = false, not self.options.passive
    if self.options.passive then host.bHasScriptImplementedTick=false end
    local tree = host.WidgetTree
    local inheritedVisibility = tree.RootWidget.Visibility
    local root = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree)
    assert(valid(root), "panel CanvasPanel creation failed")
    root.Visibility, tree.RootWidget = inheritedVisibility, root
    root:SetVisibility(self.options.passive and 3 or 4);host:SetVisibility(2)
    self.host, self.root, self.tree, self.controller = host, root, tree, controller
    self.controllerKey,self.worldKey=identity(controller),world(controller)
    self.font = font
    self.textClass, self.barClass = StaticFindObject("/Script/UMG.TextBlock"), StaticFindObject("/Script/UMG.ProgressBar")
    if not self.options.passive then
        self.mouse=require('MousePanel').new({host=host,root=root,tree=tree,font=self.font,controller=controller,library=library,
            getController=self.options.getController,onAction=self.options.onAction})
    end
    self.textPool, self.barPool, self.inputs, self.scrolls, self.attached = {}, {}, {}, {}, false
end
function Renderer:_node(pool, index, class)
    local item = pool[index]
    if not item or not valid(item.widget) then
        local widget = StaticConstructObject(class, self.tree)
        assert(valid(widget), "UMG primitive creation failed")
        widget:SetVisibility(3)
        item = {widget = widget}; pool[index] = item
    end
    if not item.attached then item.slot, item.attached = self.root:AddChildToCanvas(item.widget), true end
    return item
end
function Renderer:_isCurrent(controller)
    return valid(controller) and self.worldKey~=nil and identity(controller)==self.controllerKey and world(controller)==self.worldKey
end
function Renderer:_discard(abandon)
    local mouse,host,attached=self.mouse,self.host,self.attached
    self.mouse,self.host,self.root,self.tree,self.controller=nil,nil,nil,nil,nil
    self.controllerKey,self.worldKey,self.lastModel,self.lastScene,self.lastViewportKey=nil,nil,nil,nil,nil
    self.textPool,self.barPool,self.inputs,self.scrolls,self.attached={},{},{},{},false
    if mouse then pcall(function() mouse:dispose(abandon) end) end
    if not abandon then
        pcall(function() if valid(host) then host:SetVisibility(2) end end)
        pcall(function() if attached and valid(host) then host:RemoveFromParent() end end)
    end
end
function Renderer:hide(abandon)
    local ok,controller=pcall(self.options.getController)
    if abandon or (self.controller and (not ok or not self:_isCurrent(controller))) then self:_discard(true);return end
    if self.mouse then pcall(function() self.mouse:hide() end) end
    pcall(function() if valid(self.host) then self.host:SetVisibility(2) end end)
    pcall(function() if valid(self.host) and self.attached then self.host:RemoveFromParent() end end)
    self.attached, self.lastModel = false, nil
end
function Renderer:viewport(controller)
    if self.options.viewport then return self.options.viewport() end
    local class = StaticFindObject("/Script/UMG.WidgetLayoutLibrary")
    assert(valid(class), "supply viewport() when WidgetLayoutLibrary is unavailable")
    local library = class:GetCDO()
    local size = library:GetViewportSize(controller or self.controller)
    return {width = size.X, height = size.Y, dpiScale = library:GetViewportScale(controller or self.controller)}
end
function Renderer:render(model)
    if not model then self:hide(); return true end
    local controller = self.options.getController()
    if not valid(controller) then self:_discard(true); return nil, "local controller unavailable" end
    if (self.mouse and not self.mouse:isCurrent(controller)) or (self.controller and
        (identity(controller)~=self.controllerKey or world(controller)~=self.worldKey)) then
        self:_discard(true)
    end
    local viewport=self:viewport(controller)
    local function positive(v) return type(v)=='number' and v==v and v>0 and v<math.huge end
    if not viewport or not positive(viewport.width) or not positive(viewport.height) or not positive(viewport.dpiScale) then
        self:hide();return nil,'viewport size or DPI is not ready'
    end
    local viewportKey=viewport.width..'/'..viewport.height..'/'..viewport.dpiScale
    if model == self.lastModel and self.lastViewportKey==viewportKey and self.attached and valid(self.host) then return false end
    if not valid(self.host) then self:_create(controller) end
    local scene = (assert(self.options.layout, "layout required"))(model, viewport)
    scene.fitScale=math.min(1,math.max(1,viewport.width-scene.margin*2)/scene.width,
        math.max(1,viewport.height-scene.margin*2)/scene.height)
    local scale, texts, bars, buttons = scene.fitScale / scene.dpiScale, 0, 0, {}
    local inputs,scrolls={},{}
    for _, command in ipairs(scene.commands) do
        if command.kind=='input' or command.kind=='scrollText' then
            local isInput=command.kind=='input'
            local pool=isInput and self.inputs or self.scrolls
            local used=isInput and inputs or scrolls;used[command.id]=true
            local entry=pool[command.id]
            if not entry then
                local class=StaticFindObject(isInput and '/Script/UMG.EditableTextBox' or '/Script/UMG.ScrollBox')
                local widget=StaticConstructObject(class,self.tree)
                entry={widget=widget,slot=self.root:AddChildToCanvas(widget)};pool[command.id]=entry
                if isInput then
                    local font=widget.WidgetStyle.TextStyle.Font;font.FontObject=self.font;font.Size=16
                    widget.WidgetStyle.TextStyle.Font=font
                    widget.ClearKeyboardFocusOnCommit=false;widget.SelectAllTextWhenFocused=true
                    widget.WidgetStyle.BackgroundColor.SpecifiedColor=tint('#17141D')
                    widget:SetForegroundColor(tint('#F4E7CA'))
                else
                    entry.text=StaticConstructObject(self.textClass,self.tree)
                    entry.text:SetVisibility(3);entry.text:SetAutoWrapText(true);widget:AddChild(entry.text)
                end
            end
            entry.widget:SetVisibility(0)
            entry.slot:SetPosition({X=command.x*scale,Y=command.y*scale})
            entry.slot:SetSize({X=command.width*scale,Y=command.height*scale})
            if isInput then
                if entry.resetKey~=command.resetKey then entry.widget:SetText(FText(command.text or ''));entry.resetKey=command.resetKey end
                entry.widget:SetHintText(FText(command.hint or ''))
                local font=entry.widget.WidgetStyle.TextStyle.Font;font.Size=math.floor((command.size or 16)*scale+.5)
                entry.widget.WidgetStyle.TextStyle.Font=font
            else
                entry.text:SetText(FText(command.text or ''))
                local font=entry.text.Font;font.FontObject=self.font;font.Size=math.floor((command.size or 16)*scale+.5);entry.text:SetFont(font)
                local color=entry.text.ColorAndOpacity;color.SpecifiedColor=tint(command.color or '#F4E7CA');entry.text:SetColorAndOpacity(color)
                if entry.resetKey~=command.resetKey then entry.widget:SetScrollOffset(0);entry.resetKey=command.resetKey end
            end
        elseif command.kind=='button' then
            if self.mouse then
            buttons[command.id]=true
            local entry=self.mouse:button(command.id,{text=command.text,action=command.action,enabled=command.enabled,
                value=command.value,selected=command.selected,visible=command.visible,
                x=command.x*scale,y=command.y*scale,width=command.width*scale,height=command.height*scale,
                size=math.floor(command.size*scale+.5)})
            if not entry.captionAligned then
                -- AutoWrap + a centered desired-size button child can wrap at
                -- its previous narrow prepass width, even inside a wide button.
                entry.label:SetAutoWrapText(false)
                entry.label:SetJustification(1)
                entry.label.Slot:SetHorizontalAlignment(0)
                entry.label.Slot:SetVerticalAlignment(2)
                entry.label.Slot:SetPadding({Left=6,Top=0,Right=6,Bottom=0})
                entry.captionAligned=true
            end
            if command.backgroundColor then entry.button:SetBackgroundColor(tint(command.backgroundColor)) end
            if command.textColor then
                local color=entry.label.ColorAndOpacity;color.SpecifiedColor=tint(command.textColor);entry.label:SetColorAndOpacity(color)
            end
            end
        else
        local item
        if command.kind == "text" then texts = texts + 1; item = self:_node(self.textPool, texts, self.textClass)
        else bars = bars + 1; item = self:_node(self.barPool, bars, self.barClass) end
        local widget = item.widget
        item.slot:SetPosition({X = command.x * scale, Y = (command.y - (command.kind == "line" and 1 or 0)) * scale})
        item.slot:SetSize({X = command.width * scale, Y = command.height * scale})
        if command.kind == "text" then
            widget:SetText(FText(command.text))
            widget:SetAutoWrapText(command.wrap==true)
            widget:SetJustification(command.justification or 0)
            local fontInfo = widget.Font; fontInfo.FontObject = self.font; fontInfo.Size = math.floor(command.size * scale + 0.5); widget:SetFont(fontInfo)
            local slateColor = widget.ColorAndOpacity; slateColor.SpecifiedColor = tint(command.color); widget:SetColorAndOpacity(slateColor)
        else
            widget:SetPercent(command.fraction or 1); widget:SetFillColorAndOpacity(tint(command.color, command.alpha))
            widget:SetRenderTransformPivot({X = 0, Y = 0.5})
            widget:SetRenderTransformAngle(command.kind == "line" and math.deg(math.atan(command.endY - command.y, command.endX - command.x)) or 0)
        end
        end
    end
    for id,entry in pairs(self.inputs or {}) do if not inputs[id] then entry.widget:SetVisibility(2) end end
    for id,entry in pairs(self.scrolls or {}) do if not scrolls[id] then entry.widget:SetVisibility(2) end end
    if self.mouse then
        for id,entry in pairs(self.mouse.buttons) do
            if not buttons[id] then entry.visible=false;if valid(entry.host) then entry.host:SetVisibility(2) end end
        end
    end
    for _, entry in ipairs({{self.textPool, texts}, {self.barPool, bars}}) do
        for index = entry[2] + 1, #entry[1] do
            local item = entry[1][index]
            if item.attached and valid(item.widget) then item.widget:RemoveFromParent() end
            item.attached = false
        end
    end
    self.host:SetDesiredSizeInViewport({X = scene.width * scale, Y = scene.height * scale})
    self.host:SetPositionInViewport({X = scene.margin, Y = scene.margin}, true)
    if not self.attached then self.host:AddToViewport(self.options.zOrder or 9900); self.attached = true end
    self.host:SetVisibility(self.options.passive and 3 or 4)
    if self.mouse then self.mouse:show() end
    self.lastModel, self.lastScene, self.lastViewportKey = model, scene, viewportKey
    return true
end
function Renderer:input(id)
    local ok,controller=pcall(self.options.getController)
    if not ok or not self:_isCurrent(controller) then self:_discard(true);return nil end
    local entry=self.inputs and self.inputs[id]
    if not entry or not valid(entry.widget) then return nil end
    local read,value=pcall(function() return entry.widget:GetText() end)
    if not read then return nil end
    if type(value)=='string' then return value end
    local ok,text=pcall(function() return value:ToString() end)
    return ok and text or nil
end
return Canvas
