// Race reminders (Train for it): PUT /me/races and DELETE /me/races/<id>, GET /me, the cap, the times (08:00 on the
// Monday of race week, 18:00 the day before, across summer time), sending each once from the minute cron with push and
// email, and the row's lifetime (a web user with only races keeps it; DELETE /me clears them).
import { test } from "node:test";
import assert from "node:assert/strict";
import { d1 } from "./d1.js";
import worker, { raceReminderTimes, raceWeekMessage, raceEveMessage, sendRaceReminders, cleanRaces, localAt, pruneRaces, cleanFeedRace } from "../src/worker.js";

const ok = (body) => new Response(JSON.stringify(body), { status: 200 });
const iso = (ms) => (ms == null ? null : new Date(ms).toISOString());
const hyrox = { id: "hyrox-stockholm-2026", name: "HYROX Stockholm", date: "2026-12-12", url: "https://hyrox.com/find-my-race/", remindWeek: true, remindEve: true,
  plan: { perWeek: 4, weeks: 10, startedOn: "2026-10-05", raceWeek: [{ key: "hyrox", title: "Hyrox", count: 1 }, { key: "mobility", title: "Mobility", count: 1 }] } };

async function apnsEnv(DB, extra = {}) {
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { DB, APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce",
           RESEND_API_KEY: "re_test", EMAIL_FROM: "Brüce <autobook@example.com>", ...extra };
}

/** A fake Bruce (user 42 with a token "t"), APNs and Resend; records what was sent. */
function fakeWorld({ bookings = [] } = {}) {
  const sent = { pushes: [], emails: [], bruce: [] };
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    if (url.startsWith("https://api.push.apple.com/")) { sent.pushes.push(JSON.parse(init.body)); return ok({}); }
    if (url === "https://api.resend.com/emails") { sent.emails.push(JSON.parse(init.body)); return ok({ id: "e" }); }
    if (init.headers?.["X-Access-Token"] !== "t") return new Response("", { status: 401 });
    sent.bruce.push(url);
    const u = new URL(url);
    if (u.pathname === "/v52/user/42") return ok({ user: { id: 42, email: "a@b.se", first_name: "A" } });
    if (u.pathname === "/v52/booking") return ok({ bookings, metadata: {} });
    return ok({ classes: [], metadata: {} });
  };
  return sent;
}
const call = (env, method, path, body) => worker.fetch(new Request(`https://x${path}`, { method, headers: { "X-Access-Token": "t", "X-User-Id": "42" },
  body: body && JSON.stringify(body) }), env, { waitUntil() {} }).then(async (r) => ({ status: r.status, body: await r.json() }));
const device = { token: "ab".repeat(32), env: "production" };

test("reminder times: Monday 08:00 of race week and 18:00 the day before, local, across summer time", () => {
  const t = raceReminderTimes("2026-12-12");                        // Saturday
  assert.equal(iso(t.week), "2026-12-07T07:00:00.000Z");             // Monday 08:00 CET
  assert.equal(iso(t.eve), "2026-12-11T17:00:00.000Z");              // Friday 18:00 CET
  assert.equal(raceReminderTimes("2026-12-07").week, null, "a Monday race: the evening before covers it");
  assert.equal(iso(raceReminderTimes("2026-10-26").eve), "2026-10-25T17:00:00.000Z", "Sunday 25 October, the day summer time ends");
  assert.equal(iso(raceReminderTimes("2026-10-31").week), "2026-10-26T07:00:00.000Z");
  assert.equal(iso(raceReminderTimes("2027-04-03").week), "2027-03-29T06:00:00.000Z", "after summer time starts (CEST)");
  assert.equal(iso(localAt(2027, 3, 28, 18)), "2027-03-28T16:00:00.000Z", "18:00 on the day summer time starts");
});

