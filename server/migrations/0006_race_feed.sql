-- Organiser race feeds (phase 3 of the race events, see ../README.md "Race feed").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- A partner organiser (or a hand-run script) posts its races to POST /races/import in the catalog's own schema
-- (docs/app/races.json, README.md "Race catalog"), one source at a time; the rows replace that source's earlier ones.
-- GET /races serves every imported race, and the apps lay them over the published catalog (a feed race wins when its
-- `checkedOn` is as new or newer). No organiser posts yet: the table holds whatever was imported by hand.
CREATE TABLE IF NOT EXISTS race_feed (
  race_id TEXT PRIMARY KEY,                 -- the race's catalog id ("hyrox-stockholm-2026")
  source TEXT NOT NULL,                     -- who posted it ("hyrox", "marathongruppen"), lower case with dashes
  race TEXT NOT NULL,                       -- the race as JSON, exactly one entry of races.json
  imported_at INTEGER NOT NULL              -- UTC ms
);
CREATE INDEX IF NOT EXISTS race_feed_source ON race_feed (source);
