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