test("messages: the race day, what is booked this week or the plan's mix, the race's page", () => {
  const row = { name: "HYROX Stockholm", date: "2026-12-12", url: hyrox.url, plan: JSON.stringify(hyrox.plan) };
  assert.deepEqual(raceWeekMessage(row), { title: "Race week: HYROX Stockholm", body: "Saturday is race day. Your class mix this week: 1 Hyrox and 1 Mobility." });
  const booked = [{ title: "Mobility", start: Date.parse("2026-12-09T17:00:00Z") }, { title: "Hyrox", start: Date.parse("2026-12-10T06:00:00Z") }];
  assert.equal(raceWeekMessage(row, booked).body, "Saturday is race day. Booked this week: Mobility Wed 18:00, Hyrox Thu 07:00.");
  assert.equal(raceWeekMessage({ ...row, plan: null }).body, "Saturday is race day.");
  assert.deepEqual(raceEveMessage(row), { title: "Tomorrow: HYROX Stockholm", body: "Race day tomorrow. Start times and what to bring are on hyrox.com." });
  assert.equal(raceEveMessage({ name: "Club 10K", url: null }).body, "Race day tomorrow.");
});

test("cleanRaces: valid ids and days, a reminder on, no duplicates, the cap", () => {
  const got = cleanRaces([hyrox, { ...hyrox }, { id: "Bad Id", date: "2026-12-12", remindWeek: true }, { id: "a", date: "2026-02-30", remindEve: true },
    { id: "custom-3f2a", name: "Club 10K", date: "2026-11-14", remindEve: true, url: "javascript:alert(1)" }, { id: "quiet", date: "2026-11-14" }]);
  assert.deepEqual(got.map((r) => r.id), ["hyrox-stockholm-2026", "custom-3f2a"]);
  assert.equal(got[1].url, null);
  assert.deepEqual(got[0].plan.raceWeek.map((x) => x.title), ["Hyrox", "Mobility"]);
  assert.equal(cleanRaces(Array.from({ length: 21 }, (_, i) => ({ id: "r" + i, date: "2026-12-12", remindWeek: true }))), null);
  assert.equal(cleanRaces(Array.from({ length: 20 }, (_, i) => ({ id: "r" + i, date: "2026-12-12", remindWeek: true }))).length, 20);
});

test("HTTP: PUT /me/races replaces the set, GET /me lists it, DELETE removes one; over 20 is refused", async () => {
  const DB = d1();
  const env = await apnsEnv(DB);
  fakeWorld();
  assert.equal((await worker.fetch(new Request("https://x/me/races", { method: "PUT", headers: { "X-Access-Token": "nope", "X-User-Id": "42" }, body: "{}" }), env, {})).status, 401);
  assert.equal((await call(env, "PUT", "/me/races", { races: "x" })).status, 400);
  const put = await call(env, "PUT", "/me/races", { races: [hyrox, { id: "custom-3f2a", name: "Club 10K", date: "2026-11-14", remindEve: true }] });
  assert.equal(put.status, 200);
  assert.equal(put.body.races, 2);
  assert.equal(put.body.push, false, "no device yet");
  assert.equal(put.body.email, "a@b.se");
  assert.ok(DB.t.get(42), "the row stays for a web user with only race reminders");
  let me = (await call(env, "GET", "/me")).body;
  assert.deepEqual(me.races.map((r) => [r.id, r.date, r.remindWeek, r.remindEve]), [["custom-3f2a", "2026-11-14", false, true], ["hyrox-stockholm-2026", "2026-12-12", true, true]]);
  assert.equal(me.races[1].plan.raceWeek[0].title, "Hyrox");
  await call(env, "PUT", "/me/races", { races: [hyrox] });
  assert.deepEqual(DB.rows("user_races").map((r) => r.race_id), ["hyrox-stockholm-2026"]);
  const many = Array.from({ length: 21 }, (_, i) => ({ id: "r" + i, date: "2026-12-12", remindWeek: true }));
  assert.equal((await call(env, "PUT", "/me/races", { races: many })).status, 409);
  assert.equal(DB.rows("user_races").length, 1, "a refused PUT changes nothing");
  const del = await call(env, "DELETE", "/me/races/hyrox-stockholm-2026");
  assert.equal(del.body.races, 0);
  assert.equal(DB.t.get(42), undefined, "nothing left to do: the row goes");
  me = (await call(env, "GET", "/me")).body;
  assert.deepEqual(me.races, []);
});

