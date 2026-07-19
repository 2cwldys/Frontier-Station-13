--
-- Admin kill-switch for faction raiding (default ON): lets admins block
-- non-members from entering any claimed faction's territory outright,
-- e.g. when going offline and unable to supervise. Mirrors
-- ss13_faction_creation_toggle's shape exactly.
--

CREATE TABLE IF NOT EXISTS `ss13_faction_raiding_toggle` (
  `id`      TINYINT NOT NULL DEFAULT 1,
  `enabled` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
