// Studio shop on the web (shop.js; ShopViews.swift on the iPhone): Home's Shop section with the drop card, Home › Shop
// (#/home/shop/all) with its chips, a product page (#/<tab>/product/<id>), the "Shop at the desk" rail on a studio page
// and "Forgot your towel?" on the ticket. Everything shows only while the city's catalogue has something in it. The
// studio sells: the buttons say "Ask at the desk" or open its webshop, and Notify me only reminds.
import { $, esc, icon, fmt } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import * as Sh from './shop.js';
import { glassBtn, empty, loading, toast, chip, run, sheet, pill } from './ui.js';

const studioShort = (id) => St.studioName(id).split(' ')[0];
export const shopRoute = (tab) => '#/' + (tab || 'home') + '/shop/all';
export const productRoute = (tab, id) => '#/' + (tab || 'home') + '/product/' + encodeURIComponent(id);

/** A product's picture: the kind's tint and icon (listings carry no photos). */
export const art = (kind, cls) => '<span class="part k-' + esc(kind) + (cls ? ' ' + cls : '') + '" aria-hidden="true">' + icon(Sh.kindIcon(kind)) + '</span>';

/** A product in the grid and the rail: picture, title, "449 kr · Ångan". */
export function tileHTML(p, href, compact) {
  return '<a class="ptile' + (compact ? ' compact' : '') + '" href="' + href + '" aria-label="' + esc(p.title + ', ' + Sh.kr(p.priceOre) + ', ' + St.studioName(p.studioId)) + '">' + art(p.kind) +
    '<b>' + esc(p.title) + '</b><span><em>' + esc(Sh.kr(p.priceOre)) + '</em>' + (compact ? '' : ' · ' + esc(studioShort(p.studioId))) + '</span></a>';
}

const tag = (unlocked) => '<span class="mtag">' + (unlocked ? 'Unlocked' : 'Drop') + '</span>';
/** The card's button: Notify me before the window, Reserve (the studio's checkout) in it, "Ready for pickup" at the desk. */
function dropButton(d) {
  const now = Date.now();
  const state = Sh.dropState(d, now), on = S.shopNotify.has(d.id), url = Sh.reserveUrl(d, now);
  if (state === 'ready') return '<span class="btn sm lime">' + icon('checkSeal') + ' ' + Sh.READY + '</span>';
  if (state === 'closed') return '<span class="btn sm glass on">' + icon('clock') + ' Closed</span>';
  if (url) return '<a class="btn sm lime" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' Reserve</a>';
  return '<button class="btn sm' + (on ? ' glass on' : ' lime') + '" data-notify="' + esc(d.id) + '" aria-pressed="' + on + '">' + icon('bell') + (on ? ' Notifying' : ' Notify me') + '</button>';
}

/** A drop (mockup 1): "DROP" (or "UNLOCKED") tag, the title, where to pick it up, the countdown, "31 of 40" and a meter,
 *  with Notify me, Reserve or "Ready for pickup" as the window stands. */
export function dropCardHTML(d, href) {
  const now = Date.now();
  const p = Sh.product(S.shop, d.productId);
  return '<div class="drop-card" role="group" aria-label="' + esc('Drop: ' + d.title + ', ' + Sh.countdownText(d, now) + ', ' + Sh.progressText(d) + ' reserved') + '">' +
    '<a class="drop-body" href="' + href + '"><span class="row-between">' + tag(d.unlocked) + icon(p ? Sh.kindIcon(p.kind) : 'brief', 'drop-glyph') + '</span>' +
    '<b>' + esc(d.title) + '</b><span>Pick up at ' + esc(St.studioName(d.studioId)) + '</span>' +
    '<span class="drop-meta"><span>' + icon(Sh.dropState(d, now) === 'ready' ? 'checkSeal' : 'clock') + esc(Sh.countdownText(d, now)) + '</span><span>' + esc(Sh.progressText(d)) + '</span></span>' +
    '<span class="meter"><i style="width:' + Math.round(100 * Sh.progress(d)) + '%"></i></span></a>' +
    '<div class="row-between"><b>' + (p ? esc(Sh.kr(p.priceOre)) : '') + '</b>' + dropButton(d) + '</div></div>';
}

