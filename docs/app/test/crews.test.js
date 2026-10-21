// crews.js: friends going, crews and after the race, the same cases as RaceSocialTests.swift; and the demo server's
// answers for them (demo.js handleServer).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as C from '../js/crews.js';
import * as R from '../js/races.js';
import { DEMO_RACES, DEMO_MY_RACES, handleServer } from '../js/demo.js';

const fixture = R.decode(JSON.parse(readFileSync(new URL('./races-fixture.json', import.meta.url), 'utf8')));
const published = R.decode(JSON.parse(readFileSync(new URL('../races.json', import.meta.url), 'utf8')));
const race = (id) => fixture.find((r) => r.id === id);
const entry = (m) => R.entries([m], fixture)[0];

test('words: friends going, sessions a week, the crew name', () => {
  assert.equal(C.goingText(1), '1 friend going');
  assert.equal(C.goingText(2), '2 friends going');
  assert.equal(C.goingNames(['Alex']), 'Alex is going');
  assert.equal(C.goingNames(['Alex', 'Maja']), 'Alex and Maja are going');
  assert.equal(C.goingNames(['Alex', '', 'Maja', 'Robin']), 'Alex, Maja and Robin are going');
  assert.equal(C.weeklyText(1), '1 session a week');
  assert.equal(C.weeklyText(4), '4 sessions a week');
  assert.equal(C.thisWeekText(2, 4), '2 of 4 this week');
  assert.equal(C.crewName(race('hyrox-stockholm-2026')), 'HYROX Stockholm crew');
  assert.equal(C.defaultWeekly(null), 3);
  assert.equal(C.defaultWeekly({ perWeek: 5 }), 5);
  assert.equal(C.defaultWeekly({ perWeek: 12 }), 7);
});

test('crew weeks: last week, done this week, the first week', () => {
  const w = { weekly: 4, size: 2, lastWeek: { start: '2026-10-12', end: '2026-10-18', hit: 1 },
    members: [{ userId: 42, name: 'Uwe', thisWeek: 2, lastWeek: 4 }, { userId: 7, name: 'Robin', thisWeek: 1, lastWeek: 3 }] };
  assert.equal(C.lastWeekText(w), 'Last week 1 of 2 hit their sessions');
  assert.equal(C.doneThisWeekText(w), '0 of 2 done this week');
  assert.equal(C.lastWeekText(Object.assign({}, w, { lastWeek: null })), null, "the crew's first week");
  assert.equal(C.isCrew({ raceId: 'hyrox-stockholm-2026', weekly: 4 }), true);
  assert.equal(C.isCrew({ metric: 'classes' }), false);
});

test('going is per race and only for catalog races', () => {
  assert.equal(C.sharesGoing({ raceId: 'hyrox-stockholm-2026', going: true }), true);
  assert.equal(C.sharesGoing({ raceId: 'hyrox-stockholm-2026' }), false, 'off by default');
  assert.equal(C.sharesGoing({ raceId: null, going: true, name: 'Club 10K' }), false, 'a race added by hand');
});

test('results links: https only; the 2026 editions are over with results', () => {
  assert.equal(C.resultsUrl(race('tough-viking-stadion-2027')), null);
  assert.equal(C.resultsUrl({ resultsUrl: 'https://lidingoloppet.se/en/tcs-lidingoloppet/results-and-statistics' }), 'https://lidingoloppet.se/en/tcs-lidingoloppet/results-and-statistics');
  assert.equal(C.resultsUrl({ resultsUrl: 'http://example.com/results' }), null);
  assert.equal(C.resultsUrl({ resultsUrl: 'javascript:alert(1)' }), null);
  for (const r of published.filter((x) => x.resultsUrl)) assert.ok(C.resultsUrl(r), r.id);
  for (const id of ['goteborgsvarvet-2026', 'midnattsloppet-stockholm-2026']) {
    const r = published.find((x) => x.id === id);
    assert.ok(R.isPast(r, '2026-10-21'), id);
    assert.ok(C.resultsUrl(r), id);
    assert.equal(R.pillText(r, '2026-10-21'), 'Done');
  }
  assert.ok(DEMO_RACES.some((r) => r.id === 'midnattsloppet-stockholm-2026' && r.resultsUrl), 'the demo has a race with results');
  assert.ok(DEMO_MY_RACES.some((m) => m.raceId === 'midnattsloppet-stockholm-2026'), 'and it is in the demo My races');
});

