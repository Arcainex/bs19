-- Hunger, thirst and the custom stamina bar. Simulated locally and reported to the server, which clamps and persists. Values live in BS.Player.data.needs for the HUD.

BS.Needs = { hunger = 100.0, thirst = 100.0, stamina = 100.0, infection = 0.0 }
local N = BS.Needs

local lastSprint = 0

-- Running out of breath slows you down, it never stops you. Winded is a move rate computed each frame from current stamina (full speed at windedAt and above, down to windedMoveRate at zero), so there is no flag to latch. Enforcement runs every frame because DisableControlAction lasts one frame; the 10Hz loop owns the number.

--- @return number  1.0 at full stamina, windedMoveRate at zero
local function moveRateFor(stamina)
    local S = Config.Stamina
    local winded = S.windedAt or 5.0
    if stamina >= winded then return 1.0 end

    local floorRate = S.windedMoveRate or 0.72
    -- Linear, so the slowdown is gradual.
    local t = math.max(0.0, math.min(1.0, stamina / math.max(0.001, winded)))
    return floorRate + (1.0 - floorRate) * t
end

CreateThread(function()
    local applied = nil

    while true do
        Wait(0)

        if not BS.IsLoaded() or not Config.Stamina.enabled then
            applied = nil
            Wait(250)
            goto continue
        end

        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            applied = nil
            Wait(200)
            goto continue
        end

        local rate = moveRateFor(N.stamina)

        if rate < 0.999 then
            -- Must be every frame: the override is not sticky.
            SetPedMoveRateOverride(ped, rate)
            applied = rate
        elseif applied ~= nil then
            -- Back above the line: restore the ped's speed once, then stop touching it. A stale override leaves a player permanently slow.
            SetPedMoveRateOverride(ped, 1.0)
            applied = nil
        else
            -- Costs nothing while you have breath left.
            Wait(150)
        end

        ::continue::
    end
end)

-- SetEntityHealth from a script bypasses the game's damage pipeline, so godmode does not stop it. Ask bs_admin and skip the health reduction.
local function godmodeOn()
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, on = pcall(function() return exports.bs_admin:IsGodmode() end)
    return ok and on == true
end

-- Just respawned (bs_medical sets this for a few seconds): the server is still refilling needs, so skip starve/infection damage.
local function respawnGrace()
    return LocalPlayer.state.bsRespawnGrace == true
end

local function classMultiplier(key)
    local data = BS.GetData('class')
    local stats = data and data.stats or {}
    return stats[key] or 1.0
end

-- Perks slow the drain. bs_skills owns the number; without it the base rate stands.
local function perkMultiplier(kind)
    if GetResourceState('bs_skills') ~= 'started' then return 1.0 end
    local ok, value = pcall(function() return exports.bs_skills:NeedMultiplier(kind) end)
    if ok and type(value) == 'number' then return value end
    return 1.0
end

BS.On('player:loaded', function(data)
    N.hunger    = (data.needs and data.needs.hunger) or 100.0
    N.thirst    = (data.needs and data.needs.thirst) or 100.0
    N.infection = (data.needs and data.needs.infection) or 0.0
    N.stamina   = 100.0
end)

RegisterNetEvent(BS.Events.PlayerNeeds, function(needs)
    N.hunger    = needs.hunger or N.hunger
    N.thirst    = needs.thirst or N.thirst
    N.infection = needs.infection or N.infection
    BS.Emit('needs:changed', N)
end)

--------------------------------------------------------------------------------
-- Hunger / thirst tick
--------------------------------------------------------------------------------

-- Sampler: the needs tick is 30s, so once a second we note movement and last activity. The drain tick reads the totals and resets them.
local activity = { moving = 0, samples = 0, lastActive = GetGameTimer() }

CreateThread(function()
    if not Config.Needs.enabled then return end
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local speed = GetEntitySpeed(veh ~= 0 and veh or ped)
        local moving = speed > 0.5 or IsPedSwimming(ped) or IsPedClimbing(ped)
        activity.samples = activity.samples + 1
        if moving then activity.moving = activity.moving + 1 end
        if moving or IsControlPressed(0, 24) or IsControlPressed(0, 25) or IsControlPressed(0, 1) or IsControlPressed(0, 2) then
            activity.lastActive = GetGameTimer()
        end
    end
end)

local function activityMultiplier()
    local C = Config.Needs
    local idle = C.idleMultiplier or 1.0
    local out
    if GetGameTimer() - activity.lastActive > (C.afkAfter or 120) * 1000 then
        out = C.afkMultiplier or idle
    elseif activity.samples > 0 then
        local f = activity.moving / activity.samples
        out = f + (1.0 - f) * idle
    else
        out = 1.0
    end
    activity.moving, activity.samples = 0, 0
    return out
end

