-- Per-player translations. Include as '@bs_core/shared/sh_locale.lua' (shared) and list 'locales/*.lua' in files {}.
-- Each locales/<lang>.lua returns a flat table { key = 'text with {name}' }. Missing keys fall back to en, then to the key.
-- Client: L(key, vars) uses the player's language. Server: L(key, vars) uses the server default, L(src, key, vars) or Lp(src, key, vars) uses that player's.
-- The player's choice lives on the state bag 'bs_lang' (set by bs_core), the server default on GlobalState.bs_defaultLang.

if BSLocale then return end

local RES = GetCurrentResourceName()
local IS_SERVER = IsDuplicityVersion()

BSLocale = {
    Languages = { 'en', 'pt', 'de', 'pl', 'tr', 'es', 'fr', 'it', 'ru' },
    Native = {
        en = 'English', pt = 'Português', de = 'Deutsch', pl = 'Polski', tr = 'Türkçe',
        es = 'Español', fr = 'Français', it = 'Italiano', ru = 'Русский',
    },
}
local valid = {}
for _, l in ipairs(BSLocale.Languages) do valid[l] = true end

local cache, merged = {}, {}

local function loadLang(lang)
    if cache[lang] ~= nil then return cache[lang] end
    local src = LoadResourceFile(RES, ('locales/%s.lua'):format(lang))
    local dict = false
    if src then
        local fn, err = load(src, ('@%s/locales/%s.lua'):format(RES, lang), 't', {})
        if fn then
            local ok, res = pcall(fn)
            if ok and type(res) == 'table' then dict = res end
        else
            print(('^3[%s] locale %s failed to load: %s^7'):format(RES, lang, tostring(err)))
        end
    end
    cache[lang] = dict
    return dict
end

function BSLocale.IsValid(lang) return valid[lang] == true end

function BSLocale.Default()
    local d = GlobalState.bs_defaultLang
    return valid[d] and d or 'en'
end

-- Language of a player (server) or of the local player (client).
function BSLocale.LangOf(src)
    local l
    if IS_SERVER then
        if src and tonumber(src) and tonumber(src) > 0 then l = Player(tonumber(src)).state.bs_lang end
    else
        l = LocalPlayer.state.bs_lang
    end
    return valid[l] and l or BSLocale.Default()
end
function BSLocale.Lang() return BSLocale.LangOf(nil) end

-- Full table for a language with en underneath, for NUI.
function BSLocale.Dict(lang)
    lang = valid[lang] and lang or BSLocale.Lang()
    if merged[lang] then return merged[lang] end
    local out = {}
    for k, v in pairs(loadLang('en') or {}) do out[k] = v end
    if lang ~= 'en' then for k, v in pairs(loadLang(lang) or {}) do out[k] = v end end
    merged[lang] = out
    return out
end

local function fmt(text, vars)
    if type(vars) ~= 'table' then return text end
    return (text:gsub('{([%w_]+)}', function(name)
        local v = vars[name]
        if v == nil then return '{' .. name .. '}' end
        return tostring(v)
    end))
end

function BSLocale.T(lang, key, vars)
    local d = loadLang(lang)
    local text = d and d[key]
    if text == nil and lang ~= 'en' then
        d = loadLang('en'); text = d and d[key]
    end
    if text == nil then return tostring(key) end
    return fmt(text, vars)
end

-- Player-language lookup for messages sent to a given source.
function Lp(src, key, vars) return BSLocale.T(BSLocale.LangOf(src), key, vars) end

function L(a, b, c)
    if IS_SERVER and type(a) == 'number' then return Lp(a, b, c) end
    return BSLocale.T(BSLocale.Lang(), a, b)
end

-- Change listeners: fn(lang). Client only (server code reads per player on demand).
local listeners = {}
function BSLocale.OnChange(fn) listeners[#listeners + 1] = fn end

if not IS_SERVER then
    local hasNui = (GetResourceMetadata(RES, 'ui_page', 0) or '') ~= ''
    local last

    local function pushNui()
        if hasNui then
            local lang = BSLocale.Lang()
            SendNUIMessage({ action = 'bs_i18n', lang = lang, dict = BSLocale.Dict(lang) })
        end
    end

    local function changed()
        local lang = BSLocale.Lang()
        if lang == last then return end
        last = lang
        pushNui()
        for _, fn in ipairs(listeners) do pcall(fn, lang) end
        TriggerEvent('bs_locale:changed:' .. RES, lang)
    end

    AddStateBagChangeHandler('bs_lang', nil, function(bagName)
        if bagName ~= ('player:%d'):format(GetPlayerServerId(PlayerId())) then return end
        SetTimeout(0, changed)
    end)
    AddStateBagChangeHandler('bs_defaultLang', 'global', function() SetTimeout(0, changed) end)

    -- Pages can load before the account language arrives (or the bag lands before this handler exists).
    -- Check for a short while after start and on spawn, so the first real language always reaches the page.
    CreateThread(function()
        for _ = 1, 60 do
            Wait(1000)
            changed()
        end
    end)
    AddEventHandler('bs:hook:player:loaded', function() SetTimeout(500, changed) end)

    if hasNui then
        -- i18n.js asks for its table once the page is up.
        RegisterNUICallback('bs_i18n', function(_, cb)
            local lang = BSLocale.Lang()
            last = lang
            cb({ lang = lang, dict = BSLocale.Dict(lang) })
        end)
    end

    -- Ask bs_core to change the local player's language.
    function BSLocale.Set(lang)
        if valid[lang] then TriggerServerEvent('bs_core:setLanguage', lang) end
    end
end
