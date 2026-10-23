-- BeyondSurvival | 004_zombies_world.sql
-- Zombie telemetry, loot state and persistent world objects.

CREATE TABLE IF NOT EXISTS `bs_zombie_kills` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `zombie_type`   VARCHAR(32) NOT NULL DEFAULT 'walker',
    `weapon`        VARCHAR(48) NULL,
    `headshot`      TINYINT(1) NOT NULL DEFAULT 0,
    `zone`          VARCHAR(48) NULL,
    `xp_awarded`    INT UNSIGNED NOT NULL DEFAULT 0,
    `money_awarded` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_zkills_char` (`character_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_loot_points` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `zone`          VARCHAR(48) NOT NULL,
    `loot_table`    VARCHAR(48) NOT NULL,
    `pos_x`         FLOAT NOT NULL,
    `pos_y`         FLOAT NOT NULL,
    `pos_z`         FLOAT NOT NULL,
    `looted_by`     INT UNSIGNED NULL,
    `looted_at`     TIMESTAMP NULL DEFAULT NULL,
    `respawn_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_loot_zone` (`zone`),
    KEY `ix_bs_loot_respawn` (`respawn_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_world_objects` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `object_type`   VARCHAR(48) NOT NULL,
    `model`         VARCHAR(64) NOT NULL,
    `owner_char`    INT UNSIGNED NULL,
    `pos_x`         FLOAT NOT NULL,
    `pos_y`         FLOAT NOT NULL,
    `pos_z`         FLOAT NOT NULL,
    `rot_x`         FLOAT NOT NULL DEFAULT 0,
    `rot_y`         FLOAT NOT NULL DEFAULT 0,
    `rot_z`         FLOAT NOT NULL DEFAULT 0,
    `health`        FLOAT NOT NULL DEFAULT 100,
    `metadata`      LONGTEXT NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_world_type` (`object_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zone_state` (
    `zone`          VARCHAR(48) NOT NULL,
    `difficulty`    FLOAT NOT NULL DEFAULT 1,
    `heat`          FLOAT NOT NULL DEFAULT 0,
    `last_horde`    TIMESTAMP NULL DEFAULT NULL,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
