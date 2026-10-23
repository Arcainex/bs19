-- Faction levels, mission board, skill tree and tag cosmetics.
-- Owner: bs_factions/server/sv_progression.lua (also creates these on start).
-- Faction XP comes only from missions and treasury donations.

CREATE TABLE IF NOT EXISTS `bs_faction_progress` (
    `faction_id` VARCHAR(32)  NOT NULL,
    `xp`         INT UNSIGNED NOT NULL DEFAULT 0,       -- level is derived from this
    `colour`     VARCHAR(16)  NOT NULL DEFAULT 'amber', -- tag colour id
    `style`      VARCHAR(16)  NOT NULL DEFAULT 'plain', -- tag style id
    `day_key`    INT          NOT NULL DEFAULT -1,      -- UTC day the daily board was rolled
    `week_key`   INT          NOT NULL DEFAULT -1,      -- UTC week (Mon) the weekly board was rolled
    PRIMARY KEY (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_skills` (
    `faction_id` VARCHAR(32)      NOT NULL,
    `skill_id`   VARCHAR(32)      NOT NULL,
    `rank`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`faction_id`, `skill_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_missions` (
    `faction_id`   VARCHAR(32)      NOT NULL,
    `period`       VARCHAR(8)       NOT NULL,           -- 'daily' | 'weekly'
    `slot`         TINYINT UNSIGNED NOT NULL,
    `mission_id`   VARCHAR(32)      NOT NULL,
    `target`       INT UNSIGNED     NOT NULL,
    `progress`     INT UNSIGNED     NOT NULL DEFAULT 0,
    `done`         TINYINT(1)       NOT NULL DEFAULT 0,
    `xp_reward`    INT UNSIGNED     NOT NULL DEFAULT 0,
    `money_reward` INT UNSIGNED     NOT NULL DEFAULT 0,
    PRIMARY KEY (`faction_id`, `period`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_donations` (
    `faction_id`   VARCHAR(32)  NOT NULL,
    `character_id` INT UNSIGNED NOT NULL,
    `day`          DATE         NOT NULL,
    `xp`           INT UNSIGNED NOT NULL DEFAULT 0,     -- XP earned by donating that day (capped)
    PRIMARY KEY (`faction_id`, `character_id`, `day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
