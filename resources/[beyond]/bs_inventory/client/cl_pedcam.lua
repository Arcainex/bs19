-- bs_inventory - your character in the bag screen.
-- The NUI cannot draw a ped, so the ped stays in the world, a scripted camera points at it and the page leaves a hole (`.pedstage` in style.css). The camera is offset so the ped lands on the left third where the layout has room; the CSS and camera must agree.
-- bs_multichar/client/cl_scene.lua does the same for the creator, but with a separate preview ped; this one shows the ped you actually play.
-- Must not move or freeze the player, and every exit path destroys the camera (a stuck scripted camera needs a relog); the resource stop handler destroys it again.

local Cam = {
    handle = nil,
    active = false,
}

-- Where the character stands on screen. `side` shifts the camera along its right vector, sliding the ped across the frame without turning it. Positive composes the ped in the right-side portrait column. Tuned for 16:9; on wider screens the ped drifts slightly further from center.
local VIEW = {
    -- A head-to-feet portrait needs distance, not a larger FOV: a wide lens distorts the clothes.
    distance = 3.55,
    cameraHeight = 0.20,  -- low camera, aligned with the full-body composition
    aimHeight = 0.24,     -- lower aim lifts the complete figure into frame
    side = 1.30,          -- beside the UI while keeping weapons inside frame
    fov = 42.0,
}

local function destroy()
    Cam.active = false

    if Cam.handle then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(Cam.handle, true)
        Cam.handle = nil
    end

    -- The timecycle modifier must be cleared too, or the world stays lit after the menu closes.
    ClearTimecycleModifier()
    SetUseHiDof()

    -- The player may have a permanent gameplay filter. This menu owns the camera, not their look, so restore the saved filter on exit.
    if GetResourceState('bs_ui') == 'started' then
        pcall(function() exports.bs_ui:RestoreFilter() end)
    end
end

Cam.Destroy = destroy

function Cam.Start()
    if Cam.active then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if IsPedDeadOrDying(ped, true) then return end

    local at = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local view = VIEW

    -- In a vehicle: pull back far enough to frame the whole car, aimed at its middle.
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local mn, mx = GetModelDimensions(GetEntityModel(veh))
        local size = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
        at = GetEntityCoords(veh)
        heading = GetEntityHeading(veh)
        view = {
            distance = math.max(VIEW.distance, size * 1.45),
            cameraHeight = (mx.z - mn.z) * 0.45,
            aimHeight = (mx.z - mn.z) * 0.15,
            side = VIEW.side * math.max(1.0, size / 2.6),
            fov = VIEW.fov,
            far = size * 2.2,
        }
    end

    -- In front of the ped, in the direction it faces, not at a fixed world angle (which can put the camera inside a wall).
    local rad = math.rad(heading)
    local fx, fy = -math.sin(rad), math.cos(rad)   -- the ped's forward
    local rx, ry =  math.cos(rad), math.sin(rad)   -- and its right

    local cx = at.x + fx * view.distance + rx * view.side
    local cy = at.y + fy * view.distance + ry * view.side
    local cz = at.z + view.cameraHeight

    Cam.handle = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        cx, cy, cz, 0.0, 0.0, 0.0, view.fov, false, 0)
    if not Cam.handle then return end

    -- Aimed at a point offset like the camera, so the ped sits off-center in a straight-on shot instead of a three-quarter view.
    PointCamAtCoord(Cam.handle,
        at.x + rx * view.side,
        at.y + ry * view.side,
        at.z + view.aimHeight)

    SetCamActive(Cam.handle, true)
    RenderScriptCams(true, true, 420, true, true)

    -- Depth of field so the world behind the character falls away; the game blur bs_inventory fades in does the rest.
    SetCamUseShallowDofMode(Cam.handle, true)
    SetCamNearDof(Cam.handle, 0.55)
    -- keep the whole car sharp when framing a vehicle
    SetCamFarDof(Cam.handle, math.max(3.20, view.distance + (view.far or 0) * 0.5))
    SetCamDofStrength(Cam.handle, 0.85)

    -- Add a light on the ped; at night a portrait without its own light is a silhouette. The modifier is cleared on every exit path (see destroy()).

    -- Shallow camera DOF keeps the survivor sharp. A global timecycle blur would soften both, so it is omitted.


    Cam.active = true

    -- HiDof is a this-frame flag, so re-assert it every frame while the camera lives. The loop ends itself when the camera goes.
    CreateThread(function()
        while Cam.active and Cam.handle do
            SetUseHiDof()
            Wait(0)
        end
    end)
end

-- Turning on the spot to see the back of the outfit. Dragging the portrait sends an angle; the ped turns, not the camera, so the background does not spin.
function Cam.Turn(delta)
    if not Cam.active then return end

    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    -- seated peds can not turn; leave the car alone
    if GetVehiclePedIsIn(ped, false) ~= 0 then return end

    SetEntityHeading(ped, (GetEntityHeading(ped) + (delta or 0.0)) % 360.0)
end

exports('PedCamActive', function() return Cam.active end)

AddEventHandler('bs:hook:player:died', destroy)
AddEventHandler('bs:hook:player:unloaded', destroy)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then destroy() end
end)

BSInvPedCam = Cam
