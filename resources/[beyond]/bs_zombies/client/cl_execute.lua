-- BeyondSurvival - zombies: one-hit execution from behind (E) on a walker that has not noticed you

local E = Zombies.Execute
local nextExecute = 0

-- Takedowns need a living, standing player: not dead, downed, ragdolled, carrying or being carried
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

local function isBlade(hash)
    for _, name in ipairs(E.blades or {}) do
        if GetHashKey(name) == hash then return true end
    end
    return false
end

--- The nearest walker you could execute right now, or nil.
local function candidate()
    if not Zed then return nil end

    local player = PlayerPedId()
    local at = GetEntityCoords(player)
    local forward = GetEntityForwardVector(player)

    local best, bestDist

    for _, entry in pairs(Zed.live) do
        if not entry.dying and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped) then
            local zAt = GetEntityCoords(entry.ped)
            local dist = #(zAt - at)

            if dist <= (E.range or 1.8) and (not bestDist or dist < bestDist) then
                -- Are we behind it?
                local zForward = GetEntityForwardVector(entry.ped)
                local toUs = at - zAt
                local len = #(toUs)
                local dot = len > 0.01
                    and ((zForward.x * (toUs.x / len)) + (zForward.y * (toUs.y / len)))
                    or 1.0

                local unaware = entry.state ~= 'hunting' and entry.state ~= 'grab'
                local behind  = dot <= (E.behindDot or -0.1)

                if (not E.onlyUnaware or unaware) and (behind or unaware) then
                    best, bestDist = entry, dist
                end
            end
        end
    end

    return best
end

local function play(anim)
    local ped = PlayerPedId()
    if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) end
    local waited = 0
    while not HasAnimDictLoaded(anim.dict) and waited < 1500 do Wait(10); waited = waited + 10 end
    if not HasAnimDictLoaded(anim.dict) then return false end

    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.time or 1200, 0, 0.0, false, false, false)
    return true
end

local function execute(entry)
    local now = GetGameTimer()
    if now < nextExecute or not canTakedown() then return end
    Crumb('execute', 'id=%s', tostring(entry and entry.id))
    nextExecute = now + (E.cooldown or 1200)

    local player = PlayerPedId()
    local _, weapon = GetCurrentPedWeapon(player, true)
    local blade = weapon and isBlade(weapon)

    local anim = blade and E.anims.knife or E.anims.fists

    local zAt = GetEntityCoords(entry.ped)
    local at = GetEntityCoords(player)
    SetEntityHeading(player, GetHeadingFromVector_2d(zAt.x - at.x, zAt.y - at.y))

    play(anim)

    -- It stops dead the moment the animation starts - a walker that keeps walking out of an execution looks like a missed hit
    if entry.hosted then ClearPedTasks(entry.ped) end
    Zombies.Growl(entry, 'death')

    CreateThread(function()
        Wait(math.floor((anim.time or 1200) * 0.55))

        -- Reported as damage like anything else, so the server kills it once and everybody sees the same body
        if not canTakedown() then return end
        TriggerServerEvent('bs:z:hit', entry.id, (entry.def.health or 220) * 10, true, 'execution')
    end)
end

-- The prompt

CreateThread(function()
    while true do
        local wait = 250

        if E.enabled and exports.bs_core:IsLoaded() and Zed and canTakedown() then
            local entry = candidate()

            if entry then
                wait = 0

                -- E is also the interaction key, so it is disabled here to avoid opening a door too.
                DisableControlAction(0, E.key, true)

                SetTextFont(4)
                SetTextScale(0.0, 0.38)
                SetTextColour(216, 210, 194, 225)
                SetTextDropshadow(2, 0, 0, 0, 255)
                SetTextOutline()
                SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString(L('zed.take_down'))
                DrawText(0.5, 0.62)

                if IsDisabledControlJustPressed(0, E.key) then
                    execute(entry)
                end
            end
        end

        Wait(wait)
    end
end)
