// Friends going and race crews: going is opt-in per race and only shown to the caller's Bruce friends who share a race
// too (GET /races/going); a crew is a challenge with a race and a weekly target that ends on race day; the Sunday 19:00
// crew push (once per crew and week, nobody named, opt-out); leaving and deleting remove the data.
import { test } from "node:test";
import assert from "node:assert/strict";
import { d1 } from "./d1.js";
import worker, { sendCrewUpdates, cleanRaces, goingSwitches } from "../src/worker.js";
import { localDay, addDays, crewWeeks, crewMessage, mondayOf, cleanChallenge } from "../src/insights.js";

// Uwe (42), Robin (7) and Sam (9) are friends; Eve (50) is nobody's friend.
const PEOPLE = { 42: "Uwe", 7: "Robin", 9: "Sam", 50: "Eve" };
const FRIENDS = { 42: [7, 9], 7: [42, 9], 9: [42, 7], 50: [] };
const ok = (body) => new Response(JSON.stringify(body), { status: 200 });
const today = localDay(Date.now());
const soon = addDays(today, 30), later = addDays(today, 60);

function fakeBruce() {
  const calls = [], pushes = [];
  globalThis.fetch = async (url, init = {}) => {
    url = String(url);
    calls.push(url);
    if (url.includes("push.apple.com/")) { pushes.push(JSON.parse(init.body)); return ok({}); }
    const uid = +String(init.headers?.["X-Access-Token"] ?? "").replace(/^t/, "");
    if (!PEOPLE[uid]) return new Response("", { status: 401 });
    const u = new URL(url);
    if (u.pathname.startsWith("/v52/user/")) return +u.pathname.split("/")[3] === uid ? ok({ user: { id: uid, first_name: PEOPLE[uid] } }) : new Response("", { status: 403 });
    if (u.pathname === "/v52/friend") return ok({ friends: FRIENDS[uid].map((id) => ({ id: 1000 + id, friend_user: { id, first_name: PEOPLE[id] } })) });
    if (u.pathname === "/v52/booking") return ok({ bookings: [], metadata: { pagination: { next_cursor: null } } });
    return ok({ classes: [], metadata: {} });
  };
  return { calls, pushes };
}

