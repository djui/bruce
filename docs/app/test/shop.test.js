// Studio shop (js/shop.js): the catalogue's reading and hiding rules, drop windows and progress, money, the demo
// catalogue and the demo server's shop answers, the same cases as ShopTests.swift.
// Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Sh from '../js/shop.js';
import { DEMO_SHOP, DEMO_ORDERS, handleServer } from '../js/demo.js';

const at = (s) => Date.parse(s);
const drop = { id: 'race-day', studioId: 9840, productId: 'tee', title: 'Race Day tee', opensAt: at('2027-01-25T08:00:00Z'), closesAt: at('2027-02-07T22:00:00Z'), minQty: 25, maxQty: 40, reserved: 31, pickupFrom: '2027-02-20' };

test('drops: the window, the run\'s progress and the countdown', () => {
  assert.equal(Sh.dropState(drop, at('2027-01-20T00:00:00Z')), 'upcoming');
  assert.equal(Sh.dropState(drop, at('2027-02-01T00:00:00Z')), 'open');
  assert.equal(Sh.dropState(drop, at('2027-02-08T00:00:00Z')), 'closed');
  assert.equal(Sh.progressText(drop), '31 of 40');
  assert.ok(Math.abs(Sh.progress(drop) - 0.775) < 0.001);
  assert.equal(Sh.progressText(Object.assign({}, drop, { maxQty: null })), '31 of 25');
  assert.equal(Sh.progressText(Object.assign({}, drop, { maxQty: null, minQty: 0 })), '31 reserved');
  assert.equal(Sh.progress(Object.assign({}, drop, { maxQty: null, minQty: 0 })), 0);
  assert.equal(Sh.progress(Object.assign({}, drop, { reserved: 50 })), 1);
  assert.equal(Sh.countdownText(drop, at('2027-02-05T08:00:00Z')), 'Closes in 2 d 14 h');
  assert.equal(Sh.countdownText(drop, at('2027-02-07T19:30:00Z')), 'Closes in 2 h');
  assert.equal(Sh.countdownText(drop, at('2027-02-07T21:50:00Z')), 'Closes in 10 min');
  assert.equal(Sh.countdownText(drop, at('2027-01-20T08:00:00Z')), 'Opens in 5 d 0 h');
  assert.equal(Sh.countdownText(drop, at('2027-02-08T00:00:00Z')), 'Closed');
  assert.equal(Sh.untilText(drop.closesAt, at('2027-02-08T00:00:00Z')), '');
  assert.equal(Sh.dropLine(drop), 'Pre-order until Sun 7 Feb · one print run · pickup from Sat 20 Feb');
  assert.equal(Sh.dropLine(Object.assign({}, drop, { pickupFrom: null })), 'Pre-order until Sun 7 Feb · one print run');
});

test('money: kronor incl. VAT, the exact rows and the VAT inside a price', () => {
  assert.equal(Sh.kr(44900), '449 kr');
  assert.equal(Sh.kr(129500), '1,295 kr');
  assert.equal(Sh.kr(34950), '350 kr');
  assert.equal(Sh.krExact(44900), '449,00 kr');
  assert.equal(Sh.krExact(8980), '89,80 kr');
  assert.equal(Sh.krExact(0), '0,00 kr');
  assert.equal(Sh.vatPart(44900, 25), 8980);
  assert.equal(Sh.vatPart(34900, 25), 6980);
  assert.equal(Sh.vatPart(10000, 0), 0);
  assert.equal(Sh.soldBy('Ångan Bastu AB', true), 'Sold by Ångan Bastu AB. Pay at the desk.');
  assert.equal(Sh.soldBy('Yogaloft Södermalm AB', false), 'Sold by Yogaloft Södermalm AB.');
  assert.equal(Sh.towelBody({ title: 'Bastu towel', priceOre: 44900 }), 'Rent one at the desk, or take a bastu towel home for 449 kr.');
});

