-- bs_scenes - notes and who may leave them.
-- Client input is treated as hostile: length capped, control characters stripped, kind looked up in config, and the position comes from the server's idea of where the player is, so nobody can write inside a base from across the map.

local cache = {}        -- [id] = row, everything currently in the world
local loaded = false
local lastWrite = {}    -- [src] = timestamp, rate limit

-- Per-character note count is tracked incrementally (O(1)) and kept in sync at load, write and erase, instead of scanning the whole cache on every write.
local countByChar = {}  -- [charId] = number of notes currently up

local function bumpCount(charId, delta)
    if not charId then return end
    charId = tonumber(charId)
    countByChar[charId] = math.max(0, (countByChar[charId] or 0) + delta)
end

--------------------------------------------------------------------------------
-- Cleaning what arrives
--------------------------------------------------------------------------------

--- Strips anything that is not text a human typed, and caps the length.
--- Colour codes (^1, ~r~) are removed rather than escaped: a note that can
--- recolour itself is a note that can hide itself.
local function clean(text)
    if type(text) ~= 'string' then return nil end

    text = text
        :gsub('%c', ' ')            -- control characters, newlines included
        :gsub('%^%d', '')           -- FiveM colour codes
        :gsub('~%a-~', '')          -- GTA text codes
        :gsub('%s+', ' ')
        :gsub('^%s*(.-)%s*$', '%1')

    if text == '' then return nil end

    local max = Scenes.Settings.maxLength or 140
    if #text > max then text = text:sub(1, max) end

    return text
end

local function kindOf(kind)
    return Scenes.Kinds[kind] and kind or 'note'
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

