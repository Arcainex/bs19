-- bs_zombies - 018: persistence for the zombie node simulation (sv_nodes.lua).
-- Must be registered in bs_core/server/sv_migrations.lua -> M.files; dropping a file here does not run it.
-- Tables: bs_zombie_campaign (one row, clock and totals), bs_zombie_nodes (one row per living herd), bs_zombie_spatial_memory (one row per 250m cell ever visited, outlives herds).
-- sim_time_ms is a column, never derived from NOW(): a server down for a week must resume where it left off. updated_at columns are for humans only.
-- JSON columns are LONGTEXT because drivers return JSON either decoded or as a string.
-- No nullable columns: oxmysql prepare_async measures parameter arrays with #, so a nil in the middle shifts values.

CREATE TABLE IF NOT EXISTS `bs_zombie_campaign` (
    -- Always 1. Single-row table with a fixed key.
    `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `seed` INT UNSIGNED NOT NULL,
    -- World clock in simulated ms, restored as-is.
    `sim_time_ms` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'running',
    `victory` TINYINT(1) NOT NULL DEFAULT 0,
    `total_population` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `global_cap` BIGINT UNSIGNED NOT NULL,
    -- JSON. Campaign settings plus nextNodeId, so ids are never reused.
    `settings` LONGTEXT NOT NULL,
    -- ZAtlas.version at save time. home_atlas / target_atlas are indices into ZAtlas.points, so a version mismatch makes them untrustworthy.
    `atlas_version` INT UNSIGNED NOT NULL DEFAULT 1,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zombie_nodes` (
    -- Assigned by the simulation, not AUTO_INCREMENT: the id must stay stable across save/load and the merge pass sorts on it.
    `id` BIGINT UNSIGNED NOT NULL,
    `population` BIGINT UNSIGNED NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    -- Derived from population and spread trait, stored so the row is readable without radiusFor().
    `radius` DOUBLE NOT NULL DEFAULT 20,
    -- Lehmer generator state (range 1..2147483646). A herd's future is this one integer.
    `rng_state` INT UNSIGNED NOT NULL,
    `home_atlas` INT UNSIGNED NOT NULL,
    `target_atlas` INT UNSIGNED NOT NULL,
    `intent` VARCHAR(24) NOT NULL DEFAULT 'wanderer',
    -- JSON. Herd personality, rolled at birth and inherited with mutation on split; must round-trip exactly.
    `traits` LONGTEXT NOT NULL,
    -- JSON, nullable. Noise alert in flight; expires is in sim ms, so it stays valid across restarts.
    `alert` LONGTEXT NOT NULL,
    `updated_sim_ms` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_zombie_nodes_xy` (`x`, `y`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zombie_spatial_memory` (
    -- 250m cell key as the simulation forms it: '<floor(x/250)>:<floor(y/250)>'. Stored as a string so it matches the in-memory key.
    `spatial_key` VARCHAR(32) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    -- Sim ms, or -1 for never observed (different from observed at time 0).
    `last_observed_sim_ms` BIGINT NOT NULL DEFAULT -1,
    `visit_heat` DOUBLE NOT NULL DEFAULT 0,
    `kill_pressure` DOUBLE NOT NULL DEFAULT 0,
    -- Sim ms when kill_pressure was last updated. Decay is applied lazily on read (half-life, see sv_nodes.lua), so the timestamp must persist.
    `pressure_at_sim_ms` BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`spatial_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
