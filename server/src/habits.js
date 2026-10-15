// Pure logic for "skipped a habit" recommendations: finding a weekly habit the user just broke in their
// `GET /v52/booking` history, and ranking upcoming classes for them. No I/O here (worker.js reads Bruce and pushes),
// so all of it is unit-tested in ../test/habits.test.js.
//
// A habit is the same class (title) at the same studio, weekday and local start time, visited at least
// HABIT_MIN_WEEKS weeks in a row. It is broken when the next week's slot passed without a visit, and the user then
// neither visited anything nor booked anything for LAPSE_DAYS days (a Saturday habit nudges on Wednesday). The user
// can pick another number of days, 1-7 (the apps offer 2, 4 and 7; 7 nudges on the morning of the next slot).

import { visitsFromBookings, addDays, diffDays, localDay } from "./insights.js";

const TZ = "Europe/Stockholm";
export const HABIT_MIN_WEEKS = 3;
export const LAPSE_DAYS = 4;
/** The user's quiet days (`nudgeDays` in PUT /me), or null when it is not a whole number of days from 1 to 7. */
export const cleanLapseDays = (n) => (Number.isInteger(n) && n >= 1 && n <= 7 ? n : null);
/// How far back the history must reach to see a habit (the daily read covers at least this many days).
export const HABIT_LOOKBACK_DAYS = 42;
/// Upcoming classes considered for recommendations, and how many go into the push.
export const RECOMMEND_DAYS = 7;
export const MAX_PICKS = 3;

const partsFmt = new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const WEEKDAYS = { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 };
const DAY_NAMES = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

