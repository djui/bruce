// Pure visit logic (no DOM, runs under Node): local calendar days in the city's time zone and the deduped visit list
// that goals, For you and Wrapped count from the GET /booking history. Same rule as the server (CONTRACT.md "Visit
// counting rule"): one visit per class; a drop-in within 3 hours of a class at the same studio on the same day, or a
// second drop-in there that day, is the same visit. A drop-in counts 60 minutes.

export const ZONE = 'Europe/Stockholm';
const fmts = new Map();
const WEEKDAY = { Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4, Sat: 5, Sun: 6 };

/** {day: "YYYY-MM-DD", month: "YYYY-MM", year, hour, minute, weekday (0 = Monday)} of an instant in `zone`. */
export function local(d, zone) {
  const z = zone || ZONE;
  let f = fmts.get(z);
  if (!f) {
    f = new Intl.DateTimeFormat('en-GB', { timeZone: z, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', weekday: 'short', hourCycle: 'h23' });
    fmts.set(z, f);
  }
  const p = {};
  for (const x of f.formatToParts(new Date(d))) p[x.type] = x.value;
  return { day: p.year + '-' + p.month + '-' + p.day, month: p.year + '-' + p.month, year: +p.year, hour: +p.hour % 24, minute: +p.minute, weekday: WEEKDAY[p.weekday] };
}
export function addDays(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n, 12)).toISOString().slice(0, 10);
}
/** 0 = Monday. */
export const weekdayOf = (key) => (new Date(key + 'T12:00:00Z').getUTCDay() + 6) % 7;
/** The Monday of the week that holds `key`. */
export const weekOf = (key) => addDays(key, -weekdayOf(key));
export function daysInMonth(month) {
  const [y, m] = month.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}
export function addMonths(month, n) {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return d.toISOString().slice(0, 7);
}
/** Whole days from `a` to `b` (both "YYYY-MM-DD"). */
export const daysBetween = (a, b) => Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 86400000);

/** A drop-in or solo-training visit (no class, or a gym "opening" slot) rather than a class. */
export function isDropin(b) {
  const c = b.class;
  return b.class_id == null ? !(c && c.id && !c.opening) : !!(c && c.opening);
}

/**
 * Visits from raw bookings, oldest first. Each: {id, at, day, month, hour, weekday, kind: "class" | "dropin", classId,
 * studioId, title, categories: ["2", ...], minutes, checkedIn}.
 * `checkedInOnly` (goals): only checked-in bookings count. Otherwise (challenges, Wrapped) everything counts: class
 * bookings whose class has started, and check-ins.
 */
export function visitsFrom(bookings, opts) {
  const o = opts || {};
  const now = o.now != null ? +new Date(o.now) : Date.now();
  const zone = o.zone || ZONE;
  const raw = [];
  for (const b of bookings || []) {
    if (!b || b.deleted || b.deleted_at || b.canceled) continue;
    const c = b.class || null;
    if (c && (c.canceled || c.deleted === true || c.deleted_at)) continue;
    const dropin = isDropin(b);
    const checkedIn = !!b.checked_in_at;
    if (o.checkedInOnly && !checkedIn) continue;
    const at = dropin ? (b.checked_in_at || (c && c.start_time)) : ((c && c.start_time) || b.checked_in_at);
    if (!at) continue;
    if (!checkedIn && (dropin || +new Date(at) > now)) continue;   // checked in early for a class that starts soon: counts
    const l = local(at, zone);
    const minutes = !dropin && c && c.start_time && c.end_time ? Math.max(0, Math.round((new Date(c.end_time) - new Date(c.start_time)) / 60000)) : 60;
    raw.push({
      id: b.id, at: new Date(at).toISOString(), day: l.day, month: l.month, hour: l.hour, weekday: l.weekday,
      kind: dropin ? 'dropin' : 'class', classId: dropin ? null : (b.class_id || (c && c.id) || null),
      studioId: b.studio_id || (c && (c.studio_id || (c.studio && c.studio.id))) || null,
      title: dropin ? 'Solo training' : ((c && c.title) || 'Class'),
      categories: dropin ? [] : ((c && c.class_categories) || []).map((x) => String(x.category_id)),
      minutes, checkedIn,
    });
  }
  raw.sort((a, b) => a.at.localeCompare(b.at));
  const out = [];
  const classIds = new Set();
  for (const v of raw) {
    if (v.kind !== 'class') continue;
    if (v.classId != null) { if (classIds.has(v.classId)) continue; classIds.add(v.classId); }
    out.push(v);
  }
  const classes = out.slice();
  const dropDays = new Set();
  for (const v of raw) {
    if (v.kind !== 'dropin') continue;
    const k = v.studioId + '|' + v.day;
    if (dropDays.has(k)) continue;
    const t = +new Date(v.at);
    if (classes.some((c) => c.studioId === v.studioId && c.day === v.day && Math.abs(+new Date(c.at) - t) <= 3 * 3600000)) continue;
    dropDays.add(k);
    out.push(v);
  }
  return out.sort((a, b) => a.at.localeCompare(b.at));
}

/** Count per key, as a Map sorted by count (desc). */
export function tally(items, keyOf) {
  const m = new Map();
  for (const it of items) {
    const k = keyOf(it);
    if (k == null) continue;
    m.set(k, (m.get(k) || 0) + 1);
  }
  return new Map([...m.entries()].sort((a, b) => b[1] - a[1]));
}
export const first = (m) => (m && m.size ? [...m.entries()][0] : null);
