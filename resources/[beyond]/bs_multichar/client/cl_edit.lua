-- BeyondSurvival - bs_multichar appearance edit mode: the creator's LOOK tab on your live character. Opened by bs_vip (monthly VIP change or staff ticket); the server checks entitlement on open and on save. Only face/hair change, clothes are restored after each preview.

AppearanceEdit = { active = false }
local E = AppearanceEdit

local COMPS = { 3, 4, 6, 8, 11 }

local function notify(kind, msg)
    TriggerEvent('bs:ui:notify', { type = kind, message = msg, duration = 3600 })
end

--- Face/hair on the live ped, keeping what they are wearing.
local function applyLive(appearance)
    local ped = PlayerPedId()
    local keep = {}
    for _, c in ipairs(COMPS) do
        keep[c] = { GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c), GetPedPaletteVariation(ped, c) }
    end
    exports.bs_core:ApplyAppearanceTo(ped, appearance)
    for c, v in pairs(keep) do SetPedComponentVariation(ped, c, v[1], v[2], v[3]) end
end

local function placeCam()
    local ped = PlayerPedId()
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local fwd = GetEntityForwardVector(ped)
    local dist = E.dist or 0.9
    local cam = E.cam or CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    E.cam = cam
    SetCamCoord(cam, head.x + fwd.x * dist, head.y + fwd.y * dist, head.z + 0.05)
    PointCamAtCoord(cam, head.x, head.y, head.z)
    SetCamFov(cam, 40.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
end

local function finish(restore)
    if not E.active then return end
    E.active = false
    if restore and E.original then applyLive(E.original) end
    if E.cam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(E.cam, false)
        E.cam = nil
    end
    FreezeEntityPosition(PlayerPedId(), false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('bs:ui:closed', 'appearance')
end

local function begin()
    if E.active then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) or IsPedDeadOrDying(PlayerPedId(), true) then
        return notify('warn', L('mc.stand_still'))
    end
    local r = BSB.Await('multichar:appearanceBegin', 8000)
    if not r or not r.ok then return notify('warn', (r and r.error) or L('mc.no_change')) end

    E.active = true
    E.original = r.appearance or {}
    E.dist = 0.9
    TriggerEvent('bs:ui:opened', 'appearance')
    FreezeEntityPosition(PlayerPedId(), true)
    ClearPedTasksImmediately(PlayerPedId())
    placeCam()

    SendNUIMessage({
        action = 'editAppearance',
        appearance = r.schema or {},
        current = r.appearance or {},
        gender = r.gender,
        kind = r.kind,
    })
    SetNuiFocus(true, true)
end

exports('OpenAppearanceEditor', function() CreateThread(begin) end)

-- Hooks used by cl_main's shared NUI callbacks while editing.
function E.Draft(draft) if E.active and draft then applyLive(draft.appearance or {}) end end
function E.Rotate(delta)
    local ped = PlayerPedId()
    SetEntityHeading(ped, GetEntityHeading(ped) + (tonumber(delta) or 0))
    placeCam()
end
function E.Zoom(delta)
    E.dist = math.max(0.5, math.min(2.2, (E.dist or 0.9) + (tonumber(delta) or 0)))
    placeCam()
end

RegisterNUICallback('editSave', function(data, cb)
    if not E.active then return cb({ ok = false }) end
    CreateThread(function()
        local r = BSB.Await('multichar:appearanceSave', 10000, data and data.appearance)
        if not r or not r.ok then
            return cb({ ok = false, error = (r and r.error) or 'No answer.' })
        end
        E.original = r.appearance
        applyLive(r.appearance)
        finish(false)
        notify('success', r.kind == 'ticket' and L('mc.saved_ticket') or L('mc.saved'))
        cb({ ok = true })
    end)
end)

RegisterNUICallback('editCancel', function(_, cb) finish(true); cb({ ok = true }) end)

-- Never leave the player frozen.
AddEventHandler('bs:hook:player:unloaded', function() finish(true) end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then finish(true) end end)
CreateThread(function()
    while true do
        if E.active then
            Wait(0)
            DisableAllControlActions(0)
            if IsPedDeadOrDying(PlayerPedId(), true) then finish(true) end
        else
            Wait(500)
        end
    end
end)
