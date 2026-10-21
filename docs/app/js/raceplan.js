// Train for it (Shared/BruceCore/RacePlanner.swift): a race in My races becomes a block of weeks that ends in race
// week (Base, Build, Peak, race week, then one recovery week; a race under six weeks away skips Base), each with a class
// mix by Bruce category for the race type. Progress counts this week's check-ins and bookings, and open slots get
// classes near the member. It is a class mix, not a training programme: members change any week, and it does not plan
// long runs, rides or swims. Pure functions on plain objects with days as "YYYY-MM-DD" (tests in
// test/raceplan.test.js, the same cases as RacePlannerTests); raceplanui.js draws them.
import { addDay, daysBetween, shortDay } from './races.js';

/** Bruce categories of a mix: key, id in the Bruce API (as in Demo.swift), title, short label, names a title uses. */
export const CATEGORIES = [
  ['hyrox', 13, 'Hyrox', 'Hyrox', ['hyrox']],
  ['strength', 26, 'Strength', 'Strength', ['strength']],
  ['running', 23, 'Running', 'Running', ['running', 'run']],
  ['highIntensity', 12, 'High-intensity', 'HIIT', ['high-intensity', 'high intensity', 'hiit']],
  ['crossfit', 8, 'CrossFit', 'CrossFit', ['crossfit']],
  ['climbing', 7, 'Climbing', 'Climbing', ['climbing', 'bouldering']],
  ['outdoor', 18, 'Outdoor', 'Outdoor', ['outdoor']],
  ['cycling', 9, 'Cycling', 'Cycling', ['cycling', 'spinning', 'indoor cycling']],
  ['swimming', 27, 'Swimming', 'Swimming', ['swimming', 'swim']],
  ['cardio', 6, 'Cardio', 'Cardio', ['cardio']],
  ['mobility', 16, 'Mobility', 'Mobility', ['mobility', 'stretch', 'stretching']],
  ['yoga', 2, 'Yoga', 'Yoga', ['yoga']],
  ['massage', 15, 'Massage & Naprapathy', 'Massage', ['massage', 'naprapathy']],
  ['sauna', 24, 'Sauna', 'Sauna', ['sauna']],
].map(([key, id, title, short, names]) => ({ key, id, title, short, names }));
const CAT = Object.fromEntries(CATEGORIES.map((c) => [c.key, c]));
export const category = (key) => CAT[key];
/** Hard sessions: weekly series of these are worth pausing for race week. */
export const HEAVY = ['hyrox', 'strength', 'highIntensity', 'crossfit'];
export const PER_WEEK = { min: 2, max: 6, default: 4 };
export const WEEKS = { min: 4, max: 16, default: 10 };
export const MAX_CELL = 3;
export const PHASES = {
  base: { title: 'Base', short: 'Base' }, build: { title: 'Build', short: 'Build' }, peak: { title: 'Peak', short: 'Peak' },
  race: { title: 'Race week', short: 'Race' }, recovery: { title: 'Recovery', short: 'Recover' },
};

