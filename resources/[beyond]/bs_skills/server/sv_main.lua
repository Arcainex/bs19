-- bs_skills - skill XP, levels and perks, persisted per character.
-- The server owns every number. Clients can ask for their state and to spend a point, never to set values. Perk effects that need local natives (weapon damage, drain rates, walker detection) are mirrored to the owning client after every change and re-sent on load.
-- Tables: bs_character_skills (one row per skill), bs_character_perks (one row per unlocked perk).

local State = {}        -- [src] = { charId, skills = {}, perks = {}, dirty }

--------------------------------------------------------------------------------
-- Load / save
--------------------------------------------------------------------------------

local function blankSkills()
    local out = {}
    for treeId in pairs(Skills.Trees) do out[treeId] = { level = 0, xp = 0 } end
    return out
end

local function load(src, charId)
    local entry = { charId = charId, skills = blankSkills(), perks = {}, dirty = false }

    local rows = exports.oxmysql:query_async(
        'SELECT `skill`, `level`, `xp` FROM `bs_character_skills` WHERE `character_id` = ?',
        { charId }) or {}

    for _, row in ipairs(rows) do
        if entry.skills[row.skill] then
            entry.skills[row.skill] = { level = row.level or 0, xp = row.xp or 0 }
        end
    end

    local perks = exports.oxmysql:query_async(
        'SELECT `perk`, `rank` FROM `bs_character_perks` WHERE `character_id` = ?',
        { charId }) or {}

    for _, row in ipairs(perks) do entry.perks[row.perk] = row.rank or 1 end

    State[src] = entry
    return entry
end

