-- bs_config shared helper. Include as '@bs_config/shared/apply.lua' after a resource's config files. Patches this resource's config tables with the active bs_config profile on start and on every change, and restores originals when an override is removed.
-- BSConfigGet(path, default) reads a value (e.g. 'Global.xpMultiplier').

if BSConfigHelperLoaded then return end
BSConfigHelperLoaded = true

local RES = GetCurrentResourceName()
local IS_SERVER = IsDuplicityVersion()
local globalVals, ownVals, originals = {}, {}, {}

local function resolve(path)
    local seg = {}
    for s in tostring(path):gmatch('[^%.]+') do seg[#seg + 1] = math.tointeger(tonumber(s)) or s end
    if #seg < 2 then return nil end
    local t = _G
    for i = 1, #seg - 1 do
        if type(t) ~= 'table' then return nil end
        t = t[seg[i]]
    end
    if type(t) ~= 'table' then return nil end
    return t, seg[#seg]
end

local function applyPayload(payload)
    if type(payload) ~= 'table' then return end
    globalVals = type(payload._global) == 'table' and payload._global or {}
    local mine = type(payload[RES]) == 'table' and payload[RES] or {}
    if RES == 'bs_config' then mine = {} end

    -- put back anything that is no longer overridden
    for path, orig in pairs(originals) do
        if mine[path] == nil then
            local t, k = resolve(path)
            if t then t[k] = orig end
            originals[path] = nil
        end
    end
    for path, v in pairs(mine) do
        local t, k = resolve(path)
        -- only touch existing keys with the same type, never invent config
        if t and t[k] ~= nil and type(t[k]) == type(v) then
            if originals[path] == nil then originals[path] = t[k] end
            t[k] = v
        end
    end
    ownVals = mine
    TriggerEvent('bs_config:changed:' .. RES)
end

function BSConfigGet(path, default)
    local v = globalVals[path]
    if v == nil then v = ownVals[path] end
    if v == nil then return default end
    return v
end

if IS_SERVER then
    AddEventHandler('bs_config:apply', applyPayload)
else
    RegisterNetEvent('bs_config:apply', applyPayload)
end

-- first sync: pull whatever bs_config already has
CreateThread(function()
    if RES == 'bs_config' then return end
    for _ = 1, 120 do
        if GetResourceState('bs_config') == 'started' then
            local ok, p = pcall(function() return exports.bs_config:GetPayload() end)
            if ok and type(p) == 'table' then applyPayload(p) return end
        end
        Wait(500)
    end
end)
