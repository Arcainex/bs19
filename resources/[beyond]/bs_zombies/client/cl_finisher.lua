-- bs_zombies - aimed melee finisher

-- Crash guard: only touch peds that exist
local function pedOk(ped, allowDown)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if not allowDown and (IsPedRagdoll(ped) or IsPedGettingUp(ped)) then return false end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return false end
    return true
end

local F = Zombies.Finisher
if not F then return end

local nextAt = 0
local busy = false
local MELEE = GetHashKey('GROUP_MELEE')
local UNARMED = GetHashKey('GROUP_UNARMED')

local kindByHash = {}
for kind, list in pairs(F.weapons or {}) do
    for _, name in ipairs(list) do kindByHash[GetHashKey(name)] = kind end
end

-- Which anim set for this weapon, or nil if it cannot finish.
local function animFor(weapon)
    if not weapon or weapon == 0 then return nil end
    local group = GetWeapontypeGroup(weapon)
    if group == UNARMED then return F.unarmed and F.anims.fists or nil end
    if group ~= MELEE then return nil end
    return F.anims[kindByHash[weapon] or 'large']
end

-- Nearest live walker in front of us within range.
local function target(player)
    if not Zed or not Zed.live then return nil end
    local at = GetEntityCoords(player)
    local fwd = GetEntityForwardVector(player)
    local best, bestDist
    for _, entry in pairs(Zed.live) do
        local ped = entry.ped
        if not entry.dying and ped and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local to = GetEntityCoords(ped) - at
            local d = #to
            if d <= (F.range or 1.6) and d > 0.05 and (not bestDist or d < bestDist) then
                local dot = (to.x * fwd.x + to.y * fwd.y) / d
                if dot >= (F.frontDot or 0.5) then best, bestDist = entry, d end
            end
        end
    end
    return best
end

-- Bounded, and only for dicts that exist.

-- Takedowns need a living, standing player: not dead, downed, ragdolled, carrying someone or attached to a carrier
local function canTakedown()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 or IsPedRagdoll(ped) then return false end
    if LocalPlayer.state.bsDowned then return false end
    if IsEntityAttached(ped) then return false end
    if GetResourceState('bs_medical') == 'started' then
        local ok, v = pcall(function() return exports.bs_medical:IsDowned() end)
        if ok and v then return false end
        ok, v = pcall(function() return exports.bs_medical:IsCarrying() end)
        if ok and v then return false end
    end
    return true
end

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function finish(entry, anim)
    busy = true
    Crumb('finisher', 'id=%s', tostring(entry and entry.id))
    local player = PlayerPedId()
    local zed = entry.ped

    if not canTakedown() or not loadDict(anim.dict) then busy = false; return end
    if not DoesEntityExist(zed) or IsEntityDead(zed) or entry.dying then busy = false; return end

    if (F.stamina or 0) > 0 then
        local pid = PlayerId()
        SetPlayerStamina(pid, math.max(0.0, GetPlayerStamina(pid) - F.stamina))
    end

    local zAt, at = GetEntityCoords(zed), GetEntityCoords(player)
    SetEntityHeading(player, GetHeadingFromVector_2d(zAt.x - at.x, zAt.y - at.y))

    ClearPedTasks(player)
    TaskPlayAnim(player, anim.dict, anim.plyr, 8.0, -8.0, anim.time or 1500, 0, 0.0, false, false, false)

    -- Zombie reaction only if the body is free to animate.
    if pedOk(zed) and HasAnimDictLoaded(anim.dict) then
        SetEntityHeading(zed, GetHeadingFromVector_2d(at.x - zAt.x, at.y - zAt.y))
        if entry.hosted then ClearPedTasks(zed) end
        TaskPlayAnim(zed, anim.dict, anim.victim, 8.0, -8.0, anim.time or 1500, 0, 0.0, false, false, false)
    end
    if Zombies.Growl then Zombies.Growl(entry, 'death') end

    Wait(math.floor((anim.time or 1500) * (F.killAt or 0.55)))
    -- Server-authoritative, same door as the [E] takedown. Head region by definition.
    if not canTakedown() then busy = false; return end
    local hp = (entry.def and entry.def.health) or 220
    TriggerServerEvent('bs:z:hit', entry.id, hp * 10, true, 'finisher')

    Wait(math.floor((anim.time or 1500) * (1.0 - (F.killAt or 0.55))))
    busy = false
end

CreateThread(function()
    while true do
        local wait = 200
        if F.enabled and not busy and Zed then
            local player = PlayerPedId()
            local _, weapon = GetCurrentPedWeapon(player, true)
            local anim = animFor(weapon)
            local aiming = IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, 25)

            if anim and aiming and not IsEntityDead(player) and not IsPedInAnyVehicle(player, false)
               and not IsPedRagdoll(player) and canTakedown() then
                wait = 0
                local entry = target(player)
                if entry then
                    -- Swallow the normal swing while a finisher is on offer.
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 140, true)
                    DisableControlAction(0, 141, true)
                    DisableControlAction(0, 142, true)
                    if IsDisabledControlJustPressed(0, 24) and GetGameTimer() >= nextAt then
                        nextAt = GetGameTimer() + (F.cooldown or 1500)
                        finish(entry, anim)
                    end
                end
            end
        end
        Wait(wait)
    end
end)
