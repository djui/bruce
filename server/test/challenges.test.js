import { test } from "node:test";
import assert from "node:assert/strict";
import { d1 } from "./d1.js";
import worker, { daily, refreshHistory, DAILY_CRON } from "../src/worker.js";
import { localDay, addDays } from "../src/insights.js";

// A fake Bruce with four people. Uwe (42), Robin (7) and Sam (9) are friends; Eve (50) is nobody's friend.
const PEOPLE = { 42: "Uwe", 7: "Robin", 9: "Sam", 50: "Eve" };
const FRIENDS = { 42: [7, 9], 7: [42, 9], 9: [42, 7], 50: [] };
const ago = (days, hour = 16) => new Date(Date.now() - days * 86400_000).toISOString().slice(0, 11) + `${String(hour).padStart(2, "0")}:00:00Z`;
const classBooking = (id, classId, start, title = "Reformer", checked = true) => ({
  id, class_id: classId, studio_id: 1724, checked_in_at: checked ? start : null,
  class: { title, start_time: start, end_time: new Date(Date.parse(start) + 50 * 60_000).toISOString(), studio: { name: "STC Rosenlundsparken" },
           class_categories: [{ category_id: 2 }] },
});
// Today's visits would be "in the future" before 16:00Z, so history starts yesterday.
const HISTORY = {
  42: [classBooking(1, 500, ago(1)), classBooking(2, 501, ago(2), "Hatha Flow")],
  7: [classBooking(3, 500, ago(1)), classBooking(4, 502, ago(2)), classBooking(5, 503, ago(3)),
      { id: 6, class_id: null, studio_id: 1489, checked_in_at: ago(1, 6) }],
  9: [],
  50: [],
};

const ok = (body) => new Response(JSON.stringify(body), { status: 200 });

function fakeBruce() {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    calls.push({ url, ...init });
    if (url.startsWith("https://api.push.apple.com/") || url.startsWith("https://api.sandbox.push.apple.com/")) return ok({});
    const uid = +String(init.headers?.["X-Access-Token"] ?? "").replace(/^t/, "");
    if (!PEOPLE[uid]) return new Response("", { status: 401 });
    const u = new URL(url);
    if (u.pathname.startsWith("/v52/user/")) return +u.pathname.split("/")[3] === uid ? ok({ user: { id: uid, first_name: PEOPLE[uid] } }) : new Response("", { status: 403 });
    if (u.pathname === "/v52/friend") return ok({ friends: FRIENDS[uid].map((id) => ({ id: 1000 + id, friend_user: { id, first_name: PEOPLE[id] } })) });
    if (u.pathname === "/v52/booking") return ok({ bookings: HISTORY[uid], metadata: { pagination: { next_cursor: null } } });
    if (u.pathname === "/v52/class") return ok({ classes: [], metadata: {} });
    return new Response("", { status: 404 });
  };
  return calls;
}

