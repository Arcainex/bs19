-- bs_cinecam - the settings table only. Every other file reads CineState.s, so load this first.

CineState = { s = nil, mayUse = nil }

local KVP = 'bs_cinecam:settings'

local function copyDefaults()
    local out = {}
    for k, v in pairs(Cine.Defaults) do out[k] = v end
    return out
end

-- KVP natives are asymmetric: read with GetResourceKvpString, write with SetResourceKvp (SetResourceKvpString doesn't exist).
local function load()
    local raw = GetResourceKvpString(KVP)
    local out = copyDefaults()

    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            -- Merge instead of replace so older saved blobs get new keys.
            for k, v in pairs(decoded) do
                if Cine.Defaults[k] ~= nil and type(v) == type(Cine.Defaults[k]) then
                    out[k] = v
                end
            end
        end
    end

    return out
end

function CineState.Save()
    local ok, encoded = pcall(json.encode, CineState.s)
    if ok then SetResourceKvp(KVP, encoded) end
end

-- Apply a partial patch. Unknown keys and wrong types are dropped.
function CineState.Apply(patch, save)
    if type(patch) ~= 'table' then return CineState.s end

    for k, v in pairs(patch) do
        local default = Cine.Defaults[k]
        if default ~= nil and type(v) == type(default) then
            CineState.s[k] = v
        end
    end

    -- Clamp the ones that can break the camera outright.
    local s = CineState.s
    s.fov       = math.max(Cine.Defaults.fovMin, math.min(Cine.Defaults.fovMax, s.fov))
    s.timescale = math.max(0.05, math.min(1.0, s.timescale))
    s.speed     = math.max(0.1, math.min(200.0, s.speed))

    for _, key in ipairs({ 'moveSmooth', 'lookSmooth', 'fovSmooth', 'rollSmooth' }) do
        s[key] = math.max(0.0, math.min(3.0, s[key]))
    end

    s.filterStrength = math.max(0.0, math.min(1.0, s.filterStrength or 0.8))

    if save then CineState.Save() end
    return s
end

function CineState.Reset(save)
    CineState.s = copyDefaults()
    if save then CineState.Save() end
    return CineState.s
end

CineState.s = load()
