// App state and loaders, in the spirit of AppModel.swift: one shared store that views read and re-render from.
import { Bruce, Autobook, Server, session, DEFAULT_API } from './api.js';
import { ls, setZone, dayKey, todayKey, getZone, byStart, byInstant, onDay, time, ruleTime, instructor, slug } from './util.js';
import { icsFor, icsFileName, feedUrl } from './calendar.js';
import { visitsFrom } from './visits.js';
import { remindPayload, goalTitle } from './goals.js';
import { DEFAULT_PREFS } from './recommend.js';
import { decode as decodeRaces, entries as raceEntries, upcoming as upcomingRaces, keyOf as raceKey, priceReminder, mergeFeed, decodeClubs } from './races.js';
import { makePlan, count as planCount, category as planCategory } from './raceplan.js';
import { DEMO_RACES, DEMO_MY_RACES, DEMO_TRAINING_CLUBS } from './demo.js';
import { sharesGoing } from './crews.js';

const STUDIO_CACHE_MS = 12 * 3600 * 1000;
const RACES_CACHE_MS = 6 * 3600 * 1000;

/** Doors whose QR ids are known (Presets.swift `KnownDoors`), plus doors learned from the user's own scans. */
const KNOWN_DOORS = { 1724: { major: '13994', doorId: '118661' }, 1764: { major: '13816', doorId: '118551' } };

export const S = {
  auth: ls.get('bruce.session', null),          // {token, userId, demo}
  settings: Object.assign({ cityId: 1, apiBase: DEFAULT_API }, ls.get('bruce.settings', {})),
  cities: [], categories: [], home: null,
  studios: new Map(),                            // id -> studio list entry (slim)
  studioDetails: new Map(),                      // id -> full studio
  classDetails: new Map(),                       // id -> class
  bookings: new Map(),                           // class id -> booking (with class); drop-ins keyed by "s<id>"
  standbys: new Map(),                           // class id -> standby
  watches: new Set(),                            // class ids the auto-book server books when a waitlist spot frees up
  openings: new Set(),                           // one-off class ids the server books the moment their window opens
  bookmarks: new Map(),                          // class id -> bookmark
  favorites: new Map(),                          // studio id -> favorite id
  friends: [], friendsBookings: [], notifications: [], reviewable: [], visits: null,
  history: null,                                 // every booking of the user (GET /booking, all pages), raw
  challenges: null,                              // {challenges, usesBruce} from our server
  limits: [], user: null, membership: null, block: null,
  classCache: new Map(),                         // "city:day" -> {at, classes}
  listeners: new Set(),
  seenNotifications: ls.get('bruce.seenNotifications', 0),
  skippedReviews: new Set(ls.get('bruce.skippedReviews', [])),
  learnedDoors: ls.get('bruce.doors', {}),
  races: null, racesError: null, racesLoading: null,   // the race catalog (races.js), null until read
  trainingClubs: [],                                   // studios with an organiser's training status (the catalog's trainingClubs)
  raceGoing: { going: {}, sharing: false, mine: [] }, raceGoingAt: 0, raceGoingLoading: null,   // friends going (crews.js)
};

export const emit = () => S.listeners.forEach((f) => { try { f(); } catch (e) { console.error(e); } });
export const saveSettings = () => ls.set('bruce.settings', S.settings);
export const isDemo = () => !!(S.auth && S.auth.demo);
export const loggedIn = () => !!S.auth;

export function city() {
  return S.cities.find((c) => c.id === S.settings.cityId) ||
    { id: S.settings.cityId, name: 'Stockholm', code: 'STO', time_zone: 'Europe/Stockholm', coordinates: { latitude: 59.3293, longitude: 18.0686 }, country: { code: 'SE' } };
}
const country = () => ((city().country && city().country.code) || 'SE').toUpperCase();

