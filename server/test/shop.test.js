// Studio shop (phase 2): the feed's checks (shop.js), drop windows and progress, money, and the routes: the operator's
// import (a studio stays its first source's, Notify me rows survive a re-post), the public catalogue per city and studio
// (hidden where nothing is listed), the anonymous tap counter and Notify me on and off.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { d1 } from "./d1.js";
import worker, { catalogue } from "../src/worker.js";
import { cleanStorefront, cleanProduct, cleanDrop, dropState, dropProgress, untilText, krText, krExact, vatPart, dropOpenMessage, readyMessage } from "../src/shop.js";

const ok = (body) => new Response(JSON.stringify(body), { status: 200 });
const FEED = JSON.parse(readFileSync(new URL("../feeds/example-shop-feed.json", import.meta.url), "utf8"));
const towel = { id: "towel", title: "Bastu towel", kind: "towel", priceOre: 44900, fulfilment: "desk", variants: [{ id: "natural", label: "Natural" }, { id: "charcoal", label: "Charcoal" }] };
const tee = { id: "tee", title: "Race Day tee", kind: "apparel", priceOre: 34900, fulfilment: "pod" };
const drop = { id: "race-day", productId: "tee", title: "Race Day tee", opensAt: "2027-01-25T08:00:00Z", closesAt: "2027-02-07T22:00:00Z", minQty: 25, maxQty: 40, reserved: 31 };
const front = { studioId: 9850, sellerName: "Example Bastu AB", city: "STO", consentAt: "2026-11-09", webshopUrl: "https://shop.example.org/bastu", pickupNote: "At the desk", products: [towel, tee], drops: [drop] };

/** A fake Bruce (user 42 with a token "t"); records nothing else. */
function fakeWorld() {
  globalThis.fetch = async (url, init = {}) => {
    if (init.headers?.["X-Access-Token"] !== "t") return new Response("", { status: 401 });
    if (new URL(String(url)).pathname === "/v52/user/42") return ok({ user: { id: 42, email: "a@b.se", first_name: "A" } });
    return ok({});
  };
}
const call = (env, method, path, body, headers = { "X-Access-Token": "t", "X-User-Id": "42" }) => worker.fetch(new Request(`https://x${path}`, { method, headers, body: body && JSON.stringify(body) }), env, { waitUntil() {} })
  .then(async (r) => ({ status: r.status, body: await r.json(), headers: r.headers }));
const post = (env, body, token = "shop-secret") => call(env, "POST", "/shop/import", body, token ? { authorization: `Bearer ${token}` } : {});

test("the feed's checks: ids, kinds, prices in öre, https links, no Bruce or Brüce marks on a product", () => {
  const p = cleanProduct(towel);
  assert.equal(p.title, "Bastu towel");
  assert.equal(p.vatRate, 25, "25% unless the feed says otherwise");
  assert.deepEqual(p.variants.map((v) => v.id), ["natural", "charcoal"]);
  assert.equal(p.active, true);
  for (const bad of [{ ...towel, id: "Towel" }, { ...towel, title: "Brüce towel" }, { ...towel, title: "bruce tee" }, { ...towel, kind: "hat" }, { ...towel, priceOre: 449.5 },
    { ...towel, priceOre: -1 }, { ...towel, fulfilment: "post" }, { ...towel, linkUrl: "http://x" }, { ...towel, vatRate: 125 }, { ...towel, title: " " }, null]) {
    assert.equal(cleanProduct(bad), null, JSON.stringify(bad));
  }
  assert.deepEqual(cleanProduct({ ...towel, variants: [{ id: "a", label: "A" }, { id: "a", label: "B" }, { id: "Bad", label: "C" }, { label: "D" }] }).variants.map((v) => v.label), ["A"]);
  const d = cleanDrop(drop, ["tee"]);
  assert.equal(d.opensAt, Date.parse("2027-01-25T08:00:00Z"));
  assert.equal(d.reserved, 31);
  for (const bad of [{ ...drop, productId: "towel" }, { ...drop, closesAt: "2027-01-25T07:00:00Z" }, { ...drop, opensAt: "soon" }, { ...drop, minQty: -1 }, { ...drop, pickupFrom: "2027-02-30" },
    { ...drop, linkUrl: "http://x" }, { ...drop, title: "Bruce Race tee" }, { ...drop, challengeId: "bad id!" }]) {
    assert.equal(cleanDrop(bad, ["tee"]), null, JSON.stringify(bad));
  }
  const s = cleanStorefront(front);
  assert.equal(s.sellerName, "Example Bastu AB");
  assert.deepEqual(s.products.map((p) => p.id), ["towel", "tee"]);
  assert.deepEqual(s.drops.map((x) => x.id), ["race-day"]);
  assert.deepEqual(s.skipped, []);
  assert.equal(s.stripeAccount, null);
  for (const bad of [{ ...front, consentAt: null }, { ...front, city: "Stockholm" }, { ...front, sellerName: "" }, { ...front, studioId: "9850" }, { ...front, webshopUrl: "http://x" },
    { ...front, stripeAccount: "sk_live_x" }]) {
    assert.equal(cleanStorefront(bad), null, JSON.stringify(bad));
  }
  // Unreadable products and drops are skipped and named, the rest is kept; a drop of a skipped product goes with it.
  const partly = cleanStorefront({ ...front, products: [towel, { ...tee, kind: "tee" }], drops: [drop] });
  assert.deepEqual(partly.products.map((p) => p.id), ["towel"]);
  assert.deepEqual(partly.skipped, ["tee", "race-day"]);
  // The example feed is readable as a whole.
  const ex = cleanStorefront(FEED.storefronts[0]);
  assert.equal(ex.products.length, 3);
  assert.equal(ex.drops.length, 1);
  assert.deepEqual(ex.skipped, []);
});

