-- 045: bs_darkzone - rotation state, F1 zone edits, DZ level per character, extraction log.
CREATE TABLE IF NOT EXISTS `bs_dz_state` (
    `k` VARCHAR(32) NOT NULL,
    `v` TEXT NOT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- data = JSON from the F1 editor, wins over config_darkzone.lua
CREATE TABLE IF NOT EXISTS `bs_dz_zones` (
    `id`         VARCHAR(32) NOT NULL,
    `data`       TEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- owed = rank rewards that did not fit in the inventory yet
CREATE TABLE IF NOT EXISTS `bs_dz_progress` (
    `character_id` INT UNSIGNED NOT NULL,
    `xp`           INT UNSIGNED NOT NULL DEFAULT 0,
    `rank`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `extracts`     INT UNSIGNED NOT NULL DEFAULT 0,
    `kills`        INT UNSIGNED NOT NULL DEFAULT 0,
    `deaths`       INT UNSIGNED NOT NULL DEFAULT 0,
    `owed`         TEXT NULL,
    `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_dz_log` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id` INT UNSIGNED NOT NULL,
    `kind`         VARCHAR(16) NOT NULL,
    `zone`         VARCHAR(32) NOT NULL DEFAULT '',
    `stacks`       INT NOT NULL DEFAULT 0,
    `xp`           INT NOT NULL DEFAULT 0,
    `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_dz_log_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
