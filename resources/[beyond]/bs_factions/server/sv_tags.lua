-- BeyondSurvival - bs_factions name tags. 'factions:tags' returns squad and faction mates anywhere

local function summaryOf(src)
    local ok, s = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
    if ok and type(s) == 'table' then return s end
    return nil
end

local function factionOf(src)
    local ok, f = pcall(function() return exports.bs_factions:GetFactionSummary(src) end)
    if ok and type(f) == 'table' and f.factionId then return f end
    return nil
end

-- sv_squad.lua. If absent or erroring, there are no squad tags.
local function squadOf(src)
    local ok, s = pcall(function() return exports.bs_factions:GetSquad(src) end)
    if ok and type(s) == 'table' and s.id then return s end
    return nil
end

local function inSafe(src)
    local st = Player(src).state
    return st and st.bsFactionSafeZone == true
end

local function rankLabel(map, rank)
    local key = tostring(rank or 'member')
    return (map and map[key]) or key:upper()
end

local function near(a, b, radius)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= radius
end

BSB.RegisterCallback('factions:tags', function(src)
    src = tonumber(src)
    local out = { ok = true, mates = {} }
    if not src then return out end
    local cfg = Factions.Tags or {}
    local mine = factionOf(src)
    local mySquad = squadOf(src)
    local meSafe = inSafe(src)
    -- the asker's own tag (client shows it only if "show my own tag" is on)
    local ms = summaryOf(src)
    if ms then
        local me = { src = src, name = ms.name or ((ms.firstName or '') .. ' ' .. (ms.lastName or '')), level = tonumber(ms.level) or 1 }
        if mySquad then me.squad = { name = mySquad.name or 'SQUAD', rank = mySquad.rankLabel or rankLabel(cfg.squadRankLabels, mySquad.rankId) } end
        if mine then me.faction = { id = mine.factionId, name = mine.label or mine.short or 'FACTION', short = mine.short, rank = mine.rankLabel and mine.rankLabel:upper() or rankLabel(cfg.rankLabels, mine.rank) } end
        out.me = me
    end
    if not mine and not mySquad and not meSafe then return out end
    local safeRadius = tonumber(cfg.safeRadius) or 160.0

    for _, v in ipairs(GetPlayers()) do
        local t = tonumber(v)
        if t and t ~= src then
            local entry = { src = t }
            local keep = false
            local f = factionOf(t)
            if mySquad then
                local sq = squadOf(t)
                if sq and sq.id == mySquad.id then
                    entry.squad = { name = sq.name or 'SQUAD', rank = sq.rankLabel or rankLabel(cfg.squadRankLabels, sq.rankId) }
                    keep = true
                end
            end
            if mine and f and f.factionId == mine.factionId then
                entry.faction = { id = f.factionId, name = f.label or f.short or 'FACTION', short = f.short, rank = f.rankLabel and f.rankLabel:upper() or rankLabel(cfg.rankLabels, f.rank) }
                keep = true
            end
            if meSafe and inSafe(t) and near(src, t, safeRadius) then
                entry.safe = true
                if f then entry.safeFaction = { id = f.factionId, name = f.label or 'FACTION', short = f.short } end
                keep = true
            end
            if keep then
                local s = summaryOf(t)
                if s then
                    entry.name = s.name or ((s.firstName or '') .. ' ' .. (s.lastName or ''))
                    entry.level = tonumber(s.level) or 1
                    out.mates[#out.mates + 1] = entry
                end
            end
        end
    end
    -- Survivor Link companions get the same tag as a player mate, keyed by -netId (no player source).
    if GetResourceState('bs_survivor_link') == 'started' and (mine or mySquad) then
        for _, v in ipairs(GetPlayers()) do
            local okL, link = pcall(function() return exports.bs_survivor_link:GetCompanion(tonumber(v)) end)
            if okL and type(link) == 'table' and link.net and link.life and link.life.status ~= 'dead' then
                local row = exports.oxmysql:single_async([[SELECT m.faction_id, m.`rank`, c.level FROM bs_characters c
                    LEFT JOIN bs_faction_members m ON m.character_id = c.id WHERE c.id = ? LIMIT 1]], { link.id })
                local entry = { src = -link.net, net = link.net, linked = true, name = link.name or '?', level = row and tonumber(row.level) or 1 }
                local keep = false
                local okS, sq = pcall(function() return exports.bs_factions:LinkedSquadOf(link.id) end)
                if mySquad and okS and sq and sq.id == mySquad.id then
                    entry.squad = { name = mySquad.name or 'SQUAD', rank = sq.rankLabel or rankLabel(cfg.squadRankLabels, sq.rankId) }
                    keep = true
                end
                if mine and row and row.faction_id == mine.factionId then
                    entry.faction = { id = mine.factionId, name = mine.label or mine.short or 'FACTION', short = mine.short, rank = rankLabel(cfg.rankLabels, row.rank) }
                    keep = true
                end
                if keep then out.mates[#out.mates + 1] = entry end
            end
        end
    end
    out.safe = meSafe
    return out
end)
