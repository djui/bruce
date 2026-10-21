// Races: the catalog file (docs/app/races.json) is valid, and the race logic in js/races.js (countdown, price steps,
// grouping, filters, My races) and js/calendar.js icsForRace behave like Shared/BruceCore/Races.swift (RacesTests).
// The logic tests read races-fixture.json, the catalog frozen as checked on 21 Oct 2026, so updating the catalog only
// has to keep it valid.
// Also the pure parts of the hand-run link check, scripts/check-races.mjs (it is imported here, never run).
// Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as R from '../js/races.js';
import { icsForRace } from '../js/calendar.js';
import { DEMO_RACES, DEMO_MY_RACES } from '../js/demo.js';
import { robotsVerdict, datePatterns, dateSeen, isPlatformHost, parseRobots } from '../../../scripts/check-races.mjs';

const read = (rel) => JSON.parse(readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8'));
const FILE = read('../races.json');
const CATALOG = R.decode(read('./races-fixture.json'));
const TODAY = '2026-10-21';
const race = (id) => CATALOG.find((r) => r.id === id);

// ---------------------------------------------------------------- the catalog file

test('races.json is valid: unique ids, real ISO dates, known enums, https links, endDate after date, checkedOn', () => {
  assert.deepEqual(R.validate(FILE), []);
  assert.ok(FILE.races.length >= 1);
  assert.equal(R.decode(FILE).length, FILE.races.length, 'every entry is readable by the apps');
  for (const r of FILE.races) assert.ok(r.checkedOn <= FILE.checkedOn, r.id + ' was checked on or before the file date');
  assert.deepEqual(R.validate(read('./races-fixture.json')), [], 'the frozen fixture is a valid catalog too');
});

test('the fixture is the 2026–27 season as researched on 21 Oct 2026', () => {
  const f = read('./races-fixture.json').races;
  assert.equal(f.length, 32);
  assert.deepEqual(f.filter((r) => r.klassiker).map((r) => r.name), ['Vasaloppet', 'Vätternrundan', 'Vansbrosimningen', 'Lidingöloppet']);
  const by = (k) => f.reduce((m, r) => Object.assign(m, { [r[k]]: (m[r[k]] || 0) + 1 }), {});
  assert.deepEqual(by('type'), { hyrox: 2, endurance: 6, running: 13, obstacle: 7, triathlon: 4 });
  assert.deepEqual(by('country'), { SE: 19, NO: 8, DK: 5 });
});

test('the validator catches what the schema forbids', () => {
  const ok = { id: 'a-2027', name: 'A', type: 'running', date: '2027-05-01', city: 'X', country: 'SE', distancesKm: [5], signupUrl: 'https://a.example', status: 'open', checkedOn: '2026-10-21' };
  const v = (r) => R.validate({ version: 1, checkedOn: '2026-10-21', races: [Object.assign({}, ok, r)] });
  assert.deepEqual(v({}), []);
  assert.match(v({ date: '2027-02-30' })[0], /date must be a real/);
  assert.match(v({ endDate: '2027-04-30' })[0], /endDate/);
  assert.match(v({ type: 'paddle' })[0], /type must be/);
  assert.match(v({ status: 'maybe' })[0], /status must be/);
  assert.match(v({ signupUrl: 'http://a.example' })[0], /https/);
  assert.match(v({ status: 'opensSoon' })[0], /opensOn/);
  assert.match(v({ country: 'FI' })[0], /country/);
  assert.match(v({ type: 'endurance' })[0], /need a sport/);
  assert.match(v({ priceSteps: [{ amount: 10.5, currency: 'SEK' }] })[0], /amount/);
  assert.match(v({ priceSteps: [{ until: '2027-01-10', amount: 1, currency: 'SEK' }, { from: '2027-01-05', amount: 2, currency: 'SEK' }] })[0], /overlap/);
  assert.match(v({ checkedOn: undefined })[0], /checkedOn/);
  assert.match(v({ sigupUrl: 'https://typo.example' }).join(), /unknown field sigupUrl/);
  // Formats, the change rule, start info and the arrival time.
  assert.deepEqual(v({ formats: [{ code: 'a', title: 'A', teamSize: 2, distanceKm: 5, note: 'n', priceSteps: [{ amount: 1, currency: 'SEK' }] }], changeRule: 'x', startInfo: 'y', arriveMinutesBefore: 90 }), []);
  assert.match(v({ formats: [] })[0], /formats/);
  assert.match(v({ formats: [{ code: 'Open', title: 'Open' }] })[0], /code/);
  assert.match(v({ formats: [{ code: 'a', title: 'A' }, { code: 'a', title: 'B' }] })[0], /duplicate code/);
  assert.match(v({ formats: [{ code: 'a', title: 'A', priceSteps: [{ amount: 1, currency: 'XXX' }] }] })[0], /currency/);
  assert.match(v({ formats: [{ code: 'a', title: 'A', size: 2 }] })[0], /unknown field size/);
  assert.match(v({ arriveMinutesBefore: 0 })[0], /arriveMinutesBefore/);
  assert.match(v({ changeRule: ' ' })[0], /changeRule/);
  // The apps keep the formats they can read and drop the rest.
  const dec = R.decode({ races: [Object.assign({}, ok, { formats: [{ code: 'a', title: 'A' }, { code: '', title: 'B' }, { title: 'C' }], arriveMinutesBefore: -5 })] })[0];
  assert.deepEqual(dec.formats.map((f) => f.code), ['a']);
  assert.equal(dec.arriveMinutesBefore, undefined);
  assert.equal(R.decode({ races: [Object.assign({}, ok, { formats: [] })] })[0].formats, undefined);
  const two = R.validate({ version: 1, checkedOn: '2026-10-21', races: [ok, Object.assign({}, ok, { date: '2027-04-01' })] });
  assert.ok(two.some((e) => /duplicate id/.test(e)) && two.some((e) => /sorted/.test(e)));
  // The apps skip what they can't read instead of failing on the whole file (and render what they keep).
  const bad = [Object.assign({}, ok, { id: 'b', type: 'paddle' }), Object.assign({}, ok, { id: 'c', date: '2027-02-30' }),
    Object.assign({}, ok, { id: 'd', endDate: 'garbage' }), Object.assign({}, ok, { id: 'e', opensOn: '2027-13-01' }),
    Object.assign({}, ok, { id: 'f', priceSteps: [{ amount: 1, currency: 'SEK', from: 'soon' }] })];
  assert.deepEqual(R.decode({ races: [ok].concat(bad) }).map((r) => r.id), ['a-2027']);
  const bare = R.decode({ races: [{ id: 'g', name: 'G', type: 'running', date: '2027-05-01', signupUrl: 'https://g.example', status: 'open' }] })[0];
  assert.deepEqual(bare.distancesKm, []);
  assert.equal(R.pillText(bare, TODAY), 'Sign-up open');
});

test('demo races are catalog races, and demo My races point at them', () => {
  assert.ok(DEMO_RACES.length > 10);
  assert.deepEqual(R.validate({ version: 1, checkedOn: '2026-10-21', races: DEMO_RACES }), []);
  // Prices and status may move on in the catalog; the race itself must stay the same.
  const stable = (r) => r && [r.id, r.name, r.type, r.sport, r.date, r.endDate, r.city, r.country, r.venue].join('|');
  for (const d of DEMO_RACES) assert.equal(stable(d), stable(FILE.races.find((r) => r.id === d.id)), d.id);
  for (const m of DEMO_MY_RACES) assert.ok(DEMO_RACES.some((r) => r.id === m.raceId), m.raceId);
});

// ---------------------------------------------------------------- dates and countdown

test('countdown: days to go, tomorrow, race day, done', () => {
  const tv = race('tough-viking-stadion-2027'), hyrox = race('hyrox-stockholm-2026');
  assert.equal(R.daysToGo(tv, TODAY), 206);
  assert.equal(R.countdownText(tv, TODAY), '206 days to go');
  assert.equal(R.countdownShort(tv, TODAY), '206 days');
  assert.equal(R.daysToGo(hyrox, TODAY, '2026-12-12'), 52);
  assert.equal(R.countdownText(hyrox, '2026-12-09'), 'Tomorrow');
  assert.equal(R.countdownText(hyrox, '2026-12-11'), 'Race day');
  assert.equal(R.isPast(hyrox, '2026-12-13'), false);
  assert.equal(R.countdownText(hyrox, '2026-12-14'), 'Done');
  assert.equal(R.countdownText(hyrox, '2026-12-11', '2026-12-12'), 'Tomorrow');
  assert.deepEqual(R.days(hyrox), ['2026-12-10', '2026-12-11', '2026-12-12', '2026-12-13']);
  assert.equal(R.daysBetween('2026-10-24', '2026-10-26'), 2);   // across the end of summer time
  assert.equal(R.isDay('2027-02-29'), false);
  assert.equal(R.isDay('2028-02-29'), true);
});

test('date texts', () => {
  assert.equal(R.dateText(race('hyrox-stockholm-2026')), 'Thu 10 – Sun 13 Dec 2026');
  assert.equal(R.dateText(race('hyrox-stockholm-2026'), '2026-12-12'), 'Sat 12 Dec 2026');
  assert.equal(R.longDateText(race('tough-viking-stadion-2027')), 'Saturday 15 May 2027');
  assert.equal(R.longDateText(race('vatternrundan-2027')), 'Friday 18 to Saturday 19 June 2027');
  assert.equal(R.dateText(race('toughest-oslo-2027')), 'Sat 4 – Sun 5 Sep 2027');   // as the Apple apps write it
  assert.equal(R.longDateText(race('oslo-maraton-2027')), 'Saturday 18 September 2027');
});

// ---------------------------------------------------------------- prices and status

test('price steps: current, next, the day it changes, and the list pill', () => {
  const tv = race('tough-viking-stadion-2027');
  assert.equal(R.currentStep(tv, TODAY).amount, 750);
  assert.equal(R.nextStep(tv, TODAY).amount, 775);
  assert.equal(R.nextPriceChange(tv, TODAY), '2026-11-01');
  assert.equal(R.pillText(tv, TODAY), '750 SEK until 31 Oct');
  assert.equal(R.pillText(tv, '2026-11-02'), '775 SEK');
  assert.equal(R.nextPriceChange(tv, '2026-11-02'), null);
  assert.equal(R.nextPriceChange(race('bergen-city-marathon-2027'), TODAY), '2027-02-01');
  assert.equal(R.pillText(race('vasaloppet-2027'), TODAY), '2,685 SEK until 5 Nov');
  assert.equal(R.pillText(race('vasaloppet-2027'), '2026-11-06'), '2,985 SEK');
  assert.equal(R.pillText(race('hyrox-stockholm-2026'), TODAY), 'From 1,470 SEK');
  assert.equal(R.pillText(race('holmenkollstafetten-2027'), TODAY), '4,700 NOK per team');
  assert.equal(R.pillText(race('oslo-maraton-2027'), TODAY), 'Sign-up open');
  assert.equal(R.money(1234567, 'sek'), '1,234,567 SEK');
});

test('status texts', () => {
  assert.equal(R.pillText(race('goteborgsvarvet-2027'), TODAY), 'Sold out');
  assert.equal(R.pillText(race('copenhagen-marathon-2027'), TODAY), 'Lottery');
  assert.equal(R.pillText(race('stockholm-marathon-2027'), TODAY), 'Check site');
  assert.equal(R.pillText(race('vatternrundan-2027'), TODAY), 'Opens 25 Nov');
  assert.equal(R.statusText(race('vatternrundan-2027'), TODAY), 'Sign-up opens Wed 25 Nov');
  assert.equal(R.pillText(race('vatternrundan-2027'), '2026-11-25'), 'Opens today');
  assert.equal(R.statusText(race('vatternrundan-2027'), '2026-11-25'), 'Sign-up opens today');
  assert.equal(R.pillText(race('vatternrundan-2027'), '2026-11-26'), 'Check site');
  assert.equal(R.statusText(race('midnattsloppet-stockholm-2027'), TODAY), 'Sign-up opens Sun 1 Nov');
  assert.equal(R.pillText(race('hyrox-stockholm-2026'), '2026-12-20'), 'Done');
  assert.equal(R.signupLine(race('tough-viking-stadion-2027'), TODAY), 'Sign-up on RaceID · checked 21 Oct');
  assert.equal(R.signupLine(race('vasaloppet-2027'), TODAY), 'Sign-up on vasaloppet.se · checked 21 Oct');
  assert.equal(R.signupLine(race('vasaloppet-2027'), '2027-01-05'), 'Sign-up on vasaloppet.se · checked 21 Oct 2026');
});

test('labels: kind, place, distances, facts, host', () => {
  assert.equal(R.kindLabel(race('hyrox-stockholm-2026')), 'HYROX · Solna');
  assert.equal(R.kindLabel(race('vasaloppet-2027')), 'Ski · Klassiker');
  assert.equal(R.placeLine(race('hyrox-stockholm-2026')), 'Strawberry Arena | Solna');
  assert.equal(R.placeLine(race('vasaloppet-2027')), 'Sälen to Mora');
  assert.equal(R.placeLine(race('oslo-maraton-2027')), 'Oslo');
  assert.equal(R.factsLine(race('tough-viking-stadion-2027')), '8 km · solo, duo, trio or team');
  assert.equal(R.distanceText(race('bergen-city-marathon-2027')), '42.2 / 21.1 / 5 km');
  assert.equal(R.distanceText(race('stockholm-marathon-2027')), '42.195 km');
  assert.equal(R.distanceText(race('hyrox-stockholm-2026')), null);
  assert.equal(R.host('https://www.toughviking.se/'), 'toughviking.se');
  assert.equal(R.webURL('toughviking.se'), 'https://toughviking.se/');
  assert.equal(R.webURL('not a link'), null);
  assert.equal(R.webURL('localhost'), null);
});

// ---------------------------------------------------------------- lists

test('month groups and filters', () => {
  const groups = R.byMonth(CATALOG);
  assert.deepEqual(groups.map((g) => g.title), ['December 2026', 'March 2027', 'April 2027', 'May 2027', 'June 2027', 'July 2027', 'August 2027', 'September 2027']);
  assert.deepEqual(groups.map((g) => g.races.length), [1, 3, 2, 7, 3, 2, 9, 5]);
  const f = (o) => R.filterRaces(CATALOG, Object.assign({ today: TODAY }, o)).length;
  assert.equal(f({ types: ['hyrox'] }), 2);
  assert.equal(f({ types: ['obstacle'] }), 7);
  assert.equal(f({ countries: ['SE'] }), 19);
  assert.equal(f({ countries: ['NO', 'DK'] }), 13);
  assert.equal(f({ query: 'gothenburg' }), 4);
  assert.equal(f({ query: 'GOTEBORG' }), 4);
  assert.equal(f({ query: '21.1' }), 5);
  assert.equal(f({ query: 'klassiker' }), 4);
  assert.equal(f({ query: 'ski mora' }), 1);
  assert.equal(R.filterRaces(CATALOG, { today: '2027-01-10' }).length, 31);
  assert.equal(R.filterRaces(CATALOG, { today: '2027-01-10', includePast: true }).length, 32);
});

test('My races: resolve from the catalog or as saved, upcoming and done, hints', () => {
  const tv = race('tough-viking-stadion-2027');
  const mine = [R.fromRace(tv), { id: 'x1', raceId: null, name: 'Lidingö Ultra', date: '2027-04-10', city: 'Lidingö', type: 'running', note: '50 km' },
    Object.assign(R.fromRace(race('hyrox-stockholm-2026')), { day: '2026-12-12', note: 'Doubles Open' })];
  const list = R.entries(mine, CATALOG);
  const up = R.upcoming(list, TODAY);
  assert.deepEqual(up.map((e) => e.race.name), ['HYROX Stockholm', 'Lidingö Ultra', 'Tough Viking Stockholms Stadion']);
  assert.equal(R.whenLine(up[0]), 'Sat 12 Dec · Doubles Open');
  assert.equal(up[1].race.id, 'custom-x1');
  assert.ok(R.isCustom(up[1].race));
  assert.equal(R.statusText(up[1].race, TODAY), null);
  assert.equal(R.pillText(up[1].race, TODAY), '');
  assert.equal(R.hint(up[2], TODAY), '775 SEK from 1 Nov');
  assert.equal(R.keyOf(mine[0]), 'tough-viking-stadion-2027');
  assert.deepEqual(R.past(list, '2026-12-14').map((e) => e.race.name), ['HYROX Stockholm']);
  // A catalog race that left the catalog still shows what was saved.
  const gone = R.resolve(R.fromRace(tv), []);
  assert.equal(gone.name, tv.name);
  assert.equal(gone.checkedOn, '');
  assert.equal(R.hint({ mine: { raceId: 'midnattsloppet-stockholm-2027' }, race: race('midnattsloppet-stockholm-2027') }, TODAY), 'Sign-up opens 1 Nov');
  assert.equal(R.hint({ mine: {}, race: race('goteborgsvarvet-2027') }, TODAY), 'Sold out');
});

test('formats: per-format fees, the picked one in My races, start wave and arrival time', () => {
  const r = Object.assign({}, race('hyrox-stockholm-2026'), { arriveMinutesBefore: 90, formats: [
    { code: 'singles', title: 'Singles', teamSize: 1, priceSteps: [{ amount: 1530, currency: 'SEK' }], note: 'Open or Pro' },
    { code: 'doubles', title: 'Doubles', teamSize: 2, priceSteps: [{ amount: 1470, currency: 'SEK', per: 'person' }] },
    { code: 'relay', title: 'Relay', teamSize: 4 }] });
  assert.ok(R.hasFormats(r));
  assert.ok(!R.hasFormats(race('vasaloppet-2027')));
  assert.equal(R.formatOf(r, 'doubles').title, 'Doubles');
  assert.equal(R.formatOf(r, 'pro'), null);
  assert.equal(R.formatOf(r, null), null);
  assert.equal(R.priceText(R.currentStepFor(r, R.formatOf(r, 'doubles'), TODAY)), '1,470 SEK per person');
  assert.equal(R.priceText(R.currentStepFor(r, R.formatOf(r, 'singles'), TODAY)), '1,530 SEK');
  // A format without fees of its own shows the race's.
  assert.equal(R.priceText(R.currentStepFor(r, R.formatOf(r, 'relay'), TODAY)), 'From 1,470 SEK');
  assert.equal(R.priceText(R.currentStepFor(r, null, TODAY)), 'From 1,470 SEK');
  assert.equal(R.formatDetail(R.formatOf(r, 'singles')), 'Open or Pro');
  assert.equal(R.formatDetail(R.formatOf(r, 'doubles')), '2 people');
  assert.equal(R.formatDetail({ code: 'x', title: 'X', distanceKm: 15 }), '15 km');
  assert.equal(R.formatDetail({ code: 'x', title: 'X' }), null);
  // Start waves as typed.
  assert.equal(R.clockMinutes('14:20'), 860);
  assert.equal(R.clockNormalized('1420'), '14:20');
  assert.equal(R.clockNormalized('9.05'), '09:05');
  assert.equal(R.clockNormalized(' 7:30 '), '07:30');
  assert.equal(R.clockNormalized('wave 3'), null);
  assert.equal(R.clockNormalized('25:00'), null);
  assert.equal(R.clockNormalized('14:60'), null);
  assert.equal(R.clockNormalized(''), null);
  assert.equal(R.arriveBy('14:20', 90), '12:50');
  assert.equal(R.arriveBy('00:30', 90), '00:00');
  assert.equal(R.arriveBy('wave 3', 90), null);
  assert.equal(R.arriveMinutes(r), 90);
  assert.equal(R.arriveMinutes(race('vasaloppet-2027')), 60);
  const e = R.entries([Object.assign(R.fromRace(r), { day: '2026-12-12', format: 'doubles', note: 'Open', wave: '14:20' })], [r])[0];
  assert.equal(R.startText(e), 'Doubles · Open');
  assert.equal(R.whenLine(e), 'Sat 12 Dec · Doubles · Open');
  assert.equal(R.entryArriveBy(e), '12:50');
  assert.ok(R.isRaceDay(e, '2026-12-12'));
  assert.ok(!R.isRaceDay(e, '2026-12-11'));
  // A format the catalog dropped: the note alone; nothing picked: nothing.
  assert.equal(R.startText(R.entries([Object.assign(R.fromRace(r), { format: 'pro', note: 'Open' })], [r])[0]), 'Open');
  assert.equal(R.startText(R.entries([R.fromRace(r)], [r])[0]), null);
  // The published catalog has the HYROX Stockholm formats and the rules that matter.
  const pub = R.decode(FILE).find((x) => x.id === 'hyrox-stockholm-2026');
  assert.deepEqual(pub.formats.map((f) => f.code), ['singles', 'doubles', 'relay', 'adaptive']);
  assert.equal(pub.arriveMinutesBefore, 90);
  assert.match(pub.changeRule, /Flex/);
  assert.ok(R.decode(FILE).some((x) => x.id === 'premiarhalvan-2027'));
});

test('Home: Upcoming races (not in My races, open or opening, own country first) and the next price step pill', () => {
  const mine = [R.fromRace(race('hyrox-stockholm-2026'))];
  assert.deepEqual(R.upcomingOnHome(CATALOG, mine, TODAY, 'SE', 5).map((r) => r.id),
    ['vasaloppet-2027', 'tough-viking-goteborg-2027', 'tough-viking-stadion-2027', 'toughest-malmo-2027', 'toughest-stockholm-2027']);
  assert.deepEqual(R.upcomingOnHome(CATALOG, mine, TODAY, 'NO', 3).map((r) => r.id), ['birkebeinerrennet-2027', 'bergen-city-marathon-2027', 'holmenkollstafetten-2027']);
  assert.deepEqual(R.upcomingOnHome(CATALOG, [], TODAY, null, 4).map((r) => r.id), ['hyrox-stockholm-2026', 'vasaloppet-2027', 'birkebeinerrennet-2027', 'hyrox-copenhagen-2027']);
  // A country with no races: by date.
  assert.deepEqual(R.upcomingOnHome(CATALOG, mine, TODAY, 'FI', 3).map((r) => r.id), ['vasaloppet-2027', 'birkebeinerrennet-2027', 'hyrox-copenhagen-2027']);
  assert.equal(R.upcomingOnHome(CATALOG, [], TODAY).length, 8);
  assert.ok(R.upcomingOnHome(CATALOG, [], TODAY, null, 99).every((r) => r.status === 'open' || r.status === 'opensSoon'));
  assert.equal(R.upcomingOnHome(CATALOG, [], '2027-12-01').length, 0);
  assert.equal(R.homePill(race('tough-viking-stadion-2027'), TODAY), '750 → 775 SEK on 1 Nov');
  assert.equal(R.homePill(race('vasaloppet-2027'), TODAY), '2,685 → 2,985 SEK on 6 Nov');
  assert.equal(R.homePill(race('vatternrundan-2027'), TODAY), 'Opens 25 Nov');
  assert.equal(R.homePill(race('hyrox-stockholm-2026'), TODAY), 'From 1,470 SEK');
  assert.equal(R.homePill(race('bergen-city-marathon-2027'), TODAY), '900 NOK until 31 Jan');
});

test('a race as an all-day calendar event', () => {
  const hyrox = race('hyrox-stockholm-2026');
  const one = icsForRace(hyrox, { day: '2026-12-12', facts: null, url: hyrox.signupUrl, now: Date.parse('2026-10-21T10:00:00Z') });
  assert.match(one, /DTSTART;VALUE=DATE:20261212\r\n/);
  assert.match(one, /DTEND;VALUE=DATE:20261213\r\n/);
  assert.match(one, /TRIGGER:-PT360M/);
  assert.match(one, /UID:race-hyrox-stockholm-2026@bruce\.unofficial/);
  assert.match(one, /LOCATION:Strawberry Arena\\, Solna/);
  assert.match(one, /URL:https:\/\/hyrox\.com\/find-my-race\//);
  const all = icsForRace(hyrox, {});
  assert.match(all, /DTSTART;VALUE=DATE:20261210\r\n/);
  assert.match(all, /DTEND;VALUE=DATE:20261214\r\n/);
  // Month and year ends.
  assert.match(icsForRace({ id: 'x', name: 'X', date: '2026-12-31' }, {}), /DTEND;VALUE=DATE:20270101/);
});

// ---------------------------------------------------------------- scripts/check-races.mjs (pure parts only)

test('link check: robots.txt rules for our user agent', () => {
  const txt = 'User-agent: *\nDisallow: /api/\nAllow: /api/public\nCrawl-delay: 2\n\nUser-agent: GPTBot\nDisallow: /\n';
  assert.deepEqual(robotsVerdict(txt, 'BruceRaceCheck', '/en/races/'), { allowed: true, delay: 2 });
  assert.equal(robotsVerdict(txt, 'BruceRaceCheck', '/api/x').allowed, false);
  assert.equal(robotsVerdict(txt, 'BruceRaceCheck', '/api/public/x').allowed, true);
  assert.equal(robotsVerdict('User-agent: BruceRaceCheck\nDisallow: /\n\nUser-agent: *\nAllow: /\n', 'BruceRaceCheck', '/').allowed, false);
  assert.equal(robotsVerdict('User-agent: *\nDisallow: /*.pdf$\n', 'BruceRaceCheck', '/fees.pdf').allowed, false);
  assert.equal(robotsVerdict('User-agent: *\nDisallow: /*.pdf$\n', 'BruceRaceCheck', '/fees.pdf?x=1').allowed, true);
  assert.equal(robotsVerdict('User-agent: *\nDisallow:\n', 'BruceRaceCheck', '/anything').allowed, true);
  assert.equal(robotsVerdict('', 'BruceRaceCheck', '/').allowed, true);
  assert.equal(robotsVerdict('User-agent: *\nCrawl-delay: 2000\n', 'BruceRaceCheck', '/').delay, 2000);
  assert.equal(parseRobots('User-agent: a\nUser-agent: b\nDisallow: /x\n')[0].agents.length, 2);
});

test('link check: never fetches registration platforms', () => {
  ['secure.onreg.com', 'vivenu.com', 'www.raceid.com', 'my.raceresult.com', 'signup.eqtiming.com', 'www.sportstiming.dk'].forEach((h) => assert.ok(isPlatformHost(h), h));
  ['www.toughviking.se', 'hyrox.com', 'vasaloppet.se', 'notvivenu.com'].forEach((h) => assert.ok(!isPlatformHost(h), h));
  for (const r of FILE.races) assert.ok(!isPlatformHost(new URL(r.signupUrl).hostname), r.id + ' links to the race, not a platform');
});

test('link check: finds the race date in a page in English, Swedish, Norwegian or Danish', () => {
  const tv = race('tough-viking-stadion-2027');
  assert.ok(datePatterns('2027-05-15').includes('15 maj 2027'));
  assert.ok(datePatterns('2027-05-15').includes('15. mai'));
  assert.ok(dateSeen('<p>Lördag 15 maj 2027, Stockholms Stadion</p>', tv));
  assert.ok(dateSeen('<h2>May 15, 2027</h2>', tv));
  assert.ok(dateSeen('<p>15.05.2027</p>', tv));
  assert.ok(dateSeen('<script type="application/ld+json">{"startDate":"2027-05-15"}</script>', tv));
  assert.ok(!dateSeen('<p>Lördag 16 maj 2027</p>', tv));
  assert.ok(!dateSeen('<p>115 maj</p>', tv));
  assert.ok(dateSeen('<p>10–13 december</p>', race('hyrox-stockholm-2026')), 'the last day of an event counts');
});
