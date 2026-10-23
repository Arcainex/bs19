-- bs_zombies - sector state (not the spawner): edges, wanted/actual walker counts, post-kill debt, recent noise

local C = Sectors.Settings

-- All live sector state by 'cx:cy', created lazily (most of an 8km map is ocean).
local State = {}

ZSectors = {}

-- Saved admin overrides by key. Defined here because fresh() calls it.
function ZSectors.SavedFor(_) return {} end

-- Geometry

function ZSectors.KeyFor(x, y)
    local size = C.size or 1000.0
    return ('%d:%d'):format(math.floor(x / size), math.floor(y / size))
end

--- @return number cx, number cy
local function coordsOf(key)
    local cx, cy = key:match('^(-?%d+):(-?%d+)$')
    return tonumber(cx) or 0, tonumber(cy) or 0
end

-- The grid reference an admin reads - "F-11" rather than "5:11"
local ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ'   -- I and O left out: they read as 1 and 0

-- Grid letters skip I and O, so columns past the last letter carry a second one
local function colLabel(col)
    if col < 0 then return '?' end

    local n = #ALPHABET
    if col < n then return ALPHABET:sub(col + 1, col + 1) end

    local hi, lo = math.floor(col / n), col % n
    if hi > n then return '?' end        -- past ZZ, which no map reaches
    return ALPHABET:sub(hi, hi) .. ALPHABET:sub(lo + 1, lo + 1)
end

function ZSectors.LabelFor(key)
    if Sectors.Names[key] then return Sectors.Names[key] end

    local size = C.size or 1000.0
    local origin = C.origin or { x = -4000.0, y = -4000.0 }

    -- Counted from the south-west corner of the playable area, not a hardcoded offset, so it is correct at any sector size
    local cx, cy = coordsOf(key)
    local col = cx - math.floor(origin.x / size)
    local row = cy - math.floor(origin.y / size)

    return ('%s-%d'):format(colLabel(col), row + 1)
end

-- Shortest distance from a point to the sector's nearest edge, 0 if inside
function ZSectors.DistanceTo(key, x, y)
    local size = C.size or 1000.0
    local cx, cy = coordsOf(key)

    local minX, maxX = cx * size, (cx + 1) * size
    local minY, maxY = cy * size, (cy + 1) * size

    local dx = math.max(minX - x, 0.0, x - maxX)
    local dy = math.max(minY - y, 0.0, y - maxY)

    return math.sqrt(dx * dx + dy * dy)
end

--- A random point inside a sector, for the spawner to try.
function ZSectors.RandomPointIn(key)
    local size = C.size or 1000.0
    local cx, cy = coordsOf(key)
    return cx * size + math.random() * size,
           cy * size + math.random() * size
end

-- A spawn point pulled toward recent noise: a loud sector wants its walkers near the noise, not spread over the square
function ZSectors.SpawnPointIn(key, s)
    local rx, ry = ZSectors.RandomPointIn(key)
    if not s or not s.noiseX then return rx, ry end

    local mult = ZSectors.Multiplier(s)
    local top = s.maxMultiplier or C.maxMultiplier or 3.0
    -- 0 when quiet, 1 when as loud as this sector gets.
    local pull = math.max(0.0, math.min(1.0, (mult - 1.0) / math.max(0.001, top - 1.0)))
    if pull <= 0.05 then return rx, ry end

    -- Spread shrinks as the pull grows
    local spread = 500.0 - 380.0 * pull
    local angle = math.random() * math.pi * 2.0
    local dist = (Registry and Registry.SpawnFloor and Registry.SpawnFloor() or 100.0) + math.random() * spread

    local nx = s.noiseX + math.cos(angle) * dist
    local ny = s.noiseY + math.sin(angle) * dist

    -- Blend rather than jump, so even a loud sector keeps some walkers spread out.
    local bx = rx + (nx - rx) * pull
    local by = ry + (ny - ry) * pull

    -- Push the blended point back out
    local floor = (Registry and Registry.SpawnFloor and Registry.SpawnFloor() or 100.0)
    local ddx, ddy = bx - s.noiseX, by - s.noiseY
    local d2 = ddx * ddx + ddy * ddy

    if d2 < (floor * floor) then
        local d = math.sqrt(d2)
        -- Dead on the origin has no bearing to push along; use the one we already generated for nx,ny
        if d < 0.01 then
            ddx, ddy, d = math.cos(angle), math.sin(angle), 1.0
        end
        bx = s.noiseX + (ddx / d) * floor
        by = s.noiseY + (ddy / d) * floor
    end

    return bx, by
end

-- State

local function fresh(key)
    local s = {
        key      = key,
        label    = ZSectors.LabelFor(key),
        enabled  = true,

        -- How many walkers this sector should hold before modifiers.
        target   = C.baseTarget or 28,
        respawnSeconds = C.respawnSeconds or 1800,
        maxMultiplier  = C.maxMultiplier or 3.0,

        -- Respawn debt: a list of os.time() values, one per kill
        debt     = {},

        noise    = 0.0,
        -- Where the noise was, not just how much
        noiseX   = nil,
        noiseY   = nil,
        awake    = false,
        count    = 0,
    }

    -- Config overrides first, then anything an admin has saved - so the panel wins over the file, which is the order an editor expects
    for field, value in pairs(Sectors.Overrides[key] or {}) do s[field] = value end
    for field, value in pairs(ZSectors.SavedFor(key)) do s[field] = value end
    return s
