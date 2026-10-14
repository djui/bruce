// Pure logic for challenges, goal reminders and Wrapped percentiles: turning a user's `GET /v52/booking` history
// into deduplicated visits and per-day counts, challenge periods and leaderboards, and anonymous percentiles.
// No I/O here (worker.js does the Bruce calls and D1), so all of it is unit-tested in ../test/insights.test.js.
//
// Days are local Europe/Stockholm calendar days as "YYYY-MM-DD" strings; day arithmetic is plain calendar
// arithmetic on those strings (no time zone involved once a timestamp has been turned into a local day).

const TZ = "Europe/Stockholm";
const DAY_MS = 86400_000;
/// A drop-in at the same studio within this time of a class visit is the same visit (the door check-in).
const SAME_VISIT_MS = 3 * 3600_000;
/// A drop-in (gym, solo training) has no length; it counts this many minutes.
export const DROPIN_MINUTES = 60;
/// Percentiles are only given when at least this many other users have data, so nobody's numbers can be inferred.
export const MIN_COHORT = 5;

const dayFmt = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" });
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

// MARK: Days

/** Local day "YYYY-MM-DD" of a UTC timestamp. */
export function localDay(ms) { return dayFmt.format(new Date(ms)); }

const toUTC = (day) => Date.UTC(+day.slice(0, 4), +day.slice(5, 7) - 1, +day.slice(8, 10));
const fromUTC = (ms) => new Date(ms).toISOString().slice(0, 10);
export const addDays = (day, n) => fromUTC(toUTC(day) + n * DAY_MS);
/** Whole days from `a` to `b` (b - a). */
export const diffDays = (a, b) => Math.round((toUTC(b) - toUTC(a)) / DAY_MS);
export const isDay = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && fromUTC(toUTC(s)) === s;
export const monthStart = (day) => `${day.slice(0, 7)}-01`;
export const monthEnd = (day) => addDays(fromUTC(Date.UTC(+day.slice(0, 4), +day.slice(5, 7), 1)), -1);
export const monthLabel = (month) => `${MONTHS[+month.slice(5, 7) - 1]} ${month.slice(0, 4)}`;
const shortDay = (day) => `${+day.slice(8, 10)} ${MONTHS[+day.slice(5, 7) - 1].slice(0, 3)}`;
const minDay = (a, b) => (a < b ? a : b);
const maxDay = (a, b) => (a > b ? a : b);

// MARK: Visits

/**
 * A user's visits from their booking history, newest first. "Everything counts" (the challenge rule): every past
 * booking that was not cancelled or deleted is a visit, checked in or not: classes, opening-hour slots and drop-in
 * gym check-ins (`class_id: null`, see API.md capture 8). Deduplicated so one visit is counted once:
 * - the same class id counts once;
 * - a drop-in at a studio within 3 hours of a class visit there on the same day is that class visit (the door check-in);
 * - two drop-ins at the same studio on the same day are one visit.
 * A merged visit is checked in if any of its bookings was.
 */
export function visitsFromBookings(bookings, now = Date.now()) {
  const classes = [], dropins = [];
  const byClass = new Map();
  for (const b of bookings ?? []) {
    if (!b || b.deleted || b.deleted_at || b.cancelled || b.canceled) continue;
    const c = b.class ?? null;
    if (c && (c.canceled || c.deleted || c.deleted_at)) continue;
    const isClass = b.class_id != null && !!c && c.opening !== true && c.title != null;
    const start = c?.start_time ? Date.parse(c.start_time) : NaN;
    const end = c?.end_time ? Date.parse(c.end_time) : NaN;
    const checkedIn = b.checked_in_at ? Date.parse(b.checked_in_at) : NaN;
    const at = isClass ? (Number.isFinite(start) ? start : checkedIn) : (Number.isFinite(checkedIn) ? checkedIn : start);
    if (!Number.isFinite(at) || at > now) continue;   // a future booking is not a visit (yet)
    if (isClass && byClass.has(b.class_id)) {
      byClass.get(b.class_id).checkedIn ||= Number.isFinite(checkedIn);
      continue;
    }
    const v = {
      at, day: localDay(at), kind: isClass ? "class" : "dropin",
      classId: isClass ? b.class_id : null,
      title: isClass ? String(c.title).replace(/\*\*/g, "").trim() : null,
      studioId: b.studio_id ?? c?.studio_id ?? null,
      studio: c?.studio?.name ?? null,
      minutes: isClass && Number.isFinite(start) && end > start ? Math.round((end - start) / 60_000) : DROPIN_MINUTES,
      categories: [...new Set((c?.class_categories ?? []).map((x) => x?.category_id ?? x?.category?.id).filter((x) => x != null).map(String))],
      checkedIn: Number.isFinite(checkedIn),
    };
    if (isClass) byClass.set(b.class_id, v);
    (isClass ? classes : dropins).push(v);
  }
  const kept = [...classes];
  dropins.sort((a, b) => a.at - b.at);
  for (const d of dropins) {
    const same = kept.find((k) => k.studioId === d.studioId && k.day === d.day &&
                                  (k.kind === "dropin" || Math.abs(k.at - d.at) <= SAME_VISIT_MS));
    if (same) { same.checkedIn ||= d.checkedIn; continue; }
    kept.push(d);
  }
  return kept.sort((a, b) => b.at - a.at);
}