/** A finished challenge's reward (mockup 4): the tee only finishers can order, "Unlocked", a size pick and Reserve. */
export function rewardCardHTML(c, tab) {
  const d = Sh.dropForChallenge(S.shop, c.id);
  if (!d) return '';
  const now = Date.now();
  const p = Sh.product(S.shop, d.productId);
  const studio = St.studioName(d.studioId);
  const state = Sh.dropState(d, now), url = Sh.reserveUrl(d, now), on = S.shopNotify.has(d.id);
  const sizes = p && p.variants.length ? '<div class="chips wrap sizes">' + p.variants.map((v, i) => '<button class="chip" data-size="' + esc(v.id) + '" aria-pressed="' + (v.id === 'm' || (!p.variants.some((x) => x.id === 'm') && i === 0)) + '"' + (v.inStock ? '' : ' disabled') + '>' + esc(v.label) + '</button>').join('') + '</div>' : '';
  const action = state === 'open' ? (url ? '<a class="btn lime" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' ' + esc('Reserve · ' + (p ? Sh.kr(p.priceOre) : '')) + '</a><p class="muted small">' + esc(Sh.RESERVE_HINT) + '</p>'
      : '<p class="muted small">' + esc(Sh.RESERVE_DESK) + '</p>')
    : state === 'ready' ? '<p><b>' + icon('checkSeal') + ' ' + esc(Sh.readyBody(Sh.storefront(S.shop, d.studioId))) + '</b></p>'
    : state === 'closed' ? '<p class="muted small">' + esc(Sh.DROP_CLOSED) + '</p>'
    : '<button class="btn glass" data-notify="' + esc(d.id) + '" aria-pressed="' + on + '">' + icon('bell') + (on ? ' Notify me is on' : ' Notify me') + '</button>';
  return '<div class="card reward-card"><div class="reward-top">' + art(p ? p.kind : 'apparel', 'small') + '<div class="grow">' + tag(true) + '<a href="' + productRoute(tab, d.productId) + '"><b>' + esc(d.title) + '</b></a></div><span class="muted small">' + esc(Sh.countdownText(d, now)) + '</span></div>' +
    '<p class="muted small">' + esc(Sh.finisherBody(c, studio, d)) + '</p>' + sizes + action + '</div>';
}

/** Home, after Spotlight: the live drop and a row of listings, with "Show all" into Home › Shop. Empty without a listing. */
export function shopHomeHTML(tab) {
  if (Sh.isEmpty(S.shop)) return '';
  const d = Sh.homeDrop(S.shop, Date.now());
  return '<div class="sec-row"><h2 class="sec-title">SHOP</h2><a class="btn glass sm" href="' + shopRoute(tab) + '">Show all</a></div>' +
    (d ? dropCardHTML(d, productRoute(tab, d.productId)) : '') +
    '<div class="hscroll shop-row">' + S.shop.products.slice(0, 8).map((p) => tileHTML(p, productRoute(tab, p.id))).join('') + '</div>';
}

/** Handles a Notify me click anywhere (and a size pick on a reward card); true when it was one. */
export function shopClick(e, rerender) {
  const sz = e.target.closest('[data-size]');
  if (sz) { sz.parentElement.querySelectorAll('[data-size]').forEach((x) => x.setAttribute('aria-pressed', x === sz)); return true; }
  const b = e.target.closest('[data-notify]');
  if (!b) return false;
  const d = S.shop && S.shop.drops.find((x) => x.id === b.dataset.notify);
  if (!d) return true;
  run(b, async () => { await St.setNotify(d, !S.shopNotify.has(d.id)); if (rerender) rerender(); });
  return true;
}

// ---------------------------------------------------------------- Home › Shop

