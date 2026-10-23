-- bs_weapons - R reloads from the bag or not at all

-- INPUT_RELOAD is disabled every frame
local RELOAD_CONTROL = 45

-- R is three controls on PC: 45 INPUT_RELOAD, 140 INPUT_MELEE_ATTACK_ALTERNATE (pistol-whip), 263 INPUT_MELEE_ATTACK1
local MELEE_ALT   = 140
local MELEE_LIGHT = 263

--[[ INPUT_SPRINT. Not disabled - held SHIFT still sprints, and it should;
     this only reads it as a MODIFIER on the R press. See the branch in the
     control loop below for why SHIFT+R is handled there rather than as its
     own key mapping. ]]
local SPRINT_CONTROL = 21

local UNARMED = GetHashKey('WEAPON_UNARMED')

-- One request at a time
local reloading = false
local lastComplaintAt = 0

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

-- Complaints are rate-limited: R is often held down.
local function complain(message)
    local now = GetGameTimer()
    if now - lastComplaintAt < 2000 then return end
    lastComplaintAt = now
    notify('warn', message, 2200)
end

-- Reloadable?
local function isReloadable(ped, hash)
    if not hash or hash == 0 or hash == -1 or hash == UNARMED then return false end
    if not IsWeaponValid(hash) then return false end
    return GetMaxAmmoInClip(ped, hash, 0) > 1
end

-- Rounds on the ped that are NOT in the magazine
local function reserveOf(ped, hash)
    local total = GetAmmoInPedWeapon(ped, hash) or 0
    local _, clip = GetAmmoInClip(ped, hash)
    return math.max(0, total - (clip or 0))
end

-- Ask the server for a box, then reload
local function requestReload(need, hasReserve)
    if reloading then return end
    reloading = true

    CreateThread(function()
        -- need = rounds short of a full mag; the server takes enough boxes
        local result = BSB.Await('inventory:reload', 8000, need)

        if result and not result.ok and hasReserve then
            -- Bag is dry but there are paid rounds on the ped: use those.
            MakePedReload(PlayerPedId())
        elseif not result then
            complain(L('wp.reload_fail'))
        elseif not result.ok then
            complain(result.error or L('wp.no_rounds_weapon'))
        else
            Wait(50)
            MakePedReload(PlayerPedId())
        end

        reloading = false
    end)
end


CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local _, hash = GetCurrentPedWeapon(ped, true)

        if isReloadable(ped, hash) then
            DisableControlAction(0, RELOAD_CONTROL, true)

            -- Melee controls are disabled in the same frame as the reload control, so no swing can start between the press and the read
            DisableControlAction(0, MELEE_ALT, true)
            DisableControlAction(0, MELEE_LIGHT, true)

            if IsDisabledControlJustPressed(0, RELOAD_CONTROL) and not reloading then
                local _, clip = GetAmmoInClip(ped, hash)
                local reserve = reserveOf(ped, hash)

                -- SHIFT+R (check magazine) is handled first and consumes the press, so it never also reloads
                local shift = IsDisabledControlPressed(0, SPRINT_CONTROL)
                    or IsControlPressed(0, SPRINT_CONTROL)

                if shift and Weapons and Weapons.CheckMagazine then
                    if Weapons.CheckMagazine(ped, hash) then goto continue end
                end

                -- Hands busy looking into the magazine: not also reloading.
                if Weapons and Weapons.IsCheckingMagazine
                    and Weapons.IsCheckingMagazine() then goto continue end

                -- Mag size from config (extended mag aware), not the engine's.
                local mag = Weapons.ClientMagSize and Weapons.ClientMagSize(ped, hash)
                    or GetMaxAmmoInClip(ped, hash, true)
                local need = mag - (clip or 0) - reserve

                if (clip or 0) >= mag then
                    complain(L('wp.already_loaded'))
                elseif need <= 0 then
                    -- Reserve covers it: already paid for, take nothing.
                    MakePedReload(ped)
                else
                    requestReload(need, reserve > 0)
                end
            end

            ::continue::
            Wait(0)
        else
            -- Nothing reloadable in hand: leave R alone (the engine uses it for other things; this file only handles firearms)
            Wait(250)
        end
    end
end)
