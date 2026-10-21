// Train for it on the web (raceplan.js; RacePlanViews.swift on iPhone): the plan sheet with its phase strip and weeks ×
// categories grid, the week strip on My races, "This week" with Done, Booked and Book, and the week line with the next
// class on Home's Next race card. It is a class mix, not coaching: every week can be changed. The web has no weekly
// auto-book, so there is no Book every week here (the iPhone and Mac apps have it).
import { esc, icon, todayKey, dayKey, time, fmt, getZone } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import * as R from './races.js';
import * as P from './raceplan.js';
import { sheet, toast, confirmSheet } from './ui.js';
import { recommend } from './recommend.js';
import { openRules } from './sheets.js';
import { Bruce } from './api.js';
import { ex, areas, selectedArea, studioInArea } from './filters.js';

export const INTRO = 'A weekly mix of Bruce classes for the weeks up to race day: Base, Build, Peak, race week, then a week to recover. Brüce picks classes near you; it books only when you tap.';
export const NOT_COACHING = "This is a class mix, not a training programme. It doesn't plan your long runs, rides or swims, and you can change any week.";
const GOALS_HINT = "This month's planned classes as Monthly goals, with a reminder when you fall behind. The targets follow the plan each month and go when it ends; a goal you delete stays deleted.";
const GLYPH = { hyrox: 'dumbbell', strength: 'dumbbell', highIntensity: 'flame', crossfit: 'dumbbell', running: 'run', climbing: 'flag', outdoor: 'sun',
  cycling: 'bike', swimming: 'swim', cardio: 'heart', mobility: 'yoga', yoga: 'yoga', massage: 'spa', sauna: 'spa' };

// ---------------------------------------------------------------- state

const key = (e) => R.keyOf(e.mine);
export const planOf = (e) => (e && e.mine.plan ? P.makePlan(e.day, e.race.type, e.race.sport, e.mine.plan) : null);
const entries = () => R.entries(St.myRaces(), S.races || []);
export const entryFor = (k) => entries().find((e) => key(e) === k) || null;
/** The soonest race whose plan is still running, a block week before a recovery week. */
export function activePlan() {
  const today = todayKey();
  const running = entries().sort((a, b) => (a.day < b.day ? -1 : 1)).map((e) => ({ e, plan: planOf(e) })).filter((x) => x.plan && P.isRunning(x.plan, today));
  return running.find((x) => { const s = P.status(x.plan, today); return s.kind !== 'active' || s.week.phase !== 'recovery'; }) || running[0] || null;
}
function updatePlan(k, change) {
  St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === k && m.plan ? Object.assign({}, m, { plan: change(Object.assign({}, m.plan, { edits: Object.assign({}, m.plan.edits) })) }) : m)));
  refreshPlanGoals();
}
export function startPlan(r, o) {
  let list = St.myRaces();
  if (!list.some((m) => R.keyOf(m) === r.id)) list = list.concat(R.fromRace(r));
  list = list.map((m) => (R.keyOf(m) === r.id ? Object.assign({}, m, { plan: P.newSettings(todayKey(), o) }) : m));
  St.saveMyRaces(list);
  toast('Plan started');
}
export function stopPlan(k) {
  St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === k ? Object.assign({}, m, { plan: null }) : m)));
  refreshPlanGoals();
  toast('Plan stopped. The race stays in My races.');
}

// ---------------------------------------------------------------- monthly goals from the plan (goals.js)

/** Monthly goals from a plan on or off (off removes them). */
export function setPlanGoals(k, on) {
  St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === k && m.plan ? Object.assign({}, m, { plan: Object.assign({}, m.plan, { goals: on, goalsSkip: [] }) }) : m)));
  refreshPlanGoals();
  if (on) toast(St.goals().some((g) => g.raceKey === k) ? 'Monthly goals made from your plan' : 'No classes planned this month');
}
/** Goals made from plans follow them each month and go with them (raceplan.js planGoals). */
export function refreshPlanGoals() {
  const today = todayKey();
  const plans = entries().sort((a, b) => (a.day < b.day ? -1 : 1)).map((e) => ({ e, plan: planOf(e) }))
    .filter((x) => x.plan && x.e.mine.plan.goals && P.isRunning(x.plan, today))
    .map((x) => ({ key: key(x.e), targets: P.monthTargets(x.plan, today.slice(0, 7)), skip: x.e.mine.plan.goalsSkip || [] }));
  const goals = St.goals();
  if (!plans.length && !goals.some((g) => g.raceKey)) return;
  const next = P.planGoals(goals, plans, P.categoryIds(S.categories), () => 'g-' + R.newId());
  if (JSON.stringify(next) !== JSON.stringify(goals)) St.saveGoals(next);
}