/** The city's catalogue (mockup 1): chips (All, Drops, Towels, Mats, Grip socks…), the live drops and a grid of listings. */
export function renderShop(el, ctx) {
  const state = { chip: null };
  const close = glassBtn(ctx.wide ? 'close' : 'back', 'data-sact="back"', ctx.wide ? 'Close' : 'Back');
  const draw = () => {
    const c = S.shop;
    const now = Date.now();
    const drops = Sh.liveDrops(c, now);
    const products = state.chip === 'drops' ? [] : Sh.filtered(c, state.chip);
    el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '</div><h1 class="screen-title">SHOP</h1>' +
      (!c ? loading('Loading the shop…') :
        '<div class="chips">' + chip('All', !state.chip, 'data-schip=""') + (drops.length ? chip('Drops', state.chip === 'drops', 'data-schip="drops"') : '') +
        Sh.kinds(c).map((k) => chip(esc(Sh.kindTitle(k)), state.chip === k, 'data-schip="' + k + '"')).join('') + '</div>' +
        (!state.chip || state.chip === 'drops' ? drops.map((d) => dropCardHTML(d, productRoute(ctx.tab, d.productId))).join('') : '') +
        (products.length ? (!state.chip ? '<h2 class="sec-title">Near you</h2>' : '') + '<div class="shop-grid">' + products.map((p) => tileHTML(p, productRoute(ctx.tab, p.id))).join('') + '</div>'
          : state.chip === 'drops' ? '' : empty('gift', Sh.isEmpty(c) ? 'Nothing listed in ' + St.city().name + ' yet.' : 'Nothing in this group right now.')) +
        '<p class="muted small note">' + esc(Sh.CATALOG_FOOTER) + '</p>') + '</div>';
  };
  el.onclick = (e) => {
    if (e.target.closest('[data-sact="back"]')) { ctx.close(); return; }
    const c = e.target.closest('[data-schip]');
    if (c) { state.chip = c.dataset.schip || null; draw(); return; }
    shopClick(e, draw);
  };
  draw();
  St.loadShop().then(draw);
}

// ---------------------------------------------------------------- product page

/** Mockup 3 as phase 2 shows it: the picture, title, seller and description, the price incl. VAT, the variants, the
 *  drop's window and Notify me when it is one, and "Ask at the desk" or the webshop. Opening it counts one anonymous tap. */
