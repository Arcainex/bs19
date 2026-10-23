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
