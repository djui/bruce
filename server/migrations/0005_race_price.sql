-- "Price goes up tomorrow" for races in My races (see ../README.md "Race reminders").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- The device knows the catalog's price steps, the server doesn't: with "Remind me the day before" on, PUT /me/races
-- sends the day the price changes (`priceAt`) and the words of the reminder (`priceBody`), and the minute cron pushes and
-- emails it at 09:00 local the day before, once (`price_sent_at`; a new `price_at` reminds again). A race with only this
-- reminder is stored like one with a race-day reminder, with the same per-device rules and lifetime.
ALTER TABLE user_races ADD COLUMN remind_price INTEGER NOT NULL DEFAULT 0;
ALTER TABLE user_races ADD COLUMN price_at TEXT;          -- local YYYY-MM-DD the entry fee changes
ALTER TABLE user_races ADD COLUMN price_body TEXT;        -- "HYROX Stockholm: 750 SEK until today, 775 SEK from tomorrow. Sign up on hyrox.com."
ALTER TABLE user_races ADD COLUMN price_sent_at INTEGER;  -- UTC ms the reminder went out (or was skipped)
CREATE INDEX IF NOT EXISTS user_races_price ON user_races (price_at);
