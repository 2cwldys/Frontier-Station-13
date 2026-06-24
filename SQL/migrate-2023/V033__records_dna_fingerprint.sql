ALTER TABLE `ss13_crew_records`
    ADD COLUMN `fingerprint` VARCHAR(64) DEFAULT NULL AFTER `rank`,
    ADD COLUMN `blood_dna`   VARCHAR(64) DEFAULT NULL AFTER `fingerprint`;
