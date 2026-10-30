-- bs_medical - going down instead of dying. GTA kills at health 100 (its floor), so we watch health and catch the player just above it. While down you keep camera and voice, can shout (walkers hear it) and spend one bandage for 90 more seconds. The server owns the clock.

local S = Medical.Settings

local Downed = {
    active     = false,
    until_     = 0,      -- game timer ms when the bleedout ends
    stabilised = false,
    lastShout  = 0,
    -- A 'medical:down' request is in flight. `active` is only true once the server answers, so this stops the watchdog firing a second request in the gap.
    requesting = false,
    -- Give-up hold: when the key went down (0 = not held), and whether the request is in flight.
    holdFrom   = 0,
    givingUp   = false,
    -- What the HUD may offer, refreshed from the server while down.
    opts       = { bandages = 0, medkits = 0 },
    optsAt     = 0,
    -- Medkit self-treatment start time, 0 = idle.
    selfFrom   = 0,
}

-- Set by cl_carry.lua (same Lua state) while this player is dragged or carried: the pose is not re-forced and the clock runs at Medical.Carry.bleedoutRate.
Medical.BeingCarried = false

-- Is a panel on screen? The staff menu works while downed, but this file keeps running underneath it (downed and death HUD, input blocking), which wrecks it. Anything that opens over the screen sets this so those are skipped.
local PanelsOpen = {}

local function anyPanelOpen()
    -- A panel that closed without saying so (death drops NUI focus) must not hide the downed HUD forever: no focus means nothing is open.
    if next(PanelsOpen) == nil then return false end
    if not IsNuiFocused() then PanelsOpen = {} return false end
    return true
end

AddEventHandler('bs:ui:opened', function(name)
    PanelsOpen[name or '?'] = true
end)

AddEventHandler('bs:ui:closed', function(name)
    if name == nil then PanelsOpen = {} else PanelsOpen[name] = nil end
end)

AddEventHandler('bs:ui:panic', function() PanelsOpen = {} end)

-- Helpers

local function notify(kind, message, duration, title)
    TriggerEvent('bs:ui:notify', {
        type = kind, message = message, duration = duration, title = title,
    })
end

local function playAnim(anim, flag)
    local ped = PlayerPedId()
    if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) end
    local waited = 0
    while not HasAnimDictLoaded(anim.dict) and waited < 3000 do Wait(10); waited = waited + 10 end
    if not HasAnimDictLoaded(anim.dict) then return false end
    TaskPlayAnim(ped, anim.dict, anim.clip, 2.0, 2.0, -1, flag or 1, 0.0, false, false, false)
    return true
end

-- Undoes everything a death or downed state leaves on the local player. Resurrects first if the ped is dead. Returns the ped.
local function standUp(health)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    ClearTimecycleModifier()
    StopGameplayCamShaking(true)
    AnimpostfxStopAll()
    ClearFocus()
    if health then SetEntityHealth(ped, health) end
    return ped
end

local R = Medical.Respawn or {}

local function inAvoidZone(x, y)
    for _, z in ipairs(R.avoidZones or {}) do
        local dx, dy = x - z.x, y - z.y
        if dx * dx + dy * dy <= z.r * z.r then return true end
    end
    return false
end

