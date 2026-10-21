// Studio shop (Shared/BruceCore/Shop.swift), as pure functions on plain objects (tests in test/shop.test.js); shopui.js
// draws them. The studio is the seller: Brüce lists what it approved (our server's GET /shop?city=), shows planned
// drops with Notify me and reminds. Prices are in öre incl. VAT; no address and no money pass through here, and no
// product carries a Bruce or Brüce mark.

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
    .map((s) => Object.assign({ city: '', webshopUrl: null, pickupNote: null }, s));
  const ids = new Set(fronts.map((s) => s.studioId));
  const products = ((json && json.products) || []).filter((p) => p && typeof p.id === 'string' && ids.has(p.studioId) && typeof p.title === 'string'
    && KINDS.some((k) => k[0] === p.kind) && Number.isInteger(p.priceOre) && p.priceOre >= 0 && FULFILMENTS.includes(p.fulfilment))
    .map((p) => Object.assign({ description: null, vatRate: 25, linkUrl: null }, p, {
      variants: (Array.isArray(p.variants) ? p.variants : []).filter((v) => v && typeof v.id === 'string' && typeof v.label === 'string').map((v) => Object.assign({ inStock: true }, v)) }));
  const pids = new Set(products.map((p) => p.id));
  const drops = ((json && json.drops) || []).filter((d) => d && typeof d.id === 'string' && pids.has(d.productId) && typeof d.title === 'string'
    && Number.isFinite(d.opensAt) && Number.isFinite(d.closesAt) && d.closesAt > d.opensAt)
    .map((d) => Object.assign({ challengeId: null, minQty: 0, maxQty: null, reserved: 0, pickupFrom: null, linkUrl: null, ready: false, unlocked: false }, d));
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
/** Home's drop card: an unlocked drop first (it is the member's), else the live drop closing first. */
export const homeDrop = (c, now) => liveDrops(c, now).find((d) => d.unlocked) || liveDrops(c, now)[0] || null;
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
export const soldBy = (seller, desk) => (desk ? 'Sold by ' + seller + '. Pay at the desk.' : 'Sold by ' + seller + '.');
/** Under "Forgot your towel?". */
export const towelBody = (towel) => 'Rent one at the desk, or take a ' + towel.title.toLowerCase() + ' home for ' + kr(towel.priceOre) + '.';
export const NOT_AFFILIATED = "The studio is the seller: prices, stock and returns are theirs. Brüce lists what the studio approved and reminds you; it never holds money or your address.";
export const CATALOG_FOOTER = 'Products are listed with each studio\'s written approval, in kronor incl. 25% VAT. Pickup at the desk comes first; Brüce never holds money or addresses.';
export const NOTIFY_HINT = 'A push to the Brüce iPhone app and an email from our server when the pre-order opens. Nothing is reserved for you.';
