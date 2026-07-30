--
-- Faction alliances (FACTION_ALLIANCES, code/_compile_options.dm) -- two
-- factions can become allied via a propose/accept handshake; either side
-- can break an existing alliance unilaterally at any time. faction_a/
-- faction_b are stored in canonical (sorted) order on insert to avoid
-- duplicate reversed rows -- readers/deleters check both column orderings
-- regardless.
--

CREATE TABLE IF NOT EXISTS `ss13_faction_alliances` (
	`faction_a`  VARCHAR(64) NOT NULL,
	`faction_b`  VARCHAR(64) NOT NULL,
	`allied_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`faction_a`, `faction_b`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_alliance_requests` (
	`proposer_uid`  VARCHAR(64) NOT NULL,
	`target_uid`    VARCHAR(64) NOT NULL,
	`requested_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`proposer_uid`, `target_uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
