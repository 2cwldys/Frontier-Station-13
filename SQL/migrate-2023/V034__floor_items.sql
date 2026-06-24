CREATE TABLE `ss13_floor_items` (
  `id`          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `map_path`    VARCHAR(64)     NOT NULL,
  `type`        VARCHAR(128)    NOT NULL,
  `x`           SMALLINT UNSIGNED NOT NULL,
  `y`           SMALLINT UNSIGNED NOT NULL,
  `z`           SMALLINT UNSIGNED NOT NULL,
  `pixel_x`     TINYINT         NOT NULL DEFAULT 0,
  `pixel_y`     TINYINT         NOT NULL DEFAULT 0,
  `dir`         TINYINT UNSIGNED NOT NULL DEFAULT 2,
  `name`        VARCHAR(128)    DEFAULT NULL,
  `icon_state`  VARCHAR(64)     DEFAULT NULL,
  `extra`       JSON            DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `idx_map_path` (`map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
