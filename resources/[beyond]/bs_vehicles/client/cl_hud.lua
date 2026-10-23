-- bs_vehicles - dash data: speed, RPM, gear, fuel, engine, body

-- Player choices are kept in KVP; a missing key falls back to the config default.
local KVP_ON, KVP_UNIT, KVP_SCALE, KVP_SIDE = 'bs_carhud_on', 'bs_carhud_unit', 'bs_carhud_scale', 'bs_carhud_side'
local KVP_STYLE, KVP_OPACITY = 'bs_carhud_style', 'bs_carhud_opacity'

local enabled = Vehicles.Hud.enabled
local unit = Vehicles.Hud.unit
local sideOverride = nil -- nil = auto (opposite the stats HUD), 'L' or 'R' = pinned
local scale = Vehicles.Hud.scale or 1.0
local SCALE_MIN, SCALE_MAX = 0.6, 2.4
local style = Vehicles.Hud.style or 'field'
local opacity = 100 -- percent
local drawStyle = 'field' -- resolved style;. VIP checked on the slow tick, not every frame

local function styleDef(id)
    for _, d in ipairs(Vehicles.Hud.styles or {}) do
        if d.id == id then return d end
    end
end

-- VIP mirror from bs_vip (server synced)
local function isVip()
    if GetResourceState('bs_vip') ~= 'started' then return false end
    local ok, v = pcall(function() return exports.bs_vip:IsVIP() end)
    return ok and v == true
end

local function styleAllowed(id)
    local d = styleDef(id)
    if not d then return false end
    return not d.vip or isVip()
end

-- What the dash actually draws: a VIP style falls back to field if VIP lapsed.
local function activeStyle()
    if styleAllowed(style) then return style end
    return 'field'
end

do
    local on = GetResourceKvpInt(KVP_ON) -- 1 = on, 2 = off, 0 = never set
    if on == 1 then enabled = true elseif on == 2 then enabled = false end
    local u = GetResourceKvpString(KVP_UNIT)
    if u == 'kmh' or u == 'mph' then unit = u end
    local s = GetResourceKvpFloat(KVP_SCALE)
    if s and s > 0 then scale = math.max(SCALE_MIN, math.min(SCALE_MAX, s)) end
    local side = GetResourceKvpString(KVP_SIDE)
    if side == 'L' or side == 'R' then sideOverride = side end
    local st = GetResourceKvpString(KVP_STYLE)
    if st and styleDef(st) then style = st end
    local op = GetResourceKvpInt(KVP_OPACITY)
    if op and op >= 10 and op <= 100 then opacity = op end
    if not (styleDef(style) or {}).vip then drawStyle = style end -- VIP styles wait for the first slow tick
end

local function saveSettings()
    SetResourceKvpInt(KVP_ON, enabled and 1 or 2)
    SetResourceKvp(KVP_UNIT, unit)
    SetResourceKvpFloat(KVP_SCALE, scale)
    SetResourceKvp(KVP_SIDE, sideOverride or 'auto')
    SetResourceKvp(KVP_STYLE, style)
    SetResourceKvpInt(KVP_OPACITY, opacity)
end

local function send(payload)
    if GetResourceState('bs_ui') ~= 'started' then return end
    pcall(function() exports.bs_ui:Send(payload) end)
end

RegisterCommand(Vehicles.Hud.toggleCommand, function()
    enabled = not enabled
    if not enabled then send({ action = 'dashhud', show = false }) end
    saveSettings()
    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = enabled and L('hud.on') or L('hud.off'),
        duration = 2000,
    })
end, false)

RegisterCommand(Vehicles.Hud.unitCommand, function()
    unit = (unit == 'kmh') and 'mph' or 'kmh'
    saveSettings()
    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = L('hud.unit', { unit = unit == 'kmh' and 'km/h' or 'mph' }),
        duration = 2000,
    })
end, false)

-- /bs_carhud_scale [size] - set the dash size
RegisterCommand('bs_carhud_scale', function(_, args)
    local requested = tonumber(args[1])
    if requested then
        scale = math.max(SCALE_MIN, math.min(SCALE_MAX, requested))
    else
        scale = scale + 0.15
        if scale > SCALE_MAX then scale = SCALE_MIN end
    end
    saveSettings()

    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = L('hud.size', { size = ('%.2f'):format(scale) }),
        duration = 2000,
    })
end, false)

-- /bs_carhud_side [left|right|auto] - pin the panel or go back to auto-avoid.
RegisterCommand('bs_carhud_side', function(_, args)
    local pick = args[1] and tostring(args[1]):lower()
    if pick == 'left' or pick == 'l' then sideOverride = 'L'
    elseif pick == 'right' or pick == 'r' then sideOverride = 'R'
    else sideOverride = nil end
    saveSettings()

    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = sideOverride and (sideOverride == 'L' and L('hud.pinned_left') or L('hud.pinned_right'))
            or L('hud.auto'),
        duration = 2400,
    })
end, false)

exports('SetDashHudVisible', function(on)
    enabled = on and true or false
    if not enabled then send({ action = 'dashhud', show = false }) end
    saveSettings()
end)
exports('DashHudVisible', function() return enabled end)

