// Studio shop on the web (shop.js; ShopViews.swift on the iPhone): Home's Shop section with the drop card, Home › Shop
// (#/home/shop/all) with its chips, a product page (#/<tab>/product/<id>), the "Shop at the desk" rail on a studio page
// and "Forgot your towel?" on the ticket. Everything shows only while the city's catalogue has something in it. The
// studio sells: the buttons say "Ask at the desk" or open its webshop, and Notify me only reminds.
import { $, esc, icon } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import * as Sh from './shop.js';
import { glassBtn, empty, loading, toast, chip, run } from './ui.js';

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
    // A drop's Reserve opens the studio's own checkout while the window is open; before it, Notify me; at the desk, "Ready for pickup".
    const actions = d && dstate === 'open' ? (reserve ? '<a class="btn lime" href="' + esc(reserve) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' ' + esc('Reserve · ' + Sh.kr(p.priceOre)) + '</a><p class="muted small center">' + esc(Sh.RESERVE_HINT) + '</p>'
        : '<span class="btn glass" aria-disabled="true">' + icon('person') + ' ' + esc(Sh.RESERVE_DESK) + '</span>')
      : d && dstate === 'ready' ? '<span class="btn lime" aria-disabled="true">' + icon('checkSeal') + ' ' + Sh.READY + '</span>'
      : d && dstate === 'upcoming' ? '<button class="btn ' + (on ? 'glass' : 'lime') + '" data-notify="' + esc(d.id) + '" aria-pressed="' + on + '">' + icon('bell') + (on ? ' Notify me is on' : ' Notify me') + '</button>'
      : link ? '<a class="btn lime" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + (p.linkUrl ? 'Open in the webshop' : 'Webshop') + icon('external') + '</a>'
      : '<span class="btn glass" aria-disabled="true">' + icon('person') + ' Ask at the desk</span>';
    el.innerHTML = '<header class="hero product-hero k-' + esc(p.kind) + '">' + icon(Sh.kindIcon(p.kind), 'product-glyph') + '<div class="hero-bar">' + close + '</div></header>' +
      '<div class="pane-pad"><h1 class="product-title">' + esc(p.title) + '</h1>' +
      '<p class="muted small">' + esc([studio, p.description].filter(Boolean).join(' · ')) + '</p>' +
      '<p class="price-row"><b>' + esc(Sh.kr(p.priceOre)) + '</b><span class="muted small">incl. VAT</span></p>' +
      (p.variants.length ? '<p class="small muted">' + (p.kind === 'apparel' ? 'SIZES' : 'OPTIONS') + '</p><div class="chips wrap">' + p.variants.map((v) => '<span class="chip' + (v.inStock ? '' : ' off') + '">' + esc(v.label) + (v.inStock ? '' : ' · out') + '</span>').join('') + '</div>' : '') +
      (d ? dropBlockHTML(d, studio) : '') +
      '<a class="card row-card" href="' + ctx.link('studio', p.studioId) + '">' + icon('building') + '<div class="grow"><b>' + esc(studio) + '</b><p class="muted">' + esc(front ? Sh.soldBy(front.sellerName, p.fulfilment === 'desk') : 'Studio page') + '</p></div>' + icon('chevron') + '</a>' +
      (front && front.pickupNote ? '<p class="muted small">' + icon('pin') + ' ' + esc(front.pickupNote) + '</p>' : '') +
      '<p class="muted small note">' + esc(Sh.NOT_AFFILIATED) + '</p>' +
      '<div class="actions sticky">' + actions + '</div></div>';
  };
  el.onclick = (e) => {
    if (e.target.closest('[data-sact="back"]')) { ctx.close(); return; }
    shopClick(e, draw);
  };
  draw();
  St.loadShop().then(() => { draw(); St.tapProduct(id); });
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
    '<div class="row-between seller"><span class="muted small">' + esc(Sh.soldBy(front.sellerName, products.some((p) => p.fulfilment === 'desk'))) + '</span>' +
    (url ? '<a class="btn glass sm" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + icon('external') + ' Webshop</a>' : '<span class="chip">Ask at the desk</span>') + '</div></div>';
}

/** "Forgot your towel?" on the ticket after a check-in at a sauna or spa whose storefront lists a towel. */
export function towelCardHTML(studioId) {
  if (!St.isWellness(studioId)) return '';
  const t = Sh.towelFor(S.shop, studioId);
  if (!t) return '';
  return '<a class="card row-card towel-card" href="' + productRoute('home', t.id) + '" data-close>' + art('towel', 'small') + '<div class="grow"><b>Forgot your towel?</b><p class="muted">' + esc(Sh.towelBody(t)) + '</p></div>' + icon('chevron') + '</a>';
}