--- Random open ground 500-1000 m from `from`. The ped is parked (frozen,
--- invisible) over each candidate so its collision streams in before we
--- probe. Returns x, y, z or nil.
local function findRespawnSpot(ped, from)
    if not from then return nil end
    local minD, maxD = R.minDistance or 500.0, R.maxDistance or 1000.0
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    for _ = 1, (R.tries or 14) do
        local a = math.random() * math.pi * 2
        local d = minD + math.random() * (maxD - minD)
        local x, y = from.x + math.cos(a) * d, from.y + math.sin(a) * d

        -- Rough map bounds; skips the open sea around the island.
        if x > -3700 and x < 4200 and y > -3900 and y < 7800 and not inAvoidZone(x, y) then
            SetEntityCoordsNoOffset(ped, x, y, 800.0, false, false, false)
            SetFocusPosAndVel(x, y, 100.0, 0.0, 0.0, 0.0)
            RequestCollisionAtCoord(x, y, 100.0)
            local found, gz = false, 0.0
            local waited = 0
            while waited < 2000 do
                RequestCollisionAtCoord(x, y, 100.0)
                found, gz = GetGroundZFor_3dCoord(x, y, 800.0, false)
                if found then break end
                Wait(100) waited = waited + 100
            end

            if found then
                local ok, safe = GetSafeCoordForPed(x, y, gz + 1.0, false, 16)
                if ok then x, y, gz = safe.x, safe.y, safe.z end
                local wet, wz = GetWaterHeight(x, y, gz)
                local wet2 = TestVerticalProbeAgainstAllWater(x, y, gz + 2.0, 0)
                local interior = GetInteriorAtCoords(x, y, gz)
                if not (wet and wz >= gz - 0.5) and not wet2 and interior == 0
                   and not inAvoidZone(x, y) then
                    ClearFocus()
                    return x, y, gz
                end
            end
        end
    end
    ClearFocus()
    return nil
end

-- Post-respawn grace: no re-down, no needs or condition damage for a while.
local RESPAWN_GRACE_MS = 10000

local function startRespawnGrace()
    Downed.graceUntil = GetGameTimer() + RESPAWN_GRACE_MS
    LocalPlayer.state:set('bsRespawnGrace', true, false)
    local mine = Downed.graceUntil
    SetTimeout(RESPAWN_GRACE_MS, function()
        if Downed.graceUntil == mine then LocalPlayer.state:set('bsRespawnGrace', false, false) end
    end)
end

-- Respawn health must sit above the catch window, or the watchdog downs us again on the spot.
local function respawnHealthFor(ped)
    local hp = math.max(S.respawnHealth or 120, (S.catchHealth or 106) + 15)
    local max = GetEntityMaxHealth(ped)
    if max and max > 100 and hp > max then hp = max end
    return hp
end

--- The shared wake-up: resurrect, pick ground, stand up, fade in.
local function wakeUp(point, from)
    -- Grace covers the whole spot search too, which can take a while.
    startRespawnGrace()
    Downed.flat = false
    Downed.selfFrom = 0
    Downed.requesting = false
    DoScreenFadeOut(600)
    Wait(700)

    local ped = standUp(nil)
    local x, y, z = findRespawnSpot(ped, from)
    if not x and point then x, y, z = point.x + 0.0, point.y + 0.0, point.z + 0.0 end
    if x then
        FreezeEntityPosition(ped, true)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        SetEntityHeading(ped, (point and point.h) or math.random(0, 359) + 0.0)
        local waited = 0
        while not HasCollisionLoadedAroundEntity(ped) and waited < 3000 do
            RequestCollisionAtCoord(x, y, z) Wait(100) waited = waited + 100
        end
    end

    local ped2 = standUp(nil)
    SetEntityHealth(ped2, respawnHealthFor(ped2))
    -- Restart the grace now we are actually standing.
    startRespawnGrace()
    Wait(400)
    DoScreenFadeIn(800)
    notify('error', L('med.woke_text'), 9000, L('med.woke_title'))
end

-- Entering and leaving

--- Health after a revive: 100 + reviveHealth, never in watchdog range.
local function reviveHealthFor(ped)
    local hp = 100 + (S.reviveHealth or 30)
    if hp < 120 then hp = 120 end
    local max = GetEntityMaxHealth(ped)
    if max and max > 100 and hp > max then hp = max end
    return hp
end

