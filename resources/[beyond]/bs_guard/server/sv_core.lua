-- bs_guard - the one place a detection goes through: Flag()

GuardCore = {}
local G = GuardCore

local recent = {}            -- ring of the last detections (newest last)
local RING = 300
local lastFlag = {}          -- [src][kind] = { at, count }
local allow = {}             -- [src][what] = until (GetGameTimer ms)
local staffCache = {}        -- [src] = { at, value }
G.joinedAt = {}              -- [src] = GetGameTimer at join / spawn

local function now() return GetGameTimer() end

local function dbg(...)
    if Guard.Settings.debug then print(('^5[BS GUARD]^7 ' .. string.format(...))) end
end
G.dbg = dbg

-- staff / whitelist

local function identifiers(src)
    local out = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then out[#out + 1] = id end
    end
    return out
end

function G.license(src)
    return GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license') or nil
end

function G.isStaff(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    for _, ace in ipairs(Guard.Settings.staffAces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    if GetResourceState('bs_admin') == 'started' then
        local ok, r = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and r then return true end
    end
    return false
end

function G.isExempt(src)
    if not Guard.Settings.staffExempt then
        -- whitelist still applies
    else
        local c = staffCache[src]
        if not c or now() - c.at > 30000 then
            c = { at = now(), value = G.isStaff(src) }
            staffCache[src] = c
        end
        if c.value then return true end
    end
    local wl = Guard.Settings.whitelist or {}
    if #wl > 0 then
        for _, id in ipairs(identifiers(src)) do
            for _, w in ipairs(wl) do if id == w then return true end end
        end
    end
    return false
end

-- legit-teleport allowances

function G.Allow(src, what, ms)
    src = tonumber(src)
    if not src then return false end
    what = tostring(what or 'teleport')
    ms = tonumber(ms) or 10000
    allow[src] = allow[src] or {}
    local untilAt = now() + math.min(ms, 600000)
    if (allow[src][what] or 0) < untilAt then allow[src][what] = untilAt end
    if G.onAllow then G.onAllow(src, what) end
    return true
end

function G.IsAllowed(src, what)
    local a = allow[src]
    return a ~= nil and (a[what or 'teleport'] or 0) > now()
end

function G.inGrace(src)
    local j = G.joinedAt[src]
    return j ~= nil and now() - j < (Guard.Settings.joinGraceMs or 20000)
end

exports('Allow', function(src, what, ms) return G.Allow(src, what, ms) end)
exports('IsAllowed', function(src, what) return G.IsAllowed(tonumber(src), what) end)
-- server-side event for resources that prefer not to depend on the export
AddEventHandler('bs_guard:allow', function(src, what, ms) G.Allow(src, what, ms) end)

-- database

local CREATE = [[
CREATE TABLE IF NOT EXISTS `bs_guard_log` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `src` INT NULL,
    `license` VARCHAR(64) NULL,
    `char_id` INT NULL,
    `name` VARCHAR(64) NULL,
    `kind` VARCHAR(32) NOT NULL,
    `confidence` TINYINT UNSIGNED NOT NULL DEFAULT 50,
    `details` VARCHAR(512) NULL,
    `x` FLOAT NULL,
    `y` FLOAT NULL,
    `z` FLOAT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_bs_guard_log_at` (`created_at`),
    KEY `idx_bs_guard_log_license` (`license`),
    KEY `idx_bs_guard_log_kind` (`kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

G.dbReady = false
CreateThread(function()
    local ok = pcall(function() MySQL.query.await(CREATE) end)
    G.dbReady = ok
    if not ok then print('^1[BS GUARD]^7 could not create bs_guard_log - detections stay in memory only') return end
    local days = tonumber(Guard.Alerts.keepDays) or 0
    if days > 0 then
        pcall(function()
            MySQL.update.await('DELETE FROM `bs_guard_log` WHERE `created_at` < (NOW() - INTERVAL ? DAY)', { days })
        end)
    end
end)

-- Flag

local function charInfo(src)
    if GetResourceState('bs_core') ~= 'started' then return nil end
    local ok, p = pcall(function() return exports.bs_core:GetPlayer(src) end)
    if ok and type(p) == 'table' then return p end
    return nil
end
G.charInfo = charInfo

-- per-admin "Guard alerts" switch lives in bs_admin (default off)
function G.alertsOn(src)
    if GetResourceState('bs_admin') ~= 'started' then return false end
    local ok, r = pcall(function() return exports.bs_admin:GuardAlerts(src) end)
    return ok and r == true
end

local function alertStaff(entry)
    if entry.confidence < (Guard.Alerts.minConfidence or 0) then return end
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if s and G.isStaff(s) then
            if G.alertsOn(s) then
            local kk = 'guard.kind.' .. tostring(entry.kind)
            local kind = Lp(s, kk)
            if kind == kk then kind = entry.kind end
            local text = ('%s [%d] - %s (%d%%): %s'):format(entry.name or '?', entry.src or 0, kind,
                entry.confidence, entry.details or '')
            TriggerClientEvent('bs:ui:notify', s, {
                type = entry.confidence >= 80 and 'error' or 'warn', title = 'GUARD',
                message = text, duration = Guard.Alerts.toastMs or 9000,
            })
            end
            TriggerClientEvent('bs_guard:detection', s, entry)
        end
    end
end

-- Record a detection. kind: short id ('teleport', 'speed', 'godmode', ...). confidence 0-100.
function G.Flag(src, kind, details, confidence)
    if not Guard.Settings.enabled then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    if G.isExempt(src) then return false end
    kind = tostring(kind or 'unknown'):sub(1, 32)
    confidence = math.max(0, math.min(100, math.floor(tonumber(confidence) or 50)))

    lastFlag[src] = lastFlag[src] or {}
    local lf = lastFlag[src][kind]
    local t = now()
    if lf and t - lf.at < (Guard.Alerts.cooldownMs or 30000) then
        lf.count = lf.count + 1
        return false
    end
    local suppressed = lf and lf.count or 0
    lastFlag[src][kind] = { at = t, count = 0 }

    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local p = charInfo(src)
    details = tostring(details or '')
    if suppressed > 0 then details = details .. (' (+%d repeats)'):format(suppressed) end
    local entry = {
        src = src, license = G.license(src), charId = p and p.charId or nil,
        name = (GetPlayerName(src) or '?'):sub(1, 64), charName = p and p.name or nil,
        kind = kind, confidence = confidence, details = details:sub(1, 512),
        x = c.x, y = c.y, z = c.z, time = os.time(),
    }

    recent[#recent + 1] = entry
    if #recent > RING then table.remove(recent, 1) end

    print(('^3[BS GUARD]^7 %s [%d] %s (%d%%) %s'):format(entry.name, src, kind, confidence, entry.details))

    if G.dbReady then
        MySQL.insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
            { src, entry.license, entry.charId, entry.name, kind, confidence, entry.details, c.x, c.y, c.z },
            function(id) entry.id = id end)
    end
    alertStaff(entry)
    TriggerEvent('bs_guard:flagged', entry)
    return true
end

function G.Recent() return recent end

exports('Flag', function(src, kind, details, confidence) return G.Flag(src, kind, details, confidence) end)
exports('IsExempt', function(src) return G.isExempt(tonumber(src)) end)
AddEventHandler('bs_guard:flag', function(src, kind, details, confidence) G.Flag(src, kind, details, confidence) end)

-- lifecycle

AddEventHandler('playerJoining', function() G.joinedAt[source] = now() end)
-- the client announcing its character spawn (bs_core owns the net event)
RegisterNetEvent('bs:characters:spawned', function()
    local s = source
    G.joinedAt[s] = now()
    G.Allow(s, 'teleport', Guard.Settings.joinGraceMs or 20000)
end)
RegisterNetEvent('bs:characters:logout', function() G.Allow(source, 'teleport', 60000) end)

AddEventHandler('playerDropped', function()
    local s = source
    lastFlag[s], allow[s], staffCache[s], G.joinedAt[s] = nil, nil, nil, nil
    if G.onDrop then for _, fn in ipairs(G.onDrop) do pcall(fn, s) end end
end)
G.onDrop = {}

-- resource restart: everyone online gets a grace period
CreateThread(function()
    for _, id in ipairs(GetPlayers()) do G.joinedAt[tonumber(id)] = now() end
end)
