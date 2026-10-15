// Explore filter state and rules (ExploreView.swift / Areas.swift counterparts). Pure apart from localStorage, so it is unit-tested.
import { ls } from './util.js';

export const TIERS = ['Base', 'Black', 'Epic', 'Wellness', 'Free'];
const DEFAULTS = { tab: 'studios', q: '', favs: false, free: false, map: false, tiers: [], solo: false, areaId: null };

/** Saved state (any older shape) -> full state. `free` is "Hide full classes". */
export function loadState(saved) {
  const s = Object.assign({}, DEFAULTS, saved && typeof saved === 'object' ? saved : {});
  s.tiers = Array.isArray(s.tiers) ? s.tiers.filter((t) => TIERS.includes(t)) : [];
  s.areaId = typeof s.areaId === 'string' ? s.areaId : null;
  s.q = '';
  return s;
}
export const ex = loadState(ls.get('bruce.explore', null));
export const saveEx = () => ls.set('bruce.explore', { tab: ex.tab, favs: ex.favs, free: ex.free, map: ex.map, tiers: ex.tiers, solo: ex.solo, areaId: ex.areaId, q: '' });

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
export const classPasses = (c, studio, f, favs, area) => (!f.favs || favs.has(c.studio_id)) && (!f.free || c.available_spots > 0) && studioInArea(studio, area);

/** Badge on the Filter chip (iOS activeFilterCount). */
export const activeCount = (f, hasCategory, area) => f.tiers.length + (hasCategory ? 1 : 0) + [f.favs, f.solo, f.free, !!area].filter(Boolean).length;
export function clearFilters(f) { f.tiers = []; f.favs = false; f.solo = false; f.free = false; f.areaId = null; }