export function applySession() {
  session.token = S.auth && S.auth.token;
  session.userId = S.auth && S.auth.userId;
  session.demo = isDemo();
  session.base = S.settings.apiBase || DEFAULT_API;
  session.server = S.settings.autoBookServer || null;
}
export function setAuth(a) {
  S.auth = a;
  if (a) ls.set('bruce.session', a); else ls.del('bruce.session');
  applySession();
}
export function clearData() {
  ['studios', 'studioDetails', 'classDetails', 'bookings', 'standbys', 'watches', 'openings', 'bookmarks', 'favorites', 'classCache'].forEach((k) => S[k].clear());
  Object.assign(S, { raceGoing: { going: {}, sharing: false, mine: [] }, raceGoingAt: 0 });
  Object.assign(S, { history: null, historyLoading: null, challenges: null, friends: [], friendsBookings: [], notifications: [], reviewable: [], visits: null, limits: [], user: null, membership: null, block: null, home: null, studiosLoading: null });
}

export function slimStudio(s) {
  const a = (s.studio_addresses || []).map((x) => x.address).filter(Boolean)[0] || {};
  return {
    id: s.id, name: s.name, vicinity: s.vicinity, photo: s.photo, city_id: s.city_id, label: s.label, rating: s.rating, qr: s.qr_code_id,
    cats: (s.studio_categories || []).map((c) => c.category && c.category.title).filter(Boolean),
    address: a.address, lat: a.latitude, lon: a.longitude, door: s.integration_door_type, openings: s.has_openings,
    limits: s.visit_limit && s.visit_limit.items, hasClasses: s.has_classes,
  };
}
export const studio = (id) => S.studios.get(id) || (S.studioDetails.has(id) ? slimStudio(S.studioDetails.get(id)) : null);
export const studioName = (id, fallback) => (studio(id) || {}).name || (fallback && fallback.name) || 'Studio';
export const isWellness = (id) => (studio(id) || {}).label === 'WELLNESS';
export const cityStudios = () => [...S.studios.values()].filter((s) => s.city_id === S.settings.cityId);
/** The country of the member's Bruce city ("SE"), for Home's Upcoming races (races.js). */
export function homeCountry() { const c = city().country && city().country.code; return c && c.length === 2 ? c.toUpperCase() : (S.settings.cityId === 1 ? 'SE' : null); }

/** Switches the city (Settings and the Explore filter): drops city caches and tells the app. */
export function selectCity(id) {
  S.settings.cityId = +id; saveSettings(); S.classCache.clear(); S.home = null;
  window.dispatchEvent(new Event('bruce:city'));
}

export function loadStudios(onProgress) {
  if (S.studiosLoading) return S.studiosLoading;
  const key = 'bruce.studios.' + (isDemo() ? 'demo' : country());
  const cached = ls.get(key, null);
  if (cached && Date.now() - cached.at < STUDIO_CACHE_MS && cached.studios.length) {
    cached.studios.forEach((s) => S.studios.set(s.id, s));
    S.studiosLoading = Promise.resolve();
    return S.studiosLoading;
  }
  S.studiosLoading = Bruce.studios(country(), (items, all) => { items.forEach((s) => S.studios.set(s.id, slimStudio(s))); if (onProgress) onProgress(all.length); })
    .then(() => { ls.set(key, { at: Date.now(), studios: [...S.studios.values()] }); emit(); })
    .catch((e) => { S.studiosLoading = null; throw e; });
  return S.studiosLoading;
}

export async function loadStudio(id, force) {
  if (!force && S.studioDetails.has(id)) return S.studioDetails.get(id);
  const s = await Bruce.studio(id);
  S.studioDetails.set(id, s);
  if (!S.studios.has(id)) S.studios.set(id, slimStudio(s));
  return s;
}
export async function loadClass(id) {
  const c = await Bruce.klass(id);
  S.classDetails.set(id, c);
  return c;
}

