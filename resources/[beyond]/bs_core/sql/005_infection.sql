-- Infection is a core stat with its own column since it is queried, compared and sorted on.

ALTER TABLE `bs_characters`
    ADD COLUMN `infection` FLOAT NOT NULL DEFAULT 0 AFTER `thirst`;

ALTER TABLE `bs_characters`
    ADD COLUMN `hud_settings` TEXT NULL AFTER `metadata`;
