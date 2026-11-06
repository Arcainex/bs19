-- Active UI theme pack, shared with every client through GlobalState.bsUiTheme.
-- Choice order: pack picked in F1 (kept in resource KVP), then UI.ThemePack from config, then Legacy (classic).

local PACKS = { dossier = true, classic = true, fieldradio = true, rustbelt = true, quarantine = true, nightops = true }
local rev = 1

local function current()
    local k = GetResourceKvpString('themePack')
    if k and PACKS[k] then return k end
    local v = UI and UI.ThemePack
    return PACKS[v] and v or 'classic'
end

local function publish()
    GlobalState.bsUiTheme = { theme = current(), rev = rev }
end

CreateThread(function()
    -- Old installs stored Dossier as a second default, overriding F1's selected profile.
    if GetResourceKvpInt('themeProfileAuthorityV1')~=1 then
        DeleteResourceKvp('themePack')
        SetResourceKvpInt('themeProfileAuthorityV1',1)
    end
    publish()
end)
AddEventHandler('bs_config:changed:bs_ui', publish)

exports('GetThemePack', current)
exports('ThemePacks', function() return { 'classic', 'dossier', 'fieldradio', 'rustbelt', 'quarantine', 'nightops' } end)

-- Called by bs_config after it has checked the caller is an admin.
exports('SetThemePack', function(pack)
    if not PACKS[pack] then return false end
    SetResourceKvp('themePack', pack)
    rev = rev + 1
    publish()
    return true
end)

-- Same pack, new revision: open pages reload their theme sheet.
exports('RefreshTheme', function()
    rev = rev + 1
    publish()
    return rev
end)
