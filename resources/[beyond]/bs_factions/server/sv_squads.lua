-- bs_factions - server side squads: factions work like SCUM squads.
-- Nobody joins a faction they did not create; you get in by creating one or by being invited by a member. The four config factions get an owner assigned by an admin.

local RANKS = { owner = 3, officer = 2, member = 1 }

-- Forward declaration: `dissolve` is defined further down but FactionsDisband needs it earlier (a local used before its declaration is a nil global lookup).
local dissolve

--- [factionId] = { id, label, short, owner, createdBy, isConfig }
local registry = {}
-- True only after the database-backed registry has loaded.
local registryReady = false

-- [targetSrc] = { factionId, by, at } - pending invitation. Kept in memory on purpose so invites do not survive a restart.
local invites = {}
local INVITE_SECONDS = 120

local function notify(src, kind, message, duration)
    TriggerClientEvent('bs:ui:notify', src, {
        type = kind, message = message, duration = duration or 3200,
    })
end

local function charIdOf(src)
    local player = exports.bs_core:GetPlayer(src)
    return player and player.charId or nil
end

-- Resource restarts do not replay a player-loaded hook for every survivor. Every faction action calls this before reading membership, so the first click after a restart works instead of showing a false "not loaded" error.
local function ensurePlayerState(src)
    local current = FactionStateOf and FactionStateOf(src)
    if current then return current end

    local player = exports.bs_core:GetPlayer(src)
    if player and player.charId and FactionLoadPlayer then
        FactionLoadPlayer(player)
    end
    return FactionStateOf and FactionStateOf(src) or nil
end
local function nameOf(src)
    local player = exports.bs_core:GetPlayer(src)
    if player and player.character then
        return player.character.firstname and
            (player.character.firstname .. ' ' .. (player.character.lastname or ''))
            or GetPlayerName(src)
    end
    return GetPlayerName(src) or ('player ' .. tostring(src))
end

--------------------------------------------------------------------------------
-- The register
--------------------------------------------------------------------------------

