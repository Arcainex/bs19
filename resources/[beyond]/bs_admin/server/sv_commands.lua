-- bs_admin - staff chat commands (ESX style)

local A = BSAdmin

local function T(src, key, vars) return Lp(src > 0 and src or nil, key, vars) end

local function reply(src, ok, text)
    if src == 0 then return print(('^3[BS ADMIN]^7 %s'):format(text)) end
    TriggerClientEvent('bs:ui:notify', src, { type = ok and 'success' or 'error', message = text, duration = 5000 })
end

local function result(src, r, okText)
    r = r or { ok = false }
    if r.ok then reply(src, true, r.note or okText) else reply(src, false, T(src, 'admin.c.failed', { err = r.error or '?' })) end
    return r
end

local function command(name, handler)
    RegisterCommand(name, function(src, args, raw)
        if src > 0 and not A.isAdmin(src) then return reply(src, false, T(src, 'admin.c.denied')) end
        local ok, err = pcall(handler, src, args, raw or '')
        if not ok then
            print(('^1[BS ADMIN]^7 /%s failed: %s'):format(name, tostring(err)))
            reply(src, false, T(src, 'admin.c.failed', { err = 'error' }))
        end
    end, false)
end

-- "me" (or nothing) is yourself, otherwise an online server id.
local function who(src, word)
    if word == nil or word == '' or word == 'me' then return src > 0 and src or nil end
    local id = tonumber(word)
    return (id and GetPlayerName(id)) and id or nil
end

local function onOff(word, current)
    word = tostring(word or ''):lower()
    if word == 'on' or word == '1' or word == 'true' then return true end
    if word == 'off' or word == '0' or word == 'false' then return false end
    return not current
end

local function worldState()
    if GetResourceState('bs_world') ~= 'started' then return {} end
    local ok, st = pcall(function() return exports.bs_world:WorldState() end)
    return ok and st or {}
end

-- /dz [radius] - walkers around you, through the zombie director
command('dz', function(src, args)
    if src == 0 then return reply(src, false, T(src, 'admin.u.ingame')) end
    local r = A.run(src, 'clearZombies', { radius = tonumber(args[1]) or 50 })
    result(src, r, r.ok and T(src, 'admin.c.dz_done', { n = r.count or 0, r = r.radius or 50 }))
end)

-- /ann [-t Title] <text>, /announce ..
local function announce(src, _, raw)
    local text = raw:gsub('^%S+%s*', '')
    local title
    local t, rest = text:match('^%-t%s+"([^"]+)"%s*(.*)$')
    if not t then t, rest = text:match('^%-t%s+(%S+)%s*(.*)$') end
    if t then title, text = t:gsub('_', ' '), rest end
    if text == '' then return reply(src, false, T(src, 'admin.c.usage', { u = '/ann [-t Title] <text>' })) end
    result(src, A.run(src, 'announce', { title = title, text = text }), T(src, 'admin.c.ann_sent'))
end
command('ann', announce)
command('announce', announce)

-- /weather <type> - sets and holds it, same as F10 WORLD
command('weather', function(src, args)
    local w = tostring(args[1] or ''):upper()
    local known = false
    for _, v in ipairs(Admin.Weather) do if v == w then known = true end end
    if not known then
        return reply(src, false, T(src, 'admin.c.weather_bad', { list = table.concat(Admin.Weather, ', ') }))
    end
    result(src, A.run(src, 'setWeather', { weather = w }), T(src, 'admin.c.weather_set', { w = w }))
end)

-- /time <hour> [minute]
command('time', function(src, args)
    local h, m = tonumber(args[1]), tonumber(args[2]) or 0
    if not h or h < 0 or h > 23 or m < 0 or m > 59 then
        return reply(src, false, T(src, 'admin.c.usage', { u = '/time <0-23> [0-59]' }))
    end
    local r = A.run(src, 'setTime', { hour = math.floor(h), minute = math.floor(m) })
    result(src, r, T(src, 'admin.c.time_set', { t = ('%02d:%02d'):format(math.floor(h), math.floor(m)) }))
end)

-- /freezetime [on|off] - toggles when no argument; this is the same flag F10 uses
command('freezetime', function(src, args)
    local on = onOff(args[1], worldState().timeFrozen == true)
    result(src, A.run(src, 'freezeTime', { on = on }), T(src, on and 'admin.c.time_frozen' or 'admin.c.time_running'))
end)

command('freezeweather', function(src, args)
    local on = onOff(args[1], worldState().weatherFrozen == true)
    result(src, A.run(src, 'freezeWeather', { on = on }), T(src, on and 'admin.c.weather_frozen' or 'admin.c.weather_running'))
end)

-- /blackout [on|off] - every generator zone off, or back on
command('blackout', function(src, args)
    local cur = false
    if GetResourceState('bs_world') == 'started' then pcall(function() cur = exports.bs_world:Blackout() end) end
    result(src, A.run(src, 'blackout', { on = onOff(args[1], cur) }))
end)

-- /giveitem <id|me> <item> [amount]
command('giveitem', function(src, args)
    local target, item = who(src, args[1]), tostring(args[2] or ''):lower()
    if not target or item == '' then
        return reply(src, false, T(src, 'admin.c.usage', { u = '/giveitem <id|me> <item> [amount]' }))
    end
    if GetResourceState('bs_inventory') ~= 'started' or not exports.bs_inventory:GetItem(item) then
        return reply(src, false, T(src, 'admin.c.unknown_item', { item = item }))
    end
    local amount = math.max(1, math.min(1000, math.floor(tonumber(args[3]) or 1)))
    local r = A.run(src, 'giveitem', { target = target, item = item, amount = amount })
    result(src, r, T(src, 'admin.c.gave_item', { n = amount, item = r.label or item, who = GetPlayerName(target) or target }))
end)

-- /givemoney <id|me> <amount> [cash|bank] (the old order /givemoney <id> <account> <amount> still works)
command('givemoney', function(src, args)
    local target = who(src, args[1])
    local amount, account = tonumber(args[2]), args[3]
    if not amount and tonumber(args[3]) then amount, account = tonumber(args[3]), args[2] end
    account = tostring(account or 'cash'):lower() == 'bank' and 'bank' or 'cash'
    if not target or not amount or amount <= 0 then
        return reply(src, false, T(src, 'admin.c.usage', { u = '/givemoney <id|me> <amount> [cash|bank]' }))
    end
    amount = math.floor(amount)
    result(src, A.run(src, 'givemoney', { target = target, amount = amount, account = account }),
        T(src, 'admin.c.gave_money', { n = amount, acc = account, who = GetPlayerName(target) or target }))
end)

-- /tpc x y [z] - also takes "x, y, z" or vector3(x, y, z). No Z means find ground.
command('tpc', function(src, _, raw)
    if src == 0 then return reply(src, false, T(src, 'admin.u.ingame')) end
    local text = raw:gsub('^%S+%s*', ''):gsub('vector%d%s*%(', ' ')
    local n = {}
    for num in text:gmatch('-?%d+%.?%d*') do n[#n + 1] = tonumber(num) end
    if not n[1] or not n[2] then
        return reply(src, false, T(src, 'admin.c.usage', { u = '/tpc <x> <y> [z]' }))
    end
    local r = A.run(src, 'tpCoords', { x = n[1], y = n[2], z = n[3] })
    result(src, r, T(src, 'admin.c.tpc_done', { c = r.note or '' }))
end)
