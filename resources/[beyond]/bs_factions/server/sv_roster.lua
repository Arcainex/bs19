-- bs_factions - the party HUD's data source.
-- factions:roster to { ok, members = {...} }, online members of the caller's faction only. Loads after sv_service.lua so it replaces the older registration there. Squad data comes from sv_squad.lua exports (pcall'd, falls back to faction-only).

local RES = GetCurrentResourceName()

local function call(name, ...)
    local args = table.pack(...)
    local ok, r = pcall(function()
        local e = exports[RES]
        return e[name](e, table.unpack(args, 1, args.n))
    end)
    if ok then return r end
    return nil
end

local function squadOf(src)
    local s = call('GetSquad', src)
    if type(s) == 'table' then return s end
    return nil
end

local function describe(src, factionId)
    local summary = exports.bs_core:GetPlayerSummary(src)
    if not summary or not summary.charId then return nil end
    local sq = squadOf(src)
    local st = Player(src).state
    return {
        src            = src,
        charId         = tonumber(summary.charId),
        name           = summary.name or ((summary.firstName or '?') .. ' ' .. (summary.lastName or '')),
        level          = tonumber(summary.level) or 1,
        factionRank    = call('FactionRank', src) or 'member',
        rank           = nil,
        squadId        = sq and sq.id or nil,
        squadRankId    = sq and tonumber(sq.rankId) or nil,
        squadRankLabel = sq and sq.rankLabel or nil,
        downed         = st and st.bsDowned == true or false,
        factionId      = factionId,
    }
end

local function roster(src)
    src = tonumber(src)
    local myFaction = src and call('GetFaction', src)
    local mySquad = src and squadOf(src)
    local function sameSquad(sq)
        return mySquad and sq and mySquad.id ~= nil and sq.id ~= nil and tostring(mySquad.id) == tostring(sq.id)
    end
    if not myFaction and not mySquad then return { ok = false, error = Lp(src, 'fac.not_in_a_faction') } end
    local out = {}
    for _, v in ipairs(GetPlayers()) do
        local id = tonumber(v)
        if id and ((myFaction and call('GetFaction', id) == myFaction) or sameSquad(squadOf(id))) then
            local row = describe(id, myFaction)
            if row then
                row.rank = row.factionRank   -- legacy field name for older menu code
                row.factionId = nil
                out[#out + 1] = row
            end
        end
    end
    -- Squad membership is authoritative even while an owner's player list is changing.
    if GetResourceState('bs_survivor_link') == 'started' then
        local seen={}
        for _,member in ipairs(out)do if member.charId then seen[tonumber(member.charId)]=true end end
        local function appendLink(link,sq)
            local charId=type(link)=='table'and tonumber(link.id)
            if not charId or seen[charId]or not link.life or link.life.status=='dead'then return end
            local inSquad=sameSquad(sq)
            local row
            -- Faction membership needs a database check; squad membership is already known.
            if not inSquad or not tonumber(link.level)then
                local ok,value=pcall(function()
                    return exports.oxmysql:single_async('SELECT m.faction_id, m.`rank`, c.level FROM bs_characters c LEFT JOIN bs_faction_members m ON m.character_id = c.id WHERE c.id = ? LIMIT 1',{charId})
                end)
                if ok then row=value end
            end
            if not inSquad and not (row and myFaction and tostring(row.faction_id)==tostring(myFaction))then return end
            local net=tonumber(link.net)
            if net and net<=0 then net=nil end
            out[#out+1]={src=-(net or charId),net=net,linked=true,charId=charId,name=link.name or '?',
                level=tonumber(link.level)or (row and tonumber(row.level))or 1,
                factionRank=row and row.rank or 'member',rank=row and row.rank or 'member',
                squadId=sq and sq.id or nil,squadRankId=sq and tonumber(sq.rankId)or nil,squadRankLabel=sq and sq.rankLabel or nil,
                downed=link.life.status~='alive'}
            seen[charId]=true
        end
        if mySquad then
            for _,member in ipairs(call('GetSquadMembers',src)or {})do
                local ok,link=pcall(function()return exports.bs_survivor_link:GetCompanionByCharId(member.charId)end)
                if ok then appendLink(link,{id=mySquad.id,rankId=member.rankId,rankLabel=member.rankLabel})end
            end
        end
        -- Include relevant faction companions who are not in the caller's squad.
        for _,v in ipairs(GetPlayers())do
            local ok,link=pcall(function()return exports.bs_survivor_link:GetCompanion(tonumber(v))end)
            if ok and type(link)=='table'then appendLink(link,call('LinkedSquadOf',link.id))end
        end
    end
    return { ok = true, members = out, squadId = mySquad and mySquad.id or nil, self = src }
end

BSB.RegisterCallback('factions:roster', roster)