/** Compact stored form of a visit (`daily_counts.detail`). */
const toDetail = (v) => ({ at: new Date(v.at).toISOString(), k: v.kind === "class" ? "c" : "d", id: v.classId, t: v.title,
                           s: v.studioId, n: v.studio, m: v.minutes, c: v.categories, ci: v.checkedIn });
export const fromDetail = (d, day) => ({ at: Date.parse(d.at), day, kind: d.k === "c" ? "class" : "dropin", classId: d.id ?? null,
                                         title: d.t ?? null, studioId: d.s ?? null, studio: d.n ?? null, minutes: d.m ?? DROPIN_MINUTES,
                                         categories: d.c ?? [], checkedIn: !!d.ci });

/**
 * One `daily_counts` row per day with visits. `visits`/`classes`/`dropins`/`minutes` use the challenge rule
 * (everything counts); `checkins`/`checkin_minutes`/`studios` only checked-in visits (Statistics, goals, Wrapped).
 * `detail` (every visit of the day) is kept only for challenge participants.
 */
export function dailyRows(visits, { detail = false } = {}) {
  const days = new Map();
  for (const v of visits) {
    let r = days.get(v.day);
    if (!r) days.set(v.day, r = { day: v.day, visits: 0, classes: 0, dropins: 0, minutes: 0, checkins: 0, checkin_minutes: 0, studios: [], detail: detail ? [] : null });
    r.visits++;
    if (v.kind === "class") r.classes++; else r.dropins++;
    r.minutes += v.minutes;
    if (v.checkedIn) {
      r.checkins++;
      r.checkin_minutes += v.minutes;
      if (v.studioId != null && !r.studios.includes(v.studioId)) r.studios.push(v.studioId);
    }
    if (detail) r.detail.push(toDetail(v));
  }
  return [...days.values()].sort((a, b) => (a.day < b.day ? -1 : 1));
}

/** Longest run of consecutive weeks (Monday to Sunday) with at least one of the given days. */
export function longestWeekStreak(days) {
  const mondays = [...new Set(days.map((d) => addDays(d, -((new Date(toUTC(d)).getUTCDay() + 6) % 7))))].sort();
  let best = 0, run = 0, prev = null;
  for (const m of mondays) {
    run = prev && diffDays(prev, m) === 7 ? run + 1 : 1;
    best = Math.max(best, run);
    prev = m;
  }
  return best;
}

// MARK: Goals (server reminder)

/** Same category keys as the apps: null = any visit, "anyClass", "gym" = drop-ins, else a Bruce category id. */
export function matchesCategory(v, category) {
  if (category == null || category === "") return true;
  if (category === "anyClass") return v.kind === "class";
  if (category === "gym") return v.kind === "dropin";
  return v.categories.includes(String(category));
}

/**
 * Goal reminders due today: checked-in visits this month per goal, and whether the goal is behind pace
 * (count < target * day / daysInMonth - 1), from day 8 of the month, at most once every 7 days per goal.
 */
export function goalReminders(goals, visits, today, lastPings = {}, now = Date.now()) {
  const day = +today.slice(8, 10);
  const days = +monthEnd(today).slice(8, 10);
  if (day < 8) return [];
  const month = today.slice(0, 7);
  const out = [];
  for (const g of goals ?? []) {
    const count = visits.filter((v) => v.checkedIn && v.day.startsWith(month) && matchesCategory(v, g.category) &&
                                       (g.studioId == null || v.studioId === g.studioId)).length;
    if (count >= g.target || count >= (g.target * day) / days - 1) continue;
    if (lastPings[g.id] && now - lastPings[g.id] < 7 * DAY_MS) continue;
    out.push({ goal: g, count, daysLeft: days - day });
  }
  return out;
}