local function persistSkill(charId, treeId, data)
    exports.oxmysql:execute_async([[
        INSERT INTO `bs_character_skills` (`character_id`, `skill`, `level`, `xp`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `level` = VALUES(`level`), `xp` = VALUES(`xp`)
    ]], { charId, treeId, data.level, data.xp })
end

local function persistPerk(charId, perkId, rank)
    exports.oxmysql:execute_async([[
        INSERT INTO `bs_character_perks` (`character_id`, `perk`, `rank`)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE `rank` = VALUES(`rank`)
    ]], { charId, perkId, rank })
end

--------------------------------------------------------------------------------
-- Mirroring to the owning client
--------------------------------------------------------------------------------

--- Everything the client needs to apply perk effects locally.
local function effectsFor(entry)
    local out = {
        weaponDamage = 0.0, meleeDamage = 0.0,
        hungerRate = 0.0, thirstRate = 0.0, stealth = 0.0,
        flags = {},
    }

    for treeId, tree in pairs(Skills.Trees) do
        for perkId, perk in pairs(tree.perks or {}) do
            if entry.perks[perkId] and not perk.pending then
                local effect = perk.effect or {}
                out.weaponDamage = out.weaponDamage + (effect.weaponDamage or 0.0)
                out.meleeDamage  = out.meleeDamage  + (effect.meleeDamage or 0.0)
                out.hungerRate   = out.hungerRate   + (effect.hungerRate or 0.0)
                out.thirstRate   = out.thirstRate   + (effect.thirstRate or 0.0)
                out.stealth      = out.stealth      + (effect.stealth or 0.0)
                if effect.flag then out.flags[effect.flag] = true end
            end
        end
    end

    return out
end

local function levelsFor(entry)
    local out = {}
    for treeId, data in pairs(entry.skills) do
        out[treeId] = data.level
    end
    return out
end

local function sync(src)
    local entry = State[src]
    if not entry then return end
    -- `points` is sent with the sync so the character sheet draws unspent points and trees from one payload, with no second request that could arrive stale.
    local points = 0
    pcall(function() points = exports.bs_core:GetSkillPoints(src) or 0 end)

    TriggerClientEvent('bs:skills:sync', src, {
        levels  = levelsFor(entry),
        perks   = entry.perks,
        effects = effectsFor(entry),
        points  = points,
    })
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

AddEventHandler('bs:hook:player:loaded', function(player)
    if not player or not player.source then return end
    local src = player.source
    CreateThread(function()
        load(src, player.charId)
        sync(src)
    end)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if not player or not player.source then return end
    State[player.source] = nil
end)

AddEventHandler('playerDropped', function()
    State[source] = nil
end)

-- A resource restart does not replay the player-loaded hook, so rehydrate every connected survivor. Keeps F5 -> Skills working after a restart.
CreateThread(function()
    Wait(750)
    for _, idText in ipairs(GetPlayers()) do
        local src = tonumber(idText)
        if src and not State[src] then
            local ok, player = pcall(function() return exports.bs_core:GetPlayer(src) end)
            if ok and player and player.charId then
                load(src, player.charId)
                sync(src)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- XP
--------------------------------------------------------------------------------

--- @param src number
--- @param treeId string
--- @param amount number
--- @return number levels gained
-- Tree and perk text in a player's language, config text as fallback.
local function skillText(src, key, fallback)
    local text = Lp(src, key)
    return text ~= key and text or fallback
end

local function addSkillXP(src, treeId, amount)
    local entry = State[src]
    if not entry then return 0 end

    local tree = Skills.Trees[treeId]
    if not tree then return 0 end

    amount = math.min(math.floor(tonumber(amount) or 0), Skills.Settings.maxXpPerGrant)
    if amount <= 0 then return 0 end

    local data = entry.skills[treeId]
    local gained = Skills.Math.Apply(treeId, data, amount)

    persistSkill(entry.charId, treeId, data)

    TriggerClientEvent('bs:skills:xp', src, treeId, data.xp,
        Skills.Math.ToNext(treeId, data.level), data.level, amount)

    if gained > 0 then
        -- A skill level is a real event: it may have just unlocked a perk.
        TriggerClientEvent('bs:ui:notify', src, {
            type = 'success',
            message = Lp(src, 'skill.level_up', { tree = skillText(src, 'tree.' .. treeId, tree.label), level = data.level }),
            duration = 3200,
        })

        -- Played from the server, since only the server knows a level was gained. A toast alone is too weak for a level up.
        TriggerClientEvent('bs:skills:levelUp', src, treeId, data.level, tree.label)

        sync(src)
    end

    return gained
end

exports('AddSkillXP', addSkillXP)

--------------------------------------------------------------------------------
-- Reads, for other resources
--------------------------------------------------------------------------------

exports('GetSkillLevel', function(src, treeId)
    local entry = State[src]
    if not entry or not entry.skills[treeId] then return 0 end
    return entry.skills[treeId].level
end)

exports('HasPerk', function(src, perkId)
    local entry = State[src]
    if not entry then return false end
    if not entry.perks[perkId] then return false end

    -- A pending perk is owned but does nothing, and says so.
    for _, tree in pairs(Skills.Trees) do
        local perk = tree.perks and tree.perks[perkId]
        if perk then return not perk.pending end
    end
    return false
end)

--- Extra loot draws, read by bs_interactions and bs_zombies.
exports('LootBonus', function(src)
    local entry = State[src]
    if not entry then return 0 end

    local bonus = 0
    for _, tree in pairs(Skills.Trees) do
        for perkId, perk in pairs(tree.perks or {}) do
            if entry.perks[perkId] and not perk.pending then
                bonus = bonus + ((perk.effect or {}).lootRolls or 0)
            end
        end
    end
    return bonus
end)

-- Never send infinity to the client: Skills.Math.ToNext returns math.huge for a maxed tree, and JSON cannot represent it, so SEND_NUI_MESSAGE fails for the whole payload (rapidjson error 3).
-- So xpToNext is nil (key absent) at max level. app.js already guards with isFinite(s.xpToNext) and draws a full bar. Do not use false as a sentinel: isFinite(false) is true in JS.
-- Same for NaN from divisions.
local function jsonSafeNumber(n)
    if type(n) ~= 'number' then return n end
    -- n ~= n is true only for NaN; the comparisons catch both infinities.
    if n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-- What the hub shows. Plain data only, no functions cross this boundary.
local function getSkills(src)
    local entry = State[src]
    if not entry then return nil end

    local out = {}
    for treeId, tree in pairs(Skills.Trees) do
        local data = entry.skills[treeId]
        out[treeId] = {
            id       = treeId,
            label    = skillText(src, 'tree.' .. treeId, tree.label),
            blurb    = skillText(src, 'tree.' .. treeId .. '.blurb', tree.blurb),
            level    = data.level,
            maxLevel = tree.maxLevel or 20,
            xp       = data.xp,
            xpToNext = jsonSafeNumber(Skills.Math.ToNext(treeId, data.level)),
            perks    = Skills.Math.PerkList(treeId, data.level, entry.perks),
        }
        for _, p in ipairs(out[treeId].perks) do
            p.label = skillText(src, 'perk.' .. p.id, p.label)
            p.description = skillText(src, 'perk.' .. p.id .. '.desc', p.description)
        end
    end
    return out
end

exports('GetSkills', getSkills)

--- bs_core asks this before paying out any action.
exports('RewardMultiplier', function(src, actionId)
    local entry = State[src]
    if not entry then return 1.0 end

    local multiplier = 1.0

    -- Levels in the matching skill pay a little more.
    local treeId = Skills.ActionSkill[actionId]
    if treeId and entry.skills[treeId] then
        local bonus = math.min(entry.skills[treeId].level * Skills.LevelBonus.perLevel,
                               Skills.LevelBonus.max)
        multiplier = multiplier + bonus
    end

    -- Flat XP perks apply to everything.
    for _, tree in pairs(Skills.Trees) do
        for perkId, perk in pairs(tree.perks or {}) do
            if entry.perks[perkId] and not perk.pending then
                multiplier = multiplier + ((perk.effect or {}).xpBonus or 0.0)
            end
        end
    end

    return multiplier
end)

--------------------------------------------------------------------------------
-- Spending points
--------------------------------------------------------------------------------

-- Reserve the unlock synchronously with a per-entry pendingUnlock marker before the yielding SpendSkillPoints call, so a double-click or back-to-back request cannot pay twice. Cleared on every exit path so a real retry is never blocked.
BSB.RegisterCallback('skills:unlock', function(src, treeId, perkId)
    local entry = State[src]
    if not entry then return { ok = false, error = 'not loaded' } end

    local tree = Skills.Trees[treeId]
    local perk = tree and tree.perks and tree.perks[perkId]
    if not perk then return { ok = false, error = 'no such perk' } end

    if entry.perks[perkId] then return { ok = false, error = 'already unlocked' } end

    entry.pendingUnlock = entry.pendingUnlock or {}
    if entry.pendingUnlock[perkId] then return { ok = false, error = 'already unlocked' } end

    if perk.needsPerk and not entry.perks[perk.needsPerk] then
        local prev = tree.perks[perk.needsPerk]
        return { ok = false, error = Lp(src, 'skill.needs_perk', { perk = skillText(src, 'perk.' .. perk.needsPerk, prev and prev.label or perk.needsPerk) }) }
    end

    local level = entry.skills[treeId].level
    if level < (perk.requires or 0) then
        return { ok = false, error = Lp(src, 'skill.needs_level', { tree = skillText(src, 'tree.' .. treeId, tree.label), level = perk.requires }) }
    end

    -- Reserve synchronously, before the yield, so a second request for the same perk sees the marker.
    entry.pendingUnlock[perkId] = true

    -- The points live on the character row, so bs_core does the spending.
    local ok, paid = pcall(function() return exports.bs_core:SpendSkillPoints(src, perk.cost or 1) end)
    if not ok or not paid then
        entry.pendingUnlock[perkId] = nil
        return { ok = false, error = Lp(src, 'skill.no_points') }
    end

    -- Re-fetch: State[src] may have been torn down (disconnect, character unload) while the spend call was suspended.
    entry = State[src]
    if not entry then return { ok = false, error = 'not loaded' } end

    entry.perks[perkId] = 1
    if entry.pendingUnlock then entry.pendingUnlock[perkId] = nil end
    persistPerk(entry.charId, perkId, 1)
    sync(src)

    return { ok = true, perk = perkId, label = perk.label, pending = perk.pending or false }
end)

-- Spend a point on training instead of a perk, so an unspent point is useful at level 1 when every perk is still locked.
BSB.RegisterCallback('skills:train', function(src, treeId)
    if not Skills.Training.enabled then return { ok = false, error = 'training is disabled' } end

    local entry = State[src]
    if not entry then return { ok = false, error = 'not loaded' } end

    local tree = Skills.Trees[treeId]
    if not tree then return { ok = false, error = 'unknown skill' } end

    local data = entry.skills[treeId]
    if data.level >= (tree.maxLevel or 20) then
        return { ok = false, error = ('%s is already at the cap.'):format(tree.label) }
    end

    local paid = exports.bs_core:SpendSkillPoints(src, Skills.Training.cost or 1)
    if not paid then return { ok = false, error = Lp(src, 'skill.no_points') } end

    local needed = Skills.Math.ToNext(treeId, data.level)
    local granted = math.max(1, math.floor(needed * (Skills.Training.levels or 1.0)))

    -- Goes through Apply so levels roll over exactly like earned XP.
    local gained = Skills.Math.Apply(treeId, data, granted)
    persistSkill(entry.charId, treeId, data)
    sync(src)

    TriggerClientEvent('bs:skills:xp', src, treeId, data.xp,
        Skills.Math.ToNext(treeId, data.level), data.level, granted)

    return { ok = true, level = data.level, gained = gained, label = tree.label }
end)

BSB.RegisterCallback('skills:list', function(src)
    local entry = State[src]
    if not entry then return { ok = false } end
    return {
        ok = true,
        points = exports.bs_core:GetSkillPoints(src),
        skills = getSkills(src),
    }
end)

-- Respec: wipes perks and refunds points. Costs Skills.Settings.respecXpCost via bs_core's SpendXP first; if the player cannot afford it, nothing is wiped or refunded.
BSB.RegisterCallback('skills:respec', function(src)
    if not Skills.Settings.allowRespec then return { ok = false, error = 'disabled' } end

    local entry = State[src]
    if not entry then return { ok = false } end

    local refund = 0
    for perkId in pairs(entry.perks) do
        for _, tree in pairs(Skills.Trees) do
            local perk = tree.perks and tree.perks[perkId]
            if perk then refund = refund + (perk.cost or 1) end
        end
    end

    if refund == 0 then return { ok = false, error = Lp(src, 'skill.nothing_undo') } end

    local cost = Skills.Settings.respecXpCost or 0
    if cost > 0 and not exports.bs_core:SpendXP(src, cost) then
        return { ok = false, error = Lp(src, 'skill.respec_xp', { n = cost }) }
    end

    exports.oxmysql:execute_async('DELETE FROM `bs_character_perks` WHERE `character_id` = ?',
        { entry.charId })

    entry.perks = {}
    exports.bs_core:GrantSkillPoints(src, refund)
    sync(src)

    return { ok = true, refunded = refund, xpSpent = cost }
end)

-- Staff surface, driven by the admin menu. Bypasses level requirements and point costs so staff can test perks. Only reachable through bs_admin's ACE check.

exports('SetSkillLevel', function(src, treeId, level)
    local entry = State[src]
    if not entry then return false, 'that character is not loaded' end

    local tree = Skills.Trees[treeId]
    if not tree then return false, 'unknown skill' end

    level = math.max(0, math.min(math.floor(tonumber(level) or 0), tree.maxLevel or 20))

    entry.skills[treeId] = { level = level, xp = 0 }
    persistSkill(entry.charId, treeId, entry.skills[treeId])
    sync(src)

    TriggerClientEvent('bs:skills:xp', src, treeId, 0,
        Skills.Math.ToNext(treeId, level), level, 0)
    return true
end)

exports('GrantPerk', function(src, perkId)
    local entry = State[src]
    if not entry then return false, 'that character is not loaded' end

    local found
    for _, tree in pairs(Skills.Trees) do
        if tree.perks and tree.perks[perkId] then found = tree.perks[perkId] end
    end
    if not found then return false, 'unknown perk' end
    if entry.perks[perkId] then return false, 'already has it' end

    entry.perks[perkId] = 1
    persistPerk(entry.charId, perkId, 1)
    sync(src)
    return true
end)

exports('RevokePerk', function(src, perkId)
    local entry = State[src]
    if not entry then return false, 'that character is not loaded' end
    if not entry.perks[perkId] then return false, 'they do not have it' end

    entry.perks[perkId] = nil
    exports.oxmysql:execute_async(
        'DELETE FROM `bs_character_perks` WHERE `character_id` = ? AND `perk` = ?',
        { entry.charId, perkId })
    sync(src)
    return true
end)

-- Wipes every perk and refunds points even when there is nothing to undo, so staff can reset a test character.
exports('ForceRespec', function(src)
    local entry = State[src]
    if not entry then return 0 end

    local refund = 0
    for perkId in pairs(entry.perks) do
        for _, tree in pairs(Skills.Trees) do
            local perk = tree.perks and tree.perks[perkId]
            if perk then refund = refund + (perk.cost or 1) end
        end
    end

    exports.oxmysql:execute_async('DELETE FROM `bs_character_perks` WHERE `character_id` = ?',
        { entry.charId })
    entry.perks = {}

    if refund > 0 then exports.bs_core:GrantSkillPoints(src, refund) end
    sync(src)
    return refund
end)

--- Every perk that exists, for the staff menu's list.
exports('PerkCatalogue', function()
    local out = {}
    for treeId, tree in pairs(Skills.Trees) do
        for perkId, perk in pairs(tree.perks or {}) do
            out[#out + 1] = {
                id = perkId, tree = treeId, label = perk.label,
                requires = perk.requires, cost = perk.cost or 1,
                pending = perk.pending or false,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.tree ~= b.tree then return a.tree < b.tree end
        return (a.requires or 0) < (b.requires or 0)
    end)
    return out
end)

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

RegisterCommand('skillxp', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    local target = tonumber(args[1])
    local tree   = args[2]
    local amount = tonumber(args[3])
    if not target or not tree or not amount then
        return print('usage: skillxp <playerId> <combat|survival|crafting|medical|lockpicking> <xp>')
    end
    addSkillXP(target, tree, amount)
    print(('^2[BS SKILLS]^7 gave %d %s xp to %d'):format(amount, tree, target))
end, false)

exports.bs_core:RegisterModule('skills', { side = 'server', version = '1.0.0', ready = true })
