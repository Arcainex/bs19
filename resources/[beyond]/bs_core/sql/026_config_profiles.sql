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