test("drops: the window, the run's progress and the countdown", () => {
  const d = cleanDrop(drop, ["tee"]);
  const at = (s) => Date.parse(s);
  assert.equal(dropState(d, at("2027-01-20T00:00:00Z")), "upcoming");
  assert.equal(dropState(d, at("2027-02-01T00:00:00Z")), "open");
  assert.equal(dropState(d, at("2027-02-08T00:00:00Z")), "closed");
  assert.equal(dropState({ ...d, ready: true }, at("2027-02-08T00:00:00Z")), "ready");
  assert.deepEqual(dropProgress(d), { reserved: 31, goal: 40, fraction: 0.775, text: "31 of 40" });
  assert.equal(dropProgress({ ...d, maxQty: null }).text, "31 of 25");
  assert.equal(dropProgress({ ...d, maxQty: null, minQty: 0 }).text, "31 reserved");
  assert.equal(dropProgress({ ...d, reserved: 50 }).fraction, 1);
  assert.equal(untilText(d.closesAt, at("2027-02-05T08:00:00Z")), "2 d 14 h");
  assert.equal(untilText(d.closesAt, at("2027-02-07T19:30:00Z")), "2 h");
  assert.equal(untilText(d.closesAt, at("2027-02-07T21:50:00Z")), "10 min");
  assert.equal(untilText(d.closesAt, at("2027-02-08T00:00:00Z")), "");
});

test("money: kronor incl. VAT, the exact rows and the VAT inside a price", () => {
  assert.equal(krText(44900), "449 kr");
  assert.equal(krText(129500), "1,295 kr");
  assert.equal(krText(34950), "350 kr");
  assert.equal(krExact(44900), "449,00 kr");
  assert.equal(krExact(8980), "89,80 kr");
  assert.equal(krExact(0), "0,00 kr");
  assert.equal(vatPart(44900, 25), 8980);
  assert.equal(vatPart(34900, 25), 6980);
  assert.equal(vatPart(10000, 0), 0);
  const d = cleanDrop(drop, ["tee"]);
  assert.deepEqual(dropOpenMessage(d, cleanProduct(tee), cleanStorefront(front)),
    { title: "Drop open: Race Day tee", body: "Pre-order 349 kr until Sun 7 Feb. Pick up at Example Bastu AB. The studio sells it; Brüce only reminds you." });
  assert.deepEqual(readyMessage("Race Day tee", { sellerName: "Example Bastu AB", pickupNote: "every day 07–22" }, "K7P2Q"),
    { title: "Ready for pickup: Race Day tee", body: "Show code K7P2Q at Example Bastu AB, every day 07–22." });
  assert.equal(readyMessage("Race Day tee", { sellerName: "Example Bastu AB" }).body, "Collect it at Example Bastu AB.");
});

