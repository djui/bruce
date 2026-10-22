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

// ---------------------------------------------------------------- phase 4: checkout

import { verifyStripeSignature, cleanCheckout, orderTotals, pickupCode, orderStatusText, orderConfirmedMessage, orderUpdateMessage } from "../src/shop.js";
import { stripeForm } from "../src/worker.js";

/** Signs a raw body the way Stripe does: HMAC-SHA256 of "<t>.<body>" with the endpoint secret. */
async function sign(body, secret, t) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${body}`));
  return `t=${t},v1=${[...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

test("the Stripe signature: the right secret and a fresh timestamp, else refused", async () => {
  const body = '{"id":"evt_1","type":"checkout.session.completed"}';
  const now = Date.parse("2027-02-05T08:00:00Z");
  const header = await sign(body, "whsec_test", Math.floor(now / 1000));
  assert.equal(await verifyStripeSignature(header, body, "whsec_test", now), true);
  assert.equal(await verifyStripeSignature(header, body, "whsec_other", now), false, "another secret");
  assert.equal(await verifyStripeSignature(header, body + " ", "whsec_test", now), false, "a changed body");
  assert.equal(await verifyStripeSignature(header, body, "whsec_test", now + 301_000), false, "a replay after five minutes");
  assert.equal(await verifyStripeSignature(header, body, "whsec_test", now + 299_000), true, "within the tolerance");
  assert.equal(await verifyStripeSignature(await sign(body, "whsec_test", Math.floor(now / 1000)) + ",v1=" + "0".repeat(64), body, "whsec_test", now), true, "any v1 may match");
  assert.equal(await verifyStripeSignature("t=1,v0=abc", body, "whsec_test", now), false, "no v1");
  assert.equal(await verifyStripeSignature(null, body, "whsec_test", now), false);
  assert.equal(await verifyStripeSignature(header, body, "", now), false);
});

test("checkout: what the apps may ask for, the sums with VAT and shipping, the pickup code, the words", () => {
  const storefront = { studioId: 9850, sellerName: "Example Bastu AB", shippingOre: 4900 };
  const product = { id: "towel", title: "Bastu towel", priceOre: 44900, vatRate: 25, variants: [{ id: "natural", label: "Natural", inStock: true }, { id: "x", label: "Out", inStock: false }] };
  const ok = cleanCheckout({ variantId: "natural", qty: 2, delivery: "ship" }, { storefront, product });
  assert.equal(ok.error, undefined);
  assert.deepEqual(orderTotals(ok), { items: [{ productId: "towel", variantId: "natural", title: "Bastu towel", label: "Natural", qty: 2, unitOre: 44900 }],
    subtotalOre: 89800, shippingOre: 4900, totalOre: 94700, vatOre: 18940 });
  assert.equal(cleanCheckout({ variantId: "natural" }, { storefront, product }).delivery, "pickup", "pickup is the default");
  assert.equal(orderTotals(cleanCheckout({ variantId: "natural" }, { storefront, product })).shippingOre, 0);
  for (const [body, re] of [[{}, /size or option/], [{ variantId: "x" }, /out of stock/], [{ variantId: "natural", qty: 6 }, /qty/], [{ variantId: "natural", qty: 1.5 }, /qty/],
    [{ variantId: "natural", delivery: "drone" }, /delivery/], [{ variantId: "natural", delivery: "ship" }, /does not ship/]]) {
    const front = re.test("does not ship") ? { ...storefront, shippingOre: null } : storefront;
    assert.match(cleanCheckout(body, { storefront: front, product }).error, re, JSON.stringify(body));
  }
  assert.match(cleanCheckout({}, { storefront, product: null }).error, /not found/);
  const closed = { opensAt: 1, closesAt: 2 };
  assert.match(cleanCheckout({ variantId: "natural" }, { storefront, product, drop: closed }, 5).error, /not open/);
  assert.equal(cleanCheckout({ variantId: "natural" }, { storefront, product, drop: { opensAt: 1, closesAt: 9 } }, 5).drop.closesAt, 9);
  const plain = { id: "hat", title: "Felt hat", priceOre: 29900, vatRate: 25, variants: [] };
  assert.equal(cleanCheckout({}, { storefront, product: plain }).variant, null, "no variants: none needed");
  const code = pickupCode();
  assert.match(code, /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{5}$/, "nothing that reads as 0, O, 1, I or L");
  assert.equal(pickupCode(() => new Uint8Array([0, 1, 2, 30, 31])), "ABC9A");
  assert.equal(orderStatusText("paid", "pickup"), "Paid · being prepared for pickup");
  assert.equal(orderStatusText("shipped", "ship"), "On its way");
  assert.equal(orderStatusText("ready", "pickup"), "Ready for pickup");
  const order = { items: [{ title: "Bastu towel", label: "Natural", qty: 2 }], totalOre: 94700, delivery: "pickup", pickupCode: "K7P2Q" };
  assert.deepEqual(orderConfirmedMessage(order, storefront), { title: "Order confirmed: Bastu towel · Natural × 2", body: "947 kr paid to Example Bastu AB. Show code K7P2Q at the desk once it's ready; we'll tell you." });
  assert.match(orderConfirmedMessage({ ...order, delivery: "ship" }, storefront).body, /ships to the address you gave Stripe/);
  assert.deepEqual(orderUpdateMessage(order, "ready", { sellerName: "Example Bastu AB", pickupNote: "At the desk" }), { title: "Ready for pickup: Bastu towel · Natural × 2", body: "Show code K7P2Q at Example Bastu AB, At the desk." });
  assert.equal(orderUpdateMessage(order, "shipped", storefront).body, "Your order is on its way to Example Bastu AB. We'll tell you when it's ready for pickup.");
  assert.equal(stripeForm({ mode: "payment", line_items: [{ quantity: 2, price_data: { currency: "sek", unit_amount: 44900 } }], shipping_address_collection: { allowed_countries: ["SE"] }, skip: null }).toString(),
    "mode=payment&line_items%5B0%5D%5Bquantity%5D=2&line_items%5B0%5D%5Bprice_data%5D%5Bcurrency%5D=sek&line_items%5B0%5D%5Bprice_data%5D%5Bunit_amount%5D=44900&shipping_address_collection%5Ballowed_countries%5D%5B0%5D=SE");
});

/** A fake Bruce (42, 7), Stripe (every Checkout Session is cs_test_1) and the notices; records what was sent. */
function fakeStripeWorld() {
  const sent = { pushes: [], emails: [], stripe: [] };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.startsWith("https://api.push.apple.com/")) { sent.pushes.push(JSON.parse(init.body)); return ok({}); }
    if (url === "https://api.resend.com/emails") { sent.emails.push(JSON.parse(init.body)); return ok({ id: "e" }); }
    if (url.startsWith("https://api.stripe.com/")) { sent.stripe.push({ url, headers: init.headers, form: new URLSearchParams(init.body) }); return ok({ id: "cs_test_1", url: "https://checkout.stripe.com/c/pay/cs_test_1" }); }
    const uid = +String(init.headers?.["X-Access-Token"] ?? "").replace(/^t/, "");
    if (![42, 7].includes(uid)) return new Response("", { status: 401 });
    const u = new URL(url);
    if (u.pathname.startsWith("/v52/user/")) return ok({ user: { id: uid, email: `${uid}@b.se`, first_name: "Uwe" } });
    if (u.pathname === "/v52/booking") return ok({ bookings: [], metadata: {} });
    return ok({ classes: [], metadata: {} });
  };
  return sent;
}
async function stripeEnv(DB, extra) {
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { DB, SHOP_FEED_TOKEN: "shop-secret", STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: "whsec_test", POD_WEBHOOK_SECRET: "pod-secret",
           APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce",
           RESEND_API_KEY: "re_test", EMAIL_FROM: "Brüce <autobook@example.com>", ...extra };
}
const connected = { ...front, stripeAccount: "acct_1ExampleStudio", shippingOre: 4900 };
const hook = (env, raw, header) => worker.fetch(new Request("https://x/hooks/stripe", { method: "POST", headers: header ? { "stripe-signature": header } : {}, body: raw }), env, { waitUntil() {} })
  .then(async (r) => ({ status: r.status, body: await r.json() }));
