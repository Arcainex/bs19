-- bs_factions - reputation lives here and only the server decides it. Other resources call exports.bs_factions:AddReputation(src, amount, reason); there is no client event to set reputation.
-- Unlocks are permanent once earned (bs_faction_unlocks), independent of current membership (bs_faction_members).
-- Join/leave has one implementation each (doJoin/doLeave), used by both the BSB callback and the chat commands.

local state      = {}   -- [src] = { charId, factionId, reputation, joinedAt }
local byCharId    = {}   -- [charId] = state[src], same table, second index
local unlocked    = {}   -- [charId] = { [unlockId] = true }

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function notify(src, kind, message)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = message, duration = 3400 })
end

local function bankReputation(charId, factionId, reputation)
    if not factionId then return end
    exports.oxmysql:execute_async([[
        INSERT INTO `bs_faction_reputation` (`character_id`, `faction_id`, `reputation`)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE `reputation` = VALUES(`reputation`)
    ]], { charId, factionId, reputation })
end

--------------------------------------------------------------------------------
-- Loading / unloading, driven by bs_core's cross-resource hooks
--------------------------------------------------------------------------------

local function loadUnlocks(charId)
    local rows = exports.oxmysql:query_async(
        'SELECT `unlock_id` FROM `bs_faction_unlocks` WHERE `character_id` = ?', { charId }) or {}
    local set = {}
    for _, row in ipairs(rows) do set[row.unlock_id] = true end
    unlocked[charId] = set
end

local function pushSync(src)
    local s = state[src]
    if not s then return end

    local faction = s.factionId and Factions.Get(s.factionId) or nil
    TriggerClientEvent('bs:factions:sync', src, {
        factionId  = s.factionId,
        label      = faction and faction.label or nil,
        short      = faction and faction.short or nil,
        colour     = faction and faction.colour or nil,
        reputation = s.reputation or 0,
        rank       = FactionRankOf and FactionRankOf(s.charId, s.factionId) or nil,
        unlocks    = unlocked[s.charId] or {},
    })
end

local function loadPlayer(player)
    -- `player` crossed a resource boundary, so only plain fields survived. Never expect methods on a hook payload.
    if type(player) ~= 'table' or not player.source or not player.charId then return end

    local src, charId = tonumber(player.source), tonumber(player.charId)
    if not src or not charId then return end

    local memberRow = exports.oxmysql:query_async(
        'SELECT `faction_id`, `joined_at` FROM `bs_faction_members` WHERE `character_id` = ? LIMIT 1',
        { charId })
    memberRow = memberRow and memberRow[1] or nil

    local reputation = 0
    if memberRow then
        local repRow = exports.oxmysql:query_async(
            'SELECT `reputation` FROM `bs_faction_reputation` WHERE `character_id` = ? AND `faction_id` = ? LIMIT 1',
            { charId, memberRow.faction_id })
        repRow = repRow and repRow[1] or nil
        reputation = repRow and tonumber(repRow.reputation) or 0
    end

    loadUnlocks(charId)

    local entry = {
        src        = src,   -- so unloaded/disconnect handlers can drop it in O(1)
        charId     = charId,
        factionId  = memberRow and memberRow.faction_id or nil,
        reputation = reputation,
        joinedAt   = memberRow and memberRow.joined_at or nil,
    }

    state[src] = entry
    byCharId[charId] = entry

    pushSync(src)
end

-- Available to sv_squads: creation may be requested right after a resource restart, before a new player-loaded hook fires.
FactionLoadPlayer = loadPlayer
AddEventHandler('bs:hook:player:loaded', loadPlayer)

CreateThread(function()
    Wait(750)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local player = src and exports.bs_core:GetPlayer(src)
        if player and player.charId then loadPlayer(player) end
    end
end)

local function dropPlayer(src, entry)
    if not entry then return end
    bankReputation(entry.charId, entry.factionId, entry.reputation)
    if state[src] == entry then state[src] = nil end
    byCharId[entry.charId] = nil
    unlocked[entry.charId] = nil
end

