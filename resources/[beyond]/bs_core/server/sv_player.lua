-- bs_core - server Player object, the single source of truth for a logged-in character. Other modules change players only through these methods so replication and persistence stay consistent.

BS.Players = {}          -- [source] = Player
local Player = {}
Player.__index = Player
BS.PlayerClass = Player

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- @param src number
--- @param user table   bs_users row
--- @param char table   bs_characters row
function BS.CreatePlayer(src, user, char)
    local class, classId = Config.GetClass(char.class)

    local self = setmetatable({
        source      = src,
        userId      = user.id,
        identifier  = user.identifier,
        charId      = char.id,
        name        = ('%s %s'):format(char.first_name, char.last_name),
        firstName   = char.first_name,
        lastName    = char.last_name,
        gender      = char.gender,
        dob         = char.dob,
        classId     = classId,
        class       = class,

        level       = char.level or Config.Progression.startingLevel,
        xp          = char.xp or 0,
        skillPoints = char.skill_points or 0,

        accounts    = { cash = char.cash or 0, bank = char.bank or 0 },
        needs       = {
            hunger    = char.hunger or 100.0,
            thirst    = char.thirst or 100.0,
            infection = char.infection or 0.0,
        },
        hudSettings = BS.Util.Decode(char.hud_settings, nil),
        position    = { x = char.pos_x, y = char.pos_y, z = char.pos_z, h = char.heading or 0.0 },
        appearance  = BS.Util.Decode(char.appearance, Config.DefaultAppearance(char.gender)),
        metadata    = BS.Util.Decode(char.metadata, {}),

        loadedAt    = BS.Util.Now(),
        dirty       = false,
    }, Player)

    BS.Players[src] = self
    return self
end

--------------------------------------------------------------------------------
-- Lookup helpers
--------------------------------------------------------------------------------

function BS.GetPlayer(src)          return BS.Players[tonumber(src)] end
function BS.GetPlayerByCharId(id)
    for _, p in pairs(BS.Players) do if p.charId == id then return p end end
end
function BS.GetPlayerByUserId(id)
    for _, p in pairs(BS.Players) do if p.userId == id then return p end end
end
function BS.GetPlayers()            return BS.Players end
function BS.GetPlayerCount()        return BS.Util.TableLength(BS.Players) end

--------------------------------------------------------------------------------
-- Replication
--------------------------------------------------------------------------------

--- Pushes an arbitrary key to this player's client-side mirror.
function Player:Replicate(key, value)
    TriggerClientEvent(BS.Events.PlayerDataSet, self.source, key, value)
end

-- Payload the client receives on spawn. Keep it lean; inventory and skills are sent separately by their own modules.
function Player:GetClientPayload()
    return {
        charId      = self.charId,
        name        = self.name,
        firstName   = self.firstName,
        lastName    = self.lastName,
        gender      = self.gender,
        classId     = self.classId,
        class       = {
            id = self.classId,
            label = self.class.label,
            stats = self.class.stats,
        },
        level       = self.level,
        xp          = self.xp,
        xpToNext    = Config.Progression.xpCurve(self.level),
        skillPoints = self.skillPoints,
        accounts    = self.accounts,
        needs       = self.needs,
        hudSettings = self.hudSettings,
        appearance  = self.appearance,
        metadata    = self.metadata,   -- carries outfit + lastWeapon
        position    = self.position,
    }
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

local function validAccount(account)
    return BS.Util.Contains(Config.Economy.accounts, account)
end

function Player:GetMoney(account)
    return self.accounts[account or 'cash'] or 0
end

function Player:AddMoney(account, amount, reason)
    account = account or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if not validAccount(account) or amount <= 0 then return false end
    self.accounts[account] = self:GetMoney(account) + amount
    self.dirty = true
    self:Replicate('accounts', self.accounts)
    TriggerClientEvent(BS.Events.PlayerMoney, self.source, account, self.accounts[account], amount)
    BS.Emit('player:money', self, account, amount, reason)
    BS.LogTransaction(self, account, amount, reason)
    return true
end

function Player:RemoveMoney(account, amount, reason)
    account = account or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if not validAccount(account) or amount <= 0 then return false end
    if self:GetMoney(account) < amount then return false end
    self.accounts[account] = self:GetMoney(account) - amount
    self.dirty = true
    self:Replicate('accounts', self.accounts)
    TriggerClientEvent(BS.Events.PlayerMoney, self.source, account, self.accounts[account], -amount)
    BS.Emit('player:money', self, account, -amount, reason)
    BS.LogTransaction(self, account, -amount, reason)
    return true
