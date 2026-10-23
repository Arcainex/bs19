-- BeyondSurvival - bs_zombies: surveyed atlas points. config_atlas.lua is the baseline, this is the staff survey on top.

ZAtlasPoints = { file = 'data/atlas_points.json', overrides = {}, dirty = false }

local RES = GetCurrentResourceName()

local function load()
    local raw = LoadResourceFile(RES, ZAtlasPoints.file)
    if not raw or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' or type(data.points) ~= 'table' then
        print(('^1[BS ATLAS]^7 %s is not valid JSON - ignoring the survey, using config_atlas.lua as is'):format(ZAtlasPoints.file))
        return {}
    end
    return data.points
end

local function indexOf(id)
    for i, p in ipairs(ZAtlas.points or {}) do
        if p.id == id then return i end
    end
    return nil
end

local function apply(id, o)
    ZAtlas.points = ZAtlas.points or {}
    local i = indexOf(id)
    if o.removed then
        if i then
            local p = ZAtlas.points[i]
            p.removed, p.d = true, 0.0
        end
        return
    end
    local x, y = tonumber(o.x), tonumber(o.y)
    if not x or not y then return end
    local entry = i and ZAtlas.points[i] or { id = id, n = {} }
    entry.x, entry.y, entry.z = x, y, tonumber(o.z) or entry.z or 0.0
    entry.d = math.max(0.0, math.min(20.0, tonumber(o.d) or entry.d or 1.0))
    entry.t = type(o.t) == 'string' and o.t or entry.t or 'town'
    entry.removed = nil
    entry.surveyed = true
    if type(o.n) == 'table' then
        local n = {}
        for _, v in ipairs(o.n) do
            v = tonumber(v)
            if v and v >= 1 and v ~= (i or (#ZAtlas.points + 1)) then n[#n + 1] = math.floor(v) end
        end
        entry.n = n
    end
    if not i then ZAtlas.points[#ZAtlas.points + 1] = entry end
end

-- The merge, at load.
do
    local ov = load()
    local n = 0
    for id, o in pairs(ov) do
        if type(id) == 'string' and type(o) == 'table' then
            ZAtlasPoints.overrides[id] = o
            apply(id, o)
            n = n + 1
        end
    end
    if n > 0 then
        print(('^2[BS ATLAS]^7 %d surveyed point(s) merged over config_atlas.lua'):format(n))
    end
end

-- Set or remove one point in memory. Call Save() to keep it.
function ZAtlasPoints.Set(id, o)
    if type(id) ~= 'string' or not id:match('^[%w_%-]+$') or #id > 40 then
        return false, 'id must be letters, numbers, _ or -, 40 max'
    end
    ZAtlasPoints.overrides[id] = o
    apply(id, o)
    ZAtlasPoints.dirty = true
    return true
end

function ZAtlasPoints.Save(by)
    local data = { version = 1, by = by, at = os.date('!%Y-%m-%dT%H:%M:%SZ'), points = ZAtlasPoints.overrides }
    local ok = SaveResourceFile(RES, ZAtlasPoints.file, json.encode(data), -1)
    if ok then ZAtlasPoints.dirty = false end
    return ok and true or false
end

-- Plain copy of the live points for the atlas client (labels).
function ZAtlasPoints.List()
    local out = {}
    for i, p in ipairs(ZAtlas.points or {}) do
        out[#out + 1] = { i = i, id = p.id, x = p.x, y = p.y, z = p.z, d = p.d, t = p.t,
                          n = p.n, removed = p.removed or nil, surveyed = p.surveyed or nil }
    end
    return out
end
