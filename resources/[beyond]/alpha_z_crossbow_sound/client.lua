-- Alpha-Z V4: crossbow uses a SILENT scripted shot with the original GTA weapon hash.
-- DO NOT confuse it with a regular WEAPON_SNIPERRIFLE item: only the inventory
-- item `crossbow` signals this client through bs_inventory/client/cl_hotbar.lua.
-- We cancel the native firing input BEFORE GTA can play its sniper gunshot.
-- A silent bullet (isAudible=false), ammo decrement, custom WAV, native magazine
-- reload and a cooldown replace that shot. Other rifles are unaffected.

local sniperHash = GetHashKey('WEAPON_SNIPERRIFLE')
local RELOAD_MS = 2850
local ATTACK, ATTACK2, AIM, RELOAD = 24, 257, 25, 45
local enabled, cycling, untilTick = false, false, 0
local needsAimRelease, needsAttackRelease = false, false
local previousCam = nil
local shotId = 0
local animation = nil
local lastTrigger = 0

local function pressed(ctrl)
    return IsControlPressed(0, ctrl) or IsDisabledControlPressed(0, ctrl)
end

local function stopAnimation()
    if animation then
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and IsEntityPlayingAnim(ped, animation.dict, animation.clip, 3) then
            StopAnimTask(ped, animation.dict, animation.clip, 1.5)
        end
    end
    animation = nil
end

local function clearCycle(restoreCamera)
    shotId = shotId + 1
    cycling, untilTick = false, 0
    needsAimRelease, needsAttackRelease = false, false
    stopAnimation()
    if restoreCamera and previousCam ~= nil then SetFollowPedCamViewMode(previousCam) end
    previousCam = nil
end

local function setEquipped(value)
    value = value == true
    if not value then clearCycle(true) end
    enabled = value
    if enabled then RequestWeaponAsset(sniperHash, 31, 0) end
end

AddEventHandler('alpha_z_crossbow:equipped', setEquipped)
AddEventHandler('bs:hook:player:unloaded', function() setEquipped(false) end)
AddEventHandler('onClientResourceStop', function(res)
    if res == 'bs_inventory' or res == GetCurrentResourceName() then setEquipped(false) end
end)
-- When only this sound resource restarts, retrieve the last actual inventory item.
CreateThread(function()
    Wait(1300)
    if GetResourceState('bs_inventory') == 'started' then
        local ok, active = pcall(function() return exports.bs_inventory:IsCrossbowSelected() end)
        if ok then setEquipped(active == true) end
    end
end)
exports('IsCycling', function()
    return enabled and cycling and GetSelectedPedWeapon(PlayerPedId()) == sniperHash
end)

RegisterNetEvent('alpha_z_crossbow:remoteShot', function(origin)
    if type(origin) ~= 'table' then return end
    local me = GetEntityCoords(PlayerPedId())
    local pos = vector3(tonumber(origin.x) or 0, tonumber(origin.y) or 0, tonumber(origin.z) or 0)
    local distance = #(me - pos)
    if distance > 55.0 then return end
    SendNUIMessage({ action = 'playCrossbow', volume = math.max(0.0, 1.0 - distance / 55.0) * 0.68 })
end)

-- Prefer the very same engine reload as R / changing a magazine (MakePedReload).
-- GTA refuses native reload with no spare ammo; in that case TaskReloadWeapon
-- is attempted, followed by a verified rifle-magazine animation as fallback.
local MAG_ANIMATIONS = {
    { dict='weapons@rifle@lo@', clip='reload_low' },
    { dict='anim@weapons@sniper@sniper_rifle@', clip='reload_low' },
    { dict='reload@rifle', clip='reload' },
    { dict='weapons@rifle@hi@', clip='reload_hi' },
}

local function playMagazineAnimation(id)
    CreateThread(function()
        Wait(160) -- let the camera leave scope and the aim input get released
        if not cycling or id ~= shotId then return end
        local ped = PlayerPedId()
        if not DoesEntityExist(ped) or GetSelectedPedWeapon(ped) ~= sniperHash then return end
        -- Identical native used by bs_weapons/client/cl_reload.lua on R.
        local nativeStarted = MakePedReload(ped)
        Wait(170)
        if id ~= shotId or not cycling then return end
        if IsPedReloading(ped) then return end
        -- TaskReloadWeapon requests GTA's regular weapon reload task even without
        -- a full reserve; if GTA still refuses, use the corresponding clip.
        TaskReloadWeapon(ped, true)
        Wait(130)
        if id ~= shotId or not cycling or IsPedReloading(ped) then return end

        for _, a in ipairs(MAG_ANIMATIONS) do
            if DoesAnimDictExist(a.dict) then
                RequestAnimDict(a.dict)
                local deadline = GetGameTimer() + 900
                while not HasAnimDictLoaded(a.dict) and GetGameTimer() < deadline do
                    if id ~= shotId then return end
                    Wait(0)
                end
                if HasAnimDictLoaded(a.dict) then
                    local ok, duration = pcall(GetAnimDuration, a.dict, a.clip)
                    if ok and type(duration)=='number' and duration > 0 then
                        TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0,
                            math.max(650, RELOAD_MS - 500), 48, 0.0, false, false, false)
                        Wait(65)
                        if id ~= shotId then return end
                        if IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                            animation = {dict=a.dict, clip=a.clip}
                            RemoveAnimDict(a.dict)
                            return
                        end
                    end
                    RemoveAnimDict(a.dict)
                end
            end
        end
        print('^3[Alpha-Z Crossbow V4]^7 GTA refused reload and no fallback magazine animation played.')
    end)