end

function Player:SetMoney(account, amount, reason)
    account = account or 'cash'
    if not validAccount(account) then return false end
    self.accounts[account] = math.max(0, math.floor(tonumber(amount) or 0))
    self.dirty = true
    self:Replicate('accounts', self.accounts)
    BS.LogTransaction(self, account, 0, reason or 'set')
    return true
end

--- Append-only money audit trail.
function BS.LogTransaction(player, account, delta, reason)
    BS.DB.Insert([[
        INSERT INTO `bs_transactions` (`character_id`, `account`, `amount`, `balance`, `reason`)
        VALUES (?, ?, ?, ?, ?)
    ]], { player.charId, account, delta, player:GetMoney(account), reason or 'unspecified' })
end

--------------------------------------------------------------------------------
-- Progression
--------------------------------------------------------------------------------

function Player:GetXPToNext()
    return Config.Progression.xpCurve(self.level)
end

--- Adds XP and resolves any level-ups. Returns the number of levels gained.
function Player:AddXP(amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    -- Faction sanction xp_penalty (bs_faction_bases). Staff grants are exempt.
    if reason ~= 'admin' and reason ~= 'admin menu' and GetResourceState('bs_faction_bases') == 'started' then
        local ok, mult = pcall(function() return exports.bs_faction_bases:XpMultiplier(self.source) end)
        if ok and type(mult) == 'number' and mult < 1 then
            amount = math.floor(amount * math.max(0, mult))
            if amount <= 0 then return 0 end
        end
    end

    -- bs_config XP multiplier (staff grants exempt)
    if reason ~= 'admin' and reason ~= 'admin menu' and BSConfigGet then
        local m = tonumber(BSConfigGet('Global.xpMultiplier', 1.0)) or 1.0
        if m ~= 1.0 then amount = math.floor(amount * math.max(0, m) + 0.5) end
        if amount <= 0 then return 0 end
    end

    self.xp = self.xp + amount
    local gained = 0

    while self.level < Config.Progression.maxLevel do
        local needed = self:GetXPToNext()
        if self.xp < needed then break end
        self.xp = self.xp - needed
        self.level = self.level + 1
        self.skillPoints = self.skillPoints + Config.Progression.skillPointsPerLevel
        gained = gained + 1
    end

    if self.level >= Config.Progression.maxLevel then
        self.level = Config.Progression.maxLevel
        self.xp = math.min(self.xp, self:GetXPToNext())
    end

    self.dirty = true
    TriggerClientEvent(BS.Events.PlayerXP, self.source, self.xp, self:GetXPToNext(), self.level, amount)

    if gained > 0 then
        TriggerClientEvent(BS.Events.PlayerLevelUp, self.source, self.level, self.skillPoints)
        BS.Emit('player:levelUp', self, self.level)
        BS.Log.info('progression', ('%s reached level %d'):format(self.name, self.level))
    end

    BS.Emit('player:xp', self, amount, reason)
    return gained
end

-- Removes banked XP (not yet in a level). Never delevels: if there is not enough banked, the caller should refuse as 'cannot afford'. Use this (e.g. skill respec) instead of touching player.xp directly.
function Player:SpendXP(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    if self.xp < amount then return false end

    self.xp = self.xp - amount
    self.dirty = true
    TriggerClientEvent(BS.Events.PlayerXP, self.source, self.xp, self:GetXPToNext(), self.level, -amount)
    BS.Emit('player:xp', self, -amount, 'spend')
    return true
end

--------------------------------------------------------------------------------
-- Needs
--------------------------------------------------------------------------------

function Player:SetNeeds(hunger, thirst, infection)
    self.needs.hunger    = BS.Util.Clamp(tonumber(hunger) or self.needs.hunger, 0.0, 100.0)
    self.needs.thirst    = BS.Util.Clamp(tonumber(thirst) or self.needs.thirst, 0.0, 100.0)
    self.needs.infection = BS.Util.Clamp(tonumber(infection) or self.needs.infection or 0.0, 0.0, 100.0)
    self.dirty = true
    TriggerClientEvent(BS.Events.PlayerNeeds, self.source, self.needs)
end

--- Stores the player's HUD preferences (layout, XP bar position, opacity).
function Player:SetHudSettings(settings)
    if type(settings) ~= 'table' then return false end
    self.hudSettings = settings
    self.dirty = true
    return true
end

--------------------------------------------------------------------------------
-- Metadata (free-form, persisted as JSON)
--------------------------------------------------------------------------------

function Player:GetMeta(key, fallback)
    if key == nil then return self.metadata end
    local value = self.metadata[key]
    if value == nil then return fallback end
    return value
end

function Player:SetMeta(key, value)
    self.metadata[key] = value
    self.dirty = true
    self:Replicate('metadata', self.metadata)
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Player:SetPosition(x, y, z, h)
    self.position = { x = x, y = y, z = z, h = h or self.position.h or 0.0 }
    self.dirty = true
end

--------------------------------------------------------------------------------
-- Permissions
--------------------------------------------------------------------------------

local function hasAnyAce(src, aces)
    for _, ace in ipairs(aces or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

function Player:IsAdmin()
    return hasAnyAce(self.source, Config.Permissions.adminAces)
        or self:IsSuperAdmin()
end

function Player:IsSuperAdmin()
    return hasAnyAce(self.source, Config.Permissions.superAdminAces)
end

--- 'superadmin' | 'admin' | 'player' - handy for logs and UI badges.
function Player:GetRole()
    if self:IsSuperAdmin() then return 'superadmin' end
    if self:IsAdmin() then return 'admin' end
    return 'player'
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

--- Writes the character row. force skips the dirty check.
function Player:Save(force)
    if not force and not self.dirty then return false end
    local pos = self.position or {}
    BS.DB.Update([[
        UPDATE `bs_characters` SET
            `class` = ?, `level` = ?, `xp` = ?, `skill_points` = ?,
            `cash` = ?, `bank` = ?,
            `hunger` = ?, `thirst` = ?, `infection` = ?,
            `pos_x` = ?, `pos_y` = ?, `pos_z` = ?, `heading` = ?,
            `appearance` = ?, `metadata` = ?, `hud_settings` = ?,
            `playtime` = `playtime` + ?,
            `last_played` = NOW()
        WHERE `id` = ?
    ]], {
        self.classId, self.level, self.xp, self.skillPoints,
        self.accounts.cash, self.accounts.bank,
        self.needs.hunger, self.needs.thirst, self.needs.infection or 0.0,
        pos.x, pos.y, pos.z, pos.h,
        BS.Util.Encode(self.appearance), BS.Util.Encode(self.metadata),
        self.hudSettings and BS.Util.Encode(self.hudSettings) or nil,
        math.max(0, BS.Util.Now() - (self.lastSavedAt or self.loadedAt)),
        self.charId,
    })
    self.lastSavedAt = BS.Util.Now()
    self.dirty = false
    BS.Emit('player:saved', self)
    return true
end

--- Saves and removes the player from the live table.
function BS.UnloadPlayer(src, reason)
    local player = BS.Players[src]
    if not player then return end
    player:Save(true)
    BS.Emit('player:unloaded', player, reason)
    BS.Players[src] = nil
    BS.Log.info('player', ('unloaded %s (%s)'):format(player.name, reason or 'unknown'))
end

-- Account key for a connected source: license2, falling back to license, prefixed - the string bs_users rows are stored under.
-- Exported so other resources key per-account data the same way. Returns nil for a source with no license (possible during connection).
exports('PrimaryIdentifier', function(src)
    src = tonumber(src)
    if not src then return nil end
    local identifier = BS.Identity and BS.Identity.GetPrimary and BS.Identity.GetPrimary(src)
    return identifier
end)

exports('GetPlayer', BS.GetPlayer)
exports('GetPlayers', BS.GetPlayers)
exports('GetPlayerByCharId', BS.GetPlayerByCharId)

-- Skill points
-- bs_skills owns the trees but points live on the character row, so spending happens here. Both calls are all-or-nothing.

--- @return boolean spent
exports('SpendSkillPoints', function(src, amount)
    local player = BS.Players[tonumber(src)]
    if not player then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if (player.skillPoints or 0) < amount then return false end

    player.skillPoints = player.skillPoints - amount
    player.dirty = true
    player:Replicate('skillPoints', player.skillPoints)
    return true
end)

--- Staff and respec use this; it never goes negative.
exports('GrantSkillPoints', function(src, amount)
    local player = BS.Players[tonumber(src)]
    if not player then return false end

    amount = math.floor(tonumber(amount) or 0)
    player.skillPoints = math.max(0, (player.skillPoints or 0) + amount)
    player.dirty = true
    player:Replicate('skillPoints', player.skillPoints)
    return true
end)

exports('GetSkillPoints', function(src)
    local player = BS.Players[tonumber(src)]
    return player and player.skillPoints or 0
end)

-- Plain-data surface
-- Exports return a serialised copy of a table, so methods do not survive (exports.bs_core:GetPlayer(src):AddXP(50) errors in another resource). Everything another resource needs to change a player has a function here taking a source and plain values.

-- Everything a UI needs about a player, flattened: no methods, config lookups or second call.
exports('GetPlayerSummary', function(src)
    local player = BS.Players[tonumber(src)]
    if not player then return nil end

    return {
        charId      = player.charId,
        name        = player.name,
        firstName   = player.firstName,
        lastName    = player.lastName,
        gender      = player.gender,
        classId     = player.classId,
        class       = player.class and player.class.label or player.classId,
        stats       = player.class and player.class.stats or {},
        level       = player.level,
        xp          = player.xp,
        xpToNext    = player:GetXPToNext(),
        maxLevel    = Config.Progression.maxLevel,
        skillPoints = player.skillPoints,
        accounts    = { cash = player.accounts.cash, bank = player.accounts.bank },
        needs       = {
            hunger    = player.needs.hunger,
            thirst    = player.needs.thirst,
            infection = player.needs.infection or 0.0,
        },
        playtime    = (player.playtime or 0) + math.max(0, BS.Util.Now() - (player.loadedAt or BS.Util.Now())),
        role        = player:GetRole(),
        admin       = player:IsAdmin(),
    }
end)

exports('AddXP', function(src, amount, reason)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    player:AddXP(math.floor(tonumber(amount) or 0), reason or 'export')
    return true
end)

-- Returns false (spends nothing) if the player lacks enough banked XP, see Player:SpendXP.
exports('SpendXP', function(src, amount)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    return player:SpendXP(amount)
end)

exports('AddMoney', function(src, account, amount, reason)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    return player:AddMoney(account == 'bank' and 'bank' or 'cash',
        math.floor(tonumber(amount) or 0), reason or 'export') and true or false
end)

exports('RemoveMoney', function(src, account, amount, reason)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    return player:RemoveMoney(account == 'bank' and 'bank' or 'cash',
        math.floor(tonumber(amount) or 0), reason or 'export') and true or false
end)

exports('SetLevel', function(src, level)
    local player = BS.Players[tonumber(src)]
    if not player then return false end

    level = math.max(1, math.min(math.floor(tonumber(level) or 1), Config.Progression.maxLevel))
    local gained = level - player.level

    player.level = level
    player.xp = 0
    if gained > 0 then
        player.skillPoints = player.skillPoints + (gained * Config.Progression.skillPointsPerLevel)
    end
    player.dirty = true

    TriggerClientEvent(BS.Events.PlayerXP, player.source, player.xp, player:GetXPToNext(), player.level, 0)
    TriggerClientEvent(BS.Events.PlayerLevelUp, player.source, player.level, player.skillPoints)
    return true
end)

exports('SetNeedsFor', function(src, hunger, thirst, infection)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    player:SetNeeds(hunger, thirst, infection)
    return true
end)

-- Character metadata, for resources that need to store something per character without their own table (e.g. bs_inventory's starting loadout flag).
exports('GetPlayerMeta', function(src, key, fallback)
    local player = BS.Players[tonumber(src)]
    if not player then return fallback end
    return player:GetMeta(key, fallback)
end)

exports('SetPlayerMeta', function(src, key, value)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    player:SetMeta(key, value)
    return true
end)

exports('SavePlayer', function(src, force)
    local player = BS.Players[tonumber(src)]
    if not player then return false end
    return player:Save(force ~= false) and true or false
end)

-- Staff tool (bs_admin 'Change class'): swaps a live character's class. Only the class and its stats change; starting items/skills are not re-granted. Saved immediately and replicated to the client (cl_player.lua re-applies max health/armour).
exports('SetClass', function(src, classId)
    local player = BS.Players[tonumber(src)]
    if not player then return false, 'player not loaded' end
    if type(classId) ~= 'string' or not Config.Classes[classId] then return false, 'unknown class' end

    player.classId = classId
    player.class   = Config.Classes[classId]
    player.dirty   = true
    player:Save(true)

    local payload = { id = classId, label = player.class.label, stats = player.class.stats }
    player:Replicate('classId', classId)
    player:Replicate('class', payload)
    BS.Emit('player:classChanged', player, classId)
    return true
end)

exports('ClassList', function() return Config.ClassList() end)
