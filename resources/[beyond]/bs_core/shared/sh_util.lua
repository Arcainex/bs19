-- shared/sh_util.lua - small dependency-free helpers shared by every module.

BS = BS or {}
BS.Util = {}

local U = BS.Util

--- Deep copy of a table (cycle-safe).
function U.DeepCopy(tbl, seen)
    if type(tbl) ~= 'table' then return tbl end
    seen = seen or {}
    if seen[tbl] then return seen[tbl] end
    local out = {}
    seen[tbl] = out
    for k, v in pairs(tbl) do out[U.DeepCopy(k, seen)] = U.DeepCopy(v, seen) end
    return setmetatable(out, getmetatable(tbl))
end

--- Recursive merge of override into a copy of base. Arrays are replaced.
function U.Merge(base, override)
    local out = U.DeepCopy(base)
    for k, v in pairs(override or {}) do
        if type(v) == 'table' and type(out[k]) == 'table' and not v[1] then
            out[k] = U.Merge(out[k], v)
        else
            out[k] = U.DeepCopy(v)
        end
    end
    return out
end

function U.TableLength(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do n = n + 1 end
    return n
end

function U.Contains(tbl, value)
    for _, v in pairs(tbl or {}) do if v == value then return true end end
    return false
end

function U.Keys(tbl)
    local out = {}
    for k in pairs(tbl or {}) do out[#out + 1] = k end
    return out
end

function U.Round(value, places)
    local mult = 10 ^ (places or 0)
    return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
end

function U.Clamp(value, minv, maxv)
    if value < minv then return minv end
    if value > maxv then return maxv end
    return value
end

--- Trims and collapses whitespace, then hard-limits length.
function U.CleanString(str, maxLen)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #str > maxLen then str = str:sub(1, maxLen) end
    return str
end

--- True when str only contains letters, spaces, apostrophes and dashes.
function U.IsHumanName(str)
    return type(str) == 'string' and str:match("^[%a][%a%s'%-]*$") ~= nil
end

--- RFC4122-ish v4 identifier, good enough for entity / session keys.
function U.UUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (template:gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(v)
    end))
end

function U.Dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

--- Weighted random pick: entries are { item = any, weight = number }.
function U.WeightedPick(entries)
    local total = 0
    for _, e in ipairs(entries or {}) do total = total + (e.weight or 0) end
    if total <= 0 then return nil end
    local roll, acc = math.random() * total, 0
    for _, e in ipairs(entries) do
        acc = acc + (e.weight or 0)
        if roll <= acc then return e.item, e end
    end
    return entries[#entries].item
end

--- Safe JSON decode returning fallback on failure.
function U.Decode(str, fallback)
    if type(str) ~= 'string' or str == '' then return fallback end
    local ok, decoded = pcall(json.decode, str)
    if not ok then return fallback end
    return decoded
end

function U.Encode(tbl)
    local ok, encoded = pcall(json.encode, tbl or {})
    return ok and encoded or '{}'
end

-- Reading an entity's model without flooding the console.
-- GET_ENTITY_MODEL (native 9f47b058362c84b5) can raise "exception at address gta-streaming-five.dll" hundreds of times a second with no resource named. Two gotchas:
-- 1. DoesEntityExist alone is not enough: an entity can exist while the streamer cannot resolve its archetype (mid stream-in, or a networked entity whose model has not arrived).
-- 2. pcall catches the fault but does not silence it; the engine logs it before Lua sees it, so a pcall in a per-frame loop still prints forever.
-- So this is the one accessor: it checks, pcalls, and logs which resource asked (at most once per ten seconds). Returns nil on failure, not 0, since 0 is a valid hash.
local modelFailAt, modelFails = 0, 0

-- Per-entity memoization. Some entities (e.g. bs_traders peds: frozen, invincible, not targetable) fault on every call for their whole lifetime, and ALT target scans re-ask hundreds of times a minute. A faulting entity is remembered and not asked again for RECHECK_MS: long enough to stop the flood, short enough that a transient streaming failure recovers. The table cannot grow unbounded because DoesEntityExist turns away dead handles first.
local RECHECK_MS = 15000
local knownFaulty = {}   -- [entity] = gameTimer it can be retried at

function U.ModelOf(entity)
    if not entity or entity == 0 then return nil end
    if not DoesEntityExist(entity) then return nil end
    -- Raycasts can return handles that are not peds/vehicles/objects; GetEntityModel faults on those.
    if IsDuplicityVersion and not IsDuplicityVersion() then
        if not (IsEntityAPed(entity) or IsEntityAVehicle(entity) or IsEntityAnObject(entity)) then
            return nil
        end
    end

    local now = GetGameTimer and GetGameTimer() or 0

    local retryAt = knownFaulty[entity]
    if retryAt and now < retryAt then return nil end

    local ok, hash = pcall(GetEntityModel, entity)
    if ok and hash and hash ~= 0 then
        knownFaulty[entity] = nil
        return hash
    end

    knownFaulty[entity] = now + RECHECK_MS
    modelFails = modelFails + 1

    if now - modelFailAt > 10000 then
        modelFailAt = now
        print(('^3[BeyondSurvival]^7 (%s) GetEntityModel faulted %d time(s) in the last '
            .. '10s - an entity existed but its model could not be read. Harmless here, '
            .. 'but it is this resource doing it.')
            :format(GetCurrentResourceName(), modelFails))
        modelFails = 0
    end

    return nil
end

function U.Now()
    return os.time()
end
