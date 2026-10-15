// Tests for the web app's pure modules (visit dedupe, goals, For you scoring, Wrapped stats, share links).
// Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { visitsFrom, local, weekOf, addMonths } from '../js/visits.js';
import { counts, progress, summary, weekStreak, longestWeekStreak, calendar, suggestions, goalTitle, remindPayload } from '../js/goals.js';
import { travelMinutes, detourMinutes, recommend, slotOf } from '../js/recommend.js';
import { wrappedStats, archetype, together, longestStreak, topPercent, cardsFor } from '../js/wrapped-stats.js';
import { challengeIdFromHash, challengeShareUrl, challengeRoute } from '../js/links.js';

const Z = 'Europe/Stockholm';
const NOW = '2026-10-14T10:00:00Z';   // Wednesday 14 October 2026, 12:00 in Stockholm
let nid = 1;
/** A class booking; `when` is a UTC ISO time. */
function cls(when, o) {
  const p = o || {};
  const id = p.classId || nid++;
  return {
    id: nid++, class_id: id, studio_id: p.studio || 1, checked_in_at: p.checkedIn === false ? null : when,
    class: { id, title: p.title || 'Reformer', studio_id: p.studio || 1, start_time: when, end_time: new Date(+new Date(when) + (p.min || 50) * 60000).toISOString(), class_categories: (p.cats || []).map((c) => ({ category_id: c })) },
  };
}
const dropin = (when, studio) => ({ id: nid++, class_id: null, studio_id: studio || 1, checked_in_at: when, class: null });

// ---------------------------------------------------------------- visits

test('local days follow Europe/Stockholm, not UTC', () => {
  const l = local('2026-10-13T22:30:00Z', Z);
  assert.equal(l.day, '2026-10-14');
  assert.equal(l.hour, 0);
  assert.equal(l.weekday, 2);   // Wednesday
  assert.equal(weekOf('2026-10-14'), '2026-10-12');
  assert.equal(addMonths('2026-01', -3), '2025-10');
});

test('visit dedupe: one per class, drop-in near a class or a second drop-in that day is the same visit', () => {
  const c = cls('2026-10-10T08:00:00Z', { studio: 5, classId: 77 });
  const twice = Object.assign({}, c, { id: 999 });
  const v = visitsFrom([
    c, twice,
    dropin('2026-10-10T09:30:00Z', 5),          // 1.5 h after the class at the same studio: same visit
    dropin('2026-10-10T15:00:00Z', 6),          // other studio: counts
    dropin('2026-10-10T17:00:00Z', 6),          // second drop-in there that day: same visit
    dropin('2026-10-10T14:00:00Z', 5),          // 6 h after the class: counts
  ], { now: NOW, zone: Z });
  assert.deepEqual(v.map((x) => x.kind), ['class', 'dropin', 'dropin']);
  assert.equal(v[0].minutes, 50);
  assert.equal(v[1].minutes, 60);
});

test('visit rules: booked but not checked in counts only when everything counts, and never in the future', () => {
  const past = cls('2026-10-12T08:00:00Z', { checkedIn: false });
  const future = cls('2026-10-20T08:00:00Z', { checkedIn: false });
  const deleted = Object.assign(cls('2026-10-11T08:00:00Z'), { deleted: true });
  assert.equal(visitsFrom([past, future, deleted], { now: NOW, zone: Z }).length, 1);
  assert.equal(visitsFrom([past, future, deleted], { now: NOW, zone: Z, checkedInOnly: true }).length, 0);
});

// ---------------------------------------------------------------- goals

const october = visitsFrom([
  dropin('2026-10-01T06:00:00Z'), dropin('2026-10-03T06:00:00Z'), dropin('2026-10-05T06:00:00Z'),
  dropin('2026-10-07T06:00:00Z'), dropin('2026-10-09T06:00:00Z'), dropin('2026-10-11T06:00:00Z'),
  dropin('2026-10-12T06:00:00Z'), dropin('2026-10-13T06:00:00Z'), dropin('2026-10-14T06:00:00Z'),
  cls('2026-10-08T16:00:00Z', { title: 'Lap Swim', cats: [30], studio: 9 }),
], { now: NOW, zone: Z, checkedInOnly: true });