// MARK: Challenges

export const METRICS = ["classes", "visits", "minutes", "target"];
const METRIC_TITLES = { classes: "Most classes", visits: "Most visits", minutes: "Most minutes" };
export const defaultTitle = (metric, target) => (metric === "target" ? `Everyone hits ${target}` : METRIC_TITLES[metric]);

/**
 * The challenge's current period. A monthly repeating challenge runs month after month: its period is the calendar
 * month containing today (the first one starts at `start`). Otherwise `start..end`.
 */
export function challengePeriod(ch, today) {
  let start = ch.start, end = ch.end;
  if (ch.repeatMonthly) {
    const ref = maxDay(today, ch.start);
    start = maxDay(ch.start, monthStart(ref));
    end = monthEnd(ref);
  }
  const days = diffDays(start, end) + 1;
  const wholeMonth = start === monthStart(start) && end === monthEnd(start);
  return {
    start, end, days,
    label: wholeMonth ? monthLabel(start.slice(0, 7)) : `${shortDay(start)} – ${shortDay(end)} ${end.slice(0, 4)}`,
    day: Math.min(days, Math.max(0, diffDays(start, today) + 1)),
    daysLeft: Math.max(0, diffDays(maxDay(today, addDays(start, -1)), end)),
  };
}

/** Months (newest first) a challenge has covered up to today. */
export function challengeMonths(ch, today) {
  const last = ch.repeatMonthly ? today : minDay(today, ch.end);
  const out = [];
  if (last < ch.start) return out;
  for (let m = monthStart(ch.start); m <= last; m = addDays(monthEnd(m), 1)) out.unshift(m.slice(0, 7));
  return out;
}

function score(ch, s) {
  return ch.metric === "classes" ? s.classes : ch.metric === "minutes" ? s.minutes : s.visits;
}

function tally(visits) {
  return {
    visits: visits.length,
    classes: visits.filter((v) => v.kind === "class").length,
    dropins: visits.filter((v) => v.kind === "dropin").length,
    minutes: visits.reduce((n, v) => n + v.minutes, 0),
  };
}

function top(visits, key, name) {
  const counts = new Map();
  for (const v of visits) {
    const k = key(v);
    if (k == null) continue;
    const e = counts.get(k) ?? { ...name(v), count: 0 };
    e.count++;
    counts.set(k, e);
  }
  return [...counts.values()].sort((a, b) => b.count - a.count)[0] ?? null;
}

/**
 * Leaderboard and monthly stats of a challenge. `visitsByUser` maps user id to that user's visits (from the stored
 * detail). Friends see everything: totals, class types, studios and recent visits. Invited participants have no data
 * stored until they accept; they are listed last with zeros.
 */
