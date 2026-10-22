// Studio shop (Shared/BruceCore/Shop.swift), as pure functions on plain objects (tests in test/shop.test.js); shopui.js
// draws them. The studio is the seller: Brüce lists what it approved (our server's GET /shop?city=), shows planned
// drops with Notify me and reminds. Prices are in öre incl. VAT; no address and no money pass through here, and no
// product carries a Bruce or Brüce mark. Sample listings (Shared/BruceCore/SampleShop.swift; "Sample shop" below) are made
// in the browser from the member's own studios, flagged `sample`, and never leave it.

/** The Shop screen's chips, in this order. */
export const KINDS = [
  ['towel', 'Towels', 'spa'], ['mat', 'Mats', 'yoga'], ['socks', 'Grip socks', 'walk'], ['apparel', 'Apparel', 'brief'], ['sauna', 'Sauna', 'flame'], ['other', 'Other', 'gift'],
];
export const kindTitle = (k) => (KINDS.find((x) => x[0] === k) || [k, k])[1];
export const kindIcon = (k) => (KINDS.find((x) => x[0] === k) || [k, k, 'gift'])[2];
const FULFILMENTS = ['desk', 'link', 'pod'];

/** https links only (the studio's webshop, a payment link); anything else is dropped. */
export function httpsUrl(s) {
  try { const u = new URL(s); return u.protocol === 'https:' && u.host ? u.href : null; } catch (e) { return null; }
}

/** The catalogue as the apps need it, skipping entries they can't read (a new kind, say) instead of failing the answer. */
export function decode(json) {
  const fronts = ((json && json.storefronts) || []).filter((s) => s && Number.isInteger(s.studioId) && typeof s.sellerName === 'string' && typeof s.consentAt === 'string')
    .map((s) => Object.assign({ city: '', webshopUrl: null, pickupNote: null, checkout: false, shippingOre: null }, s, { checkout: s.checkout === true, shippingOre: Number.isInteger(s.shippingOre) && s.shippingOre >= 0 ? s.shippingOre : null, sample: false }));
  const ids = new Set(fronts.map((s) => s.studioId));
  const products = ((json && json.products) || []).filter((p) => p && typeof p.id === 'string' && ids.has(p.studioId) && typeof p.title === 'string'
    && KINDS.some((k) => k[0] === p.kind) && Number.isInteger(p.priceOre) && p.priceOre >= 0 && FULFILMENTS.includes(p.fulfilment))
    .map((p) => Object.assign({ description: null, vatRate: 25, linkUrl: null }, p, {
      variants: (Array.isArray(p.variants) ? p.variants : []).filter((v) => v && typeof v.id === 'string' && typeof v.label === 'string').map((v) => Object.assign({ inStock: true }, v)), sample: false }));
  const pids = new Set(products.map((p) => p.id));
  const drops = ((json && json.drops) || []).filter((d) => d && typeof d.id === 'string' && pids.has(d.productId) && typeof d.title === 'string'
    && Number.isFinite(d.opensAt) && Number.isFinite(d.closesAt) && d.closesAt > d.opensAt)
    .map((d) => Object.assign({ challengeId: null, minQty: 0, maxQty: null, reserved: 0, pickupFrom: null, linkUrl: null, ready: false, unlocked: false }, d, { sample: false }));
  return { city: (json && json.city) || '', storefronts: fronts, products, drops };
}
/** The member's unlocked drops and their products (GET /me/shop) laid over the public catalogue, by id. */
export function merge(c, mine) {
  const out = { city: c.city, storefronts: c.storefronts.slice(), products: c.products.slice(), drops: c.drops.slice() };
  const extra = decode({ storefronts: c.storefronts, products: (mine && mine.products) || [], drops: (mine && mine.drops) || [] });
  for (const p of extra.products) if (!out.products.some((x) => x.id === p.id)) out.products.push(p);
  for (const d of extra.drops) { const i = out.drops.findIndex((x) => x.id === d.id); if (i >= 0) out.drops[i] = d; else out.drops.push(d); }
  return out;
}
export const EMPTY = { city: '', storefronts: [], products: [], drops: [] };

