--
-- The faction corvette system is retired and merged into the drydock ship
-- system (ss13_drydock_ships already supports faction ownership via its
-- faction_uid column, and now also accepts a faction_beacon as a retrieve/
-- stash anchor alongside docking_beacon). Dev environment cutover -- no
-- corvette ownership data existed worth migrating.
--

DROP TABLE IF EXISTS `ss13_faction_corvettes_backup`;
DROP TABLE IF EXISTS `ss13_faction_corvettes`;