// ---------------------------------------------------------------- this week

const tried = new Set();
/** Loads the history and the city schedule for the rest of the plan's week once (a failed read is not retried until
 *  the page reloads, so a failing server is not asked again on every redraw), then the views redraw. */
function ensureWeek(plan) {
  const s = P.status(plan, todayKey());
  if (s.kind !== 'active') return;
  const days = [];
  for (let d = todayKey(); d <= s.week.sunday; d = R.addDay(d, 1)) days.push(d);
  const want = days.filter((d) => !tried.has(S.settings.cityId + ':' + d));
  const history = !S.history && !tried.has('history');
  if (!want.length && !history) return;
  want.forEach((d) => tried.add(S.settings.cityId + ':' + d));
  tried.add('history');
  Promise.all([history ? St.loadHistory().catch(() => null) : null, St.loadStudios().catch(() => {}), ...want.map((d) => St.dayClasses(d).catch(() => null))])
    .then((got) => { if (got.some((x) => x != null)) St.emit(); });
}

function tier() { return ((S.membership && (S.membership.membership_tier || S.membership.admission_tier)) || 'BASE').toUpperCase(); }
/** Category keys of a studio's main category (a drop-in counts there). */
function studioKeys(studioId) {
  const s = St.studio(studioId);
  const main = s && s.cats && s.cats[0];
  return main ? P.CATEGORIES.filter((c) => P.namesCategory(c.key, main)).map((c) => c.key) : [];
}

/** The plan's week now: check-ins, bookings and a class for each open slot. null outside the plan's weeks. */
export function weekStatus(e, plan) {
  const today = todayKey();
  const s = P.status(plan, today);
  if (s.kind !== 'active') return null;
  const w = s.week, ids = P.categoryIds(S.categories), now = Date.now();
  const items = [];
  const seen = new Set();
  for (const v of St.visitList(true)) {
    if (v.day < w.monday || v.day > w.sunday || Date.parse(v.at) > now) continue;
    if (v.classId) seen.add(v.classId);
    items.push({ kind: 'done', classId: v.classId, title: v.title, studioId: v.studioId, at: v.at,
      categories: v.kind === 'class' ? P.keysOf(v.categories, ids) : studioKeys(v.studioId) });
  }
  for (const b of S.bookings.values()) {
    const c = b.class;
    if (!c || !c.start_time || seen.has(c.id)) continue;
    const d = dayKey(c.start_time);
    if (d < w.monday || d > w.sunday) continue;
    seen.add(c.id);
    items.push({ kind: b.checked_in_at ? 'done' : 'booked', classId: c.id, title: c.title, studioId: c.studio_id, at: c.start_time,
      categories: P.keysOf((c.class_categories || []).map((x) => x.category_id), ids) });
  }
  const st = P.assign(w, plan.rows, items);
  // This week's days still ahead; in race week until the day before race day, in the recovery week after it.
  const first = w.phase === 'recovery' ? R.addDay(plan.raceDay, 1) : w.monday;
  const last = w.phase === 'race' ? R.addDay(plan.raceDay, -1) : w.sunday;
  const classes = [];
  for (let d = first > today ? first : today; d <= last; d = R.addDay(d, 1)) classes.push(...(((S.classCache.get(S.settings.cityId + ':' + d) || {}).classes) || []));
  const area = selectedArea(areas, ex.areaId, S.settings.cityId);
  const p = St.placesState();
  const studios = new Map([...S.studios.values()].map((x) => [x.id, { lat: x.lat, lon: x.lon, name: x.name }]));
  const friends = S.friendsBookings.map((b) => ({ userId: b.user_id, classId: b.class_id, name: (St.friendUser(b.user_id) || {}).first_name }));
  const visits = St.visitList(false);
  return P.suggest(st, {
    now, notAfter: Infinity, classes: classes.filter((c) => !seen.has(c.id) && !S.bookings.has(c.id) && !S.standbys.has(c.id)), ids,
    dayOf: (c) => dayKey(c.start_time),
    busyDays: new Set(st.slots.filter((x) => x.item).map((x) => dayKey(x.item.at))),
    allowed: (c) => {
      const studio = St.studio(c.studio_id);
      if (c.user_attendance_info && c.user_attendance_info.visit_limit_reached) return false;
      const lim = studio && (studio.limits || []).find((x) => (x.label || '').toUpperCase() === tier());
      if (lim && lim.limit === -1) return false;
      return studioInArea(studio, area);
    },
    rank: (pool) => recommend({ classes: pool, visits, now, zone: getZone(), booked: new Set(S.bookings.keys()), friends, studios, catTitle: St.catTitle,
      places: p.places, prefs: p, hours: 24 * 8, limit: 40 }),
  });
}

