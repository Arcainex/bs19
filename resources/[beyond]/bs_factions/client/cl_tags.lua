-- bs_factions - player tags.
-- In a safe zone every player gets a tag (faction + name + level). Outside: squad mates and faction mates, each behind its own toggle. Never enemies. The server (factions:tags) decides who may be described; this file only positions them for html/tags.html.
-- Never takes focus, never fires bs:ui:opened/closed, and only sends messages while a tag is visible (plus one final clear).

local Cfg = Factions.Tags or {}
local FADE_START = Cfg.fadeStart or 0.5
local MIN_SCALE  = Cfg.minScale or 0.62
local HEAD_UP    = Cfg.headOffset or 0.35
local RMIN, RMAX = Cfg.rangeMin or 10, Cfg.rangeMax or 150
local RDEF       = math.floor(Cfg.range or 50)

-- KVP: 0 = never set = ON; 1 = on; 2 = off. Range: 0 = default.
local function readBool(key) return GetResourceKvpInt(key) ~= 2 end
local function readRange()
    local v = GetResourceKvpInt('bs_tags_range')
    if v <= 0 then return math.floor(tonumber(BSConfigGet and BSConfigGet('Factions.Tags.range', nil)) or Cfg.range or RDEF) end
    return math.max(RMIN, math.min(RMAX, v))
end

local prefs = {
    master  = readBool('bs_tags_master'),
    squad   = readBool('bs_tags_squad'),
    faction = readBool('bs_tags_faction'),
    range   = readRange(),
    self    = GetResourceKvpInt('bs_tags_self') == 1, -- own tag: default OFF
}

-- bs_config changed the default: follow it unless the player picked a range
AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function()
    if GetResourceKvpInt('bs_tags_range') <= 0 then prefs.range = readRange() end
end)
local myEntry = nil    -- own tag data from the server
local mates = {}       -- [serverId] = server entry
local sight = {}       -- [serverId] = true when last LOS check was clear
local shown = false

local function inSafe() return LocalPlayer.state.bsFactionSafeZone == true end
local function anyOn() return prefs.master and (prefs.faction or prefs.squad or prefs.self or inSafe()) end

local function sendClear()
    if shown then
        SendNUIMessage({ action = 'tags', tags = {} })
        shown = false
    end
end

CreateThread(function()
    Wait(1000)
    SendNUIMessage({ action = 'tagsConfig', colours = Cfg.colours or {} })
end)

local function refresh()
    if not anyOn() then mates = {} return end
    local result = BSB.Await('factions:tags', 6000)
    if not result or not result.ok then return end
    local fresh = {}
    for _, m in ipairs(result.mates or {}) do
        if m.src then fresh[m.src] = m end
    end
    mates = fresh
    myEntry = result.me
end

CreateThread(function()
    while true do
        if anyOn() then refresh() end
        if inSafe() then Wait(Cfg.safeRefreshMs or 2000) else Wait(Cfg.refreshMs or 5000) end
    end
end)
RegisterNetEvent('bs:factions:sync', function() if anyOn() then CreateThread(refresh) end end)
RegisterNetEvent('bs:squad:sync', function() if anyOn() then CreateThread(refresh) end end)
AddStateBagChangeHandler('bsFactionSafeZone', nil, function(bagName)
    if bagName == ('player:%d'):format(GetPlayerServerId(PlayerId())) then
        SetTimeout(200, function() if anyOn() then refresh() else mates = {} end end)
    end
end)
AddEventHandler('bs:hook:player:unloaded', function() mates = {}; myEntry = nil; sendClear() end)

local function pedOf(serverId)
    local player = GetPlayerFromServerId(serverId)
    if not player or player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

-- Which look (if any) this entry gets right now.
local function kindOf(m, safeNow)
    if m.isMe then return m.squad and 'squad' or m.faction and 'faction' or 'safe' end
    if prefs.squad and m.squad then return 'squad' end
    if prefs.faction and m.faction then return 'faction' end
    if safeNow and m.safe then return 'safe' end
    return nil
end

