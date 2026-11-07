-- Per-player bodycam settings (KVP). bs_pause reads and writes them through the exports below.

local KVP = 'bs_bodycam_v1'

BodycamPrefs = {
    bcEnabled = false,
    bcFov = 95,
    bcMotion = 70,
    bcShake = 60,
    bcGrade = 35,
    bcFilm = 50,
    bcChroma = true,
    bcStamp = true,
    bcRealisticAim = false,
    bcVehicle = false,
}

local ranges = { bcFov = { 70, 120 }, bcMotion = { 0, 100 }, bcShake = { 0, 100 }, bcGrade = { 0, 100 }, bcFilm = { 0, 100 } }
local flags = { bcEnabled = true, bcChroma = true, bcStamp = true, bcRealisticAim = true, bcVehicle = true }
local listeners = {}

local function set(k, v)
    if flags[k] then
        if type(v) ~= 'boolean' then return false end
    elseif ranges[k] then
        v = tonumber(v)
        if not v or v ~= v then return false end
        v = math.max(ranges[k][1], math.min(ranges[k][2], v))
    else
        return false
    end
    BodycamPrefs[k] = v
    return true
end

do
    local ok, saved = pcall(json.decode, GetResourceKvpString(KVP) or '')
    if ok and type(saved) == 'table' then for k, v in pairs(saved) do set(k, v) end end
end

function BodycamOnChange(fn) listeners[#listeners + 1] = fn end

function BodycamApply(patch)
    if type(patch) ~= 'table' then return false end
    local changed = false
    for k, v in pairs(patch) do
        if set(k, v) then changed = true end
    end
    if changed then
        SetResourceKvp(KVP, json.encode(BodycamPrefs))
        for _, fn in ipairs(listeners) do pcall(fn) end
    end
    return changed
end

function BodycamAllowed() return Bodycam.allowed ~= false end

-- Keys vanish from the menu while the server forbids the bodycam.
exports('GetSettings', function()
    if not BodycamAllowed() then return {} end
    local out = {}
    for k, v in pairs(BodycamPrefs) do
        -- The lens width comes from GTA's own first-person FOV setting now.
        if k ~= 'bcFov' then out[k] = v end
    end
    return out
end)

exports('ApplySettings', function(patch)
    if not BodycamAllowed() then return false end
    return BodycamApply(patch)
end)

-- Menu labels for bs_pause, in the player's language.
exports('PauseStrings', function()
    local out = {}
    for k, v in pairs(BSLocale.Dict(BSLocale.Lang())) do
        if k:sub(1, 4) == 'set.' or k:sub(1, 5) == 'st.d_' then out[k] = v end
    end
    return out
end)

exports('IsActive', function() return BodycamIsActive and BodycamIsActive() or false end)

local function notify(key, kind)
    pcall(function()
        TriggerEvent(exports.bs_core:GetEvents().UiNotify, { type = kind or 'info', message = L(key) })
    end)
end
BodycamNotify = notify

RegisterCommand('bodycam', function()
    if not BodycamAllowed() then notify('bc.disabled', 'error') return end
    BodycamApply({ bcEnabled = not BodycamPrefs.bcEnabled })
    notify(BodycamPrefs.bcEnabled and 'bc.on' or 'bc.off')
end, false)