test("DELETE /me clears the races; a race moved to another day is reminded again", async () => {
  const DB = d1();
  const env = await apnsEnv(DB);
  fakeWorld();
  await call(env, "PUT", "/me/races", { races: [hyrox] });
  DB.sql.prepare("UPDATE user_races SET week_sent_at = 1, eve_sent_at = 2").run();
  await call(env, "PUT", "/me/races", { races: [{ ...hyrox, name: "HYROX Stockholm (doubles)" }] });
  assert.deepEqual([DB.rows("user_races")[0].week_sent_at, DB.rows("user_races")[0].eve_sent_at], [1, 2], "same day: still sent");
  await call(env, "PUT", "/me/races", { races: [{ ...hyrox, date: "2026-12-13" }] });
  assert.deepEqual([DB.rows("user_races")[0].week_sent_at, DB.rows("user_races")[0].eve_sent_at], [null, null], "a new day: reminded again");
  await call(env, "DELETE", "/me");
  assert.equal(DB.rows("user_races").length, 0);
});

test("cron: the race-week push and email at 08:00 on the Monday, the day-before push at 18:00, each once", async () => {
  const DB = d1([{ user_id: 42, access_token: "t", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "a@b.se" }) }]);
  const env = await apnsEnv(DB);
  const sent = fakeWorld({ bookings: [{ id: 1, class: { title: "Mobility", start_time: "2026-12-09T17:00:00Z" } },
    { id: 2, class: { title: "Hyrox", start_time: "2026-12-10T06:00:00Z" } }, { id: 3, class: { title: "After", start_time: "2026-12-14T06:00:00Z" } }] });
  await call(env, "PUT", "/me/races", { races: [hyrox] });
  const at = (s) => Date.parse(s);
  await sendRaceReminders(env, at("2026-12-07T06:59:00Z"));          // Monday 07:59
  assert.equal(sent.pushes.length, 0);
  await sendRaceReminders(env, at("2026-12-07T07:00:30Z"));          // 08:00
  assert.equal(sent.pushes.length, 1);
  assert.equal(sent.pushes[0].aps.alert.title, "Race week: HYROX Stockholm");
  assert.equal(sent.pushes[0].aps.alert.body, "Saturday is race day. Booked this week: Mobility Wed 18:00, Hyrox Thu 07:00.");
  assert.equal(sent.pushes[0].aps.category, "RACE_REMINDER");
  assert.equal(sent.pushes[0].raceId, "hyrox-stockholm-2026");
  assert.equal(sent.emails.length, 1);
  assert.equal(sent.emails[0].subject, "Race week: HYROX Stockholm");
  assert.match(sent.emails[0].text, /Open the race: https:\/\/djui\.github\.io\/bruce\/app\/#\/mine\/race\/hyrox-stockholm-2026/);
  assert.match(sent.emails[0].text, /No more emails: https:\/\/\S+\/email\/off\?u=42&t=/);
  await sendRaceReminders(env, at("2026-12-07T07:01:00Z"));
  await sendRaceReminders(env, at("2026-12-11T16:59:00Z"));          // Friday 17:59
  assert.equal(sent.pushes.length, 1, "once");
  await sendRaceReminders(env, at("2026-12-11T17:00:00Z"));          // Friday 18:00
  assert.equal(sent.pushes.length, 2);
  assert.deepEqual(sent.pushes[1].aps.alert, { title: "Tomorrow: HYROX Stockholm", body: "Race day tomorrow. Start times and what to bring are on hyrox.com." });
  assert.equal(sent.emails.length, 1, "the evening before is a push only");
  await sendRaceReminders(env, at("2026-12-11T17:01:00Z"));
  assert.equal(sent.pushes.length, 2);
  assert.ok(DB.rows("user_races")[0].week_sent_at && DB.rows("user_races")[0].eve_sent_at);
});

