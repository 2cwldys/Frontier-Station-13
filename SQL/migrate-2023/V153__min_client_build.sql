--
-- Single-row server setting: the minimum BYOND *build* (the 1687 of 516.1687)
-- a client is allowed to connect with. This is the runtime override for
-- config.txt's MIN_CLIENT_BUILD -- config is only read at startup, so without
-- this a change to the minimum would need a full server restart. Managed by
-- the Set Minimum Client Build admin verb (persistence_client_build.dm);
-- loaded at boot by minClientBuildInitialize() and enforced in
-- client_procs.dm.
--
-- Same shape as ss13_auto_backup_toggle (V150) / ss13_faction_raiding_toggle
-- (V105). Default 0, which means "no override" -- the config value applies
-- until an admin sets one, and setting it back to 0 clears the override
-- rather than blocking every client.
--
-- INT rather than SMALLINT: BYOND builds are already four digits and there is
-- no reason to be tight here.
--

CREATE TABLE IF NOT EXISTS `ss13_min_client_build` (
  `id`    TINYINT NOT NULL DEFAULT 1,
  `build` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