CreateThread(function()
    while true do
        if anyOn() and (next(mates) or (prefs.self and myEntry)) then
            local me = PlayerPedId()
            local myPos = GetEntityCoords(me)
            local safeNow = inSafe()
            local fresh = {}
            for sid, m in pairs(mates) do
                if kindOf(m, safeNow) then
                    local ped = pedOf(sid)
                    if ped and #(myPos - GetEntityCoords(ped)) <= prefs.range then
                        local los = HasEntityClearLosToEntity(me, ped, 17)
                        if los == true or los == 1 then fresh[sid] = true end
                    end
                end
            end
            if prefs.self and myEntry then fresh[myEntry.src] = true end
            sight = fresh
            Wait(Cfg.sightMs or 250)
        else
            sight = {}
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if not anyOn() or not next(sight) then
            sendClear()
            Wait(500)
        else
            local me = PlayerPedId()
            local myPos = GetEntityCoords(me)
            local range = prefs.range
            local fadeAt = range * FADE_START
            local safeNow = inSafe()
            local batch = {}
            for sid, clear in pairs(sight) do
                local m = mates[sid]
                if not m and prefs.self and myEntry and sid == myEntry.src then
                    m = myEntry; m.isMe = true
                end
                local ped = clear and m and (m.isMe and PlayerPedId() or pedOf(sid))
                local kind = m and kindOf(m, safeNow)
                if ped and kind then
                    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                    local dist = #(myPos - head)
                    if dist <= range then
                        local onScreen, x, y = GetScreenCoordFromWorldCoord(head.x, head.y, head.z + HEAD_UP)
                        if onScreen then
                            local t = 0.0
                            if dist > fadeAt then t = (dist - fadeAt) / math.max(1.0, range - fadeAt) end
                            local dead = IsPedDeadOrDying(ped, true)
                            local tag = {
                                x = x, y = y,
                                s = 1.0 - (1.0 - MIN_SCALE) * t,
                                a = 1.0 - 0.8 * t * t,
                                id = sid, kind = kind,
                                name = m.name, level = m.level,
                                down = Player(sid).state.bsDowned == true or dead == true or dead == 1,
                            }
                            if kind == 'squad' then
                                tag.group = m.squad.name; tag.rank = m.squad.rank
                            elseif kind == 'faction' then
                                tag.group = m.faction.short or m.faction.name; tag.rank = m.faction.rank
                            elseif m.isMe then
                                tag.group = L('tags.unaffiliated')
                            else
                                local sf = m.safeFaction
                                tag.group = sf and (sf.short or sf.name) or L('tags.unaffiliated')
                                tag.rank = sf and sf.short and sf.name or nil
                            end
                            -- faction tag look (level cosmetics); squad keeps its own colour
                            local st = Player(sid).state.bsFactionStyle
                            if type(st) == 'table' then
                                tag.style = st.style
                                if kind ~= 'squad' then tag.hex = st.hex end
                            end
                            -- VIP personal look (bs_vip sets it server-side) wins over the faction one
                            local vt = Player(sid).state.bsVipTag
                            if type(vt) == 'table' then
                                if type(vt.style) == 'string' then tag.style = vt.style end
                                if type(vt.hex) == 'string' then tag.hex = vt.hex end
                            end
                            batch[#batch + 1] = tag
                        end
                    end
                end
            end
            if #batch > 0 then
                SendNUIMessage({ action = 'tags', tags = batch })
                shown = true
            else
                sendClear()
            end
            Wait(Cfg.frameMs or 0)
        end
    end
end)

--------------------------------------------------------------------------------
-- Settings (bs_menu). Keys: 'bs_tags_master'|'master', 'bs_tags_squad'|'squad',
-- 'bs_tags_faction'|'faction', 'bs_tags_range'|'range', 'bs_tags_self'|'self'.
--------------------------------------------------------------------------------

local function snapshot()
    return {
        master = prefs.master, squad = prefs.squad, faction = prefs.faction, range = prefs.range, self = prefs.self,
        bs_tags_master = prefs.master, bs_tags_squad = prefs.squad,
        bs_tags_faction = prefs.faction, bs_tags_range = prefs.range, bs_tags_self = prefs.self,
    }
end

local function truthy(v) return v == true or v == 1 or v == '1' or v == 'true' end

exports('GetTagPrefs', snapshot)
exports('SetTagPref', function(key, value)
    key = tostring(key or ''):gsub('^bs_tags_', '')
    if key == 'range' then
        local n = math.floor(tonumber(value) or RDEF)
        prefs.range = math.max(RMIN, math.min(RMAX, n))
        SetResourceKvpInt('bs_tags_range', prefs.range)
    elseif key == 'master' or key == 'squad' or key == 'faction' or key == 'self' then
        prefs[key] = truthy(value)
        SetResourceKvpInt('bs_tags_' .. key, prefs[key] and 1 or 2)
    else
        return snapshot()
    end
    if anyOn() then CreateThread(refresh) else mates = {}; myEntry = nil; sight = {}; sendClear() end
    return snapshot()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then shown = true; sendClear() end
end)
