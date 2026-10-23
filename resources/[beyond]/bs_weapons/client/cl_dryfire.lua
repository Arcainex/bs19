-- bs_weapons - keep an empty gun in hand

local UNARMED = GetHashKey('WEAPON_UNARMED')

-- Telling the engine to stop auto-swapping

-- SetWeaponsNoAutoswap stops the game swapping weapons by itself; deliberate changes (wheel, hotbar, J) are unaffected
local noSwapApplied = false

local function tellEngineToStop()
    local ok = pcall(function()
        SetWeaponsNoAutoswap(true)
        SetWeaponsNoAutoreload(true)
    end)
    noSwapApplied = ok
    return ok
end

CreateThread(function()
    tellEngineToStop()

    while true do
        Wait(10000)
        tellEngineToStop()
    end
end)

AddEventHandler('bs:hook:player:spawned', function()
    CreateThread(function()
        Wait(1000)
        tellEngineToStop()
    end)
end)

-- Last weapon seen in the player's hands (no 'was empty' flag, see the loop).
local lastArmed = nil

-- Set when we put a weapon back, so an engine that keeps taking it does not cause a fight every frame
local restores, restoreWindow = 0, 0

CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()

        -- Cheap early outs: a dead ped stays disarmed, and a ped in a vehicle has its own weapon rules.
        if not ped or ped == 0 or IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
            lastArmed = nil
            Wait(250)
            goto continue
        end

        do
            local _, current = GetCurrentPedWeapon(ped, true)

            if current and current ~= UNARMED then
                lastArmed = current
                if restores > 0 and GetGameTimer() > restoreWindow then restores = 0 end

            elseif lastArmed then
                -- Ask now, not via a 'was empty last frame' flag
                local empty = (GetAmmoInPedWeapon(ped, lastArmed) or 0) <= 0

                -- Does not check Holster.stowed: it was never cleared on draw
                local holster = rawget(_G, 'Holster')
                local holstering = false

                if type(holster) == 'table' then
                    if holster.busy then
                        holstering = true
                    elseif holster.stowedAt
                           and (GetGameTimer() - holster.stowedAt) < 1500 then
                        holstering = true
                    end
                end

                if empty and not holstering then
                    local now = GetGameTimer()

                    -- Budget: three restores inside two seconds means something else wants the weapon gone
                    if now > restoreWindow then
                        restores, restoreWindow = 0, now + 2000
                    end

                    if restores < 3 then
                        restores = restores + 1

                        -- Re-give the weapon if the engine removed it entirely (SetCurrentPedWeapon is a silent no-op otherwise)
                        if not HasPedGotWeapon(ped, lastArmed, false) then
                            GiveWeaponToPed(ped, lastArmed, 0, false, false)
                        end

                        SetCurrentPedWeapon(ped, lastArmed, true)
                    else
                        -- Budget spent: back off, do not give up
                        restoreWindow = now + 1000
                        restores = 0
                    end
                else
                    -- Empty hands we have no claim on: a real holster, or a weapon with rounds that was put away
                    lastArmed = nil
                end
            end
        end

        ::continue::
    end
end)

-- Answering /giveammo

-- The server asks what is in our hands because GetSelectedPedWeapon is networked and lags a draw (see server/sv_ammodebug.lua)
RegisterNetEvent('bs:weapons:whatAmIHolding', function(boxes)
    local ped = PlayerPedId()
    local _, hash = GetCurrentPedWeapon(ped, true)

    local name = nil
    if hash and hash ~= 0 and hash ~= UNARMED then
        -- bs_weapons already keeps the hash->name map, so ask it
        local ok, resolved = pcall(function()
            return exports.bs_weapons:NameOfHash(hash)
        end)
        if ok then name = resolved end
    end

    TriggerServerEvent('bs:weapons:holdingIs', name, boxes)
end)


-- /dryfire - report why the gun was or was not put back

-- Prints every input the restore decision uses, one line each, so a failure can be diagnosed with one command
RegisterCommand('dryfire', function()
    local ped = PlayerPedId()
    local _, current = GetCurrentPedWeapon(ped, true)
    local holster = rawget(_G, 'Holster')
    local hasHolster = type(holster) == 'table'

    local lines = {
        ('in hand   : %s'):format(
            (current and current ~= UNARMED) and tostring(current) or 'UNARMED'),
        ('remembered: %s'):format(lastArmed and tostring(lastArmed) or 'none'),
        ('its ammo  : %s'):format(lastArmed
            and tostring(GetAmmoInPedWeapon(ped, lastArmed) or 0) or '-'),
        ('ped has it: %s'):format(lastArmed
            and tostring(HasPedGotWeapon(ped, lastArmed, false)) or '-'),
        -- Fixed: holster.busy or 'no table' prints 'no table' when busy is false
        ('holster   : %s'):format(hasHolster
            and ('busy=%s stowed=%s stowedAt=%s'):format(
                    tostring(holster.busy),
                    tostring(holster.stowed or '-'),
                    tostring(holster.stowedAt or '-'))
            or 'NO Holster GLOBAL (cl_holster.lua did not load)'),
        ('no-autoswap native: %s'):format(noSwapApplied and 'applied' or 'NOT AVAILABLE on this build'),
        ('restores  : %d used in the current window'):format(restores),
    }

    for _, line in ipairs(lines) do
        print('^5[BeyondSurvival]^7 (dryfire) ' .. line)
    end

    TriggerEvent('bs:ui:notify', { type = 'info', duration = 9000,
        message = table.concat(lines, '\n') })
end, false)