async function apnsEnv(DB) {
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { DB, APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce" };
}

function client(env) {
  const pending = [];
  const ctx = { waitUntil: (p) => pending.push(p) };
  return async (uid, method, path, body) => {
    const res = await worker.fetch(new Request(`https://x${path}`, { method, headers: { "X-Access-Token": `t${uid}`, "X-User-Id": String(uid) },
                                                                     body: body && JSON.stringify(body) }), env, ctx);
    while (pending.length) await pending.shift();
    return { status: res.status, body: res.status === 204 ? null : await res.json() };
  };
}
const race = (id, date, extra = {}) => ({ id, name: id, date, ...extra });

test("cleanRaces: going keeps a race without reminders, never for a race added by hand", () => {
  const got = cleanRaces([race("hyrox-stockholm-2026", soon, { going: true }), race("custom-3f2a", soon, { going: true }),
    race("vasaloppet-2027", soon, { going: "yes" }), race("custom-9b", soon, { going: true, remindEve: true })]);
  assert.deepEqual(got.map((r) => [r.id, r.going]), [["hyrox-stockholm-2026", true], ["custom-9b", false]]);
});

test("going: opt-in per race, shown only to Bruce friends who share a race too", async () => {
  const DB = d1();
  const env = { DB };
  const { calls } = fakeBruce();
  const call = client(env);
  await call(7, "PUT", "/me/races", { device: "robin-phone", races: [race("hyrox-stockholm-2026", soon, { going: true })] });
  await call(9, "PUT", "/me/races", { device: "sam-phone", races: [race("hyrox-stockholm-2026", soon, { remindWeek: true })] });   // not going
  await call(50, "PUT", "/me/races", { device: "eve-web", races: [race("hyrox-stockholm-2026", soon, { going: true })] });         // no friend
  assert.deepEqual(DB.rows("user_races").map((r) => [r.user_id, r.visibility]).sort(), [[50, "friends"], [7, "friends"], [9, "private"]]);

  // Uwe shares nothing yet: nothing is read or returned.
  calls.length = 0;
  let r = await call(42, "GET", "/races/going");
  assert.deepEqual(r.body, { going: {}, sharing: false, mine: [] });
  assert.equal(calls.filter((u) => u.includes("/v52/friend")).length, 0);

  const put = await call(42, "PUT", "/me/races", { device: "uwe-phone", races: [race("vasaloppet-2027", later, { going: true })] });
  assert.deepEqual(put.body.going, ["vasaloppet-2027"]);
  r = await call(42, "GET", "/races/going");
  assert.deepEqual(r.body, { going: { "hyrox-stockholm-2026": [{ userId: 7, name: "Robin" }] }, sharing: true, mine: ["vasaloppet-2027"] });
  assert.deepEqual((await call(42, "GET", "/races/going?ids=vasaloppet-2027")).body.going, {});
  assert.deepEqual(Object.keys((await call(42, "GET", "/races/going?ids=hyrox-stockholm-2026,x")).body.going), ["hyrox-stockholm-2026"]);
  // Eve (no friend of anyone) sees nobody, though she shares the same race.
  assert.deepEqual((await call(50, "GET", "/races/going")).body.going, {});
  assert.equal((await call(77, "GET", "/races/going")).status, 401);
  assert.equal((await call(42, "GET", "/me")).body.races[0].going, true);

  // Robin switches going off (a reminder keeps the race): gone from Uwe's list. Back on, then DELETE /me removes it.
  const t0 = Date.now() - 60_000;
  await call(7, "PUT", "/me/races", { device: "robin-phone", races: [race("hyrox-stockholm-2026", soon, { remindEve: true, going: false, goingAt: t0 })] });
  assert.deepEqual((await call(42, "GET", "/races/going")).body.going, {});
  await call(7, "PUT", "/me/races", { device: "robin-phone", races: [race("hyrox-stockholm-2026", soon, { going: true, goingAt: t0 + 1000 })] });
  assert.equal(Object.keys((await call(42, "GET", "/races/going")).body.going).length, 1);
  await call(7, "DELETE", "/me");
  assert.equal(DB.rows("user_races", "user_id = 7").length, 0);
  assert.deepEqual((await call(42, "GET", "/races/going")).body.going, {});
  // A race that is over is not listed (and the daily cron deletes it).
  DB.sql.prepare("INSERT INTO user_races (user_id, race_id, name, date, source, updated_at, visibility) VALUES (9, 'old-race-2026', 'Old', ?, 's', 'x', 'friends')")
    .run(addDays(today, -1));
  assert.deepEqual((await call(42, "GET", "/races/going")).body.going, {});
});

test("going is the member's: the switch flipped last wins on every device; ids are the reminder races", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  const vis = () => DB.rows("user_races", "user_id = 7").map((r) => [r.race_id, r.visibility, r.source]);
  const t = Date.now() - 3_600_000;
  // On the iPhone at t: going, with a reminder.
  let r = await call(7, "PUT", "/me/races", { device: "phone", races: [race("hyrox-stockholm-2026", soon, { going: true, goingAt: t, remindWeek: true })] });
  assert.deepEqual(r.body.ids, ["hyrox-stockholm-2026"]);
  assert.deepEqual(r.body.going, ["hyrox-stockholm-2026"]);
  // The web has the same race with a reminder and has never seen the switch: still shared (the web owns the row now).
  await call(7, "PUT", "/me/races", { device: "web", races: [race("hyrox-stockholm-2026", soon, { remindEve: true })] });
  assert.deepEqual(vis(), [["hyrox-stockholm-2026", "friends", "web"]]);
  // Off on the iPhone at t + 2 min, with no reminder there: the web's row goes private.
  r = await call(7, "PUT", "/me/races", { device: "phone", races: [race("hyrox-stockholm-2026", soon, { going: false, goingAt: t + 120_000 })] });
  assert.deepEqual(vis(), [["hyrox-stockholm-2026", "private", "web"]]);
  assert.deepEqual(r.body.going, []);
  // A Mac that still has the switch on from t + 1 min sends it: the later off wins.
  await call(7, "PUT", "/me/races", { device: "mac", races: [race("hyrox-stockholm-2026", soon, { going: true, goingAt: t + 60_000, remindEve: true })] });
  assert.deepEqual(vis(), [["hyrox-stockholm-2026", "private", "mac"]]);
  // On again later, from the Mac: shared. A clock far ahead counts as now.
  r = await call(7, "PUT", "/me/races", { device: "mac", races: [race("hyrox-stockholm-2026", soon, { going: true, goingAt: Date.now() + 9e9, remindEve: true })] });
  assert.deepEqual(r.body.going, ["hyrox-stockholm-2026"]);
  assert.ok(DB.rows("user_races", "user_id = 7")[0].going_at <= Date.now());
  assert.deepEqual((await call(7, "GET", "/me")).body.races.map((x) => x.going), [true]);
  // A going-only race is stored but its reminders are not the server's: `ids` leaves it out.
  r = await call(7, "PUT", "/me/races", { device: "mac", races: [race("vasaloppet-2027", later, { going: true, goingAt: Date.now() })] });
  assert.deepEqual(r.body.ids, []);
  assert.deepEqual(goingSwitches([{ id: "custom-1", going: true }, { id: "x", going: "yes" }, { id: "a", going: false, goingAt: 5 }]), [{ id: "a", going: false, goingAt: 5 }]);
});