test('the catalogue: what the apps can\'t read is skipped, and nothing listed hides the shop', () => {
  const c = Sh.decode({ city: 'STO',
    storefronts: [{ studioId: 9850, sellerName: 'Ångan Bastu AB', city: 'STO', webshopUrl: 'https://shop.example.org/angan', consentAt: '2026-11-09' }, { studioId: 1, sellerName: 'Broken', city: 'STO' }],
    products: [{ id: 'towel', studioId: 9850, title: 'Bastu towel', kind: 'towel', priceOre: 44900, fulfilment: 'desk', variants: [{ id: 'natural', label: 'Natural' }, { id: 'x', label: 'Out', inStock: false }, { label: 'bad' }] },
      { id: 'hat', studioId: 9850, title: 'Felt hat', kind: 'hat', priceOre: 29900, fulfilment: 'desk' }, { id: 'orphan', studioId: 1, title: 'Mat', kind: 'mat', priceOre: 100, fulfilment: 'desk' },
      { id: 'tee', studioId: 9850, title: 'Tee', kind: 'apparel', priceOre: 34900, fulfilment: 'pod' }],
    drops: [{ id: 'd1', studioId: 9850, productId: 'tee', title: 'Tee drop', opensAt: 1, closesAt: 2 }, { id: 'd2', studioId: 9850, productId: 'gone', title: 'Gone', opensAt: 1, closesAt: 2 },
      { id: 'd3', studioId: 9850, productId: 'tee', title: 'Backwards', opensAt: 5, closesAt: 2 }] });
  assert.deepEqual(c.storefronts.map((s) => s.studioId), [9850], 'a storefront without the consent day is skipped');
  assert.deepEqual(c.products.map((p) => p.id), ['towel', 'tee'], 'an unknown kind and a product without a storefront are skipped');
  assert.deepEqual(c.drops.map((d) => d.id), ['d1'], 'a drop of a missing product or with a backwards window is skipped');
  assert.deepEqual(Sh.kinds(c), ['towel', 'apparel']);
  assert.deepEqual(Sh.filtered(c, 'towel').map((p) => p.id), ['towel']);
  assert.equal(Sh.towelFor(c, 9850).id, 'towel');
  assert.equal(Sh.towelFor(c, 1724), null);
  assert.deepEqual(Sh.product(c, 'towel').variants.map((v) => [v.label, v.inStock]), [['Natural', true], ['Out', false]]);
  assert.equal(Sh.product(c, 'towel').vatRate, 25, '25% unless the feed says otherwise');
  assert.equal(c.drops[0].reserved, 0);
  assert.equal(Sh.dropFor(c, 'tee').id, 'd1');
  assert.equal(Sh.httpsUrl('https://shop.example.org/angan'), 'https://shop.example.org/angan');
  assert.equal(Sh.httpsUrl('http://shop.example.org'), null);
  assert.equal(Sh.httpsUrl('javascript:alert(1)'), null);
  assert.equal(Sh.isEmpty(c), false);
  assert.equal(Sh.isEmpty(Sh.decode({ city: 'GOT', storefronts: [], products: [], drops: [] })), true, 'nothing listed: the apps show no shop');
  assert.equal(Sh.isEmpty(Sh.decode(null)), true);
  assert.equal(Sh.isEmpty(null), true);
  assert.equal(Sh.homeDrop(c, 5), null, 'a closed drop is no Home card');
  assert.equal(Sh.homeDrop(c, 0).id, 'd1');
});

