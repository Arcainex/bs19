-- bs_admin - remembers which staff menu toggles are on across relogs

local Prefs = {}

-- [src] = table of toggle to boolean, as last known
local live = {}

-- Whitelist of toggles a client may store, so a modified client cannot write unbounded keys
local PERSISTED = {
    godmode       = true,
    zombieGodmode = true,
    invisible     = true,
    -- F10 Simple / Advanced view
    advanced      = true,
    -- in-game guard notifications for this admin (default off)
    guardAlerts   = true,

    -- noclip is not persisted: restoring it would drop staff into the world with collision off
}

local function identifierOf(src)
    if GetResourceState('bs_core') ~= 'started' then return nil end
    local ok, identifier = pcall(function()
        return exports.bs_core:PrimaryIdentifier(src)
    end)
    return ok and identifier or nil
end

-- Reading and writing

-- Uses oxmysql directly
local schemaReady = nil

CreateThread(function()
    Wait(4000)      -- after bs_core has had a chance to run its migrations

    exports.oxmysql:single(
        "SELECT COUNT(*) AS n FROM information_schema.tables "
        .. "WHERE table_schema = DATABASE() AND table_name = 'bs_admin_prefs'",
        {},
        function(row)
            schemaReady = (row and tonumber(row.n) or 0) > 0

            if schemaReady then
                print('^2[BS ADMIN]^7 staff toggle persistence ready (bs_admin_prefs).')
            else
                print('^1' .. string.rep('=', 74) .. '^7')
                print('^1[BS ADMIN]^7 bs_admin_prefs IS MISSING - staff toggles will NOT be saved.')
                print('^1[BS ADMIN]^7 Migration 019_admin_prefs.sql has not been applied.')
                print('^1[BS ADMIN]^7 Check it is listed in bs_core/server/sv_migrations.lua -> M.files,')
                print('^1[BS ADMIN]^7 and that the file exists in bs_core/sql/. The runner iterates a')
                print('^1[BS ADMIN]^7 hardcoded list - dropping a .sql in the folder does NOT run it.')
                print('^1' .. string.rep('=', 74) .. '^7')
            end
        end)
end)

local function loadRow(identifier, cb)
    exports.oxmysql:single(
        'SELECT `toggles` FROM `bs_admin_prefs` WHERE `identifier` = ?',
        { identifier },
        function(row)
            if not row or not row.toggles then return cb(nil) end
            local ok, decoded = pcall(json.decode, row.toggles)
            cb((ok and type(decoded) == 'table') and decoded or nil)
        end)
end

local function saveRow(identifier, toggles)
    exports.oxmysql:execute(
        'INSERT INTO `bs_admin_prefs` (`identifier`, `toggles`) VALUES (?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `toggles` = VALUES(`toggles`)',
        { identifier, json.encode(toggles) })
end

-- The client side of it

-- Sent by the client on every toggle change
RegisterNetEvent('bs:admin:prefs:save', function(toggles)
    local src = source
    if type(toggles) ~= 'table' then return end

    -- Staff check on the WRITE as well as the read
    if not Prefs.IsStaff(src) then return end

    local identifier = identifierOf(src)
    if not identifier then return end

    local clean = {}
    for key, allowed in pairs(PERSISTED) do
        if allowed and toggles[key] ~= nil then
            clean[key] = toggles[key] and true or false
        end
    end

    live[src] = clean
    saveRow(identifier, clean)
end)

-- Requested by the client once it has loaded and knows it is staff
RegisterNetEvent('bs:admin:prefs:request', function()
    local src = source
    if not Prefs.IsStaff(src) then return end

    local identifier = identifierOf(src)
    if not identifier then return end

    loadRow(identifier, function(toggles)
        if not toggles then return end

        local clean = {}
        for key, allowed in pairs(PERSISTED) do
            if allowed and toggles[key] ~= nil then
                clean[key] = toggles[key] and true or false
            end
        end

        live[src] = clean
        TriggerClientEvent('bs:admin:prefs:apply', src, clean)
    end)
end)

AddEventHandler('playerDropped', function()
    live[source] = nil
end)


-- Staff check, injected by sv_main.lua (ACE lists live there, so the rule exists in one place).
Prefs.IsStaff = function() return false end

BSAdminPrefs = Prefs

-- true only when this staff member switched Guard alerts on
exports('GuardAlerts', function(src)
    src = tonumber(src)
    return src ~= nil and live[src] ~= nil and live[src].guardAlerts == true
end)


-- /prefsdebug - WHY DID MY TOGGLES NOT COME BACK

-- /prefsdebug checks the five things a toggle needs to survive a relog
RegisterCommand('prefsdebug', function(src)
    if src == 0 then
        print('^3[BS ADMIN]^7 run this in game - it reports YOUR identifier and row.')
        return
    end

    local function tell(line)
        TriggerClientEvent('chat:addMessage', src, {
            args = { '[PREFS]', line }, color = { 200, 118, 58 },
        })
    end

    local staff = Prefs.IsStaff(src)
    local identifier = identifierOf(src)

    tell(('table   : %s'):format(
        schemaReady == nil and 'not checked yet'
        or schemaReady and 'bs_admin_prefs present'
        or 'MISSING - migration 019 was not applied'))

    tell(('you     : staff=%s identifier=%s'):format(
        tostring(staff), identifier or 'NONE (no license - cannot key a row)'))

    tell(('in memory: %s'):format(live[src] and 'yes' or 'nothing reported this session'))

    if not identifier then
        tell('^1with no identifier nothing can be saved or loaded.^7')
        return
    end

    loadRow(identifier, function(toggles)
        if not toggles then
            tell('stored  : NO ROW yet - toggle something and run this again.')
            return
        end

        local parts = {}
        for key, value in pairs(toggles) do
            parts[#parts + 1] = ('%s=%s'):format(key, tostring(value))
        end
        table.sort(parts)
        tell(('stored  : %s'):format(#parts > 0 and table.concat(parts, ' ') or '(empty)'))
    end)
end, false)