local function enterDowned(seconds)
    if Downed.active then return end

    Downed.active     = true
    Downed.flat       = false
    Downed.stabilised = false
    Downed.holdFrom   = 0
    Downed.givingUp   = false
    Downed.until_     = GetGameTimer() + (seconds * 1000)
    Downed.selfFrom   = 0
    Downed.optsAt     = 0

    local ped = PlayerPedId()

    -- Pin just above the death floor and make the ped invincible, so only the bleedout timer can kill.
    SetEntityHealth(ped, 105)
    SetPlayerInvincible(PlayerId(), true)
    SetPedCanRagdoll(ped, true)
    ClearPedTasksImmediately(ped)
    playAnim(Medical.Anims.downed)

    -- Everything drains out of the world.
    SetTimecycleModifier('REDMIST_blend')
    SetTimecycleModifierStrength(0.4)
    ShakeGameplayCam('DEATH_FAIL_IN_EFFECT_SHAKE', 0.25)

    notify('error', L('med.you_are_bleeding_out_someone_has_to'), 8000, L('med.down_title'))
end

local function leaveDowned(revived)
    if not Downed.active then return end
    Downed.active   = false
    Downed.flat     = false
    Downed.holdFrom = 0
    Downed.givingUp = false
    Downed.selfFrom = 0
    -- Drop drag/carry state first, or cl_carry's victim loop keeps replaying its clip over the stand-up.
    TriggerEvent('bs:medical:carry:stop')
    Medical.BeingCarried = false
    DetachEntity(PlayerPedId(), true, false)
    SetPedCanRagdoll(PlayerPedId(), true)

    -- Same cleanup as a respawn, in place. A revive also opens a short grace window so the watchdog does not read a stale ~105 as 'down again'.
    local hp = revived and reviveHealthFor(PlayerPedId()) or nil
    if revived then Downed.graceUntil = GetGameTimer() + 8000 end
    local ped = standUp(hp)
    if revived then
        CreateThread(function()
            local untilT = GetGameTimer() + 1500
            while GetGameTimer() < untilT and not Downed.active do
                Wait(100)
                ped = PlayerPedId()
                local d = Medical.Anims.downed
                if IsEntityPlayingAnim(ped, d.dict, d.clip, 3) then ClearPedTasksImmediately(ped) end
                if GetEntityHealth(ped) < hp then SetEntityHealth(ped, hp) end
            end
        end)
    end

    if revived then
        notify('success', L('med.on_your_feet_do_not_waste_it'), 5000)
    end
end

-- The watchdog
-- One cheap loop that only acts on the frame you would have died.

CreateThread(function()
    while true do
        Wait(120)

        if S.enabled and exports.bs_core:IsLoaded()
           and not Downed.active and not Downed.requesting
           and GetGameTimer() >= (Downed.graceUntil or 0) then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)

            -- 101 is one point above the engine's floor. Catch it there.
            if health > 0 and health <= (S.catchHealth or 106) and not IsPedDeadOrDying(ped, true) then
                -- Ask the server to start the clock. It returns how long we have, so clients never disagree.
                Downed.requesting = true
                CreateThread(function()
                    local result = BSB.Await('medical:down', 6000)
                    Downed.requesting = false
                    if result and result.ok then
                        enterDowned(result.seconds or S.bleedoutTime)
                    end
                end)
                Wait(1500)
            end
        end
    end
end)

-- While you are down

-- The bleedout clock and the two available actions, drawn as bare text with a shadow. Declared above the loop that calls it: a `local function` used before its declaration compiles to a global lookup and is nil at runtime.
local HELP = Medical.Help or {}
local SR = Medical.SelfRevive or {}
local lastHelp = 0

-- Heart stopped (medical system): only a defibrillator helps now.
local function drawFlatline(left)
    SetTextFont(4)
    SetTextScale(0.0, 0.62)
    SetTextColour(200, 70, 60, 240)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(L('flatline_title', { s = math.max(0, math.floor(left)) }))
    DrawText(0.5, 0.78)

    SetTextFont(4)
    SetTextScale(0.0, 0.34)
    SetTextColour(160, 152, 136, 210)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(L('flatline_tip'))
    DrawText(0.5, 0.825)
