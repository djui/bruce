-- Friends going and race crews (Phase 3 of the race events, see ../README.md "Friends going" and "Race crews").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- Going is opt-in per race: a race in My races is shared only when the member switches "Show friends I'm going" on
-- (PUT /me/races `going`), and only catalog races can be shared (a race added by hand has no shared record). Who may see
-- it: the member's Bruce friends who share a race themselves (GET /races/going checks the caller's friends with Bruce).
-- The row holds the user id, the race id and this column; it goes when the member switches it off, removes the race,
-- the race is over (the daily cron), or with the account (DELETE /me, an expired login).
ALTER TABLE user_races ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'friends'));
-- When the member last flipped going for the race (UTC ms, from the device): going is the member's, not a device's, so
-- on PUT /me/races the switch flipped last wins and a device that has not heard of a change cannot undo it.
ALTER TABLE user_races ADD COLUMN going_at INTEGER;

-- A race crew is a challenge (0001) that ends on race day: `race_id` is the catalog race it trains for and `weekly`
-- the sessions each member aims for per week (Monday to Sunday). Its metric is 'visits' (everything counts), so an app
-- that does not know crews shows it as a "Most visits" challenge. NULL for every other challenge.
ALTER TABLE challenges ADD COLUMN race_id TEXT;
ALTER TABLE challenges ADD COLUMN weekly INTEGER;
CREATE INDEX IF NOT EXISTS challenges_race ON challenges (race_id);

-- The crew's Sunday push ("4 of 5 hit their 4 sessions this week"), one row per crew and week (the week's Monday),
-- written before the push goes out so it is sent once (like nudges and race reminders). Goes with the crew.
CREATE TABLE IF NOT EXISTS crew_updates (
  challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  week TEXT NOT NULL,                       -- local YYYY-MM-DD of the week's Monday
  sent_at INTEGER NOT NULL,                 -- UTC ms
  PRIMARY KEY (challenge_id, week)
);
