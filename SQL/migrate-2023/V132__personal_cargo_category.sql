--
-- Personal cargo specialization (FACTION_CARGO_SPECIALIZATION, code/_compile_options.dm) --
-- extends the same "pick one cargo category, then locked for a while" rule to
-- an individual PERSONALLY-tagged cargo console/PDA (personal_ckey/
-- personal_char_name, modular_computer/variables.dm), keyed by the same
-- (ckey, char_name) composite identity ss13_char_identity/ss13_mob_position
-- already use for per-character state. NULL allowed_cargo_category means
-- "hasn't chosen one yet" -- nothing orderable from a personal console until
-- it does. Unlike the faction version (1 real-world calendar month), this
-- lock is a flat 30 real days from cargo_category_changed_at.
--

CREATE TABLE IF NOT EXISTS `ss13_personal_cargo_category` (
	`ckey`                      VARCHAR(32) NOT NULL,
	`char_name`                 VARCHAR(64) NOT NULL,
	`allowed_cargo_category`    VARCHAR(64) NULL DEFAULT NULL,
	`cargo_category_changed_at` DATETIME NULL DEFAULT NULL,
	PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
