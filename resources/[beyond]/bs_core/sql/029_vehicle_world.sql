-- World vehicles: random road spawns that start without a battery, spark plug and fuel tank.
-- `missing` is a JSON list of part ids that are not fitted. Wrecks are vehicles that exploded.

ALTER TABLE `bs_vehicles`
    ADD COLUMN IF NOT EXISTS `missing`     LONGTEXT NULL AFTER `parts`,
    ADD COLUMN IF NOT EXISTS `world_spawn` TINYINT(1) NOT NULL DEFAULT 0 AFTER `stored`,
    ADD COLUMN IF NOT EXISTS `category`    VARCHAR(16) NULL AFTER `world_spawn`,
    ADD COLUMN IF NOT EXISTS `wrecked_at`  DATETIME NULL AFTER `stripped_at`;
