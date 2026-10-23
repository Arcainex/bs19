-- bs_core - global framework config. Every value here is safe to change.

Config = Config or {}

Config.Framework = {
    name        = 'BeyondSurvival',
    version     = '0.1.0',
    locale      = 'en',
    -- trace | debug | info | warn | error | none
    logLevel    = 'info',
    -- Server-side timers (seconds)
    autoSaveInterval    = 300,   -- full player save sweep
    positionSyncInterval = 30,   -- client -> server position heartbeat
}

Config.Database = {
    -- Supported drivers: 'oxmysql'. server/sv_database.lua is a thin layer so another driver can be added without touching modules.
    driver          = 'oxmysql',
    runMigrations   = true,      -- apply sql/*.sql on resource start
    tablePrefix     = 'bs_',     -- informational; migrations use it literally
    slowQueryMs     = 250,       -- log any query slower than this
}

Config.Session = {
    -- Character slots a player may own.
    maxCharacters       = 3,
    -- Freeze and hide the player until a character is selected.
    useMultichar        = true,
    -- Camera position during character select.
    selectCam           = { x = -1043.0, y = -2745.0, z = 21.35, h = 330.0 },
    -- Fallback spawn for a character with no stored position.
    defaultSpawn        = { x = 1855.0, y = 3683.0, z = 34.27, h = 210.0 },

    -- Places a character must never be saved at or respawned into. The character-select stage is a sealed room with nothing to stream. A position inside one of these is refused on save and on spawn (falls back to defaultSpawn), so a bad coordinate cannot repeat.
    forbiddenSpawns     = {
        -- bs_multichar's stage. Keep in step with Multichar.Scene.ped.
        { x = 402.88, y = -996.45, z = -99.0, radius = 40.0 },

    },

    -- Outside this box a coordinate is treated as corrupt.
    worldBounds         = { xy = 8500.0, zMin = -800.0, zMax = 2500.0 },

    -- Force the world to load around the spawn point before releasing the player. Off on purpose (see cl_spawn.lua): NewLoadSceneStart on large [map] ymap extents causes a burst that triggers the "Pool Full, Size == 256" crash. Re-enable once those extents are tightened.
    spawnLoadScene      = false,

    -- Diagnostic: ignore the saved position and always use defaultSpawn. Turn on and log in once; if a crash on spawn stops, the saved coordinates are the trigger and need clearing.
    spawnForceDefault   = false,
    -- Kick the player if the client never reports ready.
    handshakeTimeout    = 60,
}

Config.Economy = {
    startingCash        = 250,
    startingBank        = 0,
    currencySymbol      = '$',
    -- Accounts persisted per character.
    accounts = { 'cash', 'bank' },
}

Config.Progression = {
    startingLevel       = 1,
    maxLevel            = 60,
    -- XP required to go from level n to n+1.
    xpCurve = function(level)
        return math.floor(120 * (level ^ 1.45))
    end,
    -- Skill points granted per level up.
    skillPointsPerLevel = 1,
}

-- Rewards per action. One table for XP, money and skill progress; the HUD XP popups show these.
Config.Rewards = {
    zombie_kill          = { xp = 25,  money = 15, skill = 'combat',   skillXp = 12 },
    zombie_kill_headshot = { xp = 40,  money = 25, skill = 'combat',   skillXp = 20 },
    zombie_kill_brute    = { xp = 160, money = 120, skill = 'combat',  skillXp = 60 },
    horde_cleared        = { xp = 300, money = 250, skill = 'combat',  skillXp = 120 },
    resource_gathered    = { xp = 8,   money = 0,  skill = 'survival', skillXp = 10 },
    container_searched   = { xp = 5,   money = 0,  skill = 'survival', skillXp = 6 },
    -- Hunting: paid when a carcass is skinned, scaled per animal (bs_crafting Crafting.HuntReward).
    animal_skinned       = { xp = 30,  money = 0,  skill = 'survival', skillXp = 25 },
    item_crafted         = { xp = 15,  money = 0,  skill = 'crafting', skillXp = 20 },
    player_revived       = { xp = 60,  money = 0,  skill = 'medical',  skillXp = 40 },
    wound_treated        = { xp = 20,  money = 0,  skill = 'medical',  skillXp = 15 },

    -- Vehicles: keeping a machine alive is a craft, so it pays into crafting rather than survival.
    vehicle_repaired     = { xp = 45,  money = 0,  skill = 'crafting', skillXp = 35 },
    vehicle_scrapped     = { xp = 30,  money = 0,  skill = 'crafting', skillXp = 25 },
    vehicle_hotwired     = { xp = 55,  money = 0,  skill = 'lockpicking', skillXp = 45 },
}

Config.Permissions = {
    -- Aces that make Player:IsAdmin() true (staff tier).
    adminAces      = { 'bs.admin', 'command.zombiemenu' },
    -- Aces that make Player:IsSuperAdmin() true (owner tier). group.superadmin inherits group.admin in server.cfg, so a superadmin also passes IsAdmin().
    superAdminAces = { 'bs.superadmin' },
}

-- Push the configured log level into the logger once config is parsed.
if BS and BS.Log then BS.Log.level = Config.Framework.logLevel end

-- Crash breadcrumbs (client): the last few events are saved to KVP and printed on next start as "[crumbs] last session: ...".
Config.Crumbs = {
    enabled = true,
    keep = 40,         -- entries kept
    saveMs = 2000,     -- KVP write interval (only when something new)
}