CreateThread(function()
    if not Config.Needs.enabled then return end
    local tick = (Config.Needs.tickRate or 30) * 1000

    while true do
        Wait(tick)
        if BS.IsLoaded() then
            local ped = PlayerPedId()
            local sprinting = IsPedSprinting(ped)
            local mult = (sprinting and (Config.Needs.sprintMultiplier or 1.0) or 1.0) * activityMultiplier()

            N.hunger = BS.Util.Clamp(
                N.hunger - Config.Needs.hungerPerTick * classMultiplier('hungerRate')
                    * (BSConfigGet and BSConfigGet('Global.hungerRateMultiplier', 1.0) or 1.0)
                    * perkMultiplier('hunger') * mult, 0.0, 100.0)
            N.thirst = BS.Util.Clamp(
                N.thirst - Config.Needs.thirstPerTick * classMultiplier('thirstRate')
                    * (BSConfigGet and BSConfigGet('Global.thirstRateMultiplier', 1.0) or 1.0)
                    * perkMultiplier('thirst') * mult, 0.0, 100.0)

            if (N.hunger <= Config.Needs.starvingAt or N.thirst <= Config.Needs.dehydratedAt)
               and not godmodeOn() and not respawnGrace() then
                local health = GetEntityHealth(ped)
                if health > 0 then
                    SetEntityHealth(ped, math.max(0, health - (Config.Needs.damagePerTick or 3)))
                end
            end

            -- Infection only climbs, and only while you carry it.
            -- With bs_medical running it owns infection and sets this number itself.
            if Config.Infection.enabled and N.infection > 0 and not GlobalState.bsMedicalInfection then
                N.infection = BS.Util.Clamp(N.infection + Config.Infection.perTick * ((LocalPlayer.state.bsDrugMods or {}).infection or 1.0), 0.0, 100.0)

                if N.infection >= Config.Infection.criticalAt and not godmodeOn() and not respawnGrace() then
                    local health = GetEntityHealth(ped)
                    if health > 0 then
                        SetEntityHealth(ped, math.max(0, health - Config.Infection.damagePerTick))
                    end
                end
            end

            TriggerServerEvent(BS.Events.UpdateNeeds, N.hunger, N.thirst, N.infection)
            BS.Emit('needs:changed', N)
        end
    end
end)

--------------------------------------------------------------------------------
-- Custom stamina
--------------------------------------------------------------------------------

CreateThread(function()
    if not Config.Stamina.enabled then return end

    while true do
        Wait(100)
        if BS.IsLoaded() then
            local ped = PlayerPedId()
            local mult = classMultiplier('staminaMult')
            -- Drug buffs/withdrawal (bs_drugs) scale drain/regen and can cap the bar.
            local dm = LocalPlayer.state.bsDrugMods or {}

            -- Native stamina is disabled so the bar is the only limit.
            RestorePlayerStamina(PlayerId(), 1.0)

            if IsPedSprinting(ped) and not IsPedInAnyVehicle(ped, false) then
                lastSprint = GetGameTimer()
                N.stamina = BS.Util.Clamp(
                    N.stamina - (Config.Stamina.drainPerSecond / 10) * (dm.drain or 1.0) / mult, 0.0, 100.0)

                -- Nothing is enforced here. The per-frame thread above reads N.stamina and works out the move rate itself.
            elseif GetGameTimer() - lastSprint > (Config.Stamina.regenDelay * 1000) then
                N.stamina = BS.Util.Clamp(
                    N.stamina + (Config.Stamina.regenPerSecond / 10) * mult * (dm.regen or 1.0), 0.0, 100.0)
            end
            if dm.cap and N.stamina > dm.cap then N.stamina = dm.cap end
            -- Low blood (bs_medical) caps it too.
            local medCap = LocalPlayer.state.bsMedStaminaCap
            if medCap and N.stamina > medCap then N.stamina = medCap end

            BS.Emit('needs:stamina', N.stamina)
        end
    end
end)

exports('GetNeeds', function() return N end)

-- A setter is needed because GetNeeds() crosses an export boundary and returns a copy. Anything that spends stamina (e.g. the roll in bs_emotes) must go through this.
exports('AdjustStamina', function(delta)
    N.stamina = BS.Util.Clamp(N.stamina + (tonumber(delta) or 0), 0.0, 100.0)
    BS.Emit('needs:stamina', N.stamina)
    return N.stamina
end)


-- Infection symptoms: visual only and cheap (colour correction plus an occasional stumble). Damage is done by the tick above.

local infectionGradeActive = false

CreateThread(function()
    if not Config.Infection.enabled then return end

    while true do
        Wait(500)

        if BS.IsLoaded() and N.infection >= Config.Infection.symptomsAt and not GlobalState.bsMedicalInfection then
            -- Scales from 0 at the symptom threshold to 1 at fatal.
            local span = math.max(1.0, Config.Infection.fatalAt - Config.Infection.symptomsAt)
            local severity = math.min(1.0, (N.infection - Config.Infection.symptomsAt) / span)

            infectionGradeActive = true
            SetTimecycleModifier('spectator5')
            SetTimecycleModifierStrength(0.15 + severity * 0.55)

            if severity > 0.55 and math.random() < severity * 0.08 then
                local ped = PlayerPedId()
                if not IsPedRagdoll(ped) and not IsPedInAnyVehicle(ped, false) then
                    SetPedToRagdoll(ped, 800, 1000, 0, true, true, false)
                end
            end
        elseif infectionGradeActive then
            -- Only touch the timecycle while symptoms are active; clearing it every pass erased the player's selected filter and caused flashing.
            infectionGradeActive = false
            ClearTimecycleModifier()
            if GetResourceState('bs_ui') == 'started' then
                pcall(function() exports.bs_ui:RestoreFilter() end)
            end
        end
    end
end)

-- Server-side infection change (zombie bites, cures).
RegisterNetEvent('bs:needs:setInfection', function(value)
    N.infection = BS.Util.Clamp(tonumber(value) or 0, 0.0, 100.0)
    BS.Emit('needs:changed', N)
end)
