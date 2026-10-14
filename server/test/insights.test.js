import { test } from "node:test";
import assert from "node:assert/strict";
import {
  localDay, addDays, diffDays, monthEnd, visitsFromBookings, dailyRows, fromDetail, longestWeekStreak, goalReminders, challengePeriod,
  challengeMonths, challengeStats, cleanChallenge, percentile, cohortValues, percentiles,
} from "../src/insights.js";

const NOW = Date.parse("2026-10-14T10:00:00Z");
const cls = (id, classId, start, extra = {}) => ({
  id, class_id: classId, studio_id: 1724, checked_in_at: null,
  class: { title: "Reformer", start_time: start, end_time: new Date(Date.parse(start) + 50 * 60_000).toISOString(), studio: { name: "STC Rosenlundsparken" },
           class_categories: [{ category_id: 2 }] },
  ...extra,
});
const dropin = (id, at, studio = 1724) => ({ id, class_id: null, studio_id: studio, checked_in_at: at, opening_hour_occurrence_id: 9 });

test("days: local day across midnight and DST, calendar arithmetic", () => {
  assert.equal(localDay(Date.parse("2026-10-13T22:30:00Z")), "2026-10-14");   // 00:30 CEST
  assert.equal(localDay(Date.parse("2026-12-31T23:30:00Z")), "2027-01-01");   // 00:30 CET
  assert.equal(addDays("2026-02-28", 1), "2026-03-01");
  assert.equal(diffDays("2026-10-14", "2026-10-31"), 17);
  assert.equal(monthEnd("2028-02-10"), "2028-02-29");
});

test("visits: everything counts, deduplicated", () => {
  const visits = visitsFromBookings([
    cls(1, 100, "2026-10-13T16:00:00Z"),                                            // booked, not checked in: counts
    cls(2, 100, "2026-10-13T16:00:00Z", { checked_in_at: "2026-10-13T15:50:00Z" }),  // same class again: once, now checked in
    dropin(3, "2026-10-13T15:52:00Z"),                                              // door check-in for that class: same visit
    cls(10, 104, "2026-10-09T09:00:00Z"), cls(11, 104, "2026-10-09T09:00:00Z", { checked_in_at: "2026-10-09T08:55:00Z" }), // merged: checked in
    dropin(4, "2026-10-12T07:00:00Z"), dropin(5, "2026-10-12T19:00:00Z"),          // two gym visits the same day: once
    dropin(6, "2026-10-12T08:00:00Z", 999),                                         // another studio: counts
    cls(7, 101, "2026-10-11T09:00:00Z", { deleted: true }),                         // cancelled: no
    cls(8, 102, "2026-10-20T09:00:00Z"),                                            // future: no
    cls(9, 103, "2026-10-10T09:00:00Z", { class: { title: null, opening: true, start_time: "2026-10-10T05:00:00Z" } }), // opening slot = gym
  ], NOW);
  assert.deepEqual(visits.map((v) => v.kind), ["class", "dropin", "dropin", "dropin", "class"]);
  assert.equal(visits[4].checkedIn, true);
  assert.equal(visits[0].checkedIn, true);
  assert.equal(visits[0].minutes, 50);
  assert.deepEqual(visits[0].categories, ["2"]);
  assert.equal(visits[1].minutes, 60);
  const rows = dailyRows(visits, { detail: true });
  assert.deepEqual(rows.map((r) => [r.day, r.visits, r.checkins]), [["2026-10-09", 1, 1], ["2026-10-10", 1, 0], ["2026-10-12", 2, 2], ["2026-10-13", 1, 1]]);
  assert.deepEqual(rows[2].studios, [999, 1724]);
  assert.deepEqual(fromDetail(rows[3].detail[0], rows[3].day), { ...visits[0] });
  assert.equal(dailyRows(visits)[0].detail, null);
});

test("week streak", () => {
  assert.equal(longestWeekStreak([]), 0);
  // Mon 5 Oct, Sun 11 Oct (same week), Wed 14 Oct, then a gap week, then 28 Oct.
  assert.equal(longestWeekStreak(["2026-10-05", "2026-10-11", "2026-10-14", "2026-10-28"]), 2);
  assert.equal(longestWeekStreak(["2026-12-28", "2027-01-04", "2027-01-11"]), 3);
});

test("goal reminders: behind pace from day 8, once a week", () => {
  const swim = { id: "g1", title: "Swims", category: "7", target: 8 };
  const any = { id: "g2", title: "Visits", category: null, target: 2 };
  const v = (day, cats = ["7"], checkedIn = true) => ({ day, kind: "class", categories: cats, checkedIn, studioId: 1 });
  const visits = [v("2026-10-02"), v("2026-10-03", ["7"], false), v("2026-10-05", ["2"])];
  assert.deepEqual(goalReminders([swim, any], visits, "2026-10-07"), []);
  const due = goalReminders([swim, any], visits, "2026-10-14", {}, NOW);
  assert.deepEqual(due.map((d) => [d.goal.id, d.count, d.daysLeft]), [["g1", 1, 17]]);
  assert.deepEqual(goalReminders([swim], visits, "2026-10-14", { g1: NOW - 3 * 86400_000 }, NOW), []);
});

