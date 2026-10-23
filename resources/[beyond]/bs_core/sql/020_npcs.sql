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
