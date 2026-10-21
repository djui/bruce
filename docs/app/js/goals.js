// Pure monthly-goal logic (no DOM, runs under Node): which visits count for a goal, progress and pace, the week
// streak, the month calendar and suggestions. Goals are stored on the device; progress counts checked-in visits
// (visits.js `visitsFrom(..., {checkedInOnly: true})`), like the server's goal reminders.
// Goal: {id, category: null | "anyClass" | "gym" | "<category id>", target, studioId?, remind}.

import { addDays, addMonths, daysInMonth, weekOf, weekdayOf, tally } from './visits.js';

/** Does visit `v` count for `goal`? Category keys as in CONTRACT.md, plus "anyClass" (device only). */
export function counts(goal, v) {
  if (goal.studioId && v.studioId !== goal.studioId) return false;
  const k = goal.category;
  if (k == null || k === '') return true;
  if (k === 'anyClass') return v.kind === 'class';
  if (k === 'gym') return v.kind === 'dropin';
  if (k === 'newStudios') return false;   // needs the whole history: see newStudioVisits
  return v.categories.includes(String(k));
}

/** "Try new studios": this month's first-ever visits at studios never visited before this month, one per studio. */
export function newStudioVisits(visits, today) {
  const month = today.slice(0, 7);
  const first = {};
  for (const v of visits.slice().sort((a, b) => a.day.localeCompare(b.day))) if (v.studioId && v.day <= today && !first[v.studioId]) first[v.studioId] = v;
  return Object.values(first).filter((v) => v.month === month);
}

/** "Gym visits", "Yoga classes", "Classes", "Visits". `titleOf(id)` names a Bruce category. */
export function goalTitle(category, titleOf) {
  if (category == null || category === '') return 'Visits';
  if (category === 'anyClass') return 'Classes';
  if (category === 'gym') return 'Gym visits';
  if (category === 'newStudios') return 'New studios';
  const t = (titleOf && titleOf(category)) || 'Category';
  return /class(es)?$/i.test(t) ? t : t + ' classes';
}

/** {month, day, days, daysLeft} for "YYYY-MM-DD"; daysLeft does not count today. */
export function monthInfo(today) {
  const month = today.slice(0, 7);
  const day = +today.slice(8, 10);
  const days = daysInMonth(month);
  return { month, day, days, daysLeft: days - day };
}

const plural = (n, one, many) => n + ' ' + (n === 1 ? one : (many || one + 's'));

/**
 * Progress of one goal this month: {done, target, pct, pacePct, expected, status: "done" | "ahead" | "onPace" | "behind",
 * pace: "Exactly on pace", toGo: "11 to go · 17 days left", last: visit | null}.
 * Behind = more than one visit under the straight line from 0 to the target (the server's reminder rule).
 */
export function progress(goal, visits, today) {
  const m = monthInfo(today);
  const mine = goal.category === 'newStudios' ? newStudioVisits(visits, today) : visits.filter((v) => v.month === m.month && v.day <= today && counts(goal, v));
  const done = mine.length;
  const target = Math.max(1, goal.target || 1);
  const expected = target * m.day / m.days;
  let status;
  if (done >= target) status = 'done';
  else if (done < expected - 1) status = 'behind';
  else if (done >= expected + 1) status = 'ahead';
  else status = 'onPace';
  const diff = Math.round(done - expected);
  const pace = status === 'done' ? 'Goal reached' : diff === 0 ? 'Exactly on pace' : diff > 0 ? plural(diff, 'ahead of pace', 'ahead of pace') : plural(-diff, 'behind pace', 'behind pace');
  const left = target - done;
  const toGo = left <= 0 ? (done > target ? (done - target) + ' extra' : 'Done') : left + ' to go' + (m.daysLeft ? ' · ' + plural(m.daysLeft, 'day') + ' left' : ' · last day');
  return {
    done, target, expected, status, pace, toGo, last: mine[mine.length - 1] || null,
    pct: Math.min(100, Math.round(1000 * done / target) / 10), pacePct: Math.min(100, Math.round(1000 * expected / target) / 10),
  };
}

/**
 * The ring on the goals screen: {done, target, pct, status: "Done" | "On pace" | "Behind", hint, streak}.
 * `done` caps each goal at its target, so one goal far ahead does not hide another one behind.
 */