/** Nothing listed: the apps then show no shop at all. */
export const isEmpty = (c) => !c || !c.products.length;
export const storefront = (c, studioId) => (c ? c.storefronts.find((s) => s.studioId === studioId) || null : null);
export const product = (c, id) => (c ? c.products.find((p) => p.id === id) || null : null);
export const productsFor = (c, studioId) => (c ? c.products.filter((p) => p.studioId === studioId) : []);
export const dropFor = (c, productId) => (c ? c.drops.find((d) => d.productId === productId) || null : null);
/** The chips: the kinds that have a product, in the chips' order. */
export const kinds = (c) => KINDS.filter(([k]) => c && c.products.some((p) => p.kind === k)).map(([k]) => k);
export const filtered = (c, kind) => (c ? (kind ? c.products.filter((p) => p.kind === kind) : c.products) : []);
/** A studio lists a towel (the "Forgot your towel?" card after a check-in at a Wellness studio). */
export const towelFor = (c, studioId) => productsFor(c, studioId).find((p) => p.kind === 'towel') || null;

/** "upcoming" before the window, "open" in it, "closed" after, "ready" once the studio has it at the desk. */
export function dropState(d, now) {
  if (d.ready) return 'ready';
  if (now < d.opensAt) return 'upcoming';
  return now < d.closesAt ? 'open' : 'closed';
}
/** Drops not over yet (or ready at the desk), soonest closing first. */
export const liveDrops = (c, now) => (c ? c.drops.filter((d) => dropState(d, now) !== 'closed').sort((a, b) => a.closesAt - b.closesAt) : []);
/** Home's drop card: an unlocked drop first (it is the member's), then a real drop closing first, then a sample. */
export const homeDrop = (c, now) => liveDrops(c, now).find((d) => d.unlocked) || liveDrops(c, now).find((d) => !d.sample) || liveDrops(c, now)[0] || null;
/** The drop a finished challenge unlocked, if the member has it. */
export const dropForChallenge = (c, id) => (c ? c.drops.find((d) => d.challengeId === id && d.unlocked) || null : null);
/** Reserve (phase 3): the studio's own checkout, while the window is open. The studio sells; Brüce only links. */
export const reserveUrl = (d, now) => (dropState(d, now) === 'open' ? httpsUrl(d.linkUrl) : null);
/** The run's goal: its size, else the minimum; "31 of 40", or "31 reserved" without a goal. */
export const dropGoal = (d) => d.maxQty || d.minQty || 0;
export const progressText = (d) => (dropGoal(d) > 0 ? d.reserved + ' of ' + dropGoal(d) : d.reserved + ' reserved');
export const progress = (d) => (dropGoal(d) > 0 ? Math.min(1, d.reserved / dropGoal(d)) : 0);

