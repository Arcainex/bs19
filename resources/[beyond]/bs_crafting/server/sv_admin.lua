-- bs_crafting: F1 recipe editor backend and building registration.
-- bs_config checks admin rights before it forwards anything here (see ConfigExt in bs_config).

local INV = exports.bs_inventory

local function validItem(name) return type(name) == 'string' and INV:GetItem(name) ~= nil end

local function clean(r)
    if type(r) ~= 'table' or type(r.result) ~= 'table' or not validItem(r.result.item) then return nil, 'Unknown result item.' end
    if r.station ~= nil and r.station ~= '' and not Crafting.Stations[r.station] then return nil, 'Unknown station.' end
    local out = {
        label = type(r.label) == 'string' and r.label ~= '' and r.label:sub(1, 48) or nil,
        cat = type(r.cat) == 'string' and r.cat:sub(1, 16) or 'misc',
        station = (r.station ~= '' and r.station) or nil,
        result = { item = r.result.item, amount = math.max(1, math.min(100, math.floor(tonumber(r.result.amount) or 1))) },
        time = math.max(1, math.min(3600, math.floor(tonumber(r.time) or 5))),
        cost = {},
        explosive = r.explosive and true or nil,
        burn = validItem(r.burn) and r.burn or nil,
        factionBase = r.factionBase and true or nil,
    }
    if type(r.tool) == 'table' then
        out.tool = {}
        for _, t in ipairs(r.tool) do if validItem(t) then out.tool[#out.tool + 1] = t end end
        if #out.tool == 0 then out.tool = nil end
    end
    for _, c in ipairs(r.cost or {}) do
        if not validItem(c.item) then return nil, 'Unknown cost item: ' .. tostring(c.item) end
        out.cost[#out.cost + 1] = { item = c.item, amount = math.max(1, math.min(999, math.floor(tonumber(c.amount) or 1))) }
        if #out.cost >= 8 then break end
    end
    if #out.cost == 0 then return nil, 'A recipe needs at least one cost.' end
    return out
end

local function listState()
    local items = {}
    for name, d in pairs(INV:GetItems() or {}) do items[#items + 1] = { id = name, label = d.label } end
    table.sort(items, function(a, b) return a.id < b.id end)
    local ov = Craft.Overrides()
    local recipes = {}
    local all = {}
    for id in pairs(Crafting.Recipes) do all[id] = true end
    for id in pairs(ov) do all[id] = true end
    for id in pairs(all) do
        local base = Crafting.Recipes[id]
        local r = ov[id]
        recipes[#recipes + 1] = { id = id, recipe = (r ~= false and r) or base, disabled = r == false,
            edited = r ~= nil, custom = base == nil }
    end
    table.sort(recipes, function(a, b) return a.id < b.id end)
    local stations = {}
    for id, d in pairs(Crafting.Stations) do if not d.farm then stations[#stations + 1] = { id = id, label = d.label } end end
    return { ok = true, recipes = recipes, items = items, stations = stations, categories = Crafting.Categories }
end

local function who(src) return src == 0 and 'console' or (GetPlayerName(src) or tostring(src)) end

exports('ConfigExt', function(src, action, a)
    if action == 'recipes' then return listState() end
    local ov = Craft.Overrides()
    if action == 'saveRecipe' and type(a) == 'table' then
        local id = tostring(a.id or ''):lower():gsub('[^%w_]', '')
        if id == '' or #id > 48 then return { ok = false, error = 'Bad recipe id.' } end
        local r, err = clean(a.recipe)
        if not r then return { ok = false, error = err } end
        ov[id] = r
        Craft.SaveOverrides(ov)
        if src > 0 then Craft.Log(src, 'craft_admin', 'recipe saved ' .. id) end
        print(('[bs_crafting] %s saved recipe %s'):format(who(src), id))
        return listState()
    elseif action == 'disableRecipe' then
        ov[tostring(a)] = false
        Craft.SaveOverrides(ov)
        if src > 0 then Craft.Log(src, 'craft_admin', 'recipe disabled ' .. tostring(a)) end
        return listState()
    elseif action == 'resetRecipe' then
        ov[tostring(a)] = nil
        Craft.SaveOverrides(ov)
        if src > 0 then Craft.Log(src, 'craft_admin', 'recipe reset ' .. tostring(a)) end
        return listState()
    end
    return { ok = false, error = 'Unknown action.' }
end)

-- Hand our stations to bs_building whichever of us starts first.
local function registerPlaceables()
    if GetResourceState('bs_building') ~= 'started' then return end
    local defs = exports[GetCurrentResourceName()]:StationDefs()
    for _, d in pairs(defs) do
        pcall(function() exports.bs_building:RegisterPlaceable(d) end)
    end
end

CreateThread(function() Wait(5000) registerPlaceables() end)
AddEventHandler('onResourceStart', function(res)
    if res == 'bs_building' then SetTimeout(5000, registerPlaceables) end
end)