export async function loadMine() {
  const [b, s, bm] = await Promise.all([Bruce.bookings(), Bruce.standbys().catch(() => []), Bruce.bookmarks().catch(() => [])]);
  S.bookings.clear(); S.standbys.clear(); S.bookmarks.clear();
  b.filter((x) => !x.deleted).forEach((x) => S.bookings.set(x.class_id || (x.class && x.class.id) || 's' + x.id, x));
  s.filter((x) => x.class).forEach((x) => S.standbys.set(x.class.id, x));
  bm.filter((x) => x.class).forEach((x) => S.bookmarks.set(x.class.id, x));
  emit();
}
/** Reads which classes the auto-book server watches (a request to the server, so only when a class page needs it). */
export async function loadWatches() {
  const st = await Autobook.status(S.settings.autoBookServer);
  S.watches = new Set(st.waitlist); S.openings = new Set(st.opening);
  emit();
}
export async function setWatch(classId, on) {
  await Autobook.watch(classId, on, S.settings.autoBookServer);
  on ? S.watches.add(classId) : S.watches.delete(classId);
}
/** "Book when booking opens" for a one-off class (server only: the browser cannot book while it is closed). */
export async function setOpening(classId, on) {
  await Autobook.opening(classId, on, S.settings.autoBookServer);
  on ? S.openings.add(classId) : S.openings.delete(classId);
}
export async function loadFavorites() {
  const f = await Bruce.favorites().catch(() => []);
  S.favorites.clear(); f.forEach((x) => S.favorites.set(x.studio_id, x.id));
  emit();
}
export async function loadSocial() {
  const [f, fb] = await Promise.all([Bruce.friends().catch(() => []), Bruce.friendsBookings().catch(() => [])]);
  S.friends = f; S.friendsBookings = fb;
  emit();
}
export async function loadNotifications() {
  S.notifications = await Bruce.notifications().catch(() => []);
  emit();
}
export async function loadReviewable() {
  S.reviewable = (await Bruce.reviewable().catch(() => [])).filter((b) => b.class && !b.review_id);
  emit();
}
export async function loadAccount() {
  const [u, m, l, bl] = await Promise.all([Bruce.user().catch(() => null), Bruce.membership().catch(() => null), Bruce.limits().catch(() => []), Bruce.blockInfo().catch(() => null)]);
  S.user = u; S.membership = m; S.limits = l; S.block = bl;
  emit();
}

export async function bootstrap() {
  const [cities, cats] = await Promise.all([Bruce.cities().catch(() => []), Bruce.categories().catch(() => [])]);
  if (cities.length) S.cities = cities;
  S.categories = cats;
  setZone(city().time_zone);
  loadMine().catch(() => {});
  loadFavorites();
  loadSocial();
  loadNotifications();
  loadReviewable();
  loadAccount();
  loadStudios().catch(() => {});
}

// ---------------------------------------------------------------- derived state

export const friendUser = (userId) => (S.friends.find((f) => f.friend_user && f.friend_user.id === userId) || {}).friend_user;
/** Friends booked on a class (from the friends feed, as the iOS ClassRow faces). */
export const friendsOn = (classId) => S.friendsBookings.filter((b) => b.class_id === classId).map((b) => friendUser(b.user_id)).filter(Boolean);
export const upcomingBookings = () => [...S.bookings.values()].filter((b) => b.class && !b.checked_in_at && new Date(b.class.end_time || b.class.start_time) > Date.now());
export function simultaneousLimit() {
  const l = S.limits.find((x) => x.type === 'SIMULTANEOUS');
  return l && l.total > 0 ? l.total : null;
}
export const unseenNotifications = () => S.notifications.filter((n) => new Date(n.created_at).getTime() > S.seenNotifications).length;
export function markNotificationsSeen() {
  S.seenNotifications = Date.now(); ls.set('bruce.seenNotifications', S.seenNotifications); emit();
}
export const pendingReviews = () => S.reviewable.filter((b) => !S.skippedReviews.has(b.id));
export function skipReview(id) { S.skippedReviews.add(id); ls.set('bruce.skippedReviews', [...S.skippedReviews]); emit(); }

/** "Booked" / "Checked in" / "Waitlist" / null. */
export function classBadge(c) {
  const b = S.bookings.get(c.id);
  if (b) return b.checked_in_at ? 'Checked in' : 'Booked';
  if (S.standbys.has(c.id)) return (c.available_spots > 0) ? 'Spot open' : 'Waitlist';
  return null;
}

/** The .ics text and file name for a class (calendar.js), from the data already loaded. */
export function calendarFile(c) {
  const st = studio(c.studio_id) || c.studio || {};
  const a = ((st.studio_addresses || []).find((x) => x.main) || (st.studio_addresses || [])[0] || {}).address || {};
  const text = icsFor(c, {
    studio: { name: st.name, address: a.address, zip: a.zip_code, city: a.city }, rules: rules(c), instructor: instructor(c.instructor),
    timeText: (ms) => time(ms), longText: (ms) => ruleTime(ms), url: 'https://app.brucestudios.com/classes/' + c.id + '/' + slug(c.title),
  });
  return { text, fileName: icsFileName(c.title, dayKey(c.start_time)) };
}
/** webcal:// link to Bruce's feed of all bookings (null until the user record is loaded). Never log or show it. */
export function calendarFeed() { return feedUrl(S.auth && S.auth.userId, S.user); }

