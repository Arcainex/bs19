-- 039: bs_tutorial per-character flags.
-- skipped: the player declined the first-spawn offer (never auto-offered again).
-- mission_claimed: first mission reward taken from the inventory Mission Log. Existing finished missions were already paid.
-- bs_tutorial adds these columns itself at start when missing.
ALTER TABLE `bs_tutorial_progress`
    ADD COLUMN IF NOT EXISTS `skipped` TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `mission_claimed` TINYINT(1) NOT NULL DEFAULT 0;
UPDATE `bs_tutorial_progress` SET `mission_claimed` = `mission_done` WHERE `mission_claimed` = 0;
UPDATE `bs_tutorial_progress` SET `offered` = 1 WHERE `completed` = 1;