const fold = (s) => String(s == null ? '' : s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/** A category title or code names this category ("Hyrox", "High-intensity", "Massage & Naprapathy", "HIGH_INTENSITY"). */
export function namesCategory(key, text) {
  const t = fold(text).replace(/_/g, ' ').trim();
  if (!t) return false;
  return CAT[key].names.some((n) => t === n || t.startsWith(n + ' ') || t.startsWith(n + '-'));
}
/** The id of a category in the live list: the known id when its title still fits (or the list doesn't have it), else
 *  a category with a fitting title or code; null when the known id now names something else and no title fits. */
export function resolveCategory(key, categories) {
  const c = CAT[key];
  const list = categories || [];
  if (!list.length) return c.id;
  const own = list.find((x) => x.id === c.id);
  if (own && (namesCategory(key, own.title) || namesCategory(key, own.code))) return own.id;
  const other = list.find((x) => namesCategory(key, x.title) || namesCategory(key, x.code));
  if (other) return other.id;
  return own ? null : c.id;
}
/** {key: id} for every category the list has (or may have). */
export function categoryIds(categories) {
  const out = {};
  for (const c of CATEGORIES) { const id = resolveCategory(c.key, categories); if (id != null) out[c.key] = id; }
  return out;
}
/** Plan keys of a class's category ids ("13", 13). */
export const keysOf = (ids, map) => Object.keys(map).filter((k) => (ids || []).some((x) => String(x) === String(map[k])));
/** The category a class title points to ("Hyrox Prep", "Run Club"). */
export function guess(title) {
  const full = fold(title);
  const words = full.split(/[^a-z0-9-]+/).filter(Boolean);
  const c = CATEGORIES.find((x) => x.names.some((n) => (n.includes(' ') ? full.includes(n) : words.includes(n))));
  return c ? c.key : null;
}

// ---------------------------------------------------------------- the mix per race type

const T = (base, build, peak, race, recovery) => ({ base, build, peak, race, recovery });
/** The report's "Train for it" table: race type to Bruce categories, per phase in priority order. */
export function template(type, sport) {
  switch (type) {
    case 'hyrox': return T(['hyrox', 'strength', 'running', 'mobility', 'strength', 'highIntensity'], ['hyrox', 'strength', 'running', 'hyrox', 'highIntensity', 'mobility'],
      ['hyrox', 'hyrox', 'running', 'strength', 'highIntensity', 'mobility'], ['hyrox', 'mobility'], ['mobility', 'sauna']);
    case 'running': return T(['running', 'strength', 'cycling', 'mobility', 'yoga', 'strength'], ['running', 'cycling', 'strength', 'mobility', 'running', 'yoga'],
      ['running', 'running', 'strength', 'mobility', 'cycling', 'yoga'], ['mobility'], ['massage', 'mobility']);
    case 'obstacle': return T(['strength', 'climbing', 'running', 'crossfit', 'mobility', 'outdoor'], ['strength', 'crossfit', 'climbing', 'running', 'outdoor', 'mobility'],
      ['crossfit', 'strength', 'climbing', 'running', 'outdoor', 'mobility'], ['climbing', 'mobility'], ['mobility', 'sauna']);
    case 'triathlon': return T(['swimming', 'cycling', 'running', 'strength', 'mobility', 'swimming'], ['swimming', 'cycling', 'running', 'strength', 'cycling', 'mobility'],
      ['swimming', 'cycling', 'running', 'strength', 'running', 'mobility'], ['swimming', 'mobility'], ['mobility', 'sauna']);
    default:
      if (sport === 'bike') return T(['cycling', 'strength', 'cycling', 'mobility', 'cardio', 'yoga'], ['cycling', 'cycling', 'strength', 'cardio', 'mobility', 'cycling'],
        ['cycling', 'cycling', 'strength', 'cardio', 'mobility', 'yoga'], ['cycling', 'mobility'], ['mobility', 'sauna']);
      if (sport === 'swim') return T(['swimming', 'strength', 'swimming', 'mobility', 'cardio', 'yoga'], ['swimming', 'swimming', 'strength', 'cardio', 'mobility', 'swimming'],
        ['swimming', 'swimming', 'strength', 'mobility', 'cardio', 'yoga'], ['swimming', 'mobility'], ['mobility', 'sauna']);
      if (sport === 'ski') return T(['cardio', 'strength', 'cycling', 'mobility', 'cardio', 'yoga'], ['cardio', 'strength', 'cardio', 'cycling', 'mobility', 'strength'],
        ['cardio', 'cardio', 'strength', 'cycling', 'mobility', 'yoga'], ['cardio', 'mobility'], ['mobility', 'sauna']);
      return T(['cardio', 'strength', 'cycling', 'swimming', 'mobility', 'yoga'], ['cycling', 'cardio', 'strength', 'swimming', 'mobility', 'cycling'],
        ['cycling', 'swimming', 'cardio', 'strength', 'mobility', 'yoga'], ['cardio', 'mobility'], ['mobility', 'sauna']);
  }
}
/** Grid rows: every category of the mix, in order of first use. */
export function rowsOf(t) {
  const out = [];
  for (const k of [].concat(t.base, t.build, t.peak, t.race, t.recovery)) if (!out.includes(k)) out.push(k);
  return out;
}
/** Sessions per category in a week of `phase` with `perWeek` sessions (race week and recovery are fixed). */
export function counts(t, phase, perWeek) {
  const l = t[phase] || [];
  const n = phase === 'race' || phase === 'recovery' ? l.length : Math.max(0, perWeek);
  const out = {};
  for (let i = 0; i < n && l.length; i++) out[l[i % l.length]] = (out[l[i % l.length]] || 0) + 1;
  return out;
}
/** Phases for a block of `n` weeks (race week included), plus the recovery week. */
export function phases(n) {
  const t = Math.max(0, n - 1);
  const peak = t >= 4 ? 2 : Math.min(t, 1);
  let build, base;
  if (n <= 6) { build = t - peak; base = 0; } else { build = Math.max(2, Math.round(t / 3)); base = t - peak - build; }
  return [].concat(Array(base).fill('base'), Array(build).fill('build'), Array(peak).fill('peak'), ['race', 'recovery']);
}

// ---------------------------------------------------------------- weeks

/** The Monday of the week that holds `day`. */
export const mondayOf = (day) => addDay(day, -((new Date(day + 'T12:00:00Z').getUTCDay() + 6) % 7));
/** ISO week number: the week of the year its Thursday is in. */
export function isoWeek(day) {
  const thu = addDay(mondayOf(day), 3);
  return Math.floor(daysBetween(thu.slice(0, 4) + '-01-01', thu) / 7) + 1;
}
export const editKey = (monday, key) => monday + '|' + key;
/** New plan settings, as stored on a My races entry (`plan`). */
export const newSettings = (startedOn, o) => Object.assign({ startedOn, weeks: WEEKS.default, perWeek: PER_WEEK.default, edits: {} }, o || {});
const clamp = (v, lo, hi, d) => Math.min(hi, Math.max(lo, Number.isFinite(+v) ? Math.round(+v) : d));

/** The plan for a race day: {raceDay, settings, template, rows, weeks: [{index, monday, sunday, phase, counts, edited,
 *  label, total}], blockWeeks, raceWeek}; null without readable days. */
export function makePlan(raceDay, type, sport, s) {
  const ok = (d) => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d);
  if (!s || !ok(raceDay) || !ok(s.startedOn)) return null;
  const t = template(type, sport);
  const rows = rowsOf(t);
  const raceMonday = mondayOf(raceDay);
  const length = clamp(s.weeks, 1, WEEKS.max, WEEKS.default);
  const earliest = addDay(raceMonday, -7 * (length - 1));
  const start = mondayOf(s.startedOn);
  let first = start > earliest ? start : earliest;
  if (first > raceMonday) first = raceMonday;
  const n = daysBetween(first, raceMonday) / 7 + 1;
  const perWeek = clamp(s.perWeek, PER_WEEK.min, PER_WEEK.max, PER_WEEK.default);
  const edits = s.edits || {};
  const weeks = phases(n).map((phase, index) => {
    const monday = addDay(first, 7 * index);
    const c = counts(t, phase, perWeek);
    const edited = [];
    for (const k of rows) {
      const v = edits[editKey(monday, k)];
      if (v != null) { c[k] = clamp(v, 0, MAX_CELL, 0); edited.push(k); }
    }
    for (const k of Object.keys(c)) if (!c[k]) delete c[k];
    return { index, monday, sunday: addDay(monday, 6), phase, counts: c, edited, label: 'W' + isoWeek(monday),
      total: Object.values(c).reduce((a, b) => a + b, 0) };
  });
  return { raceDay, settings: s, template: t, rows, weeks, blockWeeks: weeks.length - 1, raceWeek: weeks.find((w) => w.phase === 'race') };
}
export const count = (w, key) => (w && w.counts[key]) || 0;
export const weekOfDay = (plan, day) => plan.weeks.find((w) => w.monday <= day && day <= w.sunday) || null;
/** {kind: "upcoming" | "active" | "done", week}. */
export function status(plan, today) {
  if (today < plan.weeks[0].monday) return { kind: 'upcoming', week: null };
  const w = weekOfDay(plan, today);
  return w ? { kind: 'active', week: w } : { kind: 'done', week: null };
}
export const isRunning = (plan, today) => status(plan, today).kind !== 'done';
/** "Week 3 of 10 · Base", "Week 10 of 10 · Race week", "Recovery week", "Starts Mon 5 Oct", "Plan done". */
export function headline(plan, today) {
  const s = status(plan, today);
  if (s.kind === 'upcoming') return 'Starts ' + shortDay(plan.weeks[0].monday, true);
  if (s.kind === 'done') return 'Plan done';
  if (s.week.phase === 'recovery') return 'Recovery week';
  return 'Week ' + (s.week.index + 1) + ' of ' + plan.blockWeeks + ' · ' + PHASES[s.week.phase].title;
}
/** The phase strip: [{phase, weeks}] of the block. */
export function segments(plan) {
  const out = [];
  for (const w of plan.weeks) {
    if (w.phase === 'recovery') continue;
    const last = out[out.length - 1];
    if (last && last.phase === w.phase) last.weeks++; else out.push({ phase: w.phase, weeks: 1 });
  }
  return out;
}
/** Sessions per category in a month ("2026-10"): a week counts for the month its Thursday is in. */
export function monthTargets(plan, month) {
  const sums = {};
  for (const w of plan.weeks) {
    if (addDay(w.monday, 3).slice(0, 7) !== month) continue;
    for (const [k, n] of Object.entries(w.counts)) sums[k] = (sums[k] || 0) + n;
  }
  return plan.rows.filter((k) => sums[k] > 0).map((k) => ({ category: k, count: sums[k] }));
}
/** "1 Hyrox and 1 Mobility", "2 Hyrox, 1 Strength and 1 Running". */
export function mixText(w, rows) {
  const parts = rows.filter((k) => count(w, k) > 0).map((k) => count(w, k) + ' ' + CAT[k].short);
  return parts.length > 1 ? parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1] : (parts[0] || '');
}