test("DELETE /me in a challenge keeps the login but drops the push devices", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  await call(42, "PUT", "/me", { rules: [], device: { token: "ab".repeat(32), env: "production" } });
  await call(42, "POST", "/challenges", { raceId: "hyrox-stockholm-2026", weekly: 3, end: soon });
  assert.equal((await call(42, "DELETE", "/me")).body.kept, "challenges");
  assert.equal(DB.t.get(42).access_token, "t42");
  assert.equal(DB.t.get(42).devices, "[]");
});

test("crewWeeks and crewMessage: this week and last week per member, nobody named", () => {
  const ch = { start: "2026-10-12", end: "2026-12-12", weekly: 3, raceId: "hyrox-stockholm-2026" };
  const v = (day) => ({ day });
  const visits = new Map([[42, ["2026-10-13", "2026-10-15", "2026-10-17", "2026-10-19", "2026-10-21"].map(v)], [7, ["2026-10-14", "2026-10-20"].map(v)]]);
  const people = [{ userId: 42, name: "Uwe", status: "accepted" }, { userId: 7, name: "Robin", status: "accepted" }, { userId: 9, name: "Sam", status: "invited" }];
  const s = crewWeeks(ch, people, visits, "2026-10-21");   // Wednesday
  assert.deepEqual(s.week, { start: "2026-10-19", end: "2026-10-25" });
  assert.deepEqual(s.lastWeek, { start: "2026-10-12", end: "2026-10-18", hit: 1 });
  assert.deepEqual(s.members.map((m) => [m.name, m.thisWeek, m.lastWeek]), [["Uwe", 2, 3], ["Robin", 1, 1]]);   // Sam is only invited
  assert.equal(s.size, 2);
  assert.equal(s.weeksLeft, 8);
  const first = crewWeeks({ ...ch, start: "2026-10-20" }, people, visits, "2026-10-21");
  assert.equal(first.lastWeek, null, "first week");
  assert.deepEqual(first.members.map((m) => [m.name, m.thisWeek]), [["Robin", 1], ["Uwe", 1]], "counted from the crew's start (Uwe's Monday visit is before it)");
  assert.equal(mondayOf("2026-10-25"), "2026-10-19");
  assert.deepEqual(crewMessage("HYROX Sthlm Doubles", 4, 5, 4, 3), { title: "Crew: HYROX Sthlm Doubles", body: "4 of 5 hit their 4 sessions this week. You did 3 of 4." });
  assert.equal(crewMessage("C", 1, 2, 1, 2).body, "1 of 2 hit their 1 session this week. You hit yours.");
});

