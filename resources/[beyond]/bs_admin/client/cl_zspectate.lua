-- bs_admin - staff camera that follows the nearest spawned zombie until ESC

local active   = false
local cam      = nil
local watching = nil          -- the ped currently being followed
local body     = nil          -- the admin's own ped, remembered for restore

-- Finding one

-- Nearest spawned walker to a point, skipping one we gave up on.
-- @return number|nil ped
-- @return number distance
local function nearestWalker(from, skip)
    if GetResourceState('bs_zombies') ~= 'started' then return nil, 0 end

    local ok, live = pcall(function() return exports.bs_zombies:Live() end)
    if not ok or type(live) ~= 'table' then return nil, 0 end

    local best, bestD = nil, math.huge

    for _, entry in pairs(live) do
        local ped = entry and entry.ped
        if ped and ped ~= skip and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local d = #(from - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end

    return best, bestD
end

-- A camera with no visible way out gets closed with Alt-F4.

local function drawHint(text)
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextColour(226, 220, 204, 210)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.92)
end

-- Stopping: written first and called from everywhere

function AdminZSpectateStop()
    if not active then return end
    active   = false
    watching = nil

    RenderScriptCams(false, false, 0, true, true)
    if cam then
        DestroyCam(cam, false)
        cam = nil
    end

    local ped = (body and DoesEntityExist(body)) and body or PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetEntityCollision(ped, true, true)
    SetLocalPlayerVisibleLocally(true)
    body = nil

    TriggerEvent('bs:ui:notify', {
        type = 'info', message = 'Stopped spectating.', duration = 2200,
    })
end

-- Is the staff camera up? Used by the noclip toggle and the menu.
function AdminZSpectateActive() return active end

-- Starting

-- "There are no zombies" message

function AdminZSpectateDiagnose()
    local result = BSB.Await('zombies:nearest', 6000)

    if not result or not result.ok then
        return (result and result.error) or 'the registry has no walkers at all - the server is not spawning'
    end

    local near = result.near or 0
    if near == 0 then
        return ('nothing within 100m - the nearest walker is %.0fm away')
            :format(result.distance or 0)
    end

    -- The server has walkers here and this client drew none. Name the reason if spawn() recorded one.
    local reason = nil
    local ok, failures = pcall(function() return exports.bs_zombies:Failures() end)

    if ok and type(failures) == 'table' then
        local worstKey, worstN = nil, 0
        for k, n in pairs(failures) do
            if n > worstN then worstKey, worstN = k, n end
        end

        if worstKey == 'ground' then
            reason = ('%d failed to find ground'):format(worstN)
        elseif worstKey then
            reason = ('%d failed on %s - try /zvanilla')
                :format(worstN, (worstKey:gsub('^model:', 'model ')))
        end
    end

    return ('the server has %d walker(s) within 100m and this client has drawn NONE%s')
        :format(near, reason and (' - ' .. reason) or ' - no reason recorded, check F8')
end

-- @return table result  { ok = true, text = ... } | { error = ... }
function AdminZSpectateNearest()
    if active then
        AdminZSpectateStop()
        return { ok = true, text = 'Spectating stopped.' }
    end

    if GetResourceState('bs_zombies') ~= 'started' then
        return { error = 'bs_zombies is not running' }
    end

    local ped = PlayerPedId()
    local at  = GetEntityCoords(ped)

    local target, distance = nearestWalker(at, nil)
    if not target then return { error = AdminZSpectateDiagnose() } end

    body     = ped
    watching = target
    active   = true

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetLocalPlayerVisibleLocally(false)

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, true)

    CreateThread(function()
        local lost = 0

        while active do
            Wait(0)

            -- ESC is disabled so the pause menu does not open under the camera
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)

            if IsDisabledControlJustPressed(0, 200)
               or IsDisabledControlJustPressed(0, 322) then
                AdminZSpectateStop()
                break
            end

            -- The walker can die, be culled or stream out. Re-acquire once before dropping the camera.
            if not watching or not DoesEntityExist(watching) or IsEntityDead(watching) then
                local from = (body and DoesEntityExist(body))
                    and GetEntityCoords(body) or GetEntityCoords(PlayerPedId())

                local next_, _ = nearestWalker(from, watching)
                if next_ then
                    watching = next_
                    lost = 0
                else
                    lost = lost + 1
                    if lost > 120 then       -- ~2 seconds of nothing at all
                        TriggerEvent('bs:ui:notify', {
                            type = 'warn',
                            message = 'Nothing left to watch here.',
                            duration = 2600,
                        })
                        AdminZSpectateStop()
                        break
                    end
                    goto continue
                end
            end

            do
                local tc = GetEntityCoords(watching)
                local h  = GetEntityHeading(watching)

                -- Behind and above, looking the way the walker faces.
                local rad = math.rad(h)
                local eye = vector3(
                    tc.x + math.sin(rad) * 3.2,
                    tc.y - math.cos(rad) * 3.2,
                    tc.z + 1.35)

                SetCamCoord(cam, eye.x, eye.y, eye.z)
                PointCamAtCoord(cam, tc.x, tc.y, tc.z + 0.2)

                -- Keep streaming focus on the walker, not the frozen body, or the camera flies into unloaded map.
                SetFocusPosAndVel(tc.x, tc.y, tc.z, 0.0, 0.0, 0.0)

                local away = (body and DoesEntityExist(body))
                    and #(GetEntityCoords(body) - tc) or 0.0

                drawHint(('SPECTATING  -  %.0fm from your body  -  ESC to stop')
                    :format(away))
            end

            ::continue::
        end

        -- Whatever ended the loop, streaming focus goes back to the player.
        ClearFocus()
    end)

    return {
        ok = true,
        text = ('Spectating the nearest walker, %.0fm away. ESC to stop.'):format(distance),
    }
end

-- Never leave it up

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then AdminZSpectateStop() end
end)

-- A staff member who dies while spectating still needs their body back.
AddEventHandler('bs:hook:player:died', function() AdminZSpectateStop() end)
AddEventHandler('bs:hook:player:spawned', function() AdminZSpectateStop() end)

-- Also a console command

RegisterCommand('zspectate', function()
    CreateThread(function()
        local result = AdminZSpectateNearest()
        if result.error then
            TriggerEvent('bs:ui:notify', { type = 'warn', message = result.error })
        elseif result.text then
            TriggerEvent('bs:ui:notify', { type = 'info', message = result.text, duration = 4200 })
        end
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/zspectate',
    'Watch the nearest walker - ESC to stop')

-- Force-spawn is also a command, so it can be repeated without the menu closing
RegisterCommand('zforce', function()
    CreateThread(function()
        local result = AdminForceZombie and AdminForceZombie()
        if result and result.error then
            TriggerEvent('bs:ui:notify', { type = 'warn', message = result.error, duration = 8000 })
        end
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/zforce',
    'Force one walker to spawn 5m in front of you (staff)')