/** Booking rule times (Logic.swift `BookingRules`). */
export function rules(c) {
  const s = new Date(c.start_time).getTime();
  return {
    start: s, end: c.end_time ? new Date(c.end_time).getTime() : null,
    bookUntil: c.bookable_latest_time ? new Date(c.bookable_latest_time).getTime() : s,
    checkInFrom: s - (c.early_check_in_minutes != null ? c.early_check_in_minutes : 30) * 60000,
    lateCheckIn: s - (c.late_check_in_minutes != null ? c.late_check_in_minutes : 5) * 60000,
    lateCancel: c.unbookable_latest_time ? new Date(c.unbookable_latest_time).getTime() : s - (c.unbookable_latest != null ? c.unbookable_latest : 43200) * 1000,
    shortNotice: s - 3 * 3600000, lastMinute: s - 3600000,
  };
}

// ---------------------------------------------------------------- check-in

export function door(studioId) { return KNOWN_DOORS[studioId] || S.learnedDoors[studioId] || null; }
export function rememberDoor(studioId, d) {
  if (!studioId || KNOWN_DOORS[studioId] || isDemo()) return;
  S.learnedDoors[studioId] = d; ls.set('bruce.doors', S.learnedDoors);
}
/** {studioId, name, subtitle, qr, door} or null when the studio has no QR id. */
export function target(studioId, subtitle) {
  const s = studio(studioId);
  const d = door(studioId);
  if (d) return { studioId, name: studioName(studioId), subtitle, qr: 'stc:' + d.major, door: d };
  if (!s || !s.qr) return null;
  return { studioId, name: s.name, subtitle, qr: s.qr, door: null };
}
/** "stc://open-door?major=13816&minor=118551" or a studio's own QR id -> target. */
export function targetForScan(code) {
  const t = code.trim();
  const m = t.match(/^stc:\/\/open-door\?(.*)$/i);
  if (m) {
    const p = new URLSearchParams(m[1]);
    const major = p.get('major'), minor = p.get('minor');
    if (!major || !minor) return null;
    const sid = +(Object.keys(KNOWN_DOORS).find((k) => KNOWN_DOORS[k].major === major) ||
      ([...S.studios.values()].find((s) => s.qr === 'stc:' + major) || {}).id || 0);
    return { studioId: sid, name: sid ? studioName(sid) : 'Door ' + major, subtitle: 'Door ' + minor, qr: 'stc:' + major, door: { major, doorId: minor } };
  }
  const s = [...S.studios.values()].find((x) => x.qr === t);
  return s ? target(s.id, s.vicinity || '') : null;
}
/** Booked classes whose check-in window is open now (CheckInLogic.swift `openWindowTargets`). */
export function openWindowTargets() {
  const now = Date.now();
  return upcomingBookings().map((b) => {
    const r = rules(b.class);
    if (!(r.checkInFrom <= now && now <= (r.end || r.start + 3600000))) return null;
    const t = target(b.class.studio_id, b.class.title + ' · ' + new Date(b.class.start_time).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: city().time_zone }));
    return t && { t, c: b.class };
  }).filter(Boolean);
}
export function recentTargets(visits) {
  const seen = new Set(); const out = [];
  for (const v of (visits || []).concat([...S.bookings.values()]).filter((b) => b.checked_in_at).sort((a, b) => byInstant(b.checked_in_at, a.checked_in_at))) {
    const sid = v.studio_id || (v.class && v.class.studio_id);
    if (!sid || seen.has(sid)) continue;
    seen.add(sid);
    const when = dayKey(v.checked_in_at) === todayKey() ? 'today' : new Date(v.checked_in_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: city().time_zone });
    const t = target(sid, 'Checked in ' + when);
    if (t) out.push(t);
    if (out.length === 5) break;
  }
  return out;
}
export function todaysCheckIn(studioId) {
  return [...S.bookings.values()].find((b) => (b.studio_id || (b.class && b.class.studio_id)) === studioId && b.checked_in_at && dayKey(b.checked_in_at) === todayKey());
}