test("HTTP: the operator's import needs the token and replaces its own source's storefronts; the catalogue is per city and studio", async () => {
  const DB = d1();
  assert.equal((await post({ DB }, { source: "op", storefronts: [front] })).status, 503, "no token configured");
  const env = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  assert.equal((await post(env, { source: "op", storefronts: [front] }, null)).status, 401);
  assert.equal((await post(env, { source: "op", storefronts: [front] }, "wrong")).status, 401);
  assert.equal((await post(env, { source: "OP", storefronts: [front] })).status, 400);
  assert.equal((await post(env, { source: "op", storefronts: "x" })).status, 400);
  assert.equal((await call(env, "GET", "/shop")).status, 400, "a city is required");
  assert.deepEqual((await call(env, "GET", "/shop?city=STO")).body, { city: "STO", storefronts: [], products: [], drops: [] });
  const first = await post(env, { source: "op", storefronts: [front, { ...front, studioId: 9830, products: [{ ...towel, id: "mat", kind: "mat", title: "Cork yoga mat" }], drops: [] }, { studioId: 1 }] });
  assert.equal(first.status, 200);
  assert.deepEqual(first.body, { ok: true, source: "op", imported: 2, skipped: ["studio 1"] });
  const city = await call(env, "GET", "/shop?city=sto");
  assert.equal(city.headers.get("Cache-Control"), "public, max-age=300");
  assert.deepEqual(city.body.storefronts.map((s) => [s.studioId, s.sellerName, s.webshopUrl]), [[9830, "Example Bastu AB", "https://shop.example.org/bastu"], [9850, "Example Bastu AB", "https://shop.example.org/bastu"]]);
  assert.deepEqual(city.body.products.map((p) => [p.id, p.studioId, p.priceOre, p.variants.map((v) => v.id)]), [["mat", 9830, 44900, ["natural", "charcoal"]], ["towel", 9850, 44900, ["natural", "charcoal"]], ["tee", 9850, 34900, []]]);
  assert.deepEqual(city.body.drops.map((d) => [d.id, d.studioId, d.reserved, d.maxQty]), [["race-day", 9850, 31, 40]]);
  assert.equal(city.body.storefronts[0].stripeAccount, undefined, "nothing of Stripe reaches the catalogue in phase 2");
  assert.deepEqual((await call(env, "GET", "/shop?city=GOT")).body.storefronts, [], "another city has none");
  const one = await call(env, "GET", "/shop/studio/9850");
  assert.equal(one.body.storefront.sellerName, "Example Bastu AB");
  assert.deepEqual(one.body.products.map((p) => p.id), ["towel", "tee"]);
  assert.equal((await call(env, "GET", "/shop/studio/1724")).body.storefront, null, "no listing: nothing to show");
  // Another source can't take a studio over; its own post replaces its storefronts (9830 goes, 9850 is updated).
  const other = await post(env, { source: "studio-itself", storefronts: [{ ...front, sellerName: "Taken" }] });
  assert.deepEqual(other.body, { ok: true, source: "studio-itself", imported: 0, skipped: ["studio 9850"] });
  await post(env, { source: "op", storefronts: [{ ...front, pickupNote: "Weekdays only", products: [{ ...towel, priceOre: 47900 }, tee], drops: [drop] }] });
  const again = await call(env, "GET", "/shop?city=STO");
  assert.deepEqual(again.body.storefronts.map((s) => [s.studioId, s.pickupNote]), [[9850, "Weekdays only"]]);
  assert.equal(again.body.products.find((p) => p.id === "towel").priceOre, 47900);
  // A product switched off hides with its drop; a storefront with nothing active hides altogether.
  await post(env, { source: "op", storefronts: [{ ...front, products: [{ ...towel, active: false }, { ...tee, active: false }], drops: [drop] }] });
  assert.deepEqual((await call(env, "GET", "/shop?city=STO")).body, { city: "STO", storefronts: [], products: [], drops: [] });
  assert.equal((await post(env, { source: "op", storefronts: Array.from({ length: 101 }, (_, i) => ({ ...front, studioId: 100 + i })) })).status, 409);
});

test("HTTP: a closed drop lingers 30 days; a drop tied to a challenge is not in the public catalogue", async () => {
  const DB = d1();
  const env = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  await post(env, { source: "op", storefronts: [{ ...front, drops: [drop, { ...drop, id: "finisher", challengeId: "abc123", title: "Finisher tee" }] }] });
  const at = (s) => Date.parse(s);
  assert.deepEqual((await catalogue(DB, { city: "STO" }, at("2027-02-20T00:00:00Z"))).drops.map((d) => d.id), ["race-day"]);
  assert.deepEqual((await catalogue(DB, { city: "STO" }, at("2027-03-20T00:00:00Z"))).drops, []);
});