test('recovery week after the race', () => {
  // HYROX on Saturday 12 December: race week 7-13 Dec, the recovery week 14-20 Dec.
  const e = entry(Object.assign(R.fromRace(race('hyrox-stockholm-2026')), { day: '2026-12-12' }));
  assert.equal(C.recovery(e, '2026-12-12'), null, 'race day');
  const r = C.recovery(e, '2026-12-13');
  assert.equal(r.monday, '2026-12-14');
  assert.equal(r.sunday, '2026-12-20');
  assert.equal(r.text, '1 Mobility and 1 Sauna');
  assert.deepEqual(r.mix.map((x) => x.key), ['mobility', 'sauna']);
  assert.ok(C.recovery(e, '2026-12-20'));
  assert.equal(C.recovery(e, '2026-12-21'), null, 'the week after the recovery week');
  // Without a day of its own, a multi-day event counts from its last day.
  const all = entry(R.fromRace(race('hyrox-stockholm-2026')));
  assert.equal(C.recovery(all, '2026-12-13'), null, 'still on');
  assert.equal(C.recovery(all, '2026-12-14').monday, '2026-12-14');
  // A run: massage and mobility.
  assert.equal(C.recovery(entry(R.fromRace(race('goteborgsvarvet-2027'))), '2027-05-24').text, '1 Massage and 1 Mobility');
});

test('demo server: friends going while you share a race, a crew with its weeks, one crew per race', () => {
  let g = handleServer('GET', '/races/going', {}).body;
  assert.equal(g.sharing, true, 'the demo shares HYROX Stockholm');
  assert.deepEqual(g.going['tough-viking-stadion-2027'].map((f) => f.userId), [22, 23]);
  handleServer('PUT', '/me/races', { races: [] });
  assert.deepEqual(handleServer('GET', '/races/going', {}).body, { going: {}, sharing: false, mine: [] });
  handleServer('PUT', '/me/races', { races: [{ id: 'hyrox-stockholm-2026', going: true }] });
  assert.equal(handleServer('GET', '/races/going', {}).body.sharing, true);

  const crew = handleServer('GET', '/challenges/demoCrew', {}).body;
  assert.equal(crew.challenge.raceId, 'hyrox-stockholm-2026');
  assert.equal(crew.crew.weekly, 4);
  assert.equal(crew.crew.lastWeek.hit, 3);
  assert.equal(crew.crew.members[0].thisWeek, 4);
  assert.equal(handleServer('POST', '/challenges', { raceId: 'hyrox-stockholm-2026', weekly: 3, end: '2026-12-12' }).status, 409);
  const made = handleServer('POST', '/challenges', { raceId: 'tough-viking-stadion-2027', weekly: 3, title: 'Viking crew', end: '2027-05-15', invite: [22] });
  assert.equal(made.status, 201);
  assert.equal(made.body.challenge.weekly, 3);
  assert.deepEqual(made.body.challenge.participants.map((p) => p.status), ['accepted', 'invited']);
  const d = handleServer('GET', '/challenges/' + made.body.challenge.id, {}).body;
  assert.equal(d.crew.lastWeek, null, 'started today');
  assert.equal(d.crew.size, 1);
});

test('PUT /me/races body: going goes with the moment it was flipped, also when switched off', async () => {
  const { racesPayload } = await import('../js/store.js');
  const hyrox = Object.assign(R.fromRace(race('hyrox-stockholm-2026')), { day: '2026-12-12' });
  const on = Object.assign({}, hyrox, { going: true, goingAt: 1000 });
  const off = Object.assign(R.fromRace(race('vasaloppet-2027')), { going: false, goingAt: 2000 });
  const quiet = R.fromRace(race('tough-viking-stadion-2027'));
  const custom = { id: 'abc', raceId: null, name: 'Club 10K', date: '2026-11-14', going: true, goingAt: 3000 };
  const body = racesPayload([on, off, quiet, custom], fixture, '2026-10-21');
  assert.deepEqual(body.map((r) => [r.id, r.going, r.goingAt]), [['hyrox-stockholm-2026', true, 1000], ['vasaloppet-2027', false, 2000]],
    'a race nobody switched and a race added by hand are not sent');
  assert.equal(body[0].date, '2026-12-12', 'the member\'s day');
});
