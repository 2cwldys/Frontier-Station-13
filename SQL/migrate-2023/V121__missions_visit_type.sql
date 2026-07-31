--
-- Adds "visit" as a third mission_type -- an away-site TEMPLATE visit
-- objective (reuses sector_template_id exactly like "kill"), completes on
-- arrival with no hostiles spawned. See persistence_missions.dm.
--

ALTER TABLE `ss13_missions` MODIFY `mission_type` ENUM('fetch','kill','visit') NOT NULL;
