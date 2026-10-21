// Train for it: js/raceplan.js against the same cases as Shared/BruceCore/RacePlanner.swift (RacePlannerTests):
// phases from the race date, the class mix per race type, the grid with the member's changes, monthly targets,
// filling this week's slots, suggestions and the category mapping. Run from the repo root:  node --test docs/app/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as P from '../js/raceplan.js';
import { DEMO_MY_RACES, DEMO_RACES } from '../js/demo.js';

const TODAY = '2026-10-21';   // Wednesday, W43
const hyrox = (o) => P.makePlan('2026-12-12', 'hyrox', null, P.newSettings((o && o.startedOn) || '2026-10-05', o));

test('phases from the block length: Base, Build, Peak, race week, recovery; under six weeks no Base', () => {
  assert.deepEqual(P.phases(10), ['base', 'base', 'base', 'base', 'build', 'build', 'build', 'peak', 'peak', 'race', 'recovery']);
  assert.deepEqual(P.phases(7), ['base', 'base', 'build', 'build', 'peak', 'peak', 'race', 'recovery']);
  assert.deepEqual(P.phases(6), ['build', 'build', 'build', 'peak', 'peak', 'race', 'recovery']);
  assert.deepEqual(P.phases(3), ['build', 'peak', 'race', 'recovery']);
  assert.deepEqual(P.phases(2), ['peak', 'race', 'recovery']);
  assert.deepEqual(P.phases(1), ['race', 'recovery']);
  assert.equal(P.phases(16).filter((p) => p === 'base').length, 8);
});

