-- bs_zombies - hybrid population helpers shared by client and server (config in config_filler.lua)

ZFiller = ZFiller or {}

local function F() return (Zombies and Zombies.Filler) or {} end

-- Hybrid needs networked walkers to promote into; legacy keeps its own local walkers
function ZFiller.Enabled()
    if F().enabled ~= true then return false end
    local mode = Zombies and Zombies.Mode
    return mode == 'networked' or mode == 'networked_plus'
end

function ZFiller.IsNight(hour)
    hour = tonumber(hour)
    if not hour then return false end
    local n = (Zones and Zones.Scaling and Zones.Scaling.nightHours) or { from = 20, to = 6 }
    if n.from > n.to then return hour >= n.from or hour < n.to end
    return hour >= n.from and hour < n.to
end

function ZFiller.NightFactor(hour)
    if not ZFiller.Enabled() or not ZFiller.IsNight(hour) then return 1.0 end
    return math.max(0.0, tonumber(F().nightMult) or 1.0)
end

-- Networked cap factor against the total number of players online
function ZFiller.PlayerScale(n)
    if not ZFiller.Enabled() then return 1.0 end
    local c = F().playerScale or {}
    local full, down = tonumber(c.fullUpTo) or 16, tonumber(c.downTo) or 48
    local minF = math.max(0.05, math.min(1.0, tonumber(c.minFactor) or 0.6))
    n = tonumber(n) or 0
    if n <= full or down <= full then return 1.0 end
    if n >= down then return minF end
    return 1.0 - (1.0 - minF) * ((n - full) / (down - full))
end

local function inCircle(z, x, y)
    local dx, dy = z.coords.x - x, z.coords.y - y
    return dx * dx + dy * dy <= z.radius * z.radius
end

-- @return kind ('city' | 'north' | 'wilds'), region id or nil
function ZFiller.RegionAt(x, y)
    for _, r in ipairs((Zones and Zones.Filler and Zones.Filler.regions) or {}) do
        if inCircle(r, x, y) then return r.kind or 'wilds', r.id end
    end
    return 'wilds', nil
end

-- Extra filler from hot zones at this spot (the largest one that applies)
function ZFiller.HotExtra(x, y)
    local best, bestId = 0, nil
    for _, h in ipairs((Zones and Zones.Filler and Zones.Filler.hotZones) or {}) do
        if inCircle(h, x, y) and (tonumber(h.extra) or 0) > best then best, bestId = tonumber(h.extra), h.id end
    end
    return best, bestId
end

-- Filler target around a point, before pool limits. Night is applied by the caller's clock.
function ZFiller.TargetAt(x, y, hour)
    local cfg = F()
    local kind, region = ZFiller.RegionAt(x, y)
    local base = tonumber((cfg.targets or {})[kind]) or 0
    local extra, hot = ZFiller.HotExtra(x, y)
    local want = (base + extra) * math.max(0.0, tonumber(cfg.density) or 1.0) * ZFiller.NightFactor(hour)
    want = math.min(math.floor(want + 0.5), math.floor(tonumber(cfg.hardCap) or 70))
    return math.max(0, want), kind, region, hot
end
