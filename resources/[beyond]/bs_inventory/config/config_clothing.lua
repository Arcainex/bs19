-- bs_inventory - clothing config.
-- Clothing is appearance (set at the wardrobe NPC, saved with the character), not items. Only the backpack and body armour are still items, since they carry capacity and protection. Other slots are kept as reserved positions, see `retired`.
-- Equipment slots are more slots of the same inventory (one store for stacking, durability, weight and persistence). Clothing.Slots is ORDERED: slot N is inventory slot (grid + bar + N) in the database. Append only; retire a slot in place instead of removing it.
-- `off` is the bare body drawable and differs between male and female models (standard freemode indices). It is data so a wrong index is a number change here.

Clothing = {}

-- Models we dress; anything else is left alone. Names, not backtick hash literals (FiveM-only syntax that breaks plain Lua checks); the hash is taken at runtime with GetHashKey.
Clothing.Models = {
    male   = 'mp_m_freemode_01',
    female = 'mp_f_freemode_01',
}

-- ORDERED: the index here is the database slot, do not remove or reorder.
-- `kind` is 'component' (worn, part of the body) or 'prop' (attached: hats, glasses, watches); different natives and numbering.
-- `retired = true` keeps a slot only to hold its position.
-- `ui` is the data-eq name of the frame in the panel; a slot without it works but is not drawn.
Clothing.Slots = {
    { id = 'mask',        label = 'Mask',        ui = 'mask',        kind = 'component', index = 1,  off = { male = 0,  female = 0  }, retired = true },
    { id = 'top',         label = 'Top',         ui = 'hoodie',      kind = 'component', index = 11, off = { male = 15, female = 15 }, arms = { male = 15, female = 15 }, retired = true },
    { id = 'undershirt',  label = 'Undershirt',  ui = 'undershirt',  kind = 'component', index = 8,  off = { male = 15, female = 14 }, retired = true },
    { id = 'legs',        label = 'Legs',        ui = 'legs',        kind = 'component', index = 4,  off = { male = 21, female = 15 }, retired = true },
    { id = 'shoes',       label = 'Shoes',       ui = 'shoes',       kind = 'component', index = 6,  off = { male = 34, female = 35 }, retired = true },
    { id = 'armour',      label = 'Body Armour', ui = 'armour',      kind = 'component', index = 9,  off = { male = 0,  female = 0  } },
    { id = 'backpack',    label = 'Backpack',    ui = 'backpack',    kind = 'component', index = 5,  off = { male = 0,  female = 0  } },
    { id = 'accessories', label = 'Accessories', ui = 'accessories', kind = 'component', index = 7,  off = { male = 0,  female = 0  }, retired = true },
    { id = 'glasses',     label = 'Glasses',     ui = 'glasses',     kind = 'prop',      index = 1, retired = true },
    { id = 'earrings',    label = 'Earrings',    ui = 'earrings',    kind = 'prop',      index = 2, retired = true },
    { id = 'watch',       label = 'Watch',       ui = 'watch',       kind = 'prop',      index = 6, retired = true },
    { id = 'bracelet',    label = 'Bracelet',    ui = 'bracelet',    kind = 'prop',      index = 7, retired = true },
    { id = 'hat',         label = 'Hat',         ui = nil,           kind = 'prop',      index = 0, retired = true },
}

--- id -> slot, built once. Callers ask this rather than looping.
Clothing.BySlot = {}
Clothing.OrderOf = {}
for i, slot in ipairs(Clothing.Slots) do
    Clothing.BySlot[slot.id] = slot
    Clothing.OrderOf[slot.id] = i
end

-- The old thirteen positions stay reserved so persisted slot numbers are never reinterpreted. Only these two are valid equipment; appearance is handled by the wardrobe NPCs.
function Clothing.Count() return #Clothing.Slots end
function Clothing.IsActiveSlot(slot)
    return slot and (slot.id == 'armour' or slot.id == 'backpack')
end

