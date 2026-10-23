-- bs_interactions - registry: what can be interacted with and how other resources add to it. It only decides what is offered; the server decides what is allowed.

Registry = { models = {}, zones = {}, entities = {}, types = {} }

-- [modelHash] = model name it was registered under. Hashes cannot be reversed, so names are remembered here for the target debug overlay (cl_target.lua). Optional.
Registry.modelNames = {}

-- Options can carry labelKey: the label is then looked up in the registering resource's
-- locales/<lang>.lua (labelRes, filled in on registration) so it follows the player's language.
-- label stays as the fallback text.
local foreign = {}
local function foreignDict(res, lang)
    local id = res .. ':' .. lang
    if foreign[id] ~= nil then return foreign[id] end
    local dict = false
    local src = LoadResourceFile(res, ('locales/%s.lua'):format(lang))
    if src then
        local fn = load(src, ('@%s/locales/%s.lua'):format(res, lang), 't', {})
        if fn then
            local ok, t = pcall(fn)
            if ok and type(t) == 'table' then dict = t end
        end
    end
    foreign[id] = dict
    return dict
end

function Registry.Label(o)
    if type(o) ~= 'table' then return '' end
    if not o.labelKey then return o.label end
    local res = o.labelRes or GetCurrentResourceName()
    local d = foreignDict(res, BSLocale.Lang())
    local text = d and d[o.labelKey]
    if text == nil then
        d = foreignDict(res, 'en')
        text = d and d[o.labelKey]
    end
    return tostring(text or o.label or o.labelKey or '')
end

local function stamp(options, res)
    if not res or res == '' then return end
    for _, opt in ipairs(options or {}) do
        if type(opt) == 'table' and opt.labelKey and not opt.labelRes then opt.labelRes = res end
    end
end

