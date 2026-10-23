-- BeyondSurvival | 003_inventory_economy.sql
-- Grid inventory, containers, crafting and vendors.

CREATE TABLE IF NOT EXISTS `bs_inventories` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- owner_type: character | container | vehicle | vendor | corpse
    `owner_type`    VARCHAR(24) NOT NULL,
    `owner_id`      VARCHAR(64) NOT NULL,
    `label`         VARCHAR(64) NULL,
    `grid_width`    TINYINT UNSIGNED NOT NULL DEFAULT 10,
    `grid_height`   TINYINT UNSIGNED NOT NULL DEFAULT 6,
    `max_weight`    FLOAT NOT NULL DEFAULT 40,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_inventories_owner` (`owner_type`, `owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_inventory_items` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `inventory_id`  INT UNSIGNED NOT NULL,
    `item`          VARCHAR(48) NOT NULL,
    `amount`        INT UNSIGNED NOT NULL DEFAULT 1,
    `slot_x`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `slot_y`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `rotated`       TINYINT(1) NOT NULL DEFAULT 0,
    `durability`    FLOAT NULL,
    `metadata`      LONGTEXT NULL,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_items_inventory` (`inventory_id`),
    KEY `ix_bs_items_item` (`item`),
    CONSTRAINT `fk_bs_items_inventory` FOREIGN KEY (`inventory_id`)
        REFERENCES `bs_inventories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_item_definitions` (
    `name`          VARCHAR(48) NOT NULL,
    `label`         VARCHAR(64) NOT NULL,
    `category`      VARCHAR(32) NOT NULL DEFAULT 'misc',
    `weight`        FLOAT NOT NULL DEFAULT 0.5,
    `grid_w`        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `grid_h`        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `stack_size`    INT UNSIGNED NOT NULL DEFAULT 1,
    `usable`        TINYINT(1) NOT NULL DEFAULT 0,
    `base_value`    INT UNSIGNED NOT NULL DEFAULT 0,
    `icon`          VARCHAR(96) NULL,
    `data`          LONGTEXT NULL,
    PRIMARY KEY (`name`),
    KEY `ix_bs_itemdef_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_crafting_known` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `recipe`        VARCHAR(48) NOT NULL,
    `learned_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_craft_char_recipe` (`character_id`, `recipe`),
    CONSTRAINT `fk_bs_craft_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_vendor_stock` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `vendor`        VARCHAR(48) NOT NULL,
    `item`          VARCHAR(48) NOT NULL,
    `stock`         INT NOT NULL DEFAULT -1,
    `price`         INT UNSIGNED NOT NULL DEFAULT 0,
    `restock_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vendor_item` (`vendor`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