async function apnsEnv(DB) {
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { DB, APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce" };
}

function client(env) {
  const pending = [];
  const ctx = { waitUntil: (p) => pending.push(p) };
  const call = async (uid, method, path, body) => {
    const res = await worker.fetch(new Request(`https://x${path}`, { method, headers: { "X-Access-Token": `t${uid}`, "X-User-Id": String(uid) },
                                                                     body: body && JSON.stringify(body) }), env, ctx);
    while (pending.length) await pending.shift();
    return { status: res.status, body: res.status === 204 ? null : await res.json() };
  };
  return call;
}

const today = localDay(Date.now());
// Around today, so the test does not depend on the day of the month.
const thisMonth = { start: addDays(today, -10), end: addDays(today, 10) };

test("challenges: create, invite by push, accept, leaderboard, share-link join, leave", async () => {
  const DB = d1();
  const env = await apnsEnv(DB);
  const calls = fakeBruce();
  const call = client(env);
  // Robin uses Brüce with push (auto-book on, no rules yet).
  assert.equal((await call(7, "PUT", "/me", { rules: [], device: { token: "cd".repeat(32), env: "production" } })).status, 200);

  const created = await call(42, "POST", "/challenges", { metric: "classes", ...thisMonth, invite: [7, 9, 50] });
  assert.equal(created.status, 201);
  const ch = created.body.challenge;
  assert.match(ch.id, /^[A-Za-z0-9]{12}$/);
  assert.equal(ch.title, "Most classes");
  assert.equal(ch.shareUrl, `https://djui.github.io/bruce/app/#challenge/${ch.id}`);
  assert.deepEqual(ch.participants.map((p) => [p.name, p.status]), [["Uwe", "accepted"], ["Robin", "invited"], ["Sam", "invited"]]);   // Eve is no friend
  const invite = calls.filter((c) => c.url.includes("/3/device/"));
  assert.equal(invite.length, 1);
  const payload = JSON.parse(invite[0].body);
  assert.equal(payload.aps.alert.title, "Uwe challenged you");
  assert.equal(payload.aps.category, "CHALLENGE_INVITE");
  assert.equal(payload.challengeId, ch.id);
  // The creator's login is stored and their history read with detail.
  assert.equal(DB.t.get(42).access_token, "t42");
  assert.ok(DB.rows("daily_counts", "user_id = 42").every((r) => r.detail));

  const list = await call(7, "GET", "/challenges");
  assert.equal(list.body.challenges[0].myStatus, "invited");
  assert.deepEqual(list.body.usesBruce.sort(), [42]);
  // Nothing of Robin's is read before Robin accepts.
  assert.equal(DB.rows("daily_counts", "user_id = 7").length, 0);

  assert.equal((await call(7, "POST", `/challenges/${ch.id}/accept`)).status, 200);
  const detail = (await call(42, "GET", `/challenges/${ch.id}`)).body;
  const [first, second] = detail.leaderboard;
  assert.equal(first.name, "Robin");
  assert.equal(first.score, 3);          // classes; the gym drop-in is a visit, not a class
  assert.equal(first.visits, 4);
  assert.equal(first.together, 1);       // class 500 with Uwe
  assert.deepEqual(first.topClass, { title: "Reformer", count: 3 });
  assert.equal(second.name, "Uwe");
  assert.equal(detail.leaderboard[2].status, "invited");
  assert.equal(detail.months[0].entries.length, 2);
  assert.ok(detail.updatedAt);

  // Share link: Eve may see a preview but not join; Sam (a friend of Uwe) joins without an invite step.
  const preview = await call(50, "GET", `/challenges/${ch.id}`);
  assert.equal(preview.body.joinable, false);
  assert.equal(preview.body.challenge.participantCount, 2);
  assert.equal(preview.body.leaderboard, undefined);
  assert.equal((await call(50, "POST", `/challenges/${ch.id}/join`)).status, 403);
  assert.equal((await call(50, "POST", `/challenges/${ch.id}/accept`)).status, 403);
  assert.equal((await call(9, "POST", `/challenges/${ch.id}/join`)).status, 200);
  assert.equal((await call(42, "GET", `/challenges/${ch.id}`)).body.leaderboard.filter((e) => e.status === "accepted").length, 3);

  // Leaving deletes Robin's per-visit detail; the challenge goes on.
  assert.equal((await call(7, "POST", `/challenges/${ch.id}/leave`)).status, 200);
  assert.ok(DB.rows("daily_counts", "user_id = 7").every((r) => r.detail === null));
  assert.equal((await call(7, "GET", `/challenges/${ch.id}`)).body.joinable, true);

  // Auto-book off keeps the login of a challenge participant.
  assert.equal((await call(42, "DELETE", "/me")).body.kept, "challenges");
  assert.equal(DB.t.get(42).access_token, "t42");
  // The last accepted participants leave: the challenge is gone.
  await call(9, "POST", `/challenges/${ch.id}/leave`);
  await call(42, "POST", `/challenges/${ch.id}/leave`);
  assert.equal((await call(42, "GET", `/challenges/${ch.id}`)).status, 404);
  assert.equal(DB.t.get(42), undefined);   // nothing left to do for Uwe: row and history deleted
  assert.equal(DB.rows("daily_counts", "user_id = 42").length, 0);
});

test("challenges: input errors and auth", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  assert.equal((await call(42, "POST", "/challenges", { metric: "speed", ...thisMonth })).status, 400);
  assert.equal((await call(42, "GET", "/challenges/nope")).status, 404);
  assert.equal((await call(77, "GET", "/challenges")).status, 401);
  assert.equal((await call(42, "PATCH", "/challenges")).status, 404);
});