test('the HYROX 10-week plan of the report', () => {
  const plan = hyrox();
  assert.deepEqual(plan.weeks.map((w) => w.label), ['W41', 'W42', 'W43', 'W44', 'W45', 'W46', 'W47', 'W48', 'W49', 'W50', 'W51']);
  assert.equal(plan.raceWeek.monday, '2026-12-07');
  assert.equal(plan.blockWeeks, 10);
  assert.deepEqual(plan.rows, ['hyrox', 'strength', 'running', 'mobility', 'highIntensity', 'sauna']);
  assert.deepEqual(P.segments(plan), [{ phase: 'base', weeks: 4 }, { phase: 'build', weeks: 3 }, { phase: 'peak', weeks: 2 }, { phase: 'race', weeks: 1 }]);
  const row = (k) => plan.weeks.map((w) => P.count(w, k));
  assert.deepEqual(row('hyrox'), [1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 0]);
  assert.deepEqual(row('strength'), [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0]);
  assert.deepEqual(row('mobility'), [1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1]);
  assert.deepEqual(row('sauna'), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
  assert.deepEqual(plan.weeks.map((w) => w.total), [4, 4, 4, 4, 4, 4, 4, 4, 4, 2, 2]);
  const five = hyrox({ perWeek: 5 });
  assert.equal(P.count(five.weeks[0], 'strength'), 2);
  assert.equal(P.count(five.weeks[4], 'highIntensity'), 1);
  assert.equal(five.weeks[9].total, 2);
});

test('headline and status over the block', () => {
  const plan = hyrox();
  assert.equal(P.headline(plan, TODAY), 'Week 3 of 10 · Base');
  assert.equal(P.headline(plan, '2026-11-10'), 'Week 6 of 10 · Build');
  assert.equal(P.headline(plan, '2026-12-08'), 'Week 10 of 10 · Race week');
  assert.equal(P.headline(plan, '2026-12-15'), 'Recovery week');
  assert.equal(P.headline(plan, '2026-12-21'), 'Plan done');
  assert.equal(P.isRunning(plan, '2026-12-21'), false);
  const early = hyrox({ startedOn: '2026-06-01' });
  assert.equal(early.weeks[0].monday, '2026-10-05');
  assert.equal(P.headline(early, '2026-09-01'), 'Starts Mon 5 Oct');
});

test('short lead times degrade: no Base, then race week only', () => {
  const late = hyrox({ startedOn: '2026-11-04' });
  assert.equal(late.blockWeeks, 6);
  assert.deepEqual(late.weeks.map((w) => w.phase), ['build', 'build', 'build', 'peak', 'peak', 'race', 'recovery']);
  assert.equal(P.headline(late, '2026-11-04'), 'Week 1 of 6 · Build');
  assert.deepEqual(hyrox({ startedOn: '2026-12-09' }).weeks.map((w) => w.phase), ['race', 'recovery']);
  const four = hyrox({ weeks: 4, perWeek: 3 });
  assert.equal(four.weeks[0].label, 'W47');
  assert.deepEqual(four.weeks.map((w) => w.phase), ['build', 'build', 'peak', 'race', 'recovery']);
  assert.equal(four.weeks[0].total, 3);
});

test('the member changes a week', () => {
  const plan = hyrox({ edits: { '2026-10-19|hyrox': 2, '2026-10-19|mobility': 0, '2026-11-30|sauna': 3 } });
  const w43 = plan.weeks[2];
  assert.equal(P.count(w43, 'hyrox'), 2);
  assert.equal(P.count(w43, 'mobility'), 0);
  assert.deepEqual(w43.edited, ['hyrox', 'mobility']);
  assert.equal(w43.total, 4);
  assert.equal(P.count(plan.weeks[8], 'sauna'), 3);
  assert.equal(P.mixText(plan.raceWeek, plan.rows), '1 Hyrox and 1 Mobility');
  assert.equal(P.mixText(plan.weeks[4], plan.rows), '2 Hyrox, 1 Strength and 1 Running');
});

test('monthly targets: a week counts for the month of its Thursday', () => {
  const plan = hyrox();
  const t = (m) => P.monthTargets(plan, m).map((x) => x.category + ' ' + x.count);
  assert.deepEqual(t('2026-10'), ['hyrox 4', 'strength 4', 'running 4', 'mobility 4']);
  assert.deepEqual(t('2026-11'), ['hyrox 8', 'strength 4', 'running 4']);
  assert.deepEqual(t('2026-12'), ['hyrox 3', 'strength 1', 'running 1', 'mobility 2', 'sauna 1']);
  assert.deepEqual(t('2027-01'), []);
});

test('this week: check-ins, then bookings, fill the slots', () => {
  const plan = hyrox();
  const it = (kind, day, categories, title) => ({ kind, classId: null, title, studioId: null, at: '2026-10-' + day + 'T16:00:00Z', categories });
  const st = P.assign(plan.weeks[2], plan.rows, [it('booked', 22, ['hyrox', 'highIntensity'], 'Hyrox'), it('done', 19, ['strength'], 'Strength'),
    it('done', 20, ['running', 'outdoor'], 'Run Club'), it('autoBook', 25, ['mobility'], 'Mobility'), it('done', 21, ['strength'], 'Strength Circuit'),
    it('done', 21, [], 'Solo training')]);
  assert.deepEqual(st.slots.map((s) => s.category), ['hyrox', 'strength', 'running', 'mobility']);
  assert.deepEqual(st.slots.map(P.slotState), ['booked', 'done', 'done', 'autoBook']);
  assert.equal(P.progressText(st), '2 of 4 this week');
  assert.deepEqual(st.extra.map((x) => x.title), ['Strength Circuit'], 'a drop-in outside the mix is left out');
  const two = P.assign(plan.weeks[4], plan.rows, [it('done', 3, ['strength', 'hyrox'], 'Hyrox Strength')]);
  assert.equal(two.slots.find((s) => s.item).category, 'hyrox');
});

test('suggestions: one class per open slot this week, not full, free to cancel first', () => {
  const plan = hyrox();
  const open = P.assign(plan.weeks[2], plan.rows, []);
  const c = (id, studio, title, start, spots, cat) => ({ id, studio_id: studio, title, start_time: start, end_time: start, available_spots: spots, class_categories: [{ category_id: cat }] });
  const classes = [c(1, 9810, 'Hyrox', '2026-10-22T16:00:00Z', 7, 13), c(2, 9810, 'Hyrox', '2026-10-27T16:00:00Z', 7, 13),
    c(3, 1724, 'Strength', '2026-10-23T05:30:00Z', 0, 26), c(4, 1724, 'Strength', '2026-10-23T16:30:00Z', 4, 26), c(5, 1489, 'Mobility', '2026-10-25T15:00:00Z', 9, 16)];
  const now = Date.parse('2026-10-21T10:00:00Z');
  const ids = P.categoryIds([]);
  const input = { now, notAfter: Date.parse('2026-10-25T23:00:00Z'), classes, ids };
  const st = P.suggest(open, input);
  assert.deepEqual(st.slots.map((s) => s.suggestion && s.suggestion.class.id), [1, 4, null, 5]);
  assert.deepEqual(st.slots.map(P.slotState), ['suggested', 'suggested', 'open', 'suggested']);
  assert.equal(P.nextToBook(st).class.id, 1);
  assert.equal(st.slots[0].suggestion.fewSpots, 7);
  assert.equal(st.slots[0].suggestion.strike, false);
  assert.equal(P.suggest(open, Object.assign({}, input, { allowed: (x) => x.studio_id !== 9810 })).slots[0].suggestion, null);
  assert.equal(P.suggest(open, Object.assign({}, input, { now: Date.parse('2026-10-22T09:00:00Z') })).slots[0].suggestion.strike, true);
});

test('category mapping: ids of the demo data, title fallback, guesses from class titles', () => {
  const demo = [[2, 'Yoga'], [6, 'Cardio'], [7, 'Climbing'], [8, 'CrossFit'], [9, 'Cycling'], [12, 'High-intensity'], [13, 'Hyrox'], [15, 'Massage & Naprapathy'],
    [16, 'Mobility'], [18, 'Outdoor'], [23, 'Running'], [24, 'Sauna'], [26, 'Strength'], [27, 'Swimming']].map(([id, title]) => ({ id, title }));
  for (const c of P.CATEGORIES) assert.equal(P.resolveCategory(c.key, demo), c.id, c.key);
  assert.equal(P.resolveCategory('swimming', [{ id: 30, title: 'Swimming' }, { id: 27, title: 'Other' }]), 30, 'the web demo has Swimming as 30');
  assert.equal(P.resolveCategory('hyrox', [{ id: 13, title: 'Other' }, { id: 1, title: 'Gym' }]), null);
  assert.equal(P.resolveCategory('hyrox', [{ id: 1, title: 'Gym' }]), 13);
  assert.equal(P.resolveCategory('highIntensity', [{ id: 40, title: 'High Intensity' }]), 40);
  assert.equal(P.resolveCategory('hyrox', [{ id: 41, title: 'Functional', code: 'HYROX' }]), 41);
  assert.deepEqual(P.keysOf(['13', 26], P.categoryIds([])), ['hyrox', 'strength']);
  assert.equal(P.guess('Hyrox Prep'), 'hyrox');
  assert.equal(P.guess('Strength Circuit'), 'strength');
  assert.equal(P.guess('Run Club'), 'running');
  assert.equal(P.guess('High Intensity'), 'highIntensity');
  assert.equal(P.guess('Morning Flow'), null);
  assert.equal(P.guess('Brunch Ride'), null);
});

test('the mix per race type: endurance weighted to the sport, race week light', () => {
  assert.equal(P.template('endurance', 'ski').base[0], 'cardio');
  assert.deepEqual(P.template('endurance', 'bike').build.slice(0, 2), ['cycling', 'cycling']);
  assert.deepEqual(P.template('endurance', 'swim').peak.slice(0, 2), ['swimming', 'swimming']);
  assert.deepEqual(P.template('endurance', 'swim').race, ['swimming', 'mobility']);
  assert.deepEqual(new Set(P.template('triathlon').base.slice(0, 4)), new Set(['swimming', 'cycling', 'running', 'strength']));
  assert.deepEqual(P.template('running').race, ['mobility']);
  assert.equal(P.template('running').recovery[0], 'massage');
  assert.deepEqual(P.template('obstacle').race, ['climbing', 'mobility']);
  for (const t of ['running', 'hyrox', 'obstacle', 'endurance', 'triathlon']) assert.ok(P.template(t).base.length >= 6, t);
});

test('monthly goals from the plan follow it, skip yours and deleted ones, and go with it', () => {
  const plan = hyrox();
  const ids = P.categoryIds([]);
  const mine = { id: 'own', category: '26', target: 6, studioId: null, remind: false };
  const oct = { key: 'hyrox-stockholm-2026', targets: P.monthTargets(plan, '2026-10') };
  let g = P.planGoals([mine], [oct], ids);
  assert.deepEqual(g.map((x) => x.category + ' ' + x.target + ' ' + (x.raceKey || 'own')),
    ['26 6 own', '13 4 hyrox-stockholm-2026', '23 4 hyrox-stockholm-2026', '16 4 hyrox-stockholm-2026']);
  assert.ok(g.filter((x) => x.raceKey).every((x) => x.remind));
  g = P.planGoals(g, [{ key: oct.key, targets: P.monthTargets(plan, '2026-11') }], ids);
  assert.deepEqual(g.filter((x) => x.raceKey).map((x) => x.category + ' ' + x.target), ['13 8', '23 4']);
  assert.deepEqual(P.planGoals(g, [{ key: oct.key, targets: P.monthTargets(plan, '2026-12') }], ids).filter((x) => x.raceKey).map((x) => x.category), ['13', '23', '16']);
  assert.ok(!P.planGoals([mine], [Object.assign({ skip: ['23'] }, oct)], ids).some((x) => x.category === '23'));
  assert.deepEqual(P.planGoals(g, [], ids), [mine]);
});

test('the demo has a plan in week 3 of 10 on 21 October 2026', () => {
  const m = DEMO_MY_RACES.find((x) => x.raceId === 'hyrox-stockholm-2026');
  const r = DEMO_RACES.find((x) => x.id === m.raceId);
  assert.ok(m.plan && m.remindWeek && m.remindEve);
  const plan = P.makePlan(m.day, r.type, r.sport, m.plan);
  assert.equal(P.headline(plan, TODAY), 'Week 3 of 10 · Base');
});
