-- What was left in the mag.
-- Adds a loaded round count to bs_character_weapons (006_weapons.sql), one row per character per weapon. Additive only. Needed because ammo is live engine state on the ped and was lost on relog or restart.

ALTER TABLE `bs_character_weapons`
    ADD COLUMN IF NOT EXISTS `ammo` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `attachments`;
