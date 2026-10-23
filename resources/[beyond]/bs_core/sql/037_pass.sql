-- bs_pass: Wasteland Pass seasons, progress, owed cash/XP and pass cars. bs_pass also creates these on start.
CREATE TABLE IF NOT EXISTS `bs_pass_season` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `started_at` INT UNSIGNED NOT NULL,
    `ends_at` INT UNSIGNED NOT NULL,
    `closed` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_progress` (
    `char_id` INT UNSIGNED NOT NULL,
    `season` INT UNSIGNED NOT NULL,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `tokens` INT UNSIGNED NOT NULL DEFAULT 0,
    `claimed` VARCHAR(255) NOT NULL DEFAULT '',
    `day_key` INT NOT NULL DEFAULT 0,
    `day_xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `rerolls` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `week_key` INT NOT NULL DEFAULT 0,
    `dailies` TEXT NULL,
    `weeklies` TEXT NULL,
    `spins` INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`char_id`),
    KEY `idx_bs_pass_rank` (`season`, `xp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_pending` (
    `char_id` INT UNSIGNED NOT NULL,
    `cash` INT UNSIGNED NOT NULL DEFAULT 0,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT UNSIGNED NOT NULL,
    `plate` VARCHAR(16) NOT NULL,
    `model` VARCHAR(32) NOT NULL,
    `delivered` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_pass_veh_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
