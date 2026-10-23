-- Base flags rework: two flag kinds (safezone, outpost) and declared raids.
-- bs_faction_bases also creates this table, make sure it exists before the updates.
CREATE TABLE IF NOT EXISTS `bs_faction_flags` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id` VARCHAR(32) NOT NULL,
    `kind` VARCHAR(16) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    `radius` FLOAT NOT NULL,
    `created_by` INT UNSIGNED NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'active',
    `reclaim_by` VARCHAR(32) NULL,
    `reclaim_ends` BIGINT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `faction_id` (`faction_id`)
);

-- Old kinds: main = player safezone, build = vanilla build flag (now an outpost).
UPDATE `bs_faction_flags` SET `kind` = 'safezone' WHERE `kind` = 'main';
UPDATE `bs_faction_flags` SET `kind` = 'outpost' WHERE `kind` = 'build';
-- Every flag area is the build radius now (50 m), so radii stop overlapping.
UPDATE `bs_faction_flags` SET `radius` = 50 WHERE `status` <> 'removed';

-- Raids declared from the Faction menu (bs_building sv_raids.lua).
CREATE TABLE IF NOT EXISTS `bs_build_raids` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `attacker_id` VARCHAR(32) NOT NULL,
    `target_id` VARCHAR(32) NOT NULL,
    `declared_by` INT UNSIGNED NULL,
    `declared_at` BIGINT NOT NULL,
    `ends_at` BIGINT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `attacker_id` (`attacker_id`),
    KEY `target_id` (`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