test("cleanChallenge: a crew is visits, weekly, from today to race day", () => {
  const c = cleanChallenge({ raceId: "hyrox-stockholm-2026", weekly: 4, title: " HYROX Sthlm Doubles ", start: "2020-01-01", end: "2026-12-12", metric: "minutes", repeatMonthly: true }, "2026-10-21");
  assert.deepEqual(c, { metric: "visits", target: null, start: "2026-10-21", end: "2026-12-12", category: null, categoryTitle: null, title: "HYROX Sthlm Doubles",
                        repeatMonthly: false, raceId: "hyrox-stockholm-2026", weekly: 4 });
  assert.match(cleanChallenge({ raceId: "custom-1", weekly: 3, end: "2026-12-12" }, "2026-10-21").error, /catalog/);
  assert.match(cleanChallenge({ raceId: "x", weekly: 0, end: "2026-12-12" }, "2026-10-21").error, /weekly/);
  assert.match(cleanChallenge({ raceId: "x", weekly: 3, end: "2026-10-20" }, "2026-10-21").error, /race day/);
  assert.match(cleanChallenge({ raceId: "x", weekly: 3, start: "2030-01-01", end: "2026-12-12" }, "2026-10-21").error, /race day/, "start after race day");
  assert.equal(cleanChallenge({ raceId: "x", weekly: 3, end: "2026-12-12" }, "2026-10-21").title, "Race crew");
  assert.equal(cleanChallenge({ metric: "classes", start: "2026-10-01", end: "2026-10-31" }, "2026-10-21").raceId, null);
});

test("crews: start one for a race, invite friends, crew stats on the page, one per race, leave", async () => {
  const DB = d1();
  const env = await apnsEnv(DB);
  const { pushes } = fakeBruce();
  const call = client(env);
  await call(7, "PUT", "/me", { rules: [], device: { token: "cd".repeat(32), env: "production" } });
  const end = addDays(today, 40);
  const r = await call(42, "POST", "/challenges", { raceId: "hyrox-stockholm-2026", weekly: 3, title: "HYROX Sthlm Doubles", end, invite: [7, 9, 50] });
  assert.equal(r.status, 201);
  const ch = r.body.challenge;
  assert.deepEqual([ch.raceId, ch.weekly, ch.metric, ch.repeatMonthly, ch.start, ch.end], ["hyrox-stockholm-2026", 3, "visits", false, today, end]);
  assert.deepEqual(ch.participants.map((p) => [p.name, p.status]), [["Uwe", "accepted"], ["Robin", "invited"], ["Sam", "invited"]]);
  assert.deepEqual(pushes.map((p) => [p.aps.alert.title, p.aps.alert.body]), [["Uwe invited you to a crew", "HYROX Sthlm Doubles · 3 sessions a week until race day. Tap to accept."]]);
  const dup = await call(42, "POST", "/challenges", { raceId: "hyrox-stockholm-2026", weekly: 2, end });
  assert.equal(dup.status, 409);
  assert.equal(dup.body.challengeId, ch.id);
  assert.equal((await call(42, "POST", "/challenges", { raceId: "custom-abc", weekly: 2, end })).status, 400);

  // Before accepting, Robin sees a preview with the race; after, the crew's weeks.
  assert.equal((await call(7, "GET", `/challenges/${ch.id}`)).body.challenge.raceId, "hyrox-stockholm-2026");
  await call(7, "POST", `/challenges/${ch.id}/accept`);
  const d = (await call(42, "GET", `/challenges/${ch.id}`)).body;
  assert.equal(d.crew.weekly, 3);
  assert.equal(d.crew.size, 2);
  assert.deepEqual(d.crew.week.start, mondayOf(today));
  assert.deepEqual(d.crew.members.map((m) => m.userId).sort(), [42, 7].sort());
  assert.equal(d.crew.lastWeek, null, "started today: no last week yet");
  assert.ok(d.leaderboard.length >= 2, "the leaderboard is there too, for apps that don't know crews");
  assert.equal((await call(42, "GET", "/challenges")).body.challenges[0].weekly, 3);

  // Leaving: Robin's per-visit detail goes; when the last member leaves the crew and its push rows go.
  DB.sql.prepare("INSERT INTO crew_updates (challenge_id, week, sent_at) VALUES (?, ?, 1)").run(ch.id, mondayOf(today));
  await call(7, "POST", `/challenges/${ch.id}/leave`);
  assert.ok(DB.rows("daily_counts", "user_id = 7").every((x) => x.detail === null));
  await call(42, "POST", `/challenges/${ch.id}/leave`);
  assert.equal((await call(42, "GET", `/challenges/${ch.id}`)).status, 404);
  assert.equal(DB.rows("crew_updates").length, 0);
});

