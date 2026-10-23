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
