-- bs_weapons - server side attachments and ammo

local Legacy = {}    -- [src] = { [weapon] = { slot = attachmentId } }
local Active = {}    -- [src] = { [weapon] = serial }, the item last drawn for that weapon
local ItemNames = {} -- [weapon] = inventory item name

-- Saved ammo: kept in the same bs_character_weapons row (see 012_weapon_ammo.sql) and given back
local Ammo = {}       -- [src] = { [weapon] = rounds }
local Charmap = {}    -- [src] = charId, so a report can be persisted without a round trip
local MagReturn = {}  -- [src] = one-shot allowance after an extended mag is removed

-- Load / save

local function load(src, charId)
    local rows = exports.oxmysql:query_async(
        'SELECT `weapon`, `attachments`, `ammo` FROM `bs_character_weapons` WHERE `character_id` = ?',
        { charId }) or {}

    local out, ammo = {}, {}
    for _, row in ipairs(rows) do
        local ok, decoded = pcall(json.decode, row.attachments or '{}')
        out[row.weapon] = (ok and type(decoded) == 'table') and decoded or {}
        ammo[row.weapon] = tonumber(row.ammo) or 0
    end

    for weapon, set in pairs(out) do
        if next(set) == nil then out[weapon] = nil end
    end

    Legacy[src] = out
    Ammo[src] = ammo
    return out, ammo
end

-- Ammo only. Attachments live on the item now; the old column is left alone here.
local function persist(charId, weapon, _, ammo)
    exports.oxmysql:execute_async([[
        INSERT INTO `bs_character_weapons` (`character_id`, `weapon`, `attachments`, `ammo`)
        VALUES (?, ?, '{}', ?)
        ON DUPLICATE KEY UPDATE `ammo` = VALUES(`ammo`)
    ]], { charId, weapon, math.floor(tonumber(ammo) or 0) })
end

local function clearLegacy(charId, weapon)
    exports.oxmysql:execute_async(
        "UPDATE `bs_character_weapons` SET `attachments` = '{}' WHERE `character_id` = ? AND `weapon` = ?",
        { charId, weapon })
end

local function copySet(t)
    local out = {}
    if type(t) == 'table' then for k, v in pairs(t) do out[k] = v end end
    return out
end

local function itemFor(weapon)
    if ItemNames[weapon] == nil then
        local ok, name = pcall(function() return exports.bs_inventory:ItemForWeapon(weapon) end)
        ItemNames[weapon] = (ok and name) or false
    end
    return ItemNames[weapon] or nil
end

local serialCounter = 0
local function newSerial()
    serialCounter = (serialCounter + 1) % 0xFFFF
    return ('%x%04x%04x'):format(os.time(), serialCounter, math.random(0, 0xFFFF))
end

-- The weapon item this player means for weapon: the one last drawn, else the first one held
local function instance(src, weapon)
    local item = itemFor(weapon)
    if not item then return nil end
    local ok, list = pcall(function() return exports.bs_inventory:ItemMetaList(src, item) end)
    if not ok or type(list) ~= 'table' or #list == 0 then return nil end

    local want = Active[src] and Active[src][weapon]
    local pick = list[1]
    if want then
        for _, e in ipairs(list) do
            if e.metadata.serial == want then pick = e break end
        end
    end

    local meta, dirty = pick.metadata, false
    if not meta.serial then meta.serial = newSerial(); dirty = true end
    if meta.attachments == nil then
        local old = Legacy[src] and Legacy[src][weapon]
        meta.attachments = copySet(old)
        dirty = true
        if old then
            Legacy[src][weapon] = nil
            if Charmap[src] then clearLegacy(Charmap[src], weapon) end
        end
    end
    if dirty then exports.bs_inventory:SetItemMeta(src, pick.slot, item, meta, true) end

    Active[src] = Active[src] or {}
    Active[src][weapon] = meta.serial
    return pick.slot, item, meta
end

-- What is fitted on the gun in question. A copy; write back with saveFitted.
local function forWeapon(src, weapon)
    local _, _, meta = instance(src, weapon)
    return copySet(meta and meta.attachments)
end

local function saveFitted(src, weapon, set)
    local slot, item, meta = instance(src, weapon)
    if not slot then return false end
    meta.attachments = copySet(set)
    return exports.bs_inventory:SetItemMeta(src, slot, item, meta, true)
end

-- Old saved parts go onto the guns the character holds right now
local function migrate(src)
    local set = Legacy[src]
    if not set then return end
    for weapon in pairs(set) do
        if not instance(src, weapon) then
            set[weapon] = nil
            if Charmap[src] then clearLegacy(Charmap[src], weapon) end
        end
    end
end

-- Lifecycle

AddEventHandler('bs:hook:player:loaded', function(player)
    if not player or not player.source then return end
    Charmap[player.source] = player.charId
    CreateThread(function()
        local _, ammo = load(player.source, player.charId)
        pcall(migrate, player.source)
        TriggerClientEvent('bs:weapons:sync', player.source, {}, ammo)
    end)
end)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source then
        Legacy[player.source] = nil
        Active[player.source] = nil
        Ammo[player.source] = nil
        Charmap[player.source] = nil
    end
