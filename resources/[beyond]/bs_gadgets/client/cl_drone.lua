-- Scout drone: a real networked drone, flown from a scripted camera while the
-- pilot stands still with a tablet (and can be bitten). Every exit path goes
-- through restore(), which is safe to call more than once.

local G = GadgetCl

local D = nil   -- the running flight, or nil

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- Same smoothing as bs_cinecam: frame-rate independent ease, alpha = 1 - e^(-dt/tau).
local function ease(dt, tau)
    if not tau or tau <= 0.0 then return 1.0 end
    return 1.0 - math.exp(-dt / tau)
end
local function angleDelta(a, b) return (b - a + 180.0) % 360.0 - 180.0 end

local function forwardOf(yaw, pitch)
    local y, p = math.rad(yaw), math.rad(pitch or 0.0)
    local c = math.cos(p)
    return vector3(-math.sin(y) * c, math.cos(y) * c, math.sin(p))
end

--------------------------------------------------------------- marks

local marks = {}    -- entity -> { blip, untilAt }

local function mark(ent, sprite, colour, label, secs)
    if marks[ent] then marks[ent].untilAt = GetGameTimer() + secs * 1000; return end
    local b = AddBlipForEntity(ent)
    SetBlipSprite(b, sprite); SetBlipColour(b, colour); SetBlipScale(b, 0.6)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(label); EndTextCommandSetBlipName(b)
    G.Blips[b] = true
    marks[ent] = { blip = b, untilAt = GetGameTimer() + secs * 1000, zombie = sprite == 1 }
end

-- Marks outlive the flight; this drops them when they expire or the ped dies.
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for ent, m in pairs(marks) do
            if now > m.untilAt or not DoesEntityExist(ent) or (m.zombie and IsEntityDead(ent)) then
                if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end
                G.Blips[m.blip] = nil
                marks[ent] = nil
            end
        end
    end
end)

local function vipColours()
    if GetResourceState('bs_vip') ~= 'started' then return 1, 5 end
    local ok, row = pcall(function() return exports.bs_vip:BoosterSkin('drone') end)
    if ok and type(row) == 'table' then return row.zombie or 1, row.loot or 5 end
    return 1, 5
end

local function scan(t, camPos)
    local zCol, lCol = vipColours()
    local n = 0
    for _, ped in ipairs(GetGamePool('CPed')) do
        if G.IsZombie(ped) and IsEntityOnScreen(ped) then
            local c = GetEntityCoords(ped)
            if #(c - camPos) <= t.markRadius and G.Los(camPos, c + vector3(0, 0, 0.6), D and D.drone or 0) then
                mark(ped, 1, zCol, L('gad.mark_infected'), t.markSecs); n = n + 1
            end
        end
    end
    if t.markLoot and Containers and Containers.ByModel then
        for _, obj in ipairs(GetGamePool('CObject')) do
            local m = GetEntityModel(obj)
            local sm = (m and m > 0x7FFFFFFF) and (m - 0x100000000) or m
            if (Containers.ByModel[m] or Containers.ByModel[sm]) and IsEntityOnScreen(obj) then
                local c = GetEntityCoords(obj)
                if #(c - camPos) <= t.markRadius * 0.6 then mark(obj, 478, lCol, L('gad.mark_loot'), t.markSecs); n = n + 1 end
            end
        end
    end
    return n
end

-------------------------------------------------------------- restore

local function restore()
    if not D then return end
    local d = D
    D = nil
    G.Busy = false
    LocalPlayer.state:set('bsDrone', false, false)
    RenderScriptCams(false, false, 0, true, true)
    if d.cam and DoesCamExist(d.cam) then DestroyCam(d.cam, false) end
    ClearFocus()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    if d.sound then StopSound(d.sound); ReleaseSoundId(d.sound) end
    local ped = PlayerPedId()
    StopAnimTask(ped, d.t.animDict, d.t.animName, 2.0)
    G.Delete(d.tablet)
    G.Nui({ action = 'drone', show = false })
    TriggerEvent('bs:ui:closed', 'drone')   -- framework HUD + XP bar back
    return d
end

-- Drone falls out of the sky, then the server cleans it up.
local function drop(d, reason)
    if not d or not d.drone or not DoesEntityExist(d.drone) then
        TriggerServerEvent('bs:gadgets:ended', 'drone', reason); return
    end
    local obj = d.drone
    FreezeEntityPosition(obj, false)
    SetEntityHasGravity(obj, true)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
    SetTimeout(d.t.fallMs or 4000, function()
        TriggerServerEvent('bs:gadgets:ended', 'drone', reason)
        G.Delete(obj)
    end)
