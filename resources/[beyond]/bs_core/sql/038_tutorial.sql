-- Tutorial progress (bs_tutorial): first-join faction pick, tour chapters seen, one-time rewards, first mission.
-- bs_tutorial also creates this itself on start.
CREATE TABLE IF NOT EXISTS `bs_tutorial_progress` (
    `character_id` INT UNSIGNED NOT NULL,
    `needs_pick`   TINYINT(1) NOT NULL DEFAULT 0,
    `offered`      TINYINT(1) NOT NULL DEFAULT 0,
    `chapters`     TEXT NULL,
    `completed`    TINYINT(1) NOT NULL DEFAULT 0,
    `kit_given`    TINYINT(1) NOT NULL DEFAULT 0,
    `mission`      TEXT NULL,
    `mission_done` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
