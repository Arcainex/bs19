-- 044: bs_operations - power station state, control point owners, mission chain runs and history, F1 editor rows.
CREATE TABLE IF NOT EXISTS `bs_ops_state` (
    `k` VARCHAR(32) NOT NULL,
    `v` TEXT NOT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_ops_points` (
    `id`          VARCHAR(32) NOT NULL,
    `faction`     VARCHAR(32) NULL DEFAULT NULL,
    `captured_at` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- kind = point | chain; data = JSON from the F1 editor
CREATE TABLE IF NOT EXISTS `bs_ops_defs` (
    `kind`       VARCHAR(8) NOT NULL,
    `id`         VARCHAR(40) NOT NULL,
    `data`       MEDIUMTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`kind`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- one running chain per character
CREATE TABLE IF NOT EXISTS `bs_ops_runs` (
    `character_id` INT UNSIGNED NOT NULL,
    `chain_id`     VARCHAR(40) NOT NULL,
    `step`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `progress`     INT NOT NULL DEFAULT 0,
    `started_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_ops_chain_log` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id` INT UNSIGNED NOT NULL,
    `chain_id`     VARCHAR(40) NOT NULL,
    `tier`         VARCHAR(16) NOT NULL DEFAULT 'story',
    `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_ops_log_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