end

-- Flies back to the pilot, then packs away.
-- battery-weighted seconds used (hover counts less, boost more)
local function flown(d) return d.used or (GetGameTimer() - (d.startedAt or GetGameTimer())) / 1000.0 end

local function recall(d)
    local obj = d.drone
    if not obj or not DoesEntityExist(obj) then TriggerServerEvent('bs:gadgets:ended', 'drone', 'recalled', flown(d)); return end
    CreateThread(function()
        local tEnd = GetGameTimer() + 4000
        while GetGameTimer() < tEnd and DoesEntityExist(obj) do
            local p = GetEntityCoords(obj)
            local home = GetEntityCoords(PlayerPedId()) + vector3(0.0, 0.0, 1.2)
            local v = home - p
            local dist = #v
            if dist < 1.0 then break end
            local step = math.min(dist, 12.0 * GetFrameTime())
            local n = p + v / dist * step
            SetEntityCoordsNoOffset(obj, n.x, n.y, n.z, false, false, false)
            Wait(0)
        end
        TriggerServerEvent('bs:gadgets:ended', 'drone', 'recalled', flown(d))
        G.Delete(obj)
    end)
end

local function finish(reason)
    Crumb('gadget', 'drone stop %s', tostring(reason))
    local d = restore()
    if not d then return end
    if reason == 'exit' then recall(d)
    elseif reason == 'server' then G.Delete(d.drone)
    else drop(d, reason) end
end

