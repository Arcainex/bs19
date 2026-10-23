-- Server authority for gadgets: loadout, item use, cooldowns, limits, turret hits,
-- beacon heals, decoy noise, PvP damage to gadgets and cleanup. Nothing here ever targets a player.

local lastUse = {}    -- src -> ms of last accepted use
local pending = {}    -- src -> { item, token, at } between "use" and "deploy"
local active = {}     -- src -> { [kind] = rec }
local pingAt = {}     -- src -> ms

-- Gadget name in a player's language, config label as fallback.
local function gname(src, t, kind)
    kind = (t and t.kind) or kind
    local key = 'gadget.' .. tostring(kind)
    local text = Lp(src, key)
    return text ~= key and text or ((t and t.label) or tostring(kind))
end

local function notify(src, msg, kind)
    TriggerClientEvent('bs:ui:notify', src, { type = kind or 'info', message = msg, duration = 3000 })
end

local function inv() return GetResourceState('bs_inventory') == 'started' end

local function countOf(src, item)
    if not inv() then return 0 end
    local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
    return (ok and tonumber(n)) or 0
end

-- Same faction skills as boosters: % off cooldown, max 60.
local function cdCut(src)
    if GetResourceState('bs_factions') ~= 'started' then return 0 end
    local ok, n = pcall(function()
        local s = exports.bs_factions:GetFactionSummary(tonumber(src))
        if type(s) ~= 'table' or not s.factionId then return 0 end
        return (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'booster_cd')) or 0)
             + (tonumber(exports.bs_factions:GetSkillValue(s.factionId, 'booster_cd2')) or 0)
    end)
    return ok and math.max(0, math.min(60, tonumber(n) or 0)) or 0
end

-- The loadout lives in bs_inventory now (items sit in off-grid slots).
-- Old metadata loadouts are moved over once: carried items leave the grid.
local function migrate(src)
    local raw = exports.bs_core:GetPlayerMeta(src, Gadgets.MetaKey, nil)
    if type(raw) ~= 'table' or next(raw) == nil then return false end
    local busy = false
    for i = 1, Gadgets.Slots do
        local v = raw[i] or raw[tostring(i)]
        if type(v) == 'string' and Gadgets.IsGadget(v) then
            local ok, done, err = pcall(function() return exports.bs_inventory:LoadoutSet(src, 'gadget', i, v, true) end)
            if ok and not done and err == 'no character' then busy = true end
        end
    end
    -- Keep the old list if the inventory was locked (mid-trade); try again later.
    if busy then return false end
    exports.bs_core:SetPlayerMeta(src, Gadgets.MetaKey, nil)
    return true
end

-- index -> { item, amount } or false
local function slots(src)
    local out = {}
    if not inv() then return out end
    local get = function() return exports.bs_inventory:LoadoutGet(src, 'gadget') end
    local ok, lo = pcall(get)
    -- Only migrate once the character's inventory is actually loaded.
    if ok and type(lo) == 'table' and lo[1] ~= nil and migrate(src) then ok, lo = pcall(get) end
    for i = 1, Gadgets.Slots do
        local e = ok and type(lo) == 'table' and lo[i] or nil
        out[i] = (type(e) == 'table' and Gadgets.IsGadget(e.item)) and e or false
    end
    return out
end

local function loadout(src)
    local out = {}
    for i, e in ipairs(slots(src)) do out[i] = e and e.item or false end
    return out
end

local function getCds(src)
    local raw = exports.bs_core:GetPlayerMeta(src, Gadgets.CdKey, nil)
    local out, now = {}, os.time()
    if type(raw) == 'table' then
        for item, t in pairs(raw) do
            t = tonumber(t)
            if t and t > now and Gadgets.IsGadget(item) then out[item] = t end
        end
    end
    return out
end

local function setCd(src, item, readyAt)
    local cds = getCds(src)
    cds[item] = readyAt
    exports.bs_core:SetPlayerMeta(src, Gadgets.CdKey, cds)
end