test('the demo catalogue: fictional studios, no Bruce or Brüce marks, the race-day tee drop', () => {
  const now = at('2027-02-05T05:40:00Z');
  const c = Sh.decode(DEMO_SHOP(now));
  assert.equal(Sh.isEmpty(c), false);
  assert.equal(c.city, 'STO');
  assert.deepEqual([...new Set(c.products.map((p) => p.studioId))].sort(), c.storefronts.map((s) => s.studioId).sort(), 'every product has a storefront');
  assert.equal(new Set(c.products.map((p) => p.id)).size, c.products.length, 'ids are unique');
  for (const p of c.products) {
    assert.doesNotMatch(p.title, /br[uü]ce/i, 'no Bruce or Brüce mark on ' + p.title);
    assert.ok(p.priceOre > 0 && p.priceOre % 100 === 0, 'whole kronor in the demo');
  }
  for (const s of c.storefronts) assert.ok(!s.webshopUrl || s.webshopUrl.startsWith('https://shop.example.org'), 'fictional webshops only');
  assert.deepEqual(Sh.kinds(c), ['towel', 'mat', 'socks', 'apparel', 'sauna', 'other']);
  assert.equal(Sh.kr(Sh.towelFor(c, 9850).priceOre), '449 kr');
  assert.equal(Sh.towelFor(c, 9830), null);
  const d = Sh.homeDrop(c, now);
  assert.equal(d.title, 'Hornstull Race Day tee');
  assert.equal(Sh.dropState(d, now), 'open');
  assert.equal(Sh.countdownText(d, now), 'Closes in 2 d 14 h');
  assert.equal(Sh.progressText(d), '31 of 40');
  assert.deepEqual(Sh.productsFor(c, 9850).map((p) => p.title), ['Bastu towel', 'Felt sauna hat', 'Linen seat cover']);
  // The demo server answers the same routes as the worker: the city, one studio, Notify me on and off, the tap.
  assert.equal(handleServer('GET', '/shop?city=STO', {}).body.products.length, 7);
  assert.deepEqual(handleServer('GET', '/shop?city=GOT', {}).body.products, []);
  const one = handleServer('GET', '/shop/studio/9850', {}).body;
  assert.equal(one.storefront.sellerName, 'Ångan Bastu AB');
  assert.equal(one.products.length, 3);
  assert.equal(handleServer('GET', '/shop/studio/1724', {}).body.storefront, null);
  assert.equal(handleServer('PUT', '/me/notify/nope', {}).status, 404);
  assert.deepEqual(handleServer('PUT', '/me/notify/hornstull-race-day-2027', {}).body, { ok: true, notify: true, push: false, email: null });
  assert.deepEqual(handleServer('GET', '/me/shop', {}).body.notify, ['hornstull-race-day-2027']);
  assert.equal(handleServer('DELETE', '/me/notify/hornstull-race-day-2027', {}).body.notify, false);
  assert.deepEqual(handleServer('GET', '/me/shop', {}).body.notify, []);
  assert.equal(handleServer('POST', '/shop/tap', { productId: 'angan-bastu-towel' }).status, 200);
});

// ---------------------------------------------------------------- phase 3: drops

import { DEMO_FINISHER } from '../js/demo.js';