test("PUT /me crewUpdates: off is kept and reported by GET /me", async () => {
  const DB = d1();
  fakeBruce();
  const call = client({ DB });
  assert.equal((await call(42, "GET", "/me")).body.crewUpdates, true);
  await call(42, "PUT", "/me", { rules: [], crewUpdates: false });
  assert.equal(JSON.parse(DB.t.get(42).state).crewUpdates, false);
  assert.equal((await call(42, "GET", "/me")).body.crewUpdates, false);
});

test("cron: the crew push on Sunday at 19:00, once, with today's visits of those behind; opt-out; two members needed", async () => {
  // Sunday 1 November 2026, 19:00 in Stockholm (CET) is 18:00 UTC; the week is Mon 26 Oct to Sun 1 Nov.
  const dev = (t) => JSON.stringify([{ token: t.repeat(32), env: "production" }]);
  const DB = d1([{ user_id: 42, access_token: "t42", devices: dev("aa") }, { user_id: 7, access_token: "t7", devices: dev("bb"), state: JSON.stringify({ crewUpdates: false }) },
                 { user_id: 9, access_token: "t9", devices: dev("cc") }, { user_id: 50, access_token: "t50", devices: dev("dd") }]);
  const env = await apnsEnv(DB);
  const { pushes } = fakeBruce();
  const add = (id, title, owner, end, people, weekly = 3) => {
    DB.sql.prepare(`INSERT INTO challenges (id, owner_id, title, metric, start_day, end_day, created_at, race_id, weekly) VALUES (?, ?, ?, 'visits', '2026-10-20', ?, 'x', 'hyrox-stockholm-2026', ?)`)
      .run(id, owner, title, end, weekly);
    for (const [uid, status] of people) DB.sql.prepare("INSERT INTO participants (challenge_id, user_id, name, status, joined_at) VALUES (?, ?, ?, ?, 'x')").run(id, uid, PEOPLE[uid], status);
  };
  add("crewA", "HYROX Sthlm Doubles", 42, "2026-12-12", [[42, "accepted"], [7, "accepted"], [9, "accepted"], [50, "invited"]]);
  add("solo", "Just me", 50, "2026-12-12", [[50, "accepted"]]);
  add("raceday", "Racing today", 42, "2026-11-01", [[42, "accepted"], [9, "accepted"]]);
  add("fresh", "Started Thursday", 42, "2026-12-12", [[42, "accepted"], [9, "accepted"]]);
  DB.sql.prepare("UPDATE challenges SET start_day = '2026-10-29' WHERE id = 'fresh'").run();
  const visit = (day, id) => ({ at: `${day}T08:00:00.000Z`, k: "c", id, t: "Hyrox", s: 1, n: "Box", m: 60, c: ["13"], ci: true });
  const counts = (uid, days) => days.forEach((day, i) => DB.sql.prepare("INSERT INTO daily_counts (user_id, day, visits, detail) VALUES (?, ?, 1, ?)")
    .run(uid, day, JSON.stringify([visit(day, uid * 100 + i)])));
  counts(42, ["2026-10-26", "2026-10-28", "2026-10-31"]);   // 3 of 3 by Saturday
  counts(7, ["2026-10-27", "2026-10-29"]);                  // 2, and one more this morning
  counts(9, ["2026-10-25", "2026-10-30"]);                  // the 25th is last week: 1 this week
  const fetched = [];
  const fetchFn = async (token, userId) => {
    fetched.push(userId);
    return { bookings: userId === 7 ? [{ id: 1, class_id: 900, studio_id: 1, checked_in_at: "2026-11-01T09:00:00Z",
      class: { title: "Hyrox", start_time: "2026-11-01T09:00:00Z", end_time: "2026-11-01T10:00:00Z", class_categories: [] } }] : [], pages: 1, complete: true };
  };
  assert.equal(await sendCrewUpdates(env, Date.parse("2026-10-31T18:00:00Z"), { fetchFn }), 0, "Saturday");
  assert.equal(await sendCrewUpdates(env, Date.parse("2026-11-01T17:59:00Z"), { fetchFn }), 0, "18:59");
  const n = await sendCrewUpdates(env, Date.parse("2026-11-01T18:00:30Z"), { fetchFn });
  assert.equal(n, 2, "Uwe and Sam; Robin switched crew updates off");
  assert.deepEqual(fetched.sort(), [7, 9], "only those behind are read");
  const bodies = pushes.map((p) => [p.aps.alert.title, p.aps.alert.body, p.aps.category, p.challengeId]);
  assert.deepEqual(bodies.sort(), [["Crew: HYROX Sthlm Doubles", "2 of 3 hit their 3 sessions this week. You did 1 of 3.", "CREW_UPDATE", "crewA"],
                                   ["Crew: HYROX Sthlm Doubles", "2 of 3 hit their 3 sessions this week. You hit yours.", "CREW_UPDATE", "crewA"]]);
  assert.ok(!pushes.some((p) => /Robin|Sam|Uwe|Eve/.test(p.aps.alert.body)), "nobody is named");
  assert.equal(await sendCrewUpdates(env, Date.parse("2026-11-01T18:05:00Z"), { fetchFn }), 0, "once");
  assert.deepEqual(DB.rows("crew_updates").map((r) => [r.challenge_id, r.week]).sort(), [["crewA", "2026-10-26"], ["fresh", "2026-10-26"], ["solo", "2026-10-26"]],
                   "a crew started this Thursday is told from its first full week");
  // The week after: too late at 21:00.
  assert.equal(await sendCrewUpdates(env, Date.parse("2026-11-08T20:00:00Z"), { fetchFn }), 0);
  // A small budget: the crew that doesn't fit waits for the next minute (nothing marked), then goes out.
  const before = pushes.length;
  assert.equal(await sendCrewUpdates({ ...env, CREW_BUDGET: "3" }, Date.parse("2026-11-08T18:00:00Z"), { fetchFn }), 2, "alone it fits without today's visits");
  assert.equal(pushes.length - before, 2);
  assert.ok(!DB.rows("crew_updates").some((r) => r.challenge_id === "fresh" && r.week === "2026-11-02"), "the other crew waits, unmarked");
  assert.equal(await sendCrewUpdates(env, Date.parse("2026-11-08T18:01:00Z"), { fetchFn }), 2, "and goes out the next minute");
});
