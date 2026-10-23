-- Client effects. The server decides what is active and for how long.

local pid = PlayerId()
local function now() return GetGameTimer() end
local effects = {}        -- drug -> { untilAt = GetGameTimer ms, s = quality effect scale, q, dur }
local wd = 0              -- withdrawal level from server
DrugActive = effects      -- read by cl_fx.lua
function DrugWithdrawal() return wd end

-- HUD: send the list only when it changes, the page counts down itself.
local function pushHud()
    if not Drugs.Hud.enabled then return end
    local list, t = {}, now()
    for drug, e in pairs(effects) do
        local left = math.floor((e.untilAt - t) / 1000)
        if left > 0 then
            list[#list + 1] = { drug = drug, label = Drugs.Types[drug].label,
                q = e.q, ql = Drugs.Quality[e.q] and Drugs.Quality[e.q].label or '', left = left, dur = e.dur }
        end
    end
    table.sort(list, function(a, b) return a.left > b.left end)
    SendNUIMessage({ action = 'drugs', list = list, withdrawal = wd })
end
local smoking = false
local lastMods


local function on(drug) local e = effects[drug]; return e and now() < e.untilAt and e or nil end
-- Scale a multiplier toward 1.0 by quality (bad = weaker).
local function scaled(base, s) return 1.0 + (base - 1.0) * s end

local function notify(msg, kind)
    TriggerEvent('bs:ui:notify', { type = kind or 'info', message = msg, duration = 3000 })
end

-- Mods read by bs_core (stamina, infection) and bs_skills (sway).
local function buildMods()
    local m = { drain = 1.0, regen = 1.0, infection = 1.0, sway = 1.0 }
    local e = on('cocaine');     if e then m.drain = m.drain * scaled(Drugs.Types.cocaine.staminaDrain, e.s) end
    e = on('amphetamine');       if e then m.sway = m.sway * scaled(Drugs.Types.amphetamine.sway, e.s)
                                           m.regen = m.regen * scaled(Drugs.Types.amphetamine.staminaRegen, e.s) end
    e = on('weed');              if e then m.infection = m.infection * scaled(Drugs.Types.weed.infection, e.s) end
    if smoking then m.cap = Drugs.Types.cigarette.staminaCap end
    local w = Drugs.Withdrawal[wd]
    if w then m.sway = m.sway * w.sway; m.regen = m.regen * w.staminaRegen end
    return m
end

local function sameMods(a, b)
    if not a or not b then return false end
    for _, k in ipairs({ 'drain', 'regen', 'infection', 'sway', 'cap' }) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

local function pushMods()
    local m = buildMods()
    if not sameMods(m, lastMods) then
        LocalPlayer.state:set('bsDrugMods', m, false)
        lastMods = m
    end
end

--------------------------------------------------------------- cigarette

local function startSmoking(duration)
    smoking = true
    local startHp = GetEntityHealth(PlayerPedId())
    local t = Drugs.Types.cigarette
    CreateThread(function()   -- slow heal
        while smoking do
            Wait(t.healTickMs)
            local ped = PlayerPedId()
            if smoking and not IsEntityDead(ped) then
                local hp = GetEntityHealth(ped)
                if hp < GetEntityMaxHealth(ped) then SetEntityHealth(ped, hp + t.healPerTick); startHp = startHp + t.healPerTick end
            end
        end
    end)
    DrugAnim.Smoke(duration, function()
        local ped = PlayerPedId()
        if IsEntityDead(ped) or IsPedSprinting(ped) or IsPlayerFreeAiming(pid) or IsPedShooting(ped)
            or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) then return true end
        local hp = GetEntityHealth(ped)
        if hp < startHp then return true end   -- took damage
        startHp = math.max(startHp, hp)
        return false
    end, function(stopped)
        smoking = false
        effects.cigarette = nil
        pushHud()
        if stopped then TriggerServerEvent('bs:drugs:stopSmoking'); notify(L('drug.drop_cig')) end
        pushMods()
    end)
end

------------------------------------------------------------------ events

