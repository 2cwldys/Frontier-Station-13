--
-- Generic per-bot appearance/config blob (JSON), starting with medbot's
-- randomly-rolled first-aid kit type so its sprite/color stays consistent
-- across saves instead of re-rolling every load.
--
ALTER TABLE ss13_persistent_bots
    ADD COLUMN extra VARCHAR(256) NULL;
