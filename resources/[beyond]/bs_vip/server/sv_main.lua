-- bs_vip - VIP state, perks and exports.
-- VIP is keyed by account (license identifier), not by character. Everything is cosmetic or convenience (see config_vip.lua).
-- Exports used by other resources must not yield: they read the in-memory caches and write to the DB without waiting.

local state    = {}   -- [src] = { src, identifier, charId }
local byIdent  = {}   -- [identifier] = state entry
local members  = {}   -- [identifier] = { tier = id, exp = unix|nil }   (all members, online or not)
local unlocked = {}   -- [identifier] = { [unlockId] = true }
local prefs    = {}   -- [identifier] = table
local looks    = {}   -- [identifier] = { month = 'YYYY-MM'|nil, tickets = n }

local db = exports.oxmysql

--------------------------------------------------------------------------------
-- Tables (also in bs_core/sql/025_vip_perks.sql)
--------------------------------------------------------------------------------

local ready = false

CreateThread(function()
    db:execute_async([[CREATE TABLE IF NOT EXISTS `bs_vip_members` (
        `identifier` VARCHAR(191) NOT NULL, `tier` VARCHAR(32) NOT NULL,
        `granted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `expires_at` DATETIME NULL DEFAULT NULL,
        PRIMARY KEY (`identifier`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    db:execute_async([[CREATE TABLE IF NOT EXISTS `bs_vip_unlocks` (
        `identifier` VARCHAR(191) NOT NULL, `unlock_id` VARCHAR(48) NOT NULL,
        `tier` VARCHAR(32) NOT NULL, `granted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`, `unlock_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    db:execute_async([[CREATE TABLE IF NOT EXISTS `bs_vip_prefs` (
        `identifier` VARCHAR(191) NOT NULL, `prefs` LONGTEXT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    db:execute_async([[CREATE TABLE IF NOT EXISTS `bs_vip_appearance` (
        `identifier` VARCHAR(191) NOT NULL, `last_free_month` CHAR(7) NULL DEFAULT NULL,
        `tickets` INT UNSIGNED NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Member cache: bs_core asks for character slots before a character is loaded, so membership must be known by identifier up front.
    local rows = db:query_async([[
        SELECT `identifier`, `tier`, UNIX_TIMESTAMP(`expires_at`) AS `exp`
        FROM `bs_vip_members` WHERE `expires_at` IS NULL OR `expires_at` > NOW()]]) or {}
    for _, r in ipairs(rows) do
        members[r.identifier] = { tier = r.tier, exp = tonumber(r.exp) }
    end
    ready = true
    print(('^2[BeyondSurvival]^7 (vip) %d active member(s)'):format(#rows))
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function notify(src, kind, message)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = message, duration = 3600 })
end

local function thisMonth() return os.date('%Y-%m') end

local function tierOf(identifier)
    -- VIP switched off by the owner: everybody gets the top tier
    if Vip.Disabled() then return Vip.Get(Vip.Order[#Vip.Order]) end
    local m = identifier and members[identifier]
    if not m then return nil end
    if m.exp and m.exp <= os.time() then return nil end
    return Vip.Get(m.tier)
end

local function levelOf(identifier)
    local t = tierOf(identifier)
    return t and t.level or 0
end

local function identOf(src)
    local s = state[tonumber(src)]
    if s then return s.identifier end
    local ok, id = pcall(function() return exports.bs_core:PrimaryIdentifier(tonumber(src)) end)
    return ok and id or nil
end

local function hasPerk(identifier, perk)
    return Vip.PerkAllowed(levelOf(identifier), perk)
end

local function prefsOf(identifier)
    local p = prefs[identifier]
    if not p then p = {}; prefs[identifier] = p end
    return p
end

--------------------------------------------------------------------------------
-- Preferences: what each key accepts and which perk unlocks it
--------------------------------------------------------------------------------

local function colourOk(level, v)
    if v == '' then return '' end
    if type(v) ~= 'string' then return nil end
    v = v:lower()
    return Vip.AllowedColours(level)[v] and v or nil
end

local function listOk(list)
    return function(_, v)
        if type(v) ~= 'string' and type(v) ~= 'number' then return nil end
        return Vip.FindById(list, v) and v or nil
    end
end

local function boolOk(_, v) if type(v) == 'boolean' then return v end return nil end

local PREFS = {
    tagStyle    = { perk = 'tagStyle',       check = listOk(Vip.TagStyles) },
    tagHex      = { perk = 'tagStyle',       check = colourOk },
    chatBadge   = { perk = 'chatBadge',      check = boolOk },
    chatHex     = { perk = 'chatBadge',      check = colourOk },
    blipColour  = { perk = 'blipColour',     check = function(_, v) v = tonumber(v); return v and Vip.FindById(Vip.BlipColours, v) and v or nil end },
    hudHex      = { perk = 'hudColour',      check = colourOk },
    stashSkin   = { perk = 'stashSkin',      check = listOk(Vip.StashSkins) },
    droneSkin   = { perk = 'boosterSkins',   check = listOk(Vip.DroneSkins) },
    turretSkin  = { perk = 'boosterSkins',   check = listOk(Vip.TurretSkins) },
    killfeed    = { perk = 'killfeedStyle',  check = listOk(Vip.KillfeedStyles) },
    deathscreen = { perk = 'killfeedStyle',  check = listOk(Vip.DeathStyles) },
    banner      = { perk = 'profileBanner',  check = listOk(Vip.Banners) },
}

-- Only prefs whose perk the account still has. A lapsed tier keeps its saved choices but they stop showing.
local function effectivePrefs(identifier)
    local level, out = levelOf(identifier), {}
    for key, value in pairs(prefs[identifier] or {}) do
        local def = PREFS[key]
        if def and Vip.PerkAllowed(level, def.perk) and value ~= '' then out[key] = value end
    end
    return out
end

--------------------------------------------------------------------------------
-- Replication
--------------------------------------------------------------------------------

--- Public statebag read by bs_factions (tags, blips) and bs_ui (party HUD).
local function pushBag(src)
    local s = state[src]
    if not s then return end
    local tier = tierOf(s.identifier)
    if not tier then
        Player(src).state:set('bsVipTag', nil, true)
        return
    end
    local p = effectivePrefs(s.identifier)
    local off = Vip.Disabled()
    Player(src).state:set('bsVipTag', {
        tier   = (not off) and tier.level or nil,
        colour = (not off) and tier.colour or nil,
        style  = (p.tagStyle and p.tagStyle ~= 'default') and p.tagStyle or nil,
        hex    = p.tagHex,
        blip   = p.blipColour,
        hud    = p.hudHex,
    }, true)
end

local function appearanceInfo(identifier)
    local l = looks[identifier] or { tickets = 0 }
    local freeOk = hasPerk(identifier, 'appearanceChange') and l.month ~= thisMonth()
    return { free = freeOk, month = l.month, tickets = l.tickets or 0,
             perk = hasPerk(identifier, 'appearanceChange'), thisMonth = thisMonth() }
end

local function pushSync(src)
    local s = state[src]
    if not s then return end
    local tier = tierOf(s.identifier)
    local m = members[s.identifier]
    TriggerClientEvent('bs:vip:sync', src, {
        tier       = tier and tier.id or nil,
        level      = tier and tier.level or 0,
        label      = tier and tier.label or nil,
        colour     = tier and tier.colour or nil,
        expiresAt  = (tier and m and m.exp) and (m.exp * 1000) or nil,
        unlocks    = unlocked[s.identifier] or {},
        prefs      = prefs[s.identifier] or {},
        appearance = appearanceInfo(s.identifier),
        open       = Vip.Disabled(),
    })
    pushBag(src)
end

local function refreshIdentifier(identifier)
    local entry = byIdent[identifier]
    if entry then pushSync(entry.src) end
end

--------------------------------------------------------------------------------
-- Loading / unloading
--------------------------------------------------------------------------------

local function loadAccount(identifier)
    local set = {}
    for _, row in ipairs(db:query_async(
        'SELECT `unlock_id` FROM `bs_vip_unlocks` WHERE `identifier` = ?', { identifier }) or {}) do
        set[row.unlock_id] = true
    end
    unlocked[identifier] = set

    local row = (db:query_async('SELECT `prefs` FROM `bs_vip_prefs` WHERE `identifier` = ?', { identifier }) or {})[1]
    local ok, decoded = pcall(json.decode, row and row.prefs or '{}')
    prefs[identifier] = (ok and type(decoded) == 'table') and decoded or {}

    local a = (db:query_async('SELECT `last_free_month`, `tickets` FROM `bs_vip_appearance` WHERE `identifier` = ?',
        { identifier }) or {})[1]
    looks[identifier] = { month = a and a.last_free_month or nil, tickets = a and tonumber(a.tickets) or 0 }

    -- Refresh membership from the DB (a grant from another tool may be newer).
    local m = (db:query_async([[SELECT `tier`, UNIX_TIMESTAMP(`expires_at`) AS `exp` FROM `bs_vip_members`
        WHERE `identifier` = ? AND (`expires_at` IS NULL OR `expires_at` > NOW()) LIMIT 1]], { identifier }) or {})[1]
    members[identifier] = m and { tier = m.tier, exp = tonumber(m.exp) } or nil
end

AddEventHandler('bs:hook:player:loaded', function(player)
    if type(player) ~= 'table' or not player.source or not player.identifier then return end
    local src, identifier = tonumber(player.source), player.identifier
    if not src then return end

    loadAccount(identifier)
    local entry = { src = src, identifier = identifier, charId = tonumber(player.charId) }
    state[src] = entry
    byIdent[identifier] = entry
    pushSync(src)
end)

local function dropPlayer(src, entry)
    if not entry then return end
    if state[src] == entry then state[src] = nil end
    if byIdent[entry.identifier] == entry then
        byIdent[entry.identifier] = nil
        unlocked[entry.identifier] = nil
        prefs[entry.identifier] = nil
        looks[entry.identifier] = nil
    end
end

AddEventHandler('bs:hook:player:unloaded', function(player)
    if type(player) ~= 'table' or not player.identifier then return end
    local entry = byIdent[player.identifier]
    if entry then
        pcall(function() Player(entry.src).state:set('bsVipTag', nil, true) end)
        dropPlayer(entry.src, entry)
    end
end)

AddEventHandler('playerDropped', function() dropPlayer(source, state[source]) end)

-- Expired subscriptions stop applying without a relog.
CreateThread(function()
    while true do
        Wait(Vip.Settings.expirySweepMs or 300000)
        local now = os.time()
        for identifier, m in pairs(members) do
            if m.exp and m.exp <= now then
                members[identifier] = nil
                refreshIdentifier(identifier)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Grant / revoke (server only)
--------------------------------------------------------------------------------

local function grantTierUnlocks(identifier, tierId)
    local tier = Vip.Get(tierId)
    if not tier then return end
    local have = unlocked[identifier] or {}
    unlocked[identifier] = have
    for _, unlock in ipairs(tier.grantUnlocks or {}) do
        if not have[unlock.id] then
            have[unlock.id] = true
            db:execute('INSERT IGNORE INTO `bs_vip_unlocks` (`identifier`, `unlock_id`, `tier`) VALUES (?, ?, ?)',
                { identifier, unlock.id, tier.id })
        end
    end
end

local function targetIdent(target)
    if type(target) == 'number' then return identOf(target) end
    if type(target) == 'string' and target:find(':') then return target end
    local n = tonumber(target)
    return n and identOf(n) or nil
end

--- @param target number|string  server id or 'license:...'
--- @param tierId string|number  'supporter'|'patron'|'legend' or 1..3
--- @param days number|nil       nil/0 = never expires
local function grantVIP(target, tierId, days)
    local tier = Vip.Get(tierId)
    if not tier then return false end
    local identifier = targetIdent(target)
    if not identifier then return false end

    days = math.floor(tonumber(days) or 0)
    members[identifier] = { tier = tier.id, exp = days > 0 and (os.time() + days * 86400) or nil }

    db:execute([[
        INSERT INTO `bs_vip_members` (`identifier`, `tier`, `granted_at`, `expires_at`)
        VALUES (?, ?, NOW(), IF(? > 0, DATE_ADD(NOW(), INTERVAL ? DAY), NULL))
        ON DUPLICATE KEY UPDATE `tier` = VALUES(`tier`), `granted_at` = NOW(), `expires_at` = VALUES(`expires_at`)
    ]], { identifier, tier.id, days, days })

    grantTierUnlocks(identifier, tier.id)

    local entry = byIdent[identifier]
    if entry then
        pushSync(entry.src)
        notify(entry.src, 'success', Lp(entry.src, 'vip.now_vip', { tier = tier.label, key = Vip.Settings.panelKey or 'F7' }))
    end
    return true
end
exports('GrantVIP', grantVIP)

exports('RevokeVIP', function(target)
    local identifier = targetIdent(target)
    if not identifier then return false end
    members[identifier] = nil
    db:execute('DELETE FROM `bs_vip_members` WHERE `identifier` = ?', { identifier })
    refreshIdentifier(identifier)
    return true
end)

--- One free appearance change, for anyone (staff comp).
local function grantTicket(target, count)
    local identifier = targetIdent(target)
    if not identifier then return false end
    count = math.max(1, math.floor(tonumber(count) or 1))
    local l = looks[identifier]
    if l then l.tickets = (l.tickets or 0) + count end
    db:execute([[INSERT INTO `bs_vip_appearance` (`identifier`, `tickets`) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `tickets` = `tickets` + VALUES(`tickets`)]], { identifier, count })
    refreshIdentifier(identifier)
    return true
end
exports('GrantAppearanceTicket', grantTicket)

--------------------------------------------------------------------------------
-- Reads (all non-yielding)
--------------------------------------------------------------------------------

exports('IsVIP', function(src) return tierOf(identOf(src)) ~= nil end)
exports('GetTier', function(src) local t = tierOf(identOf(src)); return t and t.id or nil end)
exports('TierLevel', function(src) return levelOf(identOf(src)) end)
exports('HasPerk', function(src, perk) return hasPerk(identOf(src), perk) end)

--- A number from the perk's config (bonus, pct...) if the player has it, else `default`.
exports('PerkValue', function(src, perk, key, default)
    if not hasPerk(identOf(src), perk) then return default end
    local p = Vip.Perks[perk]
    local v = p and p[key or 'bonus']
    if v == nil then return default end
    return v
end)

exports('GetPrefs', function(src)
    local identifier = identOf(src)
    return identifier and effectivePrefs(identifier) or {}
end)

-- Stored cosmetic choice for hooks not drawn yet (kill feed, death screen, banner). nil when not allowed or not chosen.
exports('GetCosmetic', function(src, key)
    local identifier = identOf(src)
    return identifier and effectivePrefs(identifier)[key] or nil
end)

exports('GetTierInfo', function(src)
    local identifier = identOf(src)
    local tier = tierOf(identifier)
    if not tier then return nil end
    local p = effectivePrefs(identifier)
    return { id = tier.id, level = tier.level, label = tier.label, colour = tier.colour,
             banner = (p.banner and p.banner ~= 'none') and p.banner or nil }
end)

--- For bs_chat. nil = draw as a normal player.
exports('ChatStyle', function(src)
    local identifier = identOf(src)
    local tier = tierOf(identifier)
    if not tier then return nil end
    local p = prefs[identifier] or {}
    local allowed = Vip.PerkAllowed(tier.level, 'chatBadge')
    if not allowed then return nil end
    return {
        badge    = (p.chatBadge ~= false and not Vip.Disabled()) and tier.label:upper() or nil,
        badgeHex = tier.colour,
        nameHex  = (p.chatHex and p.chatHex ~= '') and p.chatHex or nil,
    }
end)

--- bs_core asks this at character select, before anything is loaded.
exports('ExtraCharacterSlotsFor', function(identifier)
    if not Vip.PerkAllowed(levelOf(identifier), 'extraCharacter') then return 0 end
    return tonumber(Vip.Perks.extraCharacter.bonus) or 0
end)

--- Plate text rules, shared with bs_vehicles. Returns cleaned text or nil, reason.
local function validatePlate(text, src)
    src = tonumber(src)
    if type(text) ~= 'string' then return nil, Lp(src, 'vip.plate_none') end
    text = text:upper():gsub('^%s+', ''):gsub('%s+$', '')
    local P = Vip.Plate
    if #text < (P.minLength or 1) or #text > (P.maxLength or 8) then
        return nil, Lp(src, 'vip.plate_len', { min = P.minLength or 1, max = P.maxLength or 8 })
    end
    if not text:match('^[A-Z0-9 ]+$') then return nil, Lp(src, 'vip.plate_chars') end
    local squashed = text:gsub(' ', '')
    if squashed == '' then return nil, Lp(src, 'vip.plate_blank') end
    for _, bad in ipairs(P.blocklist or {}) do
        if squashed:find(bad, 1, true) then return nil, Lp(src, 'vip.plate_bad') end
    end
    return text
end
exports('ValidatePlateText', validatePlate)

--- @return boolean ok, string kind|reason   kind = 'free' | 'ticket'
local function canChangeAppearance(src)
    local identifier = identOf(src)
    if not identifier then return false, 'not loaded' end
    local info = appearanceInfo(identifier)
    if info.free then return true, 'free' end
    if (info.tickets or 0) > 0 then return true, 'ticket' end
    if info.perk then return false, Lp(src, 'vip.monthly_used') end
    return false, Lp(src, 'vip.no_change')
end
exports('CanChangeAppearance', canChangeAppearance)

-- Spends the change. Call only after the new look was accepted.
exports('ConsumeAppearanceChange', function(src)
    local ok, kind = canChangeAppearance(src)
    if not ok then return false, kind end
    local identifier = identOf(src)
    local l = looks[identifier] or { tickets = 0 }
    looks[identifier] = l
    if kind == 'free' then
        l.month = thisMonth()
        db:execute([[INSERT INTO `bs_vip_appearance` (`identifier`, `last_free_month`) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE `last_free_month` = VALUES(`last_free_month`)]], { identifier, l.month })
    else
        l.tickets = math.max(0, (l.tickets or 0) - 1)
        db:execute('UPDATE `bs_vip_appearance` SET `tickets` = GREATEST(`tickets` - 1, 0) WHERE `identifier` = ?',
            { identifier })
    end
    refreshIdentifier(identifier)
    return true, kind
end)

exports('GetTitle', function(src)
    local identifier = identOf(src)
    local tier = tierOf(identifier)
    if not tier then return nil end
    local have = unlocked[identifier] or {}
    local best = nil
    for _, unlock in ipairs(tier.grantUnlocks or {}) do
        if unlock.type == 'title' and have[unlock.id] then best = unlock.label end
    end
    if have.vip_title_founder then best = 'Founder' end
    return best
end)

exports('HasUnlock', function(src, unlockId)
    local have = unlocked[identOf(src) or '']
    return have ~= nil and have[unlockId] == true
end)

exports('ListUnlocks', function(src)
    local out = {}
    for id, got in pairs(unlocked[identOf(src) or ''] or {}) do
        if got then out[#out + 1] = id end
    end
    return out
end)

--------------------------------------------------------------------------------
-- Client callbacks
--------------------------------------------------------------------------------

BSB.RegisterCallback('vip:status', function(src)
    local s = state[src]
    if not s then return { ok = false } end
    local tier = tierOf(s.identifier)
    local m = members[s.identifier]
    return {
        ok         = true,
        tier       = tier and tier.id or nil,
        level      = tier and tier.level or 0,
        label      = tier and tier.label or nil,
        colour     = tier and tier.colour or nil,
        title      = exports.bs_vip:GetTitle(src),
        prefs      = prefs[s.identifier] or {},
        appearance = appearanceInfo(s.identifier),
        open       = Vip.Disabled(),
        expiresAt  = (not Vip.Disabled() and tier and m and m.exp) and (m.exp * 1000) or nil,
    }
end)

local prefRate = {}

BSB.RegisterCallback('vip:setPref', function(src, key, value)
    local s = state[src]
    if not s then return { ok = false, error = Lp(src, 'vip.e_not_loaded') } end

    local now = GetGameTimer()
    if prefRate[src] and now - prefRate[src] < 250 then return { ok = false, error = Lp(src, 'vip.e_slow') } end
    prefRate[src] = now

    local def = PREFS[key]
    if not def then return { ok = false, error = Lp(src, 'vip.e_unknown') } end
    local level = levelOf(s.identifier)
    if not Vip.PerkAllowed(level, def.perk) then
        local p = Vip.Perks[def.perk]
        return { ok = false, error = Lp(src, 'vip.needs_tier', { tier = Vip.Get(p.minTier).label }) }
    end

    local clean = def.check(level, value)
    if clean == nil then return { ok = false, error = Lp(src, 'vip.e_choice') } end

    local p = prefsOf(s.identifier)
    p[key] = clean
    db:execute([[INSERT INTO `bs_vip_prefs` (`identifier`, `prefs`) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `prefs` = VALUES(`prefs`)]], { s.identifier, json.encode(p) })

    pushSync(src)
    return { ok = true, prefs = p }
end)

AddEventHandler('playerDropped', function() prefRate[source] = nil end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function isStaff(src) return src == 0 or IsPlayerAceAllowed(src, 'bs.superadmin') end

local function reply(src, kind, key, vars)
    if src == 0 then print('[bs_vip] ' .. BSLocale.T('en', key, vars)) else notify(src, kind, Lp(src, key, vars)) end
end

RegisterCommand(Vip.Settings.statusCommand, function(src)
    if src == 0 then return end
    local tier = tierOf(identOf(src))
    if not tier then return notify(src, 'info', Lp(src, 'vip.not_vip')) end
    local m = members[identOf(src)]
    notify(src, 'info', Lp(src, 'vip.status', { tier = tier.label,
        exp = (m and m.exp) and Lp(src, 'vip.expires', { date = os.date('%Y-%m-%d', m.exp) }) or '' }))
end, false)

-- /grantvip <id|license:...> <tier name or 1-3> [days]
RegisterCommand('grantvip', function(src, args)
    if not isStaff(src) then return end
    local target = tonumber(args[1]) or args[1]
    if not target or not Vip.IsValid(args[2]) then
        return reply(src, 'info', 'vip.cmd.grant_usage', { tiers = table.concat(Vip.Order, '|') })
    end
    local ok = grantVIP(target, args[2], args[3])
    reply(src, ok and 'success' or 'warn', ok and 'vip.cmd.granted' or 'vip.cmd.grant_fail')
end, false)

RegisterCommand('revokevip', function(src, args)
    if not isStaff(src) then return end
    local target = tonumber(args[1]) or args[1]
    if not target then return reply(src, 'info', 'vip.cmd.revoke_usage') end
    local ok = exports.bs_vip:RevokeVIP(target)
    reply(src, ok and 'success' or 'warn', ok and 'vip.cmd.revoked' or 'vip.cmd.unknown')
end, false)

-- /grantappearance <id> [count] - staff gift, works for anyone.
RegisterCommand('grantappearance', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') and not IsPlayerAceAllowed(src, 'bs.superadmin') then return end
    local target = tonumber(args[1]) or args[1]
    if not target then return reply(src, 'info', 'vip.cmd.ticket_usage') end
    local ok = grantTicket(target, args[2])
    reply(src, ok and 'success' or 'warn', ok and 'vip.cmd.ticket_granted' or 'vip.cmd.unknown')
    if ok and type(target) == 'number' and GetPlayerName(target) then
        notify(target, 'success', Lp(target, 'vip.got_ticket'))
    end
end, false)

-- F1 toggle: re-sync everyone when the owner flips VIP on/off
local lastOff = Vip.Disabled()
AddEventHandler('bs_config:changed:bs_vip', function()
    if Vip.Disabled() == lastOff then return end
    lastOff = Vip.Disabled()
    print(('[bs_vip] VIP system %s'):format(lastOff and 'disabled - all perks open to everyone' or 'enabled'))
    for src in pairs(state) do pushSync(src) end
end)

exports('Enabled', function() return not Vip.Disabled() end)

exports.bs_core:RegisterModule('vip', { side = 'server', version = '2.0.0', ready = true })
