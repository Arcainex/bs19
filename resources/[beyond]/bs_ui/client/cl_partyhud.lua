-- bs_ui - party frames (left edge), Division / WoW style.
-- Data: 'factions:roster' (bs_factions/server/sv_roster.lua), re-asked every ~2 s and on bs:squad:sync / bs:factions:sync. Squad mates first, then the faction, capped at Cfg.maxRows with overflow shown as "+N more".
-- Live data (health, DOWN, OUT OF RANGE, distance) is sampled at ~5 Hz and sent only on change. Health uses the cl_hud scale (GTA 100..max -> 0..100).
-- Toggle: KVP 'bs_partyhud' (0 = unset = ON, 1 = ON, 2 = OFF), exports GetPartyHudPref() / SetPartyHudPref(v). Hidden while a full-screen panel is open.

local Cfg = {
    maxRows    = 8,      -- total frames on screen, squad included
    rosterMs   = 2000,
    liveMs     = 200,
    factionRankOrder = { owner = 1, officer = 2, member = 3 },
    factionRankLabels = { owner = 'LEADER', officer = 'OFFICER', member = 'MEMBER' },
}
if type(UI) == 'table' and type(UI.PartyHud) == 'table' then
    for k, v in pairs(UI.PartyHud) do Cfg[k] = v end
end

local KVP = 'bs_partyhud'
local enabled = GetResourceKvpInt(KVP) ~= 2
local blocking = {}
local rows = {}            -- ordered rows currently on the page
local lastRosterJson = nil
local lastLive = {}        -- [src] = signature string
local shown = nil
local refreshNow = true

local function send(payload) SendNUIMessage(payload) end

local function wantVisible()
    return enabled and next(blocking) == nil and #rows > 0
end

local function syncVisible()
    local v = wantVisible()
    if v == shown then return end
    shown = v
    send({ action = 'partyhud:visible', visible = v })
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------
local function getPref() return enabled and 1 or 2 end
local function setPref(v)
    local on = not (v == false or tonumber(v) == 2)
    enabled = on
    SetResourceKvpInt(KVP, on and 1 or 2)
    refreshNow = true
    syncVisible()
    return getPref()
end
exports('GetPartyHudPref', getPref)
exports('SetPartyHudPref', setPref)

--------------------------------------------------------------------------------
-- Panels
--------------------------------------------------------------------------------
AddEventHandler('bs:ui:opened', function(panel)
    if panel and panel ~= 'chat' then blocking[panel] = true; syncVisible() end
end)
AddEventHandler('bs:ui:closed', function(panel)
    if panel then blocking[panel] = nil else blocking = {} end
    syncVisible()
end)

RegisterNetEvent('bs:squad:sync', function() refreshNow = true end)
RegisterNetEvent('bs:factions:sync', function() refreshNow = true end)

--------------------------------------------------------------------------------
-- Roster
--------------------------------------------------------------------------------
local function buildRows(res)
    local me = GetPlayerServerId(PlayerId())
    local mySquad = res.squadId
    local squad, faction = {}, {}
    for _, m in ipairs(res.members or {}) do
        local src = tonumber(m.src)
        if src and src ~= me then
            local row = {
                src = src,
                name = tostring(m.name or '?'),
                level = tonumber(m.level) or 1,
                down = m.downed == true,
            }
            -- VIP name color on the HUD (bsVipTag.hud), if set
            local vt = Player(src).state.bsVipTag
            if type(vt) == 'table' and type(vt.hud) == 'string' and vt.hud:match('^#%x%x%x%x%x%x$') then
                row.hex = vt.hud
            end
            if mySquad ~= nil and m.squadId ~= nil and m.squadId == mySquad then
                row.kind = 'squad'
                row.tag = string.upper(tostring(m.squadRankLabel or 'SQUAD'))
                row.order = tonumber(m.squadRankId) or 99
                squad[#squad + 1] = row
            else
                row.kind = 'faction'
                local r = m.factionRank or m.rank or 'member'
                row.tag = Cfg.factionRankLabels[r] or string.upper(tostring(r))
                row.order = Cfg.factionRankOrder[r] or 9
                faction[#faction + 1] = row
            end
        end
    end
    local cmp = function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end
    table.sort(squad, cmp); table.sort(faction, cmp)

    local out, more = {}, 0
    local cap = math.max(1, tonumber(Cfg.maxRows) or 8)
    for _, r in ipairs(squad) do out[#out + 1] = r end   -- squad is never cut
    for _, r in ipairs(faction) do
        if #out < cap then out[#out + 1] = r else more = more + 1 end
    end
    return out, more
end

local function applyRoster(res)
    local list, more = {}, 0
    if type(res) == 'table' and res.ok then list, more = buildRows(res) end
    local payload = { action = 'partyhud:roster', rows = list, more = more }
    local j = json.encode(payload)
    rows = list
    if j ~= lastRosterJson then
        lastRosterJson = j
        lastLive = {}          -- page rebuilt its rows; resend live state
        send(payload)
    end
    syncVisible()
end

CreateThread(function()
    local nextAt = 0
    while true do
        local now = GetGameTimer()
        if enabled and (refreshNow or now >= nextAt) then
            refreshNow = false
            nextAt = now + Cfg.rosterMs
            local ok, res = pcall(BSB.Await, 'factions:roster', 5000)
            applyRoster(ok and res or nil)
        elseif not enabled and #rows > 0 then
            applyRoster(nil)
        end
        Wait(250)
    end
end)

--------------------------------------------------------------------------------
-- Live state (~5 Hz, changes only)
--------------------------------------------------------------------------------
local function sample(row, myPos)
    local st = Player(row.src).state
    local down = (st and st.bsDowned == true) or false
    local pid = GetPlayerFromServerId(row.src)
    if pid == -1 or not NetworkIsPlayerActive(pid) then
        return { src = row.src, oor = true, down = down }
    end
    local ped = GetPlayerPed(pid)
    if ped == 0 or not DoesEntityExist(ped) then
        return { src = row.src, oor = true, down = down }
    end
    local maxH = math.max(101, GetEntityMaxHealth(ped))
    local hp = math.floor(math.max(0, GetEntityHealth(ped) - 100) / (maxH - 100) * 100 + 0.5)
    if IsEntityDead(ped) then hp = 0 end
    local d = #(GetEntityCoords(ped) - myPos)
    return { src = row.src, oor = false, down = down, hp = math.min(100, hp), dist = math.floor(d + 0.5) }
end

CreateThread(function()
    while true do
        if shown then
            local myPos = GetEntityCoords(PlayerPedId())
            local changed = {}
            for _, row in ipairs(rows) do
                local s = sample(row, myPos)
                local sig = (s.oor and 'o' or 'i') .. (s.down and 'd' or '-') .. tostring(s.hp) .. ':' .. tostring(s.dist)
                if lastLive[row.src] ~= sig then
                    lastLive[row.src] = sig
                    changed[#changed + 1] = s
                end
            end
            if #changed > 0 then send({ action = 'partyhud:live', list = changed }) end
            Wait(Cfg.liveMs)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then send({ action = 'partyhud:visible', visible = false }) end
end)