test('drops: ready at the desk, Reserve while the window is open, unlocked drops laid over the catalogue', () => {
  const linked = Object.assign({}, drop, { linkUrl: 'https://shop.example.org/karnan/race-day-tee' });
  assert.equal(Sh.reserveUrl(linked, at('2027-02-05T08:00:00Z')), 'https://shop.example.org/karnan/race-day-tee', 'open: Reserve opens the studio\'s own checkout');
  assert.equal(Sh.reserveUrl(linked, at('2027-01-20T00:00:00Z')), null, 'not open yet');
  assert.equal(Sh.reserveUrl(linked, at('2027-02-08T00:00:00Z')), null, 'closed');
  assert.equal(Sh.reserveUrl(Object.assign({}, linked, { linkUrl: 'http://x' }), at('2027-02-05T08:00:00Z')), null, 'https only');
  const ready = Object.assign({}, linked, { ready: true });
  assert.equal(Sh.dropState(ready, at('2027-02-05T08:00:00Z')), 'ready');
  assert.equal(Sh.countdownText(ready, at('2027-02-05T08:00:00Z')), 'Ready for pickup');
  assert.equal(Sh.reserveUrl(ready, at('2027-02-05T08:00:00Z')), null, 'at the desk: nothing to reserve');
  assert.equal(Sh.readyBody({ sellerName: 'Kärnan Reformer AB', pickupNote: 'At the desk, weekdays 06–20' }), 'Ready at the desk: Kärnan Reformer AB, at the desk, weekdays 06–20.');
  assert.equal(Sh.readyBody(null), 'Ready at the desk.');
  assert.equal(Sh.finisherBody({ metric: 'target', target: 20 }, 'Kärnan Reformer', drop), 'Only for people who hit 20. One print run, picked up at Kärnan Reformer. Pre-order until Sun 7 Feb.');
  assert.equal(Sh.finisherBody({ metric: 'classes' }, 'X', drop).slice(0, 40), 'Only for people who took part to the end');
  const c = Sh.decode({ city: 'STO', storefronts: [{ studioId: 9840, sellerName: 'Kärnan Reformer AB', city: 'STO', consentAt: '2026-11-12' }],
    products: [{ id: 'socks', studioId: 9840, title: 'Grip socks', kind: 'socks', priceOre: 14900, fulfilment: 'desk' }],
    drops: [{ id: 'race-day', studioId: 9840, productId: 'socks', title: 'Socks drop', opensAt: 1, closesAt: 9999999999999, ready: true }] });
  assert.equal(Sh.dropState(c.drops[0], 5), 'ready', 'the catalogue\'s ready is read');
  assert.equal(c.drops[0].unlocked, false);
  const mine = { notify: ['finisher-tee'], drops: [{ id: 'finisher-tee', studioId: 9840, productId: 'finisher', challengeId: 'abc', title: 'Finisher tee', opensAt: 1, closesAt: 9999999999999, unlocked: true }],
    products: [{ id: 'finisher', studioId: 9840, title: 'Finisher tee', kind: 'apparel', priceOre: 34900, fulfilment: 'pod', variants: [{ id: 'm', label: 'M' }] }] };
  const merged = Sh.merge(c, mine);
  assert.deepEqual(merged.products.map((p) => p.id), ['socks', 'finisher']);
  assert.deepEqual(merged.drops.map((d) => d.id), ['race-day', 'finisher-tee']);
  assert.equal(Sh.dropForChallenge(merged, 'abc').id, 'finisher-tee');
  assert.equal(Sh.dropForChallenge(merged, 'other'), null);
  assert.equal(Sh.dropForChallenge(c, 'abc'), null, 'nothing unlocked before the server says so');
  assert.equal(Sh.homeDrop(merged, 5).id, 'finisher-tee', 'the member\'s own drop comes first on Home');
  assert.equal(Sh.merge(merged, mine).products.length, 2, 'merging twice adds nothing');
  assert.equal(Sh.merge(c, { notify: [] }).drops.length, 1, 'a member with nothing unlocked');
});

test('the demo: the finished challenge unlocks the finisher tee, which stays out of the public catalogue', () => {
  const now = at('2027-02-05T05:40:00Z');
  const pub = Sh.decode(DEMO_SHOP(now));
  assert.ok(!pub.products.some((p) => p.id === 'karnan-finisher-tee'), 'not public');
  const mine = handleServer('GET', '/me/shop', {}).body;
  assert.deepEqual(mine.drops.map((d) => [d.id, d.challengeId, d.unlocked]), [['finisher-tee-2026', 'demoDone', true]]);
  assert.equal(mine.products[0].title, 'Finisher tee');
  // The demo server builds the drop from today's clock: a window that opened two days ago and closes in six.
  const merged = Sh.merge(pub, mine), today = Date.now();
  const d = Sh.dropForChallenge(merged, 'demoDone');
  assert.equal(Sh.dropState(d, today), 'open');
  assert.ok(Sh.reserveUrl(d, today));
  assert.equal(Sh.progressText(d), '12 of 30');
  assert.equal(Sh.homeDrop(merged, today).id, 'finisher-tee-2026');
  const done = handleServer('GET', '/challenges/demoDone', {}).body;
  assert.equal(done.challenge.metric, 'target');
  assert.deepEqual(done.leaderboard.map((r) => [r.name, r.score, r.done]), [['Friend Two', 23, true], ['Demo', 20, true], ['Friend One', 17, false]]);
  assert.equal(done.challenge.period.daysLeft, 0, 'over');
  for (const p of DEMO_FINISHER(now).products) assert.doesNotMatch(p.title, /br[uü]ce/i);
});

