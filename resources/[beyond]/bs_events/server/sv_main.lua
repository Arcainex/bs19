-- bs_events - scheduler, shared event state, crate interaction, announcements, admin commands and the faction XP token

EV = { Kinds = {}, Active = {}, nextId = 1 }
local Pending = {}           -- [src] = { evId, cid, started, duration }
local Fired = {}             -- ['airdrop|2026-09-30|21:00'] = true

local function now() return GetGameTimer() end

local function started(res) return GetResourceState(res) == 'started' end

function EV.Log(msg, ...) print(('^3[bs_events]^7 ' .. msg):format(...)) end

-- Helpers

function EV.Players()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            out[#out + 1] = { src = tonumber(id), x = c.x, y = c.y, z = c.z }
        end
    end
    return out
end

function EV.Dist2D(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function EV.SafeZones()
    if not started('bs_zombies') then return {} end
    local ok, z = pcall(function() return exports.bs_zombies:SafeZonesPadded() end)
    return ok and z or {}
end

function EV.InSafeZone(x, y)
    for _, z in ipairs(EV.SafeZones()) do
        if EV.Dist2D(x, y, z.x, z.y) <= (z.padded or z.radius) then return true end
    end
    return false
end

function EV.RollLoot(tbl)
    local out = {}
    if not tbl then return out end
    for _ = 1, tbl.rolls or 3 do
        local row = tbl[math.random(#tbl)]
        if row and math.random() <= (row.chance or 1.0) then
            out[#out + 1] = { item = row.item, amount = math.random(row.min or 1, row.max or row.min or 1) }
        end
    end
    if #out == 0 and tbl[1] then out[1] = { item = tbl[1].item, amount = tbl[1].min or 1 } end
    return out
end

-- Registers a container and fills it. Returns the container id.
function EV.MakeContainer(evId, cid, label, loot)
    local id = ('evt:%d:%d:%d'):format(evId, cid, os.time() % 100000)
    exports.bs_inventory:RegisterContainer(id, { width = 6, height = 4, maxWeight = 150.0, label = label })
    for _, row in ipairs(loot) do
        pcall(function() exports.bs_inventory:ContainerGive(id, row.item, row.amount) end)
    end
    return id
end

function EV.Noise(x, y, z, loud)
    if not started('bs_zombies') then return end
    pcall(function() exports.bs_zombies:EventNoise(x, y, z, loud, 'event') end)
end

-- Client sync. Clients get plain data only; timings are sent as "ms ago".

local function view(ev)
    local crates = {}
    for cid, c in pairs(ev.crates or {}) do
        if not c.gone then
            crates[#crates + 1] = { id = cid, x = c.x, y = c.y, z = c.z, h = c.h or 0.0,
                                    model = c.model, locked = c.locked or false, wait = c.wait or false, landAgo = c.landAt and (now() - c.landAt) or nil,
                                    net = c.net, guarded = c.guarded or false, dropped = c.dropped or false, kind = c.kind }
        end
    end
    return {
        id = ev.id, kind = ev.kind, label = ev.label,
        area = ev.area, blip = ev.blipAt, radius = ev.blipRadius,
        ago = now() - ev.t0, visual = ev.visual, crates = crates,
    }
end

function EV.Sync(target)
    local list = {}
    for _, ev in pairs(EV.Active) do list[#list + 1] = view(ev) end
    TriggerClientEvent('bs_events:state', target or -1, list)
end

RegisterNetEvent('bs_events:hello', function() EV.Sync(source) end)

-- Announcements

local CHAT_COLOUR = { 214, 120, 52 }

-- Each player gets the broadcast in their own language. title and body are locale keys, vars fill them in.
function EV.Announce(kind, title, body, vars, coords)
    local grid = coords and ('%d, %d'):format(math.floor(coords.x), math.floor(coords.y)) or nil
    local chat = Events.Settings.chat and started('bs_chat')
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        local v = vars
        if type(vars) == 'table' and type(vars.place) == 'string' and vars.place:sub(1, 4) == 'loc:' then
            v = {}
            for k, x in pairs(vars) do v[k] = x end
            v.place = Lp(p, vars.place:sub(5))
        end
        local t, b = Lp(p, title, v), Lp(p, body, v)
        TriggerClientEvent('bs_events:radio', p, { kind = kind, title = t, body = b, grid = grid,
            seconds = Events.Settings.radioSeconds or 16 })
        if chat then
            pcall(function() exports.bs_chat:Send(p, Lp(p, 'ev.radio_tag'), t .. ' - ' .. b, CHAT_COLOUR) end)
        end
    end
end

-- Lifecycle

function EV.Start(kind, by, opts)
    local k = EV.Kinds[kind]
    if not k then return false, 'unknown event' end
    local ev = { id = EV.nextId, kind = kind, t0 = now(), crates = {}, by = by }
    EV.nextId = EV.nextId + 1
    ev.tag = ('evt_%s_%d'):format(kind, ev.id)
    local ok, err = k.start(ev, opts)
    if not ok then return false, err or 'could not start' end
    EV.Active[ev.id] = ev
    EV.Log('%s #%d started (%s) by %s', kind, ev.id, ev.label or '?', by or 'schedule')
    EV.Sync()
    return true, ev.id
end

function EV.Stop(id, reason)
    local ev = EV.Active[id]
    if not ev then return false end
    EV.Active[id] = nil
    for _, c in pairs(ev.crates) do
        if c.container then pcall(function() exports.bs_inventory:ContainerTakeAll(c.container) end) end
    end
    local k = EV.Kinds[ev.kind]
    if k and k.stop then pcall(k.stop, ev, reason) end
    for src, p in pairs(Pending) do if p.evId == id then Pending[src] = nil end end
    TriggerClientEvent('bs_events:ended', -1, id)
    EV.Log('%s #%d ended (%s)', ev.kind, id, reason or 'done')
    return true
end

function EV.CratePatch(ev, cid, patch)
    TriggerClientEvent('bs_events:crate', -1, ev.id, cid, patch)
end

-- Ticks: timeouts, emptied crates, per-kind think.
CreateThread(function()
    while true do
        Wait(5000)
        for id, ev in pairs(EV.Active) do
            if ev.endsAt and now() >= ev.endsAt then
                EV.Stop(id, 'timeout')
            else
                local left = 0
                for cid, c in pairs(ev.crates) do
                    if not c.gone then
                        if c.opened and c.container then
                            local ok, has = pcall(function() return exports.bs_inventory:ContainerHasItems(c.container) end)
                            if ok and not has then
                                c.gone = true
                                EV.CratePatch(ev, cid, { gone = true })
                                if c.ped and DoesEntityExist(c.ped) then Entity(c.ped).state:set('bsBodyLooted', true, true) end
                            end
                        end
                        if not c.gone and not c.body then left = left + 1 end
                    end
                end
                local k = EV.Kinds[ev.kind]
                if k.think then pcall(k.think, ev) end
                if k.usesCrates and ev.cratesReady and left == 0 then EV.Stop(id, 'looted') end
            end
        end
    end
end)

-- Crate interaction: begin (server starts the clock) to finish (checked)

local REACH = 4.0

local function playerAt(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function hasTool(src, tools)
    for _, item in ipairs(tools or {}) do
        local ok, n = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
        if ok and (tonumber(n) or 0) > 0 then return item end
    end
    return nil
end

-- bodies move when ragdolled: follow the ped (trucks are kept current by the convoy think)
local function syncPos(c)
    if c.ped and DoesEntityExist(c.ped) then
        local pc = GetEntityCoords(c.ped)
        c.x, c.y, c.z = pc.x, pc.y, pc.z
    end
end

BSB.RegisterCallback('events:begin', function(src, evId, cid)
    local ev = EV.Active[tonumber(evId)]
    local c = ev and ev.crates[tonumber(cid)]
    if not c or c.gone then return { ok = false, error = Lp(src, 'ev.nothing_here') } end
    if (c.landAt and now() < c.landAt) or c.wait or c.attached or c.dropping then return { ok = false, error = Lp(src, 'ev.still_coming') } end
    if c.guarded then return { ok = false, error = Lp(src, 'ev.guarded') } end
    if c.truck and not c.stopped then return { ok = false, error = Lp(src, 'ev.not_stopped') } end
    syncPos(c)
    local at = playerAt(src)
    if not at or EV.Dist2D(at.x, at.y, c.x, c.y) > (c.reach or REACH) then return { ok = false, error = Lp(src, 'ev.too_far') } end

    local duration, label, tool = (c.openSeconds or 6) * 1000, Lp(src, c.openLabel or 'ev.opening'), nil
    if c.locked then
        tool = hasTool(src, Events.Convoy.tools)
        if not tool then return { ok = false, error = Lp(src, 'ev.locked_need') } end
        duration = math.random(Events.Convoy.lockMin or 20, Events.Convoy.lockMax or 40) * 1000
        label = tool == 'crowbar' and Lp(src, 'ev.prying') or Lp(src, 'ev.picking')
        EV.Noise(c.x, c.y, c.z, Events.Convoy.noiseLoudness or 220.0)
    end
    Pending[src] = { evId = ev.id, cid = tonumber(cid), started = now(), duration = duration, tool = tool }
    return { ok = true, duration = duration, label = label }
end)

BSB.RegisterCallback('events:finish', function(src)
    local p = Pending[src]
    Pending[src] = nil
    if not p then return { ok = false } end
    local ev = EV.Active[p.evId]
    local c = ev and ev.crates[p.cid]
    if not c or c.gone then return { ok = false, error = Lp(src, 'ev.gone') } end
    if now() - p.started < p.duration - 1500 then return { ok = false, error = Lp(src, 'ev.too_quick') } end
    -- state may have changed during the search
    if c.guarded then return { ok = false, error = Lp(src, 'ev.guarded') } end
    syncPos(c)
    local at = playerAt(src)
    if not at or EV.Dist2D(at.x, at.y, c.x, c.y) > (c.reach or REACH) then return { ok = false, error = Lp(src, 'ev.too_far') } end

    if c.locked then
        c.locked = false
        EV.CratePatch(ev, p.cid, { locked = false })
        if p.tool == 'lockpick' and math.random() < (Events.Convoy.lockpickBreak or 0.35) then
            pcall(function() exports.bs_inventory:RemoveItem(src, 'lockpick', 1) end)
            TriggerClientEvent('bs:ui:notify', src, { type = 'warn', message = Lp(src, 'ev.pick_snapped') })
        end
    end
    -- Wasteland Pass counts the first open of an event crate per player.
    TriggerEvent('bs:events:crateOpened', src, c.container)
    c.opened = true
    if (c.cash or 0) > 0 then
        local amount = c.cash
        c.cash = 0
        local okc = pcall(function() return exports.bs_core:AddMoney(src, 'cash', amount, 'convoy_npc') end)
        if okc then TriggerClientEvent('bs:ui:notify', src, { type = 'success', message = Lp(src, 'ev.cash_found', { n = amount }) }) end
    end
    exports.bs_inventory:RegisterContainer(c.container, { width = 6, height = 4, maxWeight = 150.0, label = Lp(src, c.labelKey or ('ev.crate_' .. tostring(ev.kind))) }, src)
    exports.bs_inventory:OpenContainerFor(src, c.container)
    return { ok = true }
end)

RegisterNetEvent('bs_events:cancel', function() Pending[source] = nil end)
AddEventHandler('playerDropped', function() Pending[source] = nil end)

-- Scheduler

local DAYS = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }

local function dayMatches(days, wday)
    days = tostring(days or 'daily'):lower()
    if days == 'daily' or days == '' then return true end
    for d in days:gmatch('[a-z]+') do
        if DAYS[d:sub(1, 3)] == wday then return true end
    end
    return false
end

local function activeCount()
    local n = 0
    for _ in pairs(EV.Active) do n = n + 1 end
    return n
end

local ConvoyLast, ConvoyJit = os.time(), nil   -- last convoy start (server boot counts), chosen jitter in seconds

local function convoyDue()
    local c = Events.Convoy
    local iv = tonumber(c.intervalMinutes) or 0
    if iv <= 0 then return false end
    if ConvoyJit == nil then
        local j = math.max(0, tonumber(c.jitterMinutes) or 0)
        ConvoyJit = math.floor((math.random() * 2 - 1) * j * 60)
    end
    return os.time() >= ConvoyLast + math.max(60, iv * 60 + ConvoyJit)
end

CreateThread(function()
    Wait(15000)
    while true do
        local t = os.date('*t')
        if Events.Settings.enabled then
            local hm = ('%02d:%02d'):format(t.hour, t.min)
            local dateKey = os.date('%Y-%m-%d')
            for kind, s in pairs(Events.Schedule) do
                local byInterval = kind == 'convoy' and (tonumber(Events.Convoy.intervalMinutes) or 0) > 0
                if s.enabled and EV.Kinds[kind] and byInterval then
                    if convoyDue() then
                        ConvoyLast, ConvoyJit = os.time(), nil
                        local need = tonumber(Events.Convoy.minPlayers) or Events.Settings.minPlayers or 1
                        if Events.Convoy.enabled and activeCount() < (Events.Settings.maxConcurrent or 3) and #GetPlayers() >= need then
                            local ok, err = EV.Start(kind, 'schedule')
                            if not ok then EV.Log('scheduled %s skipped: %s', kind, tostring(err)) end
                        end
                    end
                elseif s.enabled and EV.Kinds[kind] and dayMatches(s.days, t.wday) then
                    for time in tostring(s.times or ''):gmatch('[^,%s]+') do
                        local h, m = time:match('^(%d%d?):(%d%d)$')
                        if h and ('%02d:%02d'):format(tonumber(h), tonumber(m)) == hm then
                            local key = kind .. '|' .. dateKey .. '|' .. hm
                            if not Fired[key] then
                                Fired[key] = true
                                local need = Events.Settings.minPlayers or 1
                                if kind == 'convoy' then need = tonumber(Events.Convoy.minPlayers) or need end
                                if activeCount() < (Events.Settings.maxConcurrent or 3) and #GetPlayers() >= need then
                                    local ok, err = EV.Start(kind, 'schedule')
                                    if not ok then EV.Log('scheduled %s skipped: %s', kind, tostring(err)) end
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(20000)
    end
end)

-- Admin commands: /event start <kind> | stop <kind|id|all> | list

local function isAdmin(src)
    if src == 0 then return true end
    if started('bs_admin') then
        local ok, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok then return yes == true end
    end
    return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin')
end

local function reply(src, msg)
    if src == 0 then print('[bs_events] ' .. msg) else
        TriggerClientEvent('chat:addMessage', src, { args = { '[EVENTS]', msg }, color = CHAT_COLOUR })
    end
end

-- Exports for the F10 staff menu (bs_admin). at = { x, y, z, h } starts the event on that spot.
exports('EventKinds', function()
    local out = {}
    for kind, k in pairs(EV.Kinds) do
        local cfg = Events[kind:sub(1, 1):upper() .. kind:sub(2)]
        local running = 0
        for _, ev in pairs(EV.Active) do if ev.kind == kind then running = running + 1 end end
        out[#out + 1] = { kind = kind, enabled = not cfg or cfg.enabled ~= false, atOk = k.atOk == true, running = running }
    end
    table.sort(out, function(a, b) return a.kind < b.kind end)
    return out
end)

exports('StartEvent', function(kind, by, at)
    return EV.Start(tostring(kind), by, at and { at = at } or nil)
end)

exports('StopAllEvents', function()
    local n = 0
    for id in pairs(EV.Active) do if EV.Stop(id, 'admin') then n = n + 1 end end
    return n
end)

EV.IsAdmin, EV.Reply = isAdmin, reply

RegisterCommand('convoydebug', function(src)
    if not isAdmin(src) then return reply(src, L(src, 'ev.admins_only')) end
    local any = false
    for id, ev in pairs(EV.Active) do
        local cv = ev.cv
        if ev.kind == 'convoy' and cv then
            any = true
            reply(src, ('[convoy] #%d owner=%s ready=%s wp=%s/%d arrived=%s tries=%s'):format(id, tostring(cv.owner), tostring(cv.ready), tostring(cv.wp), #cv.route, tostring(cv.arrived), tostring(cv.tries)))
            for cid, c in pairs(ev.crates) do
                reply(src, ('  crate %d kind=%s truck=%s guarded=%s stopped=%s gone=%s'):format(cid, tostring(c.kind), tostring(c.truck), tostring(c.guarded), tostring(c.stopped), tostring(c.gone)))
            end
            for i, v in ipairs(cv.veh) do
                local ex = DoesEntityExist(v)
                local c = ex and GetEntityCoords(v) or vector3(0, 0, 0)
                local p = cv.ped[i]
                local pe = p and DoesEntityExist(p)
                reply(src, ('  unit %d veh=%s net=%s exists=%s owner=%s frozen=%s pos=%.0f,%.0f,%.1f | ped=%s exists=%s seated=%s'):format(
                    i, tostring(v), ex and tostring(NetworkGetNetworkIdFromEntity(v)) or '-', tostring(ex),
                    ex and tostring(NetworkGetEntityOwner(v)) or '-', ex and tostring(IsEntityPositionFrozen(v)) or '-',
                    c.x, c.y, c.z, tostring(p), tostring(pe), tostring(ex and pe and GetPedInVehicleSeat(v, -1) == p)))
            end
        end
    end
    if not any then reply(src, L(src, 'ev.no_convoy')) end
end, false)

RegisterCommand('event', function(src, args)
    if not isAdmin(src) then return reply(src, L(src, 'ev.admins_only')) end
    local sub, what = (args[1] or 'list'):lower(), (args[2] or ''):lower()
    if sub == 'start' then
        local ok, res = EV.Start(what, src == 0 and 'console' or GetPlayerName(src))
        reply(src, ok and L(src, 'ev.started', { what = what, id = res }) or L(src, 'ev.start_failed', { why = res }))
    elseif sub == 'stop' then
        local n = 0
        for id, ev in pairs(EV.Active) do
            if what == 'all' or ev.kind == what or tostring(id) == what then
                if EV.Stop(id, 'admin') then n = n + 1 end
            end
        end
        reply(src, L(src, 'ev.stopped_n', { n = n }))
    else
        local any = false
        for id, ev in pairs(EV.Active) do
            any = true
            reply(src, ('#%d %s - %s (%ds)'):format(id, ev.kind, ev.label or '?', math.floor((now() - ev.t0) / 1000)))
        end
        if not any then reply(src, L(src, 'ev.none_running')) end
    end
end, false)

-- Faction XP token: use it inside your own faction flag radius.

AddEventHandler('bsesx:useItem:' .. Events.FactionToken.item, function(src)
    local function tell(kind, msg) TriggerClientEvent('bs:ui:notify', src, { type = kind, message = msg }) end
    if not (started('bs_factions') and started('bs_faction_bases')) then return tell('error', Lp(src, 'ev.fac_offline')) end
    local fid = exports.bs_factions:GetFaction(src)
    if not fid then return tell('warn', Lp(src, 'ev.not_in_fac')) end
    local flag = exports.bs_faction_bases:FlagAt(src)
    if not flag or tostring(flag.factionId) ~= tostring(fid) then
        return tell('warn', Lp(src, 'ev.use_in_flag'))
    end
    if not exports.bs_inventory:RemoveItem(src, Events.FactionToken.item, 1) then return end
    local ok, added = pcall(function() return exports.bs_factions:AddFactionXP(fid, Events.FactionToken.xp, 'event_token') end)
    added = ok and tonumber(added) or 0
    if added > 0 then
        tell('success', Lp(src, 'ev.token_xp', { n = added }))
    else
        -- max level or progression offline: give it back
        exports.bs_inventory:GiveItem(src, Events.FactionToken.item, 1)
        tell('warn', Lp(src, 'ev.fac_full'))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(EV.Active) do EV.Stop(id, 'resource stop') end
end)