// ---------------------------------------------------------------- history, our server, places and goals

/** All of the user's bookings (the same pages Statistics reads). Also fills `S.visits` (check-ins). */
export function loadHistory(force) {
  if (S.history && !force) return Promise.resolve(S.history);
  if (S.historyLoading && !force) return S.historyLoading;
  S.historyLoading = Bruce.visits().then((v) => {
    S.history = v; S.visits = v.filter((x) => x.checked_in_at && !x.deleted);
    S.historyLoading = null; emit();
    return v;
  }).catch((e) => { S.historyLoading = null; throw e; });
  return S.historyLoading;
}
/** Deduped visits (visits.js) from the history: check-ins only for goals, everything for For you and Wrapped. */
export function visitList(checkedInOnly) {
  return visitsFrom(S.history || [], { zone: getZone(), checkedInOnly: !!checkedInOnly });
}

/** One day of city-wide classes, shared with Explore's cache. */
export async function dayClasses(day) {
  const key = S.settings.cityId + ':' + day;
  const c = S.classCache.get(key);
  if (c && c.done && Date.now() - c.at < 10 * 60000) return c.classes;
  if (c && c.loading && c.promise) return c.promise;
  const entry = { at: Date.now(), classes: [], loading: true, done: false };
  entry.promise = Bruce.classes(day, { cityId: S.settings.cityId }).then((all) => {
    entry.classes = all.filter((c) => onDay(c, day)).sort(byStart);
    entry.done = true; entry.loading = false;
    return entry.classes;
  }).catch((e) => { S.classCache.delete(key); throw e; });
  S.classCache.set(key, entry);
  return entry.promise;
}

/** Our server (the auto-book server) is on unless switched off in Settings. Challenges always need it. */
export const serverOn = () => S.settings.serverOn !== false;
export async function loadChallenges() {
  S.challenges = await Server.challenges();
  emit();
  return S.challenges;
}
export const pendingInvites = () => ((S.challenges && S.challenges.challenges) || []).filter((c) => c.myStatus === 'invited');

const suffix = () => (isDemo() ? '.demo' : '');
/** Saved places and commute preferences. Stored on this device only, never sent anywhere. */
export function placesState() {
  const demo = isDemo() ? {
    places: [
      { id: 'home', kind: 'home', name: 'Home', label: 'Near Example Swim Hall, Södermalm', lat: 59.3141, lon: 18.0712 },
      { id: 'work', kind: 'work', name: 'Work', label: 'Near Example Reformer Loft, Norrmalm', lat: 59.3366, lon: 18.0604, workdays: [0, 1, 2, 3, 4] },
    ],
  } : { places: [] };
  return Object.assign({}, DEFAULT_PREFS, demo, ls.get('bruce.places' + suffix(), {}));
}
export function savePlaces(p) { ls.set('bruce.places' + suffix(), p); S.forYouSig = null; emit(); }

/** Monthly goals, stored on this device. */
export function goals() {
  return ls.get('bruce.goals' + suffix(), isDemo() ? [
    { id: 'g-gym', category: 'gym', target: 12, studioId: null, remind: true },
    { id: 'g-swim', category: '30', target: 2, studioId: null, remind: false },
  ] : []);
}
export const catTitle = (id) => ((S.categories.find((c) => String(c.id) === String(id)) || {}).title || null);
export function saveGoals(list) {
  ls.set('bruce.goals' + suffix(), list);
  emit();
  syncGoals(list);
}
/** "Reminder when behind": hands goals with a reminder to our server (PUT /me/goals) when it is on. Only sends a
 *  change, and failures are silent. */
export function syncGoals(list) {
  if (!serverOn()) return;
  const body = remindPayload(list || goals(), catTitle);
  const sig = JSON.stringify(body);
  const key = 'bruce.goalsSynced' + suffix();
  if (ls.get(key, '[]') === sig) return;
  Server.putGoals(body).then(() => ls.set(key, sig)).catch(() => {});
}
export { goalTitle };
/** Explore chip row: the first Home category (e.g. Gym) pinned, then alphabetical (as in the app). */
export function chipCategories() {
  const sorted = [...S.categories].sort((a, b) => (a.title || '').localeCompare(b.title || '', 'sv'));
  const home = S.home && S.home.find((s) => s.type === 'CATEGORIES');
  const pin = (home && home.items[0] && home.items[0].category_id) || (sorted.find((c) => /^gym$/i.test(c.title)) || {}).id;
  const first = sorted.find((c) => c.id === pin);
  return first ? [first, ...sorted.filter((c) => c !== first)] : sorted;
}