test("cron: the price step push and email at 09:00 the day before the fee changes, once per step day", async () => {
  const DB = d1([{ user_id: 42, access_token: "t", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "a@b.se" }) }]);
  const env = await apnsEnv(DB);
  const sent = fakeWorld();
  const tv = { id: "tough-viking-stadion-2027", name: "Tough Viking Stockholms Stadion", date: "2027-05-15", url: "https://www.toughviking.se/", remindPrice: true,
    priceAt: "2026-11-01", priceBody: "Tough Viking Stockholms Stadion: 750 SEK until today, 775 SEK from tomorrow. Sign up on toughviking.se." };
  // A race with only the price reminder is stored (catalog races only); custom races and a missing day are not.
  assert.deepEqual(cleanRaces([tv, { ...tv, id: "custom-1" }, { ...tv, id: "no-day", priceAt: null }]).map((r) => r.id), ["tough-viking-stadion-2027"]);
  assert.equal(cleanRaces([{ ...tv, priceBody: "x".repeat(300) }])[0].priceBody.length, 240);
  const put = await call(env, "PUT", "/me/races", { races: [tv] });
  assert.deepEqual(put.body.ids, ["tough-viking-stadion-2027"], "the device leaves its own notification out");
  assert.equal(DB.rows("user_races")[0].remind_price, 1);
  assert.equal(DB.rows("user_races")[0].price_at, "2026-11-01");
  const me = await call(env, "GET", "/me");
  assert.equal(me.body.races[0].remindPrice, true);
  assert.equal(me.body.races[0].priceAt, "2026-11-01");
  const at = (s) => Date.parse(s);
  await sendRaceReminders(env, at("2026-10-31T07:59:00Z"));          // Saturday 08:59 CET
  assert.equal(sent.pushes.length, 0);
  await sendRaceReminders(env, at("2026-10-31T08:00:10Z"));          // 09:00
  assert.equal(sent.pushes.length, 1);
  assert.deepEqual(sent.pushes[0].aps.alert, { title: "Price goes up tomorrow", body: tv.priceBody });
  assert.equal(sent.pushes[0].raceId, "tough-viking-stadion-2027");
  assert.equal(sent.emails.length, 1, "web users get it by email");
  assert.equal(sent.emails[0].subject, "Price goes up tomorrow");
  await sendRaceReminders(env, at("2026-10-31T08:01:00Z"));
  assert.equal(sent.pushes.length, 1, "once");
  // Sent again with the same step day: stays sent. A later step (the catalog moved on): reminded again.
  await call(env, "PUT", "/me/races", { races: [tv] });
  assert.ok(DB.rows("user_races")[0].price_sent_at);
  await call(env, "PUT", "/me/races", { races: [{ ...tv, priceAt: "2027-01-10", priceBody: null }] });
  assert.equal(DB.rows("user_races")[0].price_sent_at, null);
  await sendRaceReminders(env, at("2027-01-09T08:00:10Z"));
  assert.equal(sent.pushes.length, 2);
  assert.equal(sent.pushes[1].aps.alert.body, "Tough Viking Stockholms Stadion: the entry fee changes tomorrow. Check toughviking.se.");
  // Over 12 hours late: only marked.
  await call(env, "PUT", "/me/races", { races: [{ ...tv, priceAt: "2027-02-01" }] });
  await sendRaceReminders(env, at("2027-01-31T21:00:00Z"));
  assert.equal(sent.pushes.length, 2);
  assert.ok(DB.rows("user_races")[0].price_sent_at);
  // Switched off: the race goes with the next PUT.
  await call(env, "PUT", "/me/races", { races: [{ ...tv, remindPrice: false }] });
  assert.equal(DB.rows("user_races").length, 0);
});

