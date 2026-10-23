-- BeyondSurvival - bs_factions name tags. 'factions:tags' returns squad and faction mates anywhere, plus (only while the asker is in a safe zone) other players in a safe zone within Factions.Tags.safeRadius metres.

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
        if mine then me.faction = { name = mine.label or mine.short or 'FACTION', short = mine.short, rank = mine.rankLabel and mine.rankLabel:upper() or rankLabel(cfg.rankLabels, mine.rank) } end
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
                entry.faction = { name = f.label or f.short or 'FACTION', short = f.short, rank = f.rankLabel and f.rankLabel:upper() or rankLabel(cfg.rankLabels, f.rank) }
                keep = true
            end
            if meSafe and inSafe(t) and near(src, t, safeRadius) then
                entry.safe = true
                if f then entry.safeFaction = { name = f.label or 'FACTION', short = f.short } end
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
    out.safe = meSafe
    return out
end)
