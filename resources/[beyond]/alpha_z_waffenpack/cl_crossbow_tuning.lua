-- Alpha-Z Fernkampf-Tuning V13
-- Gilt fuer alle hier eingetragenen Fernkampfwaffen.
--
-- Normal beim Zielen:
--   Sway/Kamera-Schwanken = 50 %
--   Rueckstoss/Kamera-Hochziehen = 30 % (70 % reduziert)
--
-- SHIFT beim Zielen:
--   Luft anhalten = 6 Sekunden
--   Erholung = 3 Sekunden
--   Recoil/Shake = 0
--   dunkle/unscharfe Aussenraender
--
-- Manuelle Zielbewegung beim Luftanhalten:
--   vertikal = 1.80
--   horizontal bewusst niedrig

local SHIFT = 21
local MAX_BREATH_MS = 6000
local RECOVERY_MS = 3000

local VERTICAL_SCALE = 1.40
local HORIZONTAL_SCALE = 0.45
local CROSSBOW_HORIZONTAL_SCALE = 0.70
local HORIZONTAL_DEADZONE = 0.0

-- 70 % weniger Hochziehen/Recoil = 30 % Rest.
local NORMAL_RECOIL_SCALE = 0.30
-- 50 % des normalen Schwankens.
local NORMAL_SWAY_SCALE = 0.50

local RANGED_NAMES = {
    'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50',
    'WEAPON_SNSPISTOL', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL', 'WEAPON_REVOLVER',
    'WEAPON_MACHINEPISTOL', 'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_ASSAULTSMG',
    'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_ADVANCEDRIFLE',
    'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE',
    'WEAPON_PUMPSHOTGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN',
    'WEAPON_BULLPUPSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_MUSKET',
    'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE',
    'WEAPON_MG', 'WEAPON_COMBATMG'
}

local RANGED = {}
for _, name in ipairs(RANGED_NAMES) do
    RANGED[joaat(name)] = true
end

local holding = false
local breathStart = 0
local recoveryUntil = 0
local mustRelease = false
local uiActive = false
local lastPitch = nil
local stableWorldHeading = nil
local activeWeapon = nil

local function setBreathUI(state)
    if uiActive == state then return end
    uiActive = state
    SendNUIMessage({ action = 'alphaZBreath', active = state })
end

local function currentRangedWeapon()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    if RANGED[weapon] then return weapon end
    return nil
end

local function setNormalWeaponTuning(weapon)
    if not weapon then return end
    -- 70 % weniger Kamera-Hochziehen beim Schuss.
    SetWeaponRecoilShakeAmplitude(weapon, NORMAL_RECOIL_SCALE)
end

local function beginBreath(now, weapon)
    holding = true
    breathStart = now
    activeWeapon = weapon
    lastPitch = GetGameplayCamRelativePitch()
    stableWorldHeading = GetGameplayCamRot(2).z
    setBreathUI(true)
end

local function endBreath()
    holding = false
    lastPitch = nil
    stableWorldHeading = nil
    setBreathUI(false)
    SendNUIMessage({ action = 'alphaZBreathProgress', progress = 0.0 })
    if activeWeapon then
        setNormalWeaponTuning(activeWeapon)
    end
end