-- Rarity scales a garment's stats (via `mult`) and colours its plate in the bag. It does NOT drive loot frequency: weights are hand-set per table in bs_economy, so keep tier and drop rate consistent by hand.
-- A new garment only declares base stats and a tier.
Clothing.Rarity = {
    worn     = { label = 'Worn',     mult = 0.6, colour = '#8b8578' },
    common   = { label = 'Common',   mult = 1.0, colour = '#a8a293' },
    good     = { label = 'Good',     mult = 1.4, colour = '#5fa8d3' },
    military = { label = 'Military', mult = 2.0, colour = '#e08c46' },
}

-- Garment stats. Rule: only add a stat when something already reads it.
-- carry: kg added to the carry limit (playerInventory() in bs_inventory/server/sv_main.lua)
-- armour: flat damage off a walker bite (bs_zombies/client/cl_attack.lua)
-- stealth: fraction off walker sight range, 0.15 = 15% (stealthMultiplier() in bs_zombies/client/cl_ai.lua)
-- Warmth, insulation and similar are absent on purpose: no system reads them.
Clothing.Stats = { 'carry', 'armour', 'stealth' }

-- Condition lives in the slot's `durability` column and scales a garment's stats linearly (50% condition = half the effect). Armour is therefore a consumable.
-- `floor` keeps a ruined garment doing a little.
Clothing.Condition = {
    max   = 100,
    floor = 0.15,
    -- How much condition one walker bite costs the garments that stopped it.
    perBite = 1.5,
}

-- Starter wardrobe. Each entry is an item definition plus:
-- equipSlot: slot in the list above, so equipment frames refuse non-clothing.
-- wear: variation per model, `d` drawable and `t` texture. Omit a model to make the garment unavailable to it.
-- Sizes are real (coat 2x2, hat 1x1); worn clothes do not use grid space.
-- Drawable indices are base-game freemode values; fix wrong ones here.
local function garment(label, slot, w, h, weight, value, wear, extra)
    local def = {
        label = label, category = 'clothing',
        weight = weight, w = w, h = h, stack = 1,
        -- Clothing is never `usable`: there is no 'use a coat', only wearing it.
        usable = false, value = value,
        equipSlot = slot,
        rarity = 'common',
        -- Every garment has a durability, declared here so no garment can be immortal.
        data = { wear = wear, durability = Clothing.Condition.max },
    }
    for k, v in pairs(extra or {}) do def[k] = v end
    return def
end

--- Sugar for the common case: `stats{ armour = 4 }` alongside a rarity.
local function kit(def, rarity, stats)
    def.rarity = rarity or def.rarity
    def.data.stats = stats
    return def
end

-- Inventory clothing is retired. Appearance is bought and saved through the wardrobe NPCs; this table keeps only storage gear.
Clothing.Items = {
    hiking_pack = kit(garment('Hiking pack', 'backpack', 2, 3, 1.6, 260,
        { male = { d = 45, t = 0 }, female = { d = 45, t = 0 } },
        { data = nil }), 'good', { carry = 12.0 }),
}
-- Legacy pack. Migration 036 turns every copy into pack_medium; kept so an old row still loads.
Clothing.Items.hiking_pack.data.bag = { width = 5, height = 4, maxWeight = 20.0 }
Clothing.Items.hiking_pack.data.tier = 2
-- Packs no longer add rows to the main grid; their contents are their own grid (bag container keyed by metadata.bagId).
Clothing.Items.hiking_pack.data.rows = 0

-- Backpacks and vests (SCUM style). Each tier has its own grid (data.bag) and carry bonus (stats.carry, scaled by rarity: good x1.4, military x2).
-- Tiers: 1 small, 2 medium, 3 large, 4 military. The tier also unlocks looks (Clothing.PackLooks).
Clothing.PackTiers = { 'small', 'medium', 'large', 'military' }

