--
-- founder_ckey: the faction's original founder, set once at founding and
-- never reassigned -- the one identity that survives even a full Panic
-- Purge (faction_manage.dm), so a founder who loses rank-2 access by
-- revoking their own master-card-derived rank can still always recover it
-- via the founder-gated "Print Master Card" action. Factions founded before
-- this migration, or created via the admin "create faction" verb (no
-- player founder), simply have founder_ckey = NULL.
--
-- master_card_lost: whether the faction's master card is currently
-- considered lost/compromised (set TRUE by Panic Purge, cleared FALSE when
-- the founder prints a replacement) -- gates that same action so a fresh
-- master card can't be minted while the existing one is still presumably
-- valid and in someone's hands.
--

ALTER TABLE `ss13_factions` ADD COLUMN `founder_ckey` VARCHAR(32) NULL;
ALTER TABLE `ss13_faction_accounts` ADD COLUMN `master_card_lost` TINYINT(1) NOT NULL DEFAULT 0;
