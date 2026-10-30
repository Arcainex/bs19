-- Shared safe teleport. Every staff/debug teleport goes through here so nobody lands in the sky or under the map.
--   exports.bs_core:SafeTeleport(x, y, z, opts) -> ok, finalZ   (blocks, call it from a thread)
--   TriggerClientEvent('bs:core:safeTp', src, x, y, z, opts)    (for server-side callers)
-- z may be nil/false (find the ground). opts: heading, fade (default true), timeout (ms), silent

local busy = 0   -- token of the teleport that owns the ped right now

local function notify(msg, kind)
    TriggerEvent('bs:ui:notify', { type = kind or 'error', message = msg, duration = 5000 })
end

-- Highest surface under (x, y) seen from several heights; ignoreWater is tried second so water counts as ground first
local function probeGround(x, y, z)
    local heights = {}
    if z then heights[#heights + 1] = z + 2.0; heights[#heights + 1] = z + 50.0 end
    heights[#heights + 1] = 1000.0; heights[#heights + 1] = 500.0
    heights[#heights + 1] = 200.0;  heights[#heights + 1] = 100.0
    for _, ignoreWater in ipairs({ false, true }) do
        for _, h in ipairs(heights) do
            local found, gz = GetGroundZFor_3dCoord(x, y, h, ignoreWater)
            if found and gz > -190.0 then return gz end
        end
    end
    return nil
end

-- Last resorts: a safe ped spot, then the nearest road node (only when it is close)
local function fallbackGround(x, y, z)
    local zz = z or 60.0
    local ok, v = GetSafeCoordForPed(x, y, zz, true, 16)
    if ok and v and v.z > -190.0 and #(vector2(v.x, v.y) - vector2(x, y)) < 40.0 then return v.z, v.x, v.y end
    local found, n = GetClosestVehicleNode(x, y, zz, 1, 3.0, 0)
    if found and n and n.z > -190.0 and #(vector2(n.x, n.y) - vector2(x, y)) < 60.0 then return n.z, n.x, n.y end
    return nil
end

local function SafeTeleport(x, y, z, opts)
    opts = type(opts) == 'table' and opts or {}
    x, y = x + 0.0, y + 0.0
    z = tonumber(z) and (z + 0.0) or nil

    busy = busy + 1
    local mine = busy

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

    local doFade = opts.fade ~= false
    local faded = false
    if doFade and IsScreenFadedIn() then
        DoScreenFadeOut(180)
        local t = GetGameTimer() + 1000
        while not IsScreenFadedOut() and GetGameTimer() < t do Wait(0) end
        faded = true
    end

    FreezeEntityPosition(ent, true)
    -- High above the point so nothing can collide or fall through while the world streams in
    local hover = z and math.max(z + 300.0, 400.0) or 1000.0
    SetEntityCoordsNoOffset(ent, x, y, hover, false, false, false)
    SetEntityVelocity(ent, 0.0, 0.0, 0.0)
    SetFocusPosAndVel(x, y, z or 100.0, 0.0, 0.0, 0.0)

    NewLoadSceneStartSphere(x, y, z or 100.0, 300.0, 0)
    local sceneEnd = GetGameTimer() + 2500
    while not IsNewLoadSceneLoaded() and GetGameTimer() < sceneEnd do
        RequestCollisionAtCoord(x, y, z or 100.0)
        Wait(50)
    end
    NewLoadSceneStop()

    local timeout = tonumber(opts.timeout) or 8000
    local startedAt = GetGameTimer()
    local gz, fx, fy
    local fellBack = false

    while GetGameTimer() - startedAt < timeout + 45000 do
        if mine ~= busy then ClearFocus() return false end   -- a newer teleport took over

        RequestCollisionAtCoord(x, y, z or 100.0)
        gz = probeGround(x, y, z)
        if gz then break end

        -- Past the normal wait: try the fallbacks, then keep waiting frozen up in the air
        if GetGameTimer() - startedAt > timeout and not fellBack then
            fellBack = true
            gz, fx, fy = fallbackGround(x, y, z)
            if gz then break end
            -- Known interior point: the given height is the floor
            if z and GetInteriorAtCoords(x, y, z) ~= 0 then gz = z - 1.0 break end
            if faded then DoScreenFadeIn(220) faded = false end
            if not opts.silent then notify('Still loading the ground there, you are held safely in the air. Retrying...', 'info') end
        end
        Wait(250)
        if fellBack and (GetGameTimer() - startedAt) % 2000 < 250 then
            local g2, a, b = fallbackGround(x, y, z)
            if g2 then gz, fx, fy = g2, a, b break end
        end
    end

    if not gz then
        -- Never drop the player: stay frozen high up and say so
        if faded then DoScreenFadeIn(220) end
        ClearFocus()
        if not opts.silent then notify('No ground found there. You are held in the air, teleport again or use noclip.') end
        return false
    end

    local px, py = fx or x, fy or y
    local finalZ = gz + 1.0
    SetEntityCoordsNoOffset(ent, px, py, finalZ, false, false, false)
    if opts.heading then SetEntityHeading(ent, opts.heading + 0.0) end

    -- Wait for collision around the ped; re-place if it still ended up below the ground
    local loadEnd = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() < loadEnd do
        RequestCollisionAtCoord(px, py, finalZ)
        Wait(50)
    end
    local again = probeGround(px, py, finalZ)
    if again and GetEntityCoords(ent).z < again - 0.5 then
        finalZ = again + 1.0
        SetEntityCoordsNoOffset(ent, px, py, finalZ, false, false, false)
    end
    if ent == veh then SetVehicleOnGroundProperly(veh) end

    FreezeEntityPosition(ent, false)
    ClearFocus()

    -- Short watch after release: if it still sinks, put it back on top
    for _ = 1, 20 do
        Wait(75)
        local c = GetEntityCoords(ent)
        if c.z < finalZ - 4.0 then
            FreezeEntityPosition(ent, true)
            SetEntityCoordsNoOffset(ent, px, py, finalZ, false, false, false)
            Wait(300)
            FreezeEntityPosition(ent, false)
            break
        end
    end

    if faded then DoScreenFadeIn(220) end
    return true, finalZ
end

exports('SafeTeleport', SafeTeleport)

-- Server-side callers (they cannot probe collision) fire this at the player
RegisterNetEvent('bs:core:safeTp', function(x, y, z, opts)
    if type(x) ~= 'number' or type(y) ~= 'number' then return end
    CreateThread(function() SafeTeleport(x, y, z or nil, opts) end)
end)