end

local function drawCountdown(left)
    if Downed.flat then return drawFlatline(left) end
    local minutes = math.max(0, math.floor(left / 60))
    local seconds = math.max(0, math.floor(left % 60))

    SetTextFont(4)
    SetTextScale(0.0, 0.62)
    SetTextColour(216, 210, 194, 235)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 205)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(L('med.bleeding_out', { time = ('%d:%02d'):format(minutes, seconds) }))
    DrawText(0.5, 0.78)

    SetTextFont(4)
    SetTextScale(0.0, 0.36)
    SetTextColour(160, 152, 136, 200)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    local line = L('med.hud_help', { key = HELP.label or 'H' })
    if (not Downed.stabilised or S.stabiliseUnlimited) and (Downed.opts.bandages or 0) > 0 then
        line = line .. '     ' .. L('med.hud_pack', { n = Downed.opts.bandages })
    end
    if (Downed.opts.medkits or 0) > 0 then
        line = line .. '     ' .. L('med.hud_medkit', { key = SR.label or 'R', n = Downed.opts.medkits })
    end
    AddTextComponentString(line .. '     ' .. L('med.hud_give_up'))
    DrawText(0.5, 0.822)

    -- What is possible, said plainly.
    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(140, 134, 120, 190)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    local tip
    if Medical.BeingCarried then
        tip = L('med.you_are_being_moved_bleeding_slows_w')
    elseif (Downed.opts.medkits or 0) > 0 then
        tip = L('med.you_can_patch_yourself_up_with_your')
    else
        tip = L('med.anyone_with_a_medkit_can_treat_you_o')
    end
    AddTextComponentString(tip)
    DrawText(0.5, 0.852)
end

-- Giving up is a held key with a bar, since it is irreversible (permanent death and inventory wipe). Held for 2.5 seconds so it cannot be hit by accident, and the bar is visible so the player can let go.
local GIVE_UP_HOLD_MS = 2500

local function drawGiveUpProgress(fraction, label)
    local w, h = 0.14, 0.006
    local x, y = 0.5, 0.862

    -- The trough, then the fill. No border or box.
    DrawRect(x, y, w, h, 0, 0, 0, 150)
    DrawRect(x - (w * (1.0 - fraction) * 0.5), y, w * fraction, h, 168, 58, 48, 235)

    SetTextFont(4)
    SetTextScale(0.0, 0.32)
    SetTextColour(200, 120, 110, 225)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(label or L('med.letting_go'))
    DrawText(x, y + 0.012)
end