// ---------------------------------------------------------------- monthly goals from plans (goals.js)

/**
 * The monthly goals with those of plans in step (RacePlanner.planGoals). plans: [{key, targets: monthTargets(...),
 * skip: ["23"]}] of the plans whose goals are on; ids: {key: id}. Per plan this month's four biggest categories (goal
 * categories are ids as strings), not those the member deleted or has a goal for (their own, or an earlier race's);
 * goals of plans not listed go.
 */
export function planGoals(goals, plans, ids, newId) {
  let next = goals.filter((g) => !g.raceKey || plans.some((p) => p.key === g.raceKey));
  for (const p of plans) {
    const keep = new Set();
    for (const t of p.targets.slice().sort((a, b) => b.count - a.count).slice(0, 4)) {
      if (!(t.count > 0) || ids[t.category] == null) continue;
      const k = String(ids[t.category]);
      if ((p.skip || []).includes(k) || next.some((g) => String(g.category) === k && g.raceKey !== p.key && !g.studioId)) continue;
      keep.add(k);
      const i = next.findIndex((g) => g.raceKey === p.key && String(g.category) === k);
      if (i >= 0) { if (next[i].target !== t.count) next = next.map((g, j) => (j === i ? Object.assign({}, g, { target: t.count }) : g)); }
      else next = next.concat({ id: newId ? newId() : 'g-' + p.key + '-' + k, category: k, target: t.count, studioId: null, remind: true, raceKey: p.key });
    }
    next = next.filter((g) => g.raceKey !== p.key || keep.has(String(g.category)));
  }
  return next;
}