// ---------------------------------------------------------------- races (races.js, racesui.js)

/** The race catalog: races.json next to this page (GitHub Pages publishes docs/), the last good copy in this browser,
 *  demo races in demo mode. A failed read keeps whatever is shown. */
export function loadRaces(force) {
  if (isDemo()) { if (!S.races) { S.races = decodeRaces({ races: DEMO_RACES }); S.trainingClubs = DEMO_TRAINING_CLUBS; } return Promise.resolve(S.races); }
  if (S.racesLoading) return S.racesLoading;
  const cached = ls.get('bruce.races', null);
  if (!S.races && cached && Array.isArray(cached.races)) { S.races = decodeRaces(cached); S.trainingClubs = decodeClubs(cached); }
  if (!force && cached && Date.now() - cached.at < RACES_CACHE_MS && S.races && S.races.length) return Promise.resolve(S.races);
  S.racesLoading = fetch('races.json', { cache: 'no-cache' })
    .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then(async (json) => {
      const list = decodeRaces(json);
      if (!list.length) throw new Error('no races');
      // An organiser feed on our server lays over the file (none while the server is off; a failed read changes nothing).
      const feed = serverOn() ? await Server.races().then((f) => decodeRaces(f)).catch(() => []) : [];
      S.races = mergeFeed(list, feed); S.racesError = null;
      S.trainingClubs = decodeClubs(json);
      ls.set('bruce.races', { at: Date.now(), races: json.races, trainingClubs: json.trainingClubs || [] });
    })
    .catch(() => { if (!S.races || !S.races.length) { S.races = []; S.racesError = "Couldn't load the race list. Check your connection and reload."; } })
    .then(() => { S.racesLoading = null; emit(); return S.races; });
  return S.racesLoading;
}
/** My races, stored in this browser only (like saved places and goals). */
export function myRaces() { return ls.get('bruce.myRaces' + suffix(), isDemo() ? DEMO_MY_RACES : []); }
export function saveMyRaces(list) { ls.set('bruce.myRaces' + suffix(), list); emit(); syncRaces(list); }
/** The body of PUT /me/races: upcoming races with a race-week, day-before or price-step reminder (at most 20), with
 *  the plan's race-week mix for the push text and the price step's day and words (server/README.md). */
export function racesPayload(list, catalog, today) {
  // Going switched here (on or off) goes with the moment it was flipped: the last flip wins on every device.
  const switched = (m) => !!(m.raceId && m.goingAt);
  const price = (e) => (e.mine.remindPrice ? priceReminder(e.race, today) : null);
  return upcomingRaces(raceEntries(list, catalog), today).filter((e) => e.mine.remindWeek || e.mine.remindEve || price(e) || sharesGoing(e.mine) || switched(e.mine)).slice(0, 20).map((e) => {
    const o = { id: raceKey(e.mine), name: e.race.name, date: e.day, remindWeek: !!e.mine.remindWeek, remindEve: !!e.mine.remindEve };
    const pr = price(e);
    if (pr) { o.remindPrice = true; o.priceAt = pr.changeOn; o.priceBody = pr.body; }
    if (switched(e.mine)) { o.going = !!e.mine.going; o.goingAt = e.mine.goingAt; }
    if (e.race.signupUrl) o.url = e.race.signupUrl;
    const p = e.mine.plan && makePlan(e.day, e.race.type, e.race.sport, e.mine.plan);
    if (p) {
      o.plan = { perWeek: p.settings.perWeek, weeks: p.blockWeeks, startedOn: p.settings.startedOn,
        raceWeek: p.rows.filter((k) => planCount(p.raceWeek, k) > 0).map((k) => ({ key: k, title: planCategory(k).short, count: planCount(p.raceWeek, k) })) };
    }
    return o;
  });
}
/** Race-week and day-before reminders (our server sends them, push and email) and going (friends see it), while the
 *  server is on. Only sends a change; then reads friends going again (sharing a race changes what it shows). */
