// Pure Brüce Wrapped numbers (no DOM, runs under Node): the year to date from the visits in visits.js, the class
// personality, classes done together with friends, and which story cards to show.

import { addDays, daysBetween, tally, first, weekOf } from './visits.js';

export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const ZEN = /yoga|meditat|pilates|stretch|mobility|breath|yin|barre|spa|sauna/i;

/** Classes the user and each friend both attended: friends' bookings matched by class id. [{userId, count}], most first. */
export function together(visits, friendBookings) {
  const mine = new Set(visits.filter((v) => v.kind === 'class' && v.classId != null).map((v) => v.classId));
  const per = new Map();
  for (const b of friendBookings || []) {
    const id = b.class_id || (b.class && b.class.id);
    if (!id || !mine.has(id) || b.deleted || b.deleted_at) continue;
    const s = per.get(b.user_id) || new Set();
    s.add(id); per.set(b.user_id, s);
  }
  return [...per.entries()].map(([userId, s]) => ({ userId, count: s.size })).sort((a, b) => b.count - a.count);
}

/** Longest run of weeks in a row with a visit: {weeks, from, to} (first and last visit day of the run). */
export function longestStreak(visits) {
  const days = [...new Set(visits.map((v) => v.day))].sort();
  const weeks = [...new Set(days.map(weekOf))].sort();
  let best = { weeks: 0, start: null, end: null }, run = 0, start = null, prev = null;
  for (const w of weeks) {
    if (prev && addDays(prev, 7) === w) run++; else { run = 1; start = w; }
    if (run > best.weeks) best = { weeks: run, start, end: w };
    prev = w;
  }
  if (!best.weeks) return { weeks: 0, from: null, to: null };
  const inRun = days.filter((d) => d >= best.start && d <= addDays(best.end, 6));
  return { weeks: best.weeks, from: inRun[0], to: inRun[inRun.length - 1] };
}

/**
 * Class personality, by rules on time of day, weekdays, studio variety and categories:
 * {key, title, blurb}. `catTitle(id)` names a Bruce category.
 */
export function archetype(visits, catTitle) {
  const n = visits.length;
  if (!n) return { key: 'newcomer', title: 'The Newcomer', blurb: 'Your first visit is the hardest. The rest of the year is yours.' };
  const share = (f) => visits.filter(f).length / n;
  const count = (f) => visits.filter(f).length;
  const early = (v) => v.hour < 8;
  const night = (v) => v.hour >= 19;
  const lunch = (v) => v.weekday < 5 && v.hour >= 11 && v.hour < 14;
  const weekend = (v) => v.weekday >= 5;
  const zen = (v) => ZEN.test(v.title) || v.categories.some((c) => ZEN.test((catTitle && catTitle(c)) || ''));
  const studios = tally(visits, (v) => v.studioId);
  const top = first(studios);
  if (n >= 3 && share(early) >= 0.35) return { key: 'earlyBird', title: 'The Early Bird', blurb: count(early) + ' visits before 08:00. The morning crew knows you by name.' };
  if (n >= 3 && share(night) >= 0.35) return { key: 'nightOwl', title: 'The Night Owl', blurb: count(night) + ' visits after 19:00. You own the late slots.' };
  if (n >= 3 && share(lunch) >= 0.3) return { key: 'lunchBreaker', title: 'The Lunch Breaker', blurb: count(lunch) + ' lunch-break visits. Who needs a sandwich anyway?' };
  if (n >= 3 && share(weekend) >= 0.4) return { key: 'weekendWarrior', title: 'The Weekend Warrior', blurb: count(weekend) + ' visits on Saturdays and Sundays. Weekends are for training.' };
  if (n >= 3 && share(zen) >= 0.4) return { key: 'zenMaster', title: 'The Zen Master', blurb: count(zen) + ' calm sessions: yoga, stretch and breath. Namaste.' };
  if (n >= 3 && share((v) => v.kind === 'dropin') >= 0.6) return { key: 'ironRegular', title: 'The Iron Regular', blurb: count((v) => v.kind === 'dropin') + ' solo sessions. No class needed, just you and the weights.' };
  if (studios.size >= 8 || (n >= 6 && studios.size / n >= 0.3)) return { key: 'explorer', title: 'The Explorer', blurb: studios.size + ' different studios. Always looking for the next one.' };
  if (top && n >= 5 && top[1] / n >= 0.6) return { key: 'loyalist', title: 'The Loyalist', blurb: Math.round(100 * top[1] / n) + '% of your visits at one place. Loyal to the core.' };
  return { key: 'allRounder', title: 'The All-Rounder', blurb: 'A bit of everything, at all hours. Hard to pin down.' };
}