test("race feed: POST /races/import with the token replaces a source's races; GET /races serves them", async () => {
  const DB = d1();
  const good = { id: "example-run-2027", name: "Example Run", type: "running", date: "2027-06-05", city: "Stockholm", country: "SE", distancesKm: [10],
    signupUrl: "https://example.org/run", status: "open", priceSteps: [{ amount: 400, currency: "SEK" }], checkedOn: "2026-10-21" };
  assert.deepEqual(cleanFeedRace(good), good);
  for (const bad of [{ ...good, id: "Bad Id" }, { ...good, id: "custom-x" }, { ...good, type: "paddle" }, { ...good, status: "maybe" }, { ...good, date: "2027-02-30" },
    { ...good, endDate: "2027-06-04" }, { ...good, signupUrl: "http://example.org" }, { ...good, checkedOn: undefined }, { ...good, name: " " }, null, [good]]) {
    assert.equal(cleanFeedRace(bad), null, JSON.stringify(bad));
  }
  const post = (env, body, token) => worker.fetch(new Request("https://x/races/import", { method: "POST", headers: token ? { authorization: `Bearer ${token}` } : {},
    body: JSON.stringify(body) }), env, {}).then(async (r) => ({ status: r.status, body: await r.json() }));
  const get = (env) => worker.fetch(new Request("https://x/races"), env, {}).then((r) => r.json());
  // Without a token configured nothing can be imported; with one, only with it.
  assert.equal((await post({ DB }, { source: "hyrox", races: [good] }, "t")).status, 503);
  const env = { DB, RACE_FEED_TOKEN: "feed-secret" };
  assert.equal((await post(env, { source: "hyrox", races: [good] })).status, 401);
  assert.equal((await post(env, { source: "hyrox", races: [good] }, "wrong")).status, 401);
  assert.equal((await post(env, { source: "HYROX", races: [good] }, "feed-secret")).status, 400);
  assert.equal((await post(env, { source: "hyrox", races: "x" }, "feed-secret")).status, 400);
  assert.deepEqual(await get(env), { races: [], sources: [], importedAt: null });
  const first = await post(env, { source: "hyrox", races: [good, { ...good, id: "example-hyrox-2027", type: "hyrox" }, { ...good, type: "paddle" }, good] }, "feed-secret");
  assert.equal(first.status, 200);
  assert.deepEqual(first.body, { ok: true, source: "hyrox", imported: 2, skipped: ["example-run-2027", "example-run-2027"] });
  const served = await get(env);
  assert.deepEqual(served.races.map((r) => r.id), ["example-hyrox-2027", "example-run-2027"]);
  assert.deepEqual(served.sources, ["hyrox"]);
  assert.ok(served.importedAt > 0);
  // Another source can't take a race over; a source's new post replaces its own.
  const other = await post(env, { source: "marathongruppen", races: [good, { ...good, id: "example-half-2027" }] }, "feed-secret");
  assert.deepEqual(other.body, { ok: true, source: "marathongruppen", imported: 1, skipped: ["example-run-2027"] });
  await post(env, { source: "hyrox", races: [{ ...good, id: "example-hyrox-2027", type: "hyrox", checkedOn: "2026-11-01" }] }, "feed-secret");
  const now = await get(env);
  assert.deepEqual(now.races.map((r) => [r.id, r.checkedOn]), [["example-half-2027", "2026-10-21"], ["example-hyrox-2027", "2026-11-01"]]);
  assert.deepEqual(now.sources, ["hyrox", "marathongruppen"]);
  assert.equal((await post(env, { source: "hyrox", races: Array.from({ length: 201 }, (_, i) => ({ ...good, id: "r" + i })) }, "feed-secret")).status, 409);
});

test("cron: late reminders are dropped (12 hours, or race day's midnight for the evening before)", async () => {
  const DB = d1([{ user_id: 42, access_token: "t", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "a@b.se" }) }]);
  const env = await apnsEnv(DB);
  const sent = fakeWorld();
  await call(env, "PUT", "/me/races", { races: [hyrox] });
  // Added on Tuesday of race week, 21:00: the Monday reminder is 37 hours late and only marked.
  await sendRaceReminders(env, Date.parse("2026-12-08T20:00:00Z"));
  assert.equal(sent.emails.length + sent.pushes.length, 0);
  assert.ok(DB.rows("user_races")[0].week_sent_at);
  // Switched on at 01:00 on race day: "Tomorrow" would be wrong, so nothing.
  await sendRaceReminders(env, Date.parse("2026-12-12T00:00:00Z"));
  assert.equal(sent.pushes.length, 0);
  assert.ok(DB.rows("user_races")[0].eve_sent_at);
});

