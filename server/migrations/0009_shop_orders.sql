-- Studio shop, phase 4: checkout and orders (see ../README.md "Shop", "Checkout").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- Payment runs through Stripe Checkout on the studio's own connected account (Stripe Connect): the studio is the
-- merchant of record, gets paid by Stripe and issues the receipt. Brüce holds no money and no address: the order row
-- keeps what the member bought, the status, the Stripe session id and a pickup code. Shipping addresses stay with
-- Stripe and the print partner. Dormant until STRIPE_SECRET_KEY is set and a storefront has a `stripe_account`.
ALTER TABLE storefronts ADD COLUMN shipping_ore INTEGER;   -- shipping incl. VAT when the studio ships ("Ship to me · 49 kr"); NULL = pickup only

CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,                      -- random, unguessable
  user_id INTEGER NOT NULL,
  studio_id INTEGER NOT NULL,               -- the seller
  drop_id TEXT,                             -- the drop it belongs to, if any (counts towards "31 of 40")
  items TEXT NOT NULL,                      -- JSON [{productId, variantId, title, label, qty, unitOre}]
  total_ore INTEGER NOT NULL,               -- what was paid, incl. VAT and shipping
  vat_ore INTEGER NOT NULL,                 -- the VAT inside it
  delivery TEXT NOT NULL CHECK (delivery IN ('pickup', 'ship')),
  status TEXT NOT NULL CHECK (status IN ('paid', 'printing', 'shipped', 'ready', 'delivered', 'collected', 'refunded')),
  stripe_session TEXT UNIQUE,               -- the Checkout Session (the webhook writes the row once per session)
  stripe_account TEXT,                      -- the studio's connected account the charge went to
  pod_order TEXT,                           -- the print partner's order id, once it has one
  pickup_code TEXT,                         -- shown at the desk ("K7P2Q"); NULL for a shipped order
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  ready_sent_at INTEGER                     -- UTC ms "Ready for pickup" (or "Delivered") went out
);
CREATE INDEX IF NOT EXISTS orders_user ON orders (user_id, created_at);
CREATE INDEX IF NOT EXISTS orders_drop ON orders (drop_id);
CREATE INDEX IF NOT EXISTS orders_pod ON orders (pod_order);