-- Looks for the GTA bag component (5). `tier` is the lowest pack tier that may use it. Drawable numbers are data: fix them here.
Clothing.PackLooks = {
    { id = 'satchel',  tier = 1, male = { d = 44, t = 0 }, female = { d = 44, t = 0 } },
    { id = 'hiker',    tier = 1, male = { d = 45, t = 0 }, female = { d = 45, t = 0 } },
    { id = 'duffel',   tier = 2, male = { d = 41, t = 0 }, female = { d = 41, t = 0 } },
    { id = 'rucksack', tier = 2, male = { d = 40, t = 0 }, female = { d = 40, t = 0 } },
    { id = 'trekker',  tier = 3, male = { d = 82, t = 0 }, female = { d = 82, t = 0 } },
    { id = 'assault',  tier = 4, male = { d = 85, t = 0 }, female = { d = 85, t = 0 } },
}
-- Default look per tier (index into PackLooks).
Clothing.PackDefaultLook = { 1, 3, 5, 6 }

local function pack(label, tier, w, h, weight, value, grid, carry, rarity)
    local look = Clothing.PackLooks[Clothing.PackDefaultLook[tier]]
    local def = kit(garment(label, 'backpack', w, h, weight, value,
        { male = look.male, female = look.female }), rarity, { carry = carry })
    def.data.bag, def.data.tier, def.data.rows = grid, tier, 0
    return def
end

local function vest(label, w, h, weight, value, grid, stats, rarity)
    -- Vests sit in the armour frame. Their pockets are a small grid of their own.
    local def = kit(garment(label, 'armour', w, h, weight, value, nil), rarity, stats)
    def.data.bag, def.data.vest = grid, true
    return def
end

Clothing.Items.pack_small    = pack('Small backpack',    1, 2, 2, 0.8, 120,  { width = 4, height = 3, maxWeight = 10.0 }, 6.0,  'common')
Clothing.Items.pack_medium   = pack('Medium backpack',   2, 2, 3, 1.4, 260,  { width = 5, height = 4, maxWeight = 20.0 }, 12.0, 'common')
Clothing.Items.pack_large    = pack('Large backpack',    3, 3, 3, 2.0, 520,  { width = 6, height = 5, maxWeight = 32.0 }, 13.0, 'good')
Clothing.Items.pack_military = pack('Military backpack', 4, 3, 3, 2.6, 900,  { width = 7, height = 6, maxWeight = 45.0 }, 12.5, 'military')
Clothing.Items.vest_tactical = vest('Tactical vest',     2, 2, 2.2, 380,  { width = 3, height = 2, maxWeight = 6.0 },  { carry = 3.0, armour = 6 },  'good')
Clothing.Items.vest_plate    = vest('Plate carrier',     2, 2, 5.5, 1100, { width = 4, height = 2, maxWeight = 10.0 }, { carry = 3.0, armour = 15 }, 'military')

-- Retired from all inventories by core migration 021. Names kept as one reference list.
Clothing.RetiredItems = {
    'worn_tshirt', 'field_jacket', 'hoodie', 'rain_coat', 'plain_vest',
    'work_trousers', 'cargo_pants', 'work_boots', 'trainers', 'dust_mask',
    'gas_mask', 'cap', 'safety_glasses', 'wrist_watch',
}

--------------------------------------------------------------------------------
-- What you are wearing, added up
--------------------------------------------------------------------------------

