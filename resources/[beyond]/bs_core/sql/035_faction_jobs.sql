-- Faction jobs (bs_jobs): who holds which job, applications, the job board,
-- per-member scores, player faction job picks and stations, garage work on cars.
-- bs_jobs also creates these itself on start.

-- One job per character. status: pending (applied) or active.
CREATE TABLE IF NOT EXISTS `bs_job_members` (
    `character_id` INT UNSIGNED NOT NULL,
    `faction_id`   VARCHAR(32) NOT NULL,
    `job_id`       VARCHAR(32) NOT NULL,
    `status`       VARCHAR(12) NOT NULL DEFAULT 'pending',
    `applied_at`   BIGINT NOT NULL DEFAULT 0,
    `joined_at`    BIGINT NOT NULL DEFAULT 0,
    `approved_by`  INT UNSIGNED NULL,
    PRIMARY KEY (`character_id`),
    KEY `ix_bs_job_members_faction` (`faction_id`, `job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Wait after leaving a job before taking another.
CREATE TABLE IF NOT EXISTS `bs_job_cooldowns` (
    `character_id` INT UNSIGNED NOT NULL,
    `until_ts`     BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Score per member per week (week = YYYYWW). All-time is the sum.
CREATE TABLE IF NOT EXISTS `bs_job_stats` (
    `character_id` INT UNSIGNED NOT NULL,
    `faction_id`   VARCHAR(32) NOT NULL,
    `week`         INT UNSIGNED NOT NULL,
    `rep`          INT NOT NULL DEFAULT 0,
    `contracts`    INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_id`, `faction_id`, `week`),
    KEY `ix_bs_job_stats_faction` (`faction_id`, `week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The job board. status: open, taken, done, expired.
CREATE TABLE IF NOT EXISTS `bs_job_contracts` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id`  VARCHAR(32) NOT NULL,
    `job_id`      VARCHAR(32) NOT NULL,
    `template`    VARCHAR(48) NOT NULL,
    `data`        LONGTEXT NULL,
    `status`      VARCHAR(12) NOT NULL DEFAULT 'open',
    `taken_by`    INT UNSIGNED NULL,
    `taken_at`    BIGINT NOT NULL DEFAULT 0,
    `progress`    INT NOT NULL DEFAULT 0,
    `expires_at`  BIGINT NOT NULL DEFAULT 0,
    `created_at`  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `ix_bs_job_contracts_board` (`faction_id`, `status`),
    KEY `ix_bs_job_contracts_taker` (`taken_by`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player-made factions pick up to 2 jobs from the generic pool.
CREATE TABLE IF NOT EXISTS `bs_job_faction_picks` (
    `faction_id` VARCHAR(32) NOT NULL,
    `job_id`     VARCHAR(32) NOT NULL,
    `picked_at`  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`faction_id`, `job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Job stations player factions place at their safezone flag.
CREATE TABLE IF NOT EXISTS `bs_job_stations` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id` VARCHAR(32) NOT NULL,
    `x`          DOUBLE NOT NULL,
    `y`          DOUBLE NOT NULL,
    `z`          DOUBLE NOT NULL,
    `heading`    FLOAT NOT NULL DEFAULT 0,
    `placed_by`  INT UNSIGNED NULL,
    `created_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_job_stations_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Garage work that is not a GTA mod slot: paint and bolted-on props. Mod slots live in bs_vehicles.mods.
CREATE TABLE IF NOT EXISTS `bs_job_vehicle_mods` (
    `plate`      VARCHAR(12) NOT NULL,
    `paint`      LONGTEXT NULL,
    `props`      LONGTEXT NULL,
    `updated_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
