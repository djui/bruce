import { test } from "node:test";
import assert from "node:assert/strict";
import { d1 } from "./d1.js";
import { brokenHabit, recommendClasses, nudgeMessage, slotOf, partOfDay } from "../src/habits.js";
import { refreshHistory, sendNudges, opensAt } from "../src/worker.js";

// Reformer at STC (1724) on Saturdays 09:00 Stockholm (07:00Z in summer time): Sep 19, 26, Oct 3; skipped Oct 10.
const booking = (id, start, { title = "Reformer", studio = 1724, cat = 2, checked = true } = {}) => ({
  id, class_id: 1000 + id, studio_id: studio, checked_in_at: checked ? start : null,
  class: { title, start_time: start, end_time: new Date(Date.parse(start) + 50 * 60_000).toISOString(),
           studio: { name: studio === 1724 ? "STC Rosenlundsparken" : "Yogayama" }, class_categories: [{ category_id: cat }] },
});
const SATURDAYS = [booking(1, "2026-09-19T07:00:00Z"), booking(2, "2026-09-26T07:00:00Z"), booking(3, "2026-10-03T07:00:00Z")];
const HISTORY = [...SATURDAYS, booking(4, "2026-10-06T16:00:00Z", { title: "Hatha Flow", studio: 1489, cat: 5 }),
                 booking(5, "2026-09-29T16:00:00Z", { title: "Hatha Flow", studio: 1489, cat: 5 })];
const WED = Date.parse("2026-10-14T02:30:00Z");   // the daily run on Wednesday, 4 days after the skipped Saturday

test("slots and parts of the day", () => {
  assert.deepEqual(slotOf(Date.parse("2026-10-03T07:00:00Z")), { weekday: 7, minuteOfDay: 9 * 60 });
  assert.deepEqual(slotOf(Date.parse("2026-10-31T08:00:00Z")), { weekday: 7, minuteOfDay: 9 * 60 });   // after DST ends
  assert.equal(partOfDay(9 * 60), "morning");
  assert.equal(partOfDay(18 * 60), "evening");
});

test("broken habit: three Saturdays in a row, then nothing until Wednesday", () => {
  const h = brokenHabit(HISTORY, WED);
  assert.equal(h.title, "Reformer");
  assert.equal(h.studioId, 1724);
  assert.equal(h.weekday, 7);
  assert.equal(h.minuteOfDay, 540);
  assert.equal(h.weeks, 3);
  assert.equal(h.missedDay, "2026-10-10");
  assert.equal(h.key, "1724|reformer|7|540");
  // Too early (Tuesday), and gone once the next Saturday has come.
  assert.equal(brokenHabit(HISTORY, Date.parse("2026-10-13T02:30:00Z")), null);
  assert.ok(brokenHabit(HISTORY, Date.parse("2026-10-16T02:30:00Z")));
  assert.equal(brokenHabit(HISTORY, Date.parse("2026-10-17T02:30:00Z")), null);
});

test("broken habit: none while the user is still booking or visiting", () => {
  // Two weeks are not a habit.
  assert.equal(brokenHabit(HISTORY.slice(1), WED), null);
  // An upcoming booking (anything) means they are still booking.
  assert.equal(brokenHabit([...HISTORY, booking(6, "2026-10-17T07:00:00Z", { checked: false })], WED), null);
  // A visit since the skipped Saturday (another class, or the same one at another time).
  assert.equal(brokenHabit([...HISTORY, booking(7, "2026-10-12T16:00:00Z", { title: "Hatha Flow", studio: 1489 })], WED), null);
  assert.equal(brokenHabit([...HISTORY, booking(8, "2026-10-10T08:00:00Z")], WED), null);
  // A gap breaks the run: Sep 12, (19 missing), 26, Oct 3.
  assert.equal(brokenHabit([booking(9, "2026-09-12T07:00:00Z"), ...SATURDAYS.slice(1)], WED), null);
  // A cancelled booking is not a visit.
  assert.equal(brokenHabit([...SATURDAYS.slice(0, 2), { ...SATURDAYS[2], cancelled: true }], WED), null);
});

const cls = (id, start, { title = "Reformer", studio = 1724, spots = 3, cat = 2, opens } = {}) => ({
  id, title, studio_id: studio, start_time: start, available_spots: spots, class_categories: [{ category_id: cat }],
  studio: { name: studio === 1724 ? "STC Rosenlundsparken" : "Yogayama" }, ...(opens ? { bookable_earliest_time: opens } : {}),
});

