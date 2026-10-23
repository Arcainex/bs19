-- F1 > Operations (bs_config extension page) and the /ops staff command

local function chainRows()
    local out = {}
    for id, c in pairs(Missions.chains) do
        out[#out + 1] = { id = id, title = (c.title and c.title ~= '' and c.title) or BSLocale.T('en', ('ch.%s.t'):format(id)),
            faction = c.faction or '', tier = c.tier or 'story', steps = #(c.steps or {}), builtin = c.builtin == true,
            edited = c.edited == true, disabled = c.disabled == true }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function state()
    return { ok = true, power = Power.View(), points = Points.AdminList(), chains = chainRows(), active = Missions.ActiveList(),
        factions = { 'military', 'rebels', 'civilians', 'bikers' }, types = { 'goto', 'kill', 'collect', 'deliver', 'defend', 'escort' } }
end

-- Pretty JSON for the editor textarea, keys in a stable order.
local function chainJson(c)
    local o = {}
    for _, k in ipairs({ 'faction', 'tier', 'title', 'desc', 'minLevel', 'minRep', 'requires', 'cooldownHours', 'disabled', 'steps', 'reward' }) do o[k] = c[k] end
    return json.encode(o, { indent = true })
end

local function myPos(src)
    local p = src > 0 and OpsU.pos(src)
    return p and { x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10, z = math.floor((p.z - 1.0) * 10 + 0.5) / 10 } or nil
end

local function handle(src, action, a)
    if not OpsU.isAdmin(src) then return { ok = false, error = 'Admins only.' } end
    a = type(a) == 'table' and a or {}
    if action == 'state' then return state() end
    if action == 'pos' then return { ok = true, pos = myPos(src) } end
    if action == 'goto' then
        local x, y, z = tonumber(a.x), tonumber(a.y), tonumber(a.z)
        if src <= 0 or not (x and y and z) then return { ok = false, error = 'No position.' } end
        SetEntityCoords(GetPlayerPed(src), x, y, z + 1.0, false, false, false, false)
        OpsU.log(src, ('teleport %.0f %.0f %.0f'):format(x, y, z))
        return { ok = true }
    end

    if action == 'chainGet' then
        local c = Missions.chains[tostring(a.id or '')]
        if not c then
            return { ok = true, id = '', json = json.encode({ faction = 'military', tier = 'story', title = 'New chain', desc = '', minLevel = 1, cooldownHours = 12,
                steps = { { type = 'goto', place = '', x = 0, y = 0, z = 0, radius = 25 } }, reward = { xp = 500, money = 300, rep = 20, factionXp = 100 } }, { indent = true }) }
        end
        return { ok = true, id = c.id, json = chainJson(c), builtin = c.builtin }
    end

    local detail
    if action == 'powerStart' then
        if not Missions.FACTIONS[a.faction] then return { ok = false, error = 'Pick a faction.' } end
        local ok, why = Power.AdminStart(src, a.faction)
        if not ok then return { ok = false, error = why and Lp(src, why) or 'Busy.' } end
        detail = 'power start for ' .. a.faction
    elseif action == 'powerStop' then
        Power.Stop('admin'); detail = 'power stop'
    elseif action == 'powerCooldown' then
        Power.AdminClearCooldown(); detail = 'power cooldown cleared'
    elseif action == 'powerBuff' then
        Power.AdminClearBuff(); detail = 'power buff cleared'
    elseif action == 'panelHere' then
        if src <= 0 or not Power.AdminPanelHere(src, a.idx) then return { ok = false, error = 'Could not place the panel.' } end
        detail = 'power panel ' .. tostring(a.idx) .. ' moved'
    elseif action == 'panelRemove' then
        if not Power.AdminPanelRemove(a.idx) then return { ok = false, error = 'Only while idle, and one panel must stay.' } end
        detail = 'power panel ' .. tostring(a.idx) .. ' removed'
    elseif action == 'pointSave' then
        local ok, err = Points.AdminSave(a.id, a, a.here and myPos(src) or nil)
        if not ok then return { ok = false, error = err } end
        detail = 'point saved ' .. tostring(a.id)
    elseif action == 'pointReset' then
        if not Points.AdminReset(tostring(a.id or '')) then return { ok = false, error = 'Nothing to reset.' } end
        detail = 'point reset ' .. tostring(a.id)
    elseif action == 'pointOwner' then
        local f = tostring(a.faction or '')
        if f ~= '' and not Missions.FACTIONS[f] then return { ok = false, error = 'Bad faction.' } end
        if not Points.AdminOwner(tostring(a.id or ''), f) then return { ok = false, error = 'No such point.' } end
        detail = ('point %s owner %s'):format(tostring(a.id), f ~= '' and f or 'hostile')
    elseif action == 'chainSave' then
        if type(a.json) ~= 'string' or #a.json > 20000 then return { ok = false, error = 'Too long.' } end
        local okj, data = pcall(json.decode, a.json)
        if not okj or type(data) ~= 'table' then return { ok = false, error = 'Not valid JSON.' } end
        local cid = tostring(a.id or '')
        local clean, err = Missions.Clean(cid, data)
        if not clean then return { ok = false, error = err } end
        Missions.AdminSave(cid, clean)
        detail = 'chain saved ' .. cid
    elseif action == 'chainReset' then
        if not Missions.AdminReset(tostring(a.id or '')) then return { ok = false, error = 'No editor changes on this chain.' } end
        detail = 'chain reset ' .. tostring(a.id)
    elseif action == 'chainToggle' then
        local c = Missions.chains[tostring(a.id or '')]
        if not c then return { ok = false, error = 'No such chain.' } end
        local clean = Missions.Clean(c.id, c)
        if not clean then return { ok = false, error = 'Chain does not validate.' } end
        clean.disabled = not c.disabled or nil
        Missions.AdminSave(c.id, clean)
        detail = ('chain %s %s'):format(c.id, clean.disabled and 'disabled' or 'enabled')
    else
        return { ok = false, error = 'Unknown action.' }
    end
    OpsU.log(src, detail)
    local st = state()
    st.msg = detail
    return st
end

exports('ConfigExt', function(src, action, a)
    local ok, res = pcall(handle, tonumber(src) or 0, tostring(action or ''), a)
    if not ok then print('^1[bs_operations]^7 F1: ' .. tostring(res)); return { ok = false, error = 'Server error, see console.' } end
    return res
end)

-- /ops power start <faction> | power stop | status
RegisterCommand('ops', function(src, args)
    if not OpsU.isAdmin(src) then return end
    local function say(msg)
        if src > 0 then TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = msg }) else print(msg) end
    end
    local a, b, c = args[1], args[2], args[3]
    if a == 'power' and b == 'start' then
        local r = handle(src, 'powerStart', { faction = c })
        say(r.ok and 'Power station started.' or tostring(r.error))
    elseif a == 'power' and b == 'stop' then
        handle(src, 'powerStop', {}); say('Power station stopped.')
    else
        local v = Power.View()
        say(('Power: %s | points: %d | active chains: %d'):format(v.phase, #Points.AdminList(), #Missions.ActiveList()))
    end
end, false)

exports('PowerView', function() return Power.View() end)
exports('PointsView', function() return Points.View() end)