-- entry.src (set at load) is used directly instead of scanning every online player's state, so mass disconnects stay cheap.
AddEventHandler('bs:hook:player:unloaded', function(player)
    if type(player) ~= 'table' or not player.charId then return end
    local charId = tonumber(player.charId)
    local entry = charId and byCharId[charId]
    if not entry then return end

    dropPlayer(entry.src, entry)
end)

-- Safety net: a disconnect that skips the framework's unload (crash, timeout) should not leave a stale row.
AddEventHandler('playerDropped', function()
    dropPlayer(source, state[source])
end)

--------------------------------------------------------------------------------
-- Unlock resolution
--------------------------------------------------------------------------------

-- Checks the faction's unlock list against current reputation and grants newly earned ones. Runs after every reputation gain.
local function resolveUnlocks(src)
    local s = state[src]
    if not s or not s.factionId then return end

    local faction = Factions.Get(s.factionId)
    if not faction then return end

    local have = unlocked[s.charId] or {}
    unlocked[s.charId] = have

    for _, unlock in ipairs(faction.unlocks) do
        if not have[unlock.id] and s.reputation >= unlock.rep then
            have[unlock.id] = true

            exports.oxmysql:execute_async([[
                INSERT IGNORE INTO `bs_faction_unlocks` (`character_id`, `faction_id`, `unlock_id`)
                VALUES (?, ?, ?)
            ]], { s.charId, s.factionId, unlock.id })

            -- Cross-resource broadcast so bs_emotes/bs_inventory/bs_ui can react without bs_factions knowing what a 'clothing' or 'emote' unlock is.
            TriggerEvent('bs:hook:faction:unlock', {
                charId = s.charId, factionId = s.factionId,
                unlockId = unlock.id, type = unlock.type, label = unlock.label,
            })

            TriggerClientEvent('bs:ui:notify', src, {
                type = 'success',
                message = ('%s reputation: unlocked "%s"'):format(faction.label, unlock.label),
                duration = 4200,
            })
        end
    end
end

--------------------------------------------------------------------------------
-- Reputation, server-authoritative only
--------------------------------------------------------------------------------

--- @return number|false  the new total, or false if there is nothing to add to
exports('AddReputation', function(src, amount, reason)
    src = tonumber(src)
    local s = src and state[src]
    if not s or not s.factionId then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    s.reputation = math.min(Factions.Settings.maxReputation, s.reputation + amount)
    resolveUnlocks(src)
    pushSync(src)

    BS.Log.debug('factions', ('%s +%d %s rep (%s)'):format(
        tostring(s.charId), amount, s.factionId, reason or 'unspecified'))
    return s.reputation
end)

exports('RemoveReputation', function(src, amount, reason)
    src = tonumber(src)
    local s = src and state[src]
    if not s or not s.factionId then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    s.reputation = math.max(0, s.reputation - amount)
    pushSync(src)
    return s.reputation
end)

-- Staff override. Sets rather than adds, and re-resolves unlocks so staff can hand out cosmetics for an event.
exports('SetReputation', function(src, amount)
    src = tonumber(src)
    local s = src and state[src]
    if not s or not s.factionId then return false end

    s.reputation = math.max(0, math.min(Factions.Settings.maxReputation, math.floor(tonumber(amount) or 0)))
    resolveUnlocks(src)
    pushSync(src)
    return s.reputation
end)

-- Automatic reputation from gameplay
-- bs_core's BS.AwardAction fires 'bs:hook:player:action' (player, actionId, reward) for every rewarded action. Listening to it and looking the action up in Factions.ActionRewards is the whole integration.

AddEventHandler('bs:hook:player:action', function(player, actionId)
    if type(player) ~= 'table' or not player.source then return end

    local mapping = Factions.ActionRewards[actionId]
    if not mapping then return end

    local src = tonumber(player.source)
    local s = src and state[src]
    if not s or not s.factionId then return end
    if mapping.faction and s.factionId ~= mapping.faction then return end

    exports.bs_factions:AddReputation(src, mapping.rep, actionId)
end)

--------------------------------------------------------------------------------
-- Plain-data reads, the same shape as bs_core's GetPlayerSummary
--------------------------------------------------------------------------------

exports('GetFaction', function(src)
    local s = state[tonumber(src)]
    return s and s.factionId or nil
end)