// ---------------------------------------------------------------- this week

const KIND = { done: 0, booked: 1, autoBook: 2 };
/** Fills a week's slots: check-ins first, then bookings, oldest first; each item takes a slot of one of its categories,
 *  the one with the most open slots left. Items outside the mix are left out. Item: {kind, classId, title, studioId,
 *  at (ISO), categories: [key]}. -> {week, slots: [{category, n, item, suggestion}], extra} */
export function assign(week, rows, items) {
  const slots = [];
  for (const k of rows) for (let n = 0; n < count(week, k); n++) slots.push({ category: k, n, item: null, suggestion: null });
  const extra = [];
  const sorted = (items || []).filter((it) => it.categories.some((k) => rows.includes(k)))
    .sort((a, b) => KIND[a.kind] - KIND[b.kind] || String(a.at).localeCompare(String(b.at)));
  for (const it of sorted) {
    let best = null;
    for (const k of rows) {
      if (!it.categories.includes(k)) continue;
      const open = slots.filter((s) => s.category === k && !s.item).length;
      if (open > 0 && (!best || open > best.open)) best = { k, open };
    }
    const slot = best && slots.find((s) => s.category === best.k && !s.item);
    if (slot) slot.item = it; else extra.push(it);
  }
  return { week, slots, extra };
}
/** "done" | "booked" | "autoBook" | "suggested" | "open". */
export const slotState = (s) => (s.item ? s.item.kind : s.suggestion ? 'suggested' : 'open');
export const doneCount = (st) => st.slots.filter((s) => slotState(s) === 'done').length;
export const progressText = (st) => doneCount(st) + ' of ' + st.slots.length + ' this week';
export const nextToBook = (st) => (st.slots.find((s) => slotState(s) === 'suggested') || {}).suggestion || null;

