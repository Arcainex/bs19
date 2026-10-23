-- bs_crafting client: feeds the CRAFT tab in the inventory (bs_inventory/html/js/craft.js), station zones, work animations.

local S = Crafting.Settings
local ctx = { kind = 'hand' }        -- what the craft tab shows: hand | station | recycler
local zones = {}                      -- [id] = true
local stationAnim = nil

local function notify(kind, msg) TriggerEvent('bs:ui:notify', { type = kind, message = msg }) end

--------------------------------------------------------------------------------
-- Animations with a hand prop
--------------------------------------------------------------------------------

local function loadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function attachProp(model)
    if not model or not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(model) then return nil end
    local ped = PlayerPedId()
    local obj = CreateObject(GetHashKey(model), GetEntityCoords(ped), false, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 57005), 0.1, 0.02, -0.02, -80.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

function CraftStopAnim()
    if not stationAnim then return end
    local ped = PlayerPedId()
    if stationAnim.dict then StopAnimTask(ped, stationAnim.dict, stationAnim.clip, 1.0) end
    if stationAnim.prop and DoesEntityExist(stationAnim.prop) then DeleteEntity(stationAnim.prop) end
    stationAnim = nil
end

-- anims: list of { dict, clip }; first that loads wins. flag 1 = loop, 49 = upper body + can walk.
function CraftPlayAnim(anims, prop, flag)
    CraftStopAnim()
    for _, a in ipairs(anims or {}) do
        if loadDict(a.dict) then
            TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 3.0, 3.0, -1, flag or 1, 0.0, false, false, false)
            stationAnim = { dict = a.dict, clip = a.clip, prop = attachProp(prop) }
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- The craft tab
--------------------------------------------------------------------------------

local function openTab(kind, id)
    if exports.bs_inventory:IsOpen() then
        exports.bs_inventory:Close()
        Wait(300)
    end
    -- Set after the close: closing resets the context.
    ctx = { kind = kind, id = id }
    exports.bs_inventory:Open('craft')
end

exports('OpenCraft', function() CreateThread(function() openTab('hand') end) end)
-- bs_recycler and others show their own machine view in the same tab.
exports('OpenContext', function(kind, id) CreateThread(function() openTab(kind, id) end) end)
exports('Context', function() return ctx end)

AddEventHandler('bs:ui:closed', function(what)
    if what ~= 'inventory' then return end
    if ctx.kind == 'station' then CraftStopAnim() end
    ctx = { kind = 'hand' }
end)

-- NUI calls from craft.js. The page lives in bs_inventory, the calls land here by resource name.
RegisterNUICallback('state', function(_, cb)
    CreateThread(function()
        local base = { context = ctx, dict = BSLocale.Dict(), lang = BSLocale.Lang() }
        if ctx.kind == 'recycler' then return cb(base) end
        local r = BSB.Await('crafting:state', 8000, ctx.kind == 'station' and ctx.id or nil)
        base.data = r
        cb(base)
    end)
end)

RegisterNUICallback('queue', function(d, cb)
    CreateThread(function()
        local r = BSB.Await('crafting:queue', 8000, d.id, d.count or 1, ctx.kind == 'station' and ctx.id or nil)
        cb(r or { ok = false })
    end)
end)

RegisterNUICallback('cancel', function(d, cb)
    CreateThread(function()
        cb(BSB.Await('crafting:cancel', 8000, d.id, ctx.kind == 'station' and ctx.id or nil) or { ok = false })
    end)
end)

RegisterNUICallback('take', function(d, cb)
    CreateThread(function()
        cb(BSB.Await('crafting:take', 8000, ctx.id, d.item, d.amount) or { ok = false })
    end)
end)

RegisterNUICallback('farm', function(d, cb)
    CreateThread(function()
        local r = BSB.Await('crafting:farm', 8000, ctx.id, d.action, d.arg)
        if r and r.ok and r.items then for _, it in ipairs(r.items) do notify('success', ('+%d %s'):format(it.amount, it.label)) end end
        cb(r or { ok = false })
    end)
end)

