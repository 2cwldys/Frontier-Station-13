--
-- Tracks whether a personal Idris account's owner has ever been shown the
-- account-info/PIN-setup popup (card.dm's dispense_faction_id/
-- print_replacement/do_print_replacement) -- most accounts are actually
-- minted silently at roundstart (job.dm's setup_account()), so gating that
-- popup on "account created just now" almost never fired it. This flag lets
-- it fire exactly once ever, regardless of whether the account itself was
-- already there.
--

ALTER TABLE `ss13_money_accounts`
	ADD COLUMN `intro_shown` TINYINT(1) NOT NULL DEFAULT 0;
