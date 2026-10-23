-- bs_weapons - Shift+R: take the magazine out and look at it

Weapons = Weapons or {}

local UNARMED = GetHashKey('WEAPON_UNARMED')

local checking = false
local lastAt = 0

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

-- Resolving a clip that is really there

-- Same idea as resolveWorkAnim in cl_main.lua
local resolved, resolvedChecked = nil, false

local function resolveAnim()
    if resolvedChecked then return resolved end
    resolvedChecked = true

    local candidates = (Weapons.MagCheck and Weapons.MagCheck.anims) or {}

    for _, c in ipairs(candidates) do
        if c and c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end
            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    resolved = c
                    print(('^2[BeyondSurvival]^7 (weapons) magazine-check animation: %s / %s')
                        :format(c.dict, c.clip))
                    return resolved
                end
            end
        end
    end

    -- No clip resolved: the check still works and shows the count after the same delay, just without animation
    print('^3[BeyondSurvival]^7 (weapons) no magazine-check animation resolved - the check will be silent')
    return nil
end

-- What you see when you look

-- Magazine fill is reported in words (like looking at a real mag)
local function describe(clip, max)
    if clip <= 0 then return 'empty' end
    if max <= 0 then return L('wp.rounds_n', { n = clip }) end

    local fraction = clip / max

    if clip == max      then return L('wp.mag_full') end
    if fraction >= 0.75 then return L('wp.mag_nearly') end
    if fraction >= 0.5  then return L('wp.mag_over_half') end
    if fraction >= 0.25 then return L('wp.mag_under_half') end
    if clip <= 3        then return L('wp.mag_almost_empty') end
    return L('wp.mag_low')
end

-- The check

-- True when this weapon has a magazine to look into at all
local function hasMagazine(ped, hash)
    if not hash or hash == 0 or hash == -1 or hash == UNARMED then return false end
    if not IsWeaponValid(hash) then return false end
    return GetMaxAmmoInClip(ped, hash, 0) > 1
end

-- Called from cl_reload.lua's control loop (the only place R is read)
function Weapons.CheckMagazine(ped, hash)
    if checking then return true end

    local cfg = Weapons.MagCheck or {}
    local now = GetGameTimer()
    if now - lastAt < (cfg.cooldown or 900) then return true end

    ped = ped or PlayerPedId()
    if not hasMagazine(ped, hash) then return false end

    -- Refused quietly while in a vehicle, ragdolled or swimming, where the animation would glitch.
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedSwimming(ped)
        or IsPedFalling(ped) or IsEntityDead(ped) then
        return false
    end

    lastAt = now
    checking = true

    CreateThread(function()
        local anim = resolveAnim()
        local time = cfg.time or 2200

        if anim then
            TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0, time,
                anim.flag or 48, 0.0, false, false, false)
        end

        -- The readout lands mid-gesture: look is how far into the animation the mag is up where the character can see it
        Wait(math.floor(time * (cfg.look or 0.45)))

        -- Re-read at the moment of looking rather than reusing a value taken on the keypress
        local current = PlayerPedId()
        local _, weapon = GetCurrentPedWeapon(current, true)

        if weapon == hash and not IsEntityDead(current) then
            local _, clip = GetAmmoInClip(current, hash)
            clip = clip or 0
            local max = (Weapons.ClientMagSize and Weapons.ClientMagSize(current, hash))
                or GetMaxAmmoInClip(current, hash, true) or 0
            local reserve = math.max(0, (GetAmmoInPedWeapon(current, hash) or 0) - clip)

            local magText = cfg.exact
                and ('%d / %d'):format(clip, max)
                or describe(clip, max)

            notify(clip > 0 and 'info' or 'warn',
                L(reserve == 1 and 'wp.mag_check_one' or 'wp.mag_check', { mag = magText, n = reserve }),
                cfg.notifyTime or 3000)
        end

        -- The rest of the gesture: seating the magazine again
        Wait(time - math.floor(time * (cfg.look or 0.45)))
        checking = false
    end)

    return true
end

-- True while the gesture is playing
function Weapons.IsCheckingMagazine() return checking end

-- Nothing should be left mid-animation by a restart or a death
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if checking then ClearPedTasks(PlayerPedId()) end
    checking = false
end)

AddEventHandler('bs:hook:player:unloaded', function() checking = false end)