-- The one place worn stats are totalled. Shared so the server, the modifiers panel and bs_zombies (client) all use the same sum.
-- Pure function: no state, natives or database.
-- `entries` maps slot id -> { item = name, condition = 0..100 }; no condition means pristine.
-- @return table stats, table breakdown  -- breakdown[slotId] = per-garment totals
function Clothing.Aggregate(entries)
    local total = {}
    for _, key in ipairs(Clothing.Stats) do total[key] = 0.0 end

    local breakdown = {}

    for slotId, worn in pairs(entries or {}) do
        local def = Items.Definitions[worn.item or worn]
        local stats = def and def.data and def.data.stats

        if stats then
            local rarity = Clothing.Rarity[def.rarity or 'common']
                        or Clothing.Rarity.common
            local mult = rarity.mult or 1.0

            -- Condition scales everything the garment does (see Clothing.Condition).
            local max = Clothing.Condition.max or 100
            local cond = tonumber(type(worn) == 'table' and worn.condition or nil)
            local wear = 1.0

            if cond then
                wear = math.max(Clothing.Condition.floor or 0.15,
                                math.min(1.0, cond / max))
            end

            local one = {}
            for _, key in ipairs(Clothing.Stats) do
                local base = tonumber(stats[key])
                if base and base ~= 0 then
                    local value = base * mult * wear
                    total[key] = total[key] + value
                    one[key] = value
                end
            end

            if next(one) then breakdown[slotId] = one end
        end
    end

    -- Stealth is a fraction off sight range; the total is capped here so every consumer gets the same ceiling.
    total.stealth = math.min(total.stealth or 0.0, 0.55)

    return total, breakdown
end

-- Merged into the item table so the grid packer, weight, drops, corpses, vendors and admin list all see clothing through Items.Get. An id already in config_items.lua wins.
-- Guarded: `Items` only exists where config_items.lua is loaded. bs_multichar loads just this file for Clothing.Items / Clothing.PreviewLook.
if Items then
    for id, def in pairs(Clothing.Items) do
        if Items.Definitions[id] then
            print(('^3[BeyondSurvival]^7 (inventory) clothing item "%s" is already defined in '
                .. 'config_items.lua - keeping that one.'):format(id))
        else
            Items.Definitions[id] = def
        end
    end
end

-- Torso map: on a freemode ped the top (component 11) and torso/arms (component 3) must match, or the arms clip through the sleeves. No native exposes the pairing, so it is a table; only the few tops we ship need rows.
-- Unlisted tops fall back to the bare-arms index (looks off, never invalid). To fill a row, equip the garment in the admin menu's CLOTHING tab, adjust 'Arms / torso (3)' and paste the printed line.
-- `[drawable] = torso`, or `[drawable] = { [texture] = torso, default = torso }`.
-- Unused since clothing became appearance (migration 021); kept empty so Clothing.TorsoFor returns nil.
Clothing.TorsoMap = { male = {}, female = {} }

-- Torso drawable for a top, or nil so the caller falls back.
-- `gender` is 'male' | 'female'; `drawable`/`texture` are the top's.
function Clothing.TorsoFor(gender, drawable, texture)
    local byModel = Clothing.TorsoMap and Clothing.TorsoMap[gender]
    if not byModel then return nil end

    local entry = byModel[drawable]
    if entry == nil then return nil end

    -- A plain number is "this torso, whatever the texture".
    if type(entry) == 'number' then return entry end

    if type(entry) == 'table' then
        return entry[texture] or entry.default
    end

    return nil
end

-- Raw drawable numbers for one or more items, to show a garment on a ped without it being equipped (used by bs_multichar's creator preview).
-- Same read as applySlot() in cl_equipment.lua, so preview and spawned outfit match. Not clamped against a real ped's variation count since there is no ped here.
function Clothing.PreviewLook(itemNames, gender)
    local components, props = {}, {}

    for _, itemName in ipairs(itemNames or {}) do
        local def = Clothing.Items[itemName]
        local slot = def and Clothing.BySlot[def.equipSlot]
        local wear = def and def.data and def.data.wear and def.data.wear[gender]
        if slot and wear then
            if slot.kind == 'prop' then
                props[tostring(slot.index)] = { drawable = wear.d or 0, texture = wear.t or 0 }
            else
                components[tostring(slot.index)] = { drawable = wear.d or 0, texture = wear.t or 0 }
                if slot.arms then
                    components['3'] = {
                        drawable = wear.arms or slot.arms[gender] or 15, texture = 0,
                    }
                end
            end
        end
    end

    return components, props
end

--- The item that goes in a slot, or nil. Used by the equip validation.
function Clothing.SlotFor(itemName)
    local def = Items.Definitions[itemName]
    return def and def.equipSlot or nil
end
