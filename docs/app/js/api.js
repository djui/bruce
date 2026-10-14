// Bruce v52 API client for the browser. Same routes, parameters and bodies as Shared/BruceCore/API*.swift (see
// API.md). api.bruce.app answers CORS with `Access-Control-Allow-Origin: *`, so the page calls it directly; the
// token goes in `X-Access-Token` (no cookies). In demo mode every call goes to the in-browser fake in demo.js.
import { handle as demoHandle } from './demo.js';
import { addDays } from './util.js';

export const DEFAULT_API = 'https://api.bruce.app';
const STUDIO_FIELDS = 'checkin_studio_id,city_id,deleted,has_address,has_classes,has_openings,id,integration_door_type,keyword,label,name,photo,qr_code_id,rating,remote,requires_additional_cost,status,tier_level,time_zone,vicinity,visit_limit_id';

export class ApiError extends Error { constructor(status, message, body) { super(message); this.status = status; this.body = body; } }

export const session = { token: null, userId: null, demo: false, base: DEFAULT_API, onUnauthorized: null };

function qs(query) {
  // Brackets stay literal like the official app sends them (filter[status][in]=live).
  return Object.entries(query || {}).filter(([, v]) => v != null)
    .map(([k, v]) => encodeURIComponent(k).replace(/%5B/g, '[').replace(/%5D/g, ']') + '=' + encodeURIComponent(v)).join('&');
}
export function errorText(body, status) {
  const e = body && body.errors && body.errors[0];
  const msg = e && (e.message || e.code);
  return msg ? String(msg).trim() : 'Request failed (HTTP ' + status + ').';
}

/** One request. `raw` returns {status, body} instead of throwing on non-2xx (used by check-in). */
export async function api(method, path, query, body, opts) {
  const q = Object.assign({ locale: 'en' }, query || {});
  const b = body ? Object.assign({ locale: 'en' }, body) : null;
  let status, json;
  if (session.demo) {
    await new Promise((r) => setTimeout(r, 80 + Math.random() * 160));
    ({ status, body: json } = demoHandle(method, path, q, b || {}));
  } else {
    const headers = { Accept: 'application/json' };
    if (session.token) headers['X-Access-Token'] = session.token;
    const init = { method, headers };
    if (b) { headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(b); }
    let res;
    try { res = await fetch(session.base.replace(/\/+$/, '') + '/' + path + '?' + qs(q), init); }
    catch (e) { throw new ApiError(0, 'Could not reach the Bruce server. Check your connection.'); }
    status = res.status;
    if (opts && opts.blob) {
      if (!res.ok) throw new ApiError(status, 'Request failed (HTTP ' + status + ').');
      return res.blob();
    }
    const text = await res.text();
    try { json = text ? JSON.parse(text) : {}; } catch (e) { json = { raw: text }; }
    if (status === 401 && session.token && session.onUnauthorized) session.onUnauthorized();
  }
  if (opts && opts.raw) return { status, body: json };
  if (status < 200 || status >= 300) throw new ApiError(status, errorText(json, status), json);
  return json || {};
}

/** Pages a list endpoint by `metadata.pagination.next_cursor`; `onPage` sees each page as it arrives. */
export async function paged(path, query, key, onPage, maxPages) {
  let cursor = null; const out = [];
  for (let i = 0; i < (maxPages || 60); i++) {
    const r = await api('GET', path, Object.assign({}, query, cursor ? { next_cursor: cursor } : {}));
    const items = r[key] || [];
    out.push(...items);
    if (onPage) onPage(items, out);
    const next = r.metadata && r.metadata.pagination && r.metadata.pagination.next_cursor;
    if (!next || !items.length) break;
    cursor = next;
  }
  return out;
}

const uid = () => session.userId;

/** The auto-book server (server/README.md): books a full class for the user as soon as a waitlist spot frees up.
 *  It takes the user's own Bruce login in the same headers and answers CORS, so the page calls it directly. */
