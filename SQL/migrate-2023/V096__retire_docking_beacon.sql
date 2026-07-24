--
-- The docking_beacon machine is retired: drydock retrieve/stash are now
-- sector-relative (personal ships) or faction_beacon-anchored (faction
-- ships) instead of depending on a player-placed navigation destination.
-- Dev environment cutover -- no docking beacon data existed worth migrating.
--

DROP TABLE IF EXISTS `ss13_player_docking_beacons`;
