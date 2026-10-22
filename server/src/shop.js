// Studio shop (phase 2 of the Studio Merch plan): the pure parts of the catalogue. The studio is the seller; Brüce
// lists what it approved, shows planned drops and reminds members (worker.js `shopRoute`, `shopImportRoute`).
// Same rules as the apps (Shared/BruceCore/Shop.swift, docs/app/js/shop.js): prices in öre incl. VAT, no addresses,
// no Bruce or Brüce marks on anything listed.

export const KINDS = ["towel", "mat", "socks", "apparel", "sauna", "other"];
export const FULFILMENTS = ["desk", "link", "pod"];
export const MAX_STOREFRONTS = 100;
export const MAX_PRODUCTS = 40;
export const MAX_VARIANTS = 20;
export const MAX_DROPS = 10;

const ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const isId = (s) => typeof s === "string" && ID.test(s) && s.length <= 80;
const isDay = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(s + "T12:00:00Z").toISOString().slice(0, 10) === s;
const isHttps = (s) => typeof s === "string" && /^https:\/\/[^\s]+$/.test(s) && s.length <= 300;
const text = (s, max) => (typeof s === "string" && s.trim() ? s.trim().slice(0, max) : null);
/** "Bruce" and "Brüce" never go on a product: the marks belong to Bruce Studios AB (README.md "Notice and trademarks"). */
const MARK = /br[uü]ce/i;

/** One variant as the apps need it; null when unreadable. */
export function cleanVariant(v, i = 0) {
  if (!v || typeof v !== "object" || !isId(v.id)) return null;
  const label = text(v.label, 40);
  if (!label) return null;
  return { id: v.id, label, podSku: text(v.podSku, 80), inStock: v.inStock !== false, sort: Number.isInteger(v.sort) ? v.sort : i };
}

/** One product; null when unreadable or when its title carries a Bruce mark. Variants it can't read are dropped. */
export function cleanProduct(p, i = 0) {
  if (!p || typeof p !== "object" || !isId(p.id)) return null;
  const title = text(p.title, 80);
  if (!title || MARK.test(title) || !KINDS.includes(p.kind) || !FULFILMENTS.includes(p.fulfilment)) return null;
  if (!Number.isInteger(p.priceOre) || p.priceOre < 0 || p.priceOre > 100_000_00) return null;
  const vat = p.vatRate == null ? 25 : p.vatRate;
  if (!Number.isInteger(vat) || vat < 0 || vat > 100) return null;
  const linkUrl = p.linkUrl == null ? null : isHttps(p.linkUrl) ? p.linkUrl : undefined;
  if (linkUrl === undefined) return null;
  const variants = [];
  for (const [j, v] of (Array.isArray(p.variants) ? p.variants : []).entries()) {
    const c = cleanVariant(v, j);
    if (c && !variants.some((x) => x.id === c.id)) variants.push(c);
    if (variants.length >= MAX_VARIANTS) break;
  }
  return { id: p.id, title, kind: p.kind, description: text(p.description, 240), priceOre: p.priceOre, vatRate: vat, fulfilment: p.fulfilment,
           linkUrl, active: p.active !== false, sort: Number.isInteger(p.sort) ? p.sort : i, variants };
}