test('goal matching by category key and studio', () => {
  const swim = october.find((v) => v.kind === 'class');
  const gym = october.find((v) => v.kind === 'dropin');
  assert.ok(counts({ category: null }, swim) && counts({ category: null }, gym));
  assert.ok(counts({ category: 'anyClass' }, swim) && !counts({ category: 'anyClass' }, gym));
  assert.ok(counts({ category: 'gym' }, gym) && !counts({ category: 'gym' }, swim));
  assert.ok(counts({ category: '30' }, swim) && !counts({ category: '2' }, swim));
  assert.ok(!counts({ category: null, studioId: 3 }, swim));
  assert.equal(goalTitle('gym'), 'Gym visits');
  assert.equal(goalTitle('2', () => 'Yoga'), 'Yoga classes');
});

test('goal progress and pace on 14 October', () => {
  const p = progress({ category: 'gym', target: 20 }, october, '2026-10-14');
  assert.equal(p.done, 9);
  assert.equal(p.status, 'onPace');            // 20 * 14 / 31 = 9.03 expected
  assert.equal(p.pace, 'Exactly on pace');
  assert.equal(p.toGo, '11 to go · 17 days left');
  assert.equal(p.pacePct, 45.2);
  const swim = progress({ category: '30', target: 2 }, october, '2026-10-14');
  assert.equal(swim.done, 1);
  assert.equal(swim.last.day, '2026-10-08');
  const behind = progress({ category: null, target: 40 }, october, '2026-10-14');
  assert.equal(behind.status, 'behind');
  assert.equal(progress({ category: 'gym', target: 5 }, october, '2026-10-14').status, 'done');
});

test('goals summary: ring totals, status and the daily hint', () => {
  const s = summary([{ category: 'gym', target: 20 }, { category: '30', target: 2 }], october, '2026-10-14');
  assert.equal(s.done, 10);
  assert.equal(s.target, 22);
  assert.equal(s.status, 'On pace');
  assert.equal(s.hint, 'Day 14 of 31. Keep 1 visit every 1.5 days to hit everything.');
});

test('week streaks', () => {
  assert.equal(weekStreak(october, '2026-10-14'), 3);    // weeks of 28 Sep, 5 Oct, 12 Oct
  assert.equal(weekStreak(october, '2026-10-26'), 0);    // a whole week without a visit breaks it
  assert.equal(longestWeekStreak(october), 3);
});

test('calendar marks visits, category-goal visits and today', () => {
  const c = calendar('2026-10-14', october, [{ category: '30', target: 2 }, { category: 'gym', target: 20 }]);
  assert.equal(c.lead, 3);                                // 1 October 2026 is a Thursday
  assert.equal(c.cells.length, 31);
  assert.ok(c.cells[7].goal && c.cells[7].visit);         // the swim on 8 October
  assert.ok(c.cells[0].visit && !c.cells[0].goal);
  assert.ok(c.cells[13].today && !c.cells[14].visit && c.cells[14].future);
});

test('suggestions average the last three full months', () => {
  const vs = [];
  for (const m of ['07', '08', '09']) for (let d = 1; d <= 18; d++) vs.push(dropin('2026-' + m + '-' + String(d).padStart(2, '0') + 'T06:00:00Z'));
  for (const m of ['07', '08', '09']) for (let d = 20; d <= 22; d++) vs.push(cls('2026-' + m + '-' + d + 'T16:00:00Z', { title: 'Hatha', cats: [2] }));
  const v = visitsFrom(vs, { now: NOW, zone: Z, checkedInOnly: true });
  const s = suggestions(v, '2026-10-14', []);
  assert.deepEqual(s[0], { category: 'gym', avg: 18, target: 20 });
  assert.deepEqual(s[1], { category: '2', avg: 3, target: 4 });
  assert.equal(suggestions(v, '2026-10-14', [{ category: 'gym' }])[0].category, '2');
});

test('reminder payload only carries goals with a reminder', () => {
  const p = remindPayload([{ id: 'a', category: 'gym', target: 20, remind: true }, { id: 'b', category: '2', target: 4, remind: false }], () => 'Yoga');
  assert.deepEqual(p, [{ id: 'a', title: 'Gym visits', category: 'gym', target: 20, remind: true }]);
});

// ---------------------------------------------------------------- For you

const HOME = { kind: 'home', lat: 59.3165, lon: 18.06 };
const WORK = { kind: 'work', lat: 59.3345, lon: 18.062, workdays: [0, 1, 2, 3, 4] };