CreateThread(function()
    while true do
        if Downed.active then
            Wait(0)
            local ped = PlayerPedId()

            -- Nothing but the camera works.
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 44, true)   -- cover
            DisableControlAction(0, 37, true)   -- weapon wheel
            DisablePlayerFiring(PlayerId(), true)

            -- Keep the pose: ragdolls and impacts knock it off. Not while being dragged/carried (cl_carry owns the pose).
            if not Medical.BeingCarried and not IsEntityPlayingAnim(ped, Medical.Anims.downed.dict, Medical.Anims.downed.clip, 3) then
                playAnim(Medical.Anims.downed)
            end

            -- Scripts can still nudge health; hold the line.
            if GetEntityHealth(ped) < 102 then SetEntityHealth(ped, 105) end

            -- Being moved slows the clock (the server does the same, authoritatively).
            if Medical.BeingCarried then
                local rate = (Medical.Carry and Medical.Carry.bleedoutRate) or 0.0
                Downed.until_ = Downed.until_ + math.floor(GetFrameTime() * 1000 * (1.0 - rate))
            end

            -- Refresh what the HUD can offer (items in the bag).
            if GetGameTimer() - Downed.optsAt > 4000 then
                Downed.optsAt = GetGameTimer()
                CreateThread(function()
                    local r = BSB.Await('medical:options', 5000)
                    if r and r.ok then Downed.opts = r end
                end)
            end

            local left = (Downed.until_ - GetGameTimer()) / 1000

            -- The last thirty seconds look and sound different.
            if left <= 30 then
                SetTimecycleModifierStrength(0.75)
            end

            -- The clock, drawn as bare text with a shadow. Not drawn while a panel is up (see PanelsOpen at the top).
            if not anyPanelOpen() then drawCountdown(left) end

            -- Shout for help. Loud, and everything hears it.
            if not Downed.flat and IsControlJustPressed(0, 38) then          -- E
                local now = GetGameTimer()
                if now - Downed.lastShout >= S.shoutCooldown then
                    Downed.lastShout = now
                    local coords = GetEntityCoords(ped)

                    PlayPain(ped, 6, 0, false, false)
                    TriggerEvent('bs:world:noise', {
                        kind = 'shout', radius = S.shoutNoise,
                        coords = { x = coords.x, y = coords.y, z = coords.z },
                    })
                    if GetResourceState('bs_emotes') == 'started' then
                        pcall(function()
                            exports.bs_emotes:MakeNoise('shout', coords, S.shoutNoise)
                        end)
                    end
                    notify('warn', L('med.you_shouted_so_did_everything_that_h'), 3000)
                end
            end

            -- Ask for help: squad, faction and anyone nearby get a map ping.
            if not Downed.flat and (IsControlJustPressed(0, HELP.control or 74) or IsDisabledControlJustPressed(0, HELP.control or 74)) then
                local now = GetGameTimer()
                if now - lastHelp >= 1500 then
                    lastHelp = now
                    CreateThread(function()
                        local r = BSB.Await('medical:callHelp', 6000)
                        if r and r.ok then
                            notify('info', r.count > 0 and L('med.call_reached', { n = r.count })
                                or L('med.nobody_is_close_enough_to_hear_you'), 4000)
                        else
                            notify('warn', (r and r.error) or L('med.no_answer'), 3000)
                        end
                    end)
                end
            end

            -- Bandage yourself, once, for more time.
            if not Downed.flat and IsControlJustPressed(0, 47) and (not Downed.stabilised or S.stabiliseUnlimited) then   -- G
                CreateThread(function()
                    local result = BSB.Await('medical:stabilise', 8000)
                    if result and result.ok then
                        Downed.stabilised = true
                        Downed.until_ = Downed.until_ + ((result.bonus or 90) * 1000)
                        notify('success', L('med.packed_the_wound_it_buys_you_minutes'), 5000)
                    else
                        notify('warn', (result and result.error) or L('med.nothing_to_pack_it_with'), 3000)
                    end
                end)
            end

            -- Patch yourself up with a medkit: a few seconds, then the server revives you the same way a medic's treatment does.
            if SR.enabled and not Downed.flat and (Downed.opts.medkits or 0) > 0 and Downed.selfFrom == 0
               and (IsControlJustPressed(0, SR.control or 45) or IsDisabledControlJustPressed(0, SR.control or 45)) then
                Downed.selfFrom = GetGameTimer()
            end
            if Downed.selfFrom > 0 then
                local done = (GetGameTimer() - Downed.selfFrom) / (SR.time or 6000)
                if not anyPanelOpen() then drawGiveUpProgress(math.min(1.0, done), L('med.patching_yourself_up')) end
                if done >= 1.0 then
                    Downed.selfFrom = -1      -- in flight
                    CreateThread(function()
                        local r = BSB.Await('medical:selfRevive', 8000)
                        -- On success bs:medical:revived stands us up.
                        if not (r and r.ok) then
                            Downed.selfFrom = 0
                            notify('warn', (r and r.error) or L('med.no_answer'), 3000)
                        end
                    end)
                end
            end

            -- Give up and die now. Held, never tapped (see GIVE_UP_HOLD_MS). Disarmed while a panel is open.
            DisableControlAction(0, 73, true)
            if Downed.givingUp or Downed.flat or anyPanelOpen() then
                Downed.holdFrom = 0
            elseif IsControlPressed(0, 73) or IsDisabledControlPressed(0, 73)
                or (Downed.holdFrom > 0 and GetGameTimer() - (Downed.holdSeen or 0) < 600) then   -- X, held
                -- X is also a vehicle/emote key, so another script can disable it for a frame or two. Read the disabled state too and forgive short gaps, or the bar restarts from zero.
                if IsControlPressed(0, 73) or IsDisabledControlPressed(0, 73) then Downed.holdSeen = GetGameTimer() end
                if Downed.holdFrom == 0 then Downed.holdFrom = GetGameTimer() end

                local held = GetGameTimer() - Downed.holdFrom
                drawGiveUpProgress(math.min(1.0, held / GIVE_UP_HOLD_MS))

                if held >= GIVE_UP_HOLD_MS then
                    Downed.holdFrom = 0
                    Downed.givingUp = true
                    CreateThread(function()
                        local result = BSB.Await('medical:giveUp', 8000)
                        -- On success the server sends bs:medical:died and the handler at the bottom of this file takes over.
                        if not (result and result.ok) then
                            Downed.givingUp = false
                            notify('warn', (result and result.error)
                                or L('med.the_server_did_not_answer_still_blee'), 4000)
                        end
                    end)
                end
            else
                -- Let go early: nothing happens and the bar disappears.
                Downed.holdFrom = 0
            end
        else
            Wait(300)
        end
    end
