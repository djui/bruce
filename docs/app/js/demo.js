// Offline demo backend: answers the same /v52 routes as api.bruce.app with placeholder data (no personal data,
// modelled on Shared/BruceCore/Demo.swift). Nothing leaves the browser in demo mode.

function at(dayOffset, h, m) {
  const d = new Date();
  d.setDate(d.getDate() + dayOffset);
  d.setHours(h, m, 0, 0);
  return d.toISOString();
}
const addr = (a, zip, lat, lon) => [{ main: true, address: { address: a, zip_code: zip, city: 'Stockholm', latitude: lat, longitude: lon } }];
const cat = (id, title) => ({ category_id: id, main: true, category: { id, title } });

const studios = [
  { id: 1724, name: 'STC Rosenlundsparken', status: 'LIVE', vicinity: 'Södermalm', city_id: 1, qr_code_id: 'stc:13994',
    photo: 'k5pxisc2ienijh72umlm', rating: { total: 270, average: 470, distribution: { 1: 1, 2: 2, 3: 11, 4: 46, 5: 210 } }, has_openings: true, has_classes: true,
    studio_categories: [cat(1, 'Gym')], studio_addresses: addr('Example street 1', '118 00', 59.3165, 18.06),
    visit_limit: { items: [{ label: 'BASE', limit: 0 }, { label: 'BLACK', limit: 0 }, { label: 'EPIC', limit: 0 }] },
    description: 'A placeholder gym used for the offline demo. Strength and cardio areas, open early to late.\n\n**Good to know**\n\n* Showers in every changing room.\n* Towels for rent at the desk.\n* Indoor shoes only in the training hall.',
    studio_facilities: [{ facility: { code: 'changing', title: 'Changing room' } }, { facility: { code: 'shower', title: 'Shower' } }] },
  { id: 1489, name: 'Example Yoga Studio', status: 'LIVE', vicinity: 'Vasastan', city_id: 1, qr_code_id: '930',
    integration_door_type: 'parakey', photo: 'mfrnofbzeqyucdflpasg', rating: { total: 120, average: 482, distribution: { 1: 0, 2: 1, 3: 3, 4: 14, 5: 102 } }, has_classes: true,
    studio_categories: [cat(2, 'Yoga')], studio_addresses: addr('Example road 4', '104 05', 59.3455, 18.047),
    visit_limit: { items: [{ label: 'BASE', limit: 2 }, { label: 'BLACK', limit: 4 }, { label: 'EPIC', limit: 8 }] },
    studio_facilities: [{ facility: { code: 'shower', title: 'Shower' } }, { facility: { code: 'locker', title: 'Locker' } }],
    alerts: [{ id: 1, type: 'INFO', message: 'Placeholder notice: the front door code changes on Mondays.', start_date: at(-2, 0, 0) }],
    description: 'A placeholder studio used for the offline demo. Calm rooms, heated floors and mats for everyone.' },
  { id: 9520, name: 'Example Wellness', status: 'LIVE', vicinity: 'Kungsholmen', city_id: 1, label: 'WELLNESS',
    photo: 'xdz9eqgslqobguwuiqn8', rating: { total: 41, average: 455 }, has_classes: true, qr_code_id: '9520',
    studio_categories: [cat(25, 'Spa')], studio_addresses: addr('Example square 9', '112 20', 59.332, 18.03),
    visit_limit: { items: [{ label: 'BASE', limit: -1 }, { label: 'BLACK', limit: 4 }, { label: 'EPIC', limit: 8 }] },
    description: 'A placeholder wellness studio for the offline demo.' },
  { id: 2001, name: 'Example Climbing Hall', status: 'LIVE', vicinity: 'Hammarby Sjöstad', city_id: 1, qr_code_id: '2001',
    photo: 'ulopoksuf88nlz90lmsz', rating: { total: 88, average: 461 }, has_openings: true, has_classes: true,
    studio_categories: [cat(7, 'Climbing')], studio_addresses: addr('Example quay 12', '120 30', 59.304, 18.1),
    visit_limit: { items: [{ label: 'BASE', limit: 4 }, { label: 'BLACK', limit: 8 }, { label: 'EPIC', limit: 0 }] },
    description: 'A placeholder climbing hall for the offline demo.' },
];
const templates = [
  [1489, 'Morning Flow', 7, 0, 60, 'Instructor D', 14, [2]],
  [1724, 'Full Body Strength', 7, 30, 45, 'Instructor B', 20, [26]],
  [1489, 'Morning Meditation', 9, 0, 45, 'Instructor E', 12, [5]],
  [1724, 'High Intensity', 11, 30, 45, 'Instructor A', 20, [12]],
  [9520, 'Salt Cave', 12, 0, 45, '**Instructor G - English speaking', 6, []],
  [1724, 'Functional', 17, 0, 45, 'Instructor F', 12, [12]],
  [2001, 'Bouldering Basics', 17, 30, 90, 'Instructor H', 10, [7]],
  [1489, 'Hatha Flow', 18, 0, 75, 'Instructor C', 16, [2]],
  [1724, 'Hyrox Prep', 18, 45, 60, 'Instructor A', 18, [13]],
  [9520, 'Red Light', 19, 30, 30, null, 4, []],
  [1489, 'Yin Yoga', 20, 0, 60, 'Instructor C', 16, [2]],
];
const classes = {};
for (let day = -1; day < 8; day++) {
  templates.forEach((t, i) => {
    const id = 9000 + (day + 1) * 100 + i;
    const start = at(day, t[2], t[3]);
    const end = new Date(new Date(start).getTime() + t[4] * 60000).toISOString();
    const st = new Date(start).getTime();
    classes[id] = {
      id, studio_id: t[0], presentation_studio_id: t[0], title: t[1], start_time: start, end_time: end, instructor: t[5],
      spots: t[6], available_spots: i === 5 ? 0 : 1 + ((id * 7) % t[6]), canceled: false, deleted: false, currency: 'sek',
      bookable_latest_time: new Date(st - 600000).toISOString(), unbookable_latest: 43200,
      unbookable_latest_time: new Date(st - 43200000).toISOString(), early_check_in_minutes: 30, late_check_in_minutes: 5,
      class_categories: t[7].map((c) => ({ category_id: c, main: true })),
      description: i === 3 ? 'A placeholder interval class for the offline demo.\n\nShort, *hard* intervals with **active rest**:\n\n1. Warm-up\n2. Four rounds of intervals\n3. Stretch' : 'A placeholder class for the offline demo.',
      alert: i === 5 ? 'Placeholder notice: this class is held in the outdoor area.' : null,
    };
  });
}
// A class starting in 15 minutes, so the check-in window is open in the demo.
const soon = Date.now() + 15 * 60000;
classes[9950] = { id: 9950, studio_id: 1724, title: 'Strength Circuit', start_time: new Date(soon).toISOString(), end_time: new Date(soon + 45 * 60000).toISOString(),
  instructor: 'Instructor G', spots: 16, available_spots: 4, early_check_in_minutes: 30, late_check_in_minutes: 5, unbookable_latest: 43200,
  unbookable_latest_time: new Date(soon - 43200000).toISOString(), bookable_latest_time: new Date(soon - 600000).toISOString(), class_categories: [{ category_id: 26 }] };

