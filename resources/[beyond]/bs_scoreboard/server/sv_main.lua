-- bs_scoreboard - the three boards, read from bs_character_stats and bs_characters so there is one source of truth.
-- Cached: F9 gets mashed and three ORDER BY queries per press is wasteful. One rebuild every few seconds serves everyone, and a board a few seconds stale is still correct.

local cache = nil
local cachedAt = 0

local onlineCache = nil
local onlineCachedAt = 0
-- The online list is cached for 1 second: it is rebuilt (GetPlayer/GetPlayerPing per player, then a sort) once per second instead of on every scoreboard:get, since F9 gets mashed.
local ONLINE_CACHE_MS = 1000


local function now() return GetGameTimer() end

-- Everybody currently connected, with what they are doing.
-- VIP tier for a connected player, or nil. Wrapped because bs_vip is optional; the scoreboard must still build a list without it.
local function vipTier(src)
    if GetResourceState('bs_vip') ~= 'started' then return nil end
    -- GetTierInfo, not GetTier: GetTier returns only the id string and the scoreboard also needs the label and color.
    local ok, tier = pcall(function() return exports.bs_vip:GetTierInfo(src) end)
    if not ok or type(tier) ~= 'table' then return nil end
    return tier.id, tier.label, tier.colour, tier.banner
end

local function online()
    local out = {}

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = exports.bs_core:GetPlayer(src)

        if player then
            -- VIP is shown with the name highlighted. The color travels with the row so the page does not keep its own tier -> color table that could drift from bs_vip's.
            local tierId, tierLabel, tierColour, tierBanner = vipTier(src)

            local faction = GetResourceState('bs_factions') == 'started' and exports.bs_factions:GetFactionSummary(src) or nil
            out[#out + 1] = {
                id     = src,
                name   = ('%s %s'):format(player.firstName or '', player.lastName or ''),
                class  = player.class and player.class.label or player.className or '',
                level  = player.level or 1,
                ping   = GetPlayerPing(playerId),
                factionTag = faction and faction.short or nil,

                vip      = tierId,
                vipLabel = tierLabel,
                vipColour = tierColour,
                -- F9 banner choice (bs_vip profileBanner). Hook only, not drawn yet.
                vipBanner = tierBanner,
            }
        else
            -- Connected but still on the character screen. Shown anyway, since an empty slot is more confusing.
            out[#out + 1] = {
                id = src, name = GetPlayerName(playerId),
                class = 'choosing a survivor', level = 0,
                ping = GetPlayerPing(playerId),
            }
        end
    end

    table.sort(out, function(a, b) return (a.level or 0) > (b.level or 0) end)
    return out
end

-- One board. The column comes from the config, never from the client.
local function board(entry)
    local limit = math.max(1, math.min(25, Scoreboard.Settings.top or 10))

    -- xp lives on the character, everything else on the stats row. Two shapes, one function.
    local sql
    if entry.column == 'xp' then
        sql = ([[
            SELECT c.`first_name`, c.`last_name`, c.`level`, c.`xp` AS `value`
            FROM `bs_characters` c
            WHERE c.`deleted_at` IS NULL
            ORDER BY c.`xp` DESC
            LIMIT %d
        ]]):format(limit * 3)
    else
        sql = ([[
            SELECT c.`first_name`, c.`last_name`, c.`level`, s.`%s` AS `value`
            FROM `bs_character_stats` s
            JOIN `bs_characters` c ON c.`id` = s.`character_id`
            WHERE c.`deleted_at` IS NULL AND s.`%s` > 0
            ORDER BY s.`%s` DESC
            LIMIT %d
        ]]):format(entry.column, entry.column, entry.column, limit * 3)
    end

    local rows = exports.oxmysql:query_async(sql) or {}

    local out = {}
    -- Rows are per character; two characters with the same name would look like one person listed twice, so only the best is kept (rows come sorted).
    local seen = {}
    for _, row in ipairs(rows) do
        local name = ('%s %s'):format(row.first_name or '', row.last_name or '')
        local key = name:lower()
        if not seen[key] and #out < limit then
        seen[key] = true
        out[#out + 1] = {
            rank  = #out + 1,
            name  = name,
            level = row.level or 1,
            value = math.floor(tonumber(row.value) or 0),
        }
        end
    end

    return { id = entry.id, label = entry.label, suffix = entry.suffix, rows = out }
end

local factionCache, factionAt = {}, -60000
local function factions()
    if now() - factionAt < 60000 then return factionCache end
    factionAt = now()
    if GetResourceState('bs_factions') ~= 'started' then factionCache = {} return factionCache end
    local ok, list = pcall(function() return exports.bs_factions:GetTopFactions(Scoreboard.Settings.top or 10) end)
    factionCache = ok and type(list) == 'table' and list or {}
    return factionCache
end

local function build()
    local boards = {}
    for _, entry in ipairs(Scoreboard.Boards) do
        boards[#boards + 1] = board(entry)
    end
    return boards
end


BSB.RegisterCallback('scoreboard:get', function()
    if not cache or (now() - cachedAt) > (Scoreboard.Settings.cacheMs or 5000) then
        cache = build()
        cachedAt = now()
    end

    -- The online list is cached for ONLINE_CACHE_MS (see onlineCache above). Still effectively live.
    if not onlineCache or (now() - onlineCachedAt) > ONLINE_CACHE_MS then
        onlineCache = online()
        onlineCachedAt = now()
    end

    return {
        ok      = true,
        boards  = cache,
        players = onlineCache,
        factions = factions(),
        count   = #GetPlayers(),
        max     = GetConvarInt('sv_maxclients', 32),
        title    = Scoreboard.Settings.title,
        subtitle = Scoreboard.Settings.subtitle,
    }
end)

exports.bs_core:RegisterModule('scoreboard', { side = 'server', version = '1.0.0', ready = true })