test("wrapped percentiles: anonymous, only with five other users", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  const year = today.slice(0, 4);
  const insert = (uid, visits) => DB.sql.prepare("INSERT INTO daily_counts (user_id, day, visits, checkins, checkin_minutes, studios) VALUES (?, ?, ?, ?, ?, ?)")
    .run(uid, `${year}-01-05`, visits, visits, visits * 50, "[1724]");
  for (const [uid, n] of [[1, 10], [2, 20], [3, 30], [4, 40]]) insert(uid, n);
  insert(42, 999);   // the caller is not compared with themself
  let r = (await call(42, "GET", `/wrapped/percentiles?visits=25&minutes=1000`)).body;
  assert.deepEqual(r, { year: +year, cohort: 4, percentiles: null });
  insert(5, 50);
  r = (await call(42, "GET", `/wrapped/percentiles?year=${year}&visits=25&minutes=1000&streak=1`)).body;
  assert.deepEqual(r, { year: +year, cohort: 5, percentiles: { visits: 40, minutes: 30, streak: 50 } });
});

test("daily cron: refreshes each user once a day, incrementally, within the budget; goal reminders", async () => {
  const now = Date.now();
  const state = (extra = {}) => JSON.stringify({ upcoming: [], handled: {}, log: [], lastScan: "x", ...extra });
  const DB = d1([{ user_id: 42, access_token: "t42", state: state() }, { user_id: 7, access_token: "t7", state: state() },
                 { user_id: 77, access_token: "dead", state: state() }]);
  const env = { DB, DAILY_BUDGET: "2" };
  const calls = fakeBruce();
  await daily(env, now);
  // 42 and 7 refreshed (one page each), the budget ran out before 77.
  assert.equal(calls.filter((c) => c.url.includes("/v52/booking")).length, 2);
  assert.ok(JSON.parse(DB.t.get(42).state).statsAt);
  assert.equal(DB.rows("daily_counts", "user_id = 7").reduce((n, r) => n + r.checkins, 0), 4);
  assert.ok(DB.rows("daily_counts").every((r) => r.detail === null));   // nobody is in a challenge: counts only
  calls.length = 0;
  await daily(env, now);
  // Next run (same day): the others are done; 77's login is dead, so the row goes.
  assert.equal(calls.filter((c) => c.url.includes("/v52/booking")).length, 1);
  assert.equal(DB.t.get(77), undefined);

  // Goal reminder: behind on a goal on day >= 8 pushes once.
  const u = { userId: 9, session: { access_token: "t9", user_id: 9 }, rules: [], devices: [],
              state: { goals: [{ id: "g", title: "Swims", category: null, target: 30 }], goalPings: {}, statsFrom: null, statsAt: null, detailFrom: null } };
  const mid = Date.parse(`${today.slice(0, 7)}-20T03:00:00Z`);
  await refreshHistory({ DB }, u, mid);
  assert.ok(u.state.goalPings.g);
  const pinged = u.state.goalPings.g;
  await refreshHistory({ DB }, u, mid + 86400_000);
  assert.equal(u.state.goalPings.g, pinged);   // not again within a week
  assert.equal(DAILY_CRON, "30 2 * * *");
});

test("goals: PUT /me/goals stores reminding goals, an empty list removes a row that has nothing else", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  const r = await call(42, "PUT", "/me/goals", { goals: [{ id: "a", title: "Gym visits", category: "gym", target: 20, remind: true },
                                                       { id: "b", title: "Swims", target: 2, remind: false }] });
  assert.deepEqual(r.body, { ok: true, goals: 1 });
  assert.deepEqual(JSON.parse(DB.t.get(42).state).goals, [{ id: "a", title: "Gym visits", category: "gym", studioId: null, target: 20 }]);
  await call(42, "PUT", "/me/goals", { goals: [] });
  assert.equal(DB.t.get(42), undefined);
  assert.equal((await call(42, "PUT", "/me/goals", {})).status, 400);
});
