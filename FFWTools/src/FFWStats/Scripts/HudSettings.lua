local L,Json,Store=require('Locale'),require('Json'),require('Store')
local H={};local Settings={};Settings.__index=Settings
H.definitions={
 {'enabled','显示左上角面板','Show corner HUD',true},
 {'recentPeak','近30秒峰值 DPS','30s peak DPS',true}, {'missionPeak','本局峰值 DPS','Run peak DPS',true},
 {'incoming','累计承伤','Damage taken',true,'incomingDamage'}, {'damage','总伤害','Total damage',false,'damage'},
 {'rollingDps','当前 DPS（5秒）','Current DPS (5s)',false,'rollingDps'}, {'averageDps','本局平均 DPS','Average DPS',false,'averageDps'},
 {'hpLoss','生命损失','HP loss',false,'hpLoss'}, {'shieldAbsorbed','护盾吸收','Shield absorbed',false,'shieldAbsorbed'},
 {'kills','击杀','Kills',false,'kills',true}, {'assists','助攻','Assists',false,'assists',true},
 {'eliteKills','精英击杀','Elite kills',false,'eliteKills',true}, {'bossKills','Boss 击杀','Boss kills',false,'bossKills',true},
 {'teamHealing','队友有效治疗','Team healing',false,'teamHealing'}, {'selfHealing','自身有效治疗','Self healing',false,'selfHealing'},
 {'revives','复活队友','Revives',false,'revives',true}, {'deaths','死亡','Deaths',false,'deaths',true},
 {'shots','射击次数','Shots fired',false,'shots',true}, {'reloads','换弹次数','Reloads',false,'reloads',true},
 {'hpBreakdown','损血 / 护盾分布条','HP / shield breakdown',true}, {'ranking','团队贡献排行榜','Team contribution ranking',true},
}
local byId={};for _,d in ipairs(H.definitions) do byId[d[1]]=d end
function H.defaults() local values={};for _,d in ipairs(H.definitions) do values[d[1]]=d[4] end;return values end
local function read(path) local f=io.open(path,'rb');if not f then return nil end;local t=f:read('a');f:close();return t end
function H.new(options)
    options=options or {};local self=setmetatable({options=options,values=H.defaults(),revision=0},Settings)
    if options.enabled==false then self.values.enabled=false end
    local raw=options.path and (options.read or read)(options.path)
    if raw then
        local ok,data=pcall(Json.decode,raw)
        if ok and type(data)=='table' then for key in pairs(byId) do if type(data[key])=='boolean' then self.values[key]=data[key] end end end
    end
    return self
end
function Settings:save(nextValues)
    if self.options.path then
        local ok,err=(self.options.write or Store.writeText)(self.options.path,Json.encode(nextValues))
        if not ok then self.error=err;return false end
    end
    self.values=nextValues;self.revision=self.revision+1;self.error=nil;return true
end
function Settings:toggle(id)
    if not byId[id] then return false end
    local values={};for k,v in pairs(self.values) do values[k]=v end
    values[id]=not values[id];return self:save(values)
end
function Settings:reset() return self:save(H.defaults()) end
function Settings:model(page)
    local count=math.ceil(#H.definitions/16);page=((page or 1)-1)%count+1
    local model={rows={},page=page,pageCount=count,enabled=self.values.enabled,
        message=self.error and L.choose('设置未保存，请重试。','Settings were not saved. Try again.') or
            L.choose('点击勾选，立即保存；仅影响自己的左上角显示。','Click to toggle and save. Affects only your corner HUD.')}
    for i=(page-1)*16+1,math.min(page*16,#H.definitions) do
        local d=H.definitions[i];model.rows[#model.rows+1]={id=d[1],label=L.choose(d[2],d[3]),selected=self.values[d[1]]==true}
    end
    return model
end
return H
