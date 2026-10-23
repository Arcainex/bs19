-- bs_vip: personal cosmetic choices and the appearance-change ledger.
-- Keyed by account identifier like 010_vip.sql. bs_vip also creates these on start, so skipping this file still works.

CREATE TABLE IF NOT EXISTS `bs_vip_prefs` (
    `identifier`  VARCHAR(191) NOT NULL,
    `prefs`       LONGTEXT NULL,
    `updated_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- last_free_month = 'YYYY-MM' of the last free VIP change; tickets = staff gifts.
CREATE TABLE IF NOT EXISTS `bs_vip_appearance` (
    `identifier`      VARCHAR(191) NOT NULL,
    `last_free_month` CHAR(7) NULL DEFAULT NULL,
    `tickets`         INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
