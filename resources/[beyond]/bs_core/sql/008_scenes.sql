-- World notes left by players (bs_scenes).
-- NOTE: sv_migrations.lua halts the whole run if a file in M.files is missing on disk, so every migration after a missing one never runs. Keep M.files and this folder in sync.

CREATE TABLE IF NOT EXISTS `bs_scenes` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `author`        VARCHAR(96) NOT NULL,
    `text`          VARCHAR(160) NOT NULL,
    `kind`          VARCHAR(24) NOT NULL DEFAULT 'note',
    `x`             FLOAT NOT NULL,
    `y`             FLOAT NOT NULL,
    `z`             FLOAT NOT NULL,
    `heading`       FLOAT NOT NULL DEFAULT 0,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_scenes_char` (`character_id`),
    KEY `ix_bs_scenes_expires` (`expires_at`),
    KEY `ix_bs_scenes_pos` (`x`, `y`),
    CONSTRAINT `fk_bs_scenes_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
