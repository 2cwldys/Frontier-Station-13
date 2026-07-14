--
-- Single-row server setting: whether the join whitelist is enforced at all.
-- Managed by the Whitelist Players admin verb's "Toggle" option; loaded at
-- boot by whitelistInitialize(). Same shape as ss13_faction_creation_toggle
-- (V083).
--

CREATE TABLE IF NOT EXISTS `ss13_join_whitelist_toggle` (
  `id`      TINYINT NOT NULL DEFAULT 1,
  `enabled` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
