--
-- Central mirror of ss13_char_cyborg's last_x/y/z columns -- see
-- V160__char_cyborg_last_location.sql (local) for the full rationale.
--

ALTER TABLE `ss13_char_cyborg`
	ADD COLUMN `last_x` SMALLINT NULL AFTER `cyborg_json`,
	ADD COLUMN `last_y` SMALLINT NULL AFTER `last_x`,
	ADD COLUMN `last_z` SMALLINT NULL AFTER `last_y`;