end)

AddEventHandler('playerDropped', function()
    MagReturn[source] = nil
    Legacy[source] = nil
    Active[source] = nil
    Ammo[source] = nil
    Charmap[source] = nil
end)

-- Ammo lives on the ped (client only), so the client reports it
RegisterNetEvent('bs:weapons:reportAmmo', function(weapon, rounds)
    local src = source
    if type(weapon) ~= 'string' or #weapon > 48 then return end

    rounds = tonumber(rounds)
    -- A magazine that big is not ammo, it is a report worth ignoring.
    if not rounds or rounds < 0 or rounds > 999 then return end

    local charId = Charmap[src]
    if not charId then return end

    Ammo[src] = Ammo[src] or {}
    Ammo[src][weapon] = math.floor(rounds)

    persist(charId, weapon, nil, rounds)
end)

exports('SavedAmmo', function(src, weapon) return Ammo[src] and Ammo[src][weapon] end)

-- Sets the saved ammo count
exports('SetSavedAmmo', function(src, weapon, rounds)
    if type(weapon) ~= 'string' or #weapon > 48 then return false end

    rounds = tonumber(rounds)
    if not rounds or rounds < 0 or rounds > 999 then return false end
    rounds = math.floor(rounds)

    local charId = Charmap[src]
    if not charId then return false end

    Ammo[src] = Ammo[src] or {}
    Ammo[src][weapon] = rounds

    persist(charId, weapon, nil, rounds)
    return true
end)

-- Fitting and removing

local function attachmentFor(id)
    return Weapons.Attachments[id]
end

-- Attachment counts come from the server
BSB.RegisterCallback('weapons:state', function(src, weapon)
    if type(weapon) ~= 'string' then return { ok = false } end

    local counts = {}
    for _, att in pairs(Weapons.Attachments) do
        if att.item and counts[att.item] == nil then
            local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, att.item) end)
            counts[att.item] = (ok and tonumber(n)) or 0
        end
    end

    return { ok = true, fitted = forWeapon(src, weapon), counts = counts }
end)

-- Cheap version for the client's weapon-change refit: just what is on the gun in hand.
BSB.RegisterCallback('weapons:fitted', function(src, weapon)
    if type(weapon) ~= 'string' or #weapon > 48 then return { ok = false } end
    return { ok = true, fitted = forWeapon(src, weapon) }
end)

-- bs_inventory calls this when a weapon item is drawn (use or hotbar), so the right gun's parts are used
exports('SetActive', function(src, weapon, slot)
    if type(weapon) ~= 'string' then return end
    local item = itemFor(weapon)
    if not item then return end
    local ok, list = pcall(function() return exports.bs_inventory:ItemMetaList(src, item) end)
    if not ok or type(list) ~= 'table' then return end
    slot = tonumber(slot)
    for _, e in ipairs(list) do
        if e.slot == slot then
            if not e.metadata.serial then
                e.metadata.serial = newSerial()
                exports.bs_inventory:SetItemMeta(src, e.slot, item, e.metadata, true)
            end
            Active[src] = Active[src] or {}
            Active[src][weapon] = e.metadata.serial
            instance(src, weapon)
            return
        end
    end
end)

BSB.RegisterCallback('weapons:fit', function(src, weapon, attachmentId)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = 'no character' } end

    if type(weapon) ~= 'string' or #weapon > 48 then return { ok = false, error = 'bad weapon' } end

    local att = attachmentFor(attachmentId)
    if not att then return { ok = false, error = 'unknown attachment' } end

    -- Does this attachment exist for this weapon? The client checks too, this is the authority.
    local component = att.components and att.components[weapon]
    if not component then return { ok = false, error = Lp(src, 'wp.no_fit') } end

    local fitted = forWeapon(src, weapon)
    if fitted[att.slot] then
        return { ok = false, error = Lp(src, 'wp.slot_taken') }
    end

    if exports.bs_inventory:CountItem(src, att.item) < 1 then
        return { ok = false, error = Lp(src, 'wp.no_part', { name = att.label }) }
    end
    if not exports.bs_inventory:RemoveItem(src, att.item, 1) then
        return { ok = false, error = 'could not take the part' }
    end

    fitted[att.slot] = attachmentId
    if not saveFitted(src, weapon, fitted) then
        exports.bs_inventory:GiveItem(src, att.item, 1)
        return { ok = false, error = Lp(src, 'wp.not_carrying') }
    end

    return { ok = true, component = component, slot = att.slot, label = att.label }
end)

