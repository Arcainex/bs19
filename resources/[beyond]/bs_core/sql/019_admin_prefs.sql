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
