-- bs_crafting + bs_recycler: station queues, traps, offline refunds, recycler machines.
CREATE TABLE IF NOT EXISTS `bs_craft_stations` (
    `piece_id` INT UNSIGNED NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `data` LONGTEXT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`piece_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_craft_traps` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind` VARCHAR(32) NOT NULL,
    `owner_char` INT NOT NULL,
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_craft_traps_owner` (`owner_char`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_craft_refunds` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT NOT NULL,
    `items` TEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_craft_refunds_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_recycler_points` (
    `id` VARCHAR(48) NOT NULL,
    `label` VARCHAR(48) NOT NULL DEFAULT 'Recycler',
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    `fuel` FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
