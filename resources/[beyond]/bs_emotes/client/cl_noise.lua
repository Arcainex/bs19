-- bs_emotes - everything the world can hear.
-- Decides that something loud happened here, this far out, and tells the
-- server. bs_zombies listens to 'bs:world:noise'.

Noise = {}

-- Throttle is per noise kind, so one kind cannot swallow another. It exists to
-- stop a weapon bridge and the shooting watcher publishing the same shot twice.
local lastSent = {}

--- @param kind string   key in Emotes.Noise
--- @param coords vector3
--- @param radiusOverride number|nil
function Noise.Make(kind, coords, radiusOverride)
    -- A suppressed shot must not reach the local zombie AI or the server POI board.
    if kind == 'silenced' or kind == 'melee' then return end
    local radius = radiusOverride or Emotes.Noise[kind] or 20.0
    coords = coords or GetEntityCoords(PlayerPedId())

    -- One accepted noise feeds both local simulation and the server. The throttle
    -- runs before the local event so the same shot is not published twice.
    local now = GetGameTimer()
    if now - (lastSent[kind] or 0) < 220 then return end
    lastSent[kind] = now

    TriggerEvent('bs:world:noise', {
        kind = kind, radius = radius,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        source = GetPlayerServerId(PlayerId()),
    })
    TriggerServerEvent('bs:world:noise', kind, { x = coords.x, y = coords.y, z = coords.z }, radius)
end

exports('MakeNoise', function(kind, coords, radius) return Noise.Make(kind, coords, radius) end)

RegisterNetEvent('bs:world:noiseRelay', function(payload)
    TriggerEvent('bs:world:noise', payload)
end)

-- Automatic sources

-- Gunfire: a suppressed weapon makes no noise at all.
-- bs_weapons:IsSuppressed() answers from the fitted attachment (and optionally
-- the engine silencer flag). If yes we return before emitting anything, local
-- event included, since bs_zombies cl_ai listens to the local 'bs:world:noise'.
-- If bs_weapons is missing or errors, fall back to the engine flag and
-- NoiseScale. A missing dependency must make the gun loud, never silent.
CreateThread(function()
    while true do
        Wait(0)

        -- A disarmed watcher costs one table lookup per frame. Config is read every
        -- pass so a reload takes effect.
        local sources = Emotes.NoiseSources
        if sources and sources.gunfire == false then
            Wait(1000)
            goto continue
        end

        do
            local ped = PlayerPedId()

            if IsPedShooting(ped) then
                local _, weapon = GetCurrentPedWeapon(ped, true)

                -- The engine knows a suppressor is fitted whoever fitted it. This only picks
                -- the kind; silence is decided below by bs_weapons.
                local silenced = weapon and IsPedCurrentWeaponSilenced(ped)
                local kind = silenced and 'silenced' or 'gunshot'
                local radius = Emotes.Noise[kind] or 20.0

                local suppressed = false
                if GetResourceState('bs_weapons') == 'started' then
                    local ok, answer = pcall(function() return exports.bs_weapons:IsSuppressed() end)
                    suppressed = (ok and answer == true)
                end

                if suppressed or silenced then
                    -- Fitted suppressor or native silencer: no attraction.
                    Wait(120)
                else
                    -- Extra scaling from bs_weapons on top. Only reached when the weapon is not
                    -- fully suppressed, so config can say 'this muzzle device halves it'.
                    if GetResourceState('bs_weapons') == 'started' then
                        local ok, scale = pcall(function() return exports.bs_weapons:NoiseScale() end)
                        if ok and type(scale) == 'number' and scale < 1.0 and not silenced then
                            radius = radius * scale
                        end
                    end

                    Noise.Make(kind, GetEntityCoords(ped), radius)
                    Wait(120)
                end
            else
                Wait(80)
            end
        end

        ::continue::
    end
end)

-- Catches firearm implementations where IsPedShooting does not stay true long
-- enough for the generic watcher above.
AddEventHandler('bs:weapons:shot', function()
    local ped = PlayerPedId()
    local _, weapon = GetCurrentPedWeapon(ped, true)
    local silenced = weapon and IsPedCurrentWeaponSilenced(ped)
    local suppressed = false
    if GetResourceState('bs_weapons') == 'started' then
        local ok, answer = pcall(function() return exports.bs_weapons:IsSuppressed() end)
        suppressed = ok and answer == true
    end
    if silenced or suppressed then return end
    local kind = 'gunshot'
    Noise.Make(kind, GetEntityCoords(ped), Emotes.Noise[kind] or 20.0)
end)

-- Sprinting is quiet compared to a gunshot, but not silent.
CreateThread(function()
    while true do
        Wait(900)
        local sources = Emotes.NoiseSources
        if not (sources and sources.sprint == false) then
            local ped = PlayerPedId()
            if exports.bs_core:IsLoaded() and IsPedSprinting(ped) and not IsPedInAnyVehicle(ped, false) then
                Noise.Make('sprint', GetEntityCoords(ped))
            end
        end
    end
end)

-- Melee noise is off by default (Emotes.NoiseSources.melee). Melee is the
-- quiet answer to a walker. If you turn it on, make it per swing - this loop
-- fires every 250ms for the whole fight.
CreateThread(function()
    while true do
        Wait(250)
        local sources = Emotes.NoiseSources
        if not sources or sources.melee == true then
            local ped = PlayerPedId()
            if exports.bs_core:IsLoaded() and IsPedInMeleeCombat(ped) then
                Noise.Make('melee', GetEntityCoords(ped))
            end
        else
            -- Disarmed: idle cheaply instead of polling a native.
            Wait(1000)
        end
    end
end)
