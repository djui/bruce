import { test } from "node:test";
import assert from "node:assert/strict";
import { d1 as memoryDB } from "./d1.js";
import worker, { localParts, localMidnight, matches, opensAt, scanPlan, book, tick, tickUser, watchWaitlists, LoggedOut } from "../src/worker.js";

const rule = { id: "r1", studioId: 6614, masterId: 77, title: "Reformer", weekday: 3, minuteOfDay: 18 * 60 };
// Tue 2026-10-20 18:00 Stockholm (CEST, UTC+2) = 16:00Z
const cls = { id: 1, studio_id: 6614, master_id: 77, title: "Reformer", start_time: "2026-10-20T16:00:00Z",
  bookable_earliest: 604800, bookable_earliest_time: "2026-10-13T16:00:00Z" };

test("local time and midnight across DST", () => {
  assert.deepEqual(localParts(Date.parse("2026-10-20T16:00:00Z")).weekday, 3);
  assert.equal(new Date(localMidnight(2026, 10, 20)).toISOString(), "2026-10-19T22:00:00.000Z");
  assert.equal(new Date(localMidnight(2026, 10, 26)).toISOString(), "2026-10-25T23:00:00.000Z"); // after DST ends
  assert.equal(new Date(localMidnight(2026, 10, 25)).toISOString(), "2026-10-24T22:00:00.000Z"); // DST-change day
});

test("rule matching", () => {
  assert.ok(matches(rule, cls));
  assert.ok(!matches(rule, { ...cls, master_id: 78 }));
  assert.ok(!matches(rule, { ...cls, start_time: "2026-10-20T16:15:00Z" }));
  assert.ok(matches({ ...rule, masterId: null }, { ...cls, master_id: 5, title: "reformer" }));
  assert.ok(!matches(rule, { ...cls, deleted: true }));
  // After DST: 18:00 local is 17:00Z
  assert.ok(matches(rule, { ...cls, start_time: "2026-10-27T17:00:00Z" }));
});

test("open time", () => {
  assert.equal(opensAt(cls), Date.parse("2026-10-13T16:00:00Z"));
  assert.equal(opensAt({ start_time: cls.start_time, bookable_earliest: 345600 }), Date.parse("2026-10-16T16:00:00Z"));
  assert.equal(opensAt({ start_time: cls.start_time }), Date.parse("2026-10-13T16:00:00Z"));
});

test("scan plan covers each matching weekday once per studio", () => {
  const now = Date.parse("2026-10-14T08:00:00Z"); // Wed
  const plan = scanPlan([rule, { ...rule, id: "r2", minuteOfDay: 600 }], now);
  assert.equal(plan.length, 2); // Tue 20th and Tue 27th
  assert.equal(new Date(plan[0].from).toISOString(), "2026-10-19T22:00:00.000Z");
  assert.equal(new Date(plan[1].to).toISOString(), "2026-10-27T23:00:00.000Z");
});

function fakeFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => { calls.push({ url: String(url), ...init }); return handler(String(url), init, calls); };
  return calls;
}
const ok = (body) => new Response(JSON.stringify(body), { status: 200 });

test("book retries until the window opens", async () => {
  let t = Date.parse("2026-10-13T16:00:00Z") - 2000;
  let n = 0;
  const calls = fakeFetch(() => (++n < 3 ? new Response('{"errors":[{"message":"not bookable yet"}]}', { status: 400 }) : ok({ booking: { id: 9 } })));
  const out = await book({ access_token: "t" }, { classId: 1, opens: Date.parse("2026-10-13T16:00:00Z") },
    { sleep: async (ms) => { t += ms; }, now: () => t });
  assert.equal(out, "Booked");
  assert.equal(calls.length, 3);
  assert.equal(JSON.parse(calls[0].body).class_id, 1);
  assert.equal(calls[0].headers["X-Access-Token"], "t");
});

const userRow = (state, extra = {}) => ({ user_id: 42, access_token: "t", rules: JSON.stringify([rule]), state: JSON.stringify(state), ...extra });
const upcoming = (opens) => [{ classId: 1, title: "Reformer", start: Date.parse(cls.start_time), opens }];

test("tick: quiet minutes make no Bruce calls and no writes", async () => {
  const DB = memoryDB([userRow({ upcoming: upcoming(Date.parse(cls.bookable_earliest_time)), handled: {}, log: [], lastScan: "x" })]);
  const before = DB.t.get(42).state;
  const calls = fakeFetch(() => ok({}));
  await tick({ DB }, Date.parse("2026-10-13T12:01:00Z"));   // minute % 5 = 1, user 42 % 5 = 2
  assert.equal(calls.length, 0);
  assert.equal(DB.t.get(42).state, before);
});

