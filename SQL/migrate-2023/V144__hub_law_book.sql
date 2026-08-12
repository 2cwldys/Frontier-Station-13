--
-- Admin-editable text shown by every printed hub law book
-- (/obj/item/book/hub_laws). Mirrors ss13_faction_raiding_toggle's shape,
-- swapping the boolean for a text column.
--

CREATE TABLE IF NOT EXISTS `ss13_hub_law_text` (
  `id`       TINYINT NOT NULL DEFAULT 1,
  `law_text` MEDIUMTEXT NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