/** "2 d 14 h", "3 h", "25 min"; "" once the moment has passed. */
export function untilText(ms, now) {
  const left = ms - now;
  if (left <= 0) return '';
  const d = Math.floor(left / 86400000), h = Math.floor((left % 86400000) / 3600000), m = Math.floor((left % 3600000) / 60000);
  if (d > 0) return d + ' d ' + h + ' h';
  if (h > 0) return h + ' h';
  return Math.max(1, m) + ' min';
}
/** "Closes in 2 d 14 h", "Opens in 5 d 3 h", "Closed", "Ready for pickup". */
export function countdownText(d, now) {
  const s = dropState(d, now);
  if (s === 'upcoming') return 'Opens in ' + untilText(d.opensAt, now);
  if (s === 'open') return 'Closes in ' + untilText(d.closesAt, now);
  return s === 'ready' ? READY : 'Closed';
}
export const READY = 'Ready for pickup';
/** "Ready at the desk: Kärnan Reformer AB, at the desk, weekdays 06–20." */
export function readyBody(front) {
  if (!front) return 'Ready at the desk.';
  return 'Ready at the desk: ' + front.sellerName + (front.pickupNote ? ', ' + front.pickupNote[0].toLowerCase() + front.pickupNote.slice(1) : '') + '.';
}
/** "Only for people who hit 20. One print run, picked up at Kärnan Reformer. Pre-order until Sun 7 Feb." */
export function finisherBody(c, studio, d) {
  const who = c.metric === 'target' ? 'Only for people who hit ' + c.target + '.' : 'Only for people who took part to the end.';
  return who + ' One print run, picked up at ' + studio + '. Pre-order until ' + shortDay(d.closesAt) + '.';
}
export const FINISHER_HINT = 'Only for people who finished this challenge.';
export const RESERVE_HINT = "Reserve opens the studio's own checkout. The studio sells it and hands it out at the desk; Brüce only links and reminds.";
export const RESERVE_DESK = 'Reserve at the desk: the studio takes the pre-order itself.';
export const DROP_CLOSED = 'The pre-order has closed.';
const shortDay = (ms) => new Date(ms).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Stockholm' });
const dayOf = (key) => new Date(key + 'T12:00:00Z').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
/** "Pre-order until Sun 7 Feb · one print run · pickup from Sat 20 Feb". */
export function dropLine(d) {
  return ['Pre-order until ' + shortDay(d.closesAt), 'one print run', d.pickupFrom ? 'pickup from ' + dayOf(d.pickupFrom) : null].filter(Boolean).join(' · ');
}

