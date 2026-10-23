-- Per-player / faction-wide sanctions, jails, rank permissions and treasury caps.
-- Owners: bs_faction_bases/server/sv_sanctions.lua, bs_factions/server/sv_service.lua.
-- Rank ids: owner = Leader, officer = Vice Leader, member.

CREATE TABLE IF NOT EXISTS `bs_sanctions` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id`    VARCHAR(32) NULL,
    `character_id`  INT UNSIGNED NULL,          -- NULL = faction-wide
    `template_id`   VARCHAR(48) NOT NULL,
    `effects_json`  TEXT NOT NULL,
    `reason`        VARCHAR(255) NULL,
    `issued_by`     INT UNSIGNED NULL,
    `issued_by_name` VARCHAR(64) NULL,
    `issued_admin`  TINYINT(1) NOT NULL DEFAULT 0,
    `created_at`    BIGINT NOT NULL,
    `ends_at`       BIGINT NOT NULL,
    `fine_due`      INT NOT NULL DEFAULT 0,
    `lifted_at`     BIGINT NULL,
    `lifted_by`     INT UNSIGNED NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_sanctions_char` (`character_id`),
    KEY `ix_bs_sanctions_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_jails` (
    `scope`   VARCHAR(32) NOT NULL,             -- faction id or '__global'
    `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    `radius`  FLOAT NOT NULL DEFAULT 25,
    `exit_x` DOUBLE NULL, `exit_y` DOUBLE NULL, `exit_z` DOUBLE NULL, `exit_h` FLOAT NULL,
    PRIMARY KEY (`scope`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_jail_cells` (
    `scope` VARCHAR(32) NOT NULL,
    `n`     INT UNSIGNED NOT NULL,
    `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (`scope`, `n`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_jail_inmates` (
    `character_id` INT UNSIGNED NOT NULL,
    `sanction_id`  INT UNSIGNED NULL,
    `scope`        VARCHAR(32) NOT NULL,
    `cell`         INT UNSIGNED NOT NULL,
    `remaining`    INT NOT NULL,                -- seconds, counted while online
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_rank_perms` (
    `faction_id` VARCHAR(32) NOT NULL,
    `rank`       VARCHAR(16) NOT NULL,
    `perms_json` TEXT NOT NULL,
    `daily_cap`  INT NOT NULL DEFAULT 0,        -- 0 = unlimited
    PRIMARY KEY (`faction_id`, `rank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_faction_bank_daily` (
    `faction_id`   VARCHAR(32) NOT NULL,
    `character_id` INT UNSIGNED NOT NULL,
    `day`          DATE NOT NULL,
    `amount`       INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`faction_id`, `character_id`, `day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