export function renderProduct(el, id, ctx) {
  const close = glassBtn(ctx.wide ? 'close' : 'back', 'data-sact="back"', ctx.wide ? 'Close' : 'Back');
  const state = { variantId: null, delivery: 'pickup' };
  const draw = () => {
    const c = S.shop;
    const p = Sh.product(c, id);
    if (!p) { el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '</div>' + (c ? empty('gift', 'This listing is no longer there.') : loading('Loading…')) + '</div>'; return; }
    const front = Sh.storefront(c, p.studioId);
    const d = Sh.dropFor(c, p.id);
    const studio = St.studioName(p.studioId);
    const url = Sh.httpsUrl(p.linkUrl) || (front && Sh.httpsUrl(front.webshopUrl));
    const link = url && (p.fulfilment !== 'desk' || p.linkUrl);
    const now = Date.now(), dstate = d && Sh.dropState(d, now), reserve = d && Sh.reserveUrl(d, now), on = d && S.shopNotify.has(d.id);
    // Phase 4: Buy where the studio is connected and the listing is open to buy (no drop, or a drop whose window is open).
    const buy = Sh.canBuy(c, p) && (!d || dstate === 'open');
    const draft = buy ? Sh.draft(c, p, state) : null;
    const variants = p.variants.length ? '<p class="small muted">' + (p.kind === 'apparel' ? 'SIZES' : 'OPTIONS') + '</p><div class="chips wrap">' +
      p.variants.map((v) => (buy && v.inStock ? '<button class="chip" data-variant="' + esc(v.id) + '" aria-pressed="' + (draft && draft.variant && draft.variant.id === v.id) + '">' + esc(v.label) + '</button>'
        : '<span class="chip' + (v.inStock ? '' : ' off') + '">' + esc(v.label) + (v.inStock ? '' : ' · out') + '</span>')).join('') + '</div>' : '';
    // A drop's Reserve opens the studio's own checkout while the window is open; before it, Notify me; at the desk, "Ready for pickup".
    const actions = buy ? '<button class="btn lime" data-buy>' + icon('gift') + ' ' + esc('Buy · ' + Sh.kr(Sh.totals(draft).totalOre)) + '</button>'
      : d && dstate === 'open' ? (reserve ? '<a class="btn lime" href="' + esc(reserve) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' ' + esc('Reserve · ' + Sh.kr(p.priceOre)) + '</a><p class="muted small center">' + esc(Sh.RESERVE_HINT) + '</p>'
        : '<span class="btn glass" aria-disabled="true">' + icon('person') + ' ' + esc(Sh.RESERVE_DESK) + '</span>')
      : d && dstate === 'ready' ? '<span class="btn lime" aria-disabled="true">' + icon('checkSeal') + ' ' + Sh.READY + '</span>'
      : d && dstate === 'upcoming' ? '<button class="btn ' + (on ? 'glass' : 'lime') + '" data-notify="' + esc(d.id) + '" aria-pressed="' + on + '">' + icon('bell') + (on ? ' Notify me is on' : ' Notify me') + '</button>'
      : link ? '<a class="btn lime" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + (p.linkUrl ? 'Open in the webshop' : 'Webshop') + icon('external') + '</a>'
      : '<span class="btn glass" aria-disabled="true">' + icon('person') + ' Ask at the desk</span>';
    el.innerHTML = '<header class="hero product-hero k-' + esc(p.kind) + '">' + icon(Sh.kindIcon(p.kind), 'product-glyph') + '<div class="hero-bar">' + close + '</div></header>' +
      '<div class="pane-pad"><h1 class="product-title">' + esc(p.title) + '</h1>' +
      '<p class="muted small">' + esc([studio, p.description].filter(Boolean).join(' · ')) + '</p>' +
      '<p class="price-row"><b>' + esc(Sh.kr(p.priceOre)) + '</b><span class="muted small">incl. VAT</span></p>' +
      variants +
      (d ? dropBlockHTML(d, studio) : '') +
      (buy ? deliveryHTML(front, studio, draft.delivery, 'data-delivery') : '') +
      '<a class="card row-card" href="' + ctx.link('studio', p.studioId) + '">' + icon('building') + '<div class="grow"><b>' + esc(studio) + '</b><p class="muted">' + esc(front ? Sh.soldBy(front.sellerName, p.fulfilment === 'desk', front.checkout) : 'Studio page') + '</p></div>' + icon('chevron') + '</a>' +
      (front && front.pickupNote ? '<p class="muted small">' + icon('pin') + ' ' + esc(front.pickupNote) + '</p>' : '') +
      '<p class="muted small note">' + esc(Sh.NOT_AFFILIATED) + '</p>' +
      '<div class="actions sticky">' + actions + '</div></div>';
  };
  el.onclick = (e) => {
    if (e.target.closest('[data-sact="back"]')) { ctx.close(); return; }
    const v = e.target.closest('[data-variant]');
    if (v) { state.variantId = v.dataset.variant; draw(); return; }
    const dl = e.target.closest('[data-delivery]');
    if (dl) { state.delivery = dl.dataset.delivery; draw(); return; }
    if (e.target.closest('[data-buy]')) { openCheckout(id, state); return; }
    shopClick(e, draw);
  };
  draw();
  St.loadShop().then(() => { draw(); St.tapProduct(id); });
}

/** "How do you want it?": pick up at the desk (free, the default) or shipped where the studio ships. */
function deliveryHTML(front, studio, delivery, attr) {
  const row = (key, ic, title, sub) => '<button class="delivery-row" ' + attr + '="' + key + '" aria-pressed="' + (delivery === key) + '">' + icon(ic) + '<span class="grow"><b>' + esc(title) + '</b><small class="muted">' + esc(sub) + '</small></span>' + (delivery === key ? icon('checkSeal', 'tick') : '<i class="ring"></i>') + '</button>';
  return '<p class="small muted">' + esc(Sh.HOW_TITLE.toUpperCase()) + '</p><div class="stack delivery">' +
    row('pickup', 'building', Sh.pickupAt(studio), front.pickupNote || Sh.PICKUP_FREE) +
    (Sh.ships(front) ? row('ship', 'location', Sh.shipPrice(front), Sh.SHIP_NOTE) : '') + '</div>';
}

// ---------------------------------------------------------------- checkout and orders (phase 4)

/** Mockup 5: what is being bought, how many, how it comes, the sums with the VAT, who sells it, and Pay, which sends the
 *  browser to Stripe Checkout on the studio's account. Brüce never sees the card or an address. */
