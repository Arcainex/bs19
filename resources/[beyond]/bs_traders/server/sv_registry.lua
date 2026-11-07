-- bs_traders - merge of config and database. Config is the starting layout,
-- the database is what runs. Other files ask this for an NPC or mission rather
-- than reading Traders.Traders / Traders.Missions.
-- An override is a JSON blob keyed by id holding only changed fields; present
-- fields win, absent ones fall back to config. An id with an override but no
-- config entry is a debug-menu-created NPC/mission, and deleting its row
-- deletes it. For config ids, 'reset to default' just deletes the override row.

Registry = {}

local npcOverrides = {}       -- [id] = decoded table
local missionOverrides = {}   -- [id] = decoded table

-- Loading

local function loadOverrides()
    local npcRows = exports.oxmysql:query_async('SELECT `npc_id`, `data` FROM `bs_npc_overrides`') or {}
    for _, row in ipairs(npcRows) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then npcOverrides[row.npc_id] = decoded end
    end

    local missionRows = exports.oxmysql:query_async('SELECT `mission_id`, `data` FROM `bs_npc_mission_overrides`') or {}
    for _, row in ipairs(missionRows) do
        local ok, decoded = pcall(json.decode, row.data)
        if ok and type(decoded) == 'table' then missionOverrides[row.mission_id] = decoded end
    end

    print(('^2[bs_traders]^7 loaded %d NPC override(s), %d mission override(s)')
        :format(#npcRows, #missionRows))
end

CreateThread(loadOverrides)

-- Effective NPC

-- Coordinate priority: override x/y/z, then the config entry's `zone` + `offset`
-- (via Traders.ZoneCoords), then an absolute `coords` on the config entry.
local function resolveCoords(base, override)
    if override and override.x and override.y and override.z then
        return vector3(override.x, override.y, override.z)
    end
    if base then
        if base.zone then return Traders.ZoneCoords(base.zone, base.offset) end
        if base.coords then return base.coords end
    end
    return nil
end

-- Override value if present (false and 0 count), else config, else default.
local function pick(ov, base, key, default)
    if ov ~= nil and ov[key] ~= nil then return ov[key] end
    if base ~= nil and base[key] ~= nil then return base[key] end
    return default
end

-- Effective NPC by id, or nil if missing or deleted. `disabled` entries are
-- still returned (the debug menu needs them); spawners must check `.disabled`.
function Registry.EffectiveNpc(id)
    local base = Traders.Traders[id]
    local ov = npcOverrides[id]
    if not base and not ov then return nil end

    local coords = resolveCoords(base, ov)
    if not coords then return nil end

    -- Booleans cannot be merged with `or`: an override of false would fall through
    -- to the config value, so the flag could never be switched off. Use if/else.
    -- `disabled` only escapes this because its default is false.
    -- The flag itself: a wardrobe offered as an extra service by any NPC, separate
    -- from role = 'clothing' (a dedicated tailor).
    local clothing
    if ov ~= nil and ov.clothing ~= nil then
        clothing = ov.clothing and true or false
    else
        clothing = (base and base.clothing) and true or false
    end

    return {
        id       = id,
        label    = (ov and ov.label)    or (base and base.label)    or id,
        role     = (ov and ov.role)     or (base and base.role)     or 'trader',
        model    = (ov and ov.model)    or (base and base.model)    or 'a_m_m_farmer_01',
        scenario = (ov and ov.scenario ~= '' and ov.scenario) or (base and base.scenario),
        heading  = (ov and ov.heading)  or (base and base.heading)  or 0.0,
        coords   = coords,
        buys     = (ov and ov.buys)     or (base and base.buys)     or {},
        sells    = (ov and ov.sells)    or (base and base.sells)    or {},
        missions = (ov and ov.missions) or (base and base.missions) or {},
        -- if/else because `or` cannot merge a boolean (see above).
        clothing = clothing,

        disabled = ov and ov.disabled or false,

        -- Management fields. Each falls back override -> config -> default.
        faction      = pick(ov, base, 'faction', ''),            -- '' = neutral
        safezone     = pick(ov, base, 'safezone', base and base.zone or ''),
        categories   = pick(ov, base, 'categories', nil),        -- nil = defaults
        openFrom     = tonumber(pick(ov, base, 'openFrom', -1)) or -1,   -- -1 = always open
        openTo       = tonumber(pick(ov, base, 'openTo', -1)) or -1,
        priceMult    = tonumber(pick(ov, base, 'priceMult', 1.0)) or 1.0,
        rankDiscount = tonumber(pick(ov, base, 'rankDiscount', 0)) or 0,
        restock      = tonumber(pick(ov, base, 'restock', 0)) or 0,      -- seconds, 0 = global
        blipOn       = pick(ov, base, 'blipOn', false) and true or false,
        blipSprite   = tonumber(pick(ov, base, 'blipSprite', 52)) or 52,
        blipColor    = tonumber(pick(ov, base, 'blipColor', 2)) or 2,
        notes        = pick(ov, base, 'notes', ''),
        -- True once an override exists. The debug UI uses it to show 'reset to default'
        -- where a config default exists and 'delete' where it does not.
        hasConfig = base ~= nil,
    }
end

-- `a and false or b` returns b, so consume = false was ignored. Plain if.
local function consumeOf(ov, base)
    if ov and ov.consume ~= nil then return ov.consume end
    return base and base.consume
end

function Registry.EffectiveMission(id)
    local base = Traders.Missions[id]
    local ov = missionOverrides[id]
    if not base and not ov then return nil end

    return {
        id       = id,
        label    = (ov and ov.label)    or (base and base.label)    or id,
        giver    = (ov and ov.giver)    or (base and base.giver),
        kind     = (ov and ov.kind)     or (base and base.kind)     or 'kill',
        filter   = (ov and ov.filter)   or (base and base.filter)   or {},
        item     = (ov and ov.item)     or (base and base.item),
        target   = (ov and ov.target)   or (base and base.target)   or 1,
        consume  = consumeOf(ov, base),
        desc     = (ov and ov.desc)     or (base and base.desc)     or '',
        reward   = (ov and ov.reward)   or (base and base.reward)   or { xp = 0, money = 0 },
        cooldown = (ov and ov.cooldown) or (base and base.cooldown) or Traders.Settings.defaultCooldown,
        group    = (ov and ov.group)    or (base and base.group),
        hasConfig = base ~= nil,
    }
end

-- Every known id, config or override. Disabled/soft-deleted entries are
-- included on purpose.
function Registry.AllNpcIds()
    local seen, out = {}, {}
    for id in pairs(Traders.Traders) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    for id in pairs(npcOverrides) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    return out
end

function Registry.AllMissionIds()
    local seen, out = {}, {}
    for id in pairs(Traders.Missions) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    for id in pairs(missionOverrides) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    return out
end

-- Writing

-- Merges `patch` into the id's override (other keys kept) and saves it.
-- Returns the effective NPC.
function Registry.SetNpcOverride(id, patch)
    local merged = npcOverrides[id] or {}
    for k, v in pairs(patch) do merged[k] = v end
    npcOverrides[id] = merged

    exports.oxmysql:execute_async(
        'INSERT INTO `bs_npc_overrides` (`npc_id`, `data`) VALUES (?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
        { id, json.encode(merged) })

    return Registry.EffectiveNpc(id)
end

-- Deletes the id's override. With a config entry this resets to default;
-- without one the NPC is gone.
function Registry.ResetNpc(id)
    npcOverrides[id] = nil
    exports.oxmysql:execute_async('DELETE FROM `bs_npc_overrides` WHERE `npc_id` = ?', { id })
end

function Registry.SetMissionOverride(id, patch)
    local merged = missionOverrides[id] or {}
    for k, v in pairs(patch) do merged[k] = v end
    missionOverrides[id] = merged

    exports.oxmysql:execute_async(
        'INSERT INTO `bs_npc_mission_overrides` (`mission_id`, `data`) VALUES (?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `data` = VALUES(`data`)',
        { id, json.encode(merged) })

    return Registry.EffectiveMission(id)
end

function Registry.ResetMission(id)
    missionOverrides[id] = nil
    exports.oxmysql:execute_async('DELETE FROM `bs_npc_mission_overrides` WHERE `mission_id` = ?', { id })
end
