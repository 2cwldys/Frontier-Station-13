--
-- Captures the buyer's personal bank account number once, at purchase time
-- (drydockBuy()), so Crew-tagged ship equipment can bill the ship's owner
-- directly even when they're offline later -- there's no reliable way to
-- resolve an arbitrary (ckey, char_name)'s bank account otherwise. Null for
-- faction-owned ships (those bill via faction_debit()/faction_credit() as
-- already).
--

ALTER TABLE `ss13_drydock_ships`
    ADD COLUMN `owner_account_number` INT NULL DEFAULT NULL AFTER `owner_char_name`;
