-- bs_vehicles - scroll-wheel throttle: the wheel raises/lowers a held throttle level

local KVP_ON, KVP_UI = 'bs_wheelthr_on', 'bs_wheelthr_ui'
local enabled = GetResourceKvpInt(KVP_ON) == 1 -- default OFF
local showUi = GetResourceKvpInt(KVP_UI) ~= 2  -- default ON
local level = 0 -- -100..100, step 5; below 0 = brake/reverse
local STEP = 5
local lastSent = nil

local function send(p)
    if GetResourceState('bs_ui') ~= 'started' then return end
    pcall(function() exports.bs_ui:Send(p) end)
end

local function pushUi(show, force)
    local key = (show and showUi) and level or false
    if not force and key == lastSent then return end
    lastSent = key
    send({ action = 'throttle', show = key ~= false, level = level })
end

exports('GetCruiseSettings', function() return { wheelThrottle = enabled, throttleUi = showUi } end)
exports('ApplyCruiseSettings', function(p)
    if type(p) ~= 'table' then return end
    if type(p.wheelThrottle) == 'boolean' then
        enabled = p.wheelThrottle
        SetResourceKvpInt(KVP_ON, enabled and 1 or 2)
        if not enabled then level = 0; pushUi(false) end
    end
    if type(p.throttleUi) == 'boolean' then
        showUi = p.throttleUi
        SetResourceKvpInt(KVP_UI, showUi and 1 or 2)
        lastSent = nil
    end
end)

-- scroll up = control 15/17, scroll down = 14/16 (weapon wheel / weapon select)
local RADIO_WHEEL = { 14, 15, 16, 17, 81, 82, 83, 84, 99, 100 }

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if not enabled or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
            if level ~= 0 or lastSent ~= false then level = 0; pushUi(false) end
            Wait(300)
        else
            Wait(0)
            for i = 1, #RADIO_WHEEL do DisableControlAction(0, RADIO_WHEEL[i], true) end
            if not IsNuiFocused() and not IsPauseMenuActive() then
                if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) then
                    level = math.min(100, level + STEP)
                elseif IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) then
                    level = math.max(-100, level - STEP)
                end
            end
            -- read the player's own keys first, then inject
            local w, s = IsControlPressed(0, 71), IsControlPressed(0, 72)
            if not w and not s and level ~= 0 then
                if level > 0 then SetControlNormal(0, 71, level / 100.0)
                else SetControlNormal(0, 72, -level / 100.0) end
            end
            pushUi(true)
        end
    end
end)

AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() then send({ action = 'throttle', show = false }) end
end)
