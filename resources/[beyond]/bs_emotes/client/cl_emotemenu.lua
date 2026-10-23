-- bs_emotes - dpEmotes-style menu and favourites wheel.
-- Tabs (Emotes / Dances / Walks / Expressions / Favourites), search, play on
-- click, cancel, star to favourite. Everything is open to everyone.
-- Emotes play through EmoteCore (cl_emotes.lua), so the usual cancel rules
-- apply. Walks and expressions are applied here.
-- Every `bs:ui:opened` 'emotes' is matched by one `bs:ui:closed` 'emotes'
-- through the single close().

local Cfg      = Emotes.Menu or {}
local BaseFavLimit = tonumber(Emotes.FavLimit) or 15

-- Base + bs_vip bonus, read live so tier changes apply at once.
local function favLimit()
    local bonus = 0
    if GetResourceState('bs_vip') == 'started' then
        local ok, n = pcall(function() return exports.bs_vip:PerkValue(Emotes.VipFavPerk or 'emoteFavourites', 'bonus', 0) end)
        bonus = ok and (tonumber(n) or 0) or 0
    end
    return BaseFavLimit + math.max(0, math.floor(bonus))
end
local KVP_FAVS = 'bs_emotes:favourites'

local menuOpen = false
local favs     = {}     -- ordered list of ids

local walkIndex, faceIndex = {}, {}
for _, w in ipairs(Emotes.Walks or {}) do walkIndex[w.id] = w end
for _, f in ipairs(Emotes.Expressions or {}) do faceIndex[f.id] = f end

-- Favourites (client KVP, stays on this player's client)

local function known(id)
    return (EmoteCore and EmoteCore.index[id]) or walkIndex[id] or faceIndex[id]
end

local function loadFavs()
    favs = {}
    local raw = GetResourceKvpString(KVP_FAVS)
    if not raw or raw == '' then return end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' then return end
    for _, id in ipairs(list) do
        -- Not trimmed to the live limit: VIP may not have synced yet, and a lapsed VIP
        -- keeps their list but cannot add more.
        if type(id) == 'string' and #favs < (Emotes.FavHardCap or 40) then favs[#favs + 1] = id end
    end
end

local function saveFavs()
    SetResourceKvp(KVP_FAVS, json.encode(favs))
end

local function isFav(id)
    for i, v in ipairs(favs) do if v == id then return i end end
    return nil
end

local function notify(kind, message)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = 3000 })
end

--- @return boolean ok, string|nil err
local function toggleFav(id)
    if type(id) ~= 'string' or not known(id) then return false, L('emo.unknown') end
    local at = isFav(id)
    if at then
        table.remove(favs, at)
    else
        local limit = favLimit()
        if #favs >= limit then
            return false, ('Favourites are full (%d).'):format(limit)
        end
        favs[#favs + 1] = id
    end
    saveFavs()
    return true
end

-- Playing anything the menu shows

local function applyWalk(walk)
    if walk.vip and not (EmoteVipOk and EmoteVipOk()) then return false, L('emo.vip_walk') end
    local ped = PlayerPedId()
    if walk.reset then ResetPedMovementClipset(ped, 0.25); return true end
    RequestAnimSet(walk.clipset)
    local waited = 0
    while not HasAnimSetLoaded(walk.clipset) and waited < 3000 do
        Wait(10); waited = waited + 10
    end
    if not HasAnimSetLoaded(walk.clipset) then return false, 'that walk is not on this build' end
    SetPedMovementClipset(ped, walk.clipset, 0.25)
    return true
end

local function applyFace(face)
    local ped = PlayerPedId()
    if face.reset then ClearFacialIdleAnimOverride(ped); return true end
    SetFacialIdleAnimOverride(ped, face.mood, 0)
    return true
end

-- Must run inside a thread (walk and emote loading wait).
local function playAny(id)
    if EmoteCore and EmoteCore.index[id] then return EmoteCore.play(id) end
    if walkIndex[id] then return applyWalk(walkIndex[id]) end
    if faceIndex[id] then return applyFace(faceIndex[id]) end
    return false, L('emo.unknown')
end

-- Menu

local function payload()
    local function plain(list)
        local out = {}
        for _, v in ipairs(list or {}) do
            out[#out + 1] = { id = v.id, label = v.label, reset = v.reset and true or false, vip = v.vip and true or false }
        end
        return out
    end
    return {
        categories  = exports[GetCurrentResourceName()]:EmoteList(),
        walks       = plain(Emotes.Walks),
        expressions = plain(Emotes.Expressions),
        favourites  = favs,
        favLimit    = favLimit(),
        vipOk       = EmoteVipOk and EmoteVipOk() or false,
        current     = EmoteCore and EmoteCore.current() or nil,
        keys        = { menu = Cfg.key or 'F6', fav = Cfg.favKey or 'COMMA', cancel = 'DELETE' },
    }
end

local function close()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('bs:ui:closed', 'emotes')
end

local function open()
    if menuOpen then return end
    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) then return end

    menuOpen = true
    -- Announce first so anything else open (radial included) closes.
    TriggerEvent('bs:ui:opened', 'emotes')
    SendNUIMessage({ action = 'open', data = payload() })
    SetNuiFocus(true, true)

    -- Watch for death while open. Ends when the menu closes.
    CreateThread(function()
        while menuOpen do
            Wait(250)
            if IsPedDeadOrDying(PlayerPedId(), true) then close() end
        end
    end)
end

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)

