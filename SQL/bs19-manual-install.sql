-- BS19 manual database install. Use only on a new, empty database.
-- Select the database in your SQL client before importing this file.
-- Do not import over an existing BS19 installation.

CREATE TABLE IF NOT EXISTS `bs_migrations` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `filename` VARCHAR(191) NOT NULL,
    `checksum` VARCHAR(64) NULL,
    `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_migrations_filename` (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 001_core_schema.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('001_core_schema.sql', '3275');

-- 002_progression.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('002_progression.sql', '2569');

-- 003_inventory_economy.sql
-- BeyondSurvival | 003_inventory_economy.sql
-- Grid inventory, containers, crafting and vendors.

CREATE TABLE IF NOT EXISTS `bs_inventories` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- owner_type: character | container | vehicle | vendor | corpse
    `owner_type`    VARCHAR(24) NOT NULL,
    `owner_id`      VARCHAR(64) NOT NULL,
    `label`         VARCHAR(64) NULL,
    `grid_width`    TINYINT UNSIGNED NOT NULL DEFAULT 10,
    `grid_height`   TINYINT UNSIGNED NOT NULL DEFAULT 6,
    `max_weight`    FLOAT NOT NULL DEFAULT 40,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_inventories_owner` (`owner_type`, `owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_inventory_items` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `inventory_id`  INT UNSIGNED NOT NULL,
    `item`          VARCHAR(48) NOT NULL,
    `amount`        INT UNSIGNED NOT NULL DEFAULT 1,
    `slot_x`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `slot_y`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `rotated`       TINYINT(1) NOT NULL DEFAULT 0,
    `durability`    FLOAT NULL,
    `metadata`      LONGTEXT NULL,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_items_inventory` (`inventory_id`),
    KEY `ix_bs_items_item` (`item`),
    CONSTRAINT `fk_bs_items_inventory` FOREIGN KEY (`inventory_id`)
        REFERENCES `bs_inventories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_item_definitions` (
    `name`          VARCHAR(48) NOT NULL,
    `label`         VARCHAR(64) NOT NULL,
    `category`      VARCHAR(32) NOT NULL DEFAULT 'misc',
    `weight`        FLOAT NOT NULL DEFAULT 0.5,
    `grid_w`        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `grid_h`        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `stack_size`    INT UNSIGNED NOT NULL DEFAULT 1,
    `usable`        TINYINT(1) NOT NULL DEFAULT 0,
    `base_value`    INT UNSIGNED NOT NULL DEFAULT 0,
    `icon`          VARCHAR(96) NULL,
    `data`          LONGTEXT NULL,
    PRIMARY KEY (`name`),
    KEY `ix_bs_itemdef_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_crafting_known` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `recipe`        VARCHAR(48) NOT NULL,
    `learned_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_craft_char_recipe` (`character_id`, `recipe`),
    CONSTRAINT `fk_bs_craft_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_vendor_stock` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `vendor`        VARCHAR(48) NOT NULL,
    `item`          VARCHAR(48) NOT NULL,
    `stock`         INT NOT NULL DEFAULT -1,
    `price`         INT UNSIGNED NOT NULL DEFAULT 0,
    `restock_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vendor_item` (`vendor`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('003_inventory_economy.sql', '3418');

-- 004_zombies_world.sql
-- BeyondSurvival | 004_zombies_world.sql
-- Zombie telemetry, loot state and persistent world objects.

CREATE TABLE IF NOT EXISTS `bs_zombie_kills` (
    `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `zombie_type`   VARCHAR(32) NOT NULL DEFAULT 'walker',
    `weapon`        VARCHAR(48) NULL,
    `headshot`      TINYINT(1) NOT NULL DEFAULT 0,
    `zone`          VARCHAR(48) NULL,
    `xp_awarded`    INT UNSIGNED NOT NULL DEFAULT 0,
    `money_awarded` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_zkills_char` (`character_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_loot_points` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `zone`          VARCHAR(48) NOT NULL,
    `loot_table`    VARCHAR(48) NOT NULL,
    `pos_x`         FLOAT NOT NULL,
    `pos_y`         FLOAT NOT NULL,
    `pos_z`         FLOAT NOT NULL,
    `looted_by`     INT UNSIGNED NULL,
    `looted_at`     TIMESTAMP NULL DEFAULT NULL,
    `respawn_at`    TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `ix_bs_loot_zone` (`zone`),
    KEY `ix_bs_loot_respawn` (`respawn_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_world_objects` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `object_type`   VARCHAR(48) NOT NULL,
    `model`         VARCHAR(64) NOT NULL,
    `owner_char`    INT UNSIGNED NULL,
    `pos_x`         FLOAT NOT NULL,
    `pos_y`         FLOAT NOT NULL,
    `pos_z`         FLOAT NOT NULL,
    `rot_x`         FLOAT NOT NULL DEFAULT 0,
    `rot_y`         FLOAT NOT NULL DEFAULT 0,
    `rot_z`         FLOAT NOT NULL DEFAULT 0,
    `health`        FLOAT NOT NULL DEFAULT 100,
    `metadata`      LONGTEXT NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_world_type` (`object_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zone_state` (
    `zone`          VARCHAR(48) NOT NULL,
    `difficulty`    FLOAT NOT NULL DEFAULT 1,
    `heat`          FLOAT NOT NULL DEFAULT 0,
    `last_horde`    TIMESTAMP NULL DEFAULT NULL,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`zone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('004_zombies_world.sql', '2547');

-- 005_infection.sql
-- Infection is a core stat with its own column since it is queried, compared and sorted on.

ALTER TABLE `bs_characters`
    ADD COLUMN `infection` FLOAT NOT NULL DEFAULT 0 AFTER `thirst`;

ALTER TABLE `bs_characters`
    ADD COLUMN `hud_settings` TEXT NULL AFTER `metadata`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('005_infection.sql', '277');

-- 006_weapons.sql
-- What is attached to a character's weapons. One row per character per weapon. `attachments` is a JSON object keyed by slot, e.g. { "muzzle": "suppressor", "scope": "scope" }, so a new slot is a config change, not a migration.

CREATE TABLE IF NOT EXISTS `bs_character_weapons` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `weapon`        VARCHAR(48) NOT NULL,
    `attachments`   LONGTEXT NULL,
    `rounds_fired`  INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_charweap` (`character_id`, `weapon`),
    CONSTRAINT `fk_bs_charweap_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('006_weapons.sql', '884');

-- 007_vehicles.sql
-- Vehicles that belong to somebody, remember damage and hold items.
-- Identified by PLATE, not network id, so it survives restarts and respawns.

CREATE TABLE IF NOT EXISTS `bs_vehicles` (
    `id`                INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `plate`             VARCHAR(12) NOT NULL,
    `model`             VARCHAR(48) NOT NULL,

    -- NULL = nobody owns it. A found car works; it just has no keys.
    `owner_character_id` INT UNSIGNED NULL,

    `fuel`              FLOAT NOT NULL DEFAULT 60,
    `body_health`       FLOAT NOT NULL DEFAULT 1000,
    `engine_health`     FLOAT NOT NULL DEFAULT 1000,
    `tank_health`       FLOAT NOT NULL DEFAULT 1000,

    -- Wear on the individual parts, 0..100. JSON so a new part is a config
    -- change rather than a migration.
    `parts`             LONGTEXT NULL,
    -- Full vehicle properties (colours, mods, extras) as JSON.
    `props`             LONGTEXT NULL,
    -- Where it was last seen: { x, y, z, h }.
    `position`          LONGTEXT NULL,

    `locked`            TINYINT(1) NOT NULL DEFAULT 1,
    -- 1 while the car is put away and should not be spawned into the world.
    `stored`            TINYINT(1) NOT NULL DEFAULT 0,
    -- 1 once it has been stripped for parts. Kept rather than deleted so the
    -- plate is never handed out twice.
    `scrapped`          TINYINT(1) NOT NULL DEFAULT 0,

    `created_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vehicles_plate` (`plate`),
    KEY `ix_bs_vehicles_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Who can open and start it. The owner always can; this table is everybody
-- else they handed a key to.
CREATE TABLE IF NOT EXISTS `bs_vehicle_keys` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `vehicle_id`    INT UNSIGNED NOT NULL,
    `character_id`  INT UNSIGNED NOT NULL,
    `granted_by`    INT UNSIGNED NULL,
    `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_vehicle_keys` (`vehicle_id`, `character_id`),
    KEY `ix_bs_vehicle_keys_char` (`character_id`),
    CONSTRAINT `fk_bs_vehicle_keys_vehicle`
        FOREIGN KEY (`vehicle_id`) REFERENCES `bs_vehicles` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('007_vehicles.sql', '2485');

-- 008_scenes.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('008_scenes.sql', '1123');

-- 009_factions.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('009_factions.sql', '1667');

-- 010_vip.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('010_vip.sql', '1224');

-- 011_vehicle_tyres.sql
-- Wheel damage that survives a restart.
-- Vehicles restored after streaming out are rebuilt with CreateVehicle (four good tyres), so tyre state is stored as JSON, wheel index -> state: 0 = fine, 1 = burst, 2 = detached.
-- Additive only, see bs_core/server/sv_migrations.lua.

ALTER TABLE `bs_vehicles`
    ADD COLUMN `tyres_burst` LONGTEXT NULL AFTER `parts`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('011_vehicle_tyres.sql', '363');

-- 012_weapon_ammo.sql
-- What was left in the mag.
-- Adds a loaded round count to bs_character_weapons (006_weapons.sql), one row per character per weapon. Additive only. Needed because ammo is live engine state on the ped and was lost on relog or restart.

ALTER TABLE `bs_character_weapons`
    ADD COLUMN IF NOT EXISTS `ammo` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `attachments`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('012_weapon_ammo.sql', '361');

-- 013_vehicle_stripped.sql
-- A stripped car stays as a hulk; this adds a timestamp so the 3-day cleanup sweep in bs_vehicles/server/sv_main.lua knows what to remove.

ALTER TABLE `bs_vehicles`
    ADD COLUMN IF NOT EXISTS `stripped_at` DATETIME NULL AFTER `scrapped`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('013_vehicle_stripped.sql', '242');

-- 014_vehicle_mods.sql
-- Admin Car Tuning menu: installed performance/visual mods, so a tune persists through despawn and restart.
-- Stored as JSON, mod type -> mod index (as GetVehicleMod/SetVehicleMod), e.g. {"11": 3, "12": 2}. Additive only.

ALTER TABLE `bs_vehicles`
    ADD COLUMN `mods` LONGTEXT NULL AFTER `parts`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('014_vehicle_mods.sql', '302');

-- 015_stashes.sql
-- Buried caches. A stash is a place owned by a character; its contents are an ordinary inventory container owned by 'stash:<id>'.
-- The server only sends a player their own rows.

CREATE TABLE IF NOT EXISTS `bs_stashes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_character_id` INT UNSIGNED NOT NULL,
    `label` VARCHAR(48) NOT NULL DEFAULT 'Stash',
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `buried_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_stashes_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('015_stashes.sql', '652');

-- 016_faction_registry.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('016_faction_registry.sql', '1133');

-- 017_inventory_grid.sql
-- Two-dimensional placement for inventory items.
-- slot_x stays the flat slot index (hotbar, crafting, drops and moves all key on it); the grid position gets its own columns. Additive and idempotent. slot_y stays untouched.
-- 0,0 means not placed: existing rows are repacked on first load, biggest item first (see Grid.Repack in bs_inventory/server/sv_grid.lua).

ALTER TABLE `bs_inventory_items`
    ADD COLUMN IF NOT EXISTS `grid_x` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `slot_y`,
    ADD COLUMN IF NOT EXISTS `grid_y` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `grid_x`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('017_inventory_grid.sql', '580');

-- 018_zombie_nodes.sql
-- bs_zombies - 018: persistence for the zombie node simulation (sv_nodes.lua).
-- Must be registered in bs_core/server/sv_migrations.lua -> M.files; dropping a file here does not run it.
-- Tables: bs_zombie_campaign (one row, clock and totals), bs_zombie_nodes (one row per living herd), bs_zombie_spatial_memory (one row per 250m cell ever visited, outlives herds).
-- sim_time_ms is a column, never derived from NOW(): a server down for a week must resume where it left off. updated_at columns are for humans only.
-- JSON columns are LONGTEXT because drivers return JSON either decoded or as a string.
-- No nullable columns: oxmysql prepare_async measures parameter arrays with #, so a nil in the middle shifts values.

CREATE TABLE IF NOT EXISTS `bs_zombie_campaign` (
    -- Always 1. Single-row table with a fixed key.
    `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `seed` INT UNSIGNED NOT NULL,
    -- World clock in simulated ms, restored as-is.
    `sim_time_ms` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'running',
    `victory` TINYINT(1) NOT NULL DEFAULT 0,
    `total_population` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `global_cap` BIGINT UNSIGNED NOT NULL,
    -- JSON. Campaign settings plus nextNodeId, so ids are never reused.
    `settings` LONGTEXT NOT NULL,
    -- ZAtlas.version at save time. home_atlas / target_atlas are indices into ZAtlas.points, so a version mismatch makes them untrustworthy.
    `atlas_version` INT UNSIGNED NOT NULL DEFAULT 1,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zombie_nodes` (
    -- Assigned by the simulation, not AUTO_INCREMENT: the id must stay stable across save/load and the merge pass sorts on it.
    `id` BIGINT UNSIGNED NOT NULL,
    `population` BIGINT UNSIGNED NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    -- Derived from population and spread trait, stored so the row is readable without radiusFor().
    `radius` DOUBLE NOT NULL DEFAULT 20,
    -- Lehmer generator state (range 1..2147483646). A herd's future is this one integer.
    `rng_state` INT UNSIGNED NOT NULL,
    `home_atlas` INT UNSIGNED NOT NULL,
    `target_atlas` INT UNSIGNED NOT NULL,
    `intent` VARCHAR(24) NOT NULL DEFAULT 'wanderer',
    -- JSON. Herd personality, rolled at birth and inherited with mutation on split; must round-trip exactly.
    `traits` LONGTEXT NOT NULL,
    -- JSON, nullable. Noise alert in flight; expires is in sim ms, so it stays valid across restarts.
    `alert` LONGTEXT NOT NULL,
    `updated_sim_ms` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_zombie_nodes_xy` (`x`, `y`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_zombie_spatial_memory` (
    -- 250m cell key as the simulation forms it: '<floor(x/250)>:<floor(y/250)>'. Stored as a string so it matches the in-memory key.
    `spatial_key` VARCHAR(32) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    -- Sim ms, or -1 for never observed (different from observed at time 0).
    `last_observed_sim_ms` BIGINT NOT NULL DEFAULT -1,
    `visit_heat` DOUBLE NOT NULL DEFAULT 0,
    `kill_pressure` DOUBLE NOT NULL DEFAULT 0,
    -- Sim ms when kill_pressure was last updated. Decay is applied lazily on read (half-life, see sv_nodes.lua), so the timestamp must persist.
    `pressure_at_sim_ms` BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`spatial_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('018_zombie_nodes.sql', '3885');

-- 019_admin_prefs.sql
-- Staff menu toggles, remembered across relogs.
-- Must be registered in bs_core/server/sv_migrations.lua -> M.files; dropping a file in this folder does not run it.
-- Keyed by identifier (same as bs_users), not character, since these belong to the staff member. One JSON column so new toggles need no migration; unknown keys are ignored on load.

CREATE TABLE IF NOT EXISTS `bs_admin_prefs` (
    `identifier` VARCHAR(64) NOT NULL,
    `toggles`    LONGTEXT    NULL,
    `updated_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
                             ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('019_admin_prefs.sql', '664');

-- 020_npcs.sql
-- Four tables for bs_npcs.
-- bs_npc_missions: active state, one row per (character_id, mission_id); `progress` only matters for kind='kill' (gather is checked live at turn-in).
-- bs_npc_mission_log: history, used for cooldowns.
-- bs_npc_overrides / bs_npc_mission_overrides: written by the /npcdebug editor; `data` is a JSON blob of changed fields merged over config_npcs.lua. A row with no config entry is an NPC/mission created in the menu.

CREATE TABLE IF NOT EXISTS `bs_npc_missions` (
    `character_id` INT UNSIGNED NOT NULL,
    `mission_id`   VARCHAR(48)   NOT NULL,
    `npc_id`       VARCHAR(48)   NOT NULL,
    `progress`     INT UNSIGNED  NOT NULL DEFAULT 0,
    `accepted_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`, `mission_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_npc_mission_log` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id`  INT UNSIGNED NOT NULL,
    `mission_id`    VARCHAR(48)  NOT NULL,
    `completed_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_npc_mission_log_lookup` (`character_id`, `mission_id`, `completed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_npc_overrides` (
    `npc_id`      VARCHAR(48)  NOT NULL,
    `data`        JSON         NOT NULL,
    `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`npc_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_npc_mission_overrides` (
    `mission_id`  VARCHAR(48)  NOT NULL,
    `data`        JSON         NOT NULL,
    `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`mission_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('020_npcs.sql', '1956');

-- 021_retire_inventory_clothing.sql
-- Clothing appearance is now NPC/wardrobe-owned, not inventory-owned.
-- Keeps backpacks and bulletproof vests; removes retired clothing items from bags, containers, drops and the synced item-definition catalogue.
DELETE FROM `bs_inventory_items`
WHERE `item` IN (
  'worn_tshirt','field_jacket','hoodie','rain_coat','plain_vest',
  'work_trousers','cargo_pants','work_boots','trainers','dust_mask',
  'gas_mask','cap','safety_glasses','wrist_watch'
);

DELETE FROM `bs_item_definitions`
WHERE `name` IN (
  'worn_tshirt','field_jacket','hoodie','rain_coat','plain_vest',
  'work_trousers','cargo_pants','work_boots','trainers','dust_mask',
  'gas_mask','cap','safety_glasses','wrist_watch'
);
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('021_retire_inventory_clothing.sql', '694');

-- 022_squads.sql
-- Squads inside a faction (bs_factions/server/sv_squad.lua). A squad row is deleted when its last member leaves; members cascade.

CREATE TABLE IF NOT EXISTS `bs_squads` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name`         VARCHAR(32)  NOT NULL,
    `faction_id`   VARCHAR(32)  NOT NULL,
    `leader_char`  INT UNSIGNED NOT NULL,
    `ranks`        TEXT         NULL,
    `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_squads_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_squad_members` (
    `character_id` INT UNSIGNED NOT NULL,
    `squad_id`     INT UNSIGNED NOT NULL,
    `rank_id`      INT UNSIGNED NOT NULL DEFAULT 3,
    `name`         VARCHAR(64)  NOT NULL DEFAULT '',
    `joined_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`),
    KEY `ix_bs_squad_members_squad` (`squad_id`),
    CONSTRAINT `fk_bs_squad_members_squad` FOREIGN KEY (`squad_id`)
        REFERENCES `bs_squads` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_bs_squad_members_char` FOREIGN KEY (`character_id`)
        REFERENCES `bs_characters` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('022_squads.sql', '1260');

-- 023_faction_sanctions.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('023_faction_sanctions.sql', '2884');

-- 024_faction_progression.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('024_faction_progression.sql', '2182');

-- 025_vip_perks.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('025_vip_perks.sql', '978');

-- 026_config_profiles.sql
-- bs_config: F1 config console profiles, active profile, audit log.
CREATE TABLE IF NOT EXISTS `bs_config_profiles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `created_by` VARCHAR(128) NULL,
    `updated_by` VARCHAR(128) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_config_profiles_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_config_state` (
    `k` VARCHAR(64) NOT NULL,
    `v` TEXT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_config_audit` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `actor` VARCHAR(128) NULL,
    `actor_ident` VARCHAR(128) NULL,
    `action` VARCHAR(24) NOT NULL DEFAULT 'set',
    `profile` VARCHAR(64) NULL,
    `setting` VARCHAR(191) NULL,
    `old_value` TEXT NULL,
    `new_value` TEXT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_bs_config_audit_at` (`at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('026_config_profiles.sql', '1224');

-- 027_inventory_slot_smallint.sql
-- Booster/gadget loadout slots (901-903 / 911-912) don't fit a TINYINT UNSIGNED, so the column is widened. bs_inventory moves rows already clamped to 255 back into a loadout slot on load.
ALTER TABLE `bs_inventory_items`
    MODIFY COLUMN `slot_x` SMALLINT UNSIGNED NOT NULL DEFAULT 0;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('027_inventory_slot_smallint.sql', '287');

-- 028_guard_log.sql
-- bs_guard: anti-cheat detection log. Detection only, nothing here kicks or bans. bs_guard also creates this table itself on start.
CREATE TABLE IF NOT EXISTS `bs_guard_log` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `src` INT NULL,
    `license` VARCHAR(64) NULL,
    `char_id` INT NULL,
    `name` VARCHAR(64) NULL,
    `kind` VARCHAR(32) NOT NULL,
    `confidence` TINYINT UNSIGNED NOT NULL DEFAULT 50,
    `details` VARCHAR(512) NULL,
    `x` FLOAT NULL,
    `y` FLOAT NULL,
    `z` FLOAT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_bs_guard_log_at` (`created_at`),
    KEY `idx_bs_guard_log_license` (`license`),
    KEY `idx_bs_guard_log_kind` (`kind`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('028_guard_log.sql', '773');

-- 029_vehicle_world.sql
-- World vehicles: random road spawns that start without a battery, spark plug and fuel tank.
-- `missing` is a JSON list of part ids that are not fitted. Wrecks are vehicles that exploded.

ALTER TABLE `bs_vehicles`
    ADD COLUMN IF NOT EXISTS `missing`     LONGTEXT NULL AFTER `parts`,
    ADD COLUMN IF NOT EXISTS `world_spawn` TINYINT(1) NOT NULL DEFAULT 0 AFTER `stored`,
    ADD COLUMN IF NOT EXISTS `category`    VARCHAR(16) NULL AFTER `world_spawn`,
    ADD COLUMN IF NOT EXISTS `wrecked_at`  DATETIME NULL AFTER `stripped_at`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('029_vehicle_world.sql', '537');

-- 030_user_language.sql
-- Interface language chosen by the player, per account (not per character).
-- NULL means "use the server default" (bs_config Global.defaultLanguage).
-- Additive only, see bs_core/server/sv_migrations.lua.

ALTER TABLE `bs_users`
    ADD COLUMN `language` VARCHAR(8) NULL DEFAULT NULL AFTER `name`;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('030_user_language.sql', '301');

-- 031_building.sql
-- bs_building: faction base pieces. Old per-character structures from bs_world_objects are moved in.
CREATE TABLE IF NOT EXISTS `bs_build_pieces` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `piece`       VARCHAR(32) NOT NULL,
    `faction_id`  VARCHAR(32) NULL,
    `owner_char`  INT UNSIGNED NULL,
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL,
    `h`           FLOAT NOT NULL DEFAULT 0,
    `health`      FLOAT NOT NULL DEFAULT 100,
    `built`       TINYINT(1) NOT NULL DEFAULT 0,
    `deposited`   TEXT NULL,
    `code`        VARCHAR(8) NULL,
    `data`        TEXT NULL,
    `placed_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_build_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_build_bases` (
    `faction_id`  VARCHAR(32) NOT NULL,
    `last_visit`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Keep player bases: move the old builder's structures over, owned by the builder's faction.
INSERT INTO `bs_build_pieces` (`piece`, `faction_id`, `owner_char`, `x`, `y`, `z`, `h`, `health`, `built`, `data`)
SELECT CASE o.`object_type`
           WHEN 'barricade_wood' THEN 'barricade'
           WHEN 'barricade_metal' THEN 'barricade'
           WHEN 'bedroll' THEN 'sleeping_bag'
           WHEN 'crate' THEN 'storage_small'
           ELSE o.`object_type` END,
       m.`faction_id`, o.`owner_char`, o.`pos_x`, o.`pos_y`, o.`pos_z`, o.`rot_z`, o.`health`, 1,
       CONCAT('{"legacy":', o.`id`, '}')
FROM `bs_world_objects` o
LEFT JOIN `bs_faction_members` m ON m.`character_id` = o.`owner_char`
WHERE o.`object_type` IN ('barricade_wood','barricade_metal','campfire','workbench','bedroll','crate');

DELETE FROM `bs_world_objects` WHERE `object_type` IN ('barricade_wood','barricade_metal','campfire','workbench','bedroll','crate');
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('031_building.sql', '1990');

-- 032_crafting.sql
-- bs_crafting + bs_recycler: station queues, traps, offline refunds, recycler machines.
CREATE TABLE IF NOT EXISTS `bs_craft_stations` (
    `piece_id` INT UNSIGNED NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `data` LONGTEXT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`piece_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_craft_traps` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind` VARCHAR(32) NOT NULL,
    `owner_char` INT NOT NULL,
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_craft_traps_owner` (`owner_char`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_craft_refunds` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT NOT NULL,
    `items` TEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_craft_refunds_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_recycler_points` (
    `id` VARCHAR(48) NOT NULL,
    `label` VARCHAR(48) NOT NULL DEFAULT 'Recycler',
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL, `h` FLOAT NOT NULL DEFAULT 0,
    `fuel` FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('032_crafting.sql', '1483');

-- 033_medical.sql
-- bs_medical: injuries, infection, sickness and blood per character (JSON, timers stored as seconds left).
CREATE TABLE IF NOT EXISTS `bs_character_medical` (
    `character_id` INT UNSIGNED NOT NULL,
    `data`         TEXT NOT NULL,
    `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('033_medical.sql', '430');

-- 034_base_flags.sql
-- Base flags rework: two flag kinds (safezone, outpost) and declared raids.
-- bs_faction_bases also creates this table, make sure it exists before the updates.
CREATE TABLE IF NOT EXISTS `bs_faction_flags` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id` VARCHAR(32) NOT NULL,
    `kind` VARCHAR(16) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    `radius` FLOAT NOT NULL,
    `created_by` INT UNSIGNED NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'active',
    `reclaim_by` VARCHAR(32) NULL,
    `reclaim_ends` BIGINT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `faction_id` (`faction_id`)
);

-- Old kinds: main = player safezone, build = vanilla build flag (now an outpost).
UPDATE `bs_faction_flags` SET `kind` = 'safezone' WHERE `kind` = 'main';
UPDATE `bs_faction_flags` SET `kind` = 'outpost' WHERE `kind` = 'build';
-- Every flag area is the build radius now (50 m), so radii stop overlapping.
UPDATE `bs_faction_flags` SET `radius` = 50 WHERE `status` <> 'removed';

-- Raids declared from the Faction menu (bs_building sv_raids.lua).
CREATE TABLE IF NOT EXISTS `bs_build_raids` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `attacker_id` VARCHAR(32) NOT NULL,
    `target_id` VARCHAR(32) NOT NULL,
    `declared_by` INT UNSIGNED NULL,
    `declared_at` BIGINT NOT NULL,
    `ends_at` BIGINT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `attacker_id` (`attacker_id`),
    KEY `target_id` (`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('034_base_flags.sql', '1657');

-- 035_faction_jobs.sql
-- Faction jobs (bs_jobs): who holds which job, applications, the job board,
-- per-member scores, player faction job picks and stations, garage work on cars.
-- bs_jobs also creates these itself on start.

-- One job per character. status: pending (applied) or active.
CREATE TABLE IF NOT EXISTS `bs_job_members` (
    `character_id` INT UNSIGNED NOT NULL,
    `faction_id`   VARCHAR(32) NOT NULL,
    `job_id`       VARCHAR(32) NOT NULL,
    `status`       VARCHAR(12) NOT NULL DEFAULT 'pending',
    `applied_at`   BIGINT NOT NULL DEFAULT 0,
    `joined_at`    BIGINT NOT NULL DEFAULT 0,
    `approved_by`  INT UNSIGNED NULL,
    PRIMARY KEY (`character_id`),
    KEY `ix_bs_job_members_faction` (`faction_id`, `job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Wait after leaving a job before taking another.
CREATE TABLE IF NOT EXISTS `bs_job_cooldowns` (
    `character_id` INT UNSIGNED NOT NULL,
    `until_ts`     BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Score per member per week (week = YYYYWW). All-time is the sum.
CREATE TABLE IF NOT EXISTS `bs_job_stats` (
    `character_id` INT UNSIGNED NOT NULL,
    `faction_id`   VARCHAR(32) NOT NULL,
    `week`         INT UNSIGNED NOT NULL,
    `rep`          INT NOT NULL DEFAULT 0,
    `contracts`    INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_id`, `faction_id`, `week`),
    KEY `ix_bs_job_stats_faction` (`faction_id`, `week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The job board. status: open, taken, done, expired.
CREATE TABLE IF NOT EXISTS `bs_job_contracts` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id`  VARCHAR(32) NOT NULL,
    `job_id`      VARCHAR(32) NOT NULL,
    `template`    VARCHAR(48) NOT NULL,
    `data`        LONGTEXT NULL,
    `status`      VARCHAR(12) NOT NULL DEFAULT 'open',
    `taken_by`    INT UNSIGNED NULL,
    `taken_at`    BIGINT NOT NULL DEFAULT 0,
    `progress`    INT NOT NULL DEFAULT 0,
    `expires_at`  BIGINT NOT NULL DEFAULT 0,
    `created_at`  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `ix_bs_job_contracts_board` (`faction_id`, `status`),
    KEY `ix_bs_job_contracts_taker` (`taken_by`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player-made factions pick up to 2 jobs from the generic pool.
CREATE TABLE IF NOT EXISTS `bs_job_faction_picks` (
    `faction_id` VARCHAR(32) NOT NULL,
    `job_id`     VARCHAR(32) NOT NULL,
    `picked_at`  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`faction_id`, `job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Job stations player factions place at their safezone flag.
CREATE TABLE IF NOT EXISTS `bs_job_stations` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id` VARCHAR(32) NOT NULL,
    `x`          DOUBLE NOT NULL,
    `y`          DOUBLE NOT NULL,
    `z`          DOUBLE NOT NULL,
    `heading`    FLOAT NOT NULL DEFAULT 0,
    `placed_by`  INT UNSIGNED NULL,
    `created_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_bs_job_stations_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Garage work that is not a GTA mod slot: paint and bolted-on props. Mod slots live in bs_vehicles.mods.
CREATE TABLE IF NOT EXISTS `bs_job_vehicle_mods` (
    `plate`      VARCHAR(12) NOT NULL,
    `paint`      LONGTEXT NULL,
    `props`      LONGTEXT NULL,
    `updated_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('035_faction_jobs.sql', '3707');

-- 036_backpack_tiers.sql
-- Backpack tiers (bs_inventory). The old single pack ('hiking_pack', and any 'backpack' row) becomes the medium tier.
-- Metadata (bagId) is kept, so whatever was inside the old pack stays inside it.
-- Items that sat in the extra rows an old pack added to the main grid are left alone: the grid keeps those rows until they are emptied.
UPDATE `bs_inventory_items` SET `item` = 'pack_medium' WHERE `item` IN ('hiking_pack', 'backpack');
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('036_backpack_tiers.sql', '438');

-- 037_pass.sql
-- bs_pass: Wasteland Pass seasons, progress, owed cash/XP and pass cars. bs_pass also creates these on start.
CREATE TABLE IF NOT EXISTS `bs_pass_season` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `started_at` INT UNSIGNED NOT NULL,
    `ends_at` INT UNSIGNED NOT NULL,
    `closed` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_progress` (
    `char_id` INT UNSIGNED NOT NULL,
    `season` INT UNSIGNED NOT NULL,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `tokens` INT UNSIGNED NOT NULL DEFAULT 0,
    `claimed` VARCHAR(255) NOT NULL DEFAULT '',
    `day_key` INT NOT NULL DEFAULT 0,
    `day_xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `rerolls` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `week_key` INT NOT NULL DEFAULT 0,
    `dailies` TEXT NULL,
    `weeklies` TEXT NULL,
    `spins` INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`char_id`),
    KEY `idx_bs_pass_rank` (`season`, `xp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_pending` (
    `char_id` INT UNSIGNED NOT NULL,
    `cash` INT UNSIGNED NOT NULL DEFAULT 0,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_pass_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` INT UNSIGNED NOT NULL,
    `plate` VARCHAR(16) NOT NULL,
    `model` VARCHAR(32) NOT NULL,
    `delivered` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_bs_pass_veh_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('037_pass.sql', '1781');

-- 038_tutorial.sql
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
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('038_tutorial.sql', '669');

-- 039_tutorial_flags.sql
-- 039: bs_tutorial per-character flags.
-- skipped: the player declined the first-spawn offer (never auto-offered again).
-- mission_claimed: first mission reward taken from the inventory Mission Log. Existing finished missions were already paid.
-- bs_tutorial adds these columns itself at start when missing.
ALTER TABLE `bs_tutorial_progress`
    ADD COLUMN IF NOT EXISTS `skipped` TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `mission_claimed` TINYINT(1) NOT NULL DEFAULT 0;
UPDATE `bs_tutorial_progress` SET `mission_claimed` = `mission_done` WHERE `mission_claimed` = 0;
UPDATE `bs_tutorial_progress` SET `offered` = 1 WHERE `completed` = 1;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('039_tutorial_flags.sql', '664');

-- 041_convoy_routes.sql
-- 041: bs_events convoy routes recorded in-game with /convoyroute. points = JSON [[x,y,z],...].
CREATE TABLE IF NOT EXISTS `bs_convoy_routes` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `points` MEDIUMTEXT NOT NULL,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `created_by` VARCHAR(64) NOT NULL DEFAULT '',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('041_convoy_routes.sql', '508');

-- 042_build_zones.sql
-- 042: bs_building areas staff add in game with /buildzone. kind block = no building, allow = build area for allowedOnly.
CREATE TABLE IF NOT EXISTS `bs_build_zones` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `kind`        VARCHAR(8) NOT NULL DEFAULT 'block',
    `label`       VARCHAR(64) NOT NULL DEFAULT '',
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL DEFAULT 0,
    `radius`      FLOAT NOT NULL DEFAULT 50,
    `created_by`  VARCHAR(64) NOT NULL DEFAULT '',
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Piece limits are per player now.
ALTER TABLE `bs_build_pieces` ADD INDEX IF NOT EXISTS `ix_bs_build_owner` (`owner_char`);
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('042_build_zones.sql', '824');

-- 044_operations.sql
-- 044: bs_operations - power station state, control point owners, mission chain runs and history, F1 editor rows.
CREATE TABLE IF NOT EXISTS `bs_ops_state` (
    `k` VARCHAR(32) NOT NULL,
    `v` TEXT NOT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_ops_points` (
    `id`          VARCHAR(32) NOT NULL,
    `faction`     VARCHAR(32) NULL DEFAULT NULL,
    `captured_at` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- kind = point | chain; data = JSON from the F1 editor
CREATE TABLE IF NOT EXISTS `bs_ops_defs` (
    `kind`       VARCHAR(8) NOT NULL,
    `id`         VARCHAR(40) NOT NULL,
    `data`       MEDIUMTEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`kind`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- one running chain per character
CREATE TABLE IF NOT EXISTS `bs_ops_runs` (
    `character_id` INT UNSIGNED NOT NULL,
    `chain_id`     VARCHAR(40) NOT NULL,
    `step`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `progress`     INT NOT NULL DEFAULT 0,
    `started_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_ops_chain_log` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id` INT UNSIGNED NOT NULL,
    `chain_id`     VARCHAR(40) NOT NULL,
    `tier`         VARCHAR(16) NOT NULL DEFAULT 'story',
    `completed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_ops_log_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('044_operations.sql', '1860');

-- 045_darkzone.sql
-- 045: bs_darkzone - rotation state, F1 zone edits, DZ level per character, extraction log.
CREATE TABLE IF NOT EXISTS `bs_dz_state` (
    `k` VARCHAR(32) NOT NULL,
    `v` TEXT NOT NULL,
    PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- data = JSON from the F1 editor, wins over config_darkzone.lua
CREATE TABLE IF NOT EXISTS `bs_dz_zones` (
    `id`         VARCHAR(32) NOT NULL,
    `data`       TEXT NOT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- owed = rank rewards that did not fit in the inventory yet
CREATE TABLE IF NOT EXISTS `bs_dz_progress` (
    `character_id` INT UNSIGNED NOT NULL,
    `xp`           INT UNSIGNED NOT NULL DEFAULT 0,
    `rank`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `extracts`     INT UNSIGNED NOT NULL DEFAULT 0,
    `kills`        INT UNSIGNED NOT NULL DEFAULT 0,
    `deaths`       INT UNSIGNED NOT NULL DEFAULT 0,
    `owed`         TEXT NULL,
    `updated_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `bs_dz_log` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id` INT UNSIGNED NOT NULL,
    `kind`         VARCHAR(16) NOT NULL,
    `zone`         VARCHAR(32) NOT NULL DEFAULT '',
    `stacks`       INT NOT NULL DEFAULT 0,
    `xp`           INT NOT NULL DEFAULT 0,
    `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_dz_log_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('045_darkzone.sql', '1799');

-- 046_building_v2.sql
-- 046: bs_building v2. Pieces that were dropped become their closest match so old bases keep standing.
-- window wall -> wall, hatch floor -> floor, window bars -> chain-link panel, hatch -> ladder
UPDATE `bs_build_pieces` SET `piece` = 'wall' WHERE `piece` = 'wall_window';
UPDATE `bs_build_pieces` SET `piece` = 'floor' WHERE `piece` = 'floor_frame';
UPDATE `bs_build_pieces` SET `piece` = 'mesh_panel' WHERE `piece` = 'window';
UPDATE `bs_build_pieces` SET `piece` = 'ladder' WHERE `piece` = 'hatch';

-- Power cables between generators, power poles and junction boxes.
CREATE TABLE IF NOT EXISTS `bs_build_wires` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `a_id`        INT UNSIGNED NOT NULL,
    `b_id`        INT UNSIGNED NOT NULL,
    `owner_char`  INT UNSIGNED NULL,
    `faction_id`  VARCHAR(32) NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_build_wires_a` (`a_id`),
    KEY `ix_bs_build_wires_b` (`b_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('046_building_v2.sql', '1039');

-- 047_faction_emblems.sql
-- 047: faction emblems and safezone banners (bs_factions/server/sv_emblem.lua). Adds only, nothing is dropped or rewritten.
-- logo is the old {mark,color} value; it is kept and still read as a fallback.
ALTER TABLE `bs_faction_registry` ADD COLUMN IF NOT EXISTS `logo` VARCHAR(128) NULL;
ALTER TABLE `bs_faction_registry` ADD COLUMN IF NOT EXISTS `emblem` TEXT NULL;

-- Banner poles placed by staff (/factionbanner). Rows for a faction replace its config defaults.
CREATE TABLE IF NOT EXISTS `bs_faction_banners` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_id`  VARCHAR(32) NOT NULL,
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL,
    `heading`     FLOAT NOT NULL DEFAULT 0,
    `created_by`  INT UNSIGNED NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_faction_banners_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('047_faction_emblems.sql', '1011');

-- 048_backpack_refresh.sql
-- Keep each bag ID and its stored contents while replacing the retired pack items.
UPDATE `bs_inventory_items` SET `item` = 'pack_civilian' WHERE `item` = 'pack_small';
UPDATE `bs_inventory_items` SET `item` = 'pack_hiking' WHERE `item` IN ('pack_medium', 'hiking_pack');
UPDATE `bs_inventory_items` SET `item` = 'pack_survival' WHERE `item` = 'pack_large';
UPDATE `bs_inventory_items` SET `item` = 'pack_field_military' WHERE `item` = 'pack_military';
INSERT INTO `bs_migrations` (`filename`, `checksum`) VALUES ('048_backpack_refresh.sql', '459');