const paidEvent = (session, extra = {}) => JSON.stringify({ id: "evt_1", type: "checkout.session.completed", account: "acct_1ExampleStudio",
  data: { object: { id: session, payment_status: "paid", amount_total: 44900, client_reference_id: "42", metadata: { userId: "42", productId: "towel", variantId: "natural", qty: "1", delivery: "pickup", dropId: "", studioId: "9850", ...extra } } } });

test("HTTP: checkout is dormant without a Stripe key or a connected studio; with both it opens a Session on the studio's account", async () => {
  const DB = d1([{ user_id: 42, access_token: "t42", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "42@b.se" }) }]);
  const sent = fakeStripeWorld();
  const quiet = { DB, SHOP_FEED_TOKEN: "shop-secret" };
  await post(quiet, { source: "op", storefronts: [front] });
  assert.equal((await as(42, quiet, "POST", "/checkout", { productId: "towel", variantId: "natural" })).status, 503, "no key: the apps keep the link-out");
  assert.equal((await call(quiet, "GET", "/shop?city=STO")).body.storefronts[0].checkout, false);
  const env = await stripeEnv(DB);
  assert.equal((await call(env, "GET", "/shop?city=STO")).body.storefronts[0].checkout, false, "a key, but no connected account");
  assert.equal((await as(42, env, "POST", "/checkout", { productId: "towel", variantId: "natural" })).status, 409);
  await post(env, { source: "op", storefronts: [connected] });
  const city = await call(env, "GET", "/shop?city=STO");
  assert.deepEqual([city.body.storefronts[0].checkout, city.body.storefronts[0].shippingOre], [true, 4900]);
  assert.equal(city.body.storefronts[0].stripeAccount, undefined, "the account id stays on the server");
  assert.equal((await worker.fetch(new Request("https://x/checkout", { method: "POST", headers: { "X-Access-Token": "nope", "X-User-Id": "42" }, body: "{}" }), env, {})).status, 401);
  assert.equal((await as(42, env, "POST", "/checkout", { productId: "nope" })).status, 404);
  assert.equal((await as(42, env, "POST", "/checkout", { productId: "towel" })).status, 400, "a size or option is needed");
  const r = await as(42, env, "POST", "/checkout", { productId: "towel", variantId: "natural", qty: 2, delivery: "ship", returnTo: "app" });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { url: "https://checkout.stripe.com/c/pay/cs_test_1", sessionId: "cs_test_1", totalOre: 94700, vatOre: 18940 });
  assert.equal(sent.stripe.length, 1);
  const req = sent.stripe[0];
  assert.equal(req.url, "https://api.stripe.com/v1/checkout/sessions");
  assert.equal(req.headers["Stripe-Account"], "acct_1ExampleStudio", "a direct charge on the studio's account");
  assert.equal(req.headers.authorization, "Bearer sk_test_x");
  assert.equal(req.form.get("mode"), "payment");
  assert.equal(req.form.get("line_items[0][price_data][product_data][name]"), "Bastu towel · Natural");
  assert.equal(req.form.get("line_items[0][price_data][unit_amount]"), "44900");
  assert.equal(req.form.get("line_items[0][quantity]"), "2");
  assert.equal(req.form.get("line_items[1][price_data][product_data][name]"), "Shipping");
  assert.equal(req.form.get("line_items[1][price_data][unit_amount]"), "4900");
  assert.equal(req.form.get("shipping_address_collection[allowed_countries][0]"), "SE", "the address goes to Stripe, never here");
  assert.equal(req.form.get("success_url"), "bruece://orders?paid={CHECKOUT_SESSION_ID}");
  assert.equal(req.form.get("customer_email"), "42@b.se");
  assert.deepEqual([req.form.get("metadata[userId]"), req.form.get("metadata[productId]"), req.form.get("metadata[delivery]")], ["42", "towel", "ship"]);
  assert.equal(req.form.get("payment_method_types[0]"), null, "Stripe's Dashboard decides the methods");
  const web = await as(42, env, "POST", "/checkout", { productId: "towel", variantId: "natural" });
  assert.equal(sent.stripe[1].form.get("success_url"), "https://djui.github.io/bruce/app/#/home/orders?paid={CHECKOUT_SESSION_ID}");
  assert.equal(sent.stripe[1].form.get("shipping_address_collection[allowed_countries][0]"), null, "pickup asks for no address");
  assert.equal(web.body.totalOre, 44900);
});