-- Hand dismantle: you stand still for it, so the bag closes.
RegisterNUICallback('dismantle', function(d, cb)
    cb({ ok = true })
    CreateThread(function()
        local r = BSB.Await('crafting:dismantleStart', 8000, d.item)
        if not r or not r.ok then return notify('warn', (r and r.error) or L('failed')) end
        exports.bs_inventory:Close()
        local done = exports.bs_interactions:RunSearch(L('dismantling'), r.ms, { pose = 'kneel' })
        if not done then BSB.Await('crafting:dismantleFinish', 5000); return notify('warn', L('interrupted')) end
        local f = BSB.Await('crafting:dismantleFinish', 8000)
        if not f or not f.ok then return notify('warn', (f and f.error) or L('failed')) end
        if #(f.items or {}) == 0 then return notify('info', L('nothing_useful')) end
        for _, it in ipairs(f.items) do notify('success', ('+%d %s'):format(it.amount, it.label)); Wait(120) end
    end)
end)

--------------------------------------------------------------------------------
-- Hand queue feedback: bar and a light animation while you walk
--------------------------------------------------------------------------------

local handShown = nil
CreateThread(function()
    while true do
        Wait(1500)
        local r = BSB.Await('crafting:hand', 5000)
        local head = r and r.ok and r.jobs and r.jobs[1]
        if head and head.running then
            if handShown ~= head.id then
                handShown = head.id
                exports.bs_interactions:Progress(L('crafting_item', { item = head.label }), math.max(500, head.left * 1000))
            end
            if not exports.bs_inventory:IsOpen() and not IsEntityPlayingAnim(PlayerPedId(), Crafting.HandAnim.dict, Crafting.HandAnim.clip, 3)
                and not IsPedInAnyVehicle(PlayerPedId(), false) and GetSelectedPedWeapon(PlayerPedId()) == GetHashKey('WEAPON_UNARMED') and loadDict(Crafting.HandAnim.dict) then
                TaskPlayAnim(PlayerPedId(), Crafting.HandAnim.dict, Crafting.HandAnim.clip, 2.0, 2.0, -1, Crafting.HandAnim.flag or 49, 0.0, false, false, false)
            end
        elseif handShown then
            handShown = nil
            -- Progress() has no auto-hide, so close the bar when the queue ends
            exports.bs_interactions:CancelProgress()
            StopAnimTask(PlayerPedId(), Crafting.HandAnim.dict, Crafting.HandAnim.clip, 1.0)
        end
        if not (r and r.ok and r.jobs and #r.jobs > 0) then Wait(2500) end
    end
end)

--------------------------------------------------------------------------------
-- Station zones
--------------------------------------------------------------------------------

RegisterNetEvent('bs:crafting:openStation', function(payload)
    local a = payload and payload.args
    if not a or not a.id then return end
    local def = Crafting.Stations[a.type]
    if not def then return end
    CreateThread(function()
        openTab('station', a.id)
        if def.anim then CraftPlayAnim(def.anim, def.prop, 1) end
    end)
end)

RegisterNetEvent('bs:crafting:openStorage', function(payload)
    local a = payload and payload.args
    if not a or not a.id then return end
    CreateThread(function()
        local r = BSB.Await('crafting:openStorage', 8000, a.id)
        if not r or not r.ok then notify('warn', (r and r.error) or L('failed')) end
    end)
end)

local function refreshZones()
    local r = BSB.Await('crafting:nearStations', 6000)
    if not r or not r.ok then return end
    local seen = {}
    for _, s in ipairs(r.list or {}) do
        local id = tostring(s.id)
        seen[id] = true
        if not zones[id] and s.mine then
            local opts = { { label = L('use_station', { station = s.label }), icon = 'wrench', event = 'bs:crafting:openStation', args = { id = s.id, type = s.type } } }
            if not Crafting.Stations[s.type].farm then
                opts[#opts + 1] = { label = L('open_storage'), icon = 'bag', event = 'bs:crafting:openStorage', args = { id = s.id } }
            end
            exports.bs_interactions:AddZone('craftst:' .. id, vector3(s.x + 0.0, s.y + 0.0, s.z + 0.6), 2.2, opts)
            zones[id] = true
        end
    end
    for id in pairs(zones) do
        if not seen[id] then exports.bs_interactions:RemoveZone('craftst:' .. id); zones[id] = nil end
    end
end

CreateThread(function()
    Wait(4000)
    while true do
        if exports.bs_core:IsLoaded() then pcall(refreshZones) end
        Wait(5000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CraftStopAnim()
    for id in pairs(zones) do exports.bs_interactions:RemoveZone('craftst:' .. id) end
end)

RegisterNetEvent('bs:crafting:stewBonus', function(b)
    local ped = PlayerPedId()
    if b.health then SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + b.health)) end
    if b.stamina then RestorePlayerStamina(PlayerId(), b.stamina / 100.0) end
    notify('success', L('stew_bonus'))
end)