/** One drop; null when unreadable (a window that closes before it opens, an unknown product). */
export function cleanDrop(d, productIds, i = 0) {
  if (!d || typeof d !== "object" || !isId(d.id) || !isId(d.productId) || !productIds.includes(d.productId)) return null;
  const title = text(d.title, 80);
  const opensAt = Date.parse(d.opensAt), closesAt = Date.parse(d.closesAt);
  if (!title || MARK.test(title) || !Number.isFinite(opensAt) || !Number.isFinite(closesAt) || closesAt <= opensAt) return null;
  const n = (v, max) => (v == null ? null : Number.isInteger(v) && v >= 0 && v <= max ? v : NaN);
  const minQty = n(d.minQty, 10_000) ?? 0, maxQty = n(d.maxQty, 10_000), reserved = n(d.reserved, 100_000) ?? 0;
  if (Number.isNaN(minQty) || Number.isNaN(maxQty) || Number.isNaN(reserved)) return null;
  if (d.pickupFrom != null && !isDay(d.pickupFrom)) return null;
  if (d.linkUrl != null && !isHttps(d.linkUrl)) return null;
  const challengeId = d.challengeId == null ? null : typeof d.challengeId === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(d.challengeId) ? d.challengeId : undefined;
  if (challengeId === undefined) return null;
  return { id: d.id, productId: d.productId, challengeId, title, opensAt, closesAt, minQty, maxQty, reserved, pickupFrom: d.pickupFrom ?? null,
           linkUrl: d.linkUrl ?? null, ready: d.ready === true, sort: i };
}

/**
 * One storefront of a `POST /shop/import` body as the apps need it: `{studioId, sellerName, city, consentAt}` are
 * required (a listing without the studio's consent day is not listed), products and drops the feed can't read are
 * skipped and reported. Null when the storefront itself is unreadable.
 */
export function cleanStorefront(s) {
  if (!s || typeof s !== "object" || !Number.isInteger(s.studioId) || s.studioId <= 0) return null;
  const sellerName = text(s.sellerName, 80);
  const city = typeof s.city === "string" && /^[A-Z]{2,5}$/.test(s.city) ? s.city : null;
  if (!sellerName || !city || !isDay(s.consentAt)) return null;
  if (s.webshopUrl != null && !isHttps(s.webshopUrl)) return null;
  const stripeAccount = s.stripeAccount == null ? null : typeof s.stripeAccount === "string" && /^acct_[A-Za-z0-9]{8,64}$/.test(s.stripeAccount) ? s.stripeAccount : undefined;
  if (stripeAccount === undefined) return null;
  const shippingOre = s.shippingOre == null ? null : Number.isInteger(s.shippingOre) && s.shippingOre >= 0 && s.shippingOre <= 100_000 ? s.shippingOre : undefined;
  if (shippingOre === undefined) return null;
  const skipped = [];
  const products = [];
  for (const [i, p] of (Array.isArray(s.products) ? s.products : []).entries()) {
    const c = cleanProduct(p, i);
    if (c && !products.some((x) => x.id === c.id) && products.length < MAX_PRODUCTS) products.push(c); else skipped.push(String(p?.id ?? "?"));
  }
  const drops = [];
  for (const [i, d] of (Array.isArray(s.drops) ? s.drops : []).entries()) {
    const c = cleanDrop(d, products.map((p) => p.id), i);
    if (c && !drops.some((x) => x.id === c.id) && drops.length < MAX_DROPS) drops.push(c); else skipped.push(String(d?.id ?? "?"));
  }
  return { studioId: s.studioId, sellerName, city, webshopUrl: s.webshopUrl ?? null, stripeAccount, shippingOre, pickupNote: text(s.pickupNote, 120),
           consentAt: s.consentAt, products, drops, skipped };
}

// MARK: Drops

/** "upcoming" before the window, "open" in it, "closed" after; "ready" once the studio marked it ready for pickup. */
export function dropState(d, now) {
  if (d.ready) return "ready";
  if (now < d.opensAt) return "upcoming";
  return now < d.closesAt ? "open" : "closed";
}

/**
 * A challenge's finisher, who alone sees its drop (phase 3): an accepted participant who reached the target of an
 * "everyone hits N" challenge (`done` on their leaderboard entry), or took part in any other challenge to its end.
 */
export function isFinisher(ch, entry, today) {
  if (!entry || entry.status !== "accepted") return false;
  return ch.metric === "target" ? entry.done === true : ch.end < today;
}