/** "449 kr", "1,295 kr": whole kronor, as the prices on the pages. */
export const kr = (ore) => Math.round(ore / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' kr';
/** "449,00 kr", "89,80 kr": the checkout rows. */
export function krExact(ore) {
  const a = Math.abs(ore);
  return (ore < 0 ? '-' : '') + Math.floor(a / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ',' + String(a % 100).padStart(2, '0') + ' kr';
}
/** The VAT inside a price that includes it: 449 kr at 25% holds 89,80 kr. */
export const vatPart = (ore, rate) => Math.round(ore - ore / (1 + rate / 100));

/** "Sold by Ångan Bastu AB. Pay at the desk." / "Sold by Yogaloft Södermalm AB." */
export const soldBy = (seller, desk, checkout) => (checkout ? 'Sold by ' + seller + '. Pay here or at the desk.' : desk ? 'Sold by ' + seller + '. Pay at the desk.' : 'Sold by ' + seller + '.');
/** Under "Forgot your towel?". */
export const towelBody = (towel) => 'Rent one at the desk, or take a ' + towel.title.toLowerCase() + ' home for ' + kr(towel.priceOre) + '.';
export const NOT_AFFILIATED = "The studio is the seller: prices, stock and returns are theirs. Brüce lists what the studio approved and reminds you; it never holds money or your address.";
export const CATALOG_FOOTER = 'Products are listed with each studio\'s written approval, in kronor incl. 25% VAT. Pickup at the desk comes first; Brüce never holds money or addresses.';
export const NOTIFY_HINT = 'A push to the Brüce iPhone app and an email from our server when the pre-order opens. Nothing is reserved for you.';

// ---------------------------------------------------------------- checkout (phase 4)

/** Buy is offered only where the server has a Stripe key and the studio a connected account (`storefront.checkout`). */
export const canBuy = (c, p) => { const f = p && storefront(c, p.studioId); return !!(f && f.checkout); };
export const ships = (front) => !!front && front.shippingOre != null;
export const MAX_QTY = 5;
export const DELIVERIES = ['pickup', 'ship'];

/** The sums of a draft {product, storefront, variant, qty, delivery}: prices incl. VAT, shipping where the studio ships. */
export function totals(d) {
  const subtotalOre = d.product.priceOre * d.qty;
  const shippingOre = d.delivery === 'ship' ? d.storefront.shippingOre || 0 : 0;
  const totalOre = subtotalOre + shippingOre;
  return { subtotalOre, shippingOre, totalOre, vatOre: vatPart(totalOre, d.product.vatRate == null ? 25 : d.product.vatRate) };
}
/** "Bastu towel · Natural × 2". */
export const itemLine = (title, label, qty) => title + (label ? ' · ' + label : '') + (qty > 1 ? ' × ' + qty : '');
/** Why a draft can't go to Stripe yet; null when it can. */
export function draftProblem(d) {
  if (!d.storefront || !d.storefront.checkout) return NO_CHECKOUT;
  if (d.product.variants.length && !d.variant) return PICK_VARIANT;
  if (d.variant && !d.variant.inStock) return OUT_OF_STOCK;
  if (d.delivery === 'ship' && !ships(d.storefront)) return NO_SHIPPING;
  if (!(d.qty >= 1 && d.qty <= MAX_QTY)) return '1 to ' + MAX_QTY + ' of each';
  return null;
}
/** The first in-stock variant picked, pickup by default (what the checkout sheet starts with). */
export function draft(c, p, opts) {
  const front = storefront(c, p.studioId);
  if (!front) return null;
  const o = opts || {};
  const variant = p.variants.find((v) => v.id === o.variantId && v.inStock) || p.variants.find((v) => v.inStock) || null;
  return { product: p, storefront: front, variant, qty: 1, delivery: ships(front) && o.delivery === 'ship' ? 'ship' : 'pickup' };
}
/** What POST /checkout takes. */
export const checkoutBody = (d) => Object.assign({ productId: d.product.id, qty: d.qty, delivery: d.delivery, returnTo: 'web' }, d.variant ? { variantId: d.variant.id } : {});

/** An order's status as the apps word it (the server sends `statusText` too; this is the fallback). */
export function orderStatusText(status, delivery) {
  switch (status) {
    case 'paid': return delivery === 'ship' ? 'Paid · being prepared' : 'Paid · being prepared for pickup';
    case 'printing': return 'Being printed';
    case 'shipped': return delivery === 'ship' ? 'On its way' : 'On its way to the studio';
    case 'ready': return 'Ready for pickup';
    case 'delivered': return 'Delivered';
    case 'collected': return 'Collected';
    case 'refunded': return 'Refunded';
    default: return status;
  }
}
export const orderLine = (o) => o.statusText || orderStatusText(o.status, o.delivery);
export const isReady = (o) => o.status === 'ready';
export const isDone = (o) => ['collected', 'delivered', 'refunded'].includes(o.status);
/** GET /me/orders as the sheet needs it: broken rows skipped, newest first. */
export function decodeOrders(json) {
  return ((json && json.orders) || []).filter((o) => o && typeof o.id === 'string' && Number.isInteger(o.totalOre) && typeof o.status === 'string' && typeof o.createdAt === 'string')
    .map((o) => Object.assign({ items: [], vatOre: 0, delivery: 'pickup', pickupCode: null, sellerName: null, pickupNote: null, statusText: null, dropId: null }, o,
      { items: (Array.isArray(o.items) ? o.items : []).filter((i) => i && typeof i.title === 'string').map((i) => Object.assign({ label: null, qty: 1, unitOre: 0 }, i)) }))
    .sort((a, b) => (a.createdAt < b.createdAt ? 1 : a.createdAt > b.createdAt ? -1 : 0));
}

export const HOW_TITLE = 'How do you want it?';
export const PICKUP_FREE = 'Free · at the desk';
export const pickupAt = (studio) => 'Pick up at ' + studio;
export const shipPrice = (front) => 'Ship to me · ' + kr(front.shippingOre || 0);
export const SHIP_NOTE = '2–4 days · the address goes to Stripe';
export const PAY_METHODS = 'Apple Pay, Swish, Klarna or card, as the studio set up';
export const PAY_SAFETY = "Payment by Stripe on the studio's account. Brüce never sees your card or address. Menu › Orders shows your pickup code.";
export const RETURN_NOTE = 'Receipt and withdrawal form come by email from the studio.';
export const sellerLine = (front, vicinity) => 'Seller: ' + front.sellerName + (vicinity ? ', ' + vicinity : '') + '. ' + RETURN_NOTE;
export const vatLine = (rate) => 'incl. VAT ' + rate + '%';
export const NO_CHECKOUT = 'This studio has no checkout in Brüce yet: ask at the desk or use its webshop.';
export const PICK_VARIANT = 'Pick a size or option first.';
export const OUT_OF_STOCK = 'That option is out of stock.';
export const NO_SHIPPING = 'This studio does not ship: pick it up at the desk.';
export const ORDERS_EMPTY = "Nothing bought yet. What you buy from a studio's shop shows up here with its pickup code.";
export const ORDERS_NOTE = 'The studio is the seller and sends the receipt. Brüce keeps what you bought, the status and your pickup code; never a card or an address.';
export const PAID_OPEN = 'Back from Stripe. Your order shows here once Stripe confirms the payment, usually within a minute.';
export const DEMO_CHECKOUT = 'Demo: Stripe Checkout would open now (offline, nothing sent)';

// ---------------------------------------------------------------- sample shop (SampleShop.swift)

export const SAMPLE_PREFIX = 'sample-';
export const isSampleId = (id) => typeof id === 'string' && id.startsWith(SAMPLE_PREFIX);
export const SAMPLE_TAG = 'Sample';
export const SAMPLE_TOAST = 'Sample item, not for sale';
export const SAMPLE_NOTE = 'Sample items to preview the shop. Not for sale. Settings › Show sample shop turns them off.';
export const SAMPLE_PRODUCT_NOTE = 'A sample item to preview the shop. The studio does not sell it and nothing here can be bought.';
export const SAMPLE_SETTING = 'Show sample shop';
export const SAMPLE_SETTING_NOTE = 'Sample items on your own studios, to preview the shop. They are not for sale and never leave this device.';

/** Any sample listing in it (the Shop screen then says so at the top), and anything real (only then the footer says the
 *  studios approved the listings). */
export const hasSamples = (c) => !!c && c.products.some((p) => p.sample);
export const hasReal = (c) => !!c && c.products.some((p) => !p.sample);

/** "STC Rosenlundsparken": the name starts with STC as a word. */
export const isSTC = (name) => /^stc(?![\p{L}])/iu.test(String(name || '').trim());

/** Which studios the samples sit on: the yoga studio visited most, else a favourite one, else the nearest; the same among
 *  STC studios; and the studio whose Hyrox classes (or Hyrox category) were visited most, else a favourite, else the nearest
 *  that runs Hyrox. All in the member's city; ties go to the nearer studio, then the lower id. A studio with a real storefront
 *  (`listed`) keeps its own listings. `i`: {studios: [{id, name, cityId, cats: [titles]}], cityId, visits: {id: n},
 *  hyroxVisits: {id: n}, hyroxClassStudios: [ids], favourites: [ids], distances: {id: metres}, listed: [ids]}. */
export function samplePicks(i) {
  const fav = new Set(i.favourites || []), listed = new Set(i.listed || []), hx = new Set(i.hyroxClassStudios || []);
  const visits = i.visits || {}, hyrox = i.hyroxVisits || {}, dist = i.distances || {};
  const city = (i.studios || []).filter((s) => (s.cityId == null ? i.cityId : s.cityId) === i.cityId && !listed.has(s.id));
  const has = (s, word) => (s.cats || []).some((c) => String(c).toLowerCase().includes(word));
  const near = (a, b) => { const da = dist[a.id] == null ? Infinity : dist[a.id], db = dist[b.id] == null ? Infinity : dist[b.id]; return da !== db ? da - db : a.id - b.id; };
  const best = (list, score) => {
    const went = list.filter((s) => score(s) > 0).sort((a, b) => score(b) - score(a) || near(a, b));
    if (went.length) return went[0].id;
    const favs = list.filter((s) => fav.has(s.id)).sort(near);
    if (favs.length) return favs[0].id;
    const nearest = list.slice().sort(near)[0];
    return nearest ? nearest.id : null;
  };
  const visited = (s) => visits[s.id] || 0;
  return {
    yoga: best(city.filter((s) => has(s, 'yoga')), visited),
    gym: best(city.filter((s) => isSTC(s.name)), visited),
    hyrox: best(city.filter((s) => has(s, 'hyrox') || hx.has(s.id) || (hyrox[s.id] || 0) > 0), (s) => (hyrox[s.id] || 0) * 1000 + visited(s)),
  };
}

/** The sample catalogue for the picked studios, in kronor incl. VAT. The seller is the studio itself, under its own name;
 *  every storefront, product and drop carries `sample`. The race-day tee is open, 31 of 40 reserved. */
export function sampleCatalog(picks, studioName, city, now) {
  const c = { city: city || '', storefronts: [], products: [], drops: [] };
  const add = (studio, slug, title, kind, description, kr, fulfilment, sizes) => {
    if (!c.storefronts.some((f) => f.studioId === studio)) {
      c.storefronts.push({ studioId: studio, sellerName: studioName(studio), city: c.city, webshopUrl: null, pickupNote: null, consentAt: '', checkout: false, shippingOre: null, sample: true });
    }
    c.products.push({ id: SAMPLE_PREFIX + studio + '-' + slug, studioId: studio, title, kind, description, priceOre: kr * 100, vatRate: 25, fulfilment: fulfilment || 'desk', linkUrl: null,
      variants: (sizes || []).map((l) => ({ id: l.toLowerCase().replace('/', '-'), label: l, inStock: true })), sample: true });
  };
  if (picks.yoga != null) {
    add(picks.yoga, 'cork-mat', 'Cork yoga mat', 'mat', 'Natural cork on rubber · 183 × 61 cm · 4 mm', 795, 'link');
    add(picks.yoga, 'grip-socks', 'Grip socks', 'socks', 'Cotton with silicone grip · 2-pack', 149, 'desk', ['S/M', 'L/XL']);
    add(picks.yoga, 'mat-towel', 'Mat towel', 'towel', 'Microfibre with grip dots · 183 × 63 cm', 299);
  }
  if (picks.gym != null) {
    add(picks.gym, 'gym-towel', 'Gym towel', 'towel', 'Quick-dry microfibre · 50 × 100 cm', 199);
    add(picks.gym, 'shaker', 'Shaker bottle', 'other', '700 ml, leak-proof lid', 129);
    add(picks.gym, 'lifting-straps', 'Lifting straps', 'other', 'Cotton with a padded wrist loop · pair', 179);
  }
  if (picks.hyrox != null) {
    const h = picks.hyrox, t = now == null ? Date.now() : now;
    add(h, 'race-day-tee', 'Race-day tee', 'apparel', 'Organic cotton, printed in the EU · unisex', 349, 'pod', ['XS', 'S', 'M', 'L', 'XL']);
    add(h, 'grip-gloves', 'Grip gloves', 'other', 'Padded palm, open fingers · for pull-ups and wall balls', 249);
    const day = new Date(t); day.setUTCDate(day.getUTCDate() + 12);
    c.drops.push({ id: SAMPLE_PREFIX + h + '-race-day', studioId: h, productId: SAMPLE_PREFIX + h + '-race-day-tee', challengeId: null, title: 'Race-day tee',
      opensAt: t - 5 * 86400000, closesAt: t + 2 * 86400000 + 14 * 3600000, minQty: 25, maxQty: 40, reserved: 31, pickupFrom: day.toISOString().slice(0, 10), linkUrl: null, ready: false, unlocked: false, sample: true });
  }
  return c;
}

/** Sample listings after the real ones; a studio with a real storefront keeps only its own. */
export function overlay(real, samples) {
  if (isEmpty(samples)) return real;
  const base = real || { city: samples.city, storefronts: [], products: [], drops: [] };
  const taken = new Set(base.storefronts.map((f) => f.studioId));
  const fronts = samples.storefronts.filter((f) => !taken.has(f.studioId));
  const ids = new Set(fronts.map((f) => f.studioId));
  return { city: base.city || samples.city, storefronts: base.storefronts.concat(fronts), products: base.products.concat(samples.products.filter((p) => ids.has(p.studioId))),
    drops: base.drops.concat(samples.drops.filter((d) => ids.has(d.studioId))) };
}