end)

-- The hard death, when the catch above is skipped
-- Fall damage, drowning, an explosion or one big hit can clear the 1-106 window in one tick, so the ped is dead before the 120ms watchdog sees it alive and `enterDowned` never runs. This polls IsEntityDead instead of the health window and handles it.

local HardDead = {
    active  = false,
    -- Watchdog ignores deaths until this game time (just respawned).
    grace   = 0,
    -- A respawn request is in flight. Without it, holding or double-tapping E sent two requests and the second hit the server cooldown.
    pending = false,
}

-- Seconds before the respawn key works (defibrillator window, medical system only).
function HardDead.waitLeft()
    if not GlobalState.bsMedicalOn or not HardDead.since then return 0 end
    local window = (Medical.System and Medical.System.defibWindow or 0) * 1000
    return math.max(0, math.ceil((window - (GetGameTimer() - HardDead.since)) / 1000))
end

local function drawHardDeath()
    SetTextFont(4)
    SetTextScale(0.0, 0.7)
    SetTextColour(180, 60, 50, 235)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(L('med.you_died'))
    DrawText(0.5, 0.74)

    SetTextFont(4)
    SetTextScale(0.0, 0.36)
    SetTextColour(216, 210, 194, 220)
    SetTextDropshadow(2, 0, 0, 0, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    local wait = HardDead.waitLeft and HardDead.waitLeft() or 0
    AddTextComponentString(wait > 0 and L('respawn_in', { s = wait }) or L('respawn_prompt'))
    DrawText(0.5, 0.80)
end

-- PvP deaths go down first. A player's bullet usually exceeds the catch window in one tick, so the hard-death path ran. When the killer was another player and Medical.PvP.downFirst is on, the body is picked up where it lies, pinned at 105 and handed to the downed state. Returns true if it took the death.
-- Fall tracking for hardDeathFallHeight: last Z the ped stood on the ground.
local lastGroundZ = nil
CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            local falling = IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) or IsPedRagdoll(ped)
            if not falling or lastGroundZ == nil then
                lastGroundZ = GetEntityCoords(ped).z
            end
        end
    end
end)

local FALL_HASH   = GetHashKey('WEAPON_FALL')
local DROWN_HASH  = GetHashKey('WEAPON_DROWNING')
local DROWNV_HASH = GetHashKey('WEAPON_DROWNING_IN_VEHICLE')

