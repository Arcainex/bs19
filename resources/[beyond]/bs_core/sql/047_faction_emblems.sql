-- 047: faction emblems and safezone banners (bs_factions/server/sv_emblem.lua). Adds only, nothing is dropped or rewritten.
-- logo is the old {mark,color} value; it is kept and still read as a fallback.
ALTER TABLE `bs_faction_registry` ADD COLUMN IF NOT EXISTS `logo` VARCHAR(128) NULL;
ALTER TABLE `bs_faction_registry` ADD COLUMN IF NOT EXISTS `emblem` TEXT NULL;

-- Banner poles placed by staff (/factionbanner). Rows for a faction replace its config defaults.
CREATE TABLE IF NOT EXISTS `bs_faction_banners` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id`  VARCHAR(32) NOT NULL,
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL,
    `heading`     FLOAT NOT NULL DEFAULT 0,
    `created_by`  INT UNSIGNED NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_faction_banners_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
