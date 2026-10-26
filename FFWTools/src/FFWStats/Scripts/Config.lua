local Store=require('Store')
local Config={
    loopMilliseconds=250,rosterSeconds=2,viewSeconds=1,saveSeconds=5,
    hudEnabled=true,
    hotkeys={toggle='F8',previousMetric='PAGE_UP',nextMetric='PAGE_DOWN',previousScope='HOME',nextScope='END',nextPage='F10'},
    -- Runtime settlement callbacks have been observed; full attack/multiplayer
    -- coverage has not. Observed events remain partial until separately verified.
    verifiedHostMetrics={},localTracking={},
}
function Config.paths(source)
    local script=source:gsub('^@',''):gsub('\\','/')
    local scripts=assert(script:match('^(.*)/[^/]+$'),'file-backed FFWStats entry point required')
    local root=assert(scripts:match('^(.*)/[^/]+$'),'FFWStats Scripts directory required')
    return {scripts=scripts,root=root,save=root..'/Data/last-mission.json',epoch=root..'/Data/boot-epoch.txt'}
end
local function readEpoch(path)
    local file=io.open(path,'rb');if not file then return nil end
    local value=tonumber(file:read('a'));file:close()
    if not value or value<1 or value>9007199254740991 or value%1~=0 then return nil,'invalid saved boot epoch' end
    return value
end
function Config.nextEpoch(path,now)
    local prior,err=readEpoch(path)
    local backup,backupError=readEpoch(path..'.bak')
    if not prior and not backup and (err or backupError) then return nil,err or backupError end
    local nextValue=math.max(math.floor(now or os.time()),(prior or 0)+1,(backup or 0)+1,1)
    if nextValue>9007199254740991 then return nil,'boot epoch exhausted' end
    local ok,writeError=Store.writeText(path,string.format('%.0f\n',nextValue))
    if not ok then return nil,writeError end
    return nextValue
end
return Config
