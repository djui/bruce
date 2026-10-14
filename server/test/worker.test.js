import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { localParts, localMidnight, matches, opensAt, scanPlan, book, tick, tickUser } from "../src/worker.js";

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

// A tiny in-memory stand-in for the D1 binding, enough for the queries the worker makes.
function memoryDB(rows = []) {
  const t = new Map(rows.map((r) => [r.user_id, { rules: "[]", devices: "[]", state: "{}", ...r }]));
  return { t, prepare(sql) {
    let args = [];
    const stmt = {
      bind(...a) { args = a; return stmt; },
      async run() {
        if (sql.startsWith("INSERT")) t.set(args[0], { user_id: args[0], access_token: args[1], rules: args[2], devices: args[3], state: args[4] });
        if (sql.startsWith("DELETE")) t.delete(args[0]);
      },
      async first() { return t.get(args[0]) ?? null; },
      async all() { return { results: [...t.values()] }; },
    };
    return stmt;
  } };
}

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
