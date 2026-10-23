-- BeyondSurvival - bs_zombies combat feedback options for everyone: health bars over aimed walkers, hit marker sounds and cross

local KVP = 'bs_zombies:fxoptions'
local OLD_KVP = 'bs_vip:options'

local DEFAULTS = {
    zombieHealthBars  = true,
    healthBarLinger   = 5,
    hitMarker         = false,  -- off by default, players turn it on in F7
    hitMarkerVisual   = true,
    hitMarkerHead     = true,
    hitMarkerKill     = true,
    hitMarkerHeadOnly = false,
    -- VIP colours, '' = server palette
    hbHigh = '', hbMid = '', hbLow = '', hmHex = '',
}
local COLOUR_KEYS = { hbHigh = true, hbMid = true, hbLow = true, hmHex = true }

local Options = {}
for k, v in pairs(DEFAULTS) do Options[k] = v end

local function vipColoursAllowed()
    if GetResourceState('bs_vip') ~= 'started' then return false, 0 end
    local ok, yes = pcall(function() return exports.bs_vip:HasPerk('combatColours') end)
    local ok2, level = pcall(function() return exports.bs_vip:TierLevel() end)
    return (ok and yes == true), (ok2 and tonumber(level)) or 0
end

-- Palette and tier colours only (bs_vip decides the list).
local function colourAllowed(hex)
    if hex == '' then return true end
    if type(hex) ~= 'string' or not hex:match('^#%x%x%x%x%x%x$') then return false end
    local ok, list = pcall(function() return exports.bs_vip:AllowedColours() end)
    return ok and type(list) == 'table' and list[hex:lower()] == true
end

local function load()
    local raw = GetResourceKvpString(KVP) or GetResourceKvpString(OLD_KVP)
    if not raw then return end
    local ok, saved = pcall(json.decode, raw)
    if not ok or type(saved) ~= 'table' then return end
    for key, default in pairs(DEFAULTS) do
        if type(saved[key]) == type(default) then Options[key] = saved[key] end
    end
end

local function save()
    local ok, raw = pcall(json.encode, Options)
    if ok and raw then SetResourceKvp(KVP, raw) end
end

local function snapshot()
    local custom = vipColoursAllowed()
    local out = { custom = custom }
    for k, v in pairs(Options) do out[k] = v end
    return out
end

local function broadcast() TriggerEvent('bs:combatfx:options', snapshot()) end

--- @return table { ok, options } or { ok = false, error }
local function setOption(key, value)
    local default = DEFAULTS[key]
    if default == nil then return { ok = false, error = L('zed.unknown_opt') } end
    if type(value) ~= type(default) then return { ok = false, error = L('zed.bad_value') } end

    if COLOUR_KEYS[key] then
        if not vipColoursAllowed() then return { ok = false, error = L('zed.vip_colours') } end
        value = value:lower()
        if not colourAllowed(value) then return { ok = false, error = L('zed.palette') } end
    elseif key == 'healthBarLinger' then
        value = math.max(1, math.min(15, math.floor(value)))
    end

    Options[key] = value
    save()
    broadcast()
    return { ok = true, options = snapshot() }
end

exports('GetFxOptions', snapshot)
exports('SetFxOption', setOption)
Zombies.SetFxOption = setOption

CreateThread(function()
    load()
    for _ = 1, 3 do Wait(2000); broadcast() end
end)

-- VIP status decides whether custom colours apply.
AddEventHandler('bs:vip:changed', function() broadcast() end)
AddEventHandler('bs:hook:player:loaded', function()
    CreateThread(function() Wait(1500) broadcast() end)
end)