const categories = [
  { id: 1, title: 'Gym', photo: 'ulopoksuf88nlz90lmsz' }, { id: 2, title: 'Yoga', photo: 'mfrnofbzeqyucdflpasg' }, { id: 5, title: 'Meditation', photo: 'dgl20t8p7zqpugxw9ron' },
  { id: 7, title: 'Climbing' }, { id: 12, title: 'High-intensity', photo: 'k5pxisc2ienijh72umlm' }, { id: 13, title: 'Hyrox' },
  { id: 19, title: 'Pilates', photo: 'xdz9eqgslqobguwuiqn8' }, { id: 25, title: 'Spa' }, { id: 26, title: 'Strength' },
];
const users = {
  1: { id: 1, first_name: 'Demo', last_name: 'User', email: 'demo@example.com', social: true },
  21: { id: 21, first_name: 'Friend', last_name: 'One', social: true },
  22: { id: 22, first_name: 'Friend', last_name: 'Two', social: true },
  23: { id: 23, first_name: 'Friend', last_name: 'Three', social: true },
};
let nextId = 500;
const bookings = [
  { id: 401, user_id: 1, class_id: 9203, studio_id: 1724, checked_in_at: null },
  { id: 402, user_id: 1, class_id: 9307, studio_id: 1489, checked_in_at: null },
  { id: 403, user_id: 1, class_id: 9950, studio_id: 1724, checked_in_at: null },
];
const past = [
  { id: 301, user_id: 1, class_id: 9008, studio_id: 1489, checked_in_at: at(-1, 17, 52), review_id: null },
  { id: 302, user_id: 1, class_id: null, studio_id: 1724, checked_in_at: at(-3, 7, 51) },
  { id: 303, user_id: 1, class_id: null, studio_id: 2001, checked_in_at: at(-6, 18, 10) },
  { id: 304, user_id: 1, class_id: null, studio_id: 1724, checked_in_at: at(-9, 6, 40) },
];
const friendBookings = [
  { id: 801, user_id: 21, class_id: 9203 }, { id: 802, user_id: 22, class_id: 9210 }, { id: 803, user_id: 21, class_id: 9405 },
  { id: 804, user_id: 23, class_id: 9301 }, { id: 805, user_id: 22, class_id: 9507 },
];
const standbys = [{ id: 77, class_id: 9205 }];
const bookmarks = [{ id: 61, class_id: 9408 }];
const favorites = [{ id: 11, studio_id: 1489 }];
const notifications = [
  { id: 5, type: 'STANDBY_AVAILABLE', title: 'Free spot', message: 'A spot opened up in Functional at STC Rosenlundsparken.', created_at: at(0, 8, 2), meta: { class_id: 9205 } },
  { id: 4, type: 'CLASS_INVITE', title: 'Friend One invited you', message: 'Join Hatha Flow at Example Yoga Studio.', created_at: at(-1, 19, 40), meta: { class_id: 9307, inviting_user_name: 'Friend One' } },
  { id: 3, type: 'BOOKING_REMINDER', title: 'Class tomorrow', message: 'High Intensity starts tomorrow at 11:30.', created_at: at(-1, 11, 30), meta: { class_id: 9203 } },
  { id: 2, type: 'USER_STRIKE', title: 'You got a strike', message: 'Late cancellation of Yin Yoga.', created_at: at(-8, 9, 0), meta: {} },
  { id: 1, type: 'PAUSE_ENDING', title: 'Welcome back', message: 'Your membership pause has ended.', created_at: at(-20, 9, 0) },
];
const reviews = {
  1724: [
    { id: 91, rating: 5, comment: 'Clean, never crowded in the mornings.', created_at: at(-4, 9, 0), booking: { class: { opening: true }, user: { first_name: 'Alex' } } },
    { id: 92, rating: 4, comment: 'Good classes, the changing room gets busy at 18.', created_at: at(-12, 19, 0), booking: { class: { title: 'High Intensity' }, user: { first_name: 'Sam' } } },
  ],
  1489: [{ id: 93, rating: 5, comment: 'Lovely teachers and warm rooms.', created_at: at(-2, 21, 0), booking: { class: { title: 'Hatha Flow' }, user: { first_name: 'Kim' } } }],
};
const setting = { id: 1, marketing_email: true, marketing_push: true, marketing_sms: false, types: [
  { key: 'booking_reminder', name: 'Booking reminders', description: 'Before a booked class starts', enabled: true },
  { key: 'check_in_reminder', name: 'Check-in reminders', description: 'When your check-in window opens', enabled: true },
  { key: 'new_studio', name: 'New studios', description: 'When a studio opens near you', enabled: false }] };

