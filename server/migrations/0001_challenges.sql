-- Challenges with friends, goal reminders and Wrapped percentiles (see ../README.md).
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
-- The `users` table predates migrations; the worker creates it on first use.

-- One challenge between friends. Days are local Europe/Stockholm days (YYYY-MM-DD). A repeating challenge runs
-- month after month; its `end_day` is the end of the first month.
CREATE TABLE IF NOT EXISTS challenges (
  id TEXT PRIMARY KEY,                      -- random, unguessable (also the share link)
  owner_id INTEGER NOT NULL,                -- Bruce user id of the creator
  title TEXT NOT NULL,
  metric TEXT NOT NULL CHECK (metric IN ('classes', 'visits', 'minutes', 'target')),
  target INTEGER,                           -- for metric 'target' ("Everyone hits 12")
  category TEXT,                            -- NULL = everything, 'gym' = drop-ins, else a Bruce category id
  category_title TEXT,
  start_day TEXT NOT NULL,
  end_day TEXT NOT NULL,
  repeat_monthly INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

-- Who is in a challenge. Each friend accepts each challenge separately: until then (status 'invited') nothing of
-- theirs is read or shown.
CREATE TABLE IF NOT EXISTS participants (
  challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'accepted')),
  invited_by INTEGER,
  joined_at TEXT,
  PRIMARY KEY (challenge_id, user_id)
);
CREATE INDEX IF NOT EXISTS participants_user ON participants (user_id);

-- Visits per user and local day, filled by the daily cron from the user's GET /v52/booking history.
-- visits/classes/dropins/minutes: everything counts (bookings, check-ins, drop-ins; deduplicated).
-- checkins/checkin_minutes/studios: checked-in visits only (goal reminders, Wrapped percentiles).
-- detail: JSON array of the day's visits (class, studio, categories), only while the user is in a challenge.
CREATE TABLE IF NOT EXISTS daily_counts (
  user_id INTEGER NOT NULL,
  day TEXT NOT NULL,
  visits INTEGER NOT NULL DEFAULT 0,
  classes INTEGER NOT NULL DEFAULT 0,
  dropins INTEGER NOT NULL DEFAULT 0,
  minutes INTEGER NOT NULL DEFAULT 0,
  checkins INTEGER NOT NULL DEFAULT 0,
  checkin_minutes INTEGER NOT NULL DEFAULT 0,
  studios TEXT NOT NULL DEFAULT '[]',
  detail TEXT,
  PRIMARY KEY (user_id, day)
);