export function challengeStats(ch, participants, visitsByUser, viewerId, today) {
  const period = challengePeriod(ch, today);
  const upTo = minDay(today, period.end);
  const counts = (uid, from, to) => (visitsByUser.get(uid) ?? [])
    .filter((v) => v.day >= from && v.day <= to && matchesCategory(v, ch.category));
  const mine = new Set(counts(viewerId, period.start, upTo).filter((v) => v.classId != null).map((v) => v.classId));
  const accepted = participants.filter((p) => p.status === "accepted");
  const entries = accepted.map((p) => {
    const vs = counts(p.userId, period.start, upTo);
    const t = tally(vs);
    const daily = [];
    for (let d = period.start; d <= upTo; d = addDays(d, 1)) daily.push(vs.filter((v) => v.day === d).length);
    const cats = new Map();
    for (const v of vs) for (const c of v.categories) cats.set(c, (cats.get(c) ?? 0) + 1);
    if (vs.some((v) => v.kind === "dropin")) cats.set("gym", t.dropins);
    return {
      userId: p.userId, name: p.name, status: p.status, rank: null, score: score(ch, t), ...t,
      studios: new Set(vs.map((v) => v.studioId).filter((x) => x != null)).size,
      topStudio: top(vs, (v) => v.studioId, (v) => ({ id: v.studioId, name: v.studio })),
      topClass: top(vs.filter((v) => v.title), (v) => v.title.toLowerCase(), (v) => ({ title: v.title })),
      categories: [...cats].map(([key, count]) => ({ key, count })).sort((a, b) => b.count - a.count),
      together: p.userId === viewerId ? 0 : vs.filter((v) => v.classId != null && mine.has(v.classId)).length,
      lastVisit: vs.length ? new Date(Math.max(...vs.map((v) => v.at))).toISOString() : null,
      done: ch.metric === "target" ? t.visits >= (ch.target ?? Infinity) : false,
      daily,
      recent: [...vs].sort((a, b) => b.at - a.at).slice(0, 10)
        .map((v) => ({ at: new Date(v.at).toISOString(), kind: v.kind, title: v.title, studioId: v.studioId, studio: v.studio })),
    };
  }).sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  // Competition ranking: equal scores share a rank (1, 2, 2, 4).
  entries.forEach((e, i) => { e.rank = i > 0 && entries[i - 1].score === e.score ? entries[i - 1].rank : i + 1; });
  for (const p of participants.filter((p) => p.status !== "accepted")) {
    entries.push({ userId: p.userId, name: p.name, status: p.status, rank: null, score: 0, visits: 0, classes: 0, dropins: 0, minutes: 0,
                   studios: 0, topStudio: null, topClass: null, categories: [], together: 0, lastVisit: null, done: false, daily: [], recent: [] });
  }
  const months = challengeMonths(ch, today).map((month) => {
    const from = maxDay(ch.start, `${month}-01`);
    const to = minDay(minDay(monthEnd(`${month}-01`), today), ch.repeatMonthly ? "9999-12-31" : ch.end);
    return { month, label: monthLabel(month), entries: accepted.map((p) => {
      const t = tally(counts(p.userId, from, to));
      return { userId: p.userId, name: p.name, score: score(ch, t), ...t };
    }).sort((a, b) => b.score - a.score) };
  });
  return { period, leaderboard: entries, months };
}

/** Validates a `POST /challenges` body; returns `{ error }` or the clean challenge fields. */
export function cleanChallenge(body, today) {
  const metric = METRICS.includes(body?.metric) ? body.metric : null;
  if (!metric) return { error: `metric must be one of ${METRICS.join(", ")}` };
  const target = metric === "target" ? Math.round(+body.target) : null;
  if (metric === "target" && !(target >= 1 && target <= 500)) return { error: "target must be 1-500" };
  let { start, end } = body;
  if (!isDay(start) || !isDay(end) || end < start) return { error: "start and end must be days (YYYY-MM-DD), end not before start" };
  if (diffDays(start, end) > 365) return { error: "a challenge lasts at most 366 days" };
  if (end < today) return { error: "the challenge is already over" };
  const category = body.category == null || body.category === "" ? null : String(body.category).slice(0, 40);
  const title = String(body.title ?? "").trim().slice(0, 80) || defaultTitle(metric, target);
  return { metric, target, start, end, category, categoryTitle: category ? String(body.categoryTitle ?? "").slice(0, 60) || null : null,
           title, repeatMonthly: !!body.repeatMonthly };
}

// MARK: Wrapped percentiles

/** Share (0-100) of `values` below `x`, ties counting half. */
export function percentile(values, x) {
  if (!values.length) return null;
  let below = 0, equal = 0;
  for (const v of values) { if (v < x) below++; else if (v === x) equal++; }
  return Math.round((100 * (below + equal / 2)) / values.length);
}

/** Year-to-date values per user from `daily_counts` rows (checked-in visits, like the apps' Statistics). */
export function cohortValues(rows) {
  const users = new Map();
  for (const r of rows) {
    let u = users.get(r.user_id);
    if (!u) users.set(r.user_id, u = { visits: 0, minutes: 0, studios: new Set(), days: [] });
    if (!r.checkins) continue;
    u.visits += r.checkins;
    u.minutes += r.checkin_minutes;
    for (const s of JSON.parse(r.studios || "[]")) u.studios.add(s);
    u.days.push(r.day);
  }
  return [...users].filter(([, u]) => u.visits > 0)
    .map(([userId, u]) => ({ userId, visits: u.visits, minutes: u.minutes, studios: u.studios.size, streak: longestWeekStreak(u.days) }));
}

export const PERCENTILE_METRICS = ["visits", "minutes", "studios", "streak"];

/** Percentiles of the caller's (device-computed) values among the other users; null below MIN_COHORT. */
export function percentiles(cohort, mine) {
  if (cohort.length < MIN_COHORT) return null;
  const out = {};
  for (const k of PERCENTILE_METRICS) if (Number.isFinite(mine[k])) out[k] = percentile(cohort.map((u) => u[k]), mine[k]);
  return out;
}
