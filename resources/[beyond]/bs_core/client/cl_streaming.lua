-- Streaming focus watchdog and the "Refresh all game textures" fix.
-- Cameras (selector, drone, spectate, cinecam, tutorial) move focus away from the player on purpose.
-- If one of them forgets to give it back, the world around the player stops loading: blurry LOD buildings, roads without collision.

local refreshing = false

local function notify(kind, key)
    TriggerEvent('bs:ui:notify', { type = kind, message = L(key), duration = 4000 })
end

-- True while something legitimately owns the camera or is moving the player.
local function focusOwned(ped)
    if GetRenderingCam() ~= -1 then return true end
    if IsEntityPositionFrozen(ped) then return true end
    if IsPlayerSwitchInProgress() then return true end
    if LocalPlayer.state.bsDrone then return true end
    return false
end

local function focusOnPlayer(ped)
    if IsEntityFocus(ped) then return true end
    local veh = GetVehiclePedIsIn(ped, false)
    return veh ~= 0 and IsEntityFocus(veh)
end

CreateThread(function()
    local strikes, logged = 0, false
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if BS.IsLoaded() and not refreshing and not focusOwned(ped) and not focusOnPlayer(ped) then
            strikes = strikes + 1
            -- A few seconds of grace, a teleport or camera can be between two steps
            if strikes >= 3 then
                ClearFocus()
                if IsNewLoadSceneActive() then NewLoadSceneStop() end
                strikes = 0
                if not logged then
                    logged = true
                    print('^3[BeyondSurvival]^7 streaming focus was away from the player - reset')
                end
            end
        else
            strikes = 0
        end
    end
end)

--- Puts streaming back on the player and reloads the world around them.
local function refreshTextures()
    if refreshing then notify('info', 'core.tex_busy') return false end
    if not BS.IsLoaded() then return false end
    refreshing = true
    notify('info', 'core.tex_start')

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local interior = GetInteriorFromEntity(ped)
    local room = interior ~= 0 and GetRoomKeyFromEntity(ped) or 0

    ClearFocus()
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    pcall(ClearHdArea)
    pcall(ClearRoomForEntity, ped)
    RequestCollisionAtCoord(c.x, c.y, c.z)

    NewLoadSceneStartSphere(c.x, c.y, c.z, 150.0, 0)
    local deadline = GetGameTimer() + 10000
    local nextAsk = 0
    while IsNewLoadSceneActive() and not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do
        -- Not every frame: each request takes a streaming slot
        if GetGameTimer() >= nextAsk then
            RequestCollisionAtCoord(c.x, c.y, c.z)
            nextAsk = GetGameTimer() + 1000
        end
        Wait(100)
    end
    NewLoadSceneStop()

    -- Inside a building the room itself can be the stale part
    if interior ~= 0 then
        pcall(RefreshInterior, interior)
        if room ~= 0 then pcall(ForceRoomForEntity, ped, interior, room) end
    end

    ClearFocus()
    -- bs_pause puts the player's graphics preset (LOD scale, budgets) back
    TriggerEvent('bs:streaming:refreshed')

    refreshing = false
    notify('success', 'core.tex_done')
    return true
end

exports('RefreshTextures', function()
    CreateThread(refreshTextures)
    return true
end)

RegisterCommand('refreshtextures', function() CreateThread(refreshTextures) end, false)
TriggerEvent('chat:addSuggestion', '/refreshtextures', 'Reload the world around you (blurry or missing textures)')
