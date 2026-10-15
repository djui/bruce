-- "Skipped a habit" recommendations (see ../README.md). Apply with: npx wrangler d1 migrations apply bruce-autobook --remote

-- The latest broken habit told to each user: planned by the daily cron, pushed by the minute cron at `send_at`
-- (08:00 local), kept after sending so the same break is told once.
CREATE TABLE IF NOT EXISTS nudges (
  user_id INTEGER PRIMARY KEY,
  habit TEXT NOT NULL,                      -- studio|title|weekday|minute of day
  missed_day TEXT NOT NULL,                 -- the local day (YYYY-MM-DD) of the skipped class
  send_at INTEGER NOT NULL,                 -- UTC ms
  sent_at INTEGER,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data TEXT NOT NULL DEFAULT '{}'           -- push payload: {"recommend":[classId, ...]}
);