test("HTTP: taps count per product and day without a user; the stats route needs the token", async () => {
  const DB = d1();
  const env = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  await post(env, { source: "op", storefronts: [front] });
  assert.equal((await call(env, "POST", "/shop/tap", { productId: "nope" }, {})).status, 404);
  assert.equal((await call(env, "POST", "/shop/tap", { productId: "Bad Id" }, {})).status, 400);
  for (let i = 0; i < 3; i++) assert.equal((await call(env, "POST", "/shop/tap", { productId: "towel" }, {})).status, 200);
  await call(env, "POST", "/shop/tap", { productId: "tee" }, {});
  assert.deepEqual(DB.rows("taps").map((r) => [r.product_id, r.n]).sort(), [["tee", 1], ["towel", 3]]);
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(DB.rows("taps")[0].day));
  assert.equal((await call(env, "GET", "/shop/stats", null, {})).status, 401);
  const stats = await call(env, "GET", "/shop/stats", null, { authorization: "Bearer shop-secret" });
  assert.deepEqual(stats.body.taps.map((t) => [t.productId, t.n]), [["tee", 1], ["towel", 3]]);
  assert.deepEqual(stats.body.notify, []);
});

test("HTTP: Notify me stores the login, lists on every device, keeps the row while a drop is watched, survives a re-post", async () => {
  const DB = d1();
  const env = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  fakeWorld();
  await post(env, { source: "op", storefronts: [{ ...front, drops: [drop, { ...drop, id: "second", title: "Second" }] }] });
  assert.equal((await worker.fetch(new Request("https://x/me/notify/race-day", { method: "PUT", headers: { "X-Access-Token": "nope", "X-User-Id": "42" } }), env, {})).status, 401);
  assert.equal((await call(env, "PUT", "/me/notify/unknown")).status, 404);
  const on = await call(env, "PUT", "/me/notify/race-day");
  assert.equal(on.status, 200);
  assert.deepEqual([on.body.notify, on.body.push, on.body.email], [true, false, null]);
  assert.ok(DB.t.get(42), "the login is stored: the push and email need the row");
  await call(env, "PUT", "/me/notify/second");
  await call(env, "PUT", "/me/notify/second");
  assert.deepEqual((await call(env, "GET", "/me/shop")).body, { notify: ["race-day", "second"], drops: [], products: [] });
  const stats = await call(env, "GET", "/shop/stats", null, { authorization: "Bearer shop-secret" });
  assert.deepEqual(stats.body.notify, [{ dropId: "race-day", n: 1 }, { dropId: "second", n: 1 }]);
  // A re-post keeps the rows of drops that stay and drops the rows of drops that went.
  await post(env, { source: "op", storefronts: [{ ...front, drops: [{ ...drop, reserved: 35 }] }] });
  assert.deepEqual((await call(env, "GET", "/me/shop")).body.notify, ["race-day"]);
  const off = await call(env, "DELETE", "/me/notify/race-day");
  assert.deepEqual(off.body, { ok: true, notify: false });
  assert.deepEqual((await call(env, "GET", "/me/shop")).body.notify, []);
  assert.equal(DB.t.get(42), undefined, "nothing left to do: the row goes");
  // DELETE /me clears the notify rows too.
  await call(env, "PUT", "/me/notify/race-day");
  await call(env, "DELETE", "/me");
  assert.equal(DB.rows("notify").length, 0);
});

// ---------------------------------------------------------------- phase 3: drops

import { isFinisher } from "../src/shop.js";
import { sendDropNotices } from "../src/worker.js";

const device = { token: "ab".repeat(32), env: "production" };
/** A challenge that is already over (the route refuses to create one) with its participants, straight into the tables. */
function pastChallenge(DB, id, { owner, metric, target = null, members }) {
  DB.sql.prepare(`INSERT INTO challenges (id, owner_id, title, metric, target, start_day, end_day, repeat_monthly, created_at)
      VALUES (?, ?, 'Past', ?, ?, '2026-09-01', '2026-09-30', 0, '2026-09-01T00:00:00Z')`).run(id, owner, metric, target);
  for (const [uid, status] of Object.entries(members)) {
    DB.sql.prepare("INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?, ?, 'P', ?, NULL, '2026-09-01T00:00:00Z')").run(id, +uid, status);
  }
}

