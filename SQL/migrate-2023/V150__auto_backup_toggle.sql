--
-- Single-row server setting: whether the periodic autosave (SSpersistence
-- fire(), persistence.dm) also runs a full database backup (the same
-- scripts/db_backup that Trigger Database Backup runs on demand) after each
-- successful save. Managed by the Toggle Auto Backup On Autosave admin verb
-- (persistence_backups.dm); loaded at boot by autoBackupToggleInitialize().
-- Same shape as ss13_faction_raiding_toggle (V105) / ss13_join_whitelist_toggle
-- (V085). Default OFF -- opt-in, unlike those two, since this adds new
-- automatic behavior rather than preserving an existing default.
--

CREATE TABLE IF NOT EXISTS `ss13_auto_backup_toggle` (
  `id`      TINYINT NOT NULL DEFAULT 1,
  `enabled` BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
