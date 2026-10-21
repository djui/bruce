-- Race-week and day-before reminders for races in My races (Train for it, see ../README.md "Race reminders").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- My races live on the device. A race is stored here only while the member has a race-day reminder on for it and the
-- server switched on; PUT /me/races replaces the races that device sent, the daily cron drops races that are over, and
-- the rows go with the account (DELETE /me, an expired login). Phase 3 builds on this table: friends going adds who may see the race (a `visibility` column, by
-- ALTER TABLE) and finds the friends on the same race through `race_id`; a race crew is a challenge (0001) that ends
-- on race day.
CREATE TABLE IF NOT EXISTS user_races (
  user_id INTEGER NOT NULL,
  race_id TEXT NOT NULL,                    -- catalog id ("hyrox-stockholm-2026"), or "custom-<uuid>" for a race added by hand
  name TEXT NOT NULL,
  date TEXT NOT NULL,                       -- the member's race day (their day of a multi-day event), local YYYY-MM-DD
  url TEXT,                                 -- the race's own page, linked from the email
  remind_week INTEGER NOT NULL DEFAULT 0,   -- push and email at 08:00 local on the Monday of race week
  remind_eve INTEGER NOT NULL DEFAULT 0,    -- push at 18:00 local the day before
  plan TEXT,                                -- JSON: Train for it settings and the race-week class mix, or NULL
  week_sent_at INTEGER,                     -- UTC ms the race-week reminder went out (or was skipped): each is sent once
  eve_sent_at INTEGER,
  source TEXT NOT NULL DEFAULT '',          -- the device or browser that sent it: My races are per device, and each one's
                                            -- PUT /me/races replaces only its own races
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, race_id)
);
CREATE INDEX IF NOT EXISTS user_races_date ON user_races (date);
CREATE INDEX IF NOT EXISTS user_races_race ON user_races (race_id);
