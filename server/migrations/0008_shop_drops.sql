-- Studio shop, phase 3: drops (see ../README.md "Shop", "Drops").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- The minute cron sends "Drop open" by push and email to a drop's Notify me list when its window opens, and "Ready for
-- pickup" once the operator marks the drop ready in the feed (`ready: true`), each once. A drop tied to a challenge
-- (`challenge_id`, 0007) is shown only to that challenge's finishers (GET /me/shop). Reserve opens the studio's own
-- payment link (`link_url`, 0007): the studio sells, nothing is reserved here.
ALTER TABLE drops ADD COLUMN opened_sent_at INTEGER;   -- UTC ms "Drop open" went out (or was skipped as too late)
ALTER TABLE drops ADD COLUMN ready_at INTEGER;         -- UTC ms the operator marked it ready for pickup; NULL until then
ALTER TABLE drops ADD COLUMN ready_sent_at INTEGER;    -- UTC ms "Ready for pickup" went out
