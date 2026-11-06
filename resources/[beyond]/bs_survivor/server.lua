local cache = {}

BSB.RegisterCallback('survivor:snapshot', function(src)
    local summary = exports.bs_core:GetPlayerSummary(src)
    if not summary then return { ok = false, error = 'No active character' } end
    local stored = cache[src]
    if stored and stored.character == summary.charId and os.time() - stored.at < 4 then return stored.result end

    local skills
    if GetResourceState('bs_skills') == 'started' then
        local ok, result = pcall(function() return exports.bs_skills:GetSkills(src) end)
        if ok then skills = result end
    end
    -- Only counters with active writers in the framework are presented.
    local ok, rows = pcall(function()
        return exports.oxmysql:query_async(
            'SELECT zombie_kills, deaths, items_crafted FROM bs_character_stats WHERE character_id = ? LIMIT 1',
            { summary.charId })
    end)
    local record = ok and rows and (rows[1] or { zombie_kills = 0, deaths = 0, items_crafted = 0 }) or nil
    local result = { ok = true, character = {
        name = summary.name, class = summary.class, level = summary.level,
        xp = summary.xp, xpToNext = summary.xpToNext, maxLevel = summary.maxLevel,
        skillPoints = summary.skillPoints, playtime = summary.playtime,
        stats = summary.stats,
    }, skills = skills, record = record }
    cache[src] = { character = summary.charId, at = os.time(), result = result }
    return result
end)

AddEventHandler('playerDropped', function() cache[source] = nil end)
AddEventHandler('bs:hook:player:unloaded', function(player)
    if player then cache[player.source] = nil end
end)
