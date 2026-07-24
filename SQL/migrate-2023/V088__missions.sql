--
-- Admin-authored mission templates -- fetch-item and kill-NPC types for now.
-- Templates only; per-accepter progress (current claim, remaining kill
-- count, spawned mob refs) is runtime-only, matching the single-claim-at-a-
-- time design (see persistence_missions.dm / /datum/mission_instance).
--
-- sector_template_id references an away-site TEMPLATE id (e.g.
-- "wrecked_nt_ship"), not a specific live instance's display name -- away
-- sites aren't guaranteed to exist in a given session (dynamic sites are
-- drawn from an RNG pool each boot), so missions target "wherever the
-- current instance of this template is, spawning one on demand if needed"
-- rather than one specific, possibly-absent site.
--

CREATE TABLE IF NOT EXISTS `ss13_missions` (
  `id`                  INT NOT NULL AUTO_INCREMENT,
  `map_path`            VARCHAR(64) NOT NULL,
  `mission_type`        ENUM('fetch','kill') NOT NULL,
  `title`               VARCHAR(128) NOT NULL,
  `description`         VARCHAR(512) NULL,
  `fetch_item_path`     VARCHAR(255) NULL,
  `fetch_count`         INT NULL,
  `kill_mob_path`       VARCHAR(255) NULL,
  `kill_count`          INT NULL,
  `sector_template_id`  VARCHAR(128) NULL,
  `reward`              INT NOT NULL,
  `enabled`             TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
