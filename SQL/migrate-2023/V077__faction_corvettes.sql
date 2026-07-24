CREATE TABLE IF NOT EXISTS `ss13_faction_corvettes` (
    `corvette_id`  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `template_id`  VARCHAR(64) NOT NULL,
    `faction_uid`  VARCHAR(32) NOT NULL COMMENT 'owning faction -- always set, corvettes are never personal',
    `stashed`      TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1 = DB row only, no live Z content; 0 = deployed live',
    `z`            INT DEFAULT NULL COMMENT 'assigned on first retrieve; permanently reserved to this corvette_id thereafter',
    `overmap_x`    INT DEFAULT NULL COMMENT 'last placed position; recomputed fresh on each retrieve',
    `overmap_y`    INT DEFAULT NULL,
    `purchased_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `stashed_at`   DATETIME DEFAULT NULL,
    PRIMARY KEY (`corvette_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