export const AUTOBOOK_SERVER = 'https://bruce-autobook.uwe-af1.workers.dev';
const demoWatches = new Set();
async function autobook(method, path, base) {
  const res = await fetch((base || AUTOBOOK_SERVER).replace(/\/+$/, '') + path, {
    method, headers: { 'X-Access-Token': session.token, 'X-User-Id': String(uid()) },
  }).catch(() => { throw new ApiError(0, 'Could not reach the auto-book server.'); });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, body.error || 'Auto-book server: HTTP ' + res.status, body);
  return body;
}
export const Autobook = {
  /** Class ids the server watches for a free waitlist spot. */
  watching: (base) => session.demo ? Promise.resolve([...demoWatches]) : autobook('GET', '/me', base).then((r) => (r.waitlist || []).map((w) => w.classId)),
  watch: (classId, on, base) => {
    if (session.demo) { on ? demoWatches.add(classId) : demoWatches.delete(classId); return Promise.resolve({ ok: true }); }
    return autobook(on ? 'PUT' : 'DELETE', '/me/waitlist/' + classId, base);
  },
};
const yyyymmdd = (d) => d.toISOString().slice(0, 10).replace(/-/g, '');

export const Bruce = {
  login: (email, password) => api('POST', 'v52/access/authenticate', null, { authenticator: 'PASSWORD', email, password }),
  logout: () => api('DELETE', 'v52/access/logout', null, {}),

  cities: () => api('GET', 'v52/location/city', { include_country: 'true' }).then((r) => (r.cities || []).filter((c) => !c.hidden)),
  categories: () => api('GET', 'v52/category', { 'filter[main][eq]': 'true' }).then((r) => r.categories || []),
  home: (lat, lon) => api('GET', 'v52/home_screen', { coordinates: lat + ',' + lon }).then((r) => r.sections || []),

  studios: (country, onPage) => paged('v52/studio/filter', {
    'filter[status][in]': 'live', 'filter[country_code][eq]': country, fields: STUDIO_FIELDS,
    include: 'addresses,addresses_address,categories,categories_category,visit_limit', limit: 30,
  }, 'studios', onPage, 200),
  studio: (id) => api('GET', 'v52/studio/' + id, {
    include_addresses: 'true', include_addresses_address: 'true', include_studio_photos: 'true', include_studio_photos_photo: 'true',
    include_facilities: 'true', include_categories: 'true', include_alerts: 'true', exclude_expired_alerts: 'true',
  }).then((r) => r.studio),
  schedule: (id, from, to) => api('GET', 'v52/studio/' + id + '/opening_hour/schedule', {
    start: from.toISOString(), end: to.toISOString(), include_studio_user_attendance_info: 'true',
  }).then((r) => r.schedule || []),
  reviews: (studioId) => api('GET', 'v52/review', {
    studio_id: studioId, comment: 'true', hidden: 'false', order_by: '-id', limit: 50,
    include_booking: 'true', include_booking_class: 'true', include_booking_user: 'true',
  }).then((r) => r.reviews || []),
  studioLimits: (studioId, month) => api('GET', 'v52/studio/user_visit_limit', { user_id: uid(), studio_id: studioId, month }).then((r) => r.limits || []),

  klass: (id) => api('GET', 'v52/class/' + id, {
    include_studio: 'true', include_info: 'true', include_class_categories: 'true', include_absolute_times: 'true',
    include_booking_credit_costs: 'true', include_studio_alerts: 'true', exclude_studio_expired_alerts: 'true',
    include_dynamic_prices: 'true', include_studio_user_attendance_info: 'true',
  }).then((r) => r.class),
  /** One day (YYYY-MM-DD, local time of the city) city-wide or for one studio. */
  classes(key, opts, onPage) {
    const q = {
      start_time_after: key + 'T00:00:00', start_time_before: addDays(key, 1) + 'T00:00:00', limit: 30,
      is_recurring_base: 'false', is_master: 'false', dedicated: 'false', opening: 'false', studio_status: 'live', deleted: 'false',
      include_absolute_times: 'true', include_class_categories: 'true', include_booking_credit_costs: 'true', include_dynamic_prices: 'true',
    };
    if (opts.studioId) { q.studio_id = opts.studioId; q.presentation_studio_id = opts.studioId; } else q.studio_city_id = opts.cityId;
    return paged('v52/class', q, 'classes', onPage);
  },
  similar: (classId) => api('GET', 'v52/studio/class/alternative_recommendation', { class_id: classId }).then((r) => r.class_cards || []),
  attendees: (classId) => paged('v52/booking', { class_id: classId, include_user: 'true', include_message: 'true', deleted: 'false', limit: 30 }, 'bookings', null, 4),
  invite: (classId, userIds) => api('POST', 'v52/class/' + classId + '/invite', null, { user_ids: userIds }),

  bookings: () => paged('v52/booking', {
    user_id: uid(), limit: 30, deleted: 'false', include_class: 'true', include_class_studio: 'true',
    class_start_time_after: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
  }, 'bookings', null, 15),
  visits: () => paged('v52/booking', { user_id: uid(), limit: 30, deleted: 'false', include_class: 'true', include_class_studio: 'true' }, 'bookings', null, 20),
  reviewable: () => api('GET', 'v52/booking', { reviewable: 'true', user_id: uid(), include_class: 'true' }).then((r) => r.bookings || []),
  aggregate: () => api('GET', 'v52/booking/aggregate', { user_id: uid() }).then((r) => r.booking_aggregates || []),
  book: (classId) => api('POST', 'v52/booking', null, { class_id: classId, booked_via: 'HOMESCREEN_SPOTLIGHT', include_user: false }),
  cancel: (bookingId) => api('DELETE', 'v52/booking/' + bookingId, null, { include_user: false }),
  standbys: () => api('GET', 'v52/standby', {
    user_id: uid(), include_class: 'true', include_class_studio: 'true', deleted: 'false', class_start_time_after: new Date().toISOString(),
  }).then((r) => r.standbys || []),
  joinWaitlist: (classId) => api('POST', 'v52/standby', null, { class_id: classId }),
  leaveWaitlist: (id) => api('DELETE', 'v52/standby/' + id, null, {}),
  bookmarks: () => api('GET', 'v52/bookmark', { user_id: uid(), include_class: 'true', include_class_studio: 'true', deleted: 'false' }).then((r) => r.bookmarks || []),
  addBookmark: (classId) => api('POST', 'v52/bookmark', null, { class_id: classId }).then((r) => r.bookmark),
  removeBookmark: (id) => api('DELETE', 'v52/bookmark/' + id, null, {}),
  favorites: () => api('GET', 'v52/favorite').then((r) => r.favorites || []),
  addFavorite: (studioId) => api('POST', 'v52/favorite', null, { studio_id: studioId }).then((r) => r.favorite),
  removeFavorite: (id) => api('DELETE', 'v52/favorite/' + id, null, {}),
  review: (bookingId, rating, comment, isPublic) => api('POST', 'v52/review', null, Object.assign(
    { rating, public: isPublic, booking_id: bookingId, include_booking: true }, comment ? { comment } : {})),
  /** Check-in: `{"qr_code_id":"stc:<major>","meta":{major,minor,door_id}}` with a door, else the studio's qr_code_id [163]. */
  checkIn: (qrCodeId, door) => api('POST', 'v52/studio/check_in', null, Object.assign(
    { qr_code_id: qrCodeId, include_class: true }, door ? { meta: { major: door.major, minor: door.doorId, door_id: door.doorId } } : {}), { raw: true }),

  friends: () => api('GET', 'v52/friend', { user_id: uid(), include_friend_user: 'true' }).then((r) => r.friends || []),
  friendsBookings: () => api('GET', 'v52/booking', {
    user_id: uid(), friends: 'true', class_day_after: yyyymmdd(new Date()), deleted: 'false', limit: 30, include_class: 'true', include_class_studio: 'true',
  }).then((r) => r.bookings || []),
  notifications: () => api('GET', 'v52/notification', { user_id: uid() }).then((r) => r.notifications || []),

  user: () => api('GET', 'v52/user/' + uid()).then((r) => r.user || r),
  setSocial: (social) => api('PUT', 'v52/user/' + uid(), null, { social }),
  membership: () => api('GET', 'v52/membership/user_info', { user_id: uid() }).then((r) => r.user_membership_info),
  limits: () => api('GET', 'v52/studio/user_visit_limit', { user_id: uid() }).then((r) => r.limits || []),
  blockInfo: () => api('GET', 'v52/user_block/info', { user_id: uid() }).then((r) => r.user_block_info),
  payments: () => api('GET', 'v52/payment', { user_id: uid() }).then((r) => r.payments || []),
  receipt: (id) => api('GET', 'v52/payment/' + id + '/receipt.pdf', null, null, { blob: true }),
  paymentMethods: () => api('GET', 'v52/payment/method', { user_id: uid() }).then((r) => r.payment_methods || []),
  vouchers: () => api('GET', 'v52/booking/voucher', { owner_id: uid() }).then((r) => r.booking_vouchers || []),
  notificationSetting: () => api('GET', 'v52/user/' + uid() + '/notification_setting').then((r) => (r.notification_settings || [])[0]),
  updateNotificationSetting: (id, body) => api('PUT', 'v52/user/' + uid() + '/notification_setting/' + id, null, body),
};
