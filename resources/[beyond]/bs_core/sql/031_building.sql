-- bs_building: faction base pieces. Old per-character structures from bs_world_objects are moved in.
CREATE TABLE IF NOT EXISTS `bs_build_pieces` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `piece`       VARCHAR(32) NOT NULL,
    `faction_id`  VARCHAR(32) NULL,
    `owner_char`  INT UNSIGNED NULL,
    `x`           DOUBLE NOT NULL,
    `y`           DOUBLE NOT NULL,
    `z`           DOUBLE NOT NULL,
    `h`           FLOAT NOT NULL DEFAULT 0,
    `health`      FLOAT NOT NULL DEFAULT 100,
    `built`       TINYINT(1) NOT NULL DEFAULT 0,
    `deposited`   TEXT NULL,
    `code`        VARCHAR(8) NULL,
    `data`        TEXT NULL,
    `placed_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_build_faction` (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bs_build_bases` (
    `faction_id`  VARCHAR(32) NOT NULL,
    `last_visit`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`faction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Keep player bases: move the old builder's structures over, owned by the builder's faction.
INSERT INTO `bs_build_pieces` (`piece`, `faction_id`, `owner_char`, `x`, `y`, `z`, `h`, `health`, `built`, `data`)
SELECT CASE o.`object_type`
           WHEN 'barricade_wood' THEN 'barricade'
           WHEN 'barricade_metal' THEN 'barricade'
           WHEN 'bedroll' THEN 'sleeping_bag'
           WHEN 'crate' THEN 'storage_small'
           ELSE o.`object_type` END,
       m.`faction_id`, o.`owner_char`, o.`pos_x`, o.`pos_y`, o.`pos_z`, o.`rot_z`, o.`health`, 1,
       CONCAT('{"legacy":', o.`id`, '}')
FROM `bs_world_objects` o
LEFT JOIN `bs_faction_members` m ON m.`character_id` = o.`owner_char`
WHERE o.`object_type` IN ('barricade_wood','barricade_metal','campfire','workbench','bedroll','crate');

DELETE FROM `bs_world_objects` WHERE `object_type` IN ('barricade_wood','barricade_metal','campfire','workbench','bedroll','crate');