test("a finisher: reached the target of an 'everyone hits N' challenge, or took part in any other to its end", () => {
  const target = { metric: "target", target: 20, end: "2027-01-31" };
  assert.equal(isFinisher(target, { status: "accepted", done: true }, "2027-01-28"), true, "done before the end counts");
  assert.equal(isFinisher(target, { status: "accepted", done: false }, "2027-02-10"), false);
  assert.equal(isFinisher(target, { status: "invited", done: true }, "2027-02-10"), false);
  assert.equal(isFinisher(target, null, "2027-02-10"), false);
  const most = { metric: "classes", end: "2027-01-31" };
  assert.equal(isFinisher(most, { status: "accepted" }, "2027-01-31"), false, "still running");
  assert.equal(isFinisher(most, { status: "accepted" }, "2027-02-01"), true);
});

/** A fake Bruce for users 42 and 7 (tokens t42, t7), friends of each other; APNs and Resend record what was sent. */
function fakePeople() {
  const sent = { pushes: [], emails: [] };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.startsWith("https://api.push.apple.com/")) { sent.pushes.push(JSON.parse(init.body)); return ok({}); }
    if (url === "https://api.resend.com/emails") { sent.emails.push(JSON.parse(init.body)); return ok({ id: "e" }); }
    const uid = +String(init.headers?.["X-Access-Token"] ?? "").replace(/^t/, "");
    if (![42, 7].includes(uid)) return new Response("", { status: 401 });
    const u = new URL(url);
    if (u.pathname.startsWith("/v52/user/")) return ok({ user: { id: uid, email: `${uid}@b.se`, first_name: uid === 42 ? "Uwe" : "Robin" } });
    if (u.pathname === "/v52/friend") return ok({ friends: [{ id: 1, friend_user: { id: uid === 42 ? 7 : 42, first_name: "F" } }] });
    if (u.pathname === "/v52/booking") return ok({ bookings: [], metadata: {} });
    return ok({ classes: [], metadata: {} });
  };
  return sent;
}
const as = (uid, env, method, path, body) => worker.fetch(new Request(`https://x${path}`, { method, headers: { "X-Access-Token": `t${uid}`, "X-User-Id": String(uid) },
  body: body && JSON.stringify(body) }), env, { waitUntil() {} }).then(async (r) => ({ status: r.status, body: await r.json() }));

test("HTTP: a drop tied to a challenge, and its product, show only to that challenge's finishers", async () => {
  const DB = d1();
  const env = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  fakePeople();
  // 42 started "Everyone hits 2" last month and hit it; 7 accepted but did not. A finisher tee drop hangs on it.
  const chId = "hits2";
  pastChallenge(DB, chId, { owner: 42, metric: "target", target: 2, members: { 42: "accepted", 7: "accepted" } });
  const detail = (ids) => JSON.stringify(ids.map((id) => ({ at: "2026-09-10T16:00:00Z", k: "c", id, t: "Reformer", s: 9840, m: 50, c: ["22"], ci: true })));
  DB.sql.prepare("INSERT INTO daily_counts (user_id, day, visits, classes, detail) VALUES (42, '2026-09-10', 2, 2, ?), (7, '2026-09-10', 1, 1, ?)").run(detail([1, 2]), detail([3]));
  const finisher = { ...drop, id: "finisher-tee", productId: "finisher", title: "Finisher tee", challengeId: chId };
  const product = { ...tee, id: "finisher", title: "Finisher tee" };
  await post(env, { source: "op", storefronts: [{ ...front, products: [towel, tee, product], drops: [drop, finisher] }] });
  const city = await call(env, "GET", "/shop?city=STO");
  assert.deepEqual(city.body.products.map((p) => p.id), ["towel", "tee"], "the finisher tee is not in the public catalogue");
  assert.deepEqual(city.body.drops.map((d) => d.id), ["race-day"]);
  assert.equal(city.body.drops[0].ready, false);
  const mine = await as(42, env, "GET", "/me/shop");
  assert.deepEqual(mine.body.drops.map((d) => [d.id, d.unlocked, d.challengeId]), [["finisher-tee", true, chId]]);
  assert.deepEqual(mine.body.products.map((p) => p.id), ["finisher"]);
  const theirs = await as(7, env, "GET", "/me/shop");
  assert.deepEqual([theirs.body.drops, theirs.body.products], [[], []], "7 did not reach the target");
  // A "most classes" challenge unlocks its drop for everyone who took part, once it is over.
  pastChallenge(DB, "most", { owner: 7, metric: "classes", members: { 7: "accepted", 42: "invited" } });
  await post(env, { source: "op", storefronts: [{ ...front, products: [towel, tee, product], drops: [drop, { ...finisher, challengeId: "most" }] }] });
  assert.equal((await as(7, env, "GET", "/me/shop")).body.drops.length, 1);
  assert.equal((await as(42, env, "GET", "/me/shop")).body.drops.length, 0, "invited, never accepted");
  assert.equal((await as(42, env, "PUT", "/me/notify/finisher-tee")).status, 200, "Notify me works on an unlocked drop too");
});