test("HTTP: the Stripe webhook writes one order per session with a pickup code and tells the member; the print partner moves it on", async () => {
  const DB = d1([{ user_id: 42, access_token: "t42", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "42@b.se" }) }]);
  const sent = fakeStripeWorld();
  const env = await stripeEnv(DB);
  await post(env, { source: "op", storefronts: [{ ...connected, drops: [{ ...drop, opensAt: "2020-01-01T00:00:00Z", closesAt: "2099-01-01T00:00:00Z" }] }] });
  const raw = paidEvent("cs_test_1");
  assert.equal((await hook({ ...env, STRIPE_WEBHOOK_SECRET: undefined }, raw, await sign(raw, "whsec_test", Math.floor(Date.now() / 1000)))).status, 503);
  assert.equal((await hook(env, raw)).status, 400, "no signature");
  assert.equal((await hook(env, raw, await sign(raw, "whsec_wrong", Math.floor(Date.now() / 1000)))).status, 400);
  assert.equal((await hook(env, raw, await sign(raw, "whsec_test", Math.floor(Date.now() / 1000) - 3600))).status, 400, "an old event");
  const other = JSON.stringify({ id: "evt_2", type: "payment_intent.succeeded" });
  assert.deepEqual((await hook(env, other, await sign(other, "whsec_test", Math.floor(Date.now() / 1000)))).body, { received: true, ignored: "payment_intent.succeeded" });
  const first = await hook(env, raw, await sign(raw, "whsec_test", Math.floor(Date.now() / 1000)));
  assert.equal(first.status, 200);
  assert.ok(first.body.orderId);
  const rows = DB.rows("orders");
  assert.equal(rows.length, 1);
  assert.deepEqual([rows[0].user_id, rows[0].studio_id, rows[0].status, rows[0].delivery, rows[0].total_ore, rows[0].vat_ore, rows[0].stripe_session, rows[0].stripe_account],
    [42, 9850, "paid", "pickup", 44900, 8980, "cs_test_1", "acct_1ExampleStudio"]);
  assert.match(rows[0].pickup_code, /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{5}$/);
  assert.deepEqual(JSON.parse(rows[0].items), [{ productId: "towel", variantId: "natural", title: "Bastu towel", label: "Natural", qty: 1, unitOre: 44900 }]);
  assert.equal(sent.pushes.length, 1);
  assert.equal(sent.pushes[0].aps.alert.title, "Order confirmed: Bastu towel · Natural");
  assert.match(sent.pushes[0].aps.alert.body, new RegExp(`449 kr paid to Example Bastu AB. Show code ${rows[0].pickup_code} at the desk`));
  assert.equal(sent.pushes[0].aps.category, "SHOP_ORDER");
  assert.equal(sent.emails.length, 1);
  assert.match(sent.emails[0].text, /Open your orders: https:\/\/djui\.github\.io\/bruce\/app\/#\/home\/orders/);
  // The same session again (Stripe retries): nothing new.
  assert.deepEqual((await hook(env, raw, await sign(raw, "whsec_test", Math.floor(Date.now() / 1000)))).body, { received: true, duplicate: true });
  assert.equal(DB.rows("orders").length, 1);
  const unpaid = raw.replace('"payment_status":"paid"', '"payment_status":"unpaid"').replace("cs_test_1", "cs_test_2");
  assert.deepEqual((await hook(env, unpaid, await sign(unpaid, "whsec_test", Math.floor(Date.now() / 1000)))).body, { received: true, ignored: "not paid" });
  // A paid tee of the drop counts towards the run; no address anywhere.
  const teeEvent = paidEvent("cs_test_3", { productId: "tee", variantId: "", qty: "2", dropId: "race-day" });
  await hook(env, teeEvent, await sign(teeEvent, "whsec_test", Math.floor(Date.now() / 1000)));
  assert.equal((await call(env, "GET", "/shop?city=STO")).body.drops[0].reserved, 33, "31 from the feed and 2 paid");
  assert.ok(!Object.keys(DB.rows("orders")[0]).some((k) => /address|street|zip/.test(k)));
  // The member's orders.
  const mine = await as(42, env, "GET", "/me/orders");
  assert.equal(mine.body.orders.length, 2);
  assert.deepEqual([mine.body.orders[1].statusText, mine.body.orders[1].sellerName, mine.body.orders[1].pickupCode], ["Paid · being prepared for pickup", "Example Bastu AB", rows[0].pickup_code]);
  assert.equal(mine.body.orders[0].userId, undefined);
  assert.deepEqual((await as(7, env, "GET", "/me/orders")).body.orders, [], "only one's own");
  // The print partner: its secret, printing, shipped (to the studio), then delivered there = ready for pickup, with the code.
  const pod = (body, secret = "pod-secret") => worker.fetch(new Request("https://x/hooks/pod", { method: "POST", headers: secret ? { "x-pod-secret": secret } : {}, body: JSON.stringify(body) }), env, { waitUntil() {} })
    .then(async (r) => ({ status: r.status, body: await r.json() }));
  const id = rows[0].id;
  assert.equal((await worker.fetch(new Request("https://x/hooks/pod", { method: "POST", body: "{}" }), { DB }, {})).status, 503);
  assert.equal((await pod({ orderId: id, status: "shipped" }, "wrong")).status, 401);
  assert.equal((await pod({ orderId: id, status: "lost" })).status, 400);
  assert.equal((await pod({ orderId: "nope", status: "shipped" })).status, 404);
  assert.deepEqual((await pod({ orderId: id, status: "printing", podOrder: "pod-77" })).body, { ok: true, status: "printing" });
  assert.equal(DB.rows("orders", `id = '${id}'`)[0].pod_order, "pod-77");
  assert.equal(sent.pushes.length, 2, "printing is quiet");
  assert.deepEqual((await pod({ podOrder: "pod-77", status: "shipped" })).body, { ok: true, status: "shipped" });
  assert.equal(sent.pushes[2].aps.alert.title, "On its way: Bastu towel · Natural");
  assert.deepEqual((await pod({ podOrder: "pod-77", status: "delivered" })).body, { ok: true, status: "ready" }, "delivered to the studio: ready for pickup");
  assert.equal(sent.pushes[3].aps.alert.title, "Ready for pickup: Bastu towel · Natural");
  assert.match(sent.pushes[3].aps.alert.body, new RegExp(`Show code ${rows[0].pickup_code} at Example Bastu AB, At the desk`));
  assert.equal(sent.pushes[3].orderId, id);
  assert.deepEqual((await pod({ podOrder: "pod-77", status: "shipped" })).body, { ok: true, status: "ready", unchanged: true }, "nothing goes back from ready");
  assert.equal((await as(42, env, "GET", "/me/orders")).body.orders.find((o) => o.id === id).status, "ready");
});

