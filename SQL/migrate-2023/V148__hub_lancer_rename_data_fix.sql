--
-- Data fix for the Ceres Lance -> Hub Lancer rename (berets.dm,
-- miscellaneous.dm, armor.dm, helmet.dm, modular_armor.dm, modkit.dm and
-- others -- all `name`/`desc` literal changes, no type path renamed).
--
-- ss13_floor_items (persistence_floor_items.dm) is the ONE persistence table
-- that snapshots an item's display `name` as literal text and force-restores
-- it verbatim on load (`if(data["name"]) I.name = data["name"]`) -- every
-- other path (player inventory via ss13_mob_position/applyPersistentInventory,
-- closet contents) restores purely from `type`, so a renamed item picks up
-- its new compile-time name automatically and needs no data fix. Any of these
-- 8 item types that was ever dropped loose on the persistent map's floor
-- would otherwise keep showing its old "Ceres Lance"/"ceres lance" name
-- forever, even after this rename ships.
--
-- REPLACE() rather than an exact match: `\improper`-prefixed names compile
-- to a leading BYOND macro control character before the visible text, so the
-- stored string isn't a clean literal match against the source. Substring
-- replace on just the renamed portion handles that regardless of the prefix,
-- and each UPDATE is scoped by `type` so it can only ever touch rows for the
-- exact item being renamed.
--

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'ceres lance fatigues', 'hub lancer fatigues')
  WHERE `type` = '/obj/item/clothing/under/lance' AND `name` LIKE '%ceres lance fatigues%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'Ceres Lance tactical uniform', 'Hub Lancer tactical uniform')
  WHERE `type` = '/obj/item/clothing/under/rank/lance' AND `name` LIKE '%Ceres Lance tactical uniform%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'ceres lance arm guards', 'hub lancer arm guards')
  WHERE `type` = '/obj/item/clothing/accessory/arm_guard/riot/lancer' AND `name` LIKE '%ceres lance arm guards%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'ceres lance leg guards', 'hub lancer leg guards')
  WHERE `type` = '/obj/item/clothing/accessory/leg_guard/riot/lancer' AND `name` LIKE '%ceres lance leg guards%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'Ceres Lance beret', 'Hub Lancer beret')
  WHERE `type` = '/obj/item/clothing/head/beret/lancer' AND `name` LIKE '%Ceres Lance beret%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'ceres lance helmet', 'hub lancer helmet')
  WHERE `type` = '/obj/item/clothing/head/helmet/riot/lancer' AND `name` LIKE '%ceres lance helmet%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'ceres lance armor plate', 'hub lancer armor plate')
  WHERE `type` = '/obj/item/clothing/accessory/armor_plate/riot/lancer' AND `name` LIKE '%ceres lance armor plate%';

UPDATE `ss13_floor_items` SET `name` = REPLACE(`name`, 'Ceres'' Lance voidsuit kit', 'Hub Lancer voidsuit kit')
  WHERE `type` = '/obj/item/voidsuit_modkit/ceres_lance_unathi' AND `name` LIKE '%Ceres'' Lance voidsuit kit%';
