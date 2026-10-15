// Pure "For you" scoring (no DOM, runs under Node). Ranks the next two days' classes from the class lists the app
// already loads, using the user's past visits (titles, categories, studios, time slots), friends' bookings and the
// travel time from saved places. Travel time is a distance estimate: straight line x a detour factor at a per-mode
// speed plus a fixed overhead (parking, waiting). Places never leave the device.

import { local } from './visits.js';
import { byStart } from './util.js';

export const MODES = {
  walk: { kmh: 4.8, detour: 1.3, fixed: 0, icon: 'walk', label: 'Walk' },
  bike: { kmh: 15, detour: 1.25, fixed: 1, icon: 'bike', label: 'Bike' },
  transit: { kmh: 22, detour: 1.4, fixed: 7, icon: 'tram', label: 'Transit' },
  car: { kmh: 26, detour: 1.35, fixed: 5, icon: 'car', label: 'Car' },
};
export const DEFAULT_PREFS = { mode: 'bike', maxDetour: 15, workFrom: '11:30', workTo: '13:30', useFriends: true };

export function metres(a, b) {
  const R = 6371000, r = Math.PI / 180;
  const x = Math.sin((b.lat - a.lat) * r / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin((b.lon - a.lon) * r / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}
/** Minutes from `a` to `b` ({lat, lon}) by `mode`. Transit is never slower than walking. */
export function travelMinutes(a, b, mode) {
  const est = (m) => m.fixed + (metres(a, b) / 1000) * m.detour / m.kmh * 60;
  const m = MODES[mode] || MODES.bike;
  const t = mode === 'transit' ? Math.min(est(m), est(MODES.walk)) : est(m);
  return Math.max(1, Math.round(t));
}
/** Extra minutes for stopping at `p` on the way from `a` to `b`. */
export function detourMinutes(a, b, p, mode) {
  return Math.max(0, travelMinutes(a, p, mode) + travelMinutes(p, b, mode) - travelMinutes(a, b, mode));
}

/** Time slot names used for "Lunch slot you use". */
export function slotOf(hour, weekday) {
  const part = hour < 9 ? 'early' : hour < 11 ? 'morning' : hour < 14 ? 'lunch' : hour < 17 ? 'afternoon' : hour < 20 ? 'evening' : 'late';
  return (weekday >= 5 ? 'weekend ' : '') + part;
}
const SLOT_TEXT = { early: 'Early slot you use', morning: 'Morning slot you use', lunch: 'Lunch slot you use', afternoon: 'Afternoon slot you use', evening: 'Evening slot you use', late: 'Late slot you use' };
const minutesOf = (hhmm) => { const [h, m] = String(hhmm || '0:0').split(':').map(Number); return h * 60 + (m || 0); };
const norm = (s) => String(s || '').trim().toLowerCase();

/** What the user usually does, from visits (visits.js) of the last `days` days. */
export function profile(visits, now, days) {
  const since = +new Date(now) - (days || 365) * 86400000;
  const recent = visits.filter((v) => +new Date(v.at) >= since && +new Date(v.at) <= +new Date(now));
  const p = { n: recent.length, classes: 0, titles: new Map(), titleStudio: new Map(), cats: new Map(), studios: new Map(), slots: new Map() };
  const inc = (m, k) => m.set(k, (m.get(k) || 0) + 1);
  for (const v of recent) {
    inc(p.studios, v.studioId);
    inc(p.slots, slotOf(v.hour, v.weekday));
    if (v.kind !== 'class') continue;
    p.classes++;
    inc(p.titles, norm(v.title));
    inc(p.titleStudio, norm(v.title) + '|' + v.studioId);
    v.categories.forEach((c) => inc(p.cats, c));
  }
  return p;
}

const pluralTitle = (title, n) => (n === 1 || /s$/i.test(title) ? title : title + 's');

/**
 * Scores and explains classes. input = {
 *   classes: Bruce classes, visits: visits.js visits, now, zone,
 *   booked: Set of class ids the user booked, friends: [{userId, name, classId}],
 *   studios: Map id -> {lat, lon, name}, catTitle: (id) -> "Yoga",
 *   places: [{kind: "home" | "work" | "other", lat, lon, workdays: [0..6]}], prefs: DEFAULT_PREFS,
 *   hours: 52 (how far ahead), limit: 8 }
 * -> [{class, score, match (0-99), reasons: [{icon, text, tone?, faces?}], friends: [userId]}], best first.
 */
export function recommend(input) {
  const now = +new Date(input.now || Date.now());
  const zone = input.zone;
  const prefs = Object.assign({}, DEFAULT_PREFS, input.prefs || {});
  const prof = profile(input.visits || [], now, 365);
  const home = (input.places || []).find((p) => p.kind === 'home' && p.lat != null);
  const work = (input.places || []).find((p) => p.kind === 'work' && p.lat != null);
  const studios = input.studios || new Map();
  const friendsBy = new Map();
  if (prefs.useFriends) for (const f of input.friends || []) {
    if (!friendsBy.has(f.classId)) friendsBy.set(f.classId, []);
    if (!friendsBy.get(f.classId).some((x) => x.userId === f.userId)) friendsBy.get(f.classId).push(f);
  }
  const horizon = now + (input.hours || 52) * 3600000;
  const mode = MODES[prefs.mode] ? prefs.mode : 'bike';
  const out = [];
  for (const c of input.classes || []) {
    const start = +new Date(c.start_time);
    if (!(start > now + 10 * 60000 && start < horizon)) continue;
    if (c.canceled || c.deleted === true || c.deleted_at || c.opening) continue;
    if (input.booked && input.booked.has(c.id)) continue;
    if (c.bookable_latest_time && +new Date(c.bookable_latest_time) < now) continue;
    if (c.available_spots != null && c.available_spots <= 0) continue;
    const l = local(c.start_time, zone);
    const title = c.title || '';
    const st = studios.get(c.studio_id) || null;
    let s = 4;
    const reasons = [];
    // Where you are around then.
    if (st && st.lat != null) {
      const startMin = l.hour * 60 + l.minute;
      const workday = work && (work.workdays || [0, 1, 2, 3, 4]).includes(l.weekday);
      if (workday && startMin >= minutesOf(prefs.workFrom) && startMin < minutesOf(prefs.workTo)) {
        const t = travelMinutes(work, st, mode);
        s += t <= 10 ? 26 : t <= 20 ? 14 : t <= 30 ? 2 : -25;
        if (t <= 30) reasons.push({ icon: mode === 'walk' ? 'walk' : 'brief', text: t + ' min ' + (mode === 'walk' ? 'walk ' : '') + 'from work' });
      } else if (workday && home && startMin >= minutesOf(prefs.workTo) && l.hour < 22) {
        const d = detourMinutes(work, home, st, mode);
        if (d <= prefs.maxDetour) { s += d <= 5 ? 28 : 18; reasons.push({ icon: MODES[mode].icon, text: 'On your way home · +' + d + ' min' }); }
        else if (home) { const t = travelMinutes(home, st, mode); s += t <= 10 ? 14 : t <= 20 ? 6 : -20; }
      } else if (home) {
        const t = travelMinutes(home, st, mode);
        s += t <= 10 ? 24 : t <= 20 ? 14 : t <= 30 ? 2 : -25;
        if (t <= 30) reasons.push({ icon: MODES[mode].icon, text: t + ' min ' + (mode === 'walk' ? 'walk ' : '') + 'from home' });
      }
    }
    // What you usually do.
    const tn = prof.titles.get(norm(title)) || 0;
    const tsn = prof.titleStudio.get(norm(title) + '|' + c.studio_id) || 0;
    if (tn >= 2) {
      s += Math.min(30, 8 + tn * 3);
      reasons.push({ icon: 'history', text: tsn >= 2 ? 'You did ' + tsn + ' ' + pluralTitle(title, tsn) + ' here' : 'You did ' + tn + ' ' + pluralTitle(title, tn) });
    }
    const cats = (c.class_categories || []).map((x) => String(x.category_id));
    const best = cats.map((k) => [k, prof.cats.get(k) || 0]).sort((a, b) => b[1] - a[1])[0];
    if (best && best[1] >= 3 && prof.classes) {
      const share = best[1] / prof.classes;
      s += Math.min(20, 6 + share * 30);
      const name = input.catTitle && input.catTitle(best[0]);
      if (name && tn < 2) reasons.push({ icon: 'history', text: 'You do ' + name + ' often' });
    }
    const sn = prof.studios.get(c.studio_id) || 0;
    if (sn >= 2) {
      s += Math.min(12, sn * 1.5);
      if (!reasons.some((r) => r.icon === 'history')) reasons.push({ icon: 'history', text: 'You go here often' });
    }
    const slot = slotOf(l.hour, l.weekday);
    const slotN = prof.slots.get(slot) || 0;
    if (slotN >= 3 && prof.n) {
      s += Math.min(15, (slotN / prof.n) * 45);
      if (slotN / prof.n >= 0.2) reasons.push({ icon: 'clock', text: SLOT_TEXT[slot.replace('weekend ', '')] });
    }
    // Friends going.
    const going = friendsBy.get(c.id) || [];
    if (going.length) {
      s += Math.min(32, going.length * 16);
      reasons.push({ icon: 'friends', faces: going.map((f) => f.userId), text: going.length === 1 ? (going[0].name || 'A friend') + ' booked' : going.length <= 2 && going.every((f) => f.name) ? going.map((f) => f.name).join(', ') : going.length + ' friends going' });
    }
    // Few spots left (shown, not scored).
    if (c.available_spots != null && c.available_spots > 0 && c.available_spots <= 3) reasons.push({ tone: 'lime', text: c.available_spots + (c.available_spots === 1 ? ' spot left' : ' spots left') });
    const match = Math.max(20, Math.min(99, Math.round(100 * (1 - Math.exp(-s / 42)))));
    out.push({ class: c, score: s, match, reasons, friends: going.map((f) => f.userId) });
  }
  out.sort((a, b) => b.score - a.score || byStart(a.class, b.class));
  // One pick per class title at a studio, so a recurring class does not fill the list.
  const seen = new Set();
  const picks = out.filter((r) => { const k = norm(r.class.title) + '|' + r.class.studio_id; if (seen.has(k)) return false; seen.add(k); return true; });
  return picks.slice(0, input.limit || 8);
}