-- Adds options for a set of models.
-- exports.bs_interactions:AddModel({'prop_bin_01a'}, { { label = ..., event = ... } })
function Registry.AddModel(models, options)
    if type(models) == 'string' then models = { models } end
    stamp(options, GetInvokingResource())

    for _, model in ipairs(models or {}) do
        local hash = type(model) == 'number' and model or GetHashKey(model)
        Registry.models[hash] = Registry.models[hash] or {}
        if type(model) == 'string' then Registry.modelNames[hash] = model end

        for _, opt in ipairs(options or {}) do
            -- Skip an option identical to one already on this model (same label and action). Model lists are hand written and get duplicated.
            local already = false
            for _, existing in ipairs(Registry.models[hash]) do
                if existing == opt
                    or (existing.label == opt.label
                        and existing.event == opt.event
                        and existing.serverEvent == opt.serverEvent
                        and existing.action == opt.action) then
                    already = true
                    break
                end
            end

            if not already then
                Registry.models[hash][#Registry.models[hash] + 1] = opt
            end
        end
    end
end

--- Adds options for a sphere in the world.
function Registry.AddZone(id, coords, radius, options)
    stamp(options, GetInvokingResource())
    Registry.zones[id] = { coords = coords, radius = radius or 1.5, options = options or {} }
end

function Registry.RemoveZone(id) Registry.zones[id] = nil end

-- [entity] = flags passed to AddEntity (e.g. { noOutline = true }), read by setOutline() in cl_target.lua. Optional.
Registry.entityFlags = {}

-- Adds options for one entity handle (a spawned prop, a vendor ped).
-- `flags` is optional, e.g. exports.bs_interactions:AddEntity(ped, opts, { noOutline = true }).
function Registry.AddEntity(entity, options, flags)
    if not DoesEntityExist(entity) then return false end
    stamp(options, GetInvokingResource())
    Registry.entities[entity] = options or {}
    Registry.entityFlags[entity] = flags
    return true
end

-- Removing an entity also drops it from cl_target.lua's cache right away (see Target.ForceRelease). Target is a global from the same resource.
function Registry.RemoveEntity(entity)
    Registry.entities[entity] = nil
    Registry.entityFlags[entity] = nil
    if Target and Target.ForceRelease then Target.ForceRelease(entity) end
end

--- Adds options for a whole entity class: 'ped' | 'vehicle' | 'object'.
function Registry.AddType(entityType, options)
    Registry.types[entityType] = Registry.types[entityType] or {}
    stamp(options, GetInvokingResource())
    for _, opt in ipairs(options or {}) do
        Registry.types[entityType][#Registry.types[entityType] + 1] = opt
    end
end

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

local TYPE_NAME = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

-- Filters: functions do not survive an export boundary, so options from other resources describe conditions as data (strings, numbers) that are evaluated here. Example: filters = { onFoot = true, behind = true, maxDistance = 3.0 }. `canInteract` only works for options registered by bs_interactions itself.

--- @return boolean, string|nil  passes, and why not if it does not
local function passesFilters(f, entity, distance)
    if type(f) ~= 'table' then return true end

    local ped = PlayerPedId()

    if f.maxDistance and distance > f.maxDistance then return false end
    if f.minDistance and distance < f.minDistance then return false end

    -- On foot / in a vehicle.
    if f.onFoot and IsPedInAnyVehicle(ped, false) then return false end
    if f.inVehicle and not IsPedInAnyVehicle(ped, false) then return false end

    -- Where you stand relative to the target. `behind` stops a boot opening from the bonnet.
    if (f.behind or f.inFront) and DoesEntityExist(entity) then
        local offset = GetOffsetFromEntityGivenWorldCoords(entity, GetEntityCoords(ped))
        if f.behind and offset.y > -0.5 then return false end
        if f.inFront and offset.y < 0.5 then return false end
    end

    -- State bags on the entity let other resources express conditions without a function. Walkers are local, non-networked peds, so player-only options must bail out on IsPedAPlayer before touching state bags.
    if f.playerPed and not (DoesEntityExist(entity) and IsEntityAPed(entity) and IsPedAPlayer(entity)) then
        return false
    end

    if (f.stateTrue or f.stateFalse) and DoesEntityExist(entity) then
        if not NetworkGetEntityIsNetworked(entity) then
            if f.stateTrue then return false end
            goto stateDone
        end
        local state = Entity(entity).state
        if f.stateTrue and not (state and state[f.stateTrue]) then return false end
        if f.stateFalse and (state and state[f.stateFalse]) then return false end
    end
    ::stateDone::

    -- A global flag another resource keeps on the player.
    if f.playerStateTrue or f.playerStateFalse then
        local state = LocalPlayer.state
        if f.playerStateTrue and not (state and state[f.playerStateTrue]) then return false end
        if f.playerStateFalse and (state and state[f.playerStateFalse]) then return false end
    end

    -- Is this ped another player rather than a walker or scenery?
    if f.playerPed and not (DoesEntityExist(entity) and IsPedAPlayer(entity)) then
        return false
    end

    -- A flag on the player who owns this ped (e.g. bs_medical's downed state on their state bag). Resolves the ped back to its player.
    if f.ownerStateTrue or f.ownerStateFalse then
        if not DoesEntityExist(entity) or not IsEntityAPed(entity) or not IsPedAPlayer(entity) then return false end

        local playerId = NetworkGetPlayerIndexFromPed(entity)
        if not playerId or playerId == -1 then return false end

        local serverId = GetPlayerServerId(playerId)
        if serverId <= 0 then return false end

        local state = Player(serverId).state
        if f.ownerStateTrue and not (state and state[f.ownerStateTrue] == true) then return false end
        if f.ownerStateFalse and (state and state[f.ownerStateFalse] == true) then return false end
    end

    -- Dead peds (animal carcasses) and burnt-out vehicles, for bs_crafting.
    if f.dead and not (DoesEntityExist(entity) and IsEntityDead(entity)) then return false end
    if f.wreck and not (DoesEntityExist(entity) and IsEntityAVehicle(entity)
        and (IsEntityDead(entity) or GetVehicleEngineHealth(entity) <= -3900.0)) then return false end
    if f.models then
        -- ModelOf checks the handle first; GetEntityModel on a removed entity faults.
        local m, hit = BS.Util.ModelOf(entity), false
        if not m then return false end
        for _, name in ipairs(f.models) do if GetHashKey(name) == m then hit = true break end end
        if not hit then return false end
    end

    return true
end

-- Everything offered for a hit, filtered by declared filters, canInteract (same resource only) and distance. `checkZones` defaults to true, pass false when the caller resolves zones itself (see ResolveZones).
function Registry.Resolve(entity, coords, distance, checkZones)
    local out = {}

    local function add(list)
        for _, opt in ipairs(list or {}) do
            local ok = true

            if opt.distance and distance > opt.distance then ok = false end

            if ok and opt.filters then
                local success, result = pcall(passesFilters, opt.filters, entity, distance)
                ok = success and result and true or false
            end

            if ok and type(opt.canInteract) == 'function' then
                local success, result = pcall(opt.canInteract, entity, distance)
                ok = success and result and true or false
            end

            -- Skip options whose `action` arrived uncallable, and print once so the mistake shows in the console instead of a frozen-looking dot.
            if ok and not opt.event and not opt.serverEvent
               and type(opt.action) ~= 'function' then
                if not opt.__warned then
                    opt.__warned = true
                    print(('^1[BeyondSurvival]^7 (interactions) option "%s" has nothing to run - '
                        .. 'a function cannot cross a resource boundary, use `event` instead')
                        :format(tostring(opt.label)))
                end
                ok = false
            end

            if ok then out[#out + 1] = opt end
        end
    end

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        add(Registry.entities[entity])
        -- Uses BS.Util.ModelOf, which checks existence and memoizes faulting entities (see sh_util).
        local model = BS.Util.ModelOf(entity)
        if model then add(Registry.models[model]) end
        add(Registry.types[TYPE_NAME[GetEntityType(entity)]])
    end

    if checkZones ~= false then
        for _, zone in pairs(Registry.zones) do
            if #(coords - zone.coords) <= zone.radius then add(zone.options) end
        end
    end

    return out
end

-- Zones, centred on the player: resolved separately so a dropped item is found by standing near it even when the raycast hits nothing.
function Registry.ResolveZones(coords)
    local out = {}
    for _, zone in pairs(Registry.zones) do
        if #(coords - zone.coords) <= zone.radius then
            for _, opt in ipairs(zone.options or {}) do out[#out + 1] = opt end
        end
    end
    return out
end

exports('AddModel', Registry.AddModel)
exports('AddZone', Registry.AddZone)
exports('RemoveZone', Registry.RemoveZone)
exports('AddEntity', Registry.AddEntity)
exports('RemoveEntity', Registry.RemoveEntity)
exports('AddType', Registry.AddType)
