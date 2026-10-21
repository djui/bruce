// Milestones and "New to you" (Shared/BruceCore/Milestones.swift). Pure (tests in test/logic.test.js); the Home
// markup is in views.js. `visits` are the deduped check-ins from visits.js visitsFrom(history, {checkedInOnly: true}).

import { weekStreak } from './goals.js';

export const CLASS_STEPS = [10, 25, 50, 100, 250, 500, 1000];
export const STUDIO_STEPS = [5, 10, 25, 50];
export const STREAK_STEPS = [4, 8, 12, 26, 52];
export const FRESH_DAYS = 30;

const ordinal = (n) => { const s = n % 100; return n + ((s >= 11 && s <= 13) ? 'th' : n % 10 === 1 ? 'st' : n % 10 === 2 ? 'nd' : n % 10 === 3 ? 'rd' : 'th'); };
const fmtDay = (day) => new Date(day + 'T12:00:00Z').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });

/** Every milestone reached up to `today` (YYYY-MM-DD), newest first: {kind, value, title, detail, icon, day, key}. */
export function reached(visits, today, titleOf, studioNameOf) {
  const vs = (visits || []).filter((v) => v.day <= today).slice().sort((a, b) => a.day.localeCompare(b.day) || a.at.localeCompare(b.at));
  const out = [];
  const classes = vs.filter((v) => v.kind === 'class');
  for (const n of CLASS_STEPS) {
    if (classes.length < n) break;
    const v = classes[n - 1];
    const studios = new Set(classes.slice(0, n).map((x) => x.studioId).filter(Boolean)).size;
    out.push({ kind: 'classes', value: n, title: n + ' classes', detail: 'Number ' + n + ' was ' + v.title + ' on ' + fmtDay(v.day) + '. ' + studios + ' studio' + (studios === 1 ? '' : 's') + ' so far.', icon: 'run', day: v.day, key: 'classes-' + n });
  }
  const seen = [], firstAt = {};
  for (const v of vs) if (v.studioId && !seen.includes(v.studioId)) { seen.push(v.studioId); firstAt[v.studioId] = v; }
  for (const n of STUDIO_STEPS) {
    if (seen.length < n) break;
    const s = seen[n - 1], v = firstAt[s];
    out.push({ kind: 'studios', value: n, title: n + ' studios', detail: 'Your ' + ordinal(n) + ' was ' + ((studioNameOf && studioNameOf(s)) || 'a new studio') + ' on ' + fmtDay(v.day) + '.', icon: 'building', day: v.day, key: 'studios-' + n });
  }
  const catFirst = {};
  for (const v of classes) for (const c of new Set(v.categories)) if (!catFirst[c]) catFirst[c] = v;
  const fifth = classes[4] ? classes[4].day + classes[4].at : '';
  for (const [c, v] of Object.entries(catFirst)) {
    if (v.day + v.at <= fifth) continue;
    const t = (titleOf && titleOf(c)) || 'a new category';
    out.push({ kind: 'category', value: +c, title: 'New: ' + t, detail: 'Your first ' + t + ' class was ' + v.title + ' on ' + fmtDay(v.day) + '.', icon: 'spark', day: v.day, key: 'category-' + c });
  }
  const streak = weekStreak(vs, today);
  if (streak > 0) {
    const last = vs[vs.length - 1];
    const monday = (day) => { const d = new Date(day + 'T12:00:00Z'); const wd = (d.getUTCDay() + 6) % 7; d.setUTCDate(d.getUTCDate() - wd); return d.toISOString().slice(0, 10); };
    const addWeeks = (day, n) => { const d = new Date(day + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + 7 * n); return d.toISOString().slice(0, 10); };
    const top = monday(last.day) < monday(today) ? monday(last.day) : monday(today);
    const from = addWeeks(top, -(streak - 1));
    for (const n of STREAK_STEPS) {
      if (streak < n) break;
      out.push({ kind: 'streak', value: n, title: n + '-week streak', detail: 'A visit every week since ' + fmtDay(from) + '.', icon: 'flame', day: addWeeks(from, n - 1), key: 'streak-' + n + '-' + from });
    }
  }
  return out.sort((a, b) => b.day.localeCompare(a.day));
}

/** The newest milestone of the last FRESH_DAYS days that was not dismissed yet. */
export function fresh(list, seen, today) {
  const since = new Date(new Date(today + 'T12:00:00Z').getTime() - FRESH_DAYS * 86400000).toISOString().slice(0, 10);
  return (list || []).find((m) => !seen.has(m.key) && m.day >= since) || null;
}

/** Whether the plan (tier label, e.g. "BASE") includes a studio, from its visit_limit items as the Explore filter reads them. */
export function includedInPlan(studio, tier) {
  const items = studio.limits;
  if (!Array.isArray(items)) return true;
  const mine = items.find((i) => String(i.label || '').toUpperCase() === String(tier || 'BASE').toUpperCase());
  return !mine || mine.limit !== -1;
}

/**
 * Studios never visited, in the plan, in categories the user does (`likedTitles`, lowercase) or within 3 km of
 * `here` ({lat, lon}); `metres(a, b)` measures. Nearest first, max `limit`.
 */
export function newToYou(studios, visitedIds, likedTitles, tier, here, metres, limit) {
  const liked = new Set((likedTitles || []).map((t) => String(t).toLowerCase()));
  const out = [];
  for (const s of studios || []) {
    if (visitedIds.has(s.id) || !includedInPlan(s, tier)) continue;
    if (!(s.hasClasses || s.openings)) continue;
    const shared = (s.cats || []).find((c) => liked.has(String(c).toLowerCase()));
    const d = here && s.lat != null ? metres(here.lat, here.lon, s.lat, s.lon) : null;
    if (!shared && !(d != null && d <= 3000)) continue;
    out.push({ studio: s, distance: d, reason: shared ? shared + ', which you do' : 'near you', rank: (shared ? 0 : 1e6) + (d == null ? 1e5 : d) });
  }
  return out.sort((a, b) => a.rank - b.rank).slice(0, limit || 8);
}