export function openCheckout(productId, opts) {
  const p = Sh.product(S.shop, productId);
  const d = p && Sh.draft(S.shop, p, opts);
  if (!d) { toast(Sh.NO_CHECKOUT); return; }
  const studio = St.studioName(p.studioId);
  const vicinity = (St.studio(p.studioId) || {}).vicinity;
  const s = sheet('Checkout', '');
  const draw = () => {
    const t = Sh.totals(d), problem = Sh.draftProblem(d);
    s.body.innerHTML = '<div class="checkout-item">' + art(p.kind, 'small') + '<div class="grow"><b>' + esc(p.title) + '</b><p class="muted small">' + esc([d.variant && d.variant.label, studio].filter(Boolean).join(' · ')) + '</p></div><b class="num">' + esc(Sh.krExact(p.priceOre)) + '</b></div>' +
      '<div class="row-between qty"><b>Quantity</b><span class="stepper"><button data-q="-1" aria-label="Fewer"' + (d.qty <= 1 ? ' disabled' : '') + '>−</button><b>' + d.qty + '</b><button data-q="1" aria-label="More"' + (d.qty >= Sh.MAX_QTY ? ' disabled' : '') + '>+</button></span></div>' +
      deliveryHTML(d.storefront, studio, d.delivery, 'data-cdelivery') +
      '<div class="card sums"><span>' + esc(Sh.itemLine(p.title, d.variant && d.variant.label, d.qty)) + '</span><b>' + esc(Sh.krExact(t.subtotalOre)) + '</b>' +
      (d.delivery === 'ship' ? '<span>Shipping</span><b>' + esc(Sh.krExact(t.shippingOre)) + '</b>' : '') +
      '<span class="total">Total</span><b class="total">' + esc(Sh.krExact(t.totalOre)) + '</b>' +
      '<span class="muted">' + esc(Sh.vatLine(p.vatRate == null ? 25 : p.vatRate)) + '</span><b class="muted">' + esc(Sh.krExact(t.vatOre)) + '</b></div>' +
      '<p class="muted small">' + esc(Sh.sellerLine(d.storefront, vicinity)) + '</p>' +
      (problem ? '<p class="small red center">' + esc(problem) + '</p>' : '') +
      '<div class="stack"><button class="btn lime" data-pay' + (problem ? ' disabled' : '') + '>' + icon('lock') + ' ' + esc('Pay ' + Sh.krExact(t.totalOre)) + '</button>' +
      '<p class="muted small center">' + esc(Sh.PAY_METHODS) + '</p><p class="muted small">' + icon('lock') + ' ' + esc(Sh.PAY_SAFETY) + '</p></div>';
  };
  s.body.addEventListener('click', (e) => {
    const q = e.target.closest('[data-q]');
    if (q) { d.qty = Math.min(Sh.MAX_QTY, Math.max(1, d.qty + +q.dataset.q)); draw(); return; }
    const dl = e.target.closest('[data-cdelivery]');
    if (dl) { d.delivery = dl.dataset.cdelivery; draw(); return; }
    const pay = e.target.closest('[data-pay]');
    if (pay) run(pay, async () => {
      const url = await St.startCheckout(d);
      if (!url) { toast(Sh.DEMO_CHECKOUT); return; }
      location.assign(url);
    });
  });
  draw();
}

/** Menu › Orders: what the member bought from studio shops, the status as the server words it, and the pickup code. */
export function openOrders(paid) {
  const s = sheet('Orders', loading());
  const draw = () => {
    const list = S.orders;
    s.body.innerHTML = (!list.length ? (S.ordersLoaded ? empty('gift', Sh.ORDERS_EMPTY) : loading()) :
      list.map((o) => '<div class="card order"><div class="order-top">' + icon(Sh.isReady(o) ? 'checkSeal' : o.status === 'shipped' ? 'location' : 'gift') + '<div class="grow"><b>' + esc(o.items.map((i) => Sh.itemLine(i.title, i.label, i.qty)).join(', ')) + '</b>' +
        '<p class="muted small">' + esc([o.sellerName || St.studioName(o.studioId), fmt(o.createdAt, { day: 'numeric', month: 'short' })].filter(Boolean).join(' · ')) + '</p></div><b class="num">' + esc(Sh.kr(o.totalOre)) + '</b></div>' +
        pill(Sh.orderLine(o), Sh.isReady(o) ? 'lime' : '') +
        (o.pickupCode && !Sh.isDone(o) ? '<p class="small muted code-label">PICKUP CODE</p><b class="pickup-code" aria-label="Pickup code ' + esc(o.pickupCode.split('').join(' ')) + '">' + esc(o.pickupCode) + '</b>' + (o.pickupNote ? '<p class="muted small">' + esc(o.pickupNote) + '</p>' : '') : '') + '</div>').join('')) +
      '<p class="muted small note">' + esc(Sh.ORDERS_NOTE) + '</p>';
  };
  draw();
  St.loadOrders().then(draw);
  if (paid) toast(Sh.PAID_OPEN);
}

