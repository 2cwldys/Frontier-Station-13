-- Admin-tunable, live-editable cap on how many drydock ships can be
-- deployed (retrieved, not stashed) at once server-wide. Single-row
-- ("singleton") table -- id is always 1. 0 = no limit, so existing/
-- upgrading servers aren't suddenly capped until an admin explicitly picks
-- a value via the "Set Drydock Ship Cap" admin verb.

CREATE TABLE IF NOT EXISTS `ss13_drydock_config` (
    `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `max_deployed_ships` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    CONSTRAINT `single_row` CHECK (`id` = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `ss13_drydock_config` (`id`, `max_deployed_ships`) VALUES (1, 0);
