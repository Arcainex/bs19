-- bs_jobs world: job stations, the animal spawner, fishing, the water purifier, siphoning, the chop shop and the gunsmith bench.

local S = Jobs.Settings
local q, x = J.q, J.x
local INV = exports.bs_inventory

--------------------------------------------------------------------------------
-- Stations: vanilla ones from config (F1 editable), player factions place one at their safezone flag.
--------------------------------------------------------------------------------

local Placed = {}   -- [fid] = { id, x, y, z, h }

function J.Stations(fid)
    local out = {}
    for id, s in pairs(Jobs.Stations) do
        if s.faction == fid then out[#out + 1] = { id = id, kind = s.kind, x = s.x + 0.0, y = s.y + 0.0, z = s.z + 0.0, h = (s.h or 0) + 0.0 } end
    end
    local p = Placed[fid]
    if p then out[#out + 1] = { id = 'placed_' .. p.id, kind = 'yard', x = p.x, y = p.y, z = p.z, h = p.h } end
    return out
end

function J.NearStation(src, fid, radius, kind)
    local at = J.PedPos(src)
    if not at then return nil end
    for _, s in ipairs(J.Stations(fid)) do
        if (not kind or s.kind == kind) and #(vector3(s.x, s.y, s.z) - at) <= (radius or 3.0) then return s end
    end
end

local function pushStations(target)
    for _, v in ipairs(target and { target } or GetPlayers()) do
        local src = tonumber(v)
        TriggerClientEvent('bs:jobs:stations', src, J.Stations(J.Faction(src)))
    end
end
J.PushStations = pushStations
AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function() pushStations() end)
BSB.RegisterCallback('jobs:stations', function(src) return { ok = true, list = J.Stations(J.Faction(src)) } end)

BSB.RegisterCallback('jobs:placeStation', function(src)
    local fid = J.Faction(src)
    if not fid or not J.CanManage(src) then return { ok = false, error = Lp(src, 'err.no_perm') } end
    if J.IsVanilla(fid) then return { ok = false, error = Lp(src, 'err.vanilla_fixed') } end
    local at = J.PedPos(src)
    local ok, flags = pcall(function() return exports.bs_faction_bases:ListFlags(fid) end)
    local inside = false
    for _, f in ipairs(ok and flags or {}) do
        if f.kind == 'safezone' and f.status ~= 'removed' and #(vector2(at.x, at.y) - vector2(f.x, f.y)) <= (tonumber(f.radius) or 50.0) then inside = true end
    end
    if not inside then return { ok = false, error = Lp(src, 'err.need_flag') } end
    local h = GetEntityHeading(GetPlayerPed(src))
    x('INSERT INTO bs_job_stations (faction_id, x, y, z, heading, placed_by, created_at) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), heading = VALUES(heading), placed_by = VALUES(placed_by)',
        { fid, at.x, at.y, at.z - 1.0, h, J.CharId(src), J.Now() })
    local r = q('SELECT id FROM bs_job_stations WHERE faction_id = ? LIMIT 1', { fid })[1]
    Placed[fid] = { id = r and tonumber(r.id) or 0, x = at.x, y = at.y, z = at.z - 1.0, h = h }
    for _, v in ipairs(GetPlayers()) do if J.Faction(tonumber(v)) == fid then pushStations(tonumber(v)) end end
    J.Log(src, 'station', fid)
    return { ok = true }
end)

--------------------------------------------------------------------------------
-- Timed actions: start hands out a token, finish checks the time passed and the player stayed put.
--------------------------------------------------------------------------------

local tokens = {}
function J.Begin(src, kind, ms, data)
    tokens[src] = { kind = kind, ms = ms, at = GetGameTimer(), pos = J.PedPos(src), data = data }
    return { ok = true, ms = ms }
end
function J.Finish(src, kind)
    local t = tokens[src]
    tokens[src] = nil
    if not t or t.kind ~= kind then return nil end
    if GetGameTimer() - t.at < t.ms - 700 then J.Flag(src, kind .. '_fast', 'finished early'); return nil end
    local at = J.PedPos(src)
    if not at or not t.pos or #(at - t.pos) > 4.0 then return nil end
    return t.data or true
end
AddEventHandler('playerDropped', function() tokens[source] = nil end)

--------------------------------------------------------------------------------
-- Fishing (anyone with a rod; Fishers and Hunter & Fishers get contracts for it)
--------------------------------------------------------------------------------

local function fishSpot(at)
    for _, s in ipairs(Jobs.Fishing.spots) do
        if #(vector2(at.x, at.y) - vector2(s.x, s.y)) <= (s.r or 25.0) then return s end
    end
end

BSB.RegisterCallback('jobs:fish:start', function(src)
    local at = J.PedPos(src)
    if not at or not fishSpot(at) then return { ok = false, error = Lp(src, 'err.no_fish_here') } end
    if INV:CountItem(src, 'fishing_rod') < 1 then return { ok = false, error = Lp(src, 'err.need_item', { item = INV:ItemLabel('fishing_rod', src) }) } end
    return J.Begin(src, 'fish', Jobs.Fishing.ms or 14000)
end)

BSB.RegisterCallback('jobs:fish:finish', function(src)
    if not J.Finish(src, 'fish') then return { ok = false, error = Lp(src, 'err.interrupted') } end
    local bait = INV:CountItem(src, 'fish_bait') > 0 and INV:RemoveItem(src, 'fish_bait', 1)
    local roll, got = math.random(), nil
    local acc = 0.0
    for i = #Jobs.Fishing.catch, 1, -1 do
        local c = Jobs.Fishing.catch[i]
        acc = acc + ((bait and c.baitChance) or c.chance or 0)
        if roll <= acc then got = c.item; break end
    end
    if not got then return { ok = true, item = nil } end
    if not INV:GiveItem(src, got, 1) then return { ok = false, error = Lp(src, 'err.bag_full') } end
    pcall(function() exports.bs_skills:AddSkillXP(src, 'survival', 3) end)
    J.Progress(src, 'fish_catch', 1)
    return { ok = true, item = got, label = INV:ItemLabel(got, src) }
end)

--------------------------------------------------------------------------------
-- Water purifier (Water Engineer, at their faction's water station)
--------------------------------------------------------------------------------

BSB.RegisterCallback('jobs:water:start', function(src)
    local W = Jobs.Water
    if not J.Does(src, 'water') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    if not J.NearStation(src, J.Faction(src), (S.stationRadius or 3.0) + 1.0, 'water') then return { ok = false, error = Lp(src, 'err.not_at_station') } end
    if INV:CountItem(src, W.input) < W.inputAmount then return { ok = false, error = Lp(src, 'err.missing_items', { item = INV:ItemLabel(W.input, src), n = W.inputAmount }) } end
    return J.Begin(src, 'water', W.ms)
end)

BSB.RegisterCallback('jobs:water:finish', function(src)
    local W = Jobs.Water
    if not J.Finish(src, 'water') then return { ok = false, error = Lp(src, 'err.interrupted') } end
    if not INV:RemoveItem(src, W.input, W.inputAmount) then return { ok = false } end
    if not INV:GiveItem(src, W.output, W.outputAmount) then INV:GiveItem(src, W.input, W.inputAmount); return { ok = false, error = Lp(src, 'err.bag_full') } end
    J.Progress(src, 'water_purified', 1)
    return { ok = true }
end)

--------------------------------------------------------------------------------
-- Siphon (Fuel Runner): parked cars nobody owns, never in a safezone
--------------------------------------------------------------------------------

local function vehicleNear(src, netId, dist)
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return nil end
    local at = J.PedPos(src)
    if not at or #(GetEntityCoords(ent) - at) > (dist or 5.0) then return nil end
    return ent, (GetVehicleNumberPlateText(ent) or ''):gsub('^%s+', ''):gsub('%s+$', '')
end
J.VehicleNear = vehicleNear

-- Hose plus a jerry can with room. Checked before the animation and again at the end.
local function siphonItems(src)
    local SP = Jobs.Siphon
    local missing = {}
    if INV:CountItem(src, SP.tool) < 1 then missing[#missing + 1] = INV:ItemLabel(SP.tool, src) end
    local info = INV:MeasuredInfo(src, { SP.can })
    if not info or (info.containers or 0) < 1 then missing[#missing + 1] = INV:ItemLabel(SP.can, src) end
    if #missing > 0 then return Lp(src, 'err.need_item', { item = table.concat(missing, ', ') }) end
    if (info.room or 0) < 1 then return Lp(src, 'err.can_full') end
    return nil
end

BSB.RegisterCallback('jobs:siphon:start', function(src, netId)
    local SP = Jobs.Siphon
    if not J.Does(src, 'siphon') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    local err = siphonItems(src)
    if err then return { ok = false, error = err } end
    local ent, plate = vehicleNear(src, netId, 5.0)
    if not ent then return { ok = false, error = Lp(src, 'err.not_there') } end
    local at = J.PedPos(src)
    if J.InSafeZone(at.x, at.y) then return { ok = false, error = Lp(src, 'err.safezone') } end
    local info = exports.bs_vehicles:JobInfo(plate)
    if not info then return { ok = false, error = Lp(src, 'err.not_there') } end
    if info.owner then return { ok = false, error = Lp(src, 'err.owned_car') } end
    if (info.fuel or 0) < SP.take then return { ok = false, error = Lp(src, 'err.tank_dry') } end
    return J.Begin(src, 'siphon', SP.ms, { plate = plate })
end)

BSB.RegisterCallback('jobs:siphon:finish', function(src)
    local SP = Jobs.Siphon
    local d = J.Finish(src, 'siphon')
    if not d then return { ok = false, error = Lp(src, 'err.interrupted') } end
    local err = siphonItems(src)
    if err then return { ok = false, error = err } end
    -- only take what the can has room for, then pour it in
    local room = INV:MeasuredInfo(src, { SP.can }).room or 0
    local took = exports.bs_vehicles:JobTakeFuel(d.plate, math.min(SP.take, room))
    if (took or 0) < math.min(SP.take, room) * 0.5 then return { ok = false, error = Lp(src, 'err.tank_dry') } end
    INV:PourInto(src, { SP.can }, took)
    J.Progress(src, 'fuel_siphoned', 1)
    return { ok = true }
end)

--------------------------------------------------------------------------------
-- Chop shop (Car Thief)
--------------------------------------------------------------------------------

local Picked = {}   -- [plate] = { cid, owner, at }
AddEventHandler('bs:jobs:carPicked', function(src, plate, owner)
    src = tonumber(src)
    if src and plate and owner then Picked[tostring(plate)] = { cid = J.CharId(src), owner = tonumber(owner), at = J.Now() } end
end)

BSB.RegisterCallback('jobs:chop', function(src, netId)
    local CH = Jobs.Chop
    if not J.Does(src, 'chop') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    local fid = J.Faction(src)
    if not J.NearStation(src, fid, 12.0, 'chop') then return { ok = false, error = Lp(src, 'err.not_at_station') } end
    local ent, plate = vehicleNear(src, netId, 6.0)
    if not ent then return { ok = false, error = Lp(src, 'err.not_there') } end
    local p = Picked[plate]
    local cid = J.CharId(src)
    if not p or p.cid ~= cid or J.Now() - p.at > (CH.windowMin or 120) * 60 then return { ok = false, error = Lp(src, 'err.not_stolen') } end
    if not J.VictimFree(p.owner, 'chop') then return { ok = false, error = Lp(src, 'err.victim_cooldown') } end
    local ownerFaction = q('SELECT faction_id FROM bs_faction_members WHERE character_id = ? LIMIT 1', { p.owner })[1]
    if ownerFaction and ownerFaction.faction_id == fid then return { ok = false, error = Lp(src, 'err.own_faction') } end
    local took = exports.bs_vehicles:JobChop(plate, CH.parts)
    for _, id in ipairs(took or {}) do
        local item = CH.items[id]
        if item then INV:GiveItem(src, item, 1) end
    end
    for _, b in ipairs(CH.bonus or {}) do INV:GiveItem(src, b.item, b.amount) end
    Picked[plate] = nil
    J.MarkVictim(p.owner, 'chop')
    J.Progress(src, 'car_chopped', 1)
    J.Log(src, 'chop', ('%s owner %d parts %d'):format(plate, p.owner, #(took or {})))
    return { ok = true, parts = #(took or {}) }
end)

--------------------------------------------------------------------------------
-- Gunsmith bench (military Gunsmith)
--------------------------------------------------------------------------------

local function recipe(id) for _, r in ipairs(Jobs.Gunsmith) do if r.id == id then return r end end end

BSB.RegisterCallback('jobs:gs:list', function(src)
    if not J.Does(src, 'gunsmith') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    local out = {}
    for _, r in ipairs(Jobs.Gunsmith) do
        local cost, can = {}, true
        for _, c in ipairs(r.cost) do
            local have = INV:CountItem(src, c.item)
            cost[#cost + 1] = { item = c.item, label = INV:ItemLabel(c.item, src), amount = c.amount, have = have }
            if have < c.amount then can = false end
        end
        out[#out + 1] = { id = r.id, item = r.item, label = INV:ItemLabel(r.item, src), amount = r.amount, seconds = math.floor(r.ms / 1000), cost = cost, can = can }
    end
    return { ok = true, list = out }
end)

BSB.RegisterCallback('jobs:gs:start', function(src, id)
    local r = recipe(tostring(id or ''))
    if not r or not J.Does(src, 'gunsmith') then return { ok = false, error = Lp(src, 'err.wrong_job') } end
    if not J.NearStation(src, J.Faction(src), (S.stationRadius or 3.0) + 1.0, 'gunsmith') then return { ok = false, error = Lp(src, 'err.not_at_station') } end
    for _, c in ipairs(r.cost) do
        if INV:CountItem(src, c.item) < c.amount then return { ok = false, error = Lp(src, 'err.missing_items', { item = INV:ItemLabel(c.item, src), n = c.amount }) } end
    end
    return J.Begin(src, 'gunsmith', r.ms, { id = r.id })
end)

BSB.RegisterCallback('jobs:gs:finish', function(src)
    local d = J.Finish(src, 'gunsmith')
    local r = d and recipe(d.id)
    if not r then return { ok = false, error = Lp(src, 'err.interrupted') } end
    for _, c in ipairs(r.cost) do
        if INV:CountItem(src, c.item) < c.amount then return { ok = false, error = Lp(src, 'err.missing_items', { item = INV:ItemLabel(c.item, src), n = c.amount }) } end
    end
    for _, c in ipairs(r.cost) do INV:RemoveItem(src, c.item, c.amount) end
    if not INV:GiveItem(src, r.item, r.amount) then
        for _, c in ipairs(r.cost) do INV:GiveItem(src, c.item, c.amount) end
        return { ok = false, error = Lp(src, 'err.bag_full') }
    end
    pcall(function() exports.bs_skills:AddSkillXP(src, 'crafting', math.floor(r.ms / 1000)) end)
    J.Progress(src, r.event, 1)
    J.Log(src, 'gunsmith', r.item)
    return { ok = true, label = INV:ItemLabel(r.item, src), amount = r.amount }
end)

--------------------------------------------------------------------------------
-- Animal spawner: keeps a few animals around players in hunting areas, never inside safezones.
--------------------------------------------------------------------------------

local Animals = {}   -- [entity] = { born, model, deadAt }

local function inHuntArea(at)
    for _, a in ipairs(Jobs.Hunting.areas) do
        if #(vector2(at.x, at.y) - vector2(a.x, a.y)) <= a.r then return true end
    end
    return false
end
local function inTown(x, y)
    if S.huntAvoidTowns == false then return false end
    for _, t in ipairs(Jobs.Hunting.towns or {}) do
        if #(vector2(x, y) - vector2(t.x, t.y)) <= t.r then return true end
    end
    return false
end
local function pickModel()
    local H, total = Jobs.Hunting, 0
    for i = 1, #H.models do total = total + (H.weights[i] or 1) end
    local r = math.random() * total
    for i = 1, #H.models do r = r - (H.weights[i] or 1); if r <= 0 then return H.models[i] end end
    return H.models[1]
end

local function spawnNear(src, at)
    local ang = math.random() * math.pi * 2
    local lo = math.floor(tonumber(S.huntSpawnMin) or 70)
    local hi = math.max(lo, math.floor(tonumber(S.huntSpawnMax) or 130))
    local dist = math.random(lo, hi) + 0.0
    local px, py = at.x + math.cos(ang) * dist, at.y + math.sin(ang) * dist
    if J.InSafeZone(px, py) or inTown(px, py) or not inHuntArea(vector3(px, py, 0.0)) then return end
    local r = BSB.AwaitClient(src, 'jobs:groundZ', 4000, px, py)
    local z = type(r) == 'table' and tonumber(r.z) or nil
    if not z then return end
    local model = pickModel()
    local ped = CreatePed(28, joaat(model), px, py, z + 0.3, math.random(0, 359) + 0.0, true, true)
    local t = GetGameTimer()
    while not DoesEntityExist(ped) and GetGameTimer() - t < 3000 do Wait(50) end
    if not DoesEntityExist(ped) then return end
    Entity(ped).state:set('bsAnimal', true, true)
    Entity(ped).state:set('bsProtected', true, true)
    local pred = (Jobs.Hunting.predators or {})[model] == true
    Entity(ped).state:set('bsAnimalKind', pred and 'predator' or 'prey', true)
    Animals[ped] = { born = J.Now(), model = model, pred = pred }
end

CreateThread(function()
    while true do
        Wait(15000)
        local now = J.Now()
        local life = (tonumber(S.huntLifeMinutes) or 20) * 60
        local players = {}
        for _, v in ipairs(GetPlayers()) do
            local src = tonumber(v)
            local at = J.PedPos(src)
            if at then players[#players + 1] = { src = src, at = at } end
        end
        -- cleanup
        local count = 0
        for ent, a in pairs(Animals) do
            local keep = DoesEntityExist(ent)
            if keep then
                local pos = GetEntityCoords(ent)
                local near = false
                for _, p in ipairs(players) do if #(p.at - pos) < 400.0 then near = true; break end end
                if GetEntityHealth(ent) <= 0 then a.deadAt = a.deadAt or now end
                if not near or (now - a.born) > life or (a.deadAt and now - a.deadAt > 600) then keep = false; DeleteEntity(ent) end
            end
            if keep then count = count + 1 else Animals[ent] = nil end
        end
        -- spawn
        -- Wildlife runs on its own toggle, not on the faction jobs switch.
        if S.huntingEnabled then
            for _, p in ipairs(players) do
                if count >= (tonumber(S.huntMax) or 24) then break end
                if inHuntArea(p.at) and not J.InSafeZone(p.at.x, p.at.y) and not inTown(p.at.x, p.at.y) then
                    local around = 0
                    for ent in pairs(Animals) do if #(GetEntityCoords(ent) - p.at) < 250.0 then around = around + 1 end end
                    if around < (tonumber(S.huntPerPlayer) or 3) then
                        pcall(spawnNear, p.src, p.at)
                        count = count + 1
                    end
                end
            end
        end
    end
end)

-- A predator that follows someone into a safezone is removed.
CreateThread(function()
    while true do
        Wait(3000)
        for ent, a in pairs(Animals) do
            if a.pred and DoesEntityExist(ent) and GetEntityHealth(ent) > 0 then
                local c = GetEntityCoords(ent)
                if J.InSafeZone(c.x, c.y) then DeleteEntity(ent); Animals[ent] = nil end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ent in pairs(Animals) do if DoesEntityExist(ent) then DeleteEntity(ent) end end
end)

CreateThread(function()
    while not J.Ready do Wait(500) end
    for _, r in ipairs(q('SELECT * FROM bs_job_stations')) do
        Placed[r.faction_id] = { id = tonumber(r.id), x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), h = tonumber(r.heading) or 0.0 }
    end
    pushStations()
end)