/** Booked now, cancelling would already cost a strike (store.js rules(c) `lateCancel`, 12 h before by default). */
export function strikeNow(c, now) {
  const s = Date.parse(c.start_time);
  const late = c.unbookable_latest_time ? Date.parse(c.unbookable_latest_time) : s - (c.unbookable_latest != null ? c.unbookable_latest : 43200) * 1000;
  return now >= late;
}

/**
 * A class for each open slot. input = {now (ms), notAfter (ms), notBefore (ms, optional), classes, ids ({key: id}),
 * allowed(c) (visit limits, tiers, the selected area), busyDays (Set of "YYYY-MM-DD"), dayOf(c) -> "YYYY-MM-DD",
 * rank(classes) -> [{class, reasons}] best first (the For you scoring; default: by start)}. One class per slot,
 * preferring days without another session and classes still free to cancel.
 */
export function suggest(st, input) {
  const i = input;
  const busy = new Set(i.busyDays || []);
  const used = new Set(st.slots.map((s) => s.item && s.item.classId).filter((x) => x != null));
  const dayOf = i.dayOf || ((c) => c.start_time.slice(0, 10));
  const rank = i.rank || ((list) => list.slice().sort((a, b) => a.start_time.localeCompare(b.start_time)).map((c) => ({ class: c, reasons: [] })));
  const out = Object.assign({}, st, { slots: st.slots.map((s) => Object.assign({}, s)) });
  for (const slot of out.slots) {
    if (slot.item) continue;
    const id = i.ids[slot.category];
    if (id == null) continue;
    const pool = (i.classes || []).filter((c) => {
      const s = Date.parse(c.start_time);
      if (!(s > i.now + 20 * 60000 && s >= (i.notBefore || 0) && s < i.notAfter) || used.has(c.id) || c.canceled || c.deleted === true || c.deleted_at) return false;
      if (c.available_spots != null && c.available_spots <= 0) return false;
      if (c.bookable_latest_time && Date.parse(c.bookable_latest_time) < i.now) return false;
      return (c.class_categories || []).some((x) => String(x.category_id) === String(id)) && (!i.allowed || i.allowed(c));
    });
    if (!pool.length) continue;
    const ranked = rank(pool);
    const free = (r) => !strikeNow(r.class, i.now);
    const pick = ranked.find((r) => free(r) && !busy.has(dayOf(r.class))) || ranked.find(free) || ranked[0];
    if (!pick) continue;
    used.add(pick.class.id);
    busy.add(dayOf(pick.class));
    const c = pick.class;
    const opens = c.bookable_earliest_time ? Date.parse(c.bookable_earliest_time) : null;
    slot.suggestion = { category: slot.category, class: c, reasons: pick.reasons || [], strike: !free(pick), opens: opens && opens > i.now ? opens : null,
      fewSpots: c.available_spots > 0 && c.available_spots <= 9 ? c.available_spots : null };
  }
  return out;
}