-- Should this death skip the downed state? Explosions, drowning and long falls (configurable). Everything else, zombies included, goes down.
local function isHardCause(ped)
    local cause = GetPedCauseOfDeath(ped)
    if S.hardDeathOnDrown ~= false and (cause == DROWN_HASH or cause == DROWNV_HASH or IsPedSwimmingUnderWater(ped)) then
        return true
    end
    if S.hardDeathOnExplosion ~= false and cause ~= 0 and GetWeaponDamageType(cause) == 5 then
        return true
    end
    if cause == FALL_HASH then
        local z = GetEntityCoords(ped).z
        if ((lastGroundZ or z) - z) > (S.hardDeathFallHeight or 15.0) then return true end
    end
    return false
end

local function catchPvPDeath(ped)
    local P = Medical.PvP or {}
    if Downed.active or Downed.requesting then return false end
    local reason = 'catch'
    if S.catchAllDeaths then
        if isHardCause(ped) then return false end
    else
        if not P.downFirst then return false end
        local killer = GetPedSourceOfDeath(ped)
        if not killer or killer == 0 or killer == ped or not DoesEntityExist(killer) then return false end
        if GetEntityType(killer) == 2 then killer = GetPedInVehicleSeat(killer, -1) end
        if not killer or killer == 0 or not IsPedAPlayer(killer) or killer == ped then return false end
        reason = 'pvp'
    end

    local c = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, 105)
    SetPlayerInvincible(PlayerId(), true)

    Downed.requesting = true
    local result = BSB.Await('medical:down', 6000, reason)
    Downed.requesting = false
    if result and result.ok then
        enterDowned(result.seconds or S.bleedoutTime)
        return true
    end
    -- Server refused: fall back to the normal death screen.
    SetPlayerInvincible(PlayerId(), false)
    SetEntityHealth(ped, 0)
    Wait(300)
    return false
end

local function enterHardDeath()
    if HardDead.active or Downed.active then return end
    HardDead.active = true
    HardDead.since = GetGameTimer()

    -- Freeze where it fell so ragdoll physics does not slide it down a slope.
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    DisableControlAction(0, 249, true) -- push to talk, so it doesn't stay hot

    -- Tell the server we are on the death screen so others can revive the body (bsDead / bsRevivable state bags) until we respawn.
    CreateThread(function() BSB.Await('medical:dead', 6000) end)
end

local function leaveHardDeath()
    HardDead.active  = false
    HardDead.pending = false
    HardDead.grace   = GetGameTimer() + 4000
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then FreezeEntityPosition(ped, false) end
end

CreateThread(function()
    while true do
        Wait(200)

        if S.enabled and exports.bs_core:IsLoaded()
           and not Downed.active and not HardDead.active and GetGameTimer() > HardDead.grace then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) and IsEntityDead(ped) then
                if not catchPvPDeath(ped) then enterHardDeath() end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if HardDead.active then
            Wait(0)

            -- Do not paint the death text over an open staff menu. The E handler below stays live regardless, since being unable to respawn is the worst outcome here.
            if not anyPanelOpen() and not HardDead.pending then drawHardDeath() end

            -- One press, one request, and the answer is believed. There is an in-flight guard (extra presses queued requests the server's five second cooldown refused), and `result.ok` is checked so a refusal is shown instead of ignored.
            if IsControlJustPressed(0, 38) and not HardDead.pending and HardDead.waitLeft() <= 0 then -- E
                HardDead.pending = true
                CreateThread(function()
                    local result = BSB.Await('medical:hardDeath', 8000)

                    if not (result and result.ok) then
                        -- Still dead, prompt still up, press still available.
                        HardDead.pending = false
                        -- The server attaches a reason to every refusal, so a missing one means no answer arrived within eight seconds. Say that instead of a generic 'try again'.
                        return notify('warn',
                            (result and result.error)
                            or L('med.no_answer_from_the_server_press_e_ag'),
                            5000)
                    end

                    -- Stay 'active' until we are on our feet: clearing it first lets the watchdog see the still-dead ped and re-freeze it.
                    wakeUp(result.point, result.from)
                    leaveHardDeath()
                end)
            end
        else
            Wait(300)
        end
    end
end)