-- Player factions are put into Factions.List at runtime with the same shape as config ones (empty unlock ladder), so joining, reputation, status and client sync work on them unchanged.
local function publish(row)
    registry[row.faction_id] = {
        id = row.faction_id,
        label = row.label,
        short = row.short,
        owner = row.owner_character_id and tonumber(row.owner_character_id) or nil,
        createdBy = row.created_by and tonumber(row.created_by) or nil,
        isConfig = row.is_config == true or tonumber(row.is_config) == 1,
    }

    if not Factions.List[row.faction_id] then
        Factions.List[row.faction_id] = {
            id = row.faction_id,
            label = row.label,
            short = row.short,
            colour = { r = 150, g = 150, b = 150 },
            blurb = 'A faction somebody started.',
            unlocks = {},
            playerMade = true,
        }
        Factions.Order[#Factions.Order + 1] = row.faction_id
    end
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(500) end
    Wait(500)      -- let bs_core finish its migration pass

    -- Repair a legacy database whose migration history was recorded before
    -- the registry table was introduced. Safe on every later startup.
    exports.oxmysql:execute_async([[
        CREATE TABLE IF NOT EXISTS `bs_faction_registry` (
            `faction_id` VARCHAR(32) NOT NULL,
            `label` VARCHAR(48) NOT NULL,
            `short` VARCHAR(8) NOT NULL DEFAULT '',
            `owner_character_id` INT UNSIGNED NULL,
            `created_by` INT UNSIGNED NULL,
            `is_config` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`faction_id`),
            KEY `ix_bs_faction_registry_owner` (`owner_character_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})

    -- A server whose core migration history predates faction ranks must still
    -- start cleanly. Every role query depends on this column existing.
    exports.oxmysql:execute_async([[
        ALTER TABLE `bs_faction_members`
            ADD COLUMN IF NOT EXISTS `rank` VARCHAR(16) NOT NULL DEFAULT 'member' AFTER `faction_id`
    ]], {})

    -- The config factions exist in the register too, so "who owns this one"
    -- has an answer for every faction rather than only for the new kind.
    -- Move members/progress of renamed vanilla factions, drop removed ones. Safe to run every boot.
    local cols = exports.oxmysql:query_async([[
        SELECT TABLE_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'faction_id' AND TABLE_NAME LIKE 'bs\_faction\_%'
    ]], {}) or {}
    for old, new in pairs(Factions.Renamed or {}) do
        for _, c in ipairs(cols) do
            pcall(function()
                exports.oxmysql:execute_async(('UPDATE IGNORE `%s` SET `faction_id` = ? WHERE `faction_id` = ?'):format(c.TABLE_NAME), { new, old })
            end)
        end
    end
    for _, old in ipairs(Factions.Removed or {}) do
        exports.oxmysql:execute_async('DELETE FROM `bs_faction_members` WHERE `faction_id` = ?', { old })
    end
    local gone = {}
    for old in pairs(Factions.Renamed or {}) do gone[#gone + 1] = old end
    for _, old in ipairs(Factions.Removed or {}) do gone[#gone + 1] = old end
    for _, old in ipairs(gone) do
        exports.oxmysql:execute_async('DELETE FROM `bs_faction_registry` WHERE `faction_id` = ? AND `is_config` = 1', { old })
    end

    for _, id in ipairs(Factions.Order) do
        local def = Factions.List[id]
        if def then
            exports.oxmysql:execute_async([[
                INSERT IGNORE INTO `bs_faction_registry`
                    (`faction_id`, `label`, `short`, `is_config`)
                VALUES (?, ?, ?, 1)
            ]], { id, def.label, def.short or '' })
        end
    end

    -- Database startup is asynchronous, so retry the read instead of giving up if the table is not ready yet. The menu reports "starting" during a brief boot.
    local rows, lastError
    for attempt = 1, 15 do
        local loaded, result = pcall(function()
            return exports.oxmysql:query_async('SELECT * FROM `bs_faction_registry`', {})
        end)
        if loaded and type(result) == 'table' then
            rows = result
            break
        end
        lastError = result
        Wait(500)
    end
    -- On a cold server the DB can outlast the first retry window. Keep retrying instead of disabling factions for the whole session.
    while not rows do
        print(('^3[BeyondSurvival]^7 (factions) registry is still waiting for MySQL: %s')
            :format(tostring(lastError)))
        Wait(2000)
        local loaded, result = pcall(function()
            return exports.oxmysql:query_async('SELECT * FROM `bs_faction_registry`', {})
        end)
        if loaded and type(result) == 'table' then
            rows = result
        else
            lastError = result
        end
    end

    for _, row in ipairs(rows) do publish(row) end
    registryReady = true
    print(('^2[BeyondSurvival]^7 (factions) %d faction(s) registered'):format(#rows))
end)

--------------------------------------------------------------------------------
-- Rank
--------------------------------------------------------------------------------

local function rankOf(charId, factionId)
    if not charId or not factionId then return nil end

    local entry = registry[factionId]
    if entry and entry.owner == charId then return 'owner' end

    local row = exports.oxmysql:single_async([[
        SELECT `rank` FROM `bs_faction_members`
        WHERE `character_id` = ? AND `faction_id` = ? LIMIT 1
    ]], { charId, factionId })

    return row and row.rank or nil
end

-- Shared with sv_main only for client sync. The authority remains this file.
FactionRankOf = rankOf

local function setRank(charId, rank)
    exports.oxmysql:execute_async(
        'UPDATE `bs_faction_members` SET `rank` = ? WHERE `character_id` = ?',
        { rank, charId })
end

local function atLeast(rank, needed)
    return (RANKS[rank or ''] or 0) >= (RANKS[needed] or 99)
end

-- The guard. sv_main.lua calls it before every join (callback, chat command, anything added later), so "nobody joins a faction they did not create" is enforced in one place.

function FactionJoinGuard(src, factionId)
    local charId = charIdOf(src)
    if not charId then return false, Lp(src, 'fac.no_character_loaded') end

    local entry = registry[factionId]

    -- You made it. Obviously you are in it.
    if entry and (entry.owner == charId or entry.createdBy == charId) then return true end

    -- Somebody in it opened the door, recently, for you specifically.
    local invite = invites[src]
    if invite and invite.factionId == factionId
        and (os.time() - invite.at) <= INVITE_SECONDS then
        return true
    end

    return false, Lp(src, 'fac.must_be_invited')
end

--------------------------------------------------------------------------------
-- Creating one
--------------------------------------------------------------------------------

local function slug(text)
    return (tostring(text or ''):lower():gsub('[^%a%d]', '')):sub(1, 24)
end

function FactionsCreate(src, name, short)
    if not registryReady then return { ok = false, error = Lp(src, 'fac.faction_registry_is_still_starting_t') } end
    local charId = charIdOf(src)
    if not charId then return { ok = false, error = Lp(src, 'fac.no_character_loaded') } end

    -- A resource restart does not replay the core loaded event for characters already online, so hydrate the caller first.
    if not (FactionStateOf and FactionStateOf(src)) and FactionLoadPlayer then
        FactionLoadPlayer(exports.bs_core:GetPlayer(src))
    end
    local state = ensurePlayerState(src)
    if not state then return { ok = false, error = Lp(src, 'fac.your_character_is_still_loading_try') } end
    if state and state.factionId then
        return { ok = false, error = Lp(src, 'fac.leave_your_faction_before_starting_a') }
    end

    name = tostring(name or ''):gsub('[%c]', ''):sub(1, 32)
    if #name < 3 then return { ok = false, error = Lp(src, 'fac.that_name_is_too_short') } end

    local id = slug(name)
    if #id < 3 then return { ok = false, error = Lp(src, 'fac.that_name_has_too_few_letters_in_it') } end
    if registry[id] then return { ok = false, error = Lp(src, 'fac.a_faction_is_already_called_that') } end

    short = (tostring(short or ''):upper():gsub('[^%u%d]', '')):sub(1, 4)
    if short == '' then short = name:upper():sub(1, 3) end

    local inserted, affected = pcall(function()
        return exports.oxmysql:execute_async([[
            INSERT INTO `bs_faction_registry`
                (`faction_id`, `label`, `short`, `owner_character_id`, `created_by`, `is_config`)
            VALUES (?, ?, ?, ?, ?, 0)
        ]], { id, name, short, charId, charId })
    end)
    if not inserted or (tonumber(affected) or 0) < 1 then
        print(('^1[BeyondSurvival]^7 (factions) faction create write failed for %s: %s')
            :format(tostring(charId), tostring(affected)))
        return { ok = false, error = Lp(src, 'fac.faction_could_not_be_saved_try_again') }
    end

    publish({ faction_id = id, label = name, short = short,
              owner_character_id = charId, created_by = charId, is_config = 0 })

    local joined = FactionDoJoin(src, id, true)      -- bypass: you made it
    if not joined or not joined.ok then
        -- A failed founder join leaves no orphaned registry row.
        exports.oxmysql:execute_async('DELETE FROM `bs_faction_registry` WHERE `faction_id` = ?', { id })
        registry[id] = nil
        Factions.List[id] = nil
        for i, known in ipairs(Factions.Order) do if known == id then table.remove(Factions.Order, i); break end end
        return { ok = false, error = (joined and joined.error) or 'could not join it' }
    end

    setRank(charId, 'owner')

    print(('^3[BeyondSurvival]^7 (factions) %s founded "%s" [%s]')
        :format(nameOf(src), name, short))

    return { ok = true, id = id, label = name, short = short }
end

-- Recruiting

function FactionsInvite(src, targetSrc)
    local charId = charIdOf(src)
    local state = ensurePlayerState(src)
    if not charId or not state or not state.factionId then
        return { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') }
    end

    if not atLeast(rankOf(charId, state.factionId), 'officer') then
        return { ok = false, error = Lp(src, 'fac.only_the_owner_and_officers_can_recr') }
    end

    targetSrc = tonumber(targetSrc) or 0
    if targetSrc <= 0 or targetSrc == src then return { ok = false, error = Lp(src, 'fac.who') } end

    local targetChar = charIdOf(targetSrc)
    if not targetChar then return { ok = false, error = Lp(src, 'fac.they_are_not_loaded') } end

    local targetState = ensurePlayerState(targetSrc)
    if targetState and targetState.factionId then
        return { ok = false, error = Lp(src, 'fac.they_are_already_in_a_faction') }
    end

    invites[targetSrc] = { factionId = state.factionId, by = src, at = os.time() }

    local faction = Factions.Get(state.factionId)
    notify(targetSrc, 'info',
        ('%s has invited you to %s. /faccept within two minutes.')
            :format(nameOf(src), faction and faction.label or state.factionId), 8000)

    return { ok = true, name = nameOf(targetSrc) }
end

function FactionsAccept(src)
    local invite = invites[src]
    if not invite then return { ok = false, error = Lp(src, 'fac.nobody_has_invited_you') } end

    if (os.time() - invite.at) > INVITE_SECONDS then
        invites[src] = nil
        return { ok = false, error = Lp(src, 'fac.that_invitation_has_expired') }
    end

    local result = FactionDoJoin(src, invite.factionId)
    invites[src] = nil

    if not result or not result.ok then
        return { ok = false, error = (result and result.error) or 'could not join' }
    end

    if invite.by and GetPlayerName(invite.by) then
        notify(invite.by, 'success', Lp(invite.by, 'fac.sq_joined', { name = nameOf(src) }))
    end

    return result
end

-- Running one

function FactionsKick(src, targetSrc)
    local charId = charIdOf(src)
    local state = ensurePlayerState(src)
    if not charId or not state or not state.factionId then
        return { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') }
    end

    if not atLeast(rankOf(charId, state.factionId), 'officer') then
        return { ok = false, error = Lp(src, 'fac.only_the_owner_and_officers_can_remo') }
    end

    targetSrc = tonumber(targetSrc) or 0
    local targetChar = charIdOf(targetSrc)
    local targetState = ensurePlayerState(targetSrc)

    if not targetChar or not targetState or targetState.factionId ~= state.factionId then
        return { ok = false, error = Lp(src, 'fac.they_are_not_in_your_faction') }
    end

    -- Nobody removes the owner, and an officer cannot remove another officer.
    local targetRank = rankOf(targetChar, state.factionId)
    if targetRank == 'owner' then return { ok = false, error = Lp(src, 'fac.that_is_the_owner') } end
    if targetRank == 'officer' and rankOf(charId, state.factionId) ~= 'owner' then
        return { ok = false, error = Lp(src, 'fac.only_the_owner_can_remove_an_officer') }
    end

    local result = FactionDoLeave(targetSrc)
    if result and result.ok then
        notify(targetSrc, 'warn', Lp(targetSrc, 'fac.removed_from', { name = result.left }))
    end

    return { ok = true, name = nameOf(targetSrc) }
end

function FactionsPromote(src, targetSrc, rank)
    local charId = charIdOf(src)
    local state = ensurePlayerState(src)
    if not charId or not state or not state.factionId then
        return { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') }
    end

    if rankOf(charId, state.factionId) ~= 'owner' then
        return { ok = false, error = Lp(src, 'fac.only_the_owner_can_change_ranks') }
    end

    rank = tostring(rank or 'officer'):lower()
    if rank ~= 'officer' and rank ~= 'member' then
        return { ok = false, error = Lp(src, 'fac.rank_is_officer_or_member') }
    end

    local targetChar = charIdOf(tonumber(targetSrc) or 0)
    local targetState = FactionStateOf and FactionStateOf(tonumber(targetSrc) or 0)
    if not targetChar or not targetState or targetState.factionId ~= state.factionId then
        return { ok = false, error = Lp(src, 'fac.they_are_not_in_your_faction') }
    end

    setRank(targetChar, rank)
    notify(tonumber(targetSrc), 'info', Lp(tonumber(targetSrc), 'fac.you_are_now', { rank = Lp(tonumber(targetSrc), 'fac.rank_' .. tostring(rank)) }))

    return { ok = true, rank = rank }
end

-- Roster comes from the database, not from online players.
function FactionsRoster(src)
    local state = ensurePlayerState(src)
    if not state or not state.factionId then
        return { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') }
    end

    local rows = exports.oxmysql:query_async([[
        SELECT m.`character_id`, m.`rank`, c.`first_name`, c.`last_name`
          FROM `bs_faction_members` m
          JOIN `bs_characters` c ON c.`id` = m.`character_id`
         WHERE m.`faction_id` = ?
      ORDER BY FIELD(m.`rank`, 'owner', 'officer', 'member'), c.`first_name`
    ]], { state.factionId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            charId = row.character_id,
            rank = row.rank,
            name = ('%s %s'):format(row.first_name or '?', row.last_name or ''),
        }
    end

    local entry = registry[state.factionId]
    return { ok = true, faction = state.factionId,
             label = (Factions.Get(state.factionId) or {}).label,
             isConfig = entry and entry.isConfig or false,
             members = out }
end

-- Disbanding: owner only, player-made factions only (config factions are not deletable). Members are removed through the normal leave path so their reputation is banked.
function FactionsDisband(src)
    local charId = charIdOf(src)
    local state = ensurePlayerState(src)
    if not charId or not state or not state.factionId then
        return { ok = false, error = Lp(src, 'fac.you_are_not_in_a_faction') }
    end

    local entry = registry[state.factionId]
    if not entry then return { ok = false } end
    if entry.isConfig then return { ok = false, error = Lp(src, 'fac.that_faction_is_not_yours_to_disband') } end
    if entry.owner ~= charId then return { ok = false, error = Lp(src, 'fac.only_the_owner_can_disband_it') } end

    -- Shared by /fdisband and the abandonment sweep. Reputation rows are kept on purpose so rejoining a rebuilt faction resumes progress.
    local done, label = dissolve(state.factionId, 'the owner disbanded it')
    if not done then return { ok = false, error = Lp(src, 'fac.it_would_not_disband') } end

    return { ok = true, label = label }
end

-- Abandoned owners: lore (config) factions stay fixed and an admin reassigns them. Player-made factions are disbanded when the owner's character is deleted or the owner has not played for a long time.

local ABANDON_DAYS = 14

-- Turns members out and removes the faction. Shared by /fdisband and the sweep so there is one way a faction ends.
-- English disband reasons (kept for logs) mapped to locale keys for the members' notice.
local DISBAND_REASON = {
    ['the owner disbanded it'] = 'fac.why_owner',
    ['its founder is gone'] = 'fac.why_founder',
    ['removed by staff'] = 'fac.why_staff',
    ['staff reset'] = 'fac.why_reset',
}

dissolve = function(factionId, reason)
    local entry = registry[factionId]
    if not entry then return false end
    if entry.isConfig then return false end       -- lore factions never dissolve

    local label = (Factions.Get(factionId) or {}).label or factionId

    for _, id in ipairs(GetPlayers()) do
        local other = tonumber(id)
        local otherState = FactionStateOf and FactionStateOf(other)
        if otherState and otherState.factionId == factionId then
            FactionDoLeave(other)
            -- reasons are English log text; show the player's translation when there is one
            local why = reason and DISBAND_REASON[reason] and Lp(other, DISBAND_REASON[reason]) or reason
            notify(other, 'warn', Lp(other, 'fac.sq_disbanded', { name = label, why = why and (' - ' .. why) or '' }))
        end
    end

    exports.oxmysql:execute_async(
        'DELETE FROM `bs_faction_members` WHERE `faction_id` = ?', { factionId })
    exports.oxmysql:execute_async(
        'DELETE FROM `bs_faction_registry` WHERE `faction_id` = ?', { factionId })

    registry[factionId] = nil
    Factions.List[factionId] = nil
    for i, id in ipairs(Factions.Order) do
        if id == factionId then table.remove(Factions.Order, i) break end
    end

    print(('^3[BeyondSurvival]^7 (factions) "%s" dissolved%s')
        :format(label, reason and (' - ' .. reason) or ''))

    return true, label
end

-- The sweep runs hourly with one cheap query for player-made factions whose owner is deleted or inactive for two weeks. A missing owner row also counts as abandoned.
CreateThread(function()
    while true do
        Wait(3600000)     -- an hour

        local rows = exports.oxmysql:query_async([[
            SELECT r.`faction_id`
              FROM `bs_faction_registry` r
         LEFT JOIN `bs_characters` c ON c.`id` = r.`owner_character_id`
             WHERE r.`is_config` = 0
               AND (
                    r.`owner_character_id` IS NULL
                 OR c.`id` IS NULL
                 OR c.`deleted_at` IS NOT NULL
                 OR (c.`last_played` IS NOT NULL
                     AND c.`last_played` < DATE_SUB(NOW(), INTERVAL ? DAY))
               )
        ]], { ABANDON_DAYS }) or {}

        for _, row in ipairs(rows) do
            dissolve(row.faction_id, 'its founder is gone')
        end
    end
end)

-- Admin: put someone in charge of a config faction

function FactionsSetOwner(src, factionId, targetSrc)
    if not IsPlayerAceAllowed(src, 'bs.admin') and not IsPlayerAceAllowed(src, 'bs.superadmin') then
        return { ok = false, error = Lp(src, 'fac.not_allowed_not_allowed') }
    end

    factionId = tostring(factionId or ''):lower()
    local entry = registry[factionId]
    if not entry then return { ok = false, error = Lp(src, 'fac.no_such_faction') } end

    local targetChar = charIdOf(tonumber(targetSrc) or 0)
    if not targetChar then return { ok = false, error = Lp(src, 'fac.they_are_not_loaded') } end

    exports.oxmysql:execute_async(
        'UPDATE `bs_faction_registry` SET `owner_character_id` = ? WHERE `faction_id` = ?',
        { targetChar, factionId })
    entry.owner = targetChar

    -- Being made owner also makes you a member.
    local targetState = FactionStateOf and FactionStateOf(tonumber(targetSrc))
    if not targetState or targetState.factionId ~= factionId then
        FactionDoJoin(tonumber(targetSrc), factionId, true)
    end
    setRank(targetChar, 'owner')

    notify(tonumber(targetSrc), 'success',
        Lp(tonumber(targetSrc), 'fac.in_charge', { name = entry.label }))

    return { ok = true, label = entry.label, name = nameOf(tonumber(targetSrc)) }
end

-- Callbacks are thin wrappers so menus and commands share one implementation. Staff management lives next to the registry; the admin UI is never trusted and every request is checked against the caller's ACE here.
local function staff(src)
    return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin')
end

local function adminList()
    local rows = exports.oxmysql:query_async([[
        SELECT r.`faction_id`, r.`label`, r.`short`, r.`is_config`,
               r.`owner_character_id`, COUNT(m.`character_id`) AS `members`
          FROM `bs_faction_registry` r
     LEFT JOIN `bs_faction_members` m ON m.`faction_id` = r.`faction_id`
      GROUP BY r.`faction_id`, r.`label`, r.`short`, r.`is_config`, r.`owner_character_id`
      ORDER BY r.`is_config` DESC, r.`label` ASC
    ]], {}) or {}
    return { ok = true, factions = rows }
end

local function adminDelete(src, factionId)
    if not staff(src) then return { ok = false, error = Lp(src, 'fac.not_allowed_not_allowed') } end
    factionId = tostring(factionId or ''):lower()
    local entry = registry[factionId]
    if not entry then return { ok = false, error = Lp(src, 'fac.no_such_faction_no_such_faction') } end
    if entry.isConfig then return { ok = false, error = 'lore factions cannot be deleted here' } end
    local ok, label = dissolve(factionId, 'removed by staff')
    return ok and { ok = true, label = label } or { ok = false, error = 'could not remove faction' }
end

local function adminReset(src)
    if not staff(src) then return { ok = false, error = Lp(src, 'fac.not_allowed_not_allowed') } end
    local ids = {}
    for id, entry in pairs(registry) do
        if not entry.isConfig then ids[#ids + 1] = id end
    end
    local removed = 0
    for _, id in ipairs(ids) do
        if dissolve(id, 'staff reset') then removed = removed + 1 end
    end
    return { ok = true, removed = removed }
end

BSB.RegisterCallback('factions:admin:list', function(src)
    if not staff(src) then return { ok = false, error = Lp(src, 'fac.not_allowed_not_allowed') } end
    return adminList()
end)
BSB.RegisterCallback('factions:admin:delete', adminDelete)
BSB.RegisterCallback('factions:admin:reset', function(src) return adminReset(src) end)
BSB.RegisterCallback('factions:create',   function(src, name, short) return FactionsCreate(src, name, short) end)
BSB.RegisterCallback('factions:invite',   function(src, target) return FactionsInvite(src, target) end)
BSB.RegisterCallback('factions:accept',   function(src) return FactionsAccept(src) end)
BSB.RegisterCallback('factions:kick',     function(src, target) return FactionsKick(src, target) end)
BSB.RegisterCallback('factions:promote',  function(src, target, rank) return FactionsPromote(src, target, rank) end)
BSB.RegisterCallback('factions:roster',   function(src) return FactionsRoster(src) end)
BSB.RegisterCallback('factions:disband',  function(src) return FactionsDisband(src) end)
BSB.RegisterCallback('factions:setOwner', function(src, id, target) return FactionsSetOwner(src, id, target) end)

exports('FactionOwner', function(factionId)
    local entry = registry[tostring(factionId or '')]
    return entry and entry.owner or nil
end)

exports('FactionRank', function(src, factionId)
    local charId = charIdOf(src)
    return charId and rankOf(charId, factionId) or nil
end)

AddEventHandler('playerDropped', function() invites[source] = nil end)

-- Commands
-- Same operations as the menu, with a keyboard. The menu calls these too.

local function answer(src, result, good)
    notify(src, (result and result.ok) and 'success' or 'warn',
        (result and result.ok) and good(result) or ((result and result.error) or 'No.'))
end

RegisterCommand('fcreate', function(src, args)
    if src == 0 then return end
    local short = args[1]
    local name = table.concat(args, ' ', 2)
    if not short or name == '' then
        return notify(src, 'info', Lp(src, 'fac.use_fcreate'))
    end

    -- Called directly rather than through the callback: this is the server.
    local created = FactionsCreate(src, name, short)
    answer(src, created, function(r) return ('Founded %s [%s].'):format(r.label, r.short) end)
end, false)

RegisterCommand('finvite', function(src, args)
    if src == 0 then return end
    local target = tonumber(args[1])
    if not target then return notify(src, 'info', Lp(src, 'fac.use_finvite')) end

    answer(src, FactionsInvite(src, target), function(r) return ('Invited %s.'):format(r.name) end)
end, false)

RegisterCommand('faccept', function(src)
    if src == 0 then return end
    answer(src, FactionsAccept(src), function(r) return ('Joined %s.'):format(r.label) end)
end, false)

RegisterCommand('fkick', function(src, args)
    if src == 0 then return end
    local target = tonumber(args[1])
    if not target then return notify(src, 'info', Lp(src, 'fac.use_fkick')) end

    answer(src, FactionsKick(src, target), function(r) return ('Removed %s.'):format(r.name) end)
end, false)

RegisterCommand('fpromote', function(src, args)
    if src == 0 then return end
    local target = tonumber(args[1])
    if not target then return notify(src, 'info', Lp(src, 'fac.use_fpromote')) end

    answer(src, FactionsPromote(src, target, args[2]),
        function(r) return ('They are now %s.'):format(r.rank) end)
end, false)

RegisterCommand('froster', function(src)
    if src == 0 then return end

    local result = FactionsRoster(src)
    if not result or not result.ok then
        return notify(src, 'warn', (result and result.error) or Lp(src, 'fac.you_are_not_in_a_faction'))
    end

    TriggerClientEvent('chat:addMessage', src,
        { args = { 'FACTION', ('%s - %d member(s)'):format(result.label, #result.members) } })

    for _, member in ipairs(result.members) do
        TriggerClientEvent('chat:addMessage', src,
            { args = { result.label, ('%s (%s)'):format(member.name, member.rank) } })
    end
end, false)

RegisterCommand('fdisband', function(src)
    if src == 0 then return end
    answer(src, FactionsDisband(src), function(r) return ('%s is gone.'):format(r.label) end)
end, false)

BSB.RegisterCommand('factionowner', 'bs.admin', 'Put a player in charge of a faction',
    { { name = 'faction', help = 'faction id' }, { name = 'id', help = 'server id' } },
    function(src, args)
        local result = FactionsSetOwner(src, args[1], tonumber(args[2]))
        answer(src, result, function(r)
            return ('%s now runs %s.'):format(r.name, r.label)
        end)
    end)

-- Everything the faction panel needs, in one call so the panel opens complete.
-- The nearby list is computed here from real positions, so recruiting works by standing next to someone.

local RECRUIT_RADIUS = 25.0

function FactionsPanel(src)
    if not registryReady then return { ok = false, error = Lp(src, 'fac.faction_registry_is_still_starting') } end
    local charId = charIdOf(src)
    if not charId then return { ok = false } end

    local state = ensurePlayerState(src)
    local factionId = state and state.factionId or nil

    local out = {
        ok = true,
        faction = nil,
        rank = nil,
        members = {},
        nearby = {},
        invite = nil,
        canCreate = factionId == nil,
    }

    -- Pending invitation and the time left on it.
    local invite = invites[src]
    if invite and (os.time() - invite.at) <= INVITE_SECONDS then
        local def = Factions.Get(invite.factionId)
        out.invite = {
            faction = invite.factionId,
            label = def and def.label or invite.factionId,
            seconds = INVITE_SECONDS - (os.time() - invite.at),
        }
    end

    if factionId then
        local def = Factions.Get(factionId) or {}
        local entry = registry[factionId]

        out.faction = {
            id = factionId,
            label = def.label or factionId,
            short = def.short or '',
            blurb = def.blurb or '',
            -- Lore factions belong to the server and outlive everybody; player factions go with their owner.
            lore = entry and entry.isConfig or false,
            reputation = state.reputation or 0,
        }

        out.rank = rankOf(charId, factionId)

        local roster = FactionsRoster(src)
        if roster and roster.ok then
            -- Online members carry their server id so the panel can promote or remove them. Offline ones are listed without one.
            local online = {}
            for _, id in ipairs(GetPlayers()) do
                local other = tonumber(id)
                local otherChar = charIdOf(other)
                if otherChar then online[otherChar] = other end
            end

            for _, member in ipairs(roster.members) do
                member.src = online[member.charId]
                member.you = member.charId == charId
                out.members[#out.members + 1] = member
            end
        end
    end

    -- Who is close enough to be asked. Only offered to someone who can act on it.
    if factionId and atLeast(rankOf(charId, factionId), 'officer') then
        local ped = GetPlayerPed(src)
        local at = ped and ped ~= 0 and GetEntityCoords(ped) or nil

        if at then
            for _, id in ipairs(GetPlayers()) do
                local other = tonumber(id)
                if other ~= src then
                    local otherPed = GetPlayerPed(other)
                    local otherState = FactionStateOf and FactionStateOf(other)

                    if otherPed and otherPed ~= 0
                        and not (otherState and otherState.factionId) then
                        local c = GetEntityCoords(otherPed)
                        if #(at - c) <= RECRUIT_RADIUS then
                            out.nearby[#out.nearby + 1] =
                                { src = other, name = nameOf(other) }
                        end
                    end
                end
            end
        end
    end

    return out
end

BSB.RegisterCallback('factions:panel', function(src) return FactionsPanel(src) end)

-- Leaving from the menu. Uses the ordinary leave path.
BSB.RegisterCallback('factions:leave2', function(src)
    return FactionDoLeave(src)
end)

