// Explore filter state and rules (ExploreView.swift / Areas.swift counterparts). Pure apart from localStorage, so it is unit-tested.
import { ls } from './util.js';

export const TIERS = ['Base', 'Black', 'Epic', 'Wellness', 'Free'];
const DEFAULTS = { tab: 'studios', q: '', favs: false, free: false, map: false, tiers: [], solo: false, areaId: null, slots: [], durs: [], sort: 'start', bookable: false };
/** Classes: time of day (DaySlot in Recommendations.swift), duration bands, sort orders (ClassFilters.swift). */
export const SLOTS = ['early', 'morning', 'lunch', 'afternoon', 'evening', 'late'];
export const SLOT_TITLES = { early: 'Early', morning: 'Morning', lunch: 'Lunch', afternoon: 'Afternoon', evening: 'Evening', late: 'Late' };
export const DURS = ['short', 'medium', 'long'];
export const DUR_TITLES = { short: '≤ 45 min', medium: '45–60 min', long: '60+ min' };
export const SORTS = ['start', 'distance', 'travel', 'spots'];
export const SORT_TITLES = { start: 'Start', distance: 'Distance', travel: 'Travel time', spots: 'Spots left' };

/** Saved state (any older shape) -> full state. `free` is "Hide full classes". */
export function loadState(saved) {
  const s = Object.assign({}, DEFAULTS, saved && typeof saved === 'object' ? saved : {});
  s.tiers = Array.isArray(s.tiers) ? s.tiers.filter((t) => TIERS.includes(t)) : [];
  s.areaId = typeof s.areaId === 'string' ? s.areaId : null;
  s.slots = Array.isArray(s.slots) ? s.slots.filter((x) => SLOTS.includes(x)) : [];
  s.durs = Array.isArray(s.durs) ? s.durs.filter((x) => DURS.includes(x)) : [];
  s.sort = SORTS.includes(s.sort) ? s.sort : 'start';
  s.bookable = !!s.bookable;
  s.q = '';
  return s;
}
export const ex = loadState(ls.get('bruce.explore', null));
export const saveEx = () => ls.set('bruce.explore', { tab: ex.tab, favs: ex.favs, free: ex.free, map: ex.map, tiers: ex.tiers, solo: ex.solo, areaId: ex.areaId, slots: ex.slots, durs: ex.durs, sort: ex.sort, bookable: ex.bookable, q: '' });

/** Saved areas (named polygons, per city), device-local like the iOS app's. */
export const areas = ls.get('bruce.areas', []).filter((a) => a && a.id && Array.isArray(a.points) && a.points.length >= 3);
export const saveAreas = () => ls.set('bruce.areas', areas);
export const cityAreas = (list, cityId) => list.filter((a) => a.cityId === cityId);
/** The selected area, only when it belongs to the current city. */
export const selectedArea = (list, id, cityId) => (id && list.find((a) => a.id === id && a.cityId === cityId)) || null;

/** Ray casting in lat/lon (fine at city scale). `points`: [{lat, lon}]. */
export function inPolygon(points, lat, lon) {
  if (!points || points.length < 3) return false;
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const a = points[i], b = points[j];
    if ((a.lat > lat) !== (b.lat > lat) && lon < ((b.lon - a.lon) * (lat - a.lat)) / (b.lat - a.lat) + a.lon) inside = !inside;
  }
  return inside;
}
/** Studios without coordinates are never inside. */
export const studioInArea = (s, area) => !area || !!(s && s.lat && s.lon && inPolygon(area.points, s.lat, s.lon));
/** Rectangle polygon for a visible map region: {north, south, east, west}. */
export const rectangle = (b) => [{ lat: b.north, lon: b.west }, { lat: b.north, lon: b.east }, { lat: b.south, lon: b.east }, { lat: b.south, lon: b.west }];