function studioLite(id) {
  const s = studios.find((x) => x.id === id);
  return s ? { id: s.id, name: s.name, photo: s.photo, vicinity: s.vicinity, city_id: 1, alerts: s.alerts } : null;
}
const withStudio = (c) => (c ? Object.assign({}, c, { studio: studioLite(c.studio_id) }) : null);
const err = (status, message) => ({ status, body: { errors: [{ code: 'DEMO', message, status }] } });
const ok = (body) => ({ status: 200, body });
const page = { metadata: { pagination: { next_cursor: null } } };
const list = (key, items) => ok(Object.assign({ [key]: items }, page));

export function handle(method, path, q, body) {
  let m;
  const G = method === 'GET', P = method === 'POST', D = method === 'DELETE';
  if (D && path === 'v52/access/logout') return ok({});
  if (path === 'v52/location/city') return ok({ cities: [
    { id: 1, name: 'Stockholm', code: 'STO', time_zone: 'Europe/Stockholm', coordinates: { latitude: 59.3293, longitude: 18.0686 }, country: { code: 'SE' }, user_strike_block_un_lock_price: 140 },
    { id: 2, name: 'Göteborg', code: 'GOT', time_zone: 'Europe/Stockholm', coordinates: { latitude: 57.7089, longitude: 11.9746 }, country: { code: 'SE' } }] });
  if (path === 'v52/category') return ok({ categories });
  if (path === 'v52/home_screen') {
    const spot = [9203, 9307, 9408].map((id) => classes[id]);
    return ok({ sections: [
      { title: 'Spotlight', type: 'SPOTLIGHT', items: spot.map((c) => ({ type: 'CLASS', class_id: c.id, class_name: c.title, studio_id: c.studio_id, studio_name: studioLite(c.studio_id).name, photo: studioLite(c.studio_id).photo, start_time: c.start_time })) },
      { title: 'Categories', type: 'CATEGORIES', items: categories.slice(0, 6).map((c) => ({ type: 'CATEGORY', category_id: c.id, title: c.title, photo: c.photo })) },
      { title: 'Nearby gyms', type: 'NEARBY_GYMS', items: [1724, 2001].map((id, i) => { const s = studioLite(id); return { type: 'STUDIO', studio_id: id, studio_name: s.name, vicinities: [s.vicinity], categories: [i ? 'Climbing' : 'Gym'], distance: i ? 2400 : 650, photo: s.photo }; }) },
      { title: 'New studios', type: 'NEW_STUDIO', items: [9520, 1489].map((id) => { const s = studioLite(id); return { type: 'STUDIO', studio_id: id, studio_name: s.name, vicinities: [s.vicinity], categories: [], photo: s.photo }; }) },
    ] });
  }
  if (path === 'v52/studio/filter') return list('studios', studios);
  if ((m = path.match(/^v52\/studio\/(\d+)\/opening_hour\/schedule$/))) {
    const s = studios.find((x) => x.id === +m[1]);
    if (!s || !s.has_openings) return ok({ schedule: [] });
    return ok({ schedule: [0, 1].map((d) => ({ start: at(d, 5, 0), end: at(d, 23, 0), is_all_day: false })) });
  }
  if ((m = path.match(/^v52\/studio\/(\d+)$/))) {
    const s = studios.find((x) => x.id === +m[1]);
    return s ? ok({ studio: s }) : err(404, 'Studio not found');
  }
  if (path === 'v52/studio/user_visit_limit') {
    if (q.studio_id) {
      const s = studios.find((x) => x.id === +q.studio_id);
      const item = s && s.visit_limit && s.visit_limit.items.find((i) => i.label === 'BLACK');
      const used = past.filter((b) => b.studio_id === +q.studio_id).length;
      return ok({ limits: [{ type: 'STUDIO', total: item ? item.limit : 0, used, remaining: item && item.limit > 0 ? item.limit - used : 0, resets_at: at(18, 0, 0), items: s ? s.visit_limit.items : [] }] });
    }
    return ok({ limits: [
      { type: 'MONTHLY', total: 0, used: past.length, remaining: 0, resets_at: at(18, 0, 0) },
      { type: 'WELLNESS_MONTHLY', total: 4, used: 1, remaining: 3, resets_at: at(18, 0, 0) },
      { type: 'SIMULTANEOUS', total: 4, used: bookings.length, remaining: 4 - bookings.length },
    ] });
  }
  if (path === 'v52/studio/class/alternative_recommendation') {
    const c = classes[+q.class_id];
    const cards = Object.values(classes).filter((x) => c && x.id !== c.id && x.available_spots > 0 && Math.abs(new Date(x.start_time) - new Date(c.start_time)) < 4 * 3600000)
      .slice(0, 4).map((x) => ({ id: x.id, title: x.title, start_time: x.start_time, end_time: x.end_time, distance: 1200, photo: studioLite(x.studio_id).photo, studio: { id: x.studio_id, name: studioLite(x.studio_id).name } }));
    return ok({ class_cards: cards });
  }
  if (path === 'v52/studio/check_in' && P) {
    const s = studios.find((x) => x.qr_code_id === body.qr_code_id || (body.meta && x.qr_code_id === 'stc:' + body.meta.major));
    if (!s) return err(400, 'No studio found for this QR code.');
    const now = new Date().toISOString();
    const b = bookings.find((x) => x.studio_id === s.id && !x.checked_in_at && classes[x.class_id] && Math.abs(new Date(classes[x.class_id].start_time) - Date.now()) < 3600000);
    if (b) b.checked_in_at = now; else bookings.push({ id: nextId++, user_id: 1, class_id: null, studio_id: s.id, checked_in_at: now });
    return ok({ bookings: [b || bookings[bookings.length - 1]] });
  }
  if (path === 'v52/class') {
    const from = q.start_time_after ? new Date(q.start_time_after) : new Date(0);
    const to = q.start_time_before ? new Date(q.start_time_before) : new Date(8.64e15);
    let l = Object.values(classes).filter((c) => new Date(c.start_time) >= from && new Date(c.start_time) < to);
    if (q.studio_id) l = l.filter((c) => c.studio_id === +q.studio_id);
    return list('classes', l.sort((a, b) => a.start_time.localeCompare(b.start_time)));
  }
  if ((m = path.match(/^v52\/class\/(\d+)\/invite$/)) && P) return ok({ invited: (body.user_ids || []).map((id) => users[id]).filter(Boolean) });
  if ((m = path.match(/^v52\/class\/(\d+)$/))) {
    const c = classes[+m[1]];
    if (!c) return err(404, 'Class not found');
    const s = studios.find((x) => x.id === c.studio_id);
    return ok({ class: Object.assign(withStudio(c), { user_attendance_info: { admission_access: true, visit_limit_reached: false, price: s && s.label === 'WELLNESS' ? 22000 : 0 } }) });
  }
  if (path === 'v52/booking/aggregate') {
    const out = [];
    for (let i = 0; i < 9; i++) { const d = new Date(); d.setMonth(d.getMonth() - i, 5); out.push({ day: +d.toISOString().slice(0, 10).replace(/-/g, ''), count: [past.length, 9, 12, 7, 0, 4, 10, 8, 6][i] }); }
    return ok({ booking_aggregates: out });
  }
  if (path === 'v52/booking' && G) {
    const full = (b) => Object.assign({}, b, { class: b.class_id ? withStudio(classes[b.class_id]) : null });
    if (q.class_id) {
      const ids = bookings.filter((b) => b.class_id === +q.class_id).map((b) => ({ id: b.id, user_id: 1, user: users[1] }));
      friendBookings.filter((b) => b.class_id === +q.class_id).forEach((b) => ids.push({ id: b.id, user_id: b.user_id, user: users[b.user_id] }));
      ids.push({ id: 990 }, { id: 991 });
      return list('bookings', ids);
    }
    if (q.friends) return list('bookings', friendBookings.map((b) => Object.assign({}, b, { class: withStudio(classes[b.class_id]) })));
    if (q.reviewable) return list('bookings', past.filter((b) => b.class_id && !b.review_id).map(full));
    if (q.class_start_time_after) return list('bookings', bookings.map(full));
    return list('bookings', past.concat(bookings).map(full));
  }
  if (path === 'v52/booking' && P) {
    const c = classes[body.class_id];
    if (!c) return err(404, 'Class not found');
    if (c.available_spots <= 0) return err(400, 'The class is fully booked.');
    if (bookings.some((b) => b.class_id === c.id)) return err(400, 'You have already booked this class.');
    c.available_spots -= 1;
    const b = { id: nextId++, user_id: 1, class_id: c.id, studio_id: c.studio_id, checked_in_at: null };
    bookings.push(b);
    const si = standbys.findIndex((s) => s.class_id === c.id);
    if (si >= 0) standbys.splice(si, 1);
    return ok({ booking: b });
  }
  if ((m = path.match(/^v52\/booking\/(\d+)$/)) && D) {
    const i = bookings.findIndex((b) => b.id === +m[1]);
    if (i < 0) return err(404, 'Booking not found');
    if (classes[bookings[i].class_id]) classes[bookings[i].class_id].available_spots += 1;
    const [b] = bookings.splice(i, 1);
    return ok({ booking: Object.assign({}, b, { deleted: true, deleted_at: new Date().toISOString() }) });
  }
  if (path === 'v52/standby' && G) return ok({ standbys: standbys.map((s) => ({ id: s.id, class: withStudio(classes[s.class_id]) })) });
  if (path === 'v52/standby' && P) { const s = { id: nextId++, class_id: body.class_id }; standbys.push(s); return ok({ standby: s }); }
  if ((m = path.match(/^v52\/standby\/(\d+)$/)) && D) { const i = standbys.findIndex((s) => s.id === +m[1]); if (i >= 0) standbys.splice(i, 1); return ok({}); }
  if (path === 'v52/bookmark' && G) return ok({ bookmarks: bookmarks.map((b) => ({ id: b.id, class: withStudio(classes[b.class_id]) })) });
  if (path === 'v52/bookmark' && P) { const b = { id: nextId++, class_id: body.class_id }; bookmarks.push(b); return ok({ bookmark: b }); }
  if ((m = path.match(/^v52\/bookmark\/(\d+)$/)) && D) { const i = bookmarks.findIndex((b) => b.id === +m[1]); if (i >= 0) bookmarks.splice(i, 1); return ok({}); }
  if (path === 'v52/favorite' && G) return ok({ favorites: q.studio_id ? favorites.filter((f) => f.studio_id === +q.studio_id) : favorites });
  if (path === 'v52/favorite' && P) { const f = { id: nextId++, studio_id: body.studio_id }; favorites.push(f); return ok({ favorite: f }); }
  if ((m = path.match(/^v52\/favorite\/(\d+)$/)) && D) { const i = favorites.findIndex((f) => f.id === +m[1]); if (i >= 0) favorites.splice(i, 1); return ok({}); }
  if (path === 'v52/review' && G) return list('reviews', reviews[+q.studio_id] || []);
  if (path === 'v52/review' && P) {
    const b = past.find((x) => x.id === body.booking_id);
    if (b) b.review_id = nextId++;
    return ok({ review: { id: b ? b.review_id : 0, rating: body.rating, comment: body.comment } });
  }
  if (path === 'v52/friend') return ok({ friends: [21, 22, 23].map((id) => ({ id: 100 + id, friend_user: users[id] })) });
  if (path === 'v52/notification') return ok({ notifications });
  if (path === 'v52/user/1' && G) return ok({ user: users[1] });
  if (path === 'v52/user/1' && method === 'PUT') { Object.assign(users[1], { social: body.social }); return ok({ user: users[1] }); }
  if (path === 'v52/user/1/notification_setting' && G) return ok({ notification_settings: [setting] });
  if ((m = path.match(/^v52\/user\/1\/notification_setting\/\d+$/))) {
    if (body.types) setting.types.forEach((t) => { const n = body.types.find((x) => x.key === t.key); if (n) t.enabled = n.enabled; });
    ['marketing_email', 'marketing_push', 'marketing_sms'].forEach((k) => { if (k in body) setting[k] = body[k]; });
    return ok({ notification_setting: setting });
  }
  if (path === 'v52/membership/user_info') {
    return ok({ user_membership_info: { membership: true, paused: false, membership_tier: 'BLACK', admission_tier: 'BLACK', available_credits: 3, next_payment: at(18, 0, 0),
      current_membership_price: 99900, currency: 'sek', commitment_months: 12, committed_until: at(140, 0, 0), prolong_commitment: true, remaining_pause_days: 42, pause_days_total: 60 } });
  }
  if (path === 'v52/user_block/info') return ok({ user_block_info: { strike_count: 1, blocked: false, free_unlocks_remaining: 1, total_free_unlocks: 1 } });
  if (path === 'v52/payment') return ok({ payments: [
    { id: 71, created_at: at(-12, 3, 0), amount: 99900, currency: 'sek', type: 'MEMBERSHIP_RENEWAL', status: 'successful' },
    { id: 70, created_at: at(-42, 3, 0), amount: 99900, currency: 'sek', type: 'MEMBERSHIP_RENEWAL', status: 'successful' },
    { id: 69, created_at: at(-50, 14, 0), amount: 22000, currency: 'sek', type: 'BOOKING', status: 'successful' }] });
  if (path === 'v52/payment/method') return ok({ payment_methods: [{ id: 1, name: 'Visa •••• 4242', type: 'CARD', expiration: 1228, default: true }] });
  if (path === 'v52/booking/voucher') return ok({ booking_vouchers: [{ id: 1, code: 'DEMO-FRIEND-1', used: false }, { id: 2, code: 'DEMO-FRIEND-2', used: true }] });
  return err(404, 'Not available in the demo: ' + path);
}