RegisterNUICallback('play', function(data, cb)
    local id = data and data.id
    CreateThread(function()
        local ok, err = playAny(id)
        if not ok then notify('warn', err or L('emo.not_now')) end
        cb({ ok = ok and true or false, error = err,
             current = EmoteCore and EmoteCore.current() or nil })
    end)
end)

RegisterNUICallback('cancel', function(_, cb)
    if EmoteCore then EmoteCore.stop() end
    cb({ ok = true })
end)

RegisterNUICallback('favourite', function(data, cb)
    local ok, err = toggleFav(data and data.id)
    if not ok and err then notify('warn', err) end
    cb({ ok = ok, error = err, favourites = favs })
end)

-- Favourites wheel (bs_radial, via BSB.Radial)

local wheelBusy = false

local function openFavWheel()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if wheelBusy then return end
    if IsPedDeadOrDying(PlayerPedId(), true) then return end
    close()

    local items = {}
    for _, id in ipairs(favs) do
        local item = known(id)
        if item then
            items[#items + 1] = { id = id, label = item.label or id,
                                  icon = walkIndex[id] and 'walk' or (faceIndex[id] and 'face' or 'emote') }
        end
    end
    if EmoteCore and EmoteCore.current() then
        items[#items + 1] = { id = '__stop', label = L('emo.stop'), icon = 'close' }
    end
    if #items == 0 then
        return notify('info', L('emo.no_favs', { key = Cfg.key or 'F6' }))
    end

    wheelBusy = true
    CreateThread(function()
        local picked
        if BSB and BSB.Radial then
            picked = BSB.Radial({ title = L('emo.favs'), items = items })
        elseif GetResourceState('bs_radial') == 'started' then
            local ok, res = pcall(function() return exports.bs_radial:Open({ title = L('emo.favs'), items = items }) end)
            picked = ok and res or nil
        end
        wheelBusy = false
        if picked == '__stop' then
            if EmoteCore then EmoteCore.stop() end
        elseif picked then
            local ok, err = playAny(picked)
            if not ok then notify('warn', err or L('emo.not_now')) end
        end
    end)
end

-- Commands, keys, lifecycle

RegisterCommand(Cfg.command or 'emotemenu', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if menuOpen then close() else open() end
end, false)
RegisterKeyMapping(Cfg.command or 'emotemenu', L('emote.key_menu'), 'keyboard', Cfg.key or 'F6')

RegisterCommand(Cfg.favCommand or 'emotefavs', openFavWheel, false)
RegisterKeyMapping(Cfg.favCommand or 'emotefavs', L('emote.key_favs'), 'keyboard', Cfg.favKey or 'COMMA')

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'emotes' then close() end
end)
AddEventHandler('bs:hook:player:unloaded', close)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then close() end
end)

loadFavs()

exports('OpenEmoteMenu', open)
exports('CloseEmoteMenu', close)
exports('GetFavourites', function() return favs end)
