// "First visit here?" and the recent rating (Shared/BruceCore/FirstVisit.swift). Built only from fields the page
// already loaded (class check-in minutes, studio door type, facilities, the review list) and our own policy wording.
// Pure (tests in test/logic.test.js); the markup lives in detail.js.

export const LATE_CHECK_IN = 'Late check-in costs 1 strike';
export const RECENT_DAYS = 90;

/** `r` is store.js rules(c) for a class page (null on the studio page); `timeText(ms)` renders "17:00". */
export function firstVisitInfo(studio, c, r, timeText) {
  const s = studio || {};
  const info = { facilities: (s.studio_facilities || []).map((f) => f.facility && f.facility.title).filter(Boolean) };
  if (c && r) {
    info.checkIn = 'Check in ' + timeText(r.checkInFrom) + '–' + timeText(r.lateCheckIn);
    info.checkInNote = 'Opens ' + (c.early_check_in_minutes != null ? c.early_check_in_minutes : 30) + ' min before, closes ' + (c.late_check_in_minutes != null ? c.late_check_in_minutes : 5) + ' min before';
  } else {
    info.checkIn = 'Check in before the class starts';
    info.checkInNote = 'Usually opens 30 min before and closes 5–15 min before; each class page shows its window';
  }
  const door = (s.integration_door_type || '').toLowerCase();
  if (door === 'parakey' || s.parakey_config) info.door = 'Door opens from the Parakey app, linked to your account at check-in';
  else if ((s.status || '').toLowerCase() === 'live' && (s.qr_code_id || s.integration_type)) info.door = "Scan the studio's QR code in the app to check in";
  else info.door = null;
  return info;
}

/** Average of the rated reviews from the last `days` days, or null: {average, count, days}. */
export function recentRating(reviews, days, now) {
  const since = (now || Date.now()) - (days || RECENT_DAYS) * 86400000;
  const rated = (reviews || []).filter((r) => r.rating > 0 && r.created_at && Date.parse(r.created_at) >= since).map((r) => r.rating);
  if (!rated.length) return null;
  return { average: rated.reduce((a, b) => a + b, 0) / rated.length, count: rated.length, days: days || RECENT_DAYS };
}

/** "Rated lower lately." / "Rated higher lately." from 5 recent ratings 0.3 stars away from the all-time average (x100). */
export function ratingTrend(allTime, recent) {
  if (!allTime || !recent || recent.count < 5) return null;
  const diff = recent.average - allTime / 100;
  return diff <= -0.3 ? 'Rated lower lately.' : diff >= 0.3 ? 'Rated higher lately.' : null;
}

/** Studio ids with a check-in in the history (plus today's checked-in bookings); null until the history is known. */
export function visitedStudios(history, bookings) {
  if (!history) return null;
  const ids = new Set(history.filter((v) => v.checked_in_at).map((v) => v.studio_id || (v.class && v.class.studio_id)).filter(Boolean));
  (bookings || []).forEach((b) => { if (b.checked_in_at && (b.studio_id || (b.class && b.class.studio_id))) ids.add(b.studio_id || b.class.studio_id); });
  return ids;
}