-- Server-driven transitions

-- The one revive, received from any state. leaveDowned returns early when not downed, so a staff REVIVE on a player who died outright was dropped. This handles all three states, since the client is the only side that knows which it is in.
RegisterNetEvent('bs:medical:revived', function()
    if Downed.active then
        leaveDowned(true)
        return
    end

    -- Dead on the ground, with or without the respawn prompt: stand up in place first, then drop the prompt, so the watchdog never re-arms.
    HardDead.active = true
    Downed.graceUntil = GetGameTimer() + 8000
    standUp(reviveHealthFor(PlayerPedId()))
    leaveHardDeath()

    notify('success', L('med.on_your_feet_do_not_waste_it'), 5000)
end)

-- The clock ran out. The server has already moved us and reset our needs.
RegisterNetEvent('bs:medical:died', function(point, from)
    -- Hold the hard-death watchdog off while we move, or it catches the ped mid-fade.
    HardDead.active = true
    HardDead.pending = true
    Downed.active = false
    Downed.flat = false
    Downed.holdFrom = 0
    Downed.givingUp = false
    Downed.selfFrom = 0
    wakeUp(point, from)
    leaveHardDeath()
end)

-- Finishing off a downed player (only when Medical.PvP.allowExecution).
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not Downed.active or Downed.givingUp then return end
    if not (Medical.PvP and Medical.PvP.allowExecution) then return end
    local victim, attacker = args[1], args[2]
    if victim ~= PlayerPedId() or not attacker or attacker == victim then return end
    if not DoesEntityExist(attacker) or not IsPedAPlayer(attacker) then return end
    local idx = NetworkGetPlayerIndexFromPed(attacker)
    if not idx or idx == -1 then return end
    Downed.givingUp = true
    CreateThread(function()
        local r = BSB.Await('medical:executed', 6000, GetPlayerServerId(idx))
        if not (r and r.ok) then Downed.givingUp = false end
    end)
end)

-- Bleedout ran out with the medical system on: the heart stops, the body stays.
RegisterNetEvent('bs:medical:flatline', function(seconds)
    if not Downed.active then return end
    Downed.flat = true
    Downed.selfFrom = 0
    Downed.holdFrom = 0
    Downed.until_ = GetGameTimer() + (tonumber(seconds) or 60) * 1000
    SetTimecycleModifierStrength(0.9)
end)

-- Extra time from someone else's bandage.
RegisterNetEvent('bs:medical:extend', function(seconds)
    if not Downed.active then return end
    Downed.until_ = Downed.until_ + ((tonumber(seconds) or 0) * 1000)
end)

AddEventHandler('bs:hook:player:unloaded', function() leaveDowned(false); leaveHardDeath() end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetPlayerInvincible(PlayerId(), false)
        ClearTimecycleModifier()
        leaveHardDeath()
    end
end)

-- Someone downed is asking for help: a flashing blip for a while.
RegisterNetEvent('bs:medical:helpPing', function(fromSrc, name, at, why)
    if type(at) ~= 'table' then return end
    local blip = AddBlipForCoord(at.x + 0.0, at.y + 0.0, at.z + 0.0)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, why == 'squad' and 3 or (why == 'faction' and 2 or 1))
    SetBlipFlashes(blip, true)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(L('med.needs_help', { name = name or L('med.someone') }))
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    notify('warn', L('med.down_asking', { name = name or L('med.someone') }), 7000, L('med.help_title'))
    SetTimeout((HELP.blipTime or 90) * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

exports('IsDowned', function() return Downed.active end)
exports('TimeLeft', function()
    if not Downed.active then return 0 end
    return math.max(0, (Downed.until_ - GetGameTimer()) / 1000)
end)