export function syncRaces() {
  if (!serverOn() || !loggedIn()) return Promise.resolve();
  // One after the other, each reading My races when it runs, so a quick on and off reaches the server in order.
  S.raceSync = (S.raceSync || Promise.resolve()).then(sendRaces, sendRaces);
  return S.raceSync;
}
function sendRaces() {
  if (!serverOn() || !loggedIn()) return null;
  const body = racesPayload(myRaces(), S.races || [], todayKey());
  const sig = JSON.stringify(body);
  // Per login: another account in this browser sends its own races.
  const key = 'bruce.racesSynced.' + (S.auth && S.auth.userId) + suffix();
  const last = ls.get(key, null);
  if (last === sig || (last == null && !body.length)) return null;
  return Server.putRaces(body, raceDevice()).then(() => { ls.set(key, sig); ls.set(key + '.at', Date.now()); return loadGoing(true); }).catch(() => {});
}
/** Going is the member's on every device: a switch flipped elsewhere (the server's `mine`) is taken over here, unless it
 *  was flipped here after the last confirmed sync (then this browser's switch is still on its way). */
function adoptGoing(g) {
  if (isDemo()) return;
  const syncedAt = ls.get('bruce.racesSynced.' + (S.auth && S.auth.userId) + suffix() + '.at', 0);
  const server = new Set(g.mine || []);
  const today = todayKey();
  let changed = false;
  const list = myRaces().map((m) => {
    if (!m.raceId || !!m.going === server.has(m.raceId) || (m.goingAt || 0) > syncedAt) return m;
    const e = raceEntries([m], S.races || [])[0];
    if (!upcomingRaces([e], today).length) return m;
    changed = true;
    return Object.assign({}, m, { going: server.has(m.raceId) });
  });
  if (changed) saveMyRaces(list);
}

// ---------------------------------------------------------------- friends going (crews.js, racesui.js)

/** Going needs our server on (it stores who may see a race) and a login; the demo answers in the browser. */
export const canShareGoing = () => isDemo() || (serverOn() && loggedIn());
/** GET /races/going: the Bruce friends who share an upcoming race, by race id (only while you share one too). At most
 *  every 10 minutes unless `force`; a failure keeps what is shown. */
export function loadGoing(force) {
  if (!canShareGoing()) return Promise.resolve(S.raceGoing);
  // A read that started before a change must not stand in for a fresh one.
  if (S.raceGoingLoading) return force ? S.raceGoingLoading.then(() => loadGoing(true)) : S.raceGoingLoading;
  if (!force && Date.now() - S.raceGoingAt < 600000) return Promise.resolve(S.raceGoing);
  S.raceGoingLoading = Server.going().then((g) => {
    S.raceGoing = Object.assign({ going: {}, sharing: false, mine: [] }, g); S.raceGoingAt = Date.now();
    adoptGoing(S.raceGoing);
    emit();
  }).catch(() => {}).then(() => { S.raceGoingLoading = null; return S.raceGoing; });
  return S.raceGoingLoading;
}
/** Friends going to a race, as users (photo from the Friends list when Bruce has it). */
export function friendsGoing(raceId) {
  if (!canShareGoing()) return [];   // with the server off nothing is shared any more, so nothing is shown either
  return ((S.raceGoing.going || {})[raceId] || []).filter((f) => !S.auth || f.userId !== S.auth.userId)
    .map((f) => friendUser(f.userId) || { id: f.userId, first_name: f.name || '' });
}
/** This browser in PUT /me/races: each device's My races replace only the races it sent. */
function raceDevice() {
  let d = ls.get('bruce.raceDevice', null);
  if (!d) { d = 'web-' + Math.random().toString(36).slice(2, 12); ls.set('bruce.raceDevice', d); }
  return d;
}
/** Deletes a monthly goal; one made from a Train for it plan stays deleted (raceplan.js planGoals `skip`). */
export function deleteGoal(g) {
  if (g.raceKey) {
    saveMyRaces(myRaces().map((m) => (raceKey(m) === g.raceKey && m.plan
      ? Object.assign({}, m, { plan: Object.assign({}, m.plan, { goalsSkip: (m.plan.goalsSkip || []).filter((x) => x !== String(g.category)).concat(String(g.category)) }) }) : m)));
  }
  saveGoals(goals().filter((x) => x.id !== g.id));
}