/** Local weekday (1 = Sunday, like the apps) and minute of the day of a UTC timestamp. */
export function slotOf(ms) {
  const p = Object.fromEntries(partsFmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { weekday: WEEKDAYS[p.weekday], minuteOfDay: +p.hour * 60 + +p.minute };
}

const norm = (t) => String(t ?? "").replace(/\*\*/g, "").trim().toLowerCase();
const clock = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

/** Same time-of-day names as the apps' "For you" (DaySlot in Recommendations.swift). */
export function partOfDay(minuteOfDay) {
  if (minuteOfDay < 11 * 60) return "morning";
  if (minuteOfDay < 14 * 60) return "lunch";
  if (minuteOfDay < 17 * 60) return "afternoon";
  if (minuteOfDay < 20 * 60) return "evening";
  return "late";
}

/**
 * The broken habit the user should hear about today, or null. `bookings` is the raw booking history including
 * future bookings (any upcoming booking means the user is still booking, so no nudge). Of several broken habits the
 * longest run wins. `key` + `missedDay` identify the break, so it is told once.
 */
export function brokenHabit(bookings, now, { minWeeks = HABIT_MIN_WEEKS, lapseDays = LAPSE_DAYS } = {}) {
  const all = visitsFromBookings(bookings, Infinity);
  if (all.some((v) => v.at > now)) return null;
  const today = localDay(now);
  const groups = new Map();
  for (const v of all) {
    if (v.kind !== "class" || !v.title) continue;
    const s = slotOf(v.at);
    const key = `${v.studioId}|${norm(v.title)}|${s.weekday}|${s.minuteOfDay}`;
    let g = groups.get(key);
    if (!g) groups.set(key, g = { key, ...s, title: v.title, studioId: v.studioId, studio: v.studio, categories: v.categories, days: [] });
    g.days.push(v.day);
  }
  let best = null;
  for (const g of groups.values()) {
    const days = [...new Set(g.days)].sort().reverse();
    let weeks = 1;
    while (weeks < days.length && diffDays(days[weeks], days[weeks - 1]) === 7) weeks++;
    if (weeks < minWeeks) continue;
    const missedDay = addDays(days[0], 7);
    const since = diffDays(missedDay, today);
    // Only the latest break, from `lapseDays` after the missed slot until the habit's next slot (that morning included).
    if (since < lapseDays || since > 7) continue;
    if (all.some((v) => v.day >= missedDay)) continue;
    if (!best || weeks > best.weeks || (weeks === best.weeks && days[0] > best.lastDay)) {
      best = { key: g.key, title: g.title, studioId: g.studioId, studio: g.studio, categories: g.categories,
               weekday: g.weekday, minuteOfDay: g.minuteOfDay, weeks, lastDay: days[0], missedDay };
    }
  }
  return best;
}

/**
 * Upcoming classes for the user, best first, at most `max`, one per title and studio. Scored on the user's own
 * history like the apps' "For you" (the same class, its category, the studio) plus closeness to the broken habit's
 * time slot. Only classes starting in the next RECOMMEND_DAYS days that are listed, not full, and bookable before
 * they start. `opensAt(c)` gives the booking open time.
 */
export function recommendClasses(classes, bookings, habit, now, opensAt, { max = MAX_PICKS } = {}) {
  const visits = visitsFromBookings(bookings, now);
  const titles = new Map(), titleHere = new Map(), cats = new Map(), studios = new Map();
  const inc = (m, k) => m.set(k, (m.get(k) ?? 0) + 1);
  for (const v of visits) {
    if (v.studioId != null) inc(studios, v.studioId);
    if (v.kind !== "class") continue;
    inc(titles, norm(v.title));
    inc(titleHere, `${norm(v.title)}|${v.studioId}`);
    for (const c of v.categories) inc(cats, c);
  }
  const habitTitle = norm(habit.title);
  const scored = [];
  const seen = new Set();
  for (const c of classes ?? []) {
    const start = Date.parse(c.start_time);
    if (seen.has(c.id) || !(start > now + 3600_000) || start > now + RECOMMEND_DAYS * 86400_000) continue;
    seen.add(c.id);
    if (c.deleted || c.deleted_at || c.canceled || c.opening === true || c.dedicated === true) continue;
    if (c.available_spots != null && c.available_spots <= 0) continue;
    if (opensAt(c) > start) continue;
    const t = norm(c.title);
    const s = slotOf(start);
    const here = titleHere.get(`${t}|${c.studio_id}`) ?? 0;
    const anywhere = titles.get(t) ?? 0;
    const catIds = (c.class_categories ?? []).map((x) => String(x?.category_id ?? x?.category?.id ?? "")).filter(Boolean);
    const cat = Math.max(0, ...catIds.map((id) => cats.get(id) ?? 0));
    const shift = Math.abs(s.minuteOfDay - habit.minuteOfDay);
    const parts = [
      [0.30, t === habitTitle ? 1 : Math.max(Math.min(1, here / 6), Math.min(1, anywhere / 8) * 0.8)],
      [0.15, catIds.some((id) => habit.categories.includes(id)) ? 1 : Math.min(1, cat / 6)],
      [0.15, c.studio_id === habit.studioId ? 1 : Math.min(1, (studios.get(c.studio_id) ?? 0) / 8)],
      [0.25, shift <= 30 ? 1 : shift <= 90 ? 0.6 : shift <= 180 ? 0.25 : 0],
      [0.10, s.weekday === habit.weekday ? 1 : (s.weekday === 1 || s.weekday === 7) === (habit.weekday === 1 || habit.weekday === 7) ? 0.5 : 0],
      // Sooner is better: the user is out of rhythm now.
      [0.05, 1 - (start - now) / (RECOMMEND_DAYS * 86400_000)],
    ];
    const score = parts.reduce((n, [w, x]) => n + w * x, 0);
    scored.push({ score, start, pick: { classId: c.id, title: String(c.title).replace(/\*\*/g, "").trim(), studioId: c.studio_id,
                                         studio: c.studio?.name ?? null, start: new Date(start).toISOString() } });
  }
  // Best first; a weekly class shows once (its best occurrence).
  const once = new Set();
  const out = [];
  for (const { pick } of scored.sort((a, b) => b.score - a.score || a.start - b.start)) {
    const k = `${norm(pick.title)}|${pick.studioId}`;
    if (once.has(k)) continue;
    once.add(k);
    out.push(pick);
    if (out.length >= max) break;
  }
  return out;
}

const shortWhen = (iso) => new Date(iso).toLocaleString("en-GB", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit" });

/** The push: "Missing your Saturday morning Reformer?" and the picks. */
export function nudgeMessage(habit, picks) {
  const title = `Missing your ${DAY_NAMES[habit.weekday]} ${partOfDay(habit.minuteOfDay)} ${habit.title}?`;
  const streak = `${habit.weeks} ${DAY_NAMES[habit.weekday]}s in a row at ${clock(habit.minuteOfDay)}, then a break.`;
  const list = picks.map((p) => `${p.title}, ${shortWhen(p.start)}${p.studio ? ` at ${p.studio}` : ""}`).join(" · ");
  return { title, body: list ? `${streak} Picked for you: ${list}` : `${streak} Find a class in Brüce.` };
}