test('travel estimate grows with distance and mode', () => {
  const near = { lat: 59.318, lon: 18.062 };
  assert.ok(travelMinutes(HOME, near, 'walk') <= 5);
  assert.ok(travelMinutes(HOME, WORK, 'bike') < travelMinutes(HOME, WORK, 'walk'));
  assert.ok(travelMinutes(HOME, WORK, 'transit') <= travelMinutes(HOME, WORK, 'walk'));
  const onTheWay = { lat: 59.3255, lon: 18.061 };
  const offTheWay = { lat: 59.33, lon: 18.15 };
  assert.ok(detourMinutes(WORK, HOME, onTheWay, 'bike') <= 3);
  assert.ok(detourMinutes(WORK, HOME, offTheWay, 'bike') > 15);
  assert.equal(slotOf(12, 2), 'lunch');
  assert.equal(slotOf(10, 6), 'weekend morning');
});

test('recommendations rank history, places and friends, and explain why', () => {
  const studios = new Map([[1, { lat: 59.3168, lon: 18.0605 }], [2, { lat: 59.3350, lon: 18.0630 }], [3, { lat: 59.3255, lon: 18.061 }], [4, { lat: 59.40, lon: 17.90 }]]);
  const hist = [];
  for (let i = 1; i <= 9; i++) hist.push(cls('2026-09-' + String(i * 3).padStart(2, '0') + 'T05:00:00Z', { title: 'Reformer', studio: 1, cats: [19] }));
  const visits = visitsFrom(hist, { now: NOW, zone: Z });
  const mk = (id, title, studio, when, spots, cats) => ({ id, title, studio_id: studio, start_time: when, end_time: new Date(+new Date(when) + 3000000).toISOString(), available_spots: spots, class_categories: (cats || []).map((c) => ({ category_id: c })) });
  const classes = [
    mk(1, 'Reformer', 1, '2026-10-15T05:00:00Z', 6, [19]),            // Thu 07:00 near home, done 9 times there
    mk(2, 'Strength Circuit', 2, '2026-10-15T10:05:00Z', 8),         // Thu 12:05 next to work, lunch window
    mk(3, 'Hatha Flow', 3, '2026-10-15T15:45:00Z', 2, [2]),          // Thu 17:45 on the way home, 2 spots
    mk(4, 'Far Away', 4, '2026-10-15T15:45:00Z', 10),
    mk(5, 'Booked', 1, '2026-10-15T06:00:00Z', 5),
    mk(6, 'Full', 1, '2026-10-15T06:30:00Z', 0),
    mk(7, 'Past', 1, '2026-10-14T07:00:00Z', 5),
  ];
  const r = recommend({
    classes, visits, now: NOW, zone: Z, booked: new Set([5]), studios, places: [HOME, WORK],
    friends: [{ userId: 7, name: 'Sam', classId: 3 }, { userId: 8, name: 'Alex', classId: 3 }], catTitle: (id) => ({ 19: 'Pilates', 2: 'Yoga' }[id]),
    prefs: { mode: 'bike', maxDetour: 15, workFrom: '11:30', workTo: '13:30', useFriends: true },
  });
  const ids = r.map((x) => x.class.id);
  assert.equal(ids[0], 1);
  assert.ok(!ids.includes(5) && !ids.includes(6) && !ids.includes(7));
  assert.equal(ids[ids.length - 1], 4);
  const texts = (id) => r.find((x) => x.class.id === id).reasons.map((x) => x.text);
  assert.ok(texts(1).includes('You did 9 Reformers here'));
  assert.ok(texts(1).some((t) => /min from home$/.test(t)));
  assert.ok(texts(2).some((t) => /min from work$/.test(t)));
  assert.ok(texts(3).some((t) => /^On your way home · \+\d+ min$/.test(t)));
  assert.ok(texts(3).includes('Sam, Alex'));
  assert.ok(texts(3).includes('2 spots left'));
  assert.ok(r[0].match > r[r.length - 1].match && r[0].match <= 99);
  const noFriends = recommend({ classes, visits, now: NOW, zone: Z, studios, places: [], friends: [{ userId: 7, name: 'Sam', classId: 3 }], prefs: { useFriends: false } });
  assert.ok(!noFriends.find((x) => x.class.id === 3).reasons.some((x) => x.icon === 'friends'));
});

// ---------------------------------------------------------------- Wrapped