/** The drop's window: "Pre-order until Sun 7 Feb · one print run", the countdown, "31 of 40" and Notify me; "Ready for
 *  pickup" once the studio has it at the desk, "The pre-order has closed" after the window. */
function dropBlockHTML(d, studio) {
  const now = Date.now();
  const on = S.shopNotify.has(d.id), state = Sh.dropState(d, now);
  const line = state === 'ready' ? Sh.readyBody(Sh.storefront(S.shop, d.studioId)) : state === 'closed' ? Sh.DROP_CLOSED : d.unlocked ? Sh.FINISHER_HINT + ' ' + Sh.dropLine(d) + '.' : Sh.dropLine(d);
  return '<div class="card drop-block"><div class="row-between">' + tag(d.unlocked) + '<b class="small">' + icon(state === 'ready' ? 'checkSeal' : 'clock') + ' ' + esc(Sh.countdownText(d, now)) + '</b></div>' +
    '<p>' + esc(line) + '</p><div class="row-between small"><span class="muted">Pick up at ' + esc(studio) + '</span><b>' + esc(Sh.progressText(d)) + '</b></div>' +
    '<span class="meter"><i style="width:' + Math.round(100 * Sh.progress(d)) + '%"></i></span>' +
    (state === 'upcoming' || state === 'open' ? '<label class="toggle"><span>Notify me<small class="muted">' + esc(state === 'open' ? 'A push to the Brüce iPhone app and an email when it is ready for pickup.' : Sh.NOTIFY_HINT) + '</small></span><input type="checkbox" data-notify="' + esc(d.id) + '"' + (on ? ' checked' : '') + '><i></i></label>' : '') + '</div>';
}

// ---------------------------------------------------------------- studio page and the ticket

/** "Shop at the desk" on a studio page (mockup 2): the listings as a rail, who sells them and how to pay. */
export function shopRailHTML(studioId, tab) {
  const front = Sh.storefront(S.shop, studioId);
  const products = Sh.productsFor(S.shop, studioId);
  if (!front || !products.length) return '';
  const url = Sh.httpsUrl(front.webshopUrl);
  return '<div class="card shop-rail"><div class="row-between"><h3 class="section-head">Shop at the desk</h3><span class="muted small">' + products.length + (products.length === 1 ? ' item' : ' items') + '</span></div>' +
    '<div class="hscroll shop-row">' + products.map((p) => tileHTML(p, productRoute(tab, p.id), true)).join('') + '</div>' +
    '<div class="row-between seller"><span class="muted small">' + esc(Sh.soldBy(front.sellerName, products.some((p) => p.fulfilment === 'desk'), front.checkout)) + '</span>' +
    (url ? '<a class="btn glass sm" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' Webshop</a>' : '<span class="chip">Ask at the desk</span>') + '</div></div>';
}

/** "Forgot your towel?" on the ticket after a check-in at a sauna or spa whose storefront lists a towel. */
export function towelCardHTML(studioId) {
  if (!St.isWellness(studioId)) return '';
  const t = Sh.towelFor(S.shop, studioId);
  if (!t) return '';
  return '<a class="card row-card towel-card" href="' + productRoute('home', t.id) + '" data-close>' + art('towel', 'small') + '<div class="grow"><b>Forgot your towel?</b><p class="muted">' + esc(Sh.towelBody(t)) + '</p></div>' + icon('chevron') + '</a>';
}
