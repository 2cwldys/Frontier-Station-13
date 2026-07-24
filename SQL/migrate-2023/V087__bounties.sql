--
-- Player-posted bounties on a specific character. Reward is escrowed from
-- the poster's personal account at posting time (see post_bounty()), and
-- paid out to whichever accepter lands the killing blow first (see
-- check_bounty_kill(), hooked from /mob/living/carbon/human/death()).
-- Anyone can accept -- any number of people simultaneously -- like a real
-- contract; first one to land the kill wins the payout. No single-accepter
-- lock.
--
-- Target is identified by (target_ckey, target_name) together, not just a
-- name -- one ckey can play several different characters over time (never
-- simultaneously), so the pair is what actually pins down which specific
-- character is being bountied.
--

CREATE TABLE IF NOT EXISTS `ss13_bounties` (
  `id`                    INT NOT NULL AUTO_INCREMENT,
  `map_path`              VARCHAR(64) NOT NULL,
  `poster_ckey`           VARCHAR(32) NOT NULL,
  `poster_account_number` INT NOT NULL,
  `target_ckey`           VARCHAR(32) NOT NULL,
  `target_name`           VARCHAR(128) NOT NULL,
  `reward`                INT NOT NULL,
  `status`                ENUM('open','claimed','cancelled') NOT NULL DEFAULT 'open',
  `accepters`             TEXT NULL,
  `claimed_by_ckey`       VARCHAR(32) NULL,
  `posted_at`             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `claimed_at`            DATETIME NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