G.Stops.drone = nil
G.DroneStart = function(t, extra)
    if D then return end
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 0.6 + vector3(0.0, 0.0, 1.3)
    local drone, netId = G.SpawnNet(t.model, start, GetEntityHeading(ped))
    if not drone then
        G.Notify(L('gad.launch_fail'), 'error')
        TriggerServerEvent('bs:gadgets:ended', 'drone', 'failed'); return
    end
    FreezeEntityPosition(drone, true)
    SetEntityCollision(drone, true, true)
    SetEntityCanBeDamaged(drone, true)
    SetEntityMaxHealth(drone, 1000); SetEntityHealth(drone, 1000)
    local nets = { netId }

    -- tablet in hand, looping anim, pilot stays where they are
    local tablet
    local th = G.LoadModel(t.tablet)
    if th then
        local c = GetEntityCoords(ped)
        tablet = CreateObject(th, c.x, c.y, c.z, true, true, false)
        SetModelAsNoLongerNeeded(th)
        G.Spawned[tablet] = true
        AttachEntityToEntity(tablet, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
        nets[#nets + 1] = NetworkGetNetworkIdFromEntity(tablet)
    end
    TriggerServerEvent('bs:gadgets:attach', 'drone', nets)
    if G.LoadDict(t.animDict) then
        TaskPlayAnim(ped, t.animDict, t.animName, 3.0, -3.0, -1, 49, 0, false, false, false)
    end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(cam, (t.fov or 70.0) + 0.0)
    SetCamCoord(cam, start.x, start.y, start.z)
    RenderScriptCams(true, true, 400, true, true)
    SetTimecycleModifier(Gadgets.Fx.camMod)
    SetTimecycleModifierStrength(0.6)

    local sound = GetSoundId()
    PlaySoundFromEntity(sound, Gadgets.Fx.droneLoop, drone, Gadgets.Fx.droneSet, true, 0)

    -- battery from the item: seconds left and the full-charge length
    extra = type(extra) == 'table' and extra or {}
    local full = (tonumber(extra.secs) or t.battery) / math.max(0.01, Gadgets.DrainMul or 1.0)
    local flight = tonumber(extra.left) or full
    Crumb('gadget', 'drone start')
    D = { t = t, drone = drone, tablet = tablet, cam = cam, sound = sound, startedAt = GetGameTimer(), used = 0.0 }
    G.Busy = true
    LocalPlayer.state:set('bsDrone', true, false)  -- other resources' keybinds check this
    TriggerEvent('bs:ui:opened', 'drone')   -- bs_ui hides its HUD + XP bar (UI.HideHudFor)
    if t.hidePilotDrone ~= false then SetEntityLocallyInvisible(drone) end
    G.Stops.drone = function() finish('server') end

    CreateThread(function()
        local d = D
        local yaw, pitch = GetEntityHeading(ped), -10.0
        local tYaw, tPitch = yaw, pitch
        local vel = vector3(0.0, 0.0, 0.0)
        local startedAt = GetGameTimer()
        local hp = t.health
        local lastPedHp = GetEntityHealth(ped)
        local nextScan, lowWarned = 0, false
        local pingCd = 0
        local totalMarks = 0

        while D == d do
            local dt = GetFrameTime()
            local now = GetGameTimer()
            ped = PlayerPedId()
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true)   -- chat
            EnableControlAction(0, 249, true)   -- push to talk

            -- exits that aren't the pilot's choice
            if G.Downed() then finish('down'); break end
            local php = GetEntityHealth(ped)
            if t.exitOnHit and php < lastPedHp then
                G.Notify(L('gad.hit_drop'), 'error'); finish('exit'); break
            end
            lastPedHp = php
            if not DoesEntityExist(d.drone) then
                restore(); TriggerServerEvent('bs:gadgets:ended', 'drone', 'destroyed'); break
            end

            -- drone health (other players' hits are applied by the server)
            local h = GetEntityHealth(d.drone)
            local byPed = HasEntityBeenDamagedByAnyPed(d.drone)
            if h < 1000 or byPed then
                if LocalPlayer.state.bsFactionSafeZone ~= true and not G.HitByOtherPlayer(d.drone) then
                    hp = hp - math.max(0, 1000 - h)
                    if byPed and h >= 1000 then hp = hp - 25 end
                end
                SetEntityHealth(d.drone, 1000)
                ClearEntityLastDamageEntity(d.drone)
            end
            if hp <= 0 then
                -- camera back first, then the server removes it and plays the fx
                restore(); TriggerServerEvent('bs:gadgets:ended', 'drone', 'destroyed'); break
            end

            HideHudAndRadarThisFrame()
            if t.hidePilotDrone ~= false then SetEntityLocallyInvisible(d.drone) end

            -- battery (drain rate from last frame's movement)
            d.used = d.used + dt * (d.rate or 1.0)
            local left = flight - d.used
            if left <= 10.0 and not lowWarned then
                lowWarned = true
                PlaySoundFrontend(-1, Gadgets.Fx.lowSound, Gadgets.Fx.lowSet, true)
            end
            if left <= 0 then finish('battery'); break end

            -- look
            local smooth = t.smooth ~= false
            tYaw = tYaw - GetDisabledControlNormal(0, 1) * 6.0
            tPitch = clamp(tPitch - GetDisabledControlNormal(0, 2) * 6.0, -85.0, 30.0)
            if smooth then
                local a = ease(dt, t.lookSmooth or 0.08)
                yaw = yaw + angleDelta(yaw, tYaw) * a
                pitch = pitch + (tPitch - pitch) * a
            else
                yaw, pitch = tYaw, tPitch
            end

            -- move
            local fwd = forwardOf(yaw, 0.0)
            local right = vector3(fwd.y, -fwd.x, 0.0)
            local move = vector3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + fwd end
            if IsDisabledControlPressed(0, 33) then move = move - fwd end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            local speed = t.speed * (IsDisabledControlPressed(0, 21) and t.boost or 1.0)
            local vert = 0.0
            if IsDisabledControlPressed(0, 22) then vert = t.climb end
            if IsDisabledControlPressed(0, 36) then vert = -t.climb end
            local len = #move
            if len > 0.01 then move = move / len * speed end
            move = move + vector3(0.0, 0.0, vert)
            -- ease the velocity, not the position: ramps up and coasts (inertia)
            if smooth then
                vel = vel + (move - vel) * ease(dt, t.accel or 0.35)
                if #vel < 0.02 and #move < 0.01 then vel = vector3(0.0, 0.0, 0.0) end
                move = vel
            end
            local boosting = len > 0.01 and IsDisabledControlPressed(0, 21)
            if boosting then d.rate = t.boostDrain or 1.0
            elseif len > 0.01 or vert ~= 0.0 then d.rate = 1.0
            else d.rate = t.idleDrain or 1.0 end

            local pos = GetEntityCoords(d.drone)
            local target = pos + move * dt
            local home = GetEntityCoords(ped)
            if target.z - home.z > t.maxHeight then target = vector3(target.x, target.y, home.z + t.maxHeight) end
            if #(move) > 0.01 then
                local probe = target + (target - pos) / math.max(0.001, #(target - pos)) * 0.5
                if G.Los(pos, probe, d.drone) then
                    SetEntityCoordsNoOffset(d.drone, target.x, target.y, target.z, false, false, false)
                    pos = target
                else
                    vel = vector3(0.0, 0.0, 0.0)   -- bumped something: kill the drift
                end
            end
            -- nose tilts into the move
            local tilt = clamp(-#vector3(move.x, move.y, 0.0) * 1.5, -20.0, 0.0)
            SetEntityRotation(d.drone, tilt, 0.0, yaw, 2, true)

            -- camera under and ahead of the frame so the props stay out of shot
            local cf = forwardOf(yaw, 0.0) * (t.camForward or 0.35)
            SetCamCoord(d.cam, pos.x + cf.x, pos.y + cf.y, pos.z - (t.camDown or 0.35))
            SetCamRot(d.cam, pitch, 0.0, yaw, 2)

            -- zoom: hold ALT (control 19, the same key as the ALT dot / hotbar
            -- peek, which stand down while bsDrone is set) narrows the FOV
            local baseFov = (t.fov or 70.0) + 0.0
            local zFov = clamp((t.zoomFov or 25.0) + 0.0, 5.0, baseFov)
            local wantFov = IsDisabledControlPressed(0, 19) and zFov or baseFov
            d.fov = d.fov or baseFov
            d.fov = d.fov + (wantFov - d.fov) * ease(dt, t.zoomSpeed or 0.18)
            SetCamFov(d.cam, d.fov)
            SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)

            -- signal
            local dist = #(pos - home)
            local ratio = dist / t.maxRange
            local static = clamp((ratio - t.staticFrom) / (1.0 - t.staticFrom), 0.0, 1.0)
            if static > 0.0 then
                SetExtraTimecycleModifier(Gadgets.Fx.staticMod)
                SetExtraTimecycleModifierStrength(static)
            else
                ClearExtraTimecycleModifier()
            end
            if ratio >= 1.0 then finish('signal'); break end

            -- marks
            if now >= nextScan then
                nextScan = now + t.markEveryMs
                totalMarks = scan(t, pos)
            end
            for ent, m in pairs(marks) do
                if m.zombie and DoesEntityExist(ent) then
                    local c = GetEntityCoords(ent)
                    DrawMarker(0, c.x, c.y, c.z + 1.25, 0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35, 230, 60, 50, 170, true, false, 2, false, nil, nil, false)
                end
            end

            -- ping
            if IsDisabledControlJustPressed(0, 38) and now >= pingCd then
                pingCd = now + 2000
                local dir = forwardOf(yaw, pitch)
                local to = pos + dir * 400.0
                local ray = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z, to.x, to.y, to.z, 1 + 16, d.drone, 7)
                local _, hit, at = GetShapeTestResult(ray)
                if hit == 1 or hit == true then TriggerServerEvent('bs:gadgets:ping', at.x, at.y, at.z) end
            end

            -- exit
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 23) then finish('exit'); break end

            -- hud, a few times a second is plenty
            if not d.hudAt or now >= d.hudAt then
                local spd = d.lastPos and #(pos - d.lastPos) / math.max(0.001, (now - d.hudAt + 150) / 1000.0) or 0.0
                d.lastPos = pos
                d.hudAt = now + 150
                -- range to whatever is under the reticle
                local dir = forwardOf(yaw, pitch)
                local to = pos + dir * 500.0
                local ray = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z, to.x, to.y, to.z, 1 + 16, d.drone, 7)
                local _, hit, at = GetShapeTestResult(ray)
                local range = (hit == 1 or hit == true) and #(at - pos) or -1
                -- time left if you keep doing what you're doing now
                local rate = d.rate or 1.0
                G.Nui({
                    action = 'drone', show = true,
                    battery = clamp(left / full, 0.0, 1.0), secs = math.max(0, math.ceil(left / rate)),
                    alt = pos.z - home.z, dist = dist, maxRange = t.maxRange,
                    signal = clamp(1.0 - ratio, 0.0, 1.0), static = static, ratio = clamp(ratio, 0.0, 1.0),
                    hp = clamp(hp / t.health, 0.0, 1.0), marks = totalMarks,
                    heading = (360.0 - yaw) % 360.0, pitch = pitch, speed = spd, range = range,
                    boost = rate > 1.0, idle = rate < 1.0,
                    zoom = (t.fov or 70.0) / math.max(1.0, d.fov or (t.fov or 70.0)),
                })
            end
            Wait(0)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    restore()
    for _, m in pairs(marks) do if DoesBlipExist(m.blip) then RemoveBlip(m.blip) end end
end)

-- a crash mid-flight must not leave keybinds blocked
LocalPlayer.state:set('bsDrone', false, false)