test("tick: scans on the user's minute and finds the class", async () => {
  const DB = memoryDB([userRow({ upcoming: [], handled: {}, log: [], lastScan: "x" })]);
  fakeFetch((url) => ok({ classes: url.includes("2026-10-19T22") ? [cls, { ...cls, id: 2, title: "Other", master_id: 1 }] : [], metadata: {} }));
  await tick({ DB }, Date.parse("2026-10-14T08:02:00Z"));
  assert.deepEqual(JSON.parse(DB.t.get(42).state).upcoming.map((o) => o.classId), [1]);
});

test("tickUser: books a due class once and pushes the result", async () => {
  const opens = Date.parse("2026-10-13T16:00:00Z");
  const u = { userId: 42, session: { access_token: "t" }, rules: [rule], devices: [{ token: "ab".repeat(32), env: "production" }],
              state: { upcoming: upcoming(opens - 5000), handled: {}, log: [], lastScan: "x" } };
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  const env = { APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce" };
  const calls = fakeFetch(() => ok({}));
  let booked = 0;
  assert.ok(await tickUser(env, u, opens + 1000, { bookFn: async () => { booked++; return "Booked"; } }));
  assert.ok(await tickUser(env, u, opens + 61000, { bookFn: async () => { booked++; return "Booked"; } }));
  assert.equal(booked, 1);
  const apns = calls.filter((c) => c.url.startsWith("https://api.push.apple.com/3/device/"));
  assert.equal(apns.length, 1);
  assert.equal(apns[0].headers["apns-topic"], "net.dauernheim.bruce");
  assert.match(apns[0].headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.equal(JSON.parse(apns[0].body).aps.alert.title, "Booked: Reformer");
});

test("tick: a 401 at booking deletes the user", async () => {
  const opens = Date.parse("2026-10-13T16:00:00Z");
  const DB = memoryDB([userRow({ upcoming: upcoming(opens - 5000), handled: {}, log: [], lastScan: "x" })]);
  fakeFetch(() => new Response("", { status: 401 }));
  await tick({ DB }, opens + 1000);
  assert.equal(DB.t.size, 0);
});

test("HTTP API: users authenticate with their own Bruce login", async () => {
  const DB = memoryDB();
  const ctx = { waitUntil() {} };
  fakeFetch((url, init) => (url.includes("/v52/user/42") && init.headers["X-Access-Token"] === "good" ? ok({ user: { id: 42 } })
                            : url.includes("/v52/class") ? ok({ classes: [], metadata: {} }) : new Response("", { status: 401 })));
  const req = (method, path, token, body) => new Request(`https://x${path}`, { method, headers: { "X-Access-Token": token, "X-User-Id": "42" },
                                                                              body: body && JSON.stringify(body) });
  assert.equal((await worker.fetch(req("GET", "/me", "bad"), { DB }, ctx)).status, 401);
  assert.equal((await worker.fetch(req("GET", "/me", "good"), { DB, ALLOWED_USERS: "7" }, ctx)).status, 401);
  const r = await worker.fetch(req("PUT", "/me", "good", { rules: [rule], device: { token: "AB".repeat(32), env: "sandbox" } }), { DB }, ctx);
  assert.equal(r.status, 200);
  const row = DB.t.get(42);
  assert.equal(row.access_token, "good");
  assert.equal(JSON.parse(row.rules)[0].minuteOfDay, 1080);
  assert.deepEqual(JSON.parse(row.devices), [{ token: "ab".repeat(32), env: "sandbox" }]);
  const s = await (await worker.fetch(req("GET", "/me", "good"), { DB }, ctx)).json();
  assert.equal(s.hasSession, true);
  await worker.fetch(req("DELETE", "/me", "good"), { DB }, ctx);
  assert.equal(DB.t.size, 0);
});

// MARK: Waitlist watches

const watchUser = (watches, extra = {}) => ({ userId: 42, session: { access_token: "t", user_id: 42 }, rules: [], devices: [],
  state: { upcoming: [], handled: {}, log: [], lastScan: "x", watches }, ...extra });
const wl = { classId: 5, title: "Reformer", studioId: 6614, start: Date.parse("2026-10-20T16:00:00Z") };
const NOW = Date.parse("2026-10-20T08:00:00Z");   // 8 hours before: polled every minute

test("watch: waits while the class is full, books when a spot frees up, then stops", async () => {
  const u = watchUser([{ ...wl }]);
  let spots = 0, booked = 0, polls = 0;
  const classFn = async () => { polls++; return { id: 5, available_spots: spots }; };
  const bookFn = async (s, o) => { booked++; assert.equal(o.classId, 5); return "Booked"; };
  assert.ok(await watchWaitlists({}, u, NOW, { bookFn, classFn }));
  assert.equal(booked, 0);
  assert.equal(u.state.watches.length, 1);
  spots = 1;
  assert.ok(await watchWaitlists({}, u, NOW + 60_000, { bookFn, classFn }));
  assert.equal(booked, 1);
  assert.equal(u.state.watches.length, 0);
  assert.match(u.state.log[0].outcome, /^Booked/);
  await watchWaitlists({}, u, NOW + 120_000, { bookFn, classFn });
  assert.equal(polls, 2);   // nothing left to watch, no more requests
});

test("watch: a lost race keeps watching, with a pause, and gives up after repeated failures", async () => {
  const u = watchUser([{ ...wl }]);
  let polls = 0;
  const classFn = async () => { polls++; return { id: 5, available_spots: 1 }; };
  const bookFn = async () => "Not booked: class is full";
  await watchWaitlists({}, u, NOW, { bookFn, classFn });
  assert.equal(u.state.watches.length, 1);
  await watchWaitlists({}, u, NOW + 60_000, { bookFn, classFn });   // paused for 5 minutes
  assert.equal(polls, 1);
  for (let i = 1; i < 5; i++) await watchWaitlists({}, u, NOW + i * 6 * 60_000, { bookFn, classFn });
  assert.equal(u.state.watches.length, 0);
  assert.match(u.state.log[0].outcome, /^Waitlist stopped/);
});

test("watch: drops started or cancelled classes, polls far-away classes rarely, reports a dead login", async () => {
  const classFn = async () => ({ id: 5, available_spots: 0 });
  let u = watchUser([{ ...wl }]);
  await watchWaitlists({}, u, wl.start + 1, { classFn });
  assert.equal(u.state.watches.length, 0);
  u = watchUser([{ ...wl }]);
  await watchWaitlists({}, u, NOW, { classFn: async () => ({ id: 5, canceled: true, available_spots: 3 }), bookFn: async () => assert.fail("booked") });
  assert.equal(u.state.watches.length, 0);
  // A week ahead: one poll in five minutes only.
  const far = { ...wl, start: NOW + 7 * 86400_000 };
  let polls = 0;
  for (let m = 0; m < 10; m++) {
    await watchWaitlists({}, watchUser([far]), NOW + m * 60_000, { classFn: async () => { polls++; return { available_spots: 0 }; } });
  }
  assert.equal(polls, 2);
  u = watchUser([{ ...wl }]);
  assert.equal(await watchWaitlists({}, u, NOW, { classFn: async () => { throw new LoggedOut(); } }), false);
});

test("tickUser: runs the watches of a user without rules", async () => {
  const u = watchUser([{ ...wl }]);
  let booked = 0;
  assert.ok(await tickUser({}, u, NOW, { classFn: async () => ({ available_spots: 2 }), bookFn: async () => { booked++; return "Booked"; } }));
  assert.equal(booked, 1);
  assert.equal(u.state.watches.length, 0);
});

test("HTTP API: watch a full class, list it, stop watching; CORS preflight", async () => {
  const DB = memoryDB();
  const ctx = { waitUntil() {} };
  const future = new Date(Date.now() + 3 * 86400_000).toISOString();
  fakeFetch((url) => (url.includes("/v52/user/42") ? ok({ user: { id: 42 } })
                    : url.includes("/v52/class/5") ? ok({ class: { id: 5, title: "Reformer", studio_id: 6614, start_time: future, available_spots: 0 } })
                    : new Response("", { status: 404 })));
  const req = (method, path) => new Request(`https://x${path}`, { method, headers: { "X-Access-Token": "t", "X-User-Id": "42" } });
  const pre = await worker.fetch(new Request("https://x/me/waitlist/5", { method: "OPTIONS" }), { DB }, ctx);
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get("Access-Control-Allow-Headers"), /X-Access-Token/);
  assert.equal((await worker.fetch(req("PUT", "/me/waitlist/5"), { DB }, ctx)).status, 200);
  assert.equal((await worker.fetch(req("PUT", "/me/waitlist/9"), { DB }, ctx)).status, 404);
  const s = await (await worker.fetch(req("GET", "/me"), { DB }, ctx)).json();
  assert.deepEqual(s.waitlist.map((w) => w.classId), [5]);
  await worker.fetch(req("DELETE", "/me/waitlist/5"), { DB }, ctx);
  assert.equal(DB.t.size, 0);   // nothing else to do for this user: the row (and login) is gone
});
