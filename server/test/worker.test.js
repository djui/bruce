import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { localParts, localMidnight, matches, opensAt, scanPlan, book, tick } from "../src/worker.js";

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

function memoryKV(init) {
  const m = new Map(Object.entries(init).map(([k, v]) => [k, JSON.stringify(v)]));
  return { m, puts: 0,
    async get(k, type) { const v = m.get(k); return v == null ? null : type === "json" ? JSON.parse(v) : v; },
    async put(k, v) { this.puts++; m.set(k, v); }, async delete(k) { m.delete(k); } };
}

test("tick: quiet minutes make no Bruce calls and no writes", async () => {
  const kv = memoryKV({ rules: [rule], session: { access_token: "t" },
    state: { upcoming: [{ classId: 1, title: "Reformer", start: Date.parse(cls.start_time), opens: Date.parse(cls.bookable_earliest_time) }], handled: {}, log: [], lastScan: "x" } });
  const calls = fakeFetch(() => ok({}));
  await tick({ AUTOBOOK: kv }, Date.parse("2026-10-13T12:01:00Z"));
  assert.equal(calls.length, 0);
  assert.equal(kv.puts, 0);
});

test("tick: scan on the 5th minute finds the class", async () => {
  const kv = memoryKV({ rules: [rule], session: { access_token: "t" }, state: { upcoming: [], handled: {}, log: [], lastScan: "x" } });
  fakeFetch((url) => ok({ classes: url.includes("2026-10-19T22") ? [cls, { ...cls, id: 2, title: "Other", master_id: 1 }] : [], metadata: {} }));
  await tick({ AUTOBOOK: kv }, Date.parse("2026-10-14T08:05:00Z"));
  const st = JSON.parse(kv.m.get("state"));
  assert.deepEqual(st.upcoming.map((o) => o.classId), [1]);
});

test("tick: books a due class once, and a 401 stops the server", async () => {
  const opens = Date.parse("2026-10-13T16:00:00Z");
  const kv = memoryKV({ rules: [rule], session: { access_token: "t" },
    state: { upcoming: [{ classId: 1, title: "Reformer", start: Date.parse(cls.start_time), opens: opens - 5000 }], handled: {}, log: [], lastScan: "x" } });
  fakeFetch(() => new Response("", { status: 401 }));
  await tick({ AUTOBOOK: kv }, opens + 1000);
  const st = JSON.parse(kv.m.get("state"));
  assert.equal(st.log[1].outcome, "Login expired");
  assert.ok(st.handled[1]);
  assert.equal(kv.m.get("session"), undefined);
});

test("HTTP API needs the key", async () => {
  const kv = memoryKV({});
  const env = { API_KEY: "k", AUTOBOOK: kv };
  const ctx = { waitUntil() {} };
  assert.equal((await worker.fetch(new Request("https://x/status"), env, ctx)).status, 401);
  const r = await worker.fetch(new Request("https://x/rules", { method: "PUT", headers: { Authorization: "Bearer k" },
    body: JSON.stringify({ rules: [{ ...rule, createdAt: "2026-10-14T00:00:00Z" }] }) }), env, ctx);
  assert.equal(r.status, 200);
  assert.equal(JSON.parse(kv.m.get("rules"))[0].minuteOfDay, 1080);
  const s = await (await worker.fetch(new Request("https://x/status", { headers: { Authorization: "Bearer k" } }), env, ctx)).json();
  assert.equal(s.hasSession, false);
});
