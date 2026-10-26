-- Read-only language selection and UI text. Never changes the game's culture.
local directory=assert(debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/'))
local English=assert(loadfile(directory..'/English.lua','t',_ENV))()
local cardRows=assert(loadfile(directory..'/CardText.lua','t',_ENV))()
local L={revision=0}
local active='zh'
local cards={};for id,row in pairs(cardRows) do cards[id:lower()]=row end
local defaults={['：']=': ',['；']='; ',['（']=' (',['）']=')',['、']=', ',['【']='[',['】']=']',
    ['当前']='Current ',['级']=' levels',['份']=' copies',['张']=' cards'}
local dictionary={};for key,value in pairs(defaults) do dictionary[key]=value end
for key,value in pairs(English) do dictionary[key]=value end
local trie={}
for key,value in pairs(dictionary) do
    if key~='' then
        local node=trie
        for index=1,#key do local byte=key:byte(index);node[byte]=node[byte] or {};node=node[byte] end
        node[0]=value
    end
end
function L.language() return active end
function L.setCulture(culture)
    if type(culture)~='string' or culture=='' then return false end
    local lang=culture:lower():match('^zh') and 'zh' or 'en'
    if lang==active then return false end
    active=lang;L.revision=L.revision+1;return true
end
function L.choose(zh,en) return active=='zh' and zh or en end
function L.text(value)
    local text=tostring(value or '')
    if active=='zh' then return text end
    if dictionary[text] then return dictionary[text] end
    -- Longest exact fragments cover concatenated labels/values without
    -- applying patterns to numbers, object IDs or arbitrary user strings.
    local result,index={},1
    while index<=#text do
        local node,finish,replacement=trie,nil,nil
        local cursor=index
        while node[text:byte(cursor)] do
            node=node[text:byte(cursor)];cursor=cursor+1
            if node[0] then finish=cursor;replacement=node[0] end
        end
        if finish then result[#result+1]=replacement;index=finish
        else result[#result+1]=text:sub(index,index);index=index+1 end
    end
    return table.concat(result)
end
function L.card(id,field,language)
    local row=type(id)=='string' and cards[id:lower()]
    if not row then return nil end
    local prefix=(language or active)=='zh' and 'zh' or 'en'
    return row[prefix..(field=='description' and 'Description' or 'Name')]
end
function L.matches(id,query)
    query=tostring(query or ''):match('^%s*(.-)%s*$'):lower()
    if query=='' then return true end
    for _,value in ipairs({L.card(id,'name','zh') or '',L.card(id,'name','en') or '',tostring(id or '')}) do
        if value:lower():find(query,1,true) then return true end
    end
    return false
end
local library
local function valid(o)
    local ok,value=pcall(function() return o and o:IsValid() end);return ok and value
end
function L.refresh()
    if type(StaticFindObject)~='function' then return false end
    local ok,culture=pcall(function()
        if not valid(library) then
            local class=StaticFindObject('/Script/Engine.KismetInternationalizationLibrary')
            if not valid(class) then return nil end
            library=class:GetCDO()
        end
        local value=library:GetCurrentLanguage()
        return type(value)=='string' and value or value:ToString()
    end)
    if not ok then L.lastReadError=tostring(culture);return false end
    L.lastReadError=nil
    return L.setCulture(culture)
end
return L
