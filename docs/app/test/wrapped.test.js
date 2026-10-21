// Tests for Brüce Wrapped's pure numbers (js/wrapped-stats.js): year to date, months, personality, together, streaks,
// which cards show, the percentile query and the share card tiles.
// Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { visitsFrom } from '../js/visits.js';
import { wrappedStats, together, longestStreak, cardsFor, topPercent, percentileMetrics, dayRange, shareStats, archetype } from '../js/wrapped-stats.js';

const Z = 'Europe/Stockholm';
const NOW = '2026-10-14T10:00:00Z';
let nid = 1;
function cls(when, o) {
  const p = o || {};
  const id = p.classId || 100000 + nid++;
  return {
    id: nid++, class_id: id, studio_id: p.studio || 1, checked_in_at: p.checkedIn === false ? null : when,
    class: { id, title: p.title || 'Reformer', studio_id: p.studio || 1, start_time: when, end_time: new Date(+new Date(when) + (p.min || 50) * 60000).toISOString(), class_categories: [] },
  };
}
const dropin = (when, studio) => ({ id: nid++, class_id: null, studio_id: studio || 1, checked_in_at: when, class: null });
const visits = (raw) => visitsFrom(raw, { now: NOW, zone: Z });

test('year to date: totals, hours, months, best month and pace', () => {
  const raw = [
    cls('2026-09-01T05:00:00Z', { title: 'Reformer', studio: 1 }), cls('2026-09-08T05:00:00Z', { title: 'Reformer', studio: 1 }),
    cls('2026-09-15T16:00:00Z', { title: 'Yin Yoga', studio: 2, min: 70 }), cls('2026-02-02T06:00:00Z', { studio: 1 }),
    dropin('2026-03-03T05:00:00Z', 3),
    cls('2025-12-31T09:00:00Z'),                                   // last year
    cls('2026-10-20T05:00:00Z', { checkedIn: false }),             // future booking: not a visit yet
  ];
  const s = wrappedStats(visits(raw), { today: '2026-10-14' });
  assert.equal(s.year, 2026);
  assert.equal(s.total, 5);
  assert.equal(s.classes, 4);
  assert.equal(s.dropins, 1);
  assert.equal(s.minutes, 50 * 3 + 70 + 60);
  assert.equal(s.hours, 5);
  assert.deepEqual(s.months, [0, 1, 1, 0, 0, 0, 0, 0, 3, 0, 0, 0]);
  assert.equal(s.monthNow, 9);
  assert.deepEqual(s.bestMonth, { index: 8, name: 'September', count: 3 });
  assert.equal(s.studios, 3);
  assert.deepEqual(s.favStudio, { id: 1, count: 3 });
  assert.deepEqual(s.topClass, { title: 'Reformer', count: 3 });
  assert.equal(s.topHour.label, '07:00');
  assert.equal(s.every, Math.round(10 * 287 / 5) / 10);          // 1 Jan to 14 Oct is 287 days
});

test('an empty year shows only the intro and the share card', () => {
  const s = wrappedStats([], { today: '2026-10-14' });
  assert.equal(s.total, 0);
  assert.equal(s.bestMonth, null);
  assert.equal(s.favStudio, null);
  assert.equal(s.every, null);
  assert.equal(s.archetype.key, 'newcomer');
  assert.deepEqual(cardsFor(s, { visits: 50 }), ['intro', 'share']);
  assert.deepEqual(cardsFor(s, null), ['intro', 'share']);
  // A race of the year adds its chapter even without visits (races.js, racesOfYear).
  assert.deepEqual(cardsFor(Object.assign({}, s, { races: [{ key: 'midnattsloppet-stockholm-2026' }] }), null), ['intro', 'race', 'share']);
});

test('classes together: matched by class id, dropped when deleted or not mine', () => {
  const v = visits([cls('2026-05-04T05:00:00Z', { classId: 7001 }), cls('2026-05-11T05:00:00Z', { classId: 7002 }), dropin('2026-05-12T05:00:00Z')]);
  const t = together(v, [
    { user_id: 21, class_id: 7001 }, { user_id: 21, class_id: 7002 }, { user_id: 21, class_id: 7002 },   // the same class once
    { user_id: 22, class: { id: 7001 } },                                                                  // id from the included class
    { user_id: 23, class_id: 7001, deleted: true }, { user_id: 24, class_id: 9999 },
  ]);
  assert.deepEqual(t, [{ userId: 21, count: 2 }, { userId: 22, count: 1 }]);
  assert.deepEqual(together(v, null), []);
  assert.equal(wrappedStats(v, { today: '2026-10-14', together: t }).friend.userId, 21);
  assert.equal(wrappedStats(v, { today: '2026-10-14', together: [{ userId: 9, count: 0 }] }).friend, null);
});