end

function ZSectors.Get(key)
    if not State[key] then State[key] = fresh(key) end
    return State[key]
end

-- Persistence: only admin-edited fields are saved, never live state (noise, debt, count)

local SAVE_FILE = 'sector_overrides.json'
local Saved = {}

local function loadSaved()
    local raw = LoadResourceFile(GetCurrentResourceName(), SAVE_FILE)
    if not raw or raw == '' then return end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print('^1[BeyondSurvival]^7 (sectors) ' .. SAVE_FILE .. ' is not readable - starting from defaults')
        return
    end

    Saved = data
    local n = 0
    for _ in pairs(Saved) do n = n + 1 end
    print(('^2[BeyondSurvival]^7 (sectors) loaded overrides for %d sector(s)'):format(n))
end

local function persist()
    local ok, raw = pcall(json.encode, Saved)
    if ok and raw then
        SaveResourceFile(GetCurrentResourceName(), SAVE_FILE, raw, -1)
    end
end

ZSectors.Persist = persist

-- Replaces the stub declared at the top of the file now that Saved exists.
function ZSectors.SavedFor(key) return Saved[key] or {} end

-- Loaded immediately, not in a thread
loadSaved()

function ZSectors.At(x, y) return ZSectors.Get(ZSectors.KeyFor(x, y)) end

function ZSectors.All() return State end

-- Noise

-- Noise accumulates and decays
function ZSectors.AddNoise(x, y, kind)
    if not C.enabled then return end

    local weight = (C.noiseWeights or {})[kind]
    if not weight then return end

    local s = ZSectors.At(x, y)
    s.noise = math.min((C.noiseFull or 30.0) * 1.5, s.noise + weight)

    -- Remember where, weighted toward the loudest recent source so one footstep does not drag the horde off a firefight
    if not s.noiseX or weight >= 2.0 then
        s.noiseX, s.noiseY = x, y
    else
        s.noiseX = s.noiseX + (x - s.noiseX) * 0.2
        s.noiseY = s.noiseY + (y - s.noiseY) * 0.2
    end

    -- Noise bleeds into immediate neighbours at half weight
    local size = C.size or 1000.0
    local cx, cy = math.floor(x / size), math.floor(y / size)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local n = ZSectors.Get(('%d:%d'):format(cx + dx, cy + dy))
                n.noise = math.min((C.noiseFull or 30.0) * 1.5, n.noise + weight * 0.5)
            end
        end
    end
end

--- 1.0 when quiet, up to the sector's maxMultiplier when as loud as it gets.
function ZSectors.Multiplier(s)
    local full = C.noiseFull or 30.0
    local top = s.maxMultiplier or C.maxMultiplier or 3.0
    local t = math.max(0.0, math.min(1.0, s.noise / math.max(0.001, full)))
    return 1.0 + (top - 1.0) * t
end

-- Kills and debt

