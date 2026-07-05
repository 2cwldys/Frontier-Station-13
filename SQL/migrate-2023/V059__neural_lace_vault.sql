-- Neural lace storage vaults: laces stashed in a vault persist across
-- restarts with their registration data. A stored consciousness is
-- round-local and cannot be restored; was_occupied records that it held one.
CREATE TABLE IF NOT EXISTS `ss13_neural_lace_vault` (
  `id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `map_path`        VARCHAR(128) NOT NULL,
  `vault_x`         INT NOT NULL,
  `vault_y`         INT NOT NULL,
  `vault_z`         INT NOT NULL,
  `registered_name` VARCHAR(64) NOT NULL DEFAULT '',
  `registered_ckey` VARCHAR(64) NOT NULL DEFAULT '',
  `owner_faction`   VARCHAR(32) NOT NULL DEFAULT '',
  `lace_damage`     INT NOT NULL DEFAULT 0,
  `was_occupied`    TINYINT(1) NOT NULL DEFAULT 0,
  `stored_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_vault_pos` (`map_path`, `vault_x`, `vault_y`, `vault_z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
