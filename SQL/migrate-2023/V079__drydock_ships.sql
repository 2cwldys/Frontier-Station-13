-- Drydock ship ledger, mirroring ss13_faction_corvettes exactly (same
-- backup-then-delete lifecycle, same Z-based materialization) except
-- ownership is personal-or-faction: owner_ckey is set for a personal ship,
-- faction_uid for a faction one -- unlike corvettes, never both unset.
CREATE TABLE IF NOT EXISTS `ss13_drydock_ships` (
    `shuttle_id`   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `template_id`  VARCHAR(64) NOT NULL,
    `owner_ckey`   VARCHAR(32) DEFAULT NULL,
    `faction_uid`  VARCHAR(32) DEFAULT NULL,
    `stashed`      TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1 = DB row only, no live Z content; 0 = deployed live',
    `z`            INT DEFAULT NULL COMMENT 'assigned on first retrieve; permanently reserved to this shuttle_id thereafter',
    `overmap_x`    INT DEFAULT NULL COMMENT 'last placed position; recomputed fresh on each retrieve',
    `overmap_y`    INT DEFAULT NULL,
    `purchased_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `stashed_at`   DATETIME DEFAULT NULL,
    PRIMARY KEY (`shuttle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