// ---------------------------------------------------------------- building blocks

/** One bar per week of the block, past weeks full, this week lime, the phase names under. */
export function stripHTML(plan, light) {
  const today = todayKey();
  const s = P.status(plan, today);
  const block = plan.weeks.filter((w) => w.phase !== 'recovery');
  let i = 0;
  const groups = P.segments(plan).map((g) => { const weeks = block.slice(i, i + g.weeks); i += g.weeks; return { phase: g.phase, weeks }; });
  const bar = (w) => '<i class="' + (s.week && w.index === s.week.index ? 'now' : (s.week ? w.index < s.week.index : s.kind === 'done') ? 'past' : '') + '"></i>';
  return '<div class="plan-strip' + (light ? ' light' : '') + '" role="img" aria-label="' + esc(P.segments(plan).map((g) => P.PHASES[g.phase].title + ' ' + g.weeks + (g.weeks === 1 ? ' week' : ' weeks')).join(', ') + '. ' + P.headline(plan, today)) + '">' +
    '<div class="plan-phases">' + groups.map((g) => '<div style="flex:' + g.weeks.length + '"><span>' + g.weeks.map(bar).join('') + '</span><small>' + esc(P.PHASES[g.phase].short) + '</small></div>').join('') + '</div>' +
    '<div class="plan-ends"><small>' + esc(block[0].label) + '</small><small>' + esc(block[block.length - 1].label) + '</small></div></div>';
}

/** The weeks × categories table; with `editable` a click on a number (this week and later) steps it. */
export function gridHTML(plan, editable) {
  const today = todayKey();
  const s = P.status(plan, today);
  const rows = plan.rows.filter((k) => plan.weeks.some((w) => P.count(w, k) > 0));
  const head = '<tr><th></th>' + plan.weeks.map((w, i) => '<th class="' + (s.week && s.week.index === w.index ? 'now' : '') + '"><small>' +
    (i === 0 || plan.weeks[i - 1].phase !== w.phase ? esc(P.PHASES[w.phase].short) : '&nbsp;') + '</small>' + esc(w.label) + '</th>').join('') + '</tr>';
  const body = rows.map((k) => '<tr><th scope="row">' + esc(P.category(k).short) + '</th>' + plan.weeks.map((w) => {
    const n = P.count(w, k), past = w.sunday < today;
    const cls = [s.week && s.week.index === w.index ? 'now' : '', past ? 'past' : '', w.edited.includes(k) ? 'edited' : '', n ? 'n' + Math.min(n, 3) : ''].filter(Boolean).join(' ');
    const label = esc(w.label + ', ' + P.category(k).title + ': ' + n);
    return '<td class="' + cls + '">' + (editable && !past ? '<button data-plan-cell="' + w.monday + '|' + k + '" aria-label="' + label + '">' + (n || '–') + '</button>' : '<span aria-label="' + label + '">' + (n || '–') + '</span>') + '</td>';
  }).join('') + '</tr>').join('');
  const total = '<tr class="total"><th scope="row">Total</th>' + plan.weeks.map((w) => '<td class="' + (s.week && s.week.index === w.index ? 'now' : '') + (w.sunday < today ? ' past' : '') + '">' + w.total + '</td>').join('') + '</tr>';
  return '<div class="plan-grid"><table>' + head + body + total + '</table></div>';
}

