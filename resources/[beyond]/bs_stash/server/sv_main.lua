-- bs_stash - server side.
-- Only the owner knows where a stash is: a player is only sent their own stashes (the list never leaves the server otherwise), and a stranger can only ask "is anything buried where I stand", with a shovel, at most once a second. Contents are a normal inventory container owned by 'stash:<id>', so weight, moves and persistence use the same code as any other container.

local S = Stash.Settings

--- [id] = { id, owner, label, x, y, z }
local stashes = {}

local function containerFor(id) return ('stash:%d'):format(id) end

local function charIdOf(src)
    local player = exports.bs_core:GetPlayer(src)
    return player and player.charId or nil
end

-- Faction skills stash_slots/stash_slots2 add slots. Fails open to the base size.
local function bonusSlots(src)
    if GetResourceState('bs_factions') ~= 'started' then return 0 end
    local ok, n = pcall(function()
        local s = exports.bs_factions:GetFactionSummary(tonumber(src))
        if type(s) ~= 'table' or not s.factionId then return 0 end
        return (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'stash_slots')) or 0)
             + (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'stash_slots2')) or 0)
    end)
    return ok and math.floor(tonumber(n) or 0) or 0
end

-- Size never shrinks while the server runs, so nothing ends up past the last slot.
local function sizeFor(stash, src)
    local size = S.size
    if src and stash.owner == charIdOf(src) then size = S.size + bonusSlots(src) end
    stash.size = math.max(stash.size or S.size, size)
    return stash.size
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

