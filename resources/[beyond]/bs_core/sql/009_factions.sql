-- Faction membership, reputation and permanent unlocks.
-- See 008_scenes.sql for why a missing migration file breaks every one listed after it.

CREATE TABLE IF NOT EXISTS `bs_faction_members` (
    `character_id`  INT UNSIGNED NOT NULL,
    `faction_id`    VARCHAR(32) NOT NULL,
    `joined_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`),
    KEY `ix_bs_faction_members_faction` (`faction_id`),
    CONSTRAINT `fk_bs_faction_members_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_reputation` (
    `character_id`  INT UNSIGNED NOT NULL,
    `faction_id`    VARCHAR(32) NOT NULL,
    `reputation`    INT NOT NULL DEFAULT 0,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`, `faction_id`),
    CONSTRAINT `fk_bs_faction_rep_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_unlocks` (
    `character_id`  INT UNSIGNED NOT NULL,
    `faction_id`    VARCHAR(32) NOT NULL,
    `unlock_id`     VARCHAR(48) NOT NULL,
    `unlocked_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`, `faction_id`, `unlock_id`),
    CONSTRAINT `fk_bs_faction_unlocks_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
