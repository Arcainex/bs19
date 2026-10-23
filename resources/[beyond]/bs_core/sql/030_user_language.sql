-- Interface language chosen by the player, per account (not per character).
-- NULL means "use the server default" (bs_config Global.defaultLanguage).
-- Additive only, see bs_core/server/sv_migrations.lua.

ALTER TABLE `bs_users`
    ADD COLUMN `language` VARCHAR(8) NULL DEFAULT NULL AFTER `name`;