// ---------------------------------------------------------------- checkout (phase 4)

const towel = { id: 'towel', studioId: 9850, title: 'Bastu towel', kind: 'towel', priceOre: 44900, vatRate: 25, fulfilment: 'desk', linkUrl: null,
  variants: [{ id: 'natural', label: 'Natural', inStock: true }, { id: 'charcoal', label: 'Charcoal', inStock: false }] };
const connected = { studioId: 9850, sellerName: 'Ångan Bastu AB', city: 'STO', pickupNote: 'At the desk', consentAt: '2026-11-09', checkout: true, shippingOre: 4900 };
const cat = Sh.decode({ city: 'STO', storefronts: [connected, { studioId: 9840, sellerName: 'Kärnan Reformer AB', consentAt: '2026-11-12' }], products: [towel, Object.assign({}, towel, { id: 'socks', studioId: 9840, kind: 'socks' })], drops: [] });

test('checkout: the draft, its sums, the VAT and what stops it', () => {
  assert.equal(Sh.canBuy(cat, Sh.product(cat, 'towel')), true, 'the connected studio sells through Brüce');
  assert.equal(Sh.canBuy(cat, Sh.product(cat, 'socks')), false, 'a phase 3 storefront (no checkout field) keeps the desk');
  assert.equal(Sh.storefront(cat, 9840).checkout, false);
  assert.equal(Sh.ships(Sh.storefront(cat, 9850)), true);
  assert.equal(Sh.ships(Sh.storefront(cat, 9840)), false);
  const d = Sh.draft(cat, Sh.product(cat, 'towel'));
  assert.equal(d.variant.id, 'natural', 'the first in-stock variant is picked');
  assert.equal(d.delivery, 'pickup', 'pickup is the default');
  assert.equal(Sh.draft(cat, Sh.product(cat, 'towel'), { variantId: 'charcoal', delivery: 'ship' }).variant.id, 'natural', 'an out-of-stock pick falls back');
  assert.equal(Sh.draft(cat, Sh.product(cat, 'towel'), { delivery: 'ship' }).delivery, 'ship');
  assert.equal(Sh.draft(cat, Sh.product(cat, 'socks'), { delivery: 'ship' }).delivery, 'pickup', 'no shipping where the studio has none');
  d.qty = 2;
  assert.deepEqual(Sh.totals(d), { subtotalOre: 89800, shippingOre: 0, totalOre: 89800, vatOre: 17960 });
  d.delivery = 'ship';
  assert.deepEqual(Sh.totals(d), { subtotalOre: 89800, shippingOre: 4900, totalOre: 94700, vatOre: 18940 });
  assert.equal(Sh.itemLine('Bastu towel', 'Natural', 2), 'Bastu towel · Natural × 2');
  assert.equal(Sh.itemLine('Felt hat', null, 1), 'Felt hat');
  assert.deepEqual(Sh.checkoutBody(d), { productId: 'towel', variantId: 'natural', qty: 2, delivery: 'ship', returnTo: 'web' });
  assert.equal(Sh.draftProblem(d), null);
  assert.equal(Sh.draftProblem(Object.assign({}, d, { qty: 6 })), '1 to 5 of each');
  assert.equal(Sh.draftProblem(Object.assign({}, d, { variant: null })), Sh.PICK_VARIANT);
  assert.equal(Sh.draftProblem(Object.assign({}, d, { variant: towel.variants[1] })), Sh.OUT_OF_STOCK);
  assert.equal(Sh.draftProblem(Object.assign({}, d, { storefront: Object.assign({}, connected, { shippingOre: null }) })), Sh.NO_SHIPPING);
  assert.equal(Sh.draftProblem(Object.assign({}, d, { storefront: Object.assign({}, connected, { checkout: false }) })), Sh.NO_CHECKOUT);
  assert.equal(Sh.shipPrice(connected), 'Ship to me · 49 kr');
  assert.equal(Sh.sellerLine(connected, 'Hornstull'), 'Seller: Ångan Bastu AB, Hornstull. Receipt and withdrawal form come by email from the studio.');
  assert.equal(Sh.vatLine(25), 'incl. VAT 25%');
});

