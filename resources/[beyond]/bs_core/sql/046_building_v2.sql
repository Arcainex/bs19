-- 046: bs_building v2. Pieces that were dropped become their closest match so old bases keep standing.
-- window wall -> wall, hatch floor -> floor, window bars -> chain-link panel, hatch -> ladder
UPDATE `bs_build_pieces` SET `piece` = 'wall' WHERE `piece` = 'wall_window';
UPDATE `bs_build_pieces` SET `piece` = 'floor' WHERE `piece` = 'floor_frame';
UPDATE `bs_build_pieces` SET `piece` = 'mesh_panel' WHERE `piece` = 'window';
UPDATE `bs_build_pieces` SET `piece` = 'ladder' WHERE `piece` = 'hatch';

-- Power cables between generators, power poles and junction boxes.
CREATE TABLE IF NOT EXISTS `bs_build_wires` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `a_id`        INT UNSIGNED NOT NULL,
    `b_id`        INT UNSIGNED NOT NULL,
    `owner_char`  INT UNSIGNED NULL,
    `faction_id`  VARCHAR(32) NULL,
    `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ix_bs_build_wires_a` (`a_id`),
    KEY `ix_bs_build_wires_b` (`b_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
