-- bs_medical: injuries, infection, sickness and blood per character (JSON, timers stored as seconds left).
CREATE TABLE IF NOT EXISTS `bs_character_medical` (
    `character_id` INT UNSIGNED NOT NULL,
    `data`         TEXT NOT NULL,
    `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