test("cron: a drop marked ready tells its buyers with their pickup code and moves their orders to ready", async () => {
  const DB = d1([{ user_id: 42, access_token: "t42", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "42@b.se" }) },
                 { user_id: 7, access_token: "t7", rules: "[]", devices: "[]", state: JSON.stringify({ email: "7@b.se" }) }]);
  const sent = fakeStripeWorld();
  const env = await stripeEnv(DB);
  const open = { ...drop, opensAt: "2020-01-01T00:00:00Z", closesAt: "2099-01-01T00:00:00Z" };
  await post(env, { source: "op", storefronts: [{ ...connected, drops: [open] }] });
  await as(7, env, "PUT", "/me/notify/race-day");
  const teeEvent = paidEvent("cs_test_9", { productId: "tee", variantId: "", qty: "1", dropId: "race-day" });
  await hook(env, teeEvent, await sign(teeEvent, "whsec_test", Math.floor(Date.now() / 1000)));
  sent.pushes.length = 0; sent.emails.length = 0;
  await post(env, { source: "op", storefronts: [{ ...connected, drops: [{ ...open, ready: true }] }] });
  await sendDropNotices(env, Date.now());
  assert.equal(DB.rows("orders")[0].status, "ready");
  assert.equal(sent.pushes.length, 1, "42's device, with the code");
  assert.match(sent.pushes[0].aps.alert.body, new RegExp(`Show code ${DB.rows("orders")[0].pickup_code}`));
  assert.equal(sent.emails.length, 2, "the buyer and the Notify me member, each once");
  assert.deepEqual(sent.emails.map((e) => e.to[0]).sort(), ["42@b.se", "7@b.se"]);
});
