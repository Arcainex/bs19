-- Register of who owns what: factions live in the database instead of only config.
-- The four config factions are seeded as rows with no owner (an admin assigns one); player-created factions are rows like any other. Membership, reputation and unlocks key off the faction id string and need no changes.

CREATE TABLE IF NOT EXISTS `bs_faction_registry` (
    `faction_id`   VARCHAR(32) NOT NULL,
    `label`        VARCHAR(48) NOT NULL,
    `short`        VARCHAR(8)  NOT NULL DEFAULT '',
    `owner_character_id` INT UNSIGNED NULL,
    `created_by`   INT UNSIGNED NULL,
    is_config    TINYINT(1) NOT NULL DEFAULT 0,
    description  TEXT NULL,
    `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`faction_id`),
    KEY `ix_bs_faction_registry_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Rank inside a faction. 'owner' created it (or was put in charge by an admin), 'officer' may invite and kick, 'member' may not.
ALTER TABLE `bs_faction_members`
    ADD COLUMN IF NOT EXISTS `rank` VARCHAR(16) NOT NULL DEFAULT 'member' AFTER `faction_id`;
