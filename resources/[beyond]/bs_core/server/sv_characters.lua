-- bs_core - character slots: listing, creation, deletion and selection. Client input is re-validated here.

BS.Characters = {}
local Ch = BS.Characters

-- source -> bs_users row, populated during the connection handshake.
local sessions = {}

function BS.GetSession(src) return sessions[src] end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function validateName(value)
    local clean = BS.Util.CleanString(value, Config.Character.nameMaxLength)
    if #clean < Config.Character.nameMinLength then return nil, 'name too short' end
    if not BS.Util.IsHumanName(clean) then return nil, 'name contains invalid characters' end
    return clean
end

--- Coerces a submitted appearance table into the configured schema. Anything not
--- described in Config.Appearance is discarded.
local function sanitizeAppearance(input, gender)
    local out = Config.DefaultAppearance(gender)
    if type(input) ~= 'table' then return out end
    for _, field in ipairs(Config.Appearance) do
        local value = tonumber(input[field.key])
        if value then
            if field.type == 'index' then value = math.floor(value) end
            out[field.key] = BS.Util.Clamp(value, field.min, field.max)
        end
    end
    return out
end

local function validateDob(value)
    -- Expected format: YYYY-MM-DD
    local y, m, d = tostring(value or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return nil, 'invalid date of birth' end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil, 'invalid date of birth' end
    -- Precise age, not a year subtraction, so it agrees with the creator's own check.
    local today = os.date('*t')
    local age = today.year - y
    if today.month < m or (today.month == m and today.day < d) then age = age - 1 end

    if age < Config.Character.minAge or age > Config.Character.maxAge then
        return nil, 'age'
    end
    return ('%04d-%02d-%02d'):format(y, m, d)
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function Ch.List(userId)
    local rows = BS.DB.Query([[
        SELECT `id`, `first_name`, `last_name`, `gender`, `dob`, `class`,
               `level`, `xp`, `cash`, `bank`, `appearance`, `metadata`,
               `playtime`, `last_played`
          FROM `bs_characters`
         WHERE `user_id` = ? AND `deleted_at` IS NULL
         ORDER BY `id` ASC
    ]], { userId }) or {}

    for _, row in ipairs(rows) do
        row.appearance = BS.Util.Decode(row.appearance, {})
        local meta = BS.Util.Decode(row.metadata, {})
        -- Only the bits the select screen needs; the rest of metadata stays private.
        row.outfit     = meta.outfit
        row.lastWeapon = meta.lastWeapon
        row.metadata   = nil
        local class = Config.GetClass(row.class)
        row.classLabel = class and class.label or row.class
    end
    return rows
end

function Ch.Get(charId, userId)
    return BS.DB.Single([[
        SELECT * FROM `bs_characters`
         WHERE `id` = ? AND `user_id` = ? AND `deleted_at` IS NULL LIMIT 1
    ]], { charId, userId })
end

--------------------------------------------------------------------------------
-- Mutations
--------------------------------------------------------------------------------

--- Slots for this account: config + bs_vip extra slot (cosmetic convenience).
local function slotsFor(user)
    local n = Config.Session.maxCharacters
    if user and user.identifier and GetResourceState('bs_vip') == 'started' then
        local ok, extra = pcall(function() return exports.bs_vip:ExtraCharacterSlotsFor(user.identifier) end)
        if ok then n = n + math.max(0, math.floor(tonumber(extra) or 0)) end
    end
    return n
end
Ch.SlotsFor = slotsFor

-- Outfit sent by a trusted resource (bs_multichar already checked it against its lists). Only the shape is rebuilt here.
local function shapeOutfit(o)
    if type(o) ~= 'table' then return nil end
    local clean = { components = {}, props = {} }
    for id, v in pairs(o.components or {}) do
        local n = tonumber(id)
        if n and n >= 0 and n <= 11 and n ~= 5 and type(v) == 'table' then
            clean.components[tostring(math.floor(n))] = {
                drawable = math.max(0, math.floor(tonumber(v.drawable) or 0)),
                texture  = math.max(0, math.floor(tonumber(v.texture) or 0)),
                palette  = 2,
            }
        end
    end
    for id, v in pairs(o.props or {}) do
        local n = tonumber(id)
        if n and n >= 0 and n <= 7 and type(v) == 'table' then
            local d = math.floor(tonumber(v.drawable) or -1)
            clean.props[tostring(math.floor(n))] = { drawable = d < -1 and -1 or d, texture = d < 0 and -1 or math.max(0, math.floor(tonumber(v.texture) or 0)) }
        end
    end
    return clean
end

-- trusted comes only from the CreateCharacterFor export (server resources), never from a client payload: outfit, loadout (extra starting items), identity (metadata.identity), spawn, pendingFaction.
--- @return number|nil charId, string|nil error
function Ch.Create(userId, payload, maxSlots, trusted)
    payload = payload or {}
    trusted = type(trusted) == 'table' and trusted or {}

    local count = BS.DB.Scalar(
        'SELECT COUNT(*) FROM `bs_characters` WHERE `user_id` = ? AND `deleted_at` IS NULL', { userId }) or 0
    if count >= (maxSlots or Config.Session.maxCharacters) then
        return nil, 'character slots full'
    end

    local firstName, err = validateName(payload.firstName)
    if not firstName then return nil, err end
    local lastName; lastName, err = validateName(payload.lastName)
    if not lastName then return nil, err end

    local gender = BS.Util.Contains(Config.Character.genders, payload.gender) and payload.gender or 'male'

    local dob; dob, err = validateDob(payload.dob)
    if not dob then return nil, err end

    local _, classId = Config.GetClass(payload.class)
    local class = Config.Classes[classId]

    local appearance = sanitizeAppearance(payload.appearance, gender)
    -- No beard on a female character, whatever the payload says.
    if gender == 'female' then appearance.beardStyle = -1 end

    local spawn = Config.Session.defaultSpawn
    local ts = trusted.spawn
    if type(ts) == 'table' and tonumber(ts.x) and tonumber(ts.y) and tonumber(ts.z) then
        spawn = { x = tonumber(ts.x), y = tonumber(ts.y), z = tonumber(ts.z), h = tonumber(ts.h) or spawn.h }
    end

    local charId = BS.DB.Insert([[
        INSERT INTO `bs_characters`
            (`user_id`, `first_name`, `last_name`, `gender`, `dob`, `class`,
             `level`, `xp`, `skill_points`, `cash`, `bank`,
             `hunger`, `thirst`, `infection`, `pos_x`, `pos_y`, `pos_z`, `heading`,
             `appearance`, `metadata`, `created_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, 100.0, 100.0, 0.0, ?, ?, ?, ?, ?, '{}', NOW())
    ]], {
        userId, firstName, lastName, gender, dob, classId,
        Config.Progression.startingLevel,
        Config.Economy.startingCash, Config.Economy.startingBank,
        spawn.x, spawn.y, spawn.z, spawn.h,
        BS.Util.Encode(appearance),
    })

    if not charId then return nil, 'database error while creating character' end

    -- Seed starting skills. bs_skills owns the gameplay side; the rows are core.
    for skill, level in pairs(class.startingSkills or {}) do
        BS.DB.Insert([[
            INSERT INTO `bs_character_skills` (`character_id`, `skill`, `level`, `xp`)
            VALUES (?, ?, ?, 0)
            ON DUPLICATE KEY UPDATE `level` = VALUES(`level`)
        ]], { charId, skill, level })
    end

    BS.Log.info('characters', ('created character #%d (%s %s / %s)')
        :format(charId, firstName, lastName, classId))
    BS.Emit('character:created', userId, charId, classId)

    -- Starting inventory is queued as metadata; bs_inventory grants it on first spawn so the core never needs to know about items. Unequipped on purpose, see startingItems in config_classes.lua.
    -- Extra starting items from the creator kit merge into the same queue, so each item is granted once (bs_inventory clears it after the first spawn).
    local loadout = {}
    local index = {}
    for _, list in ipairs({ class.startingItems or {}, type(trusted.loadout) == 'table' and trusted.loadout or {} }) do
        for _, e in ipairs(list) do
            if type(e) == 'table' and type(e.item) == 'string' then
                local at = index[e.item]
                if at then
                    loadout[at].amount = (loadout[at].amount or 1) + math.max(1, math.floor(tonumber(e.amount) or 1))
                else
                    loadout[#loadout + 1] = { item = e.item, amount = math.max(1, math.floor(tonumber(e.amount) or 1)) }
                    index[e.item] = #loadout
                end
            end
        end
    end

    local meta = { pendingLoadout = loadout }
    -- Chosen start point (faction safezone): consumed once by the first spawn.
    if type(trusted.spawn) == 'table' and tonumber(trusted.spawn.x) and tonumber(trusted.spawn.y) and tonumber(trusted.spawn.z) then
        meta.firstSpawn = { x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.h }
    end
    local outfit = shapeOutfit(trusted.outfit)
    if outfit then meta.outfit = outfit end
    if type(trusted.identity) == 'table' then meta.identity = trusted.identity end
    if type(trusted.pendingFaction) == 'string' then meta.pendingFaction = trusted.pendingFaction end
    BS.DB.Update('UPDATE `bs_characters` SET `metadata` = ? WHERE `id` = ?',
        { BS.Util.Encode(meta), charId })

    return charId
end

--- Soft delete: the row is kept for audit, hidden from the slot list.
function Ch.Delete(userId, charId)
    local char = Ch.Get(charId, userId)
    if not char then return false, 'character not found' end
    BS.DB.Update('UPDATE `bs_characters` SET `deleted_at` = NOW() WHERE `id` = ?', { charId })
    BS.Log.info('characters', ('deleted character #%d'):format(charId))
    BS.Emit('character:deleted', userId, charId)
    return true
end

--------------------------------------------------------------------------------
-- Selection / spawn
--------------------------------------------------------------------------------

-- Reserve the charId before the first yield. BS.Players is only updated after the async DB read, so two quick select calls for the same charId could both pass the in-use check and create two Player objects for one row.
-- pendingSelect is an in-memory reservation, checked and set before yielding and always cleared once on exit.
local pendingSelect = {}

function Ch.Select(src, charId)
    local user = sessions[src]
    if not user then return false, 'session not ready' end

    if pendingSelect[charId] then return false, 'character already in use' end
    -- Also covers a character that finished loading and is live right now.
    local existing = BS.GetPlayerByCharId(charId)
    if existing and existing.source ~= src then
        return false, 'character already in use'
    end

    pendingSelect[charId] = true
    local ok, result, err = pcall(function()
        local char = Ch.Get(charId, user.id)
        if not char then return false, 'character not found' end

        -- Re-check after the yield: another select for this charId may have completed meanwhile.
        local existingAfter = BS.GetPlayerByCharId(char.id)
        if existingAfter and existingAfter.source ~= src then
            return false, 'character already in use'
        end

        local player = BS.CreatePlayer(src, user, char)

        if not player.position.x then
            local spawn = Config.Session.defaultSpawn
            player:SetPosition(spawn.x, spawn.y, spawn.z, spawn.h)
        end

        BS.DB.Update('UPDATE `bs_characters` SET `last_played` = NOW() WHERE `id` = ?', { char.id })

        TriggerClientEvent(BS.Events.PlayerLoaded, src, player:GetClientPayload())
        BS.Emit('player:loaded', player)
        BS.Emit('character:selected', player, char.id)

        BS.Log.info('characters', ('%s spawned as %s (#%d)')
            :format(GetPlayerName(src), player.name, char.id))
        return true
    end)
    pendingSelect[charId] = nil

    if not ok then
        BS.Log.error('characters', ('character select for #%s errored: %s'):format(tostring(charId), tostring(result)))
        return false, 'internal error'
    end
    return result, err
end

--------------------------------------------------------------------------------
-- Network surface
--------------------------------------------------------------------------------

BSB.RegisterCallback('characters:list', function(src)
    local user = sessions[src]
    if not user then return {} end
    return {
        characters = Ch.List(user.id),
        maxSlots   = slotsFor(user),
        classes    = Config.ClassList(),
        appearance = Config.Appearance,
    }
end)

-- Creation and selection errors are short English codes internally; players see them in their language.
local ERR_KEYS = {
    ['session not ready'] = 'char.session',
    ['name too short'] = 'char.name_short',
    ['name contains invalid characters'] = 'char.name_chars',
    ['invalid date of birth'] = 'char.dob',
    ['character slots full'] = 'char.slots_full',
    ['database error while creating character'] = 'char.db_error',
    ['character not found'] = 'char.not_found',
    ['character already in use'] = 'char.in_use',
    ['internal error'] = 'char.internal',
}
local function charErr(src, err)
    if err == nil then return nil end
    if err == 'age' then
        return Lp(src, 'char.age', { min = Config.Character.minAge, max = Config.Character.maxAge })
    end
    local key = ERR_KEYS[err]
    return key and Lp(src, key) or err
end

BSB.RegisterCallback('characters:create', function(src, payload)
    local user = sessions[src]
    if not user then return { ok = false, error = charErr(src, 'session not ready') } end
    local charId, err = Ch.Create(user.id, payload, slotsFor(user))
    if not charId then return { ok = false, error = charErr(src, err) } end
    return { ok = true, charId = charId, characters = Ch.List(user.id) }
end)

BSB.RegisterCallback('characters:delete', function(src, charId)
    local user = sessions[src]
    if not user then return { ok = false, error = charErr(src, 'session not ready') } end
    local ok, err = Ch.Delete(user.id, tonumber(charId))
    if not ok then return { ok = false, error = charErr(src, err) } end
    return { ok = true, characters = Ch.List(user.id) }
end)

BSB.RegisterCallback('characters:select', function(src, charId)
    local ok, err = Ch.Select(src, tonumber(charId))
    return { ok = ok, error = charErr(src, err) }
end)

--- Called by the connection handshake once the account row is known.
function Ch.BindSession(src, user)
    sessions[src] = user
end

function Ch.ClearSession(src)
    sessions[src] = nil
end

--- The client reports a completed spawn. Modules that need to hand out starting
--- gear (bs_inventory) or attach world state listen for the 'player:spawned' hook.
RegisterNetEvent(BS.Events.CharacterSpawned, function(charId)
    local player = BS.GetPlayer(source)
    if not player or player.charId ~= tonumber(charId) then return end
    player.spawnedAt = BS.Util.Now()
    if player.metadata and player.metadata.firstSpawn then player:SetMeta('firstSpawn', nil) end
    BS.Emit('player:spawned', player)
end)

-- Exports used by bs_multichar. Creation stays here so name/age/class validation lives in one place.

--- Creates a character for a connected player.
--- @return table { ok = boolean, charId? = number, error? = string }
exports('CreateCharacterFor', function(src, payload, trusted)
    local user = sessions[tonumber(src)]
    if not user then return { ok = false, error = charErr(src, 'session not ready') } end

    local charId, err = Ch.Create(user.id, payload, slotsFor(user), trusted)
    if not charId then return { ok = false, error = charErr(src, err) } end
    return { ok = true, charId = charId }
end)

--- Character slots for a connected player, shaped for the select screen.
exports('ListCharacters', function(src)
    local user = sessions[tonumber(src)]
    if not user then return {} end
    return Ch.List(user.id)
end)

--- Writes a starting outfit into a character's metadata.
exports('SetCharacterOutfit', function(charId, outfit)
    charId = tonumber(charId)
    if not charId or type(outfit) ~= 'table' then return false end

    local row = BS.DB.Single('SELECT `metadata` FROM `bs_characters` WHERE `id` = ? LIMIT 1', { charId })
    if not row then return false end

    local meta = BS.Util.Decode(row.metadata, {})
    meta.outfit = outfit
    BS.DB.Update('UPDATE `bs_characters` SET `metadata` = ? WHERE `id` = ?',
        { BS.Util.Encode(meta), charId })

    -- Keep a loaded player's in-memory copy in step with the row.
    local player = BS.GetPlayerByCharId(charId)
    if player then player.metadata.outfit = outfit end

    return true
end)

-- Queues clothing items to be equipped on this character's first spawn (consumed once by bs_inventory's 'pendingEquip' handling, same pattern as pendingLoadout in Ch.Create).
-- Not the same as outfit, which is only a ped appearance snapshot.
-- Nothing calls this by default; kept as a general tool for admin commands or rewards.
exports('SetCharacterPendingEquip', function(charId, itemNames)
    charId = tonumber(charId)
    if not charId or type(itemNames) ~= 'table' then return false end

    local row = BS.DB.Single('SELECT `metadata` FROM `bs_characters` WHERE `id` = ? LIMIT 1', { charId })
    if not row then return false end

    local meta = BS.Util.Decode(row.metadata, {})
    meta.pendingEquip = itemNames
    BS.DB.Update('UPDATE `bs_characters` SET `metadata` = ? WHERE `id` = ?',
        { BS.Util.Encode(meta), charId })

    -- A freshly created bs_multichar character is not loaded yet, so there is no in-memory player to update. The row is enough: the spawn hook reads metadata when the character is selected.

    return true
end)

--------------------------------------------------------------------------------
-- Appearance edit (bs_multichar edit mode, gated by bs_vip). Face/hair only.
--------------------------------------------------------------------------------

exports('AppearanceSchema', function() return Config.Appearance end)

--- Sets the loaded character's appearance (sanitised) and saves it.
--- Non-yielding: the save runs on its own thread.
exports('SetCharacterAppearance', function(src, appearance)
    local player = BS.GetPlayer(tonumber(src))
    if not player then return false end
    player.appearance = sanitizeAppearance(appearance, player.gender)
    player.dirty = true
    CreateThread(function() player:Save(true) end)
    return true, player.appearance
end)