test('Wrapped stats, streak, together and cards', () => {
  const raw = [];
  for (let w = 0; w < 7; w++) raw.push(cls(new Date(Date.UTC(2026, 7, 3 + w * 7, 4, 15)).toISOString(), { title: 'Reformer', studio: 1, classId: 5000 + w }));
  raw.push(dropin('2026-01-05T16:00:00Z', 2), dropin('2026-03-02T16:00:00Z', 3));
  raw.push(cls('2025-12-30T05:00:00Z'));                                    // last year: not counted
  const v = visitsFrom(raw, { now: NOW, zone: Z });
  const tog = together(v, [{ user_id: 21, class_id: 5000 }, { user_id: 21, class_id: 5001 }, { user_id: 22, class_id: 5002 }, { user_id: 21, class_id: 1 }]);
  assert.deepEqual(tog, [{ userId: 21, count: 2 }, { userId: 22, count: 1 }]);
  const s = wrappedStats(v, { today: '2026-10-14', together: tog });
  assert.equal(s.total, 9);
  assert.equal(s.classes, 7);
  assert.equal(s.dropins, 2);
  assert.equal(s.minutes, 7 * 50 + 120);
  assert.equal(s.bestMonth.name, 'August');
  assert.equal(s.months[7], 5);            // 3, 10, 17, 24, 31 August
  assert.deepEqual(s.favStudio, { id: 1, count: 7 });
  assert.deepEqual(s.topClass, { title: 'Reformer', count: 7 });
  assert.equal(s.topHour.label, '06:00');
  assert.deepEqual(longestStreak(v.filter((x) => x.day >= '2026-01-01')), { weeks: 7, from: '2026-08-03', to: '2026-09-14' });
  assert.equal(s.archetype.key, 'earlyBird');
  assert.equal(s.friend.userId, 21);
  assert.deepEqual(cardsFor(s, null), ['intro', 'visits', 'persona', 'place', 'streak', 'share']);
  assert.deepEqual(cardsFor(s, { visits: 92 }).slice(-2), ['top', 'share']);
  assert.equal(topPercent(92), 8);
  assert.equal(topPercent(100), 1);
});

test('archetype rules', () => {
  const at = (h, wd, o) => ({ hour: h, weekday: wd, kind: 'class', title: 'Class', categories: [], studioId: 1, day: '2026-01-01', ...(o || {}) });
  assert.equal(archetype(Array.from({ length: 6 }, () => at(20, 1)), null).key, 'nightOwl');
  assert.equal(archetype(Array.from({ length: 6 }, () => at(12, 2)), null).key, 'lunchBreaker');
  assert.equal(archetype(Array.from({ length: 6 }, () => at(10, 6)), null).key, 'weekendWarrior');
  assert.equal(archetype(Array.from({ length: 6 }, () => at(16, 1, { title: 'Yin Yoga' })), null).key, 'zenMaster');
  assert.equal(archetype(Array.from({ length: 6 }, () => at(16, 1, { kind: 'dropin', title: 'Solo training' })), null).key, 'ironRegular');
  assert.equal(archetype(Array.from({ length: 6 }, (_, i) => at(16, 1, { studioId: i })), null).key, 'explorer');
  assert.equal(archetype(Array.from({ length: 6 }, () => at(16, 1)), null).key, 'loyalist');
  assert.equal(archetype([], null).key, 'newcomer');
});

// ---------------------------------------------------------------- share links

test('challenge share links', () => {
  assert.equal(challengeIdFromHash('#challenge/k3J9x0aQ2mZp'), 'k3J9x0aQ2mZp');
  assert.equal(challengeIdFromHash('#/challenge/k3J9x0aQ2mZp/'), 'k3J9x0aQ2mZp');
  assert.equal(challengeIdFromHash('#/home'), null);
  assert.equal(challengeIdFromHash('#challenge/<script>'), null);
  assert.equal(challengeShareUrl('abcd'), 'https://djui.github.io/bruce/app/#challenge/abcd');
  assert.equal(challengeRoute('abcd'), '#/friends/challenge/abcd?tab=challenges');
});

test('classes sort by the instant they start, whatever the timestamp spelling', async () => {
  const { byStart } = await import('../js/util.js');
  const list = [
    { id: 1, start_time: '2026-10-18T10:00:00Z' },        // 12:00 in Stockholm
    { id: 2, start_time: '2026-10-18T17:00:00.000Z' },    // 19:00
    { id: 3, start_time: '2026-10-18T10:00:00+02:00' },   // 10:00
    { id: 4 },
  ];
  assert.deepEqual(list.sort(byStart).map((c) => c.id), [3, 1, 2, 4]);
});

test('a day list keeps only classes that start on that day in Stockholm', async () => {
  const { onDay } = await import('../js/util.js');
  assert.equal(onDay({ start_time: '2026-10-18T10:00:00Z' }, '2026-10-18'), true);
  assert.equal(onDay({ start_time: '2026-10-17T22:30:00Z' }, '2026-10-18'), true);   // 00:30 on the 18th
  assert.equal(onDay({ start_time: '2026-10-19T08:00:00Z' }, '2026-10-18'), false);
  assert.equal(onDay({}, '2026-10-18'), false);
});