local function payload(src)
    local lo, now, cds, out = slots(src), os.time(), getCds(src), {}
    for i = 1, Gadgets.Slots do
        local e = lo[i]
        local item = e and e.item
        if item then
            local t = Gadgets.Types[item]
            out[tostring(i)] = {
                item = item, label = t.label, kind = t.kind,
                count = e.amount or 0,
                cooldown = math.max(0, (cds[item] or 0) - now),
                battery = t.kind == 'drone' and Gadgets.BatteryPct(e.metadata) or nil,
            }
        else
            out[tostring(i)] = false
        end
    end
    return out
end

local function push(src)
    if not src or src <= 0 then return end
    TriggerClientEvent('bs:gadgets:loadout', src, payload(src))
end
exports('Push', push)
exports('Loadout', loadout)

-- Active list for the HUD: { kind = { label, left, ammo } }
local function pushActive(src)
    local list = {}
    for kind, rec in pairs(active[src] or {}) do
        list[#list + 1] = {
            kind = kind, label = rec.label,
            left = math.max(0, math.floor((rec.untilAt - GetGameTimer()) / 1000)),
            ammo = rec.ammo,
        }
    end
    TriggerClientEvent('bs:gadgets:active', src, list)
end

local function squadOf(src)
    local out = { src }
    if GetResourceState('bs_factions') ~= 'started' then return out end
    local ok, members = pcall(function() return exports.bs_factions:GetSquadMembers(src) end)
    if ok and type(members) == 'table' then
        for _, m in ipairs(members) do
            local msrc = tonumber(m.src)
            if msrc and msrc ~= src and GetPlayerPed(msrc) ~= 0 then out[#out + 1] = msrc end
        end
    end
    return out
end

local function entityOf(netId)
    netId = tonumber(netId)
    if not netId or netId == 0 then return 0 end
    local e = NetworkGetEntityFromNetworkId(netId)
    return (e and e ~= 0 and DoesEntityExist(e)) and e or 0
end

local function wipeEntities(rec)
    for _, netId in ipairs(rec.netIds or {}) do
        local e = entityOf(netId)
        if e ~= 0 then DeleteEntity(e) end
    end
    rec.netIds = {}
end

local function endGadget(src, kind, reason)
    local rec = active[src] and active[src][kind]
    if not rec then return end
    active[src][kind] = nil
    rec.dead = true
    wipeEntities(rec)
    if GetPlayerName(src) then
        TriggerClientEvent('bs:gadgets:stop', src, kind, reason)
        pushActive(src)
    end
end

local function endAll(src, reason)
    for kind in pairs(active[src] or {}) do endGadget(src, kind, reason) end
    active[src] = nil
end

----------------------------------------------------------------- loadout

RegisterNetEvent('bs:gadgets:request', function()
    local src = source
    push(src); pushActive(src)
end)

RegisterNetEvent('bs:gadgets:setSlot', function(index, item)
    local src = source
    index = math.tointeger(tonumber(index))
    if not index or index < 1 or index > Gadgets.Slots or not inv() then return end
    local ok, err
    if item == nil or item == false or item == '' then
        ok, err = exports.bs_inventory:LoadoutClear(src, 'gadget', index)
    elseif type(item) ~= 'string' or not Gadgets.IsGadget(item) then
        ok, err = false, Lp(src, 'gad.only_gadgets')
    else
        ok, err = exports.bs_inventory:LoadoutSet(src, 'gadget', index, item)
    end
    if not ok then notify(src, err or Lp(src, 'gad.could_not'), 'error') end
    push(src)
end)

---------------------------------------------------------------- use flow
-- 1. use: checks only, nothing spent. 2. client aims/places. 3. deploy: item spent.

local function alive(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then return false end
    if Player(src).state.bsDowned then return false end
    return true, ped
end

RegisterNetEvent('bs:gadgets:use', function(index)
    local src = source
    index = math.tointeger(tonumber(index))
    if not index or index < 1 or index > Gadgets.Slots then return end
    local now = GetGameTimer()
    if lastUse[src] and now - lastUse[src] < Gadgets.UseDelayMs then return end
    lastUse[src] = now

    local item = loadout(src)[index]
    if not item then notify(src, Lp(src, 'gad.slot_empty')); return end
    local t = Gadgets.Types[item]
    if t.enabled == false then notify(src, Lp(src, 'gad.not_yet'), 'error'); return end  -- shield parked
    if not alive(src) then return end

    if active[src] and active[src][t.kind] then
        -- pressing the key again on a running drone/turret: nothing, the client handles recall
        notify(src, Lp(src, 'gad.already_out', { name = gname(src, t) }), 'error'); return
    end
    local ready = getCds(src)[item] or 0
    if os.time() < ready then
        notify(src, Lp(src, 'gad.recharging', { name = t.label, n = ready - os.time() }), 'error'); return
    end
    local have = slots(src)[index]
    if not have or (have.amount or 0) < 1 then notify(src, Lp(src, 'gad.none_left', { name = gname(src, t) }), 'error'); push(src); return end
    if t.kind == 'drone' and Gadgets.BatteryPct(have.metadata) <= 0 then
        notify(src, Lp(src, 'gad.batt_empty'), 'error'); return
    end

    local token = math.random(100000, 999999)
    pending[src] = { item = item, index = index, token = token, at = now }
    TriggerClientEvent('bs:gadgets:begin', src, item, t, token)
end)

RegisterNetEvent('bs:gadgets:cancel', function() pending[source] = nil end)

RegisterNetEvent('bs:gadgets:deploy', function(token, pos, heading)
    local src = source
    local p = pending[src]
    pending[src] = nil
    if not p or p.token ~= tonumber(token) or GetGameTimer() - p.at > 60000 then return end
    local t = Gadgets.Types[p.item]
    local ok, ped = alive(src)
    if not ok then return end
    if active[src] and active[src][t.kind] then return end

    local me = GetEntityCoords(ped)
    local at = me
    if type(pos) == 'table' or type(pos) == 'vector3' then
        at = vector3(tonumber(pos.x) or me.x, tonumber(pos.y) or me.y, tonumber(pos.z) or me.z)
    end
    local reach = (t.placeRange or 3.0) + 2.0
    if #(at - me) > reach then notify(src, Lp(src, 'gad.too_far'), 'error'); return end

    local removed, meta = false, nil
    if inv() then
        local okCall, res, m = pcall(function() return exports.bs_inventory:LoadoutTake(src, 'gadget', p.index, 1, p.item) end)
        removed = okCall and res and true or false
        meta = okCall and type(m) == 'table' and m or {}
    end
    if not removed then notify(src, Lp(src, 'gad.none_left', { name = gname(src, t) }), 'error'); push(src); return end
    if (t.cooldown or 0) > 0 then
        setCd(src, p.item, os.time() + math.max(1, math.floor(t.cooldown * (1 - cdCut(src) / 100))))
    end

    -- drone: flight time comes from the battery it was packed with
    local batPct, batSecs, flightLeft
    if t.kind == 'drone' then
        batPct, batSecs = Gadgets.BatteryPct(meta), Gadgets.BatterySecs(meta)
        flightLeft = batPct / 100 * batSecs / (Gadgets.DrainMul or 1.0)
    end
    -- hovering stretches the battery, so the server timer allows for it
    local stretch = t.kind == 'drone' and 1 / math.max(0.1, tonumber(t.idleDrain) or 1.0) or 1
    local life = t.duration or ((flightLeft or t.battery or 60) * stretch + (t.fallMs or 0) / 1000 + 10)
    if t.kind == 'shield' then life = 10 * 365 * 86400 end  -- until stowed, broken or downed
    active[src] = active[src] or {}
    local rec = {
        item = p.item, kind = t.kind, label = t.label, cfg = t,
        pos = at, heading = tonumber(heading) or 0.0,
        untilAt = GetGameTimer() + life * 1000,
        ammo = t.ammo, lastShot = 0, netIds = {},
        index = p.index, meta = meta, battery = batPct, batSecs = batSecs, startAt = GetGameTimer(),
    }
    active[src][t.kind] = rec

    if t.kind == 'medic' then
        for _, id in ipairs(squadOf(src)) do
            if id ~= src then TriggerClientEvent('bs:gadgets:beaconFx', id, at, t.radius, t.duration) end
        end
        CreateThread(function()
            while not rec.dead and GetGameTimer() < rec.untilAt do
                Wait(t.tickMs)
                if rec.dead then break end
                for _, id in ipairs(squadOf(src)) do
                    local mped = GetPlayerPed(id)
                    if mped ~= 0 and GetEntityHealth(mped) > 0 and #(GetEntityCoords(mped) - rec.pos) <= t.radius then
                        TriggerClientEvent('bs:gadgets:heal', id, t.healPerTick)
                    end
                end
            end
        end)
    elseif t.kind == 'decoy' then
        CreateThread(function()
            while not rec.dead and GetGameTimer() < rec.untilAt do
                if GetResourceState('bs_zombies') == 'started' then
                    pcall(function() exports.bs_zombies:EventNoise(rec.pos.x, rec.pos.y, rec.pos.z, t.loud, 'decoy') end)
                end
                Wait(t.pulseMs)
            end
        end)
    end

    local extra = nil
    if t.kind == 'shield' then
        -- carry over durability from a stowed shield
        local hp = tonumber(exports.bs_core:GetPlayerMeta(src, Gadgets.ShieldKey, nil))
        exports.bs_core:SetPlayerMeta(src, Gadgets.ShieldKey, nil)
        extra = (hp and hp > 0) and math.min(hp, t.durability) or t.durability
        rec.hp = extra
    elseif t.kind == 'drone' then
        extra = { battery = batPct, secs = batSecs, left = flightLeft }
    end

    TriggerClientEvent('bs:gadgets:deployed', src, p.item, t, at, rec.heading, extra)
    push(src); pushActive(src)
end)

-- Client reports the networked props it made for this gadget.
RegisterNetEvent('bs:gadgets:attach', function(kind, netIds)
    local src = source
    local rec = active[src] and active[src][kind]
    if not rec or type(netIds) ~= 'table' then return end
    for i = 1, math.min(#netIds, 4) do
        local n = math.tointeger(tonumber(netIds[i]))
        if n then rec.netIds[#rec.netIds + 1] = n end
    end
end)

-- Shield put away with the same key (or a two-handed weapon): back to the bag, wear kept.
RegisterNetEvent('bs:gadgets:shieldStow', function(hp, why)
    local src = source
    local rec = active[src] and active[src].shield
    if not rec then return end
    hp = math.floor(math.max(0, math.min(tonumber(hp) or 0, rec.hp or rec.cfg.durability)))
    endGadget(src, 'shield', why == 'twohand' and 'twohand' or 'stow')
    if hp <= 0 or not inv() then return end
    local ok, given = pcall(function() return exports.bs_inventory:GiveItem(src, rec.item, 1) end)
    if ok and given ~= false then
        exports.bs_core:SetPlayerMeta(src, Gadgets.ShieldKey, hp)
    else
        notify(src, Lp(src, 'gad.no_room_shield'), 'error')
    end
end)

-- Battery left after a flight. Client says how long it flew; the server
-- never lets that be less than the real time since launch (minus a little lag).
local function droneLeft(rec, flown)
    local real = (GetGameTimer() - rec.startAt) / 1000
    flown = tonumber(flown) or real
    -- client reports battery-weighted seconds; hovering can't go below the idle rate
    local idle = tonumber(rec.cfg and rec.cfg.idleDrain) or 1.0
    flown = math.max(flown, real * idle - 3.0)
    local drain = 100 / (rec.batSecs or 60) * (Gadgets.DrainMul or 1.0)
    return math.max(0, math.floor((rec.battery or 100) - flown * drain + 0.5))
end

local function giveDrone(src, rec, pct)
    local meta = rec.meta or {}
    meta.battery = pct
    meta.capacity = meta.capacity or 'small'
    if not inv() then return end
    -- back into the same gadget slot if it is free, else the bag
    local ok, put = pcall(function() return exports.bs_inventory:LoadoutPut(src, 'gadget', rec.index, rec.item, meta) end)
    if ok and put then return end
    local ok2, given = pcall(function() return exports.bs_inventory:GiveItem(src, rec.item, 1, meta) end)
    if not ok2 or given == false then notify(src, Lp(src, 'gad.no_room_drone'), 'error') end
end

RegisterNetEvent('bs:gadgets:ended', function(kind, reason, flown)
    local src = source
    if type(kind) ~= 'string' then return end
    reason = tostring(reason or 'ended'):sub(1, 24)
    local rec = active[src] and active[src][kind]
    if rec and reason == 'destroyed' then
        local e = entityOf(rec.netIds and rec.netIds[1])
        local pos = e ~= 0 and GetEntityCoords(e) or rec.pos
        for _, id in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(id)
            if ped ~= 0 and #(GetEntityCoords(ped) - pos) < 150.0 then
                TriggerClientEvent('bs:gadgets:breakFx', id, kind, pos)
            end
        end
    end
    endGadget(src, kind, reason)
    if kind ~= 'drone' or not rec then return end
    if reason == 'recalled' then
        local pct = droneLeft(rec, flown)
        giveDrone(src, rec, pct)
        notify(src, Lp(src, 'gad.drone_packed', { pct = pct }))
    elseif reason == 'battery' and rec.cfg.keepOnEmpty then
        giveDrone(src, rec, 0)
    end
    push(src)
end)

------------------------------------------------------------- charging
-- Client asks every Charge.tickMs; server checks the source and adds % by real time.

local chargeAt = {}   -- src -> ms of last accepted tick

local function nearRunningVehicle(ped, range)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetIsVehicleEngineRunning(veh) then return true end
    local me = GetEntityCoords(ped)
    for _, v in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(v) - me) <= range and GetIsVehicleEngineRunning(v) then return true end
    end
    return false
end

RegisterNetEvent('bs:gadgets:charge', function(kind)
    local src = source
    local C = Gadgets.Charge
    local ok, ped = alive(src)
    if not ok or not inv() then return end
    if active[src] and active[src].drone then return end
    local now = GetGameTimer()
    local last = chargeAt[src]
    chargeAt[src] = now
    if not last or now - last > C.tickMs * 3 then return end   -- first tick just starts the clock
    local secs = math.min((now - last) / 1000, C.tickMs / 1000 * 1.5)

    local rate
    if kind == 'vehicle' then
        if not nearRunningVehicle(ped, C.vehicleRange + 1.5) then return end
        rate = C.vehiclePerSec
    elseif kind == 'generator' then
        -- props aren't networked, so this trusts the client's "I'm at one"; rate is still time-capped
        rate = C.generatorPerSec
    else return end

    local okL, list = pcall(function() return exports.bs_inventory:ItemMetaList(src, 'booster_drone') end)
    if not okL or type(list) ~= 'table' then return end
    for _, e in ipairs(list) do
        local pct = Gadgets.BatteryPct(e.metadata)
        if pct < 100 then
            local m = e.metadata
            m.battery = math.min(100, math.floor((pct + rate * secs) * 10 + 0.5) / 10)
            m.capacity = m.capacity or 'small'
            exports.bs_inventory:SetItemMeta(src, e.slot, 'booster_drone', m)
            TriggerClientEvent('bs:gadgets:charged', src, m.battery)
            return
        end
    end
    TriggerClientEvent('bs:gadgets:charged', src, 100, true)
end)

RegisterNetEvent('bs:gadgets:chargeStop', function() chargeAt[source] = nil end)

----------------------------------------------------------------- turret

RegisterNetEvent('bs:gadgets:turretShot', function(walkerId, tx, ty, tz, mx, my, mz)
    local src = source
    local rec = active[src] and active[src].turret
    if not rec or rec.dead then return end
    local t = rec.cfg
    local now = GetGameTimer()
    if now - rec.lastShot < t.fireMs * 0.8 then return end
    if (rec.ammo or 0) <= 0 then return end
    rec.lastShot = now
    rec.ammo = rec.ammo - 1

    if GetResourceState('bs_zombies') == 'started' then
        pcall(function()
            exports.bs_zombies:GadgetHit(src, walkerId, t.damage, rec.pos.x, rec.pos.y, t.range, 'turret')
        end)
    end

    -- Shot fx for anyone near enough to hear it.
    tx, ty, tz = tonumber(tx), tonumber(ty), tonumber(tz)
    -- barrel tip from the client, kept near the turret
    local from = rec.pos + vector3(0.0, 0.0, 0.6)
    mx, my, mz = tonumber(mx), tonumber(my), tonumber(mz)
    if mx and my and mz and #(vector3(mx, my, mz) - rec.pos) < 3.0 then from = vector3(mx, my, mz) end
    if tx and ty and tz then
        for _, id in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(id)
            if ped ~= 0 and #(GetEntityCoords(ped) - rec.pos) < 120.0 then
                TriggerClientEvent('bs:gadgets:shotFx', id, from, vector3(tx, ty, tz))
            end
        end
    end

    if rec.ammo <= 0 then endGadget(src, 'turret', 'ammo') else pushActive(src) end
end)

RegisterNetEvent('bs:gadgets:pickup', function()
    local src = source
    local rec = active[src] and active[src].turret
    if not rec then return end
    local ok, ped = alive(src)
    if not ok or #(GetEntityCoords(ped) - rec.pos) > Gadgets.PickupDist + 1.5 then return end
    local give = (rec.ammo or 0) > 0
    endGadget(src, 'turret', 'pickup')
    if give and inv() then
        pcall(function() exports.bs_inventory:GiveItem(src, rec.item, 1) end)
        notify(src, Lp(src, 'gad.turret_packed'))
    end
end)

------------------------------------------------------------------ drone

RegisterNetEvent('bs:gadgets:ping', function(x, y, z)
    local src = source
    local rec = active[src] and active[src].drone
    if not rec then return end
    local now = GetGameTimer()
    if pingAt[src] and now - pingAt[src] < 2000 then return end
    pingAt[src] = now
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > rec.cfg.maxRange + 150.0 then return end
    local name = GetPlayerName(src) or 'Scout'
    for _, id in ipairs(squadOf(src)) do
        TriggerClientEvent('bs:gadgets:pinged', id, vector3(x, y, z), name, rec.cfg.pingSecs)
    end
end)

------------------------------------------------------------------- pvp
-- Other players can break placed gadgets and flying drones. Their hits are
-- cancelled on the way to the owner and applied here instead, so the owner's
-- client never double counts. Never inside safe zones.

local P = Gadgets.PvP or {}
local HP = { turret = true, decoy = true, medic = true, drone = true }

local MELEE = {}
for _, w in ipairs({ 'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_CROWBAR', 'WEAPON_HAMMER',
    'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_WRENCH', 'WEAPON_GOLFCLUB', 'WEAPON_NIGHTSTICK',
    'WEAPON_KNUCKLE', 'WEAPON_DAGGER', 'WEAPON_BOTTLE', 'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE',
    'WEAPON_POOLCUE', 'WEAPON_STONE_HATCHET', 'WEAPON_FLASHLIGHT' }) do
    MELEE[joaat(w) & 0xFFFFFFFF] = true
end

local zones, zonesAt = {}, 0
local function inSafeZone(pos)
    local now = GetGameTimer()
    if now - zonesAt > 30000 then
        zonesAt = now
        if GetResourceState('bs_zombies') == 'started' then
            local ok, z = pcall(function() return exports.bs_zombies:SafeZones() end)
            if ok and type(z) == 'table' then zones = z end
        end
    end
    for _, z in ipairs(zones) do
        local dx, dy = pos.x - z.x, pos.y - z.y
        local r = (z.radius or 0) + (P.safeZonePad or 0)
        if dx * dx + dy * dy <= r * r then return true end
    end
    return false
end

-- netId -> owner, kind, rec
local function gadgetByNet(netId)
    netId = math.tointeger(tonumber(netId))
    if not netId then return nil end
    for owner, list in pairs(active) do
        for kind, rec in pairs(list) do
            if HP[kind] and not rec.dead then
                for _, n in ipairs(rec.netIds or {}) do
                    if n == netId then return owner, kind, rec end
                end
            end
        end
    end
end

local function gadgetPos(rec)
    local e = entityOf(rec.netIds and rec.netIds[1])
    return e ~= 0 and GetEntityCoords(e) or rec.pos
end

local function breakFx(kind, pos)
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - pos) < 150.0 then
            TriggerClientEvent('bs:gadgets:breakFx', id, kind, pos)
        end
    end
end

local function hurt(owner, kind, rec, attacker, dmg, how)
    local pos = gadgetPos(rec)
    if inSafeZone(pos) then return end
    rec.hpLeft = (rec.hpLeft or rec.cfg.health or 100) - dmg
    if rec.hpLeft > 0 then return end
    local aName = GetPlayerName(attacker) or ('#' .. tostring(attacker))
    local oName = GetPlayerName(owner) or ('#' .. tostring(owner))
    print(('[bs_gadgets] %s (%s) destroyed %s\'s %s (%s) with %s'):format(aName, attacker, oName, kind, owner, how))
    breakFx(kind, pos)
    endGadget(owner, kind, 'destroyed')
    notify(attacker, Lp(attacker, 'gad.you_destroyed', { owner = oName, name = gname(attacker, rec.cfg, kind) }), 'success')
    notify(owner, Lp(owner, 'gad.destroyed_yours', { who = aName, name = gname(owner, rec.cfg, kind) }), 'error')
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    if P.enabled == false or type(data) ~= 'table' then return end
    local ids = data.hitGlobalIds
    if type(ids) ~= 'table' or #ids == 0 then ids = { data.hitGlobalId } end
    local src = tonumber(sender)
    for _, netId in ipairs(ids) do
        local owner, kind, rec = gadgetByNet(netId)
        if owner then
            -- the server decides, the owner never sees the raw hit
            CancelEvent()
            if owner ~= src then
                local ped = GetPlayerPed(src)
                if ped ~= 0 then
                    local dist = #(GetEntityCoords(ped) - gadgetPos(rec))
                    local w = math.floor(tonumber(data.weaponType) or 0) & 0xFFFFFFFF
                    local limit = MELEE[w] and (P.meleeDist or 4.0) or (P.maxDist or 250.0)
                    if dist <= limit then
                        local dmg = math.max(P.minDamage or 5, math.floor(tonumber(data.weaponDamage) or 0))
                        hurt(owner, kind, rec, src, dmg, ('weapon %s'):format(w))
                    end
                end
            end
            return
        end
    end
end)

AddEventHandler('explosionEvent', function(sender, ev)
    if P.enabled == false or type(ev) ~= 'table' then return end
    local src = tonumber(sender)
    local x, y, z = tonumber(ev.posX), tonumber(ev.posY), tonumber(ev.posZ)
    if not src or not x then return end
    local at = vector3(x, y, z or 0.0)
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - at) > (P.maxDist or 250.0) then return end
    local hits = {}
    for owner, list in pairs(active) do
        if owner ~= src then
            for kind, rec in pairs(list) do
                if HP[kind] and not rec.dead and #(gadgetPos(rec) - at) <= (P.explosionRadius or 6.0) then
                    hits[#hits + 1] = { owner, kind, rec }
                end
            end
        end
    end
    for _, h in ipairs(hits) do
        hurt(h[1], h[2], h[3], src, P.explosionDamage or 250, ('explosion %s'):format(tostring(ev.explosionType)))
    end
end)

------------------------------------------------------------- lifecycle

-- Expiry, death and a HUD refresh, once a second.
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for src, list in pairs(active) do
            if not GetPlayerName(src) then
                endAll(src, 'left')
            else
                local down = not alive(src)
                for kind, rec in pairs(list) do
                    if now >= rec.untilAt then endGadget(src, kind, 'time')
                    elseif down then endGadget(src, kind, 'down') end
                end
                if active[src] then pushActive(src) end
            end
        end
        for src, p in pairs(pending) do
            if now - p.at > 60000 then pending[src] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    endAll(src, 'left')
    lastUse[src], pending[src], pingAt[src], chargeAt[src] = nil, nil, nil, nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(active) do
        for _, rec in pairs(active[src]) do wipeEntities(rec) end
    end
end)
