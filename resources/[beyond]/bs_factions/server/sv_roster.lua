-- bs_factions - the party HUD's data source.
-- factions:roster -> { ok, members = {...} }, online members of the caller's faction only. Loads after sv_service.lua so it replaces the older registration there. Squad data comes from sv_squad.lua exports (pcall'd, falls back to faction-only).

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
    if not myFaction then return { ok = false, error = Lp(src, 'fac.not_in_a_faction') } end
    local out = {}
    for _, v in ipairs(GetPlayers()) do
        local id = tonumber(v)
        if id and call('GetFaction', id) == myFaction then
            local row = describe(id, myFaction)
            if row then
                row.rank = row.factionRank   -- legacy field name for older menu code
                row.factionId = nil
                out[#out + 1] = row
            end
        end
    end
    local mySquad = squadOf(src)
    return { ok = true, members = out, squadId = mySquad and mySquad.id or nil, self = src }
end

BSB.RegisterCallback('factions:roster', roster)
