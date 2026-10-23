-- VIP tier membership, permanent unlocks and daily crate claims.
-- Keyed by `identifier` (license:...), not character_id, since VIP belongs to the account.
-- See 008_scenes.sql for why a missing migration file breaks later ones.

CREATE TABLE IF NOT EXISTS `bs_vip_members` (
    `identifier`    VARCHAR(191) NOT NULL,
    `tier`          VARCHAR(32) NOT NULL,
    `granted_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`    DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (`identifier`),
    KEY `ix_bs_vip_members_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_vip_unlocks` (
    `identifier`    VARCHAR(191) NOT NULL,
    `unlock_id`     VARCHAR(48) NOT NULL,
    `tier`          VARCHAR(32) NOT NULL,
    `granted_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `unlock_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_vip_crate_claims` (
    `identifier`    VARCHAR(191) NOT NULL,
    `claim_date`    DATE NOT NULL,
    PRIMARY KEY (`identifier`, `claim_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
