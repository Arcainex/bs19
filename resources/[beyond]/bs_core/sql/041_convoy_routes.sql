-- 041: bs_events convoy routes recorded in-game with /convoyroute. points = JSON [[x,y,z],...].
CREATE TABLE IF NOT EXISTS `bs_convoy_routes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `points` MEDIUMTEXT NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `created_by` VARCHAR(64) NOT NULL DEFAULT '',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