CreateThread(function()
    if not S.enabled then return end
    Wait(3000)          -- after bs_core's migrations have run

    local rows = exports.oxmysql:query_async('SELECT * FROM `bs_stashes`', {}) or {}
    for _, row in ipairs(rows) do
        stashes[row.id] = {
            id = row.id, owner = row.owner_character_id, label = row.label,
            x = row.x + 0.0, y = row.y + 0.0, z = row.z + 0.0,
        }
    end

    local n = 0
    for _ in pairs(stashes) do n = n + 1 end
    print(('^2[BeyondSurvival]^7 (stash) %d buried stash(es) loaded'):format(n))
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function distance(a, x, y, z)
    local dx, dy, dz = a.x - x, a.y - y, a.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function hasShovel(src)
    if not S.tool then return true end
    local ok, count = pcall(function()
        return exports.bs_inventory:CountItem(src, S.tool)
    end)
    return ok and (tonumber(count) or 0) >= 1
end

local function wearShovel(src)
    if not S.tool or not S.toolWear or S.toolWear <= 0 then return false end
    local ok, _, broke = pcall(function()
        return exports.bs_inventory:WearItem(src, S.tool, S.toolWear)
    end)
    return ok and broke or false
end

local function ownedBy(charId)
    local out = {}
    for _, stash in pairs(stashes) do
        if stash.owner == charId then out[#out + 1] = stash end
    end
    return out
end

-- The stash nearest a point, whoever owns it.
local function nearest(x, y, z, within)
    local best, bestDist
    for _, stash in pairs(stashes) do
        local d = distance(stash, x, y, z)
        if d <= within and (not bestDist or d < bestDist) then best, bestDist = stash, d end
    end
    return best, bestDist
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--------------------------------------------------------------------------------
-- Burying
--------------------------------------------------------------------------------

BSB.RegisterCallback('stash:bury', function(src, label)
    if not S.enabled then return { ok = false, error = Lp(src, 'st.off') } end

    local charId = charIdOf(src)
    if not charId then return { ok = false, error = 'no character' } end

    if not hasShovel(src) then return { ok = false, error = Lp(src, 'st.need_shovel') } end

    if #ownedBy(charId) >= (S.maxPerCharacter or 5) then
        return { ok = false,
                 error = ('You already have %d buried. Dig one up first.')
                     :format(S.maxPerCharacter or 5) }
    end

    local at = pedCoords(src)
    if not at then return { ok = false } end

    -- Not on top of another hole, anybody's.
    local clash = nearest(at.x, at.y, at.z, S.minSpacing or 4.0)
    if clash then
        return { ok = false, error = Lp(src, 'st.already_dug') }
    end

    label = type(label) == 'string' and label:sub(1, 40):gsub('[%c]', '') or ''
    if label == '' then label = Lp(src, 'st.default_label') end

    local id = exports.oxmysql:insert_async([[
        INSERT INTO `bs_stashes` (`owner_character_id`, `label`, `x`, `y`, `z`)
        VALUES (?, ?, ?, ?, ?)
    ]], { charId, label, at.x, at.y, at.z })

    if not id then return { ok = false, error = Lp(src, 'st.wouldnt_take') } end

    stashes[id] = { id = id, owner = charId, label = label,
                    x = at.x + 0.0, y = at.y + 0.0, z = at.z + 0.0 }

    exports.bs_inventory:RegisterContainer(containerFor(id), {
        size = sizeFor(stashes[id], src), maxWeight = S.maxWeight, label = label,
    })

    local broke = wearShovel(src)

    return { ok = true, id = id, label = label, broke = broke,
             coords = { x = at.x, y = at.y, z = at.z } }
end)

--------------------------------------------------------------------------------
-- Finding
--------------------------------------------------------------------------------

-- Everything this character buried. The only list that leaves the server, and only to its owner.
BSB.RegisterCallback('stash:mine', function(src)
    local charId = charIdOf(src)
    if not charId then return { ok = false } end

    local out = {}
    for _, stash in ipairs(ownedBy(charId)) do
        out[#out + 1] = { id = stash.id, label = stash.label,
                          x = stash.x, y = stash.y, z = stash.z }
    end

    return { ok = true, stashes = out, sight = S.ownerSight }
end)

-- VIP convenience (bs_vip 'stashName'): rename your own stash without digging it up. Anyone can still name a stash when burying it.
BSB.RegisterCallback('stash:rename', function(src, id, label)
    local charId = charIdOf(src)
    local stash = stashes[tonumber(id) or -1]
    if not charId or not stash or stash.owner ~= charId then return { ok = false, error = Lp(src, 'st.not_yours') } end

    local allowed = false
    if GetResourceState('bs_vip') == 'started' then
        pcall(function() allowed = exports.bs_vip:HasPerk(src, 'stashName') == true end)
    end
    if not allowed then return { ok = false, error = Lp(src, 'st.vip_rename') } end

    label = type(label) == 'string' and label:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 40) or ''
    if label == '' then return { ok = false, error = Lp(src, 'st.give_name') } end

    stash.label = label
    exports.oxmysql:execute_async('UPDATE `bs_stashes` SET `label` = ? WHERE `id` = ?', { label, stash.id })
    return { ok = true, label = label }
end)

-- "Is anything buried where I stand?" Uses the caller's own server-side position, within about a metre, rate limited per player, so it cannot be used to sweep an area.
local lastProbe = {}

BSB.RegisterCallback('stash:probe', function(src)
    if not S.enabled then return { ok = false } end

    local now = GetGameTimer()
    if (now - (lastProbe[src] or 0)) < ((S.probeInterval or 900) - 100) then
        return { ok = true, found = false }
    end
    lastProbe[src] = now

    if not hasShovel(src) then return { ok = true, found = false } end

    local at = pedCoords(src)
    if not at then return { ok = true, found = false } end

    local stash = nearest(at.x, at.y, at.z, S.strangerSight or 1.4)
    if not stash then return { ok = true, found = false } end

    -- Deliberately not the label or owner: a stranger sees disturbed earth until it is dug up.
    return { ok = true, found = true, id = stash.id,
             coords = { x = stash.x, y = stash.y, z = stash.z } }
end)

--------------------------------------------------------------------------------
-- Opening
--------------------------------------------------------------------------------

BSB.RegisterCallback('stash:open', function(src, id)
    if not S.enabled then return { ok = false } end

    local stash = stashes[tonumber(id) or -1]
    if not stash then return { ok = false, error = Lp(src, 'st.nothing') } end

    if not hasShovel(src) then return { ok = false, error = Lp(src, 'st.need_shovel') } end

    local at = pedCoords(src)
    if not at or distance(stash, at.x, at.y, at.z) > 3.0 then
        return { ok = false, error = Lp(src, 'st.too_far') }
    end

    local containerId = containerFor(stash.id)

    -- Registered at the moment of use with the real capacity, so a client cannot name its own container size (see bs_inventory's container registry).
    exports.bs_inventory:RegisterContainer(containerId, {
        size = sizeFor(stash, src), maxWeight = S.maxWeight, label = stash.label,
    }, src)  -- src grants this player the open; without it bs_inventory refuses

    wearShovel(src)

    TriggerClientEvent('bs:inventory:openContainer', src, containerId)
    return { ok = true, label = stash.label }
end)

-- Filling the hole in: only when empty and only by the owner. Emptiness is checked against the inventory itself so a stash with items in it is never deleted.
BSB.RegisterCallback('stash:fill', function(src, id)
    local stash = stashes[tonumber(id) or -1]
    if not stash then return { ok = false } end

    local charId = charIdOf(src)
    if not charId or stash.owner ~= charId then
        return { ok = false, error = Lp(src, 'st.not_yours2') }
    end

    local at = pedCoords(src)
    if not at or distance(stash, at.x, at.y, at.z) > 3.0 then
        return { ok = false, error = Lp(src, 'st.too_far') }
    end

    if exports.bs_inventory:ContainerHasItems(containerFor(stash.id)) then
        return { ok = false, error = Lp(src, 'st.empty_first') }
    end

    exports.oxmysql:update_async('DELETE FROM `bs_stashes` WHERE `id` = ?', { stash.id })
    stashes[stash.id] = nil

    return { ok = true }
end)

AddEventHandler('playerDropped', function() lastProbe[source] = nil end)

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

BSB.RegisterCommand('stashes', 'bs.admin', 'How many stashes are buried', {},
    function(src)
        local total = 0
        for _ in pairs(stashes) do total = total + 1 end

        local line = ('%d stash(es) buried across the map'):format(total)
        if src > 0 then
            TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = line })
        else print(line) end
    end)

exports.bs_core:RegisterModule('stash', { side = 'server', version = '0.1.0' })