test("recommendations: the usual class first, then close slots and favourite classes; one per class", () => {
  const habit = brokenHabit(HISTORY, WED);
  const classes = [
    cls(1, "2026-10-17T07:00:00Z"),                                          // Sat 09:00 Reformer: the usual
    cls(2, "2026-10-18T07:00:00Z"),                                          // Sun 09:00 Reformer: same class again, shown once
    cls(3, "2026-10-15T16:00:00Z", { title: "Hatha Flow", studio: 1489, cat: 5 }),
    cls(4, "2026-10-17T08:00:00Z", { title: "Spin", cat: 9 }),               // Sat 10:00 at the usual studio
    cls(5, "2026-10-16T07:00:00Z", { title: "Pilates", spots: 0 }),          // full
    cls(6, "2026-10-14T03:00:00Z", { title: "Too soon" }),                   // starts within the hour
    cls(7, "2026-10-25T07:00:00Z", { title: "Too late" }),                   // beyond 7 days
    cls(8, "2026-10-16T07:00:00Z", { title: "Not bookable", opens: "2026-10-20T07:00:00Z" }),
  ];
  const picks = recommendClasses(classes, HISTORY, habit, WED, opensAt);
  assert.deepEqual(picks.map((p) => p.classId), [1, 4, 3]);
  assert.deepEqual(picks[0], { classId: 1, title: "Reformer", studioId: 1724, studio: "STC Rosenlundsparken", start: "2026-10-17T07:00:00.000Z" });
});

test("push text", () => {
  const habit = brokenHabit(HISTORY, WED);
  const m = nudgeMessage(habit, [{ classId: 1, title: "Reformer", studio: "STC Rosenlundsparken", start: "2026-10-17T07:00:00.000Z" },
                                 { classId: 3, title: "Hatha Flow", studio: null, start: "2026-10-15T16:00:00.000Z" }]);
  assert.equal(m.title, "Missing your Saturday morning Reformer?");
  assert.equal(m.body, "3 Saturdays in a row at 09:00, then a break. Picked for you: Reformer, Sat 09:00 at STC Rosenlundsparken · Hatha Flow, Thu 18:00");
  assert.equal(nudgeMessage(habit, []).body, "3 Saturdays in a row at 09:00, then a break. Find a class in Brüce.");
});

async function apnsEnv(DB) {
  const { privateKey } = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const pem = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { DB, APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_TOPIC: "net.dauernheim.bruce" };
}

test("daily run plans the push for 08:00, the minute cron sends it once; switched off, nothing", async () => {
  const device = { token: "ab".repeat(32), env: "production" };
  const DB = d1([{ user_id: 42, access_token: "t42", devices: JSON.stringify([device]), state: "{}" }]);
  const env = await apnsEnv(DB);
  const pushes = [];
  globalThis.fetch = async (url, init = {}) => {
    if (String(url).includes("push.apple.com")) pushes.push(JSON.parse(init.body));
    return new Response("{}", { status: 200 });
  };
  const user = () => ({ userId: 42, session: { access_token: "t42", user_id: 42 }, rules: [], devices: [device],
                        state: { goals: [], goalPings: {}, statsFrom: null, statsAt: null, detailFrom: null } });
  const fetchFn = async (token, uid, fromMs) => {
    assert.ok(fromMs <= Date.parse("2026-09-03T00:00:00Z"));   // reads 6 weeks back for habits
    return { bookings: HISTORY, pages: 1, complete: true };
  };
  const studios = [];
  const classesFn = async (token, studioId, from, to, { meter }) => {
    studios.push(studioId);
    meter.pages++;
    return studioId === 1724 ? [cls(1, "2026-10-17T07:00:00Z")] : [cls(3, "2026-10-15T16:00:00Z", { title: "Hatha Flow", studio: 1489, cat: 5 })];
  };
  const pages = await refreshHistory(env, user(), WED, { fetchFn, classesFn });
  assert.equal(pages, 3);
  assert.deepEqual(studios, [1724, 1489]);
  const row = DB.rows("nudges")[0];
  assert.equal(row.title, "Missing your Saturday morning Reformer?");
  assert.equal(new Date(row.send_at).toISOString(), "2026-10-14T06:00:00.000Z");   // 08:00 Stockholm
  assert.deepEqual(JSON.parse(row.data), { recommend: [1, 3] });

  await sendNudges(env, WED + 3600_000);   // 05:30 local: not yet
  assert.equal(pushes.length, 0);
  await sendNudges(env, Date.parse("2026-10-14T06:00:30Z"));
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].aps.category, "RECOMMENDATION");
  assert.deepEqual(pushes[0].recommend, [1, 3]);
  await sendNudges(env, Date.parse("2026-10-14T06:01:30Z"));
  assert.equal(pushes.length, 1);

  // Thursday's run: the same break is not told again (and costs no class requests).
  studios.length = 0;
  assert.equal(await refreshHistory(env, user(), WED + 86400_000, { fetchFn, classesFn }), 1);
  assert.deepEqual(studios, []);
  assert.equal(DB.rows("nudges")[0].sent_at, Date.parse("2026-10-14T06:00:30Z"));

  // Switched off: no habit read-back, no push planned.
  DB.sql.exec("DELETE FROM nudges");
  const off = user();
  off.state.nudges = false;
  await refreshHistory(env, off, WED, { fetchFn: async () => ({ bookings: HISTORY, pages: 1, complete: true }), classesFn });
  assert.equal(DB.rows("nudges").length, 0);
});