end

local function aimVector()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx))
end

local function fireSilent(ped)
    local total = GetAmmoInPedWeapon(ped, sniperHash) or 0
    local _, loaded = GetAmmoInClip(ped, sniperHash)
    loaded = tonumber(loaded) or 0
    if total < 1 or loaded < 1 then
        TriggerEvent('bs:ui:notify', { type='warn', message='Armbrust: Keine Munition', duration=1500 })
        return
    end
    local cam = GetGameplayCamCoord()
    local dir = aimVector()
    local target = cam + dir * 350.0
    local test = StartShapeTestRay(cam.x, cam.y, cam.z,
        target.x, target.y, target.z, -1, ped, 7)
    local state, hit, hitPos = GetShapeTestResult(test)
    if state == 2 and hit == 1 and hitPos then target = hitPos end

    -- Fire from the hand/weapon position toward the actual crosshair point.
    -- isAudible=false is deliberate: no original GTA sniper shot is emitted.
    local from = GetPedBoneCoords(ped, 57005, 0.10, 0.02, 0.01)
    local dmg = 60
    local ok, actual = pcall(GetWeaponDamage, sniperHash, 0)
    if ok and type(actual) == 'number' and actual > 0 then dmg = math.floor(actual) end
    ShootSingleBulletBetweenCoords(from.x, from.y, from.z,
        target.x, target.y, target.z, dmg, false, sniperHash,
        ped, false, true, 1300.0)

    -- The bullet native may or may not alter ped ammo depending on the GTA
    -- build; charge exactly ONE bolt, never duplicate ammo or reload for free.
    local afterTotal = GetAmmoInPedWeapon(ped, sniperHash) or 0
    if afterTotal >= total then SetPedAmmo(ped, sniperHash, total - 1) end
    local _, afterClip = GetAmmoInClip(ped, sniperHash)
    if (tonumber(afterClip) or 0) >= loaded then SetAmmoInClip(ped, sniperHash, loaded - 1) end

    cycling = true
    untilTick = GetGameTimer() + RELOAD_MS
    needsAimRelease, needsAttackRelease = true, true
    shotId = shotId + 1
    local id = shotId
    if previousCam == nil then previousCam = GetFollowPedCamViewMode() end
    SetFollowPedCamViewMode(1)
    SendNUIMessage({ action = 'playCrossbow', volume = 0.85 })
    TriggerServerEvent('alpha_z_crossbow:shot')
    playMagazineAnimation(id)
end

CreateThread(function()
    while true do
        if not enabled then
            Wait(300)
        else
            Wait(0)
            local ped = PlayerPedId()
            if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
                setEquipped(false)
            elseif GetSelectedPedWeapon(ped) ~= sniperHash then
                if cycling then clearCycle(true) end
            else
                -- Critical: inhibit the engine's native WEAPON_SNIPERRIFLE shot
                -- BEFORE handling input. This prevents the loud GTA gunfire.
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, ATTACK, true)
                DisableControlAction(0, ATTACK2, true)

                if not pressed(AIM) then needsAimRelease = false end
                if not pressed(ATTACK) then needsAttackRelease = false end
                if cycling and GetGameTimer() >= untilTick then
                    cycling = false
                    stopAnimation()
                    -- A held aim/shoot key must be released before next use.
                end
                if cycling or needsAimRelease then
                    DisableControlAction(0, AIM, true)
                    if cycling then SetFollowPedCamViewMode(1) end
                end
                if cycling then DisableControlAction(0, RELOAD, true) end

                if not cycling and not needsAttackRelease and not needsAimRelease
                    and not IsNuiFocused() and not IsPauseMenuActive()
                    and not IsPedInAnyVehicle(ped, false)
                    and IsDisabledControlJustPressed(0, ATTACK)
                    and GetGameTimer() - lastTrigger >= 250 then
                    lastTrigger = GetGameTimer()
                    fireSilent(ped)
                end
            end
        end
    end
end)
