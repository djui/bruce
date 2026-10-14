/* Offline demo backend for Brüce Web. Answers the same /v52 routes as api.bruce.app with placeholder data
   (no personal data, mirrors Shared/BruceCore/Demo.swift). Nothing leaves the browser in demo mode. */
(function () {
  'use strict';

  function at(dayOffset, h, m) {
    const d = new Date();
    d.setDate(d.getDate() + dayOffset);
    d.setHours(h, m, 0, 0);
    return d.toISOString();
  }
  const studios = [
    { id: 1724, name: 'STC Rosenlundsparken', status: 'LIVE', vicinity: 'Södermalm', city_id: 1, qr_code_id: 'stc:13994',
      photo: 'k5pxisc2ienijh72umlm', rating: { total: 270, average: 470 }, has_openings: true, has_classes: true,
      studio_categories: [{ category: { id: 1, title: 'Gym' } }],
      studio_addresses: [{ main: true, address: { address: 'Example street 1', zip_code: '118 00', city: 'Stockholm', latitude: 59.3165, longitude: 18.06 } }],
      description: 'A placeholder gym used for the offline demo. Strength and cardio areas, open early to late.\n\n**Good to know**\n\n* Showers in every changing room.\n* Towels for rent at the desk.\n* Indoor shoes only in the training hall.',
      studio_facilities: [{ facility: { code: 'changing', title: 'Changing room' } }, { facility: { code: 'shower', title: 'Shower' } }] },
    { id: 1489, name: 'Example Yoga Studio', status: 'LIVE', vicinity: 'Vasastan', city_id: 1, qr_code_id: '930',
      integration_door_type: 'parakey', photo: 'mfrnofbzeqyucdflpasg', rating: { total: 120, average: 482 }, has_classes: true,
      studio_categories: [{ category: { id: 2, title: 'Yoga' } }],
      studio_addresses: [{ main: true, address: { address: 'Example road 4', zip_code: '104 05', city: 'Stockholm', latitude: 59.3655, longitude: 18.057 } }],
      studio_facilities: [{ facility: { code: 'shower', title: 'Shower' } }, { facility: { code: 'locker', title: 'Locker' } }],
      alerts: [{ id: 1, type: 'INFO', message: 'Placeholder notice: the front door code changes on Mondays.', start_date: at(-2, 0, 0) }],
      description: 'A placeholder studio used for the offline demo. Calm rooms, heated floors and mats for everyone.' },
    { id: 9520, name: 'Example Wellness', status: 'LIVE', vicinity: 'Kungsholmen', city_id: 1, label: 'WELLNESS',
      photo: 'xdz9eqgslqobguwuiqn8', rating: { total: 41, average: 455 }, has_classes: true,
      studio_categories: [{ category: { id: 25, title: 'Spa' } }],
      studio_addresses: [{ main: true, address: { address: 'Example square 9', zip_code: '112 20', city: 'Stockholm', latitude: 59.332, longitude: 18.03 } }],
      description: 'A placeholder wellness studio for the offline demo.' },
  ];
  const templates = [
    [1489, 'Morning Flow', 7, 0, 60, 'Instructor D', 14, [2]],
    [1724, 'Full Body Strength', 7, 30, 45, 'Instructor B', 20, [26]],
    [1489, 'Morning Meditation', 9, 0, 45, 'Instructor E', 12, [5]],
    [1724, 'High Intensity', 11, 30, 45, 'Instructor A', 20, [12]],
    [9520, 'Salt Cave', 12, 0, 45, '**Instructor G - English speaking', 6, []],
    [1724, 'Functional', 17, 0, 45, 'Instructor F', 12, [12]],
    [1489, 'Hatha Flow', 18, 0, 75, 'Instructor C', 16, [2]],
    [1724, 'Hyrox Prep', 18, 45, 60, 'Instructor A', 18, [13]],
    [9520, 'Red Light', 19, 30, 30, null, 4, []],
    [1489, 'Yin Yoga', 20, 0, 60, 'Instructor C', 16, [2]],
  ];
  const classes = {};
  for (let day = 0; day < 7; day++) {
    templates.forEach((t, i) => {
      const id = 9000 + day * 100 + i;
      const start = at(day, t[2], t[3]);
      const end = new Date(new Date(start).getTime() + t[4] * 60000).toISOString();
      const free = 1 + ((id * 7) % t[6]);
      classes[id] = {
        id, studio_id: t[0], presentation_studio_id: t[0], title: t[1], start_time: start, end_time: end, instructor: t[5],
        spots: t[6], available_spots: i === 5 ? 0 : free, canceled: false, deleted: false,
        unbookable_latest: 43200, unbookable_latest_time: new Date(new Date(start).getTime() - 43200000).toISOString(),
        early_check_in_minutes: 30, late_check_in_minutes: 5,
        class_categories: t[7].map((c) => ({ category_id: c, main: true })),
        description: i === 3 ? 'A placeholder interval class for the offline demo.\n\nShort, *hard* intervals with **active rest**:\n\n1. Warm-up\n2. Four rounds of intervals\n3. Stretch' : 'A placeholder class for the offline demo.',
        alert: i === 5 ? 'Placeholder notice: this class is held in the outdoor area.' : null,
      };
    });
  }
  const categories = [
    { id: 1, title: 'Gym' }, { id: 2, title: 'Yoga' }, { id: 5, title: 'Meditation' }, { id: 12, title: 'High-intensity' },
    { id: 13, title: 'Hyrox' }, { id: 25, title: 'Spa' }, { id: 26, title: 'Strength' },
  ];
  let nextId = 500;
  const bookings = [{ id: 401, class_id: 9103, studio_id: 1724, checked_in_at: null }, { id: 402, class_id: 9206, studio_id: 1489, checked_in_at: null }];
  const standbys = [{ id: 77, class_id: 9105 }];
  const favorites = [{ id: 11, studio_id: 1489 }];
  const user = { id: 1, first_name: 'Demo', last_name: 'User', email: 'demo@example.com', social: true };

  function withStudio(c) {
    const s = studios.find((x) => x.id === c.studio_id);
    return Object.assign({}, c, { studio: s ? { id: s.id, name: s.name, photo: s.photo, vicinity: s.vicinity, alerts: s.alerts } : null });
  }
  function err(status, message) { return { status, body: { errors: [{ code: 'DEMO', message, status }] } }; }
  function ok(body) { return { status: 200, body }; }
  const page = { metadata: { pagination: { next_cursor: null } } };

  function handle(method, path, q, body) {
    let m;
    if (method === 'DELETE' && path === 'v52/access/logout') return ok({});
    if (path === 'v52/location/city') return ok({ cities: [{ id: 1, name: 'Stockholm', code: 'STO', time_zone: 'Europe/Stockholm' }, { id: 2, name: 'Göteborg', code: 'GOT', time_zone: 'Europe/Stockholm' }] });
    if (path === 'v52/category') return ok({ categories });
    if (path === 'v52/studio/filter') return ok(Object.assign({ studios }, page));
    if ((m = path.match(/^v52\/studio\/(\d+)$/))) {
      const s = studios.find((x) => x.id === +m[1]);
      return s ? ok({ studio: s }) : err(404, 'Studio not found');
    }
    if (path === 'v52/studio/user_visit_limit') {
      return ok({ limits: [
        { type: 'MONTHLY', total: 0, used: 6, remaining: 0, resets_at: at(20, 0, 0) },
        { type: 'WELLNESS_MONTHLY', total: 4, used: 1, remaining: 3, resets_at: at(20, 0, 0) },
        { type: 'SIMULTANEOUS', total: 4, used: bookings.length, remaining: 4 - bookings.length },
      ] });
    }
    if (path === 'v52/studio/class/alternative_recommendation') {
      const c = classes[+q.class_id];
      const cards = Object.values(classes).filter((x) => c && x.id !== c.id && x.available_spots > 0 &&
        Math.abs(new Date(x.start_time) - new Date(c.start_time)) < 4 * 3600000).slice(0, 4)
        .map((x) => ({ id: x.id, title: x.title, start_time: x.start_time, end_time: x.end_time, distance: 1200, studio: { id: x.studio_id, name: studios.find((s) => s.id === x.studio_id).name } }));
      return ok({ class_cards: cards });
    }
    if (path === 'v52/class') {
      const from = q.start_time_after ? new Date(q.start_time_after) : new Date(0);
      const to = q.start_time_before ? new Date(q.start_time_before) : new Date(8.64e15);
      let list = Object.values(classes).filter((c) => new Date(c.start_time) >= from && new Date(c.start_time) < to);
      if (q.studio_id) list = list.filter((c) => c.studio_id === +q.studio_id);
      return ok(Object.assign({ classes: list.sort((a, b) => a.start_time.localeCompare(b.start_time)) }, page));
    }
    if ((m = path.match(/^v52\/class\/(\d+)$/))) {
      const c = classes[+m[1]];
      return c ? ok({ class: withStudio(c) }) : err(404, 'Class not found');
    }
    if (path === 'v52/booking' && method === 'GET') {
      return ok(Object.assign({ bookings: bookings.map((b) => Object.assign({}, b, { class: withStudio(classes[b.class_id]) })) }, page));
    }
    if (path === 'v52/booking' && method === 'POST') {
      const c = classes[body.class_id];
      if (!c) return err(404, 'Class not found');
      if (c.available_spots <= 0) return err(400, 'The class is fully booked.');
      if (bookings.some((b) => b.class_id === c.id)) return err(400, 'You have already booked this class.');
      c.available_spots -= 1;
      const b = { id: nextId++, class_id: c.id, studio_id: c.studio_id, checked_in_at: null };
      bookings.push(b);
      return ok({ booking: b });
    }
    if ((m = path.match(/^v52\/booking\/(\d+)$/)) && method === 'DELETE') {
      const i = bookings.findIndex((b) => b.id === +m[1]);
      if (i < 0) return err(404, 'Booking not found');
      classes[bookings[i].class_id].available_spots += 1;
      const [b] = bookings.splice(i, 1);
      return ok({ booking: Object.assign({}, b, { deleted: true, deleted_at: new Date().toISOString() }) });
    }
    if (path === 'v52/standby' && method === 'GET') {
      return ok({ standbys: standbys.map((s) => ({ id: s.id, class: withStudio(classes[s.class_id]) })) });
    }
    if (path === 'v52/standby' && method === 'POST') {
      const s = { id: nextId++, class_id: body.class_id };
      standbys.push(s);
      return ok({ standby: s });
    }
    if ((m = path.match(/^v52\/standby\/(\d+)$/)) && method === 'DELETE') {
      const i = standbys.findIndex((s) => s.id === +m[1]);
      if (i >= 0) standbys.splice(i, 1);
      return ok({});
    }
    if (path === 'v52/favorite' && method === 'GET') {
      return ok({ favorites: q.studio_id ? favorites.filter((f) => f.studio_id === +q.studio_id) : favorites });
    }
    if (path === 'v52/favorite' && method === 'POST') {
      const f = { id: nextId++, studio_id: body.studio_id };
      favorites.push(f);
      return ok({ favorite: f });
    }
    if ((m = path.match(/^v52\/favorite\/(\d+)$/)) && method === 'DELETE') {
      const i = favorites.findIndex((f) => f.id === +m[1]);
      if (i >= 0) favorites.splice(i, 1);
      return ok({});
    }
    if (path === 'v52/user/1') return ok({ user });
    if (path === 'v52/membership/user_info') {
      return ok({ user_membership_info: { membership: true, paused: false, membership_tier: 'BLACK', available_credits: 3, next_payment: at(18, 0, 0), current_membership_price: 59900, currency: 'sek' } });
    }
    if (path === 'v52/user_block/info') return ok({ user_block_info: { strike_count: 1, blocked: false, free_unlocks_remaining: 1 } });
    return err(404, 'Not available in the demo: ' + path);
  }

  window.BruceDemo = {
    userId: 1,
    request(method, path, query, body) {
      return new Promise((resolve) => setTimeout(() => resolve(handle(method, path, query || {}, body || {})), 120 + Math.random() * 180));
    },
  };
})();
