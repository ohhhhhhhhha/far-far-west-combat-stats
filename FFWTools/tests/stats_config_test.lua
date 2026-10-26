package.path='FFWTools/src/FFWStats/Scripts/?.lua;'..package.path
local T=dofile('FFWTools/tests/stats_testlib.lua')
local path='FFWTools/tests/config-epoch.txt'
local function config() return require('Config') end
local function remove() os.remove(path);os.remove(path..'.tmp');os.remove(path..'.bak') end
T.test('save paths follow the actual mod script location including spaces',function()
    local paths=config().paths('@D:\\Other Steam\\FarFarWest\\ue4ss\\Mods\\FFWStats\\Scripts\\main.lua')
    T.eq(paths.save,'D:/Other Steam/FarFarWest/ue4ss/Mods/FFWStats/Data/last-mission.json')
    T.eq(paths.epoch,'D:/Other Steam/FarFarWest/ue4ss/Mods/FFWStats/Data/boot-epoch.txt')
end)
T.test('boots in the same second persist distinct epochs and recover the previous replacement',function()
    remove()
    T.eq(assert(config().nextEpoch(path,1000)),1000)
    T.eq(assert(config().nextEpoch(path,1000)),1001)
    assert(os.rename(path,path..'.bak'))
    T.eq(assert(config().nextEpoch(path,900)),1002)
    local file=assert(io.open(path,'rb'));T.eq(tonumber(file:read('a')),1002);file:close()
end)
T.test('an unwritable epoch location never returns an uncommitted epoch',function()
    local value,err=config().nextEpoch('FFWTools/tests/no-such-epoch-directory/boot.txt',1000)
    T.eq(value,nil);T.eq(type(err),'string')
end)
remove()
T.finish()
