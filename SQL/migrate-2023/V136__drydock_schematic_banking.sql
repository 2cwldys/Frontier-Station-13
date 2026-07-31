--
-- Ship schematic banking -- a deposited /obj/item/ship_schematic (see
-- ship_schematic.dm) destroys the physical item and flags the ship here
-- instead, so drydock.dm's "withdraw_schematic" knows to offer a reprint.
-- Also forced TRUE by drydockRepossess() alongside seizing a ship for the
-- Hub, since the seized schematic is invalidated rather than replaced.
--

ALTER TABLE `ss13_drydock_ships`
	ADD COLUMN `schematic_banked` TINYINT(1) NOT NULL DEFAULT 0;