/** The run's progress: `{reserved, goal, fraction, text}`, "31 of 40" against the run size (else the minimum). */
export function dropProgress(d) {
  const goal = d.maxQty || d.minQty || 0;
  const reserved = d.reserved || 0;
  return { reserved, goal, fraction: goal > 0 ? Math.min(1, reserved / goal) : 0, text: goal > 0 ? `${reserved} of ${goal}` : `${reserved} reserved` };
}

/** "2 d 14 h", "3 h", "25 min"; "" when the moment has passed. */
export function untilText(ms, now) {
  const left = ms - now;
  if (left <= 0) return "";
  const d = Math.floor(left / 86400_000), h = Math.floor((left % 86400_000) / 3600_000), m = Math.floor((left % 3600_000) / 60_000);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h`;
  return `${Math.max(1, m)} min`;
}

/** The push and email when a drop's window opens (the notify list; phase 3). */
export function dropOpenMessage(d, product, storefront) {
  const price = product ? ` ${krText(product.priceOre)}` : "";
  const pickup = storefront ? ` Pick up at ${storefront.sellerName}.` : "";
  return { title: `Drop open: ${d.title}`, body: `Pre-order${price} until ${dayText(d.closesAt)}.${pickup} The studio sells it; Brüce only reminds you.` };
}

/** The push and email when a drop or an order is ready at the desk (phase 3 and 4). */
export function readyMessage(title, storefront, pickupCode) {
  const where = storefront?.pickupNote ? `${storefront.sellerName}, ${storefront.pickupNote}` : storefront?.sellerName ?? "the studio";
  return { title: `Ready for pickup: ${title}`, body: pickupCode ? `Show code ${pickupCode} at ${where}.` : `Collect it at ${where}.` };
}

// MARK: Money

/** "449 kr", "1,295 kr" (whole kronor; prices on the pages). */
export function krText(ore) {
  const kr = Math.round(ore / 100);
  return `${kr.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")} kr`;
}
/** "449,00 kr" (checkout rows, with the öre). */
export function krExact(ore) {
  const sign = ore < 0 ? "-" : "";
  const abs = Math.abs(ore);
  return `${sign}${Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")},${String(abs % 100).padStart(2, "0")} kr`;
}
/** The VAT inside a price that includes it: 449 kr at 25% holds 89,80 kr of VAT. */
export function vatPart(ore, rate) {
  return Math.round(ore - ore / (1 + rate / 100));
}

const dayText = (ms) => new Date(ms).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", timeZone: "Europe/Stockholm" });

// MARK: Checkout (phase 4)

export const MAX_QTY = 5;
export const DELIVERIES = ["pickup", "ship"];
export const ORDER_STATUSES = ["paid", "printing", "shipped", "ready", "delivered", "collected", "refunded"];
/** Letters and digits that can't be misread at the desk (no 0/O, 1/I/L). */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** A 5-character pickup code shown at the desk. */
export function pickupCode(random = (n) => crypto.getRandomValues(new Uint8Array(n))) {
  return [...random(5)].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

/**
 * What a checkout body asks for, checked against the catalogue: `{product, variant, qty, delivery, storefront, drop}`,
 * or `{error}`. Shipping only where the studio ships; a variant only from the product's list and in stock; a drop only
 * while its window is open.
 */
export function cleanCheckout(body, { storefront, product, drop }, now = Date.now()) {
  if (!product || !storefront) return { error: "listing not found" };
  const qty = body?.qty == null ? 1 : body.qty;
  if (!Number.isInteger(qty) || qty < 1 || qty > MAX_QTY) return { error: `qty must be 1-${MAX_QTY}` };
  const delivery = body?.delivery == null ? "pickup" : body.delivery;
  if (!DELIVERIES.includes(delivery)) return { error: "delivery must be pickup or ship" };
  if (delivery === "ship" && storefront.shippingOre == null) return { error: "this studio does not ship: pick it up at the desk" };
  let variant = null;
  if (product.variants.length) {
    variant = product.variants.find((v) => v.id === body?.variantId) ?? null;
    if (!variant) return { error: "pick a size or option" };
    if (!variant.inStock) return { error: "that option is out of stock" };
  }
  if (drop && dropState(drop, now) !== "open") return { error: "the pre-order is not open" };
  return { product, variant, qty, delivery, storefront, drop: drop ?? null };
}

/** The order's lines and sums: `{items, subtotalOre, shippingOre, totalOre, vatOre}`; shipping carries the goods' VAT rate. */
export function orderTotals({ product, variant, qty, delivery, storefront }) {
  const items = [{ productId: product.id, variantId: variant?.id ?? null, title: product.title, label: variant?.label ?? null, qty, unitOre: product.priceOre }];
  const subtotalOre = product.priceOre * qty;
  const shippingOre = delivery === "ship" ? storefront.shippingOre ?? 0 : 0;
  const totalOre = subtotalOre + shippingOre;
  return { items, subtotalOre, shippingOre, totalOre, vatOre: vatPart(totalOre, product.vatRate) };
}

/** "Bastu towel · Natural × 2". */
export const itemLine = (it) => `${it.title}${it.label ? ` · ${it.label}` : ""}${it.qty > 1 ? ` × ${it.qty}` : ""}`;

/**
 * Checks a Stripe webhook's `Stripe-Signature` header against the raw body: HMAC-SHA256 of "<t>.<body>" with the
 * endpoint secret, any `v1` signature may match, and the timestamp must be within `toleranceS` of now (a replayed
 * event is refused). Web Crypto; the comparison is constant-time.
 */
export async function verifyStripeSignature(header, body, secret, now = Date.now(), toleranceS = 300) {
  if (!header || !secret) return false;
  const sigs = [];
  let t = null;
  for (const item of String(header).split(",")) {
    const [k, v] = item.trim().split("=");
    if (k === "t") t = Number(v);
    else if (k === "v1" && /^[0-9a-f]{64}$/.test(v ?? "")) sigs.push(v);
  }
  if (!Number.isFinite(t) || !sigs.length || Math.abs(now / 1000 - t) > toleranceS) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${body}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return sigs.some((s) => timingSafeEqual(s, expected));
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** The status as the apps word it. */
export function orderStatusText(status, delivery) {
  switch (status) {
    case "paid": return delivery === "ship" ? "Paid · being prepared" : "Paid · being prepared for pickup";
    case "printing": return "Being printed";
    case "shipped": return delivery === "ship" ? "On its way" : "On its way to the studio";
    case "ready": return "Ready for pickup";
    case "delivered": return "Delivered";
    case "collected": return "Collected";
    case "refunded": return "Refunded";
    default: return status;
  }
}

/** "Order confirmed: Bastu towel" with the pickup code, or that it ships. */
export function orderConfirmedMessage(order, storefront) {
  const what = order.items.map(itemLine).join(", ");
  const body = order.delivery === "ship" ? `${krText(order.totalOre)} paid to ${storefront.sellerName}. It ships to the address you gave Stripe; we'll tell you when it's on its way.`
    : `${krText(order.totalOre)} paid to ${storefront.sellerName}. Show code ${order.pickupCode} at the desk once it's ready; we'll tell you.`;
  return { title: `Order confirmed: ${what}`, body };
}

/** The push and email when the print partner moves an order on: shipped, delivered, or ready at the desk. */
export function orderUpdateMessage(order, status, storefront) {
  const what = order.items.map(itemLine).join(", ");
  const seller = storefront?.sellerName ?? "the studio";
  switch (status) {
    case "ready": return readyMessage(what, storefront, order.pickupCode);
    case "shipped": return { title: `On its way: ${what}`, body: order.delivery === "ship" ? "Your order has shipped. Tracking, when there is any, comes from the sender."
      : `Your order is on its way to ${seller}. We'll tell you when it's ready for pickup.` };
    case "delivered": return { title: `Delivered: ${what}`, body: "Your order has been delivered." };
    default: return { title: `${orderStatusText(status, order.delivery)}: ${what}`, body: `Your order with ${seller}.` };
  }
}
