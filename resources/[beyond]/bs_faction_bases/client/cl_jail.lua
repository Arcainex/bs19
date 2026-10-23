-- bs_faction_bases - jail client: teleport to the cell, keep the inmate in the radius, draw a timer. The server owns the clock and release.

local Jail = nil        -- { cell, origin, radius, remaining, scope, cellNo }
local EndsAt = 0        -- GetGameTimer() ms when the local timer runs out
local Running = false

local function notify(msg, kind) TriggerEvent('bs:ui:notify', { type=kind or 'info', message=msg, duration=5000 }) end

local function teleport(p)
    if not p then return end
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end
    DoScreenFadeOut(250)
    local untilAt = GetGameTimer() + 600
    while not IsScreenFadedOut() and GetGameTimer() < untilAt do Wait(0) end
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) end
    RequestCollisionAtCoord(p.x, p.y, p.z)
    SetEntityCoords(ped, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, (p.h or 0.0) + 0.0)
    local collisionUntil = GetGameTimer() + 2000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < collisionUntil do Wait(0) end
    DoScreenFadeIn(250)
end

local function drawTimer()
    local left = math.max(0, math.floor((EndsAt - GetGameTimer()) / 1000))
    local text = L('fb.jail_timer', { cell = Jail.cellNo or '?', time = ('%02d:%02d'):format(math.floor(left / 60), left % 60) })
    SetTextFont(4); SetTextScale(0.45, 0.45); SetTextColour(214, 170, 92, 230)
    SetTextOutline(); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.035)
end

local function run()
    if Running then return end
    Running = true
    CreateThread(function()
        local nextCheck = 0
        while Jail do
            drawTimer()
            local now = GetGameTimer()
            if now >= nextCheck then
                nextCheck = now + 500
                local ped = PlayerPedId()
                if DoesEntityExist(ped) and Jail.origin then
                    local c = GetEntityCoords(ped)
                    local o = Jail.origin
                    if #(c - vector3(o.x, o.y, o.z)) > (Jail.radius or 25.0) then
                        notify(L('fb.cant_leave'), 'warn')
                        teleport(Jail.cell)
                    end
                end
            end
            Wait(0)
        end
        Running = false
    end)
end

RegisterNetEvent('bs:jail:enter', function(data)
    if type(data) ~= 'table' or not data.cell then return end
    local fresh = Jail == nil
    Jail = data
    EndsAt = GetGameTimer() + (tonumber(data.remaining) or 0) * 1000
    CreateThread(function() teleport(data.cell) end)
    if fresh then notify(L('fb.jailed', { min = math.ceil((tonumber(data.remaining) or 0) / 60) }), 'error') end
    run()
end)

RegisterNetEvent('bs:jail:release', function(exit)
    Jail = nil
    if type(exit) == 'table' and exit.x then CreateThread(function() teleport(exit) end) end
end)

exports('IsJailed', function() return Jail ~= nil end)