/** Studio access: any chosen tier gives access (limit -1 means "none" for that tier). */
export function tierOK(s, tiers) {
  if (!tiers || !tiers.length) return true;
  const items = (s && s.limits) || [];
  return tiers.some((t) => {
    if (t === 'Wellness') return ((s && s.label) || '').toUpperCase() === 'WELLNESS';
    const it = items.find((x) => (x.label || '').toUpperCase() === t.toUpperCase());
    return !!it && it.limit != null && it.limit !== -1;
  });
}
/** Studios tab rules (not text/category): favourites, access tiers, solo training, area. */
export const studioPasses = (s, f, favs, area) => (!f.favs || favs.has(s.id)) && tierOK(s, f.tiers) && (!f.solo || s.openings === true) && studioInArea(s, area);
/** Classes tab rules: favourite studios, hide full classes, area (like iOS, tiers and solo only filter studios). */
/** Minutes after midnight -> slot name (the same steps as DaySlot). */
export const slotOfMinute = (m) => (m < 8 * 60 + 30 ? 'early' : m < 11 * 60 ? 'morning' : m < 14 * 60 ? 'lunch' : m < 17 * 60 ? 'afternoon' : m < 20 * 60 ? 'evening' : 'late');
export const durBand = (min) => (min <= 45 ? 'short' : min <= 60 ? 'medium' : 'long');
/** Open for booking right now: window open, not closed, a spot left, not started. */
export function bookableNow(c, now) {
  const s = Date.parse(c.start_time);
  if (!(s > now) || c.deleted || c.canceled) return false;
  if (c.available_spots != null && c.available_spots <= 0) return false;
  const opens = c.bookable_earliest_time ? Date.parse(c.bookable_earliest_time) : c.bookable_earliest != null ? s - c.bookable_earliest * 1000 : null;
  if (opens != null && opens > now) return false;
  if (c.bookable_latest_time && Date.parse(c.bookable_latest_time) < now) return false;
  return true;
}
/**
 * `o` (optional): {now, minuteOf(c) -> minutes after midnight in the city's zone, minutes(c) -> class length} for
 * the time-of-day, duration and bookable-now rules; without it those rules are skipped.
 */
export function classPasses(c, studio, f, favs, area, o) {
  if ((f.favs && !favs.has(c.studio_id)) || (f.free && !(c.available_spots > 0)) || !studioInArea(studio, area)) return false;
  if (!o) return true;
  if (f.slots && f.slots.length && !f.slots.includes(slotOfMinute(o.minuteOf(c)))) return false;
  if (f.durs && f.durs.length) { const d = o.minutes(c); if (d == null || !f.durs.includes(durBand(d))) return false; }
  if (f.bookable && !bookableNow(c, o.now)) return false;
  return true;
}
/** Sorts a day's classes: start, distance (metres(studioId)), travel (minutes(studioId)) or spots left; unknown last. */
export function sortClasses(list, f, by) {
  const start = (a, b) => a.start_time.localeCompare(b.start_time);
  const num = (fn) => (a, b) => { const x = fn(a), y = fn(b); return (x == null ? 1e12 : x) - (y == null ? 1e12 : y) || start(a, b); };
  if (f.sort === 'distance') return list.slice().sort(num((c) => by.distance(c.studio_id)));
  if (f.sort === 'travel') return list.slice().sort(num((c) => by.travel(c.studio_id)));
  if (f.sort === 'spots') return list.slice().sort(num((c) => (c.available_spots == null ? 1e9 : c.available_spots <= 0 ? 1e10 : -c.available_spots)));
  return list.slice().sort(start);
}

/** Badge on the Filter chip (iOS activeFilterCount). */
export const activeCount = (f, hasCategory, area) => f.tiers.length + (hasCategory ? 1 : 0) + [f.favs, f.solo, f.free, !!area, f.slots && f.slots.length, f.durs && f.durs.length, f.sort && f.sort !== 'start', f.bookable].filter(Boolean).length;
export function clearFilters(f) { f.tiers = []; f.favs = false; f.solo = false; f.free = false; f.areaId = null; f.slots = []; f.durs = []; f.sort = 'start'; f.bookable = false; }
