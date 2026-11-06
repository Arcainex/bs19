-- bs_zombies - hybrid population, server half: turns a client's filler walker into a networked walker
-- One request per filler ped (token per client), rate limited, answered with an ack either way.

ZFiller = ZFiller or {}

local function F() return (Zombies and Zombies.Filler) or {} end

-- In-game hour from bs_world's clock, real hour as a fallback
local hourCache, hourAt = nil, -100000
function ZFiller.ServerHour()
    local t = GetGameTimer()
    if hourCache and t - hourAt < 10000 then return hourCache end
    local h
    if GetResourceState('bs_world') == 'started' then
        local ok, v = pcall(function() return exports.bs_world:GetClockHours() end)
        if ok then h = tonumber(v) end
    end
    hourCache, hourAt = h or tonumber(os.date('%H')), t
    return hourCache
end

if not (ZNet and ZNet.enabled) then return end

ZFiller.stats = { promoted = 0, refused = {}, times = {} }

local clients = {}   -- [src] = { tokens = {}, order = {}, times = {} }

local function client(src)
    local c = clients[src]
    if not c then c = { tokens = {}, order = {}, times = {} }; clients[src] = c end
    return c
end

local function prune(list, window)
    local t = GetGameTimer() - window
    local keep = {}
    for _, v in ipairs(list) do if v >= t then keep[#keep + 1] = v end end
    return keep
end

local function refuse(src, c, token, why)
    c.tokens[token] = { refused = why }
    ZFiller.stats.refused[why] = (ZFiller.stats.refused[why] or 0) + 1
    TriggerClientEvent('bs:z:filler:ack', src, token, false, why)
end

-- The filler's exact clothes and props, checked before they are stored on the record (zLook bag)
local PROPS = { [0] = true, [1] = true, [2] = true, [6] = true, [7] = true }
local function cleanLook(look)
    if type(look) ~= 'table' or type(look.c) ~= 'table' then return nil end
    local out = { c = {}, p = {} }
    for i = 1, 12 do
        local e = look.c[i]
        local d, t = type(e) == 'table' and math.tointeger(tonumber(e[1])), type(e) == 'table' and math.tointeger(tonumber(e[2]))
        if not d or not t or d < 0 or d > 255 or t < 0 or t > 255 then return nil end
        out.c[i] = { d, t }
    end
    for i = 1, 5 do
        local e = type(look.p) == 'table' and look.p[i]
        if type(e) == 'table' then
            local prop, d, t = math.tointeger(tonumber(e[1])), math.tointeger(tonumber(e[2])), math.tointeger(tonumber(e[3]))
            if prop and PROPS[prop] and d and t and d >= -1 and d <= 255 and t >= -1 and t <= 255 then
                out.p[#out.p + 1] = { prop, d, t }
            end
        end
    end
    return out
end

local function remember(c, token)
    c.order[#c.order + 1] = token
    while #c.order > 256 do c.tokens[table.remove(c.order, 1)] = nil end
end

RegisterNetEvent('bs:z:filler:promote', function(token, x, y, z, h, model, reason, targetSrc, look)
    local src = source
    token = math.tointeger(tonumber(token))
    if not token then return end
    local c = client(src)

    -- Same filler again (resend after a hitch): answer what we already decided, never spawn twice
    local prior = c.tokens[token]
    if prior then
        if prior.id then TriggerClientEvent('bs:z:filler:ack', src, token, prior.id, prior.net or 0)
        elseif prior.refused then TriggerClientEvent('bs:z:filler:ack', src, token, false, prior.refused) end
        return
    end
    c.tokens[token] = { busy = true }
    remember(c, token)

    if not ZFiller.Enabled() then return refuse(src, c, token, 'off') end

    local cfg = F()
    c.times = prune(c.times, 60000)
    -- a little over the client's own limit, so hits that skip its queue still get through
    if #c.times >= math.floor((tonumber(cfg.maxPerMinute) or 40) * 1.25) then return refuse(src, c, token, 'rate') end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return refuse(src, c, token, 'noPed') end
    if ZStream and ZStream.InGame and not ZStream.InGame(src, ped) then return refuse(src, c, token, 'notInGame') end
    if GetPlayerRoutingBucket(src) ~= 0 then return refuse(src, c, token, 'bucket') end

    x, y, z, h = tonumber(x), tonumber(y), tonumber(z), tonumber(h) or 0.0
    if not (x and y and z) or not ZPolicy.Point(x, y, z) or not ZPolicy.Finite(h) then return refuse(src, c, token, 'coord') end
    local at = GetEntityCoords(ped)
    local maxD = (tonumber(cfg.cleanupDistance) or 180.0) + 20.0
    if (x - at.x) ^ 2 + (y - at.y) ^ 2 > maxD * maxD or math.abs(z - at.z) > 60.0 then
        return refuse(src, c, token, 'far')
    end

    -- One walker per spot: a second request for the same place (another token for the same filler) gets the first walker
    c.recent = c.recent or {}
    local tnow = GetGameTimer()
    for i = #c.recent, 1, -1 do
        local r = c.recent[i]
        if tnow - r.at > 6000 or not Registry.zombies[r.id] then table.remove(c.recent, i)
        elseif (r.x - x) ^ 2 + (r.y - y) ^ 2 <= 2.5 * 2.5 then
            ZFiller.stats.refused.duplicate = (ZFiller.stats.refused.duplicate or 0) + 1
            c.tokens[token] = { id = r.id, net = r.net or 0 }
            TriggerClientEvent('bs:z:filler:ack', src, token, r.id, r.net or 0)
            return
        end
    end

    local headroom = math.floor(tonumber(cfg.capHeadroom) or 12)
    if ZNet.count >= (ZNet.cap or 0) + headroom then return refuse(src, c, token, 'netCap') end
    if ZNet.NearCount(src, 120.0) >= math.floor(tonumber(cfg.serverNearCap) or 46) then
        return refuse(src, c, token, 'nearCap')
    end

    local record, why = Registry.SpawnPromoted(x, y, z, h % 360.0, tostring(model or ''), headroom, cleanLook(look))
    if not record then return refuse(src, c, token, why or 'spawn') end
    local mark = { id = record.id, x = x, y = y, at = GetGameTimer() }
    c.recent[#c.recent + 1] = mark

    -- Who it goes for: whoever woke it (for a noise, the player who made it, if close enough)
    local chase = src
    targetSrc = tonumber(targetSrc)
    if reason == 'noise' and targetSrc and targetSrc > 0 and targetSrc ~= src then
        local other = GetPlayerPed(targetSrc)
        if other and other ~= 0 and #(GetEntityCoords(other) - vector3(x, y, z)) <= 150.0 then chase = targetSrc end
    end
    if ZNetTarget and ZNetTarget.hurt then
        ZNetTarget.hurt[record.id] = ZNetTarget.hurt[record.id] or {}
        ZNetTarget.hurt[record.id][chase] = GetGameTimer()
    end

    local t = GetGameTimer()
    c.times[#c.times + 1] = t
    ZFiller.stats.times[#ZFiller.stats.times + 1] = t
    ZFiller.stats.promoted = ZFiller.stats.promoted + 1

    CreateThread(function()
        local okSpawn = ZNet.SpawnNow(record)
        local net = (okSpawn and record.net) or 0
        mark.net = net
        c.tokens[token] = { id = record.id, net = net }
        TriggerClientEvent('bs:z:filler:ack', src, token, record.id, net)
        if F().debug then
            print(('^5[BS FILLER]^7 src %d promoted filler -> walker %d (%s, ped %s)'):format(src, record.id, tostring(reason), tostring(okSpawn)))
        end
    end)
end)

AddEventHandler('playerDropped', function() clients[source] = nil end)

-- Who may have filler: hybrid on, routing bucket 0, in the world (character screen excluded)
CreateThread(function()
    while true do
        Wait(2000)
        local on = ZFiller.Enabled()
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local ped = GetPlayerPed(src)
            local ok = on and ped and ped ~= 0 and GetPlayerRoutingBucket(src) == 0
                and (not ZStream or not ZStream.InGame or ZStream.InGame(src, ped))
            ok = ok and true or false
            local st = Player(src).state
            if st.zFiller ~= ok then st:set('zFiller', ok, true) end
        end
    end
end)

-- /zfiller: staff diagnostic; the client prints its half (filler count, region target) next to this
RegisterCommand('zfiller', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then return end
    ZFiller.stats.times = prune(ZFiller.stats.times, 60000)
    local n = #GetPlayers()
    local refused = {}
    for k, v in pairs(ZFiller.stats.refused) do refused[#refused + 1] = k .. '=' .. v end
    local info = {
        perMinute = #ZFiller.stats.times,
        players = n,
        scale = ZFiller.PlayerScale(n),
        cap = ZNet.cap, capWhy = ZNet.capWhy,
        near = src ~= 0 and ZNet.NearCount(src, 120.0) or nil,
        refused = table.concat(refused, ' '),
    }
    if src == 0 then
        print(('[BS FILLER] hybrid %s | promotions/min %d (total %d) | players %d scale x%.2f | net %d / cap %d | hour %s | refused %s')
            :format(tostring(ZFiller.Enabled()), info.perMinute, ZFiller.stats.promoted, n, info.scale,
                    ZNet.count, ZNet.cap or 0, tostring(ZFiller.ServerHour()), info.refused))
        return
    end
    TriggerClientEvent('bs:z:filler:diag', src, info)
end, false)