test("cron: a Monday race gets one reminder, the evening before", async () => {
  const DB = d1([{ user_id: 42, access_token: "t", rules: "[]", devices: JSON.stringify([device]), state: JSON.stringify({ email: "a@b.se" }) }]);
  const env = await apnsEnv(DB);
  const sent = fakeWorld();
  await call(env, "PUT", "/me/races", { races: [{ id: "monday-run", name: "Monday Run", date: "2026-12-14", remindWeek: true, remindEve: true },
    { id: "monday-week", name: "Monday Week", date: "2026-12-14", remindWeek: true }] });
  await sendRaceReminders(env, Date.parse("2026-12-07T07:00:00Z"));   // the Monday before: nothing
  assert.equal(sent.pushes.length, 0);
  await sendRaceReminders(env, Date.parse("2026-12-13T17:00:00Z"));   // Sunday 18:00
  assert.deepEqual(sent.pushes.map((p) => p.aps.alert.title).sort(), ["Tomorrow: Monday Run", "Tomorrow: Monday Week"]);
  await sendRaceReminders(env, Date.parse("2026-12-13T17:05:00Z"));
  assert.equal(sent.pushes.length, 2, "both switches on: still one");
  assert.equal(sent.emails.length, 0);
});

test("devices: each replaces only its own races; any removes one; the daily cron drops races that are over", async () => {
  const DB = d1();
  const env = await apnsEnv(DB);
  fakeWorld();
  const a = await call(env, "PUT", "/me/races", { device: "iphone-1", races: [hyrox] });
  assert.deepEqual(a.body.ids, ["hyrox-stockholm-2026"]);
  await call(env, "PUT", "/me/races", { device: "web-7", races: [{ id: "custom-3f2a", name: "Club 10K", date: "2026-11-14", remindEve: true }] });
  assert.deepEqual(DB.rows("user_races").map((r) => r.race_id).sort(), ["custom-3f2a", "hyrox-stockholm-2026"], "the web did not remove the iPhone's race");
  await call(env, "PUT", "/me/races", { device: "iphone-1", races: [] });
  assert.deepEqual(DB.rows("user_races").map((r) => r.race_id), ["custom-3f2a"]);
  // The same race from two devices is one row; the later one owns it.
  await call(env, "PUT", "/me/races", { device: "iphone-1", races: [{ id: "custom-3f2a", name: "Club 10K", date: "2026-11-15", remindWeek: true }] });
  assert.deepEqual(DB.rows("user_races").map((r) => [r.race_id, r.date, r.source]), [["custom-3f2a", "2026-11-15", "iphone-1"]]);
  // Over: gone the day after, and with it the row of a user who has nothing else here.
  assert.equal(await pruneRaces(env, Date.parse("2026-11-16T12:00:00Z")), 0, "race day's day after: kept");
  assert.equal(await pruneRaces(env, Date.parse("2026-11-17T12:00:00Z")), 1);
  assert.equal(DB.rows("user_races").length, 0);
  assert.equal(DB.t.get(42), undefined);
});

test("cron: web users (no device) get the race-week email, from the minute cron", async () => {
  const DB = d1([{ user_id: 42, access_token: "t", rules: "[]", devices: "[]", state: JSON.stringify({ email: "a@b.se" }) }]);
  const env = await apnsEnv(DB);
  const sent = fakeWorld();
  await call(env, "PUT", "/me/races", { device: "web-7", races: [{ ...hyrox, remindEve: false }] });
  let run;
  await worker.scheduled({ cron: "* * * * *", scheduledTime: Date.parse("2026-12-07T07:00:00Z") }, env, { waitUntil: (p) => { run = p; } });
  await run;
  assert.equal(sent.emails.length, 1);
  assert.equal(sent.pushes.length, 0);
});