-- The highest-reputation title the player currently has unlocked, or nil.
exports('GetTitle', function(src)
    local s = state[tonumber(src)]
    if not s or not s.factionId then return nil end

    local faction = Factions.Get(s.factionId)
    if not faction then return nil end

    local have = unlocked[s.charId] or {}
    local best = nil
    for _, unlock in ipairs(faction.unlocks) do
        if unlock.type == 'title' and have[unlock.id] then best = unlock.label end
    end
    return best
end)

exports('GetFactionSummary', function(src)
    src = tonumber(src)
    local s = state[src]
    if not s then return nil end

    local faction = s.factionId and Factions.Get(s.factionId) or nil
    return {
        factionId  = s.factionId,
        label      = faction and faction.label or nil,
        reputation = s.reputation or 0,
        title      = exports.bs_factions:GetTitle(src),
    }
end)

exports('HasUnlock', function(src, unlockId)
    local s = state[tonumber(src)]
    if not s then return false end
    local have = unlocked[s.charId]
    return have ~= nil and have[unlockId] == true
end)

exports('ListUnlocks', function(src)
    local s = state[tonumber(src)]
    if not s then return {} end
    local out = {}
    for id, got in pairs(unlocked[s.charId] or {}) do
        if got then out[#out + 1] = id end
    end
    return out
end)

-- Joining / leaving: one implementation, used by the BSB callback and the chat commands.

local function doJoin(src, factionId)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = Lp(src, 'fac.no_character_loaded') } end

    local s = state[src]
    -- A faction resource restart can happen after the character-loaded hook, so hydrate on demand.
    if not s then
        loadPlayer(player)
        s = state[src]
    end
    if not s then return { ok = false, error = Lp(src, 'fac.character_data_is_still_unavailable') } end
    if not Factions.IsValid(factionId) then return { ok = false, error = Lp(src, 'fac.no_such_faction') } end

    if s.factionId == factionId then
        return { ok = false, error = Lp(src, 'fac.already_with', { name = Factions.Get(factionId).label }) }
    end


    -- Bank reputation of the faction being left before switching; it is kept, just not live.
    bankReputation(s.charId, s.factionId, s.reputation)

    -- Resume reputation with a faction rejoined later instead of starting at zero.
    local resumeRow = exports.oxmysql:query_async(
        'SELECT `reputation` FROM `bs_faction_reputation` WHERE `character_id` = ? AND `faction_id` = ? LIMIT 1',
        { s.charId, factionId })
    resumeRow = resumeRow and resumeRow[1] or nil

    local nextReputation = resumeRow and tonumber(resumeRow.reputation) or 0
    local written, affected = pcall(function()
        return exports.oxmysql:execute_async([[
            INSERT INTO `bs_faction_members` (`character_id`, `faction_id`, `joined_at`)
            VALUES (?, ?, NOW())
            ON DUPLICATE KEY UPDATE `faction_id` = VALUES(`faction_id`), `joined_at` = NOW()
        ]], { s.charId, factionId })
    end)
    if not written or (tonumber(affected) or 0) < 1 then
        print(('^1[BeyondSurvival]^7 (factions) membership write failed for %s: %s')
            :format(tostring(s.charId), tostring(affected)))
        return { ok = false, error = Lp(src, 'fac.faction_membership_could_not_be_save') }
    end

    s.factionId  = factionId
    s.reputation = nextReputation

    resolveUnlocks(src)
    pushSync(src)

    return { ok = true, factionId = factionId, label = Factions.Get(factionId).label }
end

local function doLeave(src)
    local s = state[src]
    if not s or not s.factionId then return { ok = false, error = Lp(src, 'fac.not_in_a_faction') } end

    bankReputation(s.charId, s.factionId, s.reputation)
    exports.oxmysql:execute_async('DELETE FROM `bs_faction_members` WHERE `character_id` = ?', { s.charId })

    local left = Factions.Get(s.factionId).label
    s.factionId  = nil
    s.reputation = 0

    pushSync(src)
    return { ok = true, left = left }
end