RegisterNetEvent('bs:drugs:apply', function(drug, q, duration)
    local t, qual = Drugs.Types[drug], Drugs.Quality[q]
    if not t or not qual then return end
    duration = tonumber(duration) or 0
    Crumb('drug', '%s q=%s %ss', tostring(drug), tostring(q), tostring(duration))
    effects[drug] = { untilAt = now() + duration * 1000, s = qual.effect, q = q, dur = duration }
    if drug == 'cigarette' then startSmoking(duration)
    else DrugAnim.Play(t.anim); notify(L('drug.kicks_in', { name = t.label, q = qual.label })) end
    pushMods()
    pushHud()
end)

RegisterNetEvent('bs:drugs:anim', function(key) DrugAnim.Play(key) end)

RegisterNetEvent('bs:drugs:state', function(st)
    if type(st) ~= 'table' then return end
    local prev = wd
    wd = tonumber(st.withdrawal) or 0
    -- Drop effects the server no longer considers active (e.g. after a relog).
    for drug in pairs(effects) do
        if not (st.active and st.active[drug]) and drug ~= 'cigarette' then effects[drug] = nil end
    end
    -- Restore timers we do not know yet (relog / resource restart).
    for drug, a in pairs(st.active or {}) do
        local qual = type(a) == 'table' and Drugs.Quality[a.q]
        if qual and drug ~= 'cigarette' and not effects[drug] and Drugs.Types[drug] then
            effects[drug] = { untilAt = now() + a.rem * 1000, s = qual.effect, q = a.q, dur = a.dur }
        end
    end
    if wd > prev then notify(L('drug.withdrawal'), 'error')
    elseif wd == 0 and prev > 0 then notify(L('drug.passed'), 'success') end
    pushMods()
    pushHud()
end)

RegisterNetEvent('bs:player:loaded', function() Wait(2000); TriggerServerEvent('bs:drugs:request') end)
CreateThread(function() Wait(4000); TriggerServerEvent('bs:drugs:request') end)

------------------------------------------------------------ effect loop

CreateThread(function()
    local lastHp, nextFx, sprintOn = nil, 0, false
    while true do
        Wait(100)
        local ped = PlayerPedId()
        pid = PlayerId()

        -- Cocaine: sprint speed.
        local c = on('cocaine')
        if c and not sprintOn then
            SetRunSprintMultiplierForPlayer(pid, math.min(1.49, scaled(Drugs.Types.cocaine.sprint, c.s))); sprintOn = true
        elseif not c and sprintOn then
            SetRunSprintMultiplierForPlayer(pid, 1.0); sprintOn = false
        end

        -- Morphine: refund part of any health loss.
        local hp = GetEntityHealth(ped)
        local mo = on('morphine')
        if mo and lastHp and hp < lastHp and hp > 0 then
            local keep = scaled(Drugs.Types.morphine.damageTaken, mo.s)
            local back = math.floor((lastHp - hp) * (1.0 - keep) + 0.5)
            if back > 0 then hp = math.min(GetEntityMaxHealth(ped), hp + back); SetEntityHealth(ped, hp) end
        end
        lastHp = hp

        -- Withdrawal: camera shake, health regen, periodic screen effect.
        local wl = Drugs.Withdrawal[wd]   -- camera shake is handled in cl_fx.lua
        SetPlayerHealthRechargeMultiplier(pid, wl and wl.healthRegen or 1.0)
        if wl and now() >= nextFx then
            if nextFx > 0 then
                AnimpostfxPlay(Drugs.Withdrawal.fx, Drugs.Withdrawal.fxMs, false)
            end
            nextFx = now() + wl.fxEvery * 1000
        elseif not wl then nextFx = 0 end

        -- Expire finished effects.
        for drug, e in pairs(effects) do
            if now() >= e.untilAt and drug ~= 'cigarette' then
                effects[drug] = nil
                notify(L('drug.wears_off', { name = Drugs.Types[drug].label }))
                pushHud()
            end
        end
        pushMods()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 1.0)
    LocalPlayer.state:set('bsDrugMods', nil, false)
end)
