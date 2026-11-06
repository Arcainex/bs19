local INV = exports.bs_inventory
local casts, searches, bushes, lastStart = {}, {}, {}, {}
local function fail(message) return { ok = false, error = message } end
local function level(src)
    if GetResourceState('bs_skills') ~= 'started' then return 0 end
    return exports.bs_skills:GetSkillLevel(src, 'fishing') or 0
end
local function awardXP(src, tree, xp)
    if GetResourceState('bs_skills') == 'started' then exports.bs_skills:AddSkillXP(src, tree, xp) end
end
local function valid(src)
    local ped = GetPlayerPed(src)
    return J.CharId(src) and ped ~= 0 and GetEntityHealth(ped) > 0 and GetVehiclePedIsIn(ped, false) == 0
end
local function point(p)
    if type(p) ~= 'table' then return nil end
    for _, k in ipairs({'x','y','z'}) do
        if type(p[k]) ~= 'number' or p[k] ~= p[k] or math.abs(p[k]) > 20000 then return nil end
    end
    return vector3(p.x, p.y, p.z)
end
local function fresh(at)
    for _, area in ipairs(Jobs.Fishing.freshwater) do
        if #(vector2(at.x,at.y) - vector2(area.x,area.y)) < area.radius then return true end
    end
    return false
end
local function throttle(src)
    local now = GetGameTimer()
    if lastStart[src] and now - lastStart[src] < 1500 then return false end
    lastStart[src] = now
    return true
end

BSB.RegisterCallback('jobs:fish:start', function(src, water)
    if not throttle(src) or casts[src] or searches[src] or not valid(src) then return fail('Finish your current action first.') end
    local at, hit = J.PedPos(src), point(water)
    if not at or not hit or #(at-hit) > Jobs.Fishing.maxCastDistance then return fail('Face nearby water to cast.') end
    if INV:CountItem(src,'fishing_rod') < 1 then return fail('You need a fishing rod.') end
    if INV:CountItem(src,Jobs.Fishing.bait) < 1 then return fail('You need bait for each cast.') end
    local skill = math.min(20,math.max(0,level(src)))
    local ms = math.max(Jobs.Fishing.minMs, Jobs.Fishing.ms - skill * 175)
    local session = { pos = at, started = GetGameTimer(), ms = ms, skill = skill, fresh = fresh(hit), cid = J.CharId(src), bucket = GetPlayerRoutingBucket(src) }
    casts[src] = session -- Reserve before inventory/database calls can yield.
    if not INV:RemoveItem(src,Jobs.Fishing.bait,1) then casts[src] = nil; return fail('You need bait for each cast.') end
    return { ok = true, ms = ms, skill = skill }
end)

BSB.RegisterCallback('jobs:fish:cancel', function(src)
    casts[src] = nil
    return { ok = true }
end)