test('orders: the list as GET /me/orders sends it, the status words and the code', () => {
  const list = Sh.decodeOrders({ orders: [
    { id: 'old', studioId: 9850, totalOre: 100, status: 'collected', createdAt: '2026-10-01T10:00:00Z', items: [{ title: 'Hat' }], pickupCode: 'AAAAA' },
    { id: 'o1', studioId: 9850, items: [{ productId: 'towel', variantId: 'natural', title: 'Bastu towel', label: 'Natural', qty: 1, unitOre: 44900 }], totalOre: 44900, vatOre: 8980, delivery: 'pickup', status: 'ready', statusText: 'Ready for pickup', pickupCode: 'K7P2Q', sellerName: 'Ångan Bastu AB', createdAt: '2026-11-20T10:00:00Z' },
    { id: 'bad' },
  ] });
  assert.deepEqual(list.map((o) => o.id), ['o1', 'old'], 'newest first, a broken row skipped');
  assert.equal(Sh.isReady(list[0]), true);
  assert.equal(Sh.isDone(list[0]), false);
  assert.equal(Sh.isDone(list[1]), true, 'a collected order shows no code');
  assert.equal(Sh.orderLine(list[0]), 'Ready for pickup');
  assert.equal(Sh.orderLine({ status: 'paid', delivery: 'pickup' }), 'Paid · being prepared for pickup');
  assert.equal(Sh.orderLine({ status: 'paid', delivery: 'ship' }), 'Paid · being prepared');
  assert.equal(Sh.orderLine({ status: 'shipped', delivery: 'ship' }), 'On its way');
  assert.equal(Sh.orderLine({ status: 'shipped', delivery: 'pickup' }), 'On its way to the studio');
  assert.equal(Sh.orderLine({ status: 'printing' }), 'Being printed');
  assert.equal(list[1].items[0].qty, 1, 'defaults fill a thin row');
});

test('demo: the sauna is connected, its checkout answers, and the orders', () => {
  const c = Sh.decode(DEMO_SHOP());
  assert.equal(Sh.canBuy(c, Sh.product(c, 'angan-bastu-towel')), true);
  assert.equal(Sh.canBuy(c, Sh.product(c, 'karnan-grip-socks')), false, 'the other studios keep the desk and the webshop');
  assert.equal(Sh.storefront(c, 9850).shippingOre, 4900);
  const ok = handleServer('POST', '/checkout', { productId: 'angan-bastu-towel', variantId: 'natural', qty: 2, delivery: 'ship', returnTo: 'web' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.totalOre, 94700);
  assert.equal(ok.body.vatOre, 18940);
  assert.ok(ok.body.url.startsWith('https://checkout.stripe.com/'));
  assert.equal(handleServer('POST', '/checkout', { productId: 'karnan-grip-socks', variantId: 's-m', qty: 1, delivery: 'pickup' }).status, 409, 'no checkout at a studio without a connected account');
  assert.equal(handleServer('POST', '/checkout', { productId: 'angan-bastu-towel', qty: 1, delivery: 'pickup' }).status, 400, 'a size is needed');
  assert.equal(handleServer('POST', '/checkout', { productId: 'angan-bastu-towel', variantId: 'natural', qty: 9, delivery: 'pickup' }).status, 400);
  assert.equal(handleServer('POST', '/checkout', { productId: 'nope', qty: 1, delivery: 'pickup' }).status, 404);
  const orders = Sh.decodeOrders(handleServer('GET', '/me/orders').body);
  assert.deepEqual(orders.map((o) => o.status), ['ready', 'printing']);
  assert.equal(orders[0].pickupCode, 'K7P2Q');
  assert.equal(DEMO_ORDERS().length, 2);
  for (const o of DEMO_ORDERS()) assert.ok(!/br[uü]ce/i.test(JSON.stringify(o.items)), 'no product carries a Bruce or Brüce mark');
});
