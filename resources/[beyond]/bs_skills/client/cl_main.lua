-- bs_skills - client half of the perks. The server decides what you own; this applies the native-side effects (weapon damage modifiers, drain rates, and the `executioner` / `break_fall` flags). The server re-sends the truth on every skill change and spawn, so nothing here is trusted.

local Mine = {
    levels  = {},
    perks   = {},
    points  = 0,
    effects = { weaponDamage = 0.0, meleeDamage = 0.0, hungerRate = 0.0,
                thirstRate = 0.0, stealth = 0.0, flags = {} },
}

-- Applying

local function applyEffects()
    local playerId = PlayerId()
    local e = Mine.effects

    -- Damage modifiers are multiplicative on top of 1.0.
    SetPlayerWeaponDamageModifier(playerId, 1.0 + (e.weaponDamage or 0.0))
    SetPlayerMeleeWeaponDamageModifier(playerId, 1.0 + (e.meleeDamage or 0.0))
end

-- Level-up sound goes through bs_ui's WebAudio player (own cue in bs_ui/html/sound), not a GTA native sting. Non-positional. If bs_ui is not running it stays silent.
-- A skill level plays only the quiet LevelAppear sound; LevelUpMusic is reserved for character level-ups. bs_ui owns the sequence.
RegisterNetEvent('bs:skills:levelUp', function(treeId, level, label)
    if GetResourceState('bs_ui') ~= 'started' then return end

    pcall(function()
        exports.bs_ui:SkillLevelSequence(level, level - 1)
    end)
end)

RegisterNetEvent('bs:skills:sync', function(payload)
    if type(payload) ~= 'table' then return end

    Mine.levels  = payload.levels or {}
    Mine.perks   = payload.perks or {}
    Mine.effects = payload.effects or Mine.effects
    Mine.effects.flags = Mine.effects.flags or {}
    Mine.points  = payload.points or 0

    applyEffects()
    TriggerEvent('bs:skills:changed', Mine)
end)

-- Damage modifiers are reset by the engine on respawn, so re-apply.
AddEventHandler('bs:hook:player:spawned', function() applyEffects() end)

CreateThread(function()
    while true do
        Wait(15000)
        -- Cheap insurance: a model change silently drops the modifiers.
        applyEffects()
    end
end)

-- Reads for other resources. Two signatures are in use:
--     exports.bs_skills:HasPerk('survival', 'break_fall')
--     exports.bs_skills:HasPerk('break_fall')

exports('HasPerk', function(a, b)
    local perkId = b or a
    if not perkId then return false end
    return Mine.perks[perkId] ~= nil
end)

exports('GetSkillLevel', function(treeId)
    return Mine.levels[treeId] or 0
end)

exports('GetLevels', function() return Mine.levels end)

-- Tree definitions for UIs to draw. Labels and max levels only (bs_inventory's character sheet), so it does not need its own copy of config_skills.lua. Perks, costs and effects stay here, since decisions about them belong on the server.
exports('GetTrees', function()
    local out = {}
    for id, tree in pairs(Skills.Trees or {}) do
        out[id] = { label = (function() local k = 'tree.' .. id; local s = L(k); return s ~= k and s or tree.label end)(), maxLevel = tree.maxLevel or 20, icon = tree.icon }
    end
    return out
end)

-- Every modifier currently applying, as a flat table, for panels that list all effects. Returns a copy so consumers cannot edit this resource's state.
exports('GetEffects', function()
    local out = {}
    for k, v in pairs(Mine.effects or {}) do
        if k ~= 'flags' then out[k] = v end
    end
    out.points = Mine.points
    return out
end)

-- 1.0 = normal drain. bs_core's needs tick multiplies by this.
exports('NeedMultiplier', function(kind)
    local e = Mine.effects
    if kind == 'hunger' then return 1.0 - (e.hungerRate or 0.0) end
    if kind == 'thirst' then return 1.0 - (e.thirstRate or 0.0) end
    return 1.0
end)

-- 1.0 = seen at the normal distance. bs_zombies multiplies its sight range.
exports('StealthMultiplier', function()
    return 1.0 - (Mine.effects.stealth or 0.0)
end)

-- Named capabilities: 'executioner', 'break_fall'.
exports('HasFlag', function(flag)
    return (Mine.effects.flags or {})[flag] == true
end)

exports.bs_core:RegisterModule('skills', { side = 'client', version = '1.0.0', ready = true })
