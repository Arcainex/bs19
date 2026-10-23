-- Zombie difficulty, server side: progression of players near a point, and the per-player factors clients read

local function C() return (Zombies and Zombies.Difficulty) or {} end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

local lvl = {}   -- [src] = { lv, at }

local function levelOf(src)
    local now = GetGameTimer()
    local c = lvl[src]
    if c and now - c.at < 15000 then return c.lv end
    local ok, pl = pcall(function() return exports.bs_core:GetPlayer(src) end)
    local lv = ok and type(pl) == 'table' and tonumber(pl.level) or nil
    lvl[src] = { lv = lv, at = now }
    return lv
end

-- Average progression (0..1) of players within the radius of x,y. nil when progression is off or nobody is near.
function ZDiff.ProgressAt(x, y, radius)
    local P = C().Progression or {}
    if P.enabled ~= true or not x or not y then return nil end
    radius = tonumber(radius) or tonumber(P.radius) or 250.0
    local r2, sum, n = radius * radius, 0.0, 0
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            local dx, dy = c.x - x, c.y - y
            if dx * dx + dy * dy <= r2 then
                local lv = levelOf(src)
                if lv then sum, n = sum + lv, n + 1 end
            end
        end
    end
    if n == 0 then return nil end
    local maxL = math.max(2, tonumber(P.maxLevel) or 60)
    return clamp((sum / n - 1) / (maxL - 1), 0.0, 1.0)
end

-- Health for a new walker at x,y.
function ZDiff.Health(base, x, y)
    base = tonumber(base) or 200
    return math.max(1, math.floor(base * ZDiff.Scale('health', ZDiff.ProgressAt(x, y)) + 0.5))
end

-- Horde / wave size near x,y.
function ZDiff.HordeSize(n, x, y)
    n = tonumber(n) or 0
    return math.max(n > 0 and 1 or 0, math.floor(n * ZDiff.Scale('horde', ZDiff.ProgressAt(x, y)) + 0.5))
end

-- Density factor for the networked caps (players spread out, so the server-wide average is used).
function ZDiff.Density()
    local t
    local P = C().Progression or {}
    if P.enabled == true then
        local sum, n = 0.0, 0
        for _, s in ipairs(GetPlayers()) do
            local lv = levelOf(tonumber(s))
            if lv then sum, n = sum + lv, n + 1 end
        end
        if n > 0 then t = clamp((sum / n - 1) / (math.max(2, tonumber(P.maxLevel) or 60) - 1), 0.0, 1.0) end
    end
    return ZDiff.Scale('density', t)
end

exports('HordeSizeScale', function(n, x, y) return ZDiff.HordeSize(n, x, y) end)

-- Per-player damage and speed factors, pushed as a replicated state bag.
local sent = {}
CreateThread(function()
    while true do
        Wait(5000)
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local c = GetEntityCoords(ped)
                local t = ZDiff.ProgressAt(c.x, c.y)
                local d = math.floor(ZDiff.Scale('damage', t) * 1000 + 0.5) / 1000
                local sp = math.floor(ZDiff.Scale('speed', t) * 1000 + 0.5) / 1000
                local o = sent[src]
                if not o or o.d ~= d or o.s ~= sp then
                    sent[src] = { d = d, s = sp }
                    Player(src).state:set('bsZDiff', { d = d, s = sp }, true)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    sent[src], lvl[src] = nil, nil
end)
