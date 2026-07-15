--
-- Admin-authored mission templates -- fetch-item and kill-NPC types for now.
-- Templates only; per-accepter progress (current claim, remaining kill
-- count, spawned mob refs) is runtime-only, matching the single-claim-at-a-
-- time design (see persistence_missions.dm / /datum/mission_instance).
--

CREATE TABLE IF NOT EXISTS `ss13_missions` (
  `id`               INT NOT NULL AUTO_INCREMENT,
  `map_path`         VARCHAR(64) NOT NULL,
  `mission_type`     ENUM('fetch','kill') NOT NULL,
  `title`            VARCHAR(128) NOT NULL,
  `description`      VARCHAR(512) NULL,
  `fetch_item_path`  VARCHAR(255) NULL,
  `fetch_count`      INT NULL,
  `kill_mob_path`     VARCHAR(255) NULL,
  `kill_count`       INT NULL,
  `sector_uid`       VARCHAR(128) NULL,
  `reward`           INT NOT NULL,
  `enabled`          TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