CreateThread(function()
    -- Recoil fuer alle Fernkampfwaffen auf 30 % setzen.
    for weapon in pairs(RANGED) do
        setNormalWeaponTuning(weapon)
    end

    while true do
        local ped = PlayerPedId()
        local weapon = currentRangedWeapon()
        local aiming = weapon
            and IsPlayerFreeAiming(PlayerId())
            and not IsPedInAnyVehicle(ped, false)

        if aiming then
            activeWeapon = weapon

            -- Normales Zielen: nur halb so starkes Kamera-Schwanken.
            if not holding and IsGameplayCamShaking() then
                SetGameplayCamShakeAmplitude(NORMAL_SWAY_SCALE)
            end

            -- SHIFT ist beim Zielen fuer Luftanhalten reserviert.
            DisableControlAction(0, SHIFT, true)

            local now = GetGameTimer()
            local shiftDown = IsDisabledControlPressed(0, SHIFT)

            if not shiftDown then
                endBreath()
                mustRelease = false

            elseif not mustRelease and now >= recoveryUntil then
                if not holding then
                    beginBreath(now, weapon)
                end

                if now - breathStart < MAX_BREATH_MS then
                    -- Luft anhalten: kein Recoil und kein Kamera-Shake.
                    SetWeaponRecoilShakeAmplitude(weapon, 0.0)
                    StopGameplayCamShaking(true)

                    -- 0.0 = gerade begonnen, 1.0 = Luft komplett verbraucht.
                    local breathProgress = math.min((now - breathStart) / MAX_BREATH_MS, 1.0)
                    SendNUIMessage({
                        action = 'alphaZBreathProgress',
                        progress = breathProgress
                    })

                    -- GTA-Look waehrend Luftanhalten selbst verarbeiten,
                    -- damit Sniper-Sway nicht in die Zielbewegung einfliesst.
                    DisableControlAction(0, 1, true) -- LOOK_LR
                    DisableControlAction(0, 2, true) -- LOOK_UD

                    local lookX = GetDisabledControlNormal(0, 1)
                    local lookY = GetDisabledControlNormal(0, 2)
                    local frameScale = GetFrameTime() * 60.0

                    if lastPitch == nil then
                        lastPitch = GetGameplayCamRelativePitch()
                    end
                    if stableWorldHeading == nil then
                        stableWorldHeading = GetGameplayCamRot(2).z
                    end

                    -- V17: horizontaler Welt-Heading-Lock.
                    -- Beim freien Zielen dreht GTA den Ped-Koerper langsam zur Kamera.
                    -- Ein relativer Heading wuerde dadurch weiterwandern, obwohl die Maus steht.
                    -- Darum speichern wir den Weltwinkel und rechnen jedes Frame die
                    -- aktuelle Ped-Drehung heraus.
                    local horizontalInput = lookX
                    if math.abs(horizontalInput) < 0.004 then
                        horizontalInput = 0.0
                    end

                    if horizontalInput ~= 0.0 then
                        local horizontalScale = HORIZONTAL_SCALE
                        if weapon == joaat('WEAPON_SNIPERRIFLE') then
                            horizontalScale = CROSSBOW_HORIZONTAL_SCALE
                        end
                        stableWorldHeading = stableWorldHeading - (horizontalInput * horizontalScale)
                    end

                    if stableWorldHeading > 180.0 then stableWorldHeading = stableWorldHeading - 360.0 end
                    if stableWorldHeading < -180.0 then stableWorldHeading = stableWorldHeading + 360.0 end

                    local pedHeading = GetEntityHeading(ped)
                    local relativeHeading = stableWorldHeading - pedHeading
                    while relativeHeading > 180.0 do relativeHeading = relativeHeading - 360.0 end
                    while relativeHeading < -180.0 do relativeHeading = relativeHeading + 360.0 end

                    SetGameplayCamRelativeHeading(relativeHeading)

                    -- Vertikal bleibt bei 1.80.
                    lastPitch = lastPitch - (lookY * VERTICAL_SCALE * frameScale)

                    if lastPitch > 89.0 then lastPitch = 89.0 end
                    if lastPitch < -89.0 then lastPitch = -89.0 end
                    SetGameplayCamRelativePitch(lastPitch, 1.0)
                else
                    endBreath()
                    mustRelease = true
                    recoveryUntil = now + RECOVERY_MS
                end
            else
                endBreath()
            end

            Wait(0)
        else
            endBreath()
            mustRelease = false
            activeWeapon = weapon
            Wait(100)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setBreathUI(false)
end)