-- Exposed to sv_squads.lua, which owns the rules for who may join.
-- sv_squads is a separate chunk and cannot see doJoin/doLeave/state, so this file keeps the join mechanics (banking, resume, unlocks).
-- FactionJoinGuard is a global hook: sv_squads installs it, joins it refuses are blocked. nil means no rules installed yet.
FactionDoJoin  = function(src, factionId, bypass)
    if FactionJoinGuard and not bypass then
        local allowed, why = FactionJoinGuard(src, factionId)
        if not allowed then return { ok = false, error = why or Lp(src, 'fac.cant_join') } end
    end
    return doJoin(src, factionId)
end

FactionDoLeave = function(src) return doLeave(src) end

FactionStateOf = function(src) return state[src] end

BSB.RegisterCallback('factions:join', function(src, factionId)
    return FactionDoJoin(src, tostring(factionId or ''):lower())
end)

BSB.RegisterCallback('factions:leave', function(src)
    return doLeave(src)
end)

BSB.RegisterCallback('factions:status', function(src)
    local s = state[src]
    if not s then return { ok = false } end

    local faction = s.factionId and Factions.Get(s.factionId) or nil
    local next_ = nil
    if faction then
        for _, unlock in ipairs(faction.unlocks) do
            if s.reputation < unlock.rep then next_ = unlock; break end
        end
    end

    return {
        ok         = true,
        factionId  = s.factionId,
        label      = faction and faction.label or nil,
        reputation = s.reputation or 0,
        title      = exports.bs_factions:GetTitle(src),
        nextUnlock = next_,
    }
end)

--------------------------------------------------------------------------------
-- Commands - thin wrappers around doJoin/doLeave
--------------------------------------------------------------------------------

-- /joinfaction goes through the same join guard as everything else.
RegisterCommand(Factions.Settings.joinCommand, function(src, args)
    local factionId = args[1] and tostring(args[1]):lower()
    if not factionId or not Factions.IsValid(factionId) then
        return notify(src, 'info', Lp(src, 'fac.usage_join', { cmd = Factions.Settings.joinCommand, ids = table.concat(Factions.Order, '|') }))
    end

    local result = FactionDoJoin(src, factionId)
    notify(src, result.ok and 'success' or 'warn',
        result.ok and Lp(src, 'fac.joined', { name = result.label }) or result.error)
end, false)

RegisterCommand(Factions.Settings.leaveCommand, function(src)
    local result = doLeave(src)
    notify(src, result.ok and 'success' or 'info',
        result.ok and Lp(src, 'fac.left', { name = result.left }) or result.error)
end, false)

RegisterCommand(Factions.Settings.statusCommand, function(src)
    local s = state[src]
    if not s then return notify(src, 'info', Lp(src, 'fac.not_loaded')) end

    if not s.factionId then
        return notify(src, 'info', Lp(src, 'fac.not_in_join', { cmd = Factions.Settings.joinCommand }))
    end

    local faction = Factions.Get(s.factionId)
    local title = exports.bs_factions:GetTitle(src)
    notify(src, 'info', ('%s%s - %d reputation'):format(
        faction.label, title and (' (' .. title .. ')') or '', s.reputation or 0))
end, false)

RegisterCommand(Factions.Settings.listCommand, function(src)
    local lines = {}
    for _, id in ipairs(Factions.Order) do
        local f = Factions.Get(id)
        lines[#lines + 1] = ('%s (%s): %s'):format(f.label, f.id, f.blurb)
    end
    notify(src, 'info', table.concat(lines, '  |  '))
end, false)

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

RegisterCommand('setfactionrep', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local targetId = tonumber(args[1])
    local amount   = tonumber(args[2])
    local target   = targetId and state[targetId]

    if not target or not amount then
        return notify(src, 'info', Lp(src, 'fac.cmd.rep_usage'))
    end
    if not target.factionId then
        return notify(src, 'warn', Lp(src, 'fac.cmd.rep_nofaction'))
    end

    exports.bs_factions:SetReputation(targetId, amount)
    notify(src, 'success', Lp(src, 'fac.cmd.rep_set', { n = math.floor(amount) }))
end, false)

exports.bs_core:RegisterModule('factions', { side = 'server', version = '1.0.0', ready = true })