test('longest streak counts weeks in a row, Monday to Sunday', () => {
  const days = ['2026-01-05', '2026-01-11', '2026-01-12', '2026-01-19', '2026-02-09', '2026-02-16'];
  const v = days.map((d) => ({ day: d }));
  assert.deepEqual(longestStreak(v), { weeks: 3, from: '2026-01-05', to: '2026-01-19' });
  assert.deepEqual(longestStreak([]), { weeks: 0, from: null, to: null });
  assert.equal(longestStreak([{ day: '2026-01-04' }, { day: '2026-01-05' }]).weeks, 2);   // Sunday then Monday
});

test('cards follow the data: streak card needs a streak or a friend, percentiles need the server', () => {
  const v = visits([cls('2026-06-01T05:00:00Z'), cls('2026-06-15T05:00:00Z'), cls('2026-06-29T05:00:00Z')]);   // no two weeks in a row
  const s = wrappedStats(v, { today: '2026-10-14' });
  assert.deepEqual(cardsFor(s, null), ['intro', 'visits', 'persona', 'place', 'share']);
  assert.deepEqual(cardsFor(Object.assign({}, s, { friend: { userId: 21, count: 2 } }), { visits: 40 }), ['intro', 'visits', 'persona', 'place', 'streak', 'top', 'share']);
  assert.deepEqual(cardsFor(s, { visits: null }), ['intro', 'visits', 'persona', 'place', 'share']);
});

test('percentile query and top percent', () => {
  const v = visits([cls('2026-06-01T05:00:00Z', { studio: 1 }), cls('2026-06-08T05:00:00Z', { studio: 2 }), dropin('2026-06-10T15:00:00Z', 3)]);
  assert.deepEqual(percentileMetrics(wrappedStats(v, { today: '2026-10-14' })), { visits: 3, minutes: 160, studios: 3, streak: 2 });
  assert.equal(topPercent(92), 8);
  assert.equal(topPercent(99.6), 1);
  assert.equal(topPercent(0), 100);
});

test('day ranges and share card tiles', () => {
  assert.equal(dayRange('2026-08-03', '2026-09-20'), '3 Aug to 20 Sep');
  assert.equal(dayRange('2026-08-03', '2026-08-20'), '3 to 20 Aug');
  assert.equal(dayRange('2026-08-03', '2026-08-03'), '3 Aug');
  assert.equal(dayRange(null, '2026-08-03'), '');
  const raw = [];
  for (let w = 0; w < 4; w++) raw.push(cls(new Date(Date.UTC(2026, 7, 3 + w * 7, 5)).toISOString(), { studio: 1 }));
  const s = wrappedStats(visits(raw), { today: '2026-10-14', together: [{ userId: 21, count: 3 }] });
  assert.deepEqual(shareStats(s, { studio: 'STC Rosenlundsparken', friend: 'Robin' }), [
    { value: '4', label: 'visits' }, { value: '3 h', label: 'trained' }, { value: '4×', label: 'Reformer, top class' },
    { value: '4', label: 'at STC Rosenlundsparken' }, { value: '4 wk', label: 'longest streak' }, { value: '3', label: 'classes with Robin' },
  ]);
  const one = wrappedStats(visits([dropin('2026-04-01T05:00:00Z')]), { today: '2026-10-14' });
  assert.deepEqual(shareStats(one, {}), [{ value: '1', label: 'visit' }, { value: '1 h', label: 'trained' }, { value: '1', label: 'at your top studio' }, { value: '1', label: 'in April, best month' }]);
});

test('personality: an early bird stays one even with a few late visits', () => {
  const at = (h) => ({ hour: h, weekday: 1, kind: 'class', title: 'Reformer', categories: [], studioId: 1, day: '2026-03-03' });
  assert.equal(archetype([at(6), at(6), at(7), at(18), at(19)], null).key, 'earlyBird');
  assert.match(archetype([at(6), at(6), at(7)], null).blurb, /^3 visits before 08:00/);
});
