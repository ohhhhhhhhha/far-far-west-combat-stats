package.path='FFWTools/src/FFWStats/Scripts/?.lua;FFWTools/tests/?.lua;'..package.path
local T=require('stats_testlib')
local loaded,C=pcall(require,'Contribution')
local function fixture()
    local keys={'damage','kills','eliteKills','bossKills','assists','teamHealing','selfHealing','shieldGranted','revives','aliveDuration'}
    local values={a={300,3,1,0,0,0,50,0,0,80},b={100,1,0,1,2,200,50,100,2,100}}
    local s={time=100,status='active',players={},playerOrder={'a','b'},state={players={a={joinedAt=0},b={joinedAt=0}}}}
    for id,list in pairs(values) do
        local p={id=id,name=id,color=id=='a' and '#56B4E9' or '#E69F00',metrics={},coverage={},connected=true}
        for i,key in ipairs(keys) do p.metrics[key]=list[i];p.coverage[key]={status='complete'} end
        s.players[id]=p
    end
    return s
end
T.test('effective support and rescue can outweigh damage using declared weights',function()
    T.eq(loaded,true,'contribution calculation available')
    local board=C.build(fixture(),{selfPlayerId='a'})
    T.eq(board.rows[1].id,'b');T.eq(board.rows[2].id,'a');T.eq(board.activeWeight,100)
    T.near(board.rows[1].score,55.77777777777778)
    T.near(board.rows[2].score,44.22222222222222)
    T.eq(board.rows[1].scoreText,'55.78');T.eq(board.rows[2].isSelf,true)
    T.near(board.rows[2].groups.output,30);T.near(board.rows[2].groups.support,1.5)
end)
T.test('taking damage and wasting resources do not farm contribution points',function()
    T.eq(loaded,true)
    local s=fixture();local before=C.build(s).rows[2].score
    for _,key in ipairs({'incomingDamage','overhealing','ammo','reloads','rollingDps','averageDps'}) do
        s.players.a.metrics[key]=999999;s.players.a.coverage[key]={status='complete'}
    end
    T.near(C.build(s).rows[2].score,before)
end)
T.test('missing inputs remain unknown and unobserved teammates are not assigned zero scores',function()
    T.eq(loaded,true)
    local s=fixture();s.players.b.coverage.teamHealing.status='unavailable'
    s.players.c={id='c',name='c',color='#009E73',metrics={aliveDuration=100},coverage={aliveDuration={status='complete'}}};s.playerOrder[3]='c'
    s.state.players.c={joinedAt=0}
    local board=C.build(s);T.eq(board.partial,true)
    local b,c
    for _,row in ipairs(board.rows) do if row.id=='b' then b=row elseif row.id=='c' then c=row end end
    T.eq(b.metrics.teamHealing.value,nil);T.eq(b.missingMetrics.teamHealing,true)
    T.eq(c.score,nil);T.eq(c.rank,nil);T.eq(c.scoreText,'—')
    T.eq(c.groups.survival,nil,'unranked players do not receive apparent zero sub-scores')
    T.eq(s.players.b.metrics.teamHealing,200,'ranking must not rewrite source totals')
end)
T.test('survival accounts for join time and equal displayed scores share a rank',function()
    T.eq(loaded,true)
    local s=fixture()
    for key,value in pairs(s.players.a.metrics) do s.players.b.metrics[key]=value end
    s.state.players.b.joinedAt=50;s.players.b.metrics.aliveDuration=40
    local board=C.build(s)
    T.near(board.rows[1].score,50);T.near(board.rows[2].score,50)
    T.eq(board.rows[1].rank,1);T.eq(board.rows[2].rank,1)
end)
T.test('stale rankings keep their recorded totals but are explicitly provisional',function()
    T.eq(loaded,true)
    local board=C.build(fixture(),{stale=true})
    T.eq(board.stale,true);T.eq(board.partial,true);T.eq(board.rows[1].partial,true)
    T.near(board.rows[1].score,55.77777777777778)
end)
T.finish()
