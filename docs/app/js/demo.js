// Offline demo backend: answers the same /v52 routes as api.bruce.app with placeholder data (no personal data,
// modelled on Shared/BruceCore/Demo.swift). Nothing leaves the browser in demo mode.

import { byStart } from './util.js';

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
  { id: 3001, name: 'Example Swim Hall', status: 'LIVE', vicinity: 'Södermalm', city_id: 1, qr_code_id: '3001',
    photo: null, rating: { total: 64, average: 448 }, has_classes: true,
    studio_categories: [cat(30, 'Swimming')], studio_addresses: addr('Example pool lane 2', '118 25', 59.3087, 18.0756),
    visit_limit: { items: [{ label: 'BASE', limit: 0 }, { label: 'BLACK', limit: 0 }, { label: 'EPIC', limit: 0 }] },
    description: 'A placeholder swim hall for the offline demo. Six 25 m lanes.' },
  { id: 3002, name: 'Example Reformer Loft', status: 'LIVE', vicinity: 'Norrmalm', city_id: 1, qr_code_id: '3002',
    photo: null, rating: { total: 102, average: 476 }, has_classes: true,
    studio_categories: [cat(19, 'Pilates')], studio_addresses: addr('Example street 30', '111 57', 59.3352, 18.0628),
    visit_limit: { items: [{ label: 'BASE', limit: 0 }, { label: 'BLACK', limit: 0 }, { label: 'EPIC', limit: 0 }] },
    description: 'A placeholder reformer pilates studio for the offline demo.' },
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
  [3002, 'Reformer', 7, 0, 50, 'Instructor J', 10, [19]],
  [3002, 'Reformer', 12, 5, 45, 'Instructor J', 10, [19]],
  [3001, 'Lap Swim', 12, 0, 45, null, 30, [30]],
  [1724, 'Strength Circuit', 17, 45, 45, 'Instructor B', 3, [26]],
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
  { id: 19, title: 'Pilates', photo: 'xdz9eqgslqobguwuiqn8' }, { id: 25, title: 'Spa' }, { id: 26, title: 'Strength' }, { id: 30, title: 'Swimming' },
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
// This year's history for Statistics, goals, For you and Wrapped: a seeded, made-up routine of early classes and
// gym drop-ins (an Early Bird), with Friend One along for some of the classes.
const pastClasses = {};
const pastFriendBookings = [];
{
  let seed = 7;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  const routine = [
    // [studio, title, hour, minute, minutes, categories, chance on a weekday, chance on a weekend day, max per month]
    [3002, 'Reformer', 7, 0, 50, [19], 0.2, 0.05, 9],
    [1724, 'Full Body Strength', 7, 30, 45, [26], 0.12, 0, 6],
    [3001, 'Lap Swim', 7, 0, 45, [30], 0.05, 0.12, 3],
    [1724, 'High Intensity', 11, 30, 45, [12], 0.07, 0, 4],
    [2001, 'Bouldering Basics', 17, 30, 90, [7], 0, 0.1, 2],
    [1489, 'Hatha Flow', 18, 0, 75, [2], 0.03, 0, 1],
  ];
  const year = new Date().getFullYear();
  const days = Math.floor((Date.now() - new Date(year, 0, 1)) / 86400000);
  let id = 20000;
  const perMonth = {};
  for (let d = 0; d < days; d++) {
    const day = new Date(year, 0, 1 + d);
    const weekend = day.getDay() === 0 || day.getDay() === 6;
    const off = Date.now() - day.getTime() < 2 * 86400000;   // the last two days are in `past` above
    if (off) continue;
    let did = false;
    for (const [sid, title, h, m, len, cats, wd, we, max] of routine) {
      const mk = day.getMonth() + ':' + title;
      if (did || (perMonth[mk] || 0) >= max || rnd() > (weekend ? we : wd)) continue;
      const start = new Date(day); start.setHours(h, m, 0, 0);
      const cid = 30000 + id;
      pastClasses[cid] = { id: cid, studio_id: sid, title, start_time: start.toISOString(), end_time: new Date(start.getTime() + len * 60000).toISOString(),
        instructor: 'Instructor J', class_categories: cats.map((c) => ({ category_id: c })) };
      past.push({ id: id++, user_id: 1, class_id: cid, studio_id: sid, checked_in_at: new Date(start.getTime() - 9 * 60000).toISOString(), review_id: 1 });
      if (rnd() < 0.3) pastFriendBookings.push({ id: 60000 + id, user_id: 21, class_id: cid });
      else if (rnd() < 0.1) pastFriendBookings.push({ id: 60000 + id, user_id: 22, class_id: cid });
      perMonth[mk] = (perMonth[mk] || 0) + 1; did = true;
    }
    if (!did && !weekend && rnd() < 0.42) {
      const at = new Date(day); at.setHours(6, 35 + Math.floor(rnd() * 20), 0, 0);
      past.push({ id: id++, user_id: 1, class_id: null, studio_id: 1724, checked_in_at: at.toISOString() });
    }
  }
}
const klass = (id) => classes[id] || pastClasses[id];
const monthOf = (iso) => (iso || '').slice(0, 7) === new Date().toISOString().slice(0, 7);

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
      const used = past.filter((b) => b.studio_id === +q.studio_id && monthOf(b.checked_in_at)).length;
      return ok({ limits: [{ type: 'STUDIO', total: item ? item.limit : 0, used, remaining: item && item.limit > 0 ? item.limit - used : 0, resets_at: at(18, 0, 0), items: s ? s.visit_limit.items : [] }] });
    }
    return ok({ limits: [
      { type: 'MONTHLY', total: 0, used: past.filter((b) => monthOf(b.checked_in_at)).length, remaining: 0, resets_at: at(18, 0, 0) },
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
    return list('classes', l.sort(byStart));
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
    for (let i = 0; i < 9; i++) {
      const d = new Date(); d.setMonth(d.getMonth() - i, 5);
      const n = past.filter((b) => b.checked_in_at && b.checked_in_at.slice(0, 7) === d.toISOString().slice(0, 7)).length;
      out.push({ day: +d.toISOString().slice(0, 10).replace(/-/g, ''), count: n || [0, 9, 12, 7, 0, 4, 10, 8, 6][i] });
    }
    return ok({ booking_aggregates: out });
  }
  if (path === 'v52/booking' && G) {
    const full = (b) => Object.assign({}, b, { class: b.class_id ? withStudio(klass(b.class_id)) : null });
    if (q.class_id) {
      const ids = bookings.filter((b) => b.class_id === +q.class_id).map((b) => ({ id: b.id, user_id: 1, user: users[1] }));
      friendBookings.filter((b) => b.class_id === +q.class_id).forEach((b) => ids.push({ id: b.id, user_id: b.user_id, user: users[b.user_id] }));
      ids.push({ id: 990 }, { id: 991 });
      return list('bookings', ids);
    }
    if (q.friends) {
      // Friends' bookings from a day on (yyyymmdd): the upcoming ones, plus this year's past ones when asked for.
      const since = q.class_day_after && q.class_day_after < new Date().toISOString().slice(0, 10).replace(/-/g, '');
      return list('bookings', (since ? pastFriendBookings : []).concat(friendBookings).map((b) => Object.assign({}, b, { class: withStudio(klass(b.class_id)) })));
    }
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

// ---------------------------------------------------------------- our server (challenges, percentiles, goals)
// Fake answers in the shape of CONTRACT.md, so challenges and Wrapped percentiles work offline in the demo.

const nameOf = (id) => (users[id] ? users[id].first_name + (id === 1 ? '' : ' ' + users[id].last_name) : 'Member');
function monthPeriod(offset) {
  const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() + (offset || 0));
  const y = d.getFullYear(), m = d.getMonth();
  const key = (day) => y + '-' + String(m + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
  const days = new Date(y, m + 1, 0).getDate();
  const today = offset ? 0 : new Date().getDate();
  return { start: key(1), end: key(days), label: d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }), day: today, days, daysLeft: offset ? days : days - today };
}
const demoChallenges = [
  { id: 'demoMostCls1', title: 'Most classes', metric: 'classes', target: null, category: null, categoryTitle: null, repeatMonthly: true, ownerId: 21,
    status: { 1: 'accepted', 21: 'accepted', 22: 'accepted', 23: 'accepted' }, base: { 21: 13, 1: 11, 22: 9, 23: 6 } },
  { id: 'demoHits12x2', title: 'Everyone hits 12', metric: 'target', target: 12, category: null, categoryTitle: null, repeatMonthly: false, ownerId: 22,
    status: { 22: 'accepted', 1: 'invited', 23: 'accepted' }, base: { 22: 8, 23: 12, 1: 0 } },
];
const demoUsesBruce = [21, 22];
function summaryOf(c) {
  const period = c.period || monthPeriod(0);
  return {
    id: c.id, title: c.title, metric: c.metric, target: c.target, category: c.category, categoryTitle: c.categoryTitle,
    start: c.start || period.start, end: c.end || period.end, repeatMonthly: c.repeatMonthly, ownerId: c.ownerId, ownerName: nameOf(c.ownerId),
    myStatus: c.status[1], participants: Object.keys(c.status).map((id) => ({ userId: +id, name: nameOf(+id), status: c.status[id] })),
    period, shareUrl: 'https://djui.github.io/bruce/app/#challenge/' + c.id, createdAt: at(-14, 9, 0),
  };
}
function daily(n, days, seed) {
  const out = Array(days).fill(0);
  for (let i = 0; i < n; i++) out[(i * 7 + seed * 3 + Math.floor(i / 3)) % days] += 1;
  return out;
}
const STUDIO_ROT = [[3002, 'Reformer'], [1724, 'Full Body Strength'], [1489, 'Hatha Flow'], [2001, 'Bouldering Basics']];
function entryFor(c, id, period) {
  const accepted = c.status[id] === 'accepted';
  const scale = Math.max(1, period.day) / 14;
  const visits = accepted ? Math.max(0, Math.round((c.base[id] || 0) * scale)) : 0;
  const classes = Math.max(0, visits - (id % 3));
  const [sid, title] = STUDIO_ROT[id % STUDIO_ROT.length];
  const days = Math.max(1, period.day);
  return {
    userId: id, name: id === 1 ? nameOf(1) : nameOf(id), status: c.status[id], rank: null, score: 0,
    visits, classes, dropins: visits - classes, minutes: classes * 50 + (visits - classes) * 60, studios: accepted ? 1 + (id % 3) : 0,
    topStudio: visits ? { id: sid, name: null, count: Math.ceil(visits / 2) } : null, topClass: classes ? { title, count: Math.ceil(classes / 2) } : null,
    categories: classes ? [{ key: '19', count: Math.ceil(classes / 2) }, { key: 'gym', count: visits - classes }].filter((x) => x.count) : [],
    together: id === 1 ? 0 : Math.min(visits, 8 - (id % 4) * 2),
    lastVisit: visits ? at(id === 23 ? -6 : -(id % 2), 7, 0) : null, done: c.metric === 'target' && visits >= c.target,
    daily: accepted ? daily(visits, days, id) : Array(days).fill(0),
    recent: Array.from({ length: Math.min(visits, 6) }, (_, i) => ({ at: at(-i * 2 - (id % 2), 7, 0), kind: i % 3 === 2 ? 'dropin' : 'class',
      title: i % 3 === 2 ? null : STUDIO_ROT[(id + i) % STUDIO_ROT.length][1], studioId: i % 3 === 2 ? 1724 : STUDIO_ROT[(id + i) % STUDIO_ROT.length][0], studio: null })),
  };
}
function detailOf(c) {
  const s = summaryOf(c);
  const metric = { classes: 'classes', visits: 'visits', minutes: 'minutes', target: 'visits' }[c.metric];
  const rows = Object.keys(c.status).map((id) => entryFor(c, +id, s.period));
  rows.forEach((r) => { r.score = r[metric]; });
  const acc = rows.filter((r) => r.status === 'accepted').sort((a, b) => b.score - a.score);
  acc.forEach((r, i) => { r.rank = i && acc[i - 1].score === r.score ? acc[i - 1].rank : i + 1; });
  const board = acc.concat(rows.filter((r) => r.status !== 'accepted'));
  const months = [{ month: s.period.start.slice(0, 7), label: s.period.label, entries: acc.map((r) => ({ userId: r.userId, name: r.name, score: r.score, visits: r.visits, classes: r.classes, dropins: r.dropins, minutes: r.minutes })) }];
  if (c.repeatMonthly) {
    const prev = monthPeriod(-1);
    months.push({ month: prev.start.slice(0, 7), label: prev.label, entries: acc.map((r, i) => {
      const v = [17, 15, 12, 9][i] || 5;
      return { userId: r.userId, name: r.name, score: c.metric === 'minutes' ? v * 52 : v, visits: v + 1, classes: v, dropins: 1, minutes: v * 52 };
    }).sort((a, b) => b.score - a.score) });
  }
  return { challenge: s, leaderboard: board, months, updatedAt: at(0, 4, 30) };
}

export function handleServer(method, path, body) {
  let m;
  const ok2 = (b) => ({ status: 200, body: b });
  const fail = (status, error) => ({ status, body: { error } });
  if (path === '/challenges' && method === 'GET') return ok2({ challenges: demoChallenges.map(summaryOf), usesBruce: demoUsesBruce });
  if (path === '/challenges' && method === 'POST') {
    const status = { 1: 'accepted' };
    (body.invite || []).filter((id) => users[id]).slice(0, 20).forEach((id) => { status[id] = 'invited'; });
    const today = new Date();
    const c = { id: 'demo' + Math.random().toString(36).slice(2, 10), title: body.title || 'Challenge', metric: body.metric, target: body.target || null,
      category: body.category || null, categoryTitle: body.categoryTitle || null, repeatMonthly: !!body.repeatMonthly, ownerId: 1, status, base: { 1: 0 },
      start: body.start, end: body.end };
    if (!body.repeatMonthly) {
      const s = new Date(body.start + 'T12:00:00'), e = new Date(body.end + 'T12:00:00');
      const days = Math.round((e - s) / 86400000) + 1;
      const day = Math.max(0, Math.min(days, Math.round((today - s) / 86400000) + 1));
      c.period = { start: body.start, end: body.end, label: s.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ' – ' + e.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }), day, days, daysLeft: days - day };
    }
    demoChallenges.unshift(c);
    return { status: 201, body: { challenge: summaryOf(c) } };
  }
  if ((m = path.match(/^\/challenges\/([\w-]+)\/(accept|join)$/)) && method === 'POST') {
    let c = demoChallenges.find((x) => x.id === m[1]);
    if (!c && m[2] === 'join') {
      c = { id: m[1], title: 'Most minutes', metric: 'minutes', target: null, category: null, categoryTitle: null, repeatMonthly: true, ownerId: 23, status: { 23: 'accepted', 21: 'accepted' }, base: { 23: 10, 21: 7 } };
      demoChallenges.unshift(c);
    }
    if (!c) return fail(404, 'Challenge not found');
    c.status[1] = 'accepted'; c.base[1] = c.base[1] || 4;
    return ok2({ ok: true, challenge: summaryOf(c) });
  }
  if ((m = path.match(/^\/challenges\/([\w-]+)\/leave$/)) && method === 'POST') {
    const i = demoChallenges.findIndex((x) => x.id === m[1]);
    if (i >= 0) { delete demoChallenges[i].status[1]; if (!Object.values(demoChallenges[i].status).includes('accepted') || demoChallenges[i].ownerId === 1) demoChallenges.splice(i, 1); }
    return ok2({ ok: true });
  }
  if ((m = path.match(/^\/challenges\/([\w-]+)$/)) && method === 'GET') {
    const c = demoChallenges.find((x) => x.id === m[1]);
    if (c && c.status[1]) return ok2(detailOf(c));
    // Someone else's challenge opened from a share link: the preview.
    return ok2({ challenge: { id: m[1], title: 'Most minutes', metric: 'minutes', target: null, categoryTitle: null, period: monthPeriod(0), ownerName: nameOf(23), participantCount: 2 }, joinable: true });
  }
  if (path.startsWith('/wrapped/percentiles')) return ok2({ year: new Date().getFullYear(), cohort: 23, percentiles: { visits: 92, minutes: 88, studios: 70, streak: 79 } });
  if (path === '/me/goals' && method === 'PUT') return ok2({ ok: true, goals: (body.goals || []).length });
  if (path === '/me' && method === 'GET') return ok2({ waitlist: [] });
  return fail(404, 'Not available in the demo: ' + path);
}
