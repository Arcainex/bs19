-- BeyondSurvival - applies sql/*.sql in filename order, once each, tracked in bs_migrations.
-- a new 0XX_description.sql must ALSO be added to the hardcoded list below, otherwise it is silently never run.

BS.Migrations = {}
local M = BS.Migrations

-- Registered in load order. Keep the numeric prefixes.
M.files = {
    '001_core_schema.sql',
    '002_progression.sql',
    '003_inventory_economy.sql',
    '004_zombies_world.sql',
    '005_infection.sql',
    '006_weapons.sql',
    '007_vehicles.sql',
    '008_scenes.sql',
    '009_factions.sql',
    '010_vip.sql',
    '011_vehicle_tyres.sql',
    '012_weapon_ammo.sql',
    '013_vehicle_stripped.sql',
    '014_vehicle_mods.sql',
    '015_stashes.sql',
    '016_faction_registry.sql',
    '017_inventory_grid.sql',
    -- Zombie node tables. bs_zombies/server/sv_nodes_db.lua selects from them on boot and fails if they are missing.
    '018_zombie_nodes.sql',
    -- Staff menu toggles per staff identifier (bs_admin_prefs). Without this line they stop persisting.
    '019_admin_prefs.sql',
    -- bs_traders: mission state/history and the /traderdebug override tables. Table names still use the old bs_npcs naming on purpose, since 020_npcs.sql already holds live data.
    '020_npcs.sql',
    '021_retire_inventory_clothing.sql',
    -- Squads (bs_factions).
    '022_squads.sql',
    -- Sanctions, jails, rank perms, treasury caps (bs_faction_bases + bs_factions).
    '023_faction_sanctions.sql',
    -- Faction levels, missions, skills.
    '024_faction_progression.sql',
    -- bs_vip perks: cosmetic prefs + appearance change ledger.
    '025_vip_perks.sql',
    -- bs_config: F1 console profiles, active profile, audit (bs_config also self-creates).
    '026_config_profiles.sql',
    -- slot_x to SMALLINT so loadout slots 901+/911+ persist.
    '027_inventory_slot_smallint.sql',
    -- bs_guard: anti-cheat detection log (bs_guard also self-creates).
    '028_guard_log.sql',
    '029_vehicle_world.sql',
    -- Per-account interface language (sh_locale.lua).
    '030_user_language.sql',
    -- Faction base pieces (bs_building), moves old structures over.
    '031_building.sql',
    -- bs_crafting station queues, traps, refunds; bs_recycler machines.
    '032_crafting.sql',
    -- bs_medical: conditions per character (bs_medical also self-creates).
    '033_medical.sql',
    -- Base flags rework: safezone/outpost kinds, declared raids (bs_faction_bases, bs_building).
    '034_base_flags.sql',
    -- Faction jobs: members, board, scores, stations, garage work (bs_jobs).
    '035_faction_jobs.sql',
    -- Backpack tiers: old packs become pack_medium (bs_inventory).
    '036_backpack_tiers.sql',
    -- Wasteland Pass: seasons, progress, owed rewards, pass cars (bs_pass).
    '037_pass.sql',
    -- Tutorial: faction pick, chapters seen, one-time rewards, first mission (bs_tutorial).
    '038_tutorial.sql',
    '039_tutorial_flags.sql',
    -- 040: retired (faction NPCs were removed). Numbers are kept so 041+ stay valid. No drop-table migration.
    -- Convoy routes recorded in-game (bs_events).
    '041_convoy_routes.sql',
    -- Build zones added in game, owner index for per-player piece limits (bs_building).
    '042_build_zones.sql',
    -- Power station, control points, mission chains and their F1 editor rows (bs_operations).
    '044_operations.sql',
}

local function ensureTrackingTable()
    BS.DB.Query([[
        CREATE TABLE IF NOT EXISTS `bs_migrations` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `filename` VARCHAR(191) NOT NULL,
            `checksum` VARCHAR(64) NULL,
            `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_bs_migrations_filename` (`filename`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function alreadyApplied(filename)
    local row = BS.DB.Single('SELECT `id` FROM `bs_migrations` WHERE `filename` = ? LIMIT 1', { filename })
    return row ~= nil
end

function M.Run()
    if not Config.Database.runMigrations then
        BS.Log.info('db', 'migrations disabled by config')
        return true
    end

    ensureTrackingTable()

    local applied, skipped = 0, 0
    for _, filename in ipairs(M.files) do
        if alreadyApplied(filename) then
            skipped = skipped + 1
        else
            local content = LoadResourceFile(GetCurrentResourceName(), 'sql/' .. filename)
            if not content then
                BS.Log.error('db', ('migration file missing: sql/%s'):format(filename))
                return false
            end
            BS.Log.info('db', ('applying migration %s'):format(filename))
            local ok, info = BS.DB.Execute(content)
            if not ok then
                BS.Log.error('db', ('migration %s failed: %s'):format(filename, tostring(info)))
                return false
            end
            BS.DB.Insert('INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES (?, ?)',
                { filename, tostring(#content) })
            applied = applied + 1
        end
    end

    BS.Log.info('db', ('migrations complete: %d applied, %d already present'):format(applied, skipped))
    return true
end
