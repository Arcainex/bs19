-- Buried caches. A stash is a place owned by a character; its contents are an ordinary inventory container owned by 'stash:<id>'.
-- The server only sends a player their own rows.

CREATE TABLE IF NOT EXISTS `bs_stashes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_character_id` INT UNSIGNED NOT NULL,
    `label` VARCHAR(48) NOT NULL DEFAULT 'Stash',
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `buried_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_stashes_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
