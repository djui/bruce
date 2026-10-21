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

/** A drop (mockup 1): "DROP" tag, the title, where to pick it up, the countdown, "31 of 40" and a meter, with Notify me. */
export function dropCardHTML(d, href) {
  const now = Date.now();
  const p = Sh.product(S.shop, d.productId);
  const on = S.shopNotify.has(d.id);
  return '<div class="drop-card" role="group" aria-label="' + esc('Drop: ' + d.title + ', ' + Sh.countdownText(d, now) + ', ' + Sh.progressText(d) + ' reserved') + '">' +
    '<a class="drop-body" href="' + href + '"><span class="row-between"><span class="mtag">Drop</span>' + icon(p ? Sh.kindIcon(p.kind) : 'brief', 'drop-glyph') + '</span>' +
    '<b>' + esc(d.title) + '</b><span>Pick up at ' + esc(St.studioName(d.studioId)) + '</span>' +
    '<span class="drop-meta"><span>' + icon('clock') + esc(Sh.countdownText(d, now)) + '</span><span>' + esc(Sh.progressText(d)) + '</span></span>' +
    '<span class="meter"><i style="width:' + Math.round(100 * Sh.progress(d)) + '%"></i></span></a>' +
    '<div class="row-between"><b>' + (p ? esc(Sh.kr(p.priceOre)) : '') + '</b><button class="btn sm' + (on ? ' glass on' : ' lime') + '" data-notify="' + esc(d.id) + '" aria-pressed="' + on + '">' + icon('bell') + (on ? ' Notifying' : ' Notify me') + '</button></div></div>';
}

/** Home, after Spotlight: the live drop and a row of listings, with "Show all" into Home › Shop. Empty without a listing. */
export function shopHomeHTML(tab) {
  if (Sh.isEmpty(S.shop)) return '';
  const d = Sh.homeDrop(S.shop, Date.now());
  return '<div class="sec-row"><h2 class="sec-title">SHOP</h2><a class="btn glass sm" href="' + shopRoute(tab) + '">Show all</a></div>' +
    (d ? dropCardHTML(d, productRoute(tab, d.productId)) : '') +
    '<div class="hscroll shop-row">' + S.shop.products.slice(0, 8).map((p) => tileHTML(p, productRoute(tab, p.id))).join('') + '</div>';
}

/** Handles a Notify me click anywhere; true when it was one. */
export function shopClick(e, rerender) {
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
    el.innerHTML = '<header class="hero product-hero k-' + esc(p.kind) + '">' + icon(Sh.kindIcon(p.kind), 'product-glyph') + '<div class="hero-bar">' + close + '</div></header>' +
      '<div class="pane-pad"><h1 class="product-title">' + esc(p.title) + '</h1>' +
      '<p class="muted small">' + esc([studio, p.description].filter(Boolean).join(' · ')) + '</p>' +
      '<p class="price-row"><b>' + esc(Sh.kr(p.priceOre)) + '</b><span class="muted small">incl. VAT</span></p>' +
      (p.variants.length ? '<p class="small muted">' + (p.kind === 'apparel' ? 'SIZES' : 'OPTIONS') + '</p><div class="chips wrap">' + p.variants.map((v) => '<span class="chip' + (v.inStock ? '' : ' off') + '">' + esc(v.label) + (v.inStock ? '' : ' · out') + '</span>').join('') + '</div>' : '') +
      (d ? dropBlockHTML(d, studio) : '') +
      '<a class="card row-card" href="' + ctx.link('studio', p.studioId) + '">' + icon('building') + '<div class="grow"><b>' + esc(studio) + '</b><p class="muted">' + esc(front ? Sh.soldBy(front.sellerName, p.fulfilment === 'desk') : 'Studio page') + '</p></div>' + icon('chevron') + '</a>' +
      (front && front.pickupNote ? '<p class="muted small">' + icon('pin') + ' ' + esc(front.pickupNote) + '</p>' : '') +
      '<p class="muted small note">' + esc(Sh.NOT_AFFILIATED) + '</p>' +
      '<div class="actions sticky">' + (link ? '<a class="btn lime" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer">' + (p.linkUrl ? 'Open in the webshop' : 'Webshop') + icon('external') + '</a>'
        : '<span class="btn glass" aria-disabled="true">' + icon('person') + ' Ask at the desk</span>') + '</div></div>';
  };
  el.onclick = (e) => {
    if (e.target.closest('[data-sact="back"]')) { ctx.close(); return; }
    shopClick(e, draw);
  };
  draw();
  St.loadShop().then(() => { draw(); St.tapProduct(id); });
}

/** The drop's window: "Pre-order until Sun 7 Feb · one print run", the countdown, "31 of 40" and Notify me. */
function dropBlockHTML(d, studio) {
  const now = Date.now();
  const on = S.shopNotify.has(d.id);
  return '<div class="card drop-block"><div class="row-between"><span class="mtag">Drop</span><b class="small">' + icon('clock') + ' ' + esc(Sh.countdownText(d, now)) + '</b></div>' +
    '<p>' + esc(Sh.dropLine(d)) + '</p><div class="row-between small"><span class="muted">Pick up at ' + esc(studio) + '</span><b>' + esc(Sh.progressText(d)) + '</b></div>' +
    '<span class="meter"><i style="width:' + Math.round(100 * Sh.progress(d)) + '%"></i></span>' +
    '<label class="toggle"><span>Notify me<small class="muted">' + esc(Sh.NOTIFY_HINT) + '</small></span><input type="checkbox" data-notify="' + esc(d.id) + '"' + (on ? ' checked' : '') + '><i></i></label></div>';
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
