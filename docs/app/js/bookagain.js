// "Book again" (Shared/BruceCore/BookAgain.swift): the next class of a series the user went to, matched the way
// auto-book matches a weekly class: same studio, weekday and start time, the same master_id when both sides have
// one, else the same title. Pure (tests in test/logic.test.js); the sheet lives in sheets.js.
import { dayKey, addDays, getZone } from './util.js';

/** The series of a past class or a visit's class: {studioId, masterId, title, weekday, minuteOfDay, instructor}. */
export function templateOf(c, studioId) {
  if (!c || !c.title || !c.start_time) return null;
  const sid = studioId || c.studio_id || (c.studio && c.studio.id);
  if (!sid) return null;
  const p = new Intl.DateTimeFormat('en-US', { timeZone: getZone(), weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(new Date(c.start_time));
  const g = (t) => p.find((x) => x.type === t).value;
  const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(g('weekday')) + 1;
  return { studioId: sid, masterId: c.master_id || null, title: c.title, weekday, minuteOfDay: (+g('hour') % 24) * 60 + +g('minute'), instructor: c.instructor || null };
}

/** Whether `c` is the next class of the series. */
export function matches(t, c) {
  if (!c || c.studio_id !== t.studioId || c.deleted || c.canceled || !c.start_time) return false;
  const u = templateOf(c, c.studio_id);
  if (!u || u.weekday !== t.weekday || u.minuteOfDay !== t.minuteOfDay) return false;
  if (t.masterId && c.master_id) return c.master_id === t.masterId;
  return c.title.toLowerCase() === t.title.toLowerCase();
}

/** The next one or two days (YYYY-MM-DD) with the series' weekday; today only while the class has not started. */
export function candidateDays(t, now) {
  const out = [];
  const today = dayKey(now);
  for (let i = 0; i < 15 && out.length < 2; i++) {
    const key = addDays(today, i);
    const u = templateOf({ title: 'x', start_time: key + 'T12:00:00Z' }, 1);
    // Weekday of the key in the city's zone: noon UTC is the same calendar day everywhere in Europe.
    if (u.weekday !== t.weekday) continue;
    if (i === 0) {
      const p = new Intl.DateTimeFormat('en-US', { timeZone: getZone(), hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(new Date(now));
      const g = (x) => +p.find((y) => y.type === x).value;
      if ((g('hour') % 24) * 60 + g('minute') >= t.minuteOfDay) continue;
    }
    out.push(key);
  }
  return out;
}

/** The first upcoming class in `classes` that the series matches: {next, opens (ms or null), sameInstructor}. */
export function pick(classes, t, now) {
  const next = classes.filter((c) => matches(t, c) && Date.parse(c.start_time) > now).sort((a, b) => a.start_time.localeCompare(b.start_time))[0];
  if (!next) return null;
  const opensAt = next.bookable_earliest_time ? Date.parse(next.bookable_earliest_time) : Date.parse(next.start_time) - (next.bookable_earliest != null ? next.bookable_earliest : 7 * 86400) * 1000;
  const same = !!t.instructor && !!next.instructor && next.instructor.replace(/\*\*/g, '').trim().toLowerCase() === t.instructor.replace(/\*\*/g, '').trim().toLowerCase();
  return { next, opens: opensAt > now ? opensAt : null, sameInstructor: same };
}
