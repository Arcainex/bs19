-- BeyondSurvival | 001_core_schema.sql
-- Accounts, characters, moderation. Applied automatically by bs_core.

CREATE TABLE IF NOT EXISTS `bs_users` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier`    VARCHAR(191) NOT NULL,
    `steam`         VARCHAR(191) NULL,
    `discord`       VARCHAR(191) NULL,
    `fivem`         VARCHAR(191) NULL,
    `ip`            VARCHAR(64)  NULL,
    `name`          VARCHAR(96)  NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`     TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_users_identifier` (`identifier`),
    KEY `ix_bs_users_discord` (`discord`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_characters` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`       INT UNSIGNED NOT NULL,
    `first_name`    VARCHAR(32) NOT NULL,
    `last_name`     VARCHAR(32) NOT NULL,
    `gender`        ENUM('male','female') NOT NULL DEFAULT 'male',
    `dob`           DATE NULL,
    `class`         VARCHAR(32) NOT NULL DEFAULT 'survivor',
    `level`         INT UNSIGNED NOT NULL DEFAULT 1,
    `xp`            INT UNSIGNED NOT NULL DEFAULT 0,
    `skill_points`  INT UNSIGNED NOT NULL DEFAULT 0,
    `cash`          BIGINT NOT NULL DEFAULT 0,
    `bank`          BIGINT NOT NULL DEFAULT 0,
    `hunger`        FLOAT NOT NULL DEFAULT 100,
    `thirst`        FLOAT NOT NULL DEFAULT 100,
    `pos_x`         FLOAT NULL,
    `pos_y`         FLOAT NULL,
    `pos_z`         FLOAT NULL,
    `heading`       FLOAT NULL,
    `appearance`    LONGTEXT NULL,
    `metadata`      LONGTEXT NULL,
    `playtime`      INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_played`   TIMESTAMP NULL DEFAULT NULL,
    `deleted_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_characters_user` (`user_id`, `deleted_at`),
    KEY `ix_bs_characters_class` (`class`),
    CONSTRAINT `fk_bs_characters_user` FOREIGN KEY (`user_id`)
        REFERENCES `bs_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_bans` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`       INT UNSIGNED NOT NULL,
    `reason`        VARCHAR(255) NULL,
    `issued_by`     VARCHAR(96) NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_bans_user` (`user_id`, `expires_at`),
    CONSTRAINT `fk_bs_bans_user` FOREIGN KEY (`user_id`)
        REFERENCES `bs_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_logs` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `channel`       VARCHAR(48) NOT NULL,
    `character_id`  INT UNSIGNED NULL,
    `message`       TEXT NOT NULL,
    `data`          LONGTEXT NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_logs_channel` (`channel`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
