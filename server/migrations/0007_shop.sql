-- Studio shop, phase 2: a catalogue of studio-approved products, planned drops and Notify me (see ../README.md "Shop").
-- Apply with: npx wrangler d1 migrations apply bruce-autobook --remote   (--local for `wrangler dev`)
--
-- The studio is the seller: Brüce lists what a studio already sells at its desk or in its webshop, and reminds
-- members. No money and no addresses pass through here. Listings are posted by the operator with POST /shop/import
-- once the studio has approved them by email (`consent_at`); production starts empty. Prices are in öre and include
-- VAT, like the Bruce API's. `studio_id` is Bruce's studio id, so the apps join on the studio list they already load.
CREATE TABLE IF NOT EXISTS storefronts (
  studio_id INTEGER PRIMARY KEY,            -- Bruce's studio id
  seller_name TEXT NOT NULL,                -- the seller of record ("Ångan Bastu AB")
  city TEXT NOT NULL,                       -- Bruce city code ("STO"): GET /shop?city= lists by it
  webshop_url TEXT,                         -- the studio's own shop (https); without it the apps say "Ask at the desk"
  stripe_account TEXT,                      -- phase 4: the studio's Stripe Connect account; NULL = no checkout here
  pickup_note TEXT,                         -- "At the desk, weekdays 07–21"
  consent_at TEXT NOT NULL,                 -- the day the studio approved its listing (by email), YYYY-MM-DD
  source TEXT NOT NULL DEFAULT '',          -- who posted it (the feed's `source`); a post replaces that source's storefronts
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS storefronts_city ON storefronts (city);

CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,                      -- the feed's id, lower case with dashes ("angan-bastu-towel")
  studio_id INTEGER NOT NULL REFERENCES storefronts(studio_id) ON DELETE CASCADE,
  title TEXT NOT NULL,                      -- plain text; never a Bruce or Brüce mark
  kind TEXT NOT NULL CHECK (kind IN ('towel', 'mat', 'socks', 'apparel', 'sauna', 'other')),   -- the Shop screen's chips
  description TEXT,                         -- "Organic cotton · 90 × 180 cm"
  price_ore INTEGER NOT NULL,               -- incl. VAT
  vat_rate INTEGER NOT NULL DEFAULT 25,     -- percent; the checkout sheet shows the VAT part
  fulfilment TEXT NOT NULL CHECK (fulfilment IN ('desk', 'link', 'pod')),   -- sold at the desk, in the webshop, or printed to order
  link_url TEXT,                            -- the product's own page in the webshop (https)
  active INTEGER NOT NULL DEFAULT 1,
  sort INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS products_studio ON products (studio_id);

CREATE TABLE IF NOT EXISTS variants (
  id TEXT PRIMARY KEY,                      -- "<product id>:<variant id>"
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  label TEXT NOT NULL,                      -- "Natural", "M", "S/M"
  pod_sku TEXT,                             -- the print partner's SKU (phase 4)
  in_stock INTEGER NOT NULL DEFAULT 1,
  sort INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS variants_product ON variants (product_id);

-- A drop: a pre-order window for one product (a race-day tee, a finisher tee), one print run, picked up at the studio.
CREATE TABLE IF NOT EXISTS drops (
  id TEXT PRIMARY KEY,
  studio_id INTEGER NOT NULL REFERENCES storefronts(studio_id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  challenge_id TEXT,                        -- phase 3: only that challenge's finishers see it
  title TEXT NOT NULL,
  opens_at INTEGER NOT NULL,                -- UTC ms the pre-order window opens
  closes_at INTEGER NOT NULL,               -- UTC ms it closes
  min_qty INTEGER NOT NULL DEFAULT 0,       -- the print run goes ahead from this many ("31 of 40")
  max_qty INTEGER,                          -- the run's size, or NULL
  reserved INTEGER NOT NULL DEFAULT 0,      -- reservations the studio reports (phase 3); paid orders add to it (phase 4)
  pickup_from TEXT,                         -- the day pickup starts, YYYY-MM-DD, once known
  link_url TEXT,                            -- the studio's own payment link for Reserve (phase 3)
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS drops_window ON drops (opens_at, closes_at);

-- Notify me: who wants a push and an email when a drop opens (and when it is ready for pickup).
CREATE TABLE IF NOT EXISTS notify (
  user_id INTEGER NOT NULL,
  drop_id TEXT NOT NULL REFERENCES drops(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, drop_id)
);
CREATE INDEX IF NOT EXISTS notify_drop ON notify (drop_id);

-- Anonymous daily counters: how often a listing was opened (the KPI "item taps per studio-page view"). No user id.
CREATE TABLE IF NOT EXISTS taps (
  product_id TEXT NOT NULL,
  day TEXT NOT NULL,                        -- local YYYY-MM-DD
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (product_id, day)
);