test("challenge periods: fixed range and monthly repeat", () => {
  const oct = { start: "2026-10-01", end: "2026-10-31", repeatMonthly: false };
  assert.deepEqual(challengePeriod(oct, "2026-10-14"), { start: "2026-10-01", end: "2026-10-31", days: 31, label: "October 2026", day: 14, daysLeft: 17 });
  assert.equal(challengePeriod(oct, "2026-09-20").daysLeft, 31);
  const rep = { start: "2026-09-15", end: "2026-09-30", repeatMonthly: true };
  assert.equal(challengePeriod(rep, "2026-09-20").label, "15 Sep – 30 Sep 2026");
  assert.equal(challengePeriod(rep, "2026-11-03").label, "November 2026");
  assert.deepEqual(challengeMonths(rep, "2026-11-03"), ["2026-11", "2026-10", "2026-09"]);
  assert.deepEqual(challengeMonths(oct, "2026-12-01"), ["2026-10"]);
});

test("challenge stats: leaderboard, ranks, together, categories, months, invited last", () => {
  const ch = { id: "c", metric: "classes", start: "2026-10-01", end: "2026-10-31", repeatMonthly: false, category: null };
  const visit = (day, classId, title = "Reformer", studioId = 1724) =>
    ({ at: Date.parse(`${day}T16:00:00Z`), day, kind: classId ? "class" : "dropin", classId, title: classId ? title : null, studioId,
       studio: null, minutes: classId ? 50 : 60, categories: classId ? ["2"] : [], checkedIn: true });
  const byUser = new Map([
    [1, [visit("2026-10-02", 10), visit("2026-10-03", 11), visit("2026-10-05", null), visit("2026-09-30", 9)]],
    [2, [visit("2026-10-02", 10), visit("2026-10-03", 11), visit("2026-10-04", 12, "Hatha Flow", 1489)]],
    [3, [visit("2026-10-02", 10), visit("2026-10-06", 13)]],
  ]);
  const people = [{ userId: 1, name: "Uwe", status: "accepted" }, { userId: 2, name: "Robin", status: "accepted" },
                  { userId: 3, name: "Sam", status: "accepted" }, { userId: 4, name: "Alex", status: "invited" }];
  const { leaderboard, months, period } = challengeStats(ch, people, byUser, 1, "2026-10-06");
  assert.equal(period.day, 6);
  assert.deepEqual(leaderboard.map((e) => [e.name, e.rank, e.score]), [["Robin", 1, 3], ["Sam", 2, 2], ["Uwe", 2, 2], ["Alex", null, 0]]);
  const robin = leaderboard[0];
  assert.equal(robin.together, 2);
  assert.equal(robin.studios, 2);
  assert.deepEqual(robin.topClass, { title: "Reformer", count: 2 });
  assert.deepEqual(robin.topStudio, { id: 1724, name: null, count: 2 });
  assert.deepEqual(robin.daily, [0, 1, 1, 1, 0, 0]);
  const me = leaderboard.find((e) => e.userId === 1);
  assert.equal(me.visits, 3);   // September visit is outside the period
  assert.deepEqual(me.categories, [{ key: "2", count: 2 }, { key: "gym", count: 1 }]);
  assert.equal(me.together, 0);
  assert.equal(months.length, 1);
  assert.equal(months[0].entries[0].name, "Robin");
  // Category challenge: only gym visits count.
  const gym = challengeStats({ ...ch, metric: "visits", category: "gym" }, people, byUser, 1, "2026-10-06");
  assert.equal(gym.leaderboard[0].name, "Uwe");
  assert.equal(gym.leaderboard[0].score, 1);
});

test("challenge input validation", () => {
  const ok = cleanChallenge({ metric: "target", target: 12, start: "2026-11-01", end: "2026-11-30", repeatMonthly: true }, "2026-10-14");
  assert.equal(ok.title, "Everyone hits 12");
  assert.equal(ok.repeatMonthly, true);
  assert.match(cleanChallenge({ metric: "fastest", start: "2026-11-01", end: "2026-11-30" }, "2026-10-14").error, /metric/);
  assert.match(cleanChallenge({ metric: "visits", start: "2026-11-31", end: "2026-12-01" }, "2026-10-14").error, /days/);
  assert.match(cleanChallenge({ metric: "visits", start: "2026-01-01", end: "2027-06-01" }, "2026-10-14").error, /366/);
  assert.match(cleanChallenge({ metric: "visits", start: "2026-09-01", end: "2026-09-30" }, "2026-10-14").error, /over/);
});

test("percentiles: ties count half, small cohorts stay anonymous", () => {
  assert.equal(percentile([1, 2, 3, 4], 5), 100);
  assert.equal(percentile([1, 2, 3, 4], 3), 63);
  const rows = (uid, n) => Array.from({ length: n }, (_, i) => ({ user_id: uid, day: addDays("2026-01-05", 7 * i), checkins: 1, checkin_minutes: 50, studios: "[1]" }));
  const cohort = cohortValues([...rows(1, 3), ...rows(2, 10), ...rows(3, 20), ...rows(4, 1), { user_id: 6, day: "2026-02-01", checkins: 0, checkin_minutes: 0, studios: "[]" }]);
  assert.deepEqual(cohort.map((u) => [u.userId, u.visits, u.streak]), [[1, 3, 3], [2, 10, 10], [3, 20, 20], [4, 1, 1]]);
  assert.equal(percentiles(cohort, { visits: 15 }), null);
  const five = [...cohort, { userId: 5, visits: 30, minutes: 1500, studios: 4, streak: 2 }];
  assert.deepEqual(percentiles(five, { visits: 15, studios: 1 }), { visits: 60, studios: 40 });
});
