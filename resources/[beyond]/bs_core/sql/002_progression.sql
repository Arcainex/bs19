-- BeyondSurvival | 002_progression.sql
-- Skills, skill tree unlocks and the money audit trail.

CREATE TABLE IF NOT EXISTS `bs_character_skills` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `skill`         VARCHAR(32) NOT NULL,
    `level`         INT UNSIGNED NOT NULL DEFAULT 0,
    `xp`            INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_skills_char_skill` (`character_id`, `skill`),
    CONSTRAINT `fk_bs_skills_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_character_perks` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `perk`          VARCHAR(48) NOT NULL,
    `rank`          INT UNSIGNED NOT NULL DEFAULT 1,
    `unlocked_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_perks_char_perk` (`character_id`, `perk`),
    CONSTRAINT `fk_bs_perks_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_transactions` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `account`       VARCHAR(24) NOT NULL,
    `amount`        BIGINT NOT NULL,
    `balance`       BIGINT NOT NULL,
    `reason`        VARCHAR(96) NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_tx_char` (`character_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_character_stats` (
    `character_id`  INT UNSIGNED NOT NULL,
    `zombie_kills`  INT UNSIGNED NOT NULL DEFAULT 0,
    `player_kills`  INT UNSIGNED NOT NULL DEFAULT 0,
    `deaths`        INT UNSIGNED NOT NULL DEFAULT 0,
    `items_crafted` INT UNSIGNED NOT NULL DEFAULT 0,
    `distance_run`  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`),
    CONSTRAINT `fk_bs_stats_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
