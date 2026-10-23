-- Booster keybinds, loadout mirror and the self-only effects.

local Loadout = {}
local adrenalineUntil = 0
local fortify = { reduce = 0, untilAt = 0 }
local focusUntil, regenUntil = 0, 0

local function now() return GetGameTimer() end

local function notify(msg, kind)
    TriggerEvent('bs:ui:notify', { type = kind or 'info', message = msg, duration = 2500 })
end

-- Label of whatever key the player actually bound to boosterN (e.g. "t_5" -> "5").
local function keyLabels()
    local out = {}
    for i = 1, Boosters.Slots do
        local hash = joaat(Boosters.Command:format(i)) | 0x80000000
        local raw = GetControlInstructionalButton(0, hash, true) or ''
        local label = raw:gsub('^t_', ''):gsub('^b_%d+', '')
        if label == '' then label = Boosters.DefaultKeys[i] or tostring(i) end
        out[i] = label:upper()
    end
    return out
end
exports('KeyLabels', keyLabels)

RegisterNetEvent('bs:boosters:loadout', function(lo)
    Loadout = type(lo) == 'table' and lo or {}
    -- bs_inventory's panel draws these slots.
    TriggerEvent('bs:boosters:loadoutChanged', Loadout, keyLabels())
end)

exports('GetLoadout', function() return Loadout end)

-- Keys: default 6/7/8, rebindable in FiveM keybind settings.
for i = 1, Boosters.Slots do
    local cmd = Boosters.Command:format(i)
    RegisterCommand(cmd, function()
        if LocalPlayer.state.bsDrone then return end -- flying the drone
        if IsNuiFocused() or IsPauseMenuActive() then return end
        if IsEntityDead(PlayerPedId()) then return end
        -- no local loadout gate: the mirror can be stale, the server answers
        TriggerServerEvent('bs:boosters:use', i)
    end, false)
    RegisterKeyMapping(cmd, L('boost.key_slot', { n = i }), 'keyboard', Boosters.DefaultKeys[i] or tostring(5 + i))
end

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('bs:boosters:request')
end)

------------------------------------------------------------ bite absorb

-- Called by bs_zombies right before a bite lands. Returns what still gets through.
-- The riot shield (bs_gadgets) soaks first, then fortify.
exports('AbsorbZombieDamage', function(amount)
    amount = tonumber(amount) or 0
    if GetResourceState('bs_gadgets') == 'started' then
        local ok, left = pcall(function() return exports.bs_gadgets:ShieldAbsorb(amount) end)
        if ok and type(left) == 'number' then amount = left end
    end
    if fortify.reduce > 0 and now() < fortify.untilAt and amount > 0 then
        amount = amount * (1.0 - fortify.reduce)
    end
    return amount
end)

-- Old callers still ask bs_boosters.
exports('HasRiotShield', function()
    if GetResourceState('bs_gadgets') ~= 'started' then return false end
    local ok, yes = pcall(function() return exports.bs_gadgets:HasShield() end)
    return ok and yes == true
end)
exports('DropRiotShield', function()
    if GetResourceState('bs_gadgets') == 'started' then pcall(function() exports.bs_gadgets:StowShield() end) end
end)

--------------------------------------------------------------- adrenaline

local function startAdrenaline(t)
    adrenalineUntil = now() + t.duration * 1000
    CreateThread(function()
        local pid = PlayerId()
        SetRunSprintMultiplierForPlayer(pid, math.min(1.49, t.speed))
        while now() < adrenalineUntil do
            RestorePlayerStamina(pid, 1.0)
            Wait(0)
        end
        SetRunSprintMultiplierForPlayer(pid, 1.0)
    end)
end

----------------------------------------------------------- focus / regen

local function startFocus(t)
    focusUntil = now() + t.duration * 1000
    LocalPlayer.state:set('bsSteady', t.steady or 0.6, false)
    CreateThread(function()
        while now() < focusUntil do Wait(250) end
        LocalPlayer.state:set('bsSteady', nil, false)
    end)
end

local function startRegen(t)
    regenUntil = now() + t.duration * 1000
    CreateThread(function()
        while now() < regenUntil do
            Wait(t.tickMs or 2000)
            local ped = PlayerPedId()
            if IsEntityDead(ped) then regenUntil = 0; break end
            local hp, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
            if hp < max then SetEntityHealth(ped, math.min(max, hp + (t.healPerTick or 3))) end
        end
    end)
end

local function startFortify(t)
    fortify.reduce = math.max(0, math.min(0.8, t.reduce or 0.3))
    fortify.untilAt = now() + t.duration * 1000
end

------------------------------------------------------------------ dispatch

RegisterNetEvent('bs:boosters:activate', function(item, t)
    if type(t) ~= 'table' then return end
    notify(L('boost.used', { name = t.label }))
    if t.kind == 'adrenaline' then startAdrenaline(t)
    elseif t.kind == 'focus' then startFocus(t)
    elseif t.kind == 'regen' then startRegen(t)
    elseif t.kind == 'fortify' then startFortify(t)
    end
end)

-- Dying ends every buff.
RegisterNetEvent('bs:medical:died', function() adrenalineUntil, focusUntil, regenUntil = 0, 0, 0; fortify.untilAt = 0 end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    LocalPlayer.state:set('bsSteady', nil, false)
end)