function slotDetail(slot) {
  if (slot.item) {
    const when = slot.item.kind === 'done' ? fmt(slot.item.at, { weekday: 'short', day: 'numeric', month: 'short' }) : fmt(slot.item.at, { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + time(slot.item.at);
    return [when, slot.item.studioId ? St.studioName(slot.item.studioId) : null].filter(Boolean).join(' · ');
  }
  const g = slot.suggestion;
  if (g) return [fmt(g.class.start_time, { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + time(g.class.start_time), St.studioName(g.class.studio_id, g.class.studio),
    g.fewSpots ? g.fewSpots + (g.fewSpots === 1 ? ' spot left' : ' spots left') : null].filter(Boolean).join(' · ');
  return 'Nothing near you this week';
}
function slotRow(slot) {
  const st = P.slotState(slot), g = slot.suggestion;
  const right = st === 'done' ? '<span class="lime-ink">' + icon('check') + ' Done</span>'
    : st === 'booked' ? '<span class="muted">Booked</span>'
      : st === 'autoBook' ? '<span class="muted">Auto-book</span>'
        : st === 'suggested' ? '<button class="btn lime sm" data-plan-book="' + g.class.id + '">Book</button>'
          : '<button class="btn glass sm" data-plan-find="' + slot.category + '">Find</button>';
  return '<div class="trow plan-slot"><span class="plan-ic' + (st === 'done' ? ' on' : '') + '">' + icon(GLYPH[slot.category] || 'dumbbell') + '</span>' +
    '<span class="grow"><b>' + esc(P.category(slot.category).title) + '</b><p class="muted">' + esc(slotDetail(slot)) + '</p>' +
    (g && g.strike ? '<p class="small warn">Cancelling costs a strike</p>' : '') + '</span>' + right + '</div>';
}

/** My classes › Races: "This week · W43  2 of 4" of the running plan. */
export function weekSectionHTML() {
  const a = activePlan();
  if (!a) return '';
  ensureWeek(a.plan);
  const st = weekStatus(a.e, a.plan);
  if (!st) return '';
  return '<div class="sec-row"><h2 class="sec-title">This week · ' + esc(st.week.label) + '</h2><small class="muted">' + P.doneCount(st) + ' of ' + st.slots.length + '</small></div>' +
    (st.slots.length ? '<div class="list card flush">' + st.slots.map(slotRow).join('') + '</div>' : '<p class="muted">Nothing planned this week.</p>') +
    (st.extra.length ? '<p class="muted small">Also this week: ' + esc(st.extra.map((x) => x.title).join(', ')) + '</p>' : '') +
    '<p class="muted small note">' + esc(NOT_COACHING) + '</p>';
}

/** The race banner's plan part: the strip and "Week 3 of 10 · Base". */
export function bannerPlanHTML(e) {
  const plan = planOf(e);
  if (!plan || !P.isRunning(plan, todayKey())) return '';
  return stripHTML(plan) + '<span class="plan-line">' + esc(P.headline(plan, todayKey())) + '</span>';
}

/** Home's Next race card: the week line inside the card; `after` the next class to book, under it. */
export function homePlan(e) {
  const plan = planOf(e);
  if (!plan || !P.isRunning(plan, todayKey())) return null;
  ensureWeek(plan);
  const st = weekStatus(e, plan);
  const line = '<span class="plan-home"><span class="row-between"><b>' + esc(P.headline(plan, todayKey())) + '</b>' + (st ? '<b>' + esc(P.progressText(st)) + '</b>' : '') + '</span>' +
    (st && st.slots.length ? '<span class="plan-dots">' + st.slots.map((s) => '<i class="' + P.slotState(s) + '"></i>').join('') + '</span>' : '') + '</span>';
  const g = st && P.nextToBook(st);
  const after = g ? '<div class="card plan-next"><span class="plan-ic">' + icon(GLYPH[g.category] || 'dumbbell') + '</span><span class="grow"><b>' + esc(P.category(g.category).title + ' · ' +
    fmt(g.class.start_time, { weekday: 'short' }) + ' ' + time(g.class.start_time)) + '</b><p class="muted">' + esc([St.studioName(g.class.studio_id, g.class.studio),
    g.fewSpots ? g.fewSpots + ' spots left' : null].filter(Boolean).join(' · ')) + '</p></span><button class="btn lime sm" data-plan-book="' + g.class.id + '">Book</button></div>' : '';
  return { line, after };
}

/** Under the next race without a plan. */
export const promptHTML = (k) => '<button class="card plan-prompt" data-plan-open="' + esc(k) + '"><span class="plan-ic on">' + icon('run') + '</span><span class="grow"><b>Train for it</b>' +
  '<p class="muted small">A weekly class mix up to race day, booked when you tap</p></span>' + icon('chevron') + '</button>';

/** Race page: where the block stands; opens the plan. */
export function raceCardHTML(k) {
  const e = entryFor(k), plan = planOf(e);
  if (!plan) return '';
  const st = weekStatus(e, plan);
  return '<button class="card plan-card" data-plan-open="' + esc(k) + '"><span class="row-between"><b>' + icon('run') + ' Train for it · ' + esc(P.headline(plan, todayKey())) + '</b>' +
    (st ? '<small class="muted">' + esc(P.progressText(st)) + '</small>' : '') + '</span>' + stripHTML(plan, true) + '</button>';
}

// ---------------------------------------------------------------- clicks (Home, My classes, the race page)

function findClass(id) {
  if (S.classDetails.has(id)) return S.classDetails.get(id);
  for (const c of S.classCache.values()) { const x = (c.classes || []).find((y) => y.id === id); if (x) return x; }
  return null;
}
/** Handles the plan's buttons; true when the click was one. */
export function planClick(e) {
  const open = e.target.closest('[data-plan-open]');
  if (open) { e.preventDefault(); openPlanSheet(open.dataset.planOpen); return true; }
  const book = e.target.closest('[data-plan-book]');
  if (book) {
    e.preventDefault();
    const c = findClass(+book.dataset.planBook);
    if (c) openRules(c, 'book', async () => { await Bruce.book(c.id); toast('Booked ' + c.title); await St.loadMine(); });
    return true;
  }
  const find = e.target.closest('[data-plan-find]');
  if (find) {
    e.preventDefault();
    const id = P.categoryIds(S.categories)[find.dataset.planFind];
    location.hash = '#/explore?tab=classes' + (id != null ? '&cat=' + id : '');
    return true;
  }
  return false;
}

// ---------------------------------------------------------------- the plan sheet

export function openPlanSheet(k) {
  const s = sheet('Train for it', '<div id="plan-body"></div>', { cls: 'tall' });
  const body = s.body.querySelector('#plan-body');
  const draft = { perWeek: P.PER_WEEK.default, weeks: P.WEEKS.default };
  const stepper = (label, sub, name, v, min, max) => '<div class="frow plan-step"><span class="grow"><b>' + esc(label) + '</b><small class="muted">' + esc(sub) + '</small></span>' +
    '<button class="glass-btn sm" data-step="' + name + '" data-d="-1" aria-label="Fewer"' + (v <= min ? ' disabled' : '') + '>−</button>' +
    '<button class="glass-btn sm" data-step="' + name + '" data-d="1" aria-label="More"' + (v >= max ? ' disabled' : '') + '>+</button></div>';
  const settingsCard = (st, blockWeeks) => '<div class="card form-rows">' +
    stepper(st.perWeek + ' classes a week', 'In Base, Build and Peak. Race week has fewer.', 'perWeek', st.perWeek, P.PER_WEEK.min, P.PER_WEEK.max) +
    stepper(st.weeks + ' week block', blockWeeks < st.weeks ? blockWeeks + ' weeks left to race day' : 'Counted back from race week', 'weeks', st.weeks, P.WEEKS.min, P.WEEKS.max) + '</div>';
  const draw = () => {
    const e = entryFor(k);
    const r = (e && e.race) || (S.races || []).find((x) => x.id === k);
    if (!r) { body.innerHTML = '<p class="muted">' + esc("This race is no longer in Brüce's list.") + '</p>'; return; }
    const day = e ? e.day : r.date;
    const today = todayKey();
    let html = '<h2 class="sheet-title left">' + esc(r.name) + '</h2><p class="muted">' + esc(R.dateText(r, e && e.mine.day) + ' · ' + R.countdownText(r, today, e && e.mine.day)) + '</p>';
    const plan = planOf(e);
    if (!plan) {
      if (R.daysBetween(today, day) < 0) { body.innerHTML = html + '<p class="muted">Race day has passed.</p>'; return; }
      const preview = P.makePlan(day, r.type, r.sport, P.newSettings(today, draft));
      html += '<p>' + esc(INTRO) + '</p>' + settingsCard(draft, preview.blockWeeks) +
        '<div class="card"><b>' + esc(P.status(preview, today).kind === 'upcoming' ? 'Starts ' + R.shortDay(preview.weeks[0].monday, true) : preview.blockWeeks + ' weeks to race week') + '</b>' +
        stripHTML(preview, true) + gridHTML(preview, false) + '</div>' +
        '<p class="muted small">' + esc(NOT_COACHING) + '</p><button class="btn lime" data-plan-start>' + icon('run') + ' Start plan</button>';
    } else {
      const m = e.mine, st = weekStatus(e, plan);
      const targets = P.monthTargets(plan, today.slice(0, 7)).sort((a, b) => b.count - a.count).slice(0, 4);
      html += '<div class="card"><div class="row-between"><b>' + esc(P.headline(plan, today)) + '</b>' + (st ? '<small class="muted">' + esc(P.progressText(st)) + '</small>' : '') + '</div>' +
        stripHTML(plan, true) + gridHTML(plan, true) + '<p class="muted small">Tap a number to change that week. Past weeks stay as they were.</p></div>' +
        settingsCard(m.plan, plan.blockWeeks) +
        '<div class="card form-rows">' + toggle('week', 'Race week: Monday 08:00', m.remindWeek) + toggle('eve', 'The day before: 18:00', m.remindEve) +
        '<p class="muted small">' + esc(St.serverOn() ? 'Our server sends a push to the Brüce iPhone app and an email.' : 'Needs our server, which is off in Settings.') + '</p></div>' +
        '<div class="card form-rows"><label class="toggle"><span>' + icon('target') + ' Monthly goals from this plan<small class="muted">' +
        esc(targets.length ? targets.map((t) => P.category(t.category).short + ' ' + t.count).join(' · ') : 'No classes planned this month') + '</small></span>' +
        '<input type="checkbox" data-plan-goals' + (m.plan.goals ? ' checked' : '') + (targets.length || m.plan.goals ? '' : ' disabled') + '><i></i></label>' +
        '<p class="muted small">' + esc(GOALS_HINT) + '</p></div>' +
        '<p class="muted small">' + esc(NOT_COACHING) + '</p><button class="btn glass red-text" data-plan-stop>Stop plan</button>';
    }
    body.innerHTML = html;
  };
  const toggle = (name, label, on) => '<label class="toggle"><span>' + esc(label) + '</span><input type="checkbox" data-plan-remind="' + name + '"' + (on ? ' checked' : '') + '><i></i></label>';
  body.addEventListener('click', (ev) => {
    const e = entryFor(k);
    const r = (e && e.race) || (S.races || []).find((x) => x.id === k);
    const stepB = ev.target.closest('[data-step]');
    if (stepB) {
      const name = stepB.dataset.step, d = +stepB.dataset.d;
      const lim = name === 'perWeek' ? P.PER_WEEK : P.WEEKS;
      if (e && e.mine.plan) updatePlan(k, (p) => Object.assign(p, { [name]: Math.min(lim.max, Math.max(lim.min, (p[name] || lim.default) + d)) }));
      else draft[name] = Math.min(lim.max, Math.max(lim.min, draft[name] + d));
      draw(); return;
    }
    const cell = ev.target.closest('[data-plan-cell]');
    if (cell && e && e.mine.plan) {
      const [monday, cat] = cell.dataset.planCell.split('|');
      const plan = planOf(e);
      const w = plan.weeks.find((x) => x.monday === monday);
      const own = P.counts(plan.template, w.phase, plan.settings.perWeek)[cat] || 0;
      const n = (P.count(w, cat) + 1) % (P.MAX_CELL + 1);
      updatePlan(k, (p) => { const ek = P.editKey(monday, cat); if (n === own) delete p.edits[ek]; else p.edits[ek] = n; return p; });
      draw(); return;
    }
    if (ev.target.closest('[data-plan-start]') && r) { startPlan(r, draft); draw(); return; }
    if (ev.target.closest('[data-plan-stop]')) {
      confirmSheet('Stop this plan?', 'The weekly mix, your changes and goals made from it go. The race stays in My races.', 'Stop plan', 'red').then((yes) => { if (yes) { stopPlan(k); s.close(); } });
    }
  });
  body.addEventListener('change', (ev) => {
    if (ev.target.matches('[data-plan-goals]')) { setPlanGoals(k, ev.target.checked); draw(); return; }
    const t = ev.target.closest('[data-plan-remind]');
    if (!t) return;
    const field = t.dataset.planRemind === 'week' ? 'remindWeek' : 'remindEve';
    St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === k ? Object.assign({}, m, { [field]: t.checked }) : m)));
  });
  draw();
}