export function summary(goals, visits, today) {
  const m = monthInfo(today);
  const ps = goals.map((g) => progress(g, visits, today));
  const done = ps.reduce((a, p) => a + Math.min(p.done, p.target), 0);
  const target = ps.reduce((a, p) => a + p.target, 0);
  const status = !ps.length ? 'No goals' : ps.every((p) => p.status === 'done') ? 'Done' : ps.some((p) => p.status === 'behind') ? 'Behind' : 'On pace';
  const left = target - done;
  const daysIncl = m.daysLeft + 1;
  let hint = 'Day ' + m.day + ' of ' + m.days + '. ';
  if (!ps.length) hint += 'Add a goal to start.';
  else if (left <= 0) hint += 'Every goal is done this month.';
  else if (daysIncl / left >= 1) hint += 'Keep 1 visit every ' + fmt1(daysIncl / left) + ' days to hit everything.';
  else hint += 'About ' + fmt1(left / daysIncl) + ' visits a day to hit everything.';
  return { done, target, pct: target ? Math.min(100, Math.round(100 * done / target)) : 0, status, hint, progress: ps, streak: weekStreak(visits, today) };
}
const fmt1 = (x) => (Math.round(x * 10) / 10).toString().replace(/\.0$/, '');

/** Weeks in a row with at least one visit, up to this week (or last week while this week has none yet). */
export function weekStreak(visits, today) {
  const weeks = new Set(visits.filter((v) => v.day <= today).map((v) => weekOf(v.day)));
  let w = weekOf(today);
  if (!weeks.has(w)) w = addDays(w, -7);
  let n = 0;
  while (weeks.has(w)) { n++; w = addDays(w, -7); }
  return n;
}
/** The longest run of consecutive weeks with a visit. */
export function longestWeekStreak(visits) {
  const weeks = [...new Set(visits.map((v) => weekOf(v.day)))].sort();
  let best = 0, run = 0, prev = null;
  for (const w of weeks) {
    run = prev && addDays(prev, 7) === w ? run + 1 : 1;
    best = Math.max(best, run); prev = w;
  }
  return best;
}

/**
 * This month's calendar: {lead (blank cells before day 1, Monday first), cells: [{day, key, visit, goal, today, future}]}.
 * `goal` marks a visit that counts for a class-category goal (blue dot, e.g. a swim); `visit` any other visit (lime).
 */
export function calendar(today, visits, goals) {
  const m = monthInfo(today);
  const first = m.month + '-01';
  const special = goals.filter((g) => g.category != null && g.category !== '' && g.category !== 'anyClass' && g.category !== 'gym');
  const cells = [];
  for (let d = 1; d <= m.days; d++) {
    const key = addDays(first, d - 1);
    const vs = visits.filter((v) => v.day === key);
    cells.push({ day: d, key, visit: vs.length > 0, goal: vs.some((v) => special.some((g) => counts(g, v))), today: key === today, future: key > today });
  }
  return { lead: weekdayOf(first), cells };
}

/**
 * Goals suggested from the last three full months: [{category, avg, target}] for gym visits and the categories you do,
 * busiest first, without the ones you already have.
 */
export function suggestions(visits, today, existing) {
  const month = today.slice(0, 7);
  const from = addMonths(month, -3);
  const recent = visits.filter((v) => v.month >= from && v.month < month);
  const have = new Set((existing || []).map((g) => String(g.category)));
  const keys = tally(recent.flatMap((v) => (v.kind === 'dropin' ? ['gym'] : v.categories)), (k) => k);
  const out = [];
  for (const [k, n] of keys) {
    const avg = n / 3;
    if (avg < 1 || have.has(String(k))) continue;
    out.push({ category: k, avg: Math.round(avg), target: Math.max(1, Math.ceil(avg * 1.1)) });
  }
  return out.slice(0, 3);
}

/** Body for PUT /me/goals: the goals with a reminder, titled. */
export function remindPayload(goals, titleOf) {
  return goals.filter((g) => g.remind).slice(0, 10).map((g) => ({ id: g.id, title: goalTitle(g.category, titleOf), category: g.category == null || g.category === 'anyClass' ? null : String(g.category), target: g.target, remind: true }));
}