/**
 * Year-to-date numbers for Wrapped. visits: this year's visits (visits.js). opts = {year, today: "YYYY-MM-DD",
 * catTitle, together: [{userId, count}]}.
 */
export function wrappedStats(visits, opts) {
  const o = opts || {};
  const year = o.year || +String(o.today).slice(0, 4);
  const today = o.today || (year + '-12-31');
  const vs = visits.filter((v) => v.day.slice(0, 4) === String(year) && v.day <= today);
  const total = vs.length;
  const classes = vs.filter((v) => v.kind === 'class').length;
  const minutes = vs.reduce((a, v) => a + (v.minutes || 0), 0);
  const months = Array.from({ length: 12 }, (_, i) => vs.filter((v) => +v.day.slice(5, 7) === i + 1).length);
  const monthNow = +today.slice(5, 7) - 1;
  const best = months.reduce((b, c, i) => (c > months[b] ? i : b), 0);
  const studios = tally(vs, (v) => v.studioId);
  const fav = first(studios);
  const titles = tally(vs.filter((v) => v.kind === 'class'), (v) => v.title);
  const topClass = first(titles);
  const hours = tally(vs, (v) => v.hour);
  const topHour = first(hours);
  const elapsed = daysBetween(year + '-01-01', today) + 1;
  const friend = (o.together || [])[0];
  return {
    year, total, classes, dropins: total - classes, minutes, hours: Math.round(minutes / 60),
    every: total ? Math.round(10 * elapsed / total) / 10 : null,
    months, monthNow, bestMonth: total ? { index: best, name: MONTHS[best], count: months[best] } : null,
    studios: studios.size, favStudio: fav ? { id: fav[0], count: fav[1] } : null,
    topClass: topClass ? { title: topClass[0], count: topClass[1] } : null,
    topHour: topHour ? { hour: topHour[0], label: String(topHour[0]).padStart(2, '0') + ':00', count: topHour[1] } : null,
    streak: longestStreak(vs), archetype: archetype(vs, o.catTitle),
    friend: friend && friend.count > 0 ? friend : null,
  };
}

/** "Top N%" from a percentile (share of others below you). */
export const topPercent = (p) => Math.max(1, 100 - Math.round(p));

/** The story cards to show, in order; a card without data is skipped. */
export function cardsFor(stats, percentiles) {
  const c = ['intro'];
  if (stats.total > 0) c.push('visits');
  if (stats.total >= 3) c.push('persona');
  if (stats.favStudio) c.push('place');
  if (stats.streak.weeks >= 2 || stats.friend) c.push('streak');
  if (stats.total > 0 && percentiles && percentiles.visits != null) c.push('top');
  c.push('share');
  return c;
}

/** The metrics GET /wrapped/percentiles compares (CONTRACT.md), year to date. */
export const percentileMetrics = (s) => ({ visits: s.total, minutes: s.minutes, studios: s.studios, streak: s.streak.weeks });

/** "3 Aug to 20 Sep" from two "YYYY-MM-DD" days ("3 to 20 Sep" in one month). */
export function dayRange(from, to) {
  if (!from || !to) return '';
  const d = (k) => +k.slice(8, 10);
  const m = (k) => MONTHS[+k.slice(5, 7) - 1].slice(0, 3);
  if (from === to) return d(from) + ' ' + m(from);
  return from.slice(0, 7) === to.slice(0, 7) ? d(from) + ' to ' + d(to) + ' ' + m(to) : d(from) + ' ' + m(from) + ' to ' + d(to) + ' ' + m(to);
}

/**
 * The share card's stat tiles, up to six: [{value, label}]. names = {studio: name of the favourite studio,
 * friend: first name of the top friend}.
 */
export function shareStats(s, names) {
  const n = names || {};
  const out = [{ value: String(s.total), label: s.total === 1 ? 'visit' : 'visits' }];
  if (s.hours) out.push({ value: s.hours + ' h', label: 'trained' });
  if (s.topClass) out.push({ value: s.topClass.count + '×', label: s.topClass.title + ', top class' });
  if (s.favStudio) out.push({ value: String(s.favStudio.count), label: 'at ' + (n.studio || 'your top studio') });
  if (s.streak.weeks >= 2) out.push({ value: s.streak.weeks + ' wk', label: 'longest streak' });
  if (s.friend && n.friend) out.push({ value: String(s.friend.count), label: (s.friend.count === 1 ? 'class' : 'classes') + ' with ' + n.friend });
  if (out.length < 6 && s.studios > 1) out.push({ value: String(s.studios), label: 'studios tried' });
  if (out.length < 6 && s.bestMonth) out.push({ value: String(s.bestMonth.count), label: 'in ' + s.bestMonth.name + ', best month' });
  return out.slice(0, 6);
}