local function load()
    local rows = exports.oxmysql:query_async([[
        SELECT `id`, `character_id`, `author`, `text`, `kind`, `x`, `y`, `z`, `heading`
        FROM `bs_scenes`
        WHERE `expires_at` IS NULL OR `expires_at` > NOW()
    ]]) or {}

    cache = {}
    countByChar = {}
    for _, row in ipairs(rows) do
        cache[row.id] = {
            id = row.id, characterId = row.character_id, author = row.author,
            text = row.text, kind = row.kind,
            x = row.x, y = row.y, z = row.z, heading = row.heading,
        }
        bumpCount(row.character_id, 1)
    end

    loaded = true
    print(('^2[BeyondSurvival]^7 (scenes) %d note(s) still standing'):format(#rows))
end

CreateThread(function()
    Wait(2500)
    load()
end)

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- Everything within `radius` of a point. Plain data only.
BSB.RegisterCallback('scenes:around', function(src, x, y, z, radius)
    if not loaded then return { ok = true, scenes = {} } end
    if type(x) ~= 'number' or type(y) ~= 'number' then return { ok = false } end

    radius = math.min(600.0, math.max(20.0, tonumber(radius) or 300.0))
    local r2 = radius * radius

    local out = {}
    for _, note in pairs(cache) do
        local dx, dy = note.x - x, note.y - y
        if (dx * dx + dy * dy) <= r2 then
            out[#out + 1] = {
                id = note.id, text = note.text, kind = note.kind,
                author = note.author,
                x = note.x, y = note.y, z = note.z, heading = note.heading,
            }
        end

        -- A client is never handed the whole world at once.
        if #out >= 120 then break end
    end

    return { ok = true, scenes = out }
end)

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

BSB.RegisterCallback('scenes:write', function(src, text, kind)
    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false, error = 'no character' } end

    -- One note per few seconds, whatever the client thinks it is doing.
    local now = os.time()
    if lastWrite[src] and (now - lastWrite[src]) < 5 then
        return { ok = false, error = Lp(src, 'sc.slow') }
    end

    text = clean(text)
    if not text then return { ok = false, error = Lp(src, 'sc.nothing') } end

    kind = kindOf(kind)

    -- POSITION COMES FROM HERE, NOT FROM THE MESSAGE.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = 'where are you?' } end

    local at = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- How many has this character already got up?
    local mine = countByChar[tonumber(player.charId)] or 0

    local cap = Scenes.Settings.perCharacter or 8
    if mine >= cap then
        return { ok = false, error = ('You have %d notes out there already.'):format(cap) }
    end

    -- Not on top of another one.
    local spacing = Scenes.Settings.minSpacing or 2.0
    for _, note in pairs(cache) do
        local dx, dy, dz = note.x - at.x, note.y - at.y, note.z - at.z
        if (dx * dx + dy * dy + dz * dz) < (spacing * spacing) then
            return { ok = false, error = Lp(src, 'sc.already') }
        end
    end

    local expires = nil
    local days = Scenes.Settings.lifetimeDays or 0
    if days > 0 then
        expires = os.date('!%Y-%m-%d %H:%M:%S', now + days * 86400)
    end

    local author = ('%s %s'):format(player.firstName or '', player.lastName or '')

    local id = exports.oxmysql:insert_async([[
        INSERT INTO `bs_scenes`
            (`character_id`, `author`, `text`, `kind`, `x`, `y`, `z`, `heading`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { player.charId, author, text, kind, at.x, at.y, at.z, heading, expires })

    if not id then return { ok = false, error = Lp(src, 'sc.no_take') } end

    local note = {
        id = id, characterId = player.charId, author = author,
        text = text, kind = kind,
        x = at.x, y = at.y, z = at.z, heading = heading,
    }

    cache[id] = note
    bumpCount(player.charId, 1)
    lastWrite[src] = now

    -- Everybody near enough gets it now rather than on their next refresh.
    TriggerClientEvent('bs:scenes:added', -1, {
        id = id, text = text, kind = kind, author = author,
        x = at.x, y = at.y, z = at.z, heading = heading,
    })

    return { ok = true, id = id }
end)

--------------------------------------------------------------------------------
-- Removing
--------------------------------------------------------------------------------

--- Your own note, or anybody's if you are staff. Rubbing out somebody else's
--- writing is exactly the kind of thing that needs to be a permission.
BSB.RegisterCallback('scenes:erase', function(src, id)
    id = tonumber(id)
    local note = id and cache[id]
    if not note then return { ok = false, error = 'nothing there' } end

    local player = exports.bs_core:GetPlayer(src)
    local mine = player and note.characterId
        and tonumber(note.characterId) == tonumber(player.charId)

    if not mine and not IsPlayerAceAllowed(src, 'bs.admin') then
        return { ok = false, error = Lp(src, 'sc.other') }
    end

    exports.oxmysql:execute_async('DELETE FROM `bs_scenes` WHERE `id` = ?', { id })
    cache[id] = nil
    bumpCount(note.characterId, -1)

    TriggerClientEvent('bs:scenes:removed', -1, id)
    return { ok = true }
end)

AddEventHandler('playerDropped', function() lastWrite[source] = nil end)

--------------------------------------------------------------------------------
-- Sweeping
--------------------------------------------------------------------------------

--- Expired notes go, in the database and in memory. Runs rarely: a note that
--- lingers an hour past its date is nobody's problem.
CreateThread(function()
    while true do
        Wait(600000)   -- ten minutes

        if loaded then
            exports.oxmysql:execute_async(
                'DELETE FROM `bs_scenes` WHERE `expires_at` IS NOT NULL AND `expires_at` <= NOW()')

            local gone = {}
            for id, _ in pairs(cache) do gone[#gone + 1] = id end

            -- Reload rather than tracking expiry per note in memory: it is ten
            -- minutes apart and the table is small.
            load()

            for _, id in ipairs(gone) do
                if not cache[id] then TriggerClientEvent('bs:scenes:removed', -1, id) end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

RegisterCommand('scenewipe', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.superadmin') then return end

    exports.oxmysql:execute_async('DELETE FROM `bs_scenes`')

    for id in pairs(cache) do TriggerClientEvent('bs:scenes:removed', -1, id) end
    cache = {}

    print('^3[BS SCENES]^7 every note wiped')
end, false)

exports('Count', function()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end)

exports.bs_core:RegisterModule('scenes', { side = 'server', version = '1.0.0', ready = true })
