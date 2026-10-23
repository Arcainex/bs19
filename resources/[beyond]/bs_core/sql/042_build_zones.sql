-- 042: bs_building areas staff add in game with /buildzone. kind block = no building, allow = build area for allowedOnly.
CREATE TABLE IF NOT EXISTS `bs_build_zones` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind`        VARCHAR(8) NOT NULL DEFAULT 'block',
    `label`       VARCHAR(64) NOT NULL DEFAULT '',
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL DEFAULT 0,
    `radius`      FLOAT NOT NULL DEFAULT 50,
    `created_by`  VARCHAR(64) NOT NULL DEFAULT '',
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Piece limits are per player now.
ALTER TABLE `bs_build_pieces` ADD INDEX IF NOT EXISTS `ix_bs_build_owner` (`owner_char`);