test("cron: 'Drop open' once when the window opens (push and email to the Notify me list), 'Ready for pickup' once the feed says so", async () => {
  const DB = d1([{ user_id: 42, access_token: "t42", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "42@b.se" }) }]);
  const env = await (async () => {
    const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
    const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
    return { DB, SHOP_FEED_TOKEN: "shop-secret", APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T",
             APNS_TOPIC: "net.dauernheim.bruce", RESEND_API_KEY: "re_test", EMAIL_FROM: "Brüce <autobook@example.com>" };
  })();
  const sent = fakePeople();
  await post(env, { source: "op", storefronts: [front] });
  await as(42, env, "PUT", "/me/notify/race-day");
  await as(7, env, "PUT", "/me/notify/race-day");   // no device, no stored email beyond Bruce's: email only
  const at = (s) => Date.parse(s);
  await sendDropNotices(env, at("2027-01-25T07:59:00Z"));
  assert.equal(sent.pushes.length + sent.emails.length, 0, "not open yet");
  await sendDropNotices(env, at("2027-01-25T08:00:30Z"));
  assert.equal(sent.pushes.length, 1, "42's device");
  assert.deepEqual(sent.pushes[0].aps.alert, { title: "Drop open: Race Day tee", body: "Pre-order 349 kr until Sun 7 Feb. Pick up at Example Bastu AB. The studio sells it; Brüce only reminds you." });
  assert.equal(sent.pushes[0].aps.category, "SHOP_DROP");
  assert.deepEqual([sent.pushes[0].dropId, sent.pushes[0].productId], ["race-day", "tee"]);
  assert.equal(sent.emails.length, 2, "both by email");
  assert.match(sent.emails[0].text, /Open the listing: https:\/\/djui\.github\.io\/bruce\/app\/#\/home\/product\/tee/);
  await sendDropNotices(env, at("2027-01-25T08:01:00Z"));
  assert.equal(sent.pushes.length, 1, "once");
  assert.ok(DB.rows("drops")[0].opened_sent_at);
  // The operator marks it ready: "Ready for pickup" to the list, once; a re-post with ready keeps it sent.
  await post(env, { source: "op", storefronts: [{ ...front, drops: [{ ...drop, ready: true }] }] });
  assert.ok(DB.rows("drops")[0].ready_at);
  assert.equal((await call(env, "GET", "/shop?city=STO")).body.drops[0].ready, true);
  await sendDropNotices(env, at("2027-02-20T09:00:00Z"));
  assert.equal(sent.pushes.length, 2);
  assert.deepEqual(sent.pushes[1].aps.alert, { title: "Ready for pickup: Race Day tee", body: "Collect it at Example Bastu AB, At the desk." });
  assert.equal(sent.emails.length, 4);
  await post(env, { source: "op", storefronts: [{ ...front, drops: [{ ...drop, ready: true }] }] });
  await sendDropNotices(env, at("2027-02-20T09:01:00Z"));
  assert.equal(sent.pushes.length, 2, "still once");
  // Taken back and marked ready again: told again.
  await post(env, { source: "op", storefronts: [{ ...front, drops: [{ ...drop, ready: false }] }] });
  assert.equal(DB.rows("drops")[0].ready_at, null);
  await post(env, { source: "op", storefronts: [{ ...front, drops: [{ ...drop, ready: true }] }] });
  await sendDropNotices(env, at("2027-02-21T09:00:00Z"));
  assert.equal(sent.pushes.length, 3);
  // A window that opened more than 12 hours before the cron saw it is only marked.
  await post(env, { source: "op", storefronts: [{ ...front, drops: [drop, { ...drop, id: "late", opensAt: "2027-01-01T08:00:00Z" }] }] });
  await as(42, env, "PUT", "/me/notify/late");
  await sendDropNotices(env, at("2027-01-02T08:00:00Z"));
  assert.equal(sent.pushes.length, 3);
  assert.ok(DB.rows("drops", "id = 'late'")[0].opened_sent_at);
});
