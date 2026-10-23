-- Vehicles that belong to somebody, remember damage and hold items.
-- Identified by PLATE, not network id, so it survives restarts and respawns.

CREATE TABLE IF NOT EXISTS `bs_vehicles` (
    `id`                INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate`             VARCHAR(12) NOT NULL,
    `model`             VARCHAR(48) NOT NULL,

    -- NULL = nobody owns it. A found car works; it just has no keys.
    `owner_character_id` INT UNSIGNED NULL,

    `fuel`              FLOAT NOT NULL DEFAULT 60,
    `body_health`       FLOAT NOT NULL DEFAULT 1000,
    `engine_health`     FLOAT NOT NULL DEFAULT 1000,
    `tank_health`       FLOAT NOT NULL DEFAULT 1000,

    -- Wear on the individual parts, 0..100. JSON so a new part is a config
    -- change rather than a migration.
    `parts`             LONGTEXT NULL,
    -- Full vehicle properties (colours, mods, extras) as JSON.
    `props`             LONGTEXT NULL,
    -- Where it was last seen: { x, y, z, h }.
    `position`          LONGTEXT NULL,

    `locked`            TINYINT(1) NOT NULL DEFAULT 1,
    -- 1 while the car is put away and should not be spawned into the world.
    `stored`            TINYINT(1) NOT NULL DEFAULT 0,
    -- 1 once it has been stripped for parts. Kept rather than deleted so the
    -- plate is never handed out twice.
    `scrapped`          TINYINT(1) NOT NULL DEFAULT 0,

    `created_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vehicles_plate` (`plate`),
    KEY `ix_bs_vehicles_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Who can open and start it. The owner always can; this table is everybody
-- else they handed a key to.
CREATE TABLE IF NOT EXISTS `bs_vehicle_keys` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `vehicle_id`    INT UNSIGNED NOT NULL,
    `character_id`  INT UNSIGNED NOT NULL,
    `granted_by`    INT UNSIGNED NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vehicle_keys` (`vehicle_id`, `character_id`),
    KEY `ix_bs_vehicle_keys_char` (`character_id`),
    CONSTRAINT `fk_bs_vehicle_keys_vehicle`
        FOREIGN KEY (`vehicle_id`) REFERENCES `bs_vehicles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
