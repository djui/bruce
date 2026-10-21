// Friends going, race crews and after the race (Shared/BruceCore/RaceSocial.swift), as pure functions on plain objects
// (tests in test/crews.test.js); racesui.js and challenges.js draw them. Going is opt-in per race and only shown to
// Bruce friends who share a race too (our server checks); a crew is a challenge with a race and sessions a week that
// ends on race day.
import { addDay, isPast, lastDay } from './races.js';
import { template, counts, rowsOf, category, mondayOf, PER_WEEK } from './raceplan.js';

export const WEEKLY = { min: 1, max: 7 };

/** "1 friend going", "2 friends going". */
export const goingText = (n) => (n === 1 ? '1 friend going' : n + ' friends going');
/** "Alex is going", "Alex and Maja are going", "Alex, Maja and Robin are going". */
export function goingNames(names) {
  const list = (names || []).filter(Boolean);
  if (!list.length) return '';
  if (list.length === 1) return list[0] + ' is going';
  return list.slice(0, -1).join(', ') + ' and ' + list[list.length - 1] + ' are going';
}
/** "4 sessions a week". */
export const weeklyText = (n) => (n === 1 ? '1 session a week' : n + ' sessions a week');
/** "2 of 4 this week". */
export const thisWeekText = (done, weekly) => done + ' of ' + weekly + ' this week';
/** "Last week 4 of 5 hit their sessions"; null in the crew's first week. */
export function lastWeekText(c) {
  if (!c || !c.lastWeek || c.lastWeek.hit == null || !c.size) return null;
  return 'Last week ' + c.lastWeek.hit + ' of ' + c.size + ' hit their sessions';
}
/** "2 of 5 done this week". */
export function doneThisWeekText(c) {
  const w = c.weekly || 1;
  return c.members.filter((m) => (m.thisWeek || 0) >= w).length + ' of ' + c.members.length + ' done this week';
}
/** The name a new crew gets: "HYROX Stockholm crew". */
export const crewName = (r) => r.name + ' crew';
/** Sessions a week from the Train for it plan (Base, Build, Peak), else 3. */
export const defaultWeekly = (plan) => Math.min(WEEKLY.max, Math.max(WEEKLY.min, (plan && plan.perWeek) || 3));
export const isCrew = (c) => !!(c && c.raceId && c.weekly);

/** Shared as going: switched on, and a catalog race (a race added by hand has no shared record). */
export const sharesGoing = (m) => !!(m && m.going && m.raceId);

/** The race's results page on its own site (https only), or null. */
export function resultsUrl(r) {
  try { const u = new URL(r.resultsUrl); return u.protocol === 'https:' ? u.href : null; } catch (e) { return null; }
}

/**
 * After the race until the end of the week after race week (the Train for it recovery week): `{monday, sunday, mix:
 * [{key, title, count}], text}`, else null. `e` is a My races entry (races.js `entries`).
 */
export function recovery(e, today) {
  const raced = e.mine.day || lastDay(e.race);
  if (!isPast(e.race, today, e.mine.day)) return null;
  const monday = addDay(mondayOf(raced), 7), sunday = addDay(monday, 6);
  if (today > sunday) return null;
  const t = template(e.race.type, e.race.sport);
  const c = counts(t, 'recovery', PER_WEEK.default);
  const mix = rowsOf({ base: [], build: [], peak: [], race: [], recovery: t.recovery }).filter((k) => c[k] > 0)
    .map((k) => ({ key: k, title: category(k).short, count: c[k] }));
  const parts = mix.map((x) => x.count + ' ' + x.title);
  return { monday, sunday, mix, text: parts.length > 1 ? parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1] : parts[0] || '' };
}