BSB.RegisterCallback('weapons:remove', function(src, weapon, slot)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = 'no character' } end

    local fitted = forWeapon(src, weapon)
    local attachmentId = fitted[slot]
    if not attachmentId then return { ok = false, error = 'nothing there' } end

    local att = attachmentFor(attachmentId)
    if not att then
        -- Config changed under a saved value
        fitted[slot] = nil
        saveFitted(src, weapon, fitted)
        return { ok = true, component = nil }
    end

    -- Give the item back before recording the removal: a full bag keeps it on the gun.
    local given = exports.bs_inventory:GiveItem(src, att.item, 1)
    if not given then return { ok = false, error = Lp(src, 'wp.no_room') } end

    -- Mag came off: allow one ammo return for the rounds that no longer fit.
    local oldMag = Weapons.MagSizeFor(weapon, fitted)
    fitted[slot] = nil
    saveFitted(src, weapon, fitted)
    if slot == 'mag' then
        local newMag = Weapons.MagSizeFor(weapon, fitted)
        if oldMag and newMag and oldMag > newMag then
            MagReturn[src] = { weapon = weapon, max = oldMag, at = os.time() }
        end
    end

    return { ok = true, component = att.components and att.components[weapon],
             slot = slot, label = att.label }
end)

-- Magazines

-- Ammo item + rounds per box for a weapon name.
local function ammoBox(weapon)
    local m = Weapons.Magazines[weapon]
    local item = m and m.ammo
    if not item and GetResourceState('bs_inventory') == 'started' then
        item = exports.bs_inventory:AmmoItemFor(weapon)
    end
    if not item then return nil end
    local def = exports.bs_inventory:GetItem(item)
    local per = def and def.data and tonumber(def.data.rounds)
    if not per or per < 1 then return nil end
    return item, per, def.label
end

-- Hash to name from the magazine table, for callers that only have the ped
local MagHashes = {}
for name in pairs(Weapons.Magazines) do MagHashes[GetHashKey(name)] = name end

-- Ammo info for a weapon (name or hash). current = mag size with this player's fitted parts
exports('MagInfo', function(src, weapon)
    if type(weapon) == 'number' then weapon = MagHashes[weapon] end
    if type(weapon) ~= 'string' then return nil end
    local m = Weapons.Magazines[weapon]
    local item, per, label = ammoBox(weapon)
    if not m or not item then return nil end
    local fitted = src and forWeapon(src, weapon)
    return {
        weapon = weapon, base = m.base, ext = m.ext, drum = m.drum,
        current = Weapons.MagSizeFor(weapon, fitted) or m.base,
        ammoItem = item, boxRounds = per, ammoLabel = label,
    }
end)

exports('MagSize', function(src, weapon)
    local fitted = src and forWeapon(src, weapon)
    return Weapons.MagSizeFor(weapon, fitted)
end)

-- After an extended mag comes off, rounds that no longer fit go back to the bag as whole boxes
BSB.RegisterCallback('weapons:returnAmmo', function(src, weapon, rounds)
    local allow = MagReturn[src]
    MagReturn[src] = nil
    if not allow or allow.weapon ~= weapon or os.time() - allow.at > 30 then
        return { ok = false }
    end

    rounds = math.floor(tonumber(rounds) or 0)
    rounds = math.min(rounds, allow.max)
    local saved = Ammo[src] and Ammo[src][weapon]
    if saved then rounds = math.min(rounds, saved) end

    local item, per = ammoBox(weapon)
    if not item or rounds < per then return { ok = true, rounds = 0 } end

    local boxes = math.floor(rounds / per)
    if not exports.bs_inventory:GiveItem(src, item, boxes) then
        return { ok = false, error = 'no room' }
    end

    if saved then
        Ammo[src][weapon] = saved - boxes * per
        local charId = Charmap[src]
        if charId then persist(charId, weapon, nil, Ammo[src][weapon]) end
    end
    return { ok = true, rounds = boxes * per }
end)

-- Noise: a suppressed shot is quieter, and noise is what walkers hunt by.

exports('NoiseScale', function(src, weapon)
    local fitted = forWeapon(src, weapon)

    local scale = 1.0
    for _, attachmentId in pairs(fitted) do
        local effect = Weapons.Effects[attachmentId]
        if effect and effect.noiseScale then scale = scale * effect.noiseScale end
    end
    return scale
end)

exports('Fitted', function(src, weapon) return forWeapon(src, weapon) end)

-- Attachments that fit a weapon, as items, for the staff menu
exports('AttachmentsFor', function(weapon)
    if type(weapon) ~= 'string' then return {} end

    local out = {}
    for id, att in pairs(Weapons.Attachments) do
        local component = att.components and att.components[weapon]
        if component then
            out[#out + 1] = {
                id = id, item = att.item, label = att.label,
                slot = att.slot, component = component,
            }
        end
    end

    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end)

-- Staff

RegisterCommand('weaponinfo', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end

    local target = tonumber(args[1]) or src
    print(('^5[BS WEAPONS]^7 %s:'):format(GetPlayerName(target) or target))
    for weapon, serial in pairs(Active[target] or {}) do
        local slots = forWeapon(target, weapon)
        local parts = {}
        for slot, id in pairs(slots) do parts[#parts + 1] = ('%s=%s'):format(slot, id) end
        print(('   %-24s #%s %s'):format(weapon, tostring(serial), table.concat(parts, ' ')))
    end
end, false)

exports.bs_core:RegisterModule('weapons', { side = 'server', version = '1.0.0', ready = true })