BSB.RegisterCallback('jobs:fish:finish', function(src)
    local cast = casts[src]
    casts[src] = nil
    if not cast then return fail('That cast has ended.') end
    local elapsed, at = GetGameTimer()-cast.started, J.PedPos(src)
    if not valid(src) or cast.cid ~= J.CharId(src) or cast.bucket ~= GetPlayerRoutingBucket(src)
        or elapsed < cast.ms or elapsed > 45000 or not at or #(at-cast.pos) > 3.0
        or INV:CountItem(src,'fishing_rod') < 1 then return fail('The cast was interrupted.') end
    local water = cast.fresh and 'fresh' or 'salt'
    local choices, total = {}, 0
    for _, species in ipairs(Jobs.Fishing.species) do
        if species.water == water then
            local weight = species.weight * (species.weight < 15 and (1+cast.skill*.06) or 1)
            total = total+weight
            choices[#choices+1] = { species = species, ceiling = total }
        end
    end
    local roll, caught = math.random()*total, nil
    for _, choice in ipairs(choices) do if roll <= choice.ceiling then caught = choice.species; break end end
    if not caught then return fail('Nothing took the hook.') end
    if not INV:GiveItem(src,caught.item,1) then return fail('Your inventory is full.') end
    awardXP(src,'fishing',caught.weight < 15 and 14 or 8)
    J.Progress(src,'fish_catch',1)
    return { ok = true, item = caught.item, label = INV:ItemLabel(caught.item,src) }
end)

local function allowed(model)
    for _, name in ipairs(Jobs.Foraging.models) do if GetHashKey(name) == model then return true end end
    return false
end
local function edible(model)
    for _, name in ipairs(Jobs.Foraging.berries) do if GetHashKey(name) == model then return true end end
    return false
end
local function bushKey(src, p, model)
    return ('%s:%s:%d:%d:%d'):format(GetPlayerRoutingBucket(src),model,math.floor(p.x*2+.5),math.floor(p.y*2+.5),math.floor(p.z*2+.5))
end
-- Undergrowth is keyed by the server-side player position, so the client cannot pick its own cell.
local function cellKey(src, at)
    local size = Jobs.Foraging.cellSize or 8.0
    return ('%s:u:%d:%d'):format(GetPlayerRoutingBucket(src),math.floor(at.x/size),math.floor(at.y/size))
end
BSB.RegisterCallback('jobs:forage:start', function(src, payload)
    if not throttle(src) or casts[src] or searches[src] or not valid(src) then return fail(Lp(src,'forage.busy')) end
    local pos = point(payload)
    local model = type(payload) == 'table' and tonumber(payload.model) or nil
    local at = J.PedPos(src)
    if not pos or not at or #(at-pos) > 4.5 then return fail(Lp(src,'forage.too_far')) end
    local key
    if model and allowed(model) then
        key = bushKey(src,pos,model)
    elseif Jobs.Foraging.undergrowth then
        key, model = cellKey(src,at), nil
    else
        return fail(Lp(src,'forage.too_far'))
    end
    local now = os.time()
    local state = bushes[key]
    if state and state.untilTime > now then
        return fail(Lp(src, model and 'forage.searched_bush' or 'forage.searched_area'))
    end
    bushes[key] = { untilTime = now+15, owner = src }
    searches[src] = { key = key, pos = at, model = model or 0, at = GetGameTimer(), cid = J.CharId(src), bucket = GetPlayerRoutingBucket(src) }
    return { ok = true, ms = Jobs.Foraging.ms }
end)
BSB.RegisterCallback('jobs:forage:cancel', function(src)
    local search = searches[src]
    searches[src] = nil
    if search and bushes[search.key] and bushes[search.key].owner == src then bushes[search.key] = nil end
    return { ok = true }
end)
BSB.RegisterCallback('jobs:forage:finish', function(src)
    local search = searches[src]
    searches[src] = nil
    if not search then return fail(Lp(src,'forage.interrupted')) end
    local state, at = bushes[search.key], J.PedPos(src)
    local elapsed = GetGameTimer()-search.at
    if not state or state.owner ~= src or state.untilTime <= os.time() then return fail(Lp(src,'forage.expired')) end
    if not valid(src) or J.CharId(src) ~= search.cid or search.bucket ~= GetPlayerRoutingBucket(src)
        or not at or #(at-search.pos) > 4.0 or elapsed < Jobs.Foraging.ms or elapsed > 15000 then
        bushes[search.key] = nil; return fail(Lp(src,'forage.interrupted'))
    end
    state.untilTime = os.time()+Jobs.Foraging.cooldown
    state.owner = nil
    local item = edible(search.model) and math.random(100) <= 20 and 'cranberries'
        or (math.random(100) <= 60 and 'sticks' or 'leaves')
    local amount = item == 'cranberries' and 1 or math.random(1,3)
    if not INV:GiveItem(src,item,amount) then bushes[search.key] = nil; return fail(Lp(src,'forage.full')) end
    awardXP(src,'survival',2)
    return { ok = true, item = item, amount = amount, label = INV:ItemLabel(item,src) }
end)
AddEventHandler('playerDropped', function()
    local src = source
    local search = searches[src]
    if search and bushes[search.key] and bushes[search.key].owner == src then bushes[search.key] = nil end
    casts[src], searches[src], lastStart[src] = nil,nil,nil
end)
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for key, state in pairs(bushes) do if state.untilTime <= now then bushes[key] = nil end end
        for src, cast in pairs(casts) do if GetGameTimer()-cast.started > 45000 then casts[src] = nil end end
        for src, search in pairs(searches) do if GetGameTimer()-search.at > 15000 then searches[src] = nil end end
    end
end)

RegisterCommand('bushdebug', function(src)
    if src > 0 and J.IsAdmin(src) then TriggerClientEvent('bs:jobs:bushdebug', src) end
end, false)

AddEventHandler('bs:jobs:useRod', function(src)
    if INV:CountItem(src,'fishing_rod') > 0 then TriggerClientEvent('bs:jobs:fish:use',src) end
end)
