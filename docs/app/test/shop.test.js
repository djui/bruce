// Studio shop (js/shop.js): the catalogue's reading and hiding rules, drop windows and progress, money, the demo
// catalogue and the demo server's shop answers, the same cases as ShopTests.swift.
// Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Sh from '../js/shop.js';
import { DEMO_SHOP, handleServer } from '../js/demo.js';

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
  assert.deepEqual(handleServer('GET', '/me/shop', {}).body, { notify: ['hornstull-race-day-2027'] });
  assert.equal(handleServer('DELETE', '/me/notify/hornstull-race-day-2027', {}).body.notify, false);
  assert.deepEqual(handleServer('GET', '/me/shop', {}).body, { notify: [] });
  assert.equal(handleServer('POST', '/shop/tap', { productId: 'angan-bastu-towel' }).status, 200);
});