-- Used by the Settings tab in bs_inventory. Same values the commands set.
exports('GetDashHudSettings', function()
    return { on = enabled, unit = unit, scale = scale, side = sideOverride or 'auto',
             style = style, opacity = opacity, vip = isVip(), styles = Vehicles.Hud.styles }
end)

exports('ApplyDashHudSettings', function(patch)
    if type(patch) ~= 'table' then return end
    if type(patch.on) == 'boolean' then
        enabled = patch.on
        if not enabled then send({ action = 'dashhud', show = false }) end
    end
    if patch.unit == 'kmh' or patch.unit == 'mph' then unit = patch.unit end
    local s = tonumber(patch.scale)
    if s then scale = math.max(SCALE_MIN, math.min(SCALE_MAX, s)) end
    if patch.side == 'L' or patch.side == 'R' then sideOverride = patch.side
    elseif patch.side == 'auto' then sideOverride = nil end
    -- locked VIP styles are refused here, not just greyed out in the menu
    if type(patch.style) == 'string' and styleAllowed(patch.style) then style = patch.style; drawStyle = style end
    local op = tonumber(patch.opacity)
    if op then opacity = math.floor(math.max(10, math.min(100, op))) end
    saveSettings()
end)


local function partDef(id)
    for _, part in ipairs(Vehicles.Parts) do
        if part.id == id then return part end
    end
end

-- Same GOOD/WORN/POOR/GONE ladder as cl_radial's diagnose readout, so both always agree.
local function condLabel(value, def)
    if not def then return 'GOOD' end
    if value <= (def.fail or 0) then return 'GONE' end
    if value <= (def.warn or 50) then return 'POOR' end
    if value < 85 then return 'WORN' end
    return 'GOOD'
end

-- Body has no wear entry; GetVehicleBodyHealth is 0..1000, so it gets the same ladder.
local function bodyLabel(vehicle)
    local frac = math.max(0.0, math.min(1.0, GetVehicleBodyHealth(vehicle) / 1000.0))
    if frac <= 0.15 then return 'GONE' end
    if frac <= 0.45 then return 'POOR' end
    if frac < 0.85 then return 'WORN' end
    return 'GOOD'
end


local panelSide = 'R' -- resolved side for THIS frame; recomputed on a slow tick

CreateThread(function()
    while true do
        Wait(1500)
        drawStyle = activeStyle()
        if sideOverride then
            panelSide = sideOverride
        elseif GetResourceState('bs_ui') == 'started' then
            local ok, settings = pcall(function() return exports.bs_ui:GetHudSettings() end)
            local anchor = ok and settings and settings.hudAnchor or 'bottom-left'
            -- Sit in the corner the stats cluster is not in.
            panelSide = (anchor == 'bottom-right') and 'L' or 'R'
        end
    end
end)


CreateThread(function()
    local wasDriving = false

    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local driving = enabled and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

        if not driving then
            if wasDriving then send({ action = 'dashhud', show = false }) end
            wasDriving = false
            Wait(400)
            goto continue
        end
        wasDriving = true
        -- ~30 updates a second is smooth enough for a gauge and much cheaper than every frame
        Wait(33)

        local speedRaw = GetEntitySpeed(vehicle)
        local speed = unit == 'mph' and (speedRaw * 2.236936) or (speedRaw * 3.6)

        local ok, rpm = pcall(GetVehicleCurrentRpm, vehicle)
        if not ok or type(rpm) ~= 'number' then rpm = 0.0 end

        local gearOk, gear = pcall(GetVehicleCurrentGear, vehicle)
        if not gearOk or type(gear) ~= 'number' then gear = nil end

        local fuel = 60.0
        local fok, tank = pcall(function() return exports.bs_vehicles:TankLevel() end)
        if fok and type(tank) == 'number' then fuel = tank end

        local engineWear = 100.0
        if Wear and Wear.Current then
            local current = Wear.Current()
            if current then engineWear = current.engine or 100.0 end
        end

        -- Extra facts for the dash: raw percentages, engine/lights/lock state and heading.
        local hullPct = math.max(0.0, math.min(100.0, GetVehicleBodyHealth(vehicle) / 10.0))
        local _, lightsOn, highBeams = GetVehicleLightsState(vehicle)
        local lockStatus = GetVehicleDoorLockStatus(vehicle)

        send({
            action = 'dashhud',
            enginePct = engineWear,
            hullPct   = hullPct,
            engineOn  = GetIsVehicleEngineRunning(vehicle) and true or false,
            lights    = (highBeams == 1 or highBeams == true) and 2 or ((lightsOn == 1 or lightsOn == true) and 1 or 0),
            locked    = lockStatus == 2 or lockStatus == 4 or lockStatus == 10,
            heading   = GetEntityHeading(vehicle),
            show   = true,
            style  = drawStyle,
            opacity = opacity,
            side   = panelSide,
            scale  = scale,
            speed  = speed,
            unit   = unit,
            rpm    = rpm,
            gear   = gear,
            fuel   = fuel,
            engine = condLabel(engineWear, partDef('engine')),
            hull   = bodyLabel(vehicle),
        })

        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then send({ action = 'dashhud', show = false }) end
end)