--- A walker died here. It owes the sector a slot for the next half hour.
function ZSectors.RegisterKill(x, y)
    if not C.enabled then return end
    local s = ZSectors.At(x, y)
    s.debt[#s.debt + 1] = os.time()
end

-- Number of slots currently suppressed
function ZSectors.DebtNow(s)
    local wait = (s.respawnSeconds or C.respawnSeconds or 1800) / ZSectors.Multiplier(s)
    local now = os.time()

    local kept, live = {}, 0
    for _, at in ipairs(s.debt) do
        if now - at < wait then
            kept[#kept + 1] = at
            live = live + 1
        end
    end

    -- Expired entries are dropped here rather than in a sweep of their own
    s.debt = kept
    return live
end

-- What the spawner asks

-- @param s table sector state @param density number the zone density the registry already
function ZSectors.TargetFor(s, density, night)
    if not s.enabled then return 0 end

    local target = (s.target or C.baseTarget or 28) * (density or 1.0)

    if night then
        target = target * (Zones.Scaling.nightMultiplier or 1.35)
    end

    target = target * ZSectors.Multiplier(s)
    target = math.min(target, C.maxTarget or 90)

    -- Then take away what it still owes for the ones you killed.
    return math.max(0, math.floor(target) - ZSectors.DebtNow(s))
end

-- Upkeep

CreateThread(function()
    while true do
        Wait(60000)

        local decay = C.noiseDecayPerMinute or 6.0
        for _, s in pairs(State) do
            if s.noise > 0.0 then
                s.noise = math.max(0.0, s.noise - decay)
                -- Forget where it was once it has gone quiet, or a sector keeps herding walkers toward a firefight that ended an hour ago
                if s.noise <= 0.0 then s.noiseX, s.noiseY = nil, nil end
            end
        end

        -- Forget sectors that have gone completely cold (not awake, silent, empty, owing nothing)
        for key, s in pairs(State) do
            if not s.awake and s.noise <= 0.0 and s.count <= 0
               and #s.debt == 0 and not Sectors.Overrides[key] then
                State[key] = nil
            end
        end
    end
end)

-- Admin

--- Everything the admin menu needs to draw the sector list.
function ZSectors.Snapshot()
    local out = {}
    for key, s in pairs(State) do
        out[#out + 1] = {
            key    = key,
            label  = s.label,
            enabled = s.enabled,
            target = s.target,
            count  = s.count,
            debt   = ZSectors.DebtNow(s),
            noise  = math.floor(s.noise * 10) / 10,
            mult   = math.floor(ZSectors.Multiplier(s) * 100) / 100,
            awake  = s.awake,
            respawnSeconds = s.respawnSeconds,
        }
    end

    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- Whitelist of fields an admin may change, with bounds
local EDITABLE = {
    enabled        = function(v) return type(v) == 'boolean' and v or false end,
    target         = function(v) return math.max(0, math.min(200, math.floor(tonumber(v) or 0))) end,
    respawnSeconds = function(v) return math.max(0, math.min(21600, math.floor(tonumber(v) or 0))) end,
    maxMultiplier  = function(v) return math.max(1.0, math.min(10.0, tonumber(v) or 1.0)) end,
}

function ZSectors.Set(key, field, value)
    local clamp = EDITABLE[field]
    if not clamp then return false, 'that is not an editable field' end

    local s = ZSectors.Get(key)
    s[field] = clamp(value)

    -- Saved on every change rather than on a timer, so an edit is not lost in a crash
    Saved[key] = Saved[key] or {}
    Saved[key][field] = s[field]
    persist()

    return true
end

--- Empty a sector's debt - "this area is open again", for testing.
function ZSectors.ClearDebt(key)
    local s = ZSectors.Get(key)
    local had = #s.debt
    s.debt = {}
    return had
end

-- Bridge to the admin menu

local function isStaff(src)
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
    return ok and admin == true
end

BSB.RegisterCallback('zombies:sectors:list', function(src)
    if not isStaff(src) then return { ok = false, error = 'not staff' } end

    -- The sector the caller stands in is named separately so the panel can open on it.
    local here = nil
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local at = GetEntityCoords(ped)
        here = ZSectors.KeyFor(at.x, at.y)
        ZSectors.Get(here)          -- make sure it exists so it appears in the list
    end

    return {
        ok = true,
        here = here,
        size = Sectors.Settings.size,
        sectors = ZSectors.Snapshot(),
    }
end)

BSB.RegisterCallback('zombies:sectors:set', function(src, key, field, value)
    if not isStaff(src) then return { ok = false, error = 'not staff' } end
    if type(key) ~= 'string' or type(field) ~= 'string' then
        return { ok = false, error = 'bad request' }
    end

    local ok, err = ZSectors.Set(key, field, value)
    if not ok then return { ok = false, error = err } end

    return { ok = true, sectors = ZSectors.Snapshot() }
end)

BSB.RegisterCallback('zombies:sectors:cleardebt', function(src, key)
    if not isStaff(src) then return { ok = false, error = 'not staff' } end
    if type(key) ~= 'string' then return { ok = false, error = 'bad request' } end

    local cleared = ZSectors.ClearDebt(key)
    return { ok = true, cleared = cleared, sectors = ZSectors.Snapshot() }
end)

--- /sector - what square am I in, and what is it doing?
RegisterCommand('sector', function(src)
    if src ~= 0 and not isStaff(src) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    local key = ZSectors.KeyFor(at.x, at.y)
    local s = ZSectors.Get(key)

    local line = ('^5[BS SECTORS]^7 %s (%s) | %d/%d walkers | debt %d | noise %.1f (x%.2f) | %s')
        :format(s.label, key, s.count, s.target, ZSectors.DebtNow(s),
                s.noise, ZSectors.Multiplier(s), s.enabled and 'on' or 'OFF')

    if src == 0 then print(line) else TriggerClientEvent('chat:addMessage', src, { args = { line } }) end
end, false)


-- Exports for the sector map panel

exports('SectorSnapshot', function() return ZSectors.Snapshot() end)

exports('SectorGrid', function()
    return {
        size           = C.size,
        -- The panel labels cells itself, so it needs the same origin this file counts from.
        origin         = C.origin or { x = -4000.0, y = -4000.0 },
        activateWithin = C.activateWithin,
        baseTarget     = C.baseTarget,
        maxTarget      = C.maxTarget,
        respawnSeconds = C.respawnSeconds,
        maxMultiplier  = C.maxMultiplier,
        nightMultiplier = Zones.Scaling.nightMultiplier,
        safe  = Zones.Safe,
        spawn = Zones.Spawn,
    }
end)

exports('SectorSet', function(key, field, value)
    if type(key) ~= 'string' or type(field) ~= 'string' then return false end
    local ok = ZSectors.Set(key, field, value)
    return ok and true or false
end)

exports('SectorClearDebt', function(key)
    if type(key) ~= 'string' then return 0 end
    return ZSectors.ClearDebt(key)
end)
