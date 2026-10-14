/* Brüce Web: an unofficial Bruce Studios client that runs in the browser.
   Talks to https://api.bruce.app directly (the API answers CORS with `*`), with the same routes and parameters
   as the Swift apps (Shared/BruceCore/API*.swift, documented in API.md). The access token stays in this
   browser's localStorage and is only ever sent to api.bruce.app. No build step, no dependencies. */
(function () {
  'use strict';

  const DEFAULT_API = 'https://api.bruce.app';
  const IMG = 'https://res.cloudinary.com/dbo5hzaqa/image/upload/c_fill,dpr_2,h_{h},q_60,w_{w}/{id}.jpg';
  const STUDIO_FIELDS = 'checkin_studio_id,city_id,deleted,has_address,has_classes,has_openings,id,integration_door_type,keyword,label,name,photo,qr_code_id,rating,remote,requires_additional_cost,status,tier_level,time_zone,vicinity,visit_limit_id';
  const STUDIO_CACHE_MS = 12 * 3600 * 1000;

  // ---------------------------------------------------------------- storage
  const ls = {
    get(k, fallback) { try { const v = localStorage.getItem(k); return v == null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* quota or private mode */ } },
    del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } },
  };

  const S = {
    session: ls.get('bruce.session', null),          // {token, userId, demo}
    settings: Object.assign({ cityId: 1, apiBase: DEFAULT_API }, ls.get('bruce.settings', {})),
    cities: [], categories: [], studios: new Map(),  // studio id -> slim studio
    bookings: new Map(),                             // class id -> booking (with class)
    standbys: new Map(),                             // class id -> standby (with class)
    favorites: new Map(),                            // studio id -> favorite id
    classCache: new Map(),                           // "city:day" -> {at, classes}
    filters: { q: '', cat: null, free: false, favs: false },
    studioQuery: '',
    studiosLoading: null,
  };
  const saveSettings = () => ls.set('bruce.settings', S.settings);
  const isDemo = () => !!(S.session && S.session.demo);

  // ---------------------------------------------------------------- helpers
  const $ = (sel, root) => (root || document).querySelector(sel);
  const main = $('#main');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const img = (id, w, h) => (id ? IMG.replace('{w}', w || 400).replace('{h}', h || 250).replace('{id}', encodeURIComponent(id)) : '');
  const city = () => S.cities.find((c) => c.id === S.settings.cityId) || { id: S.settings.cityId, name: 'Stockholm', time_zone: 'Europe/Stockholm' };
  const tz = () => city().time_zone || 'Europe/Stockholm';

  function fmt(iso, opts) {
    if (!iso) return '';
    try { return new Intl.DateTimeFormat('en-GB', Object.assign({ timeZone: tz() }, opts)).format(new Date(iso)); } catch (e) { return ''; }
  }
  const timeOf = (iso) => fmt(iso, { hour: '2-digit', minute: '2-digit', hour12: false });
  /** YYYY-MM-DD of a date in the city's time zone. */
  function dayKey(d) {
    const p = new Intl.DateTimeFormat('en-CA', { timeZone: tz(), year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d);
    const g = (t) => p.find((x) => x.type === t).value;
    return g('year') + '-' + g('month') + '-' + g('day');
  }
  function addDays(key, n) {
    const [y, m, d] = key.split('-').map(Number);
    const t = new Date(Date.UTC(y, m - 1, d + n, 12));
    return t.toISOString().slice(0, 10);
  }
  const todayKey = () => dayKey(new Date());
  function dayLabel(key) {
    const t = todayKey();
    const noon = new Date(key + 'T12:00:00Z');
    const name = new Intl.DateTimeFormat('en-GB', { weekday: 'short', timeZone: 'UTC' }).format(noon);
    const num = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(noon);
    if (key === t) return ['Today', num];
    if (key === addDays(t, 1)) return ['Tomorrow', num];
    return [name, num];
  }
  function longDay(iso) {
    const k = dayKey(new Date(iso));
    if (k === todayKey()) return 'Today, ' + fmt(iso, { day: 'numeric', month: 'long' });
    if (k === addDays(todayKey(), 1)) return 'Tomorrow, ' + fmt(iso, { day: 'numeric', month: 'long' });
    return fmt(iso, { weekday: 'long', day: 'numeric', month: 'long' });
  }
  const minutes = (a, b) => (a && b ? Math.round((new Date(b) - new Date(a)) / 60000) : null);
  const instructor = (s) => (s ? s.replace(/\*\*/g, '').trim() || null : null);
  const isListed = (c) => c && c.deleted !== true && !c.deleted_at && c.canceled !== true;
  const rating = (r) => (r && r.average > 0 ? (r.average / 100).toFixed(1) : null);

  /** Tiny Markdown subset (paragraphs, **bold**, *italic*, lists, links) on escaped text. */
  function rich(md) {
    if (!md) return '';
    const inline = (s) => esc(s)
      .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
      .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, '$1<i>$2</i>')
      .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    return md.replace(/\r/g, '').split(/\n{2,}/).map((block) => {
      const lines = block.split('\n');
      if (lines.every((l) => /^\s*[*-]\s+/.test(l))) return '<ul>' + lines.map((l) => '<li>' + inline(l.replace(/^\s*[*-]\s+/, '')) + '</li>').join('') + '</ul>';
      if (lines.every((l) => /^\s*\d+[.)]\s+/.test(l))) return '<ol>' + lines.map((l) => '<li>' + inline(l.replace(/^\s*\d+[.)]\s+/, '')) + '</li>').join('') + '</ol>';
      return '<p>' + lines.map(inline).join('<br>') + '</p>';
    }).join('');
  }

  let toastTimer;
  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg; t.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2800);
  }
  function confirmDialog(title, body, okLabel, danger) {
    const d = $('#confirm');
    $('#confirm-title').textContent = title;
    $('#confirm-body').textContent = body;
    const ok = $('#confirm-ok');
    ok.textContent = okLabel || 'OK';
    ok.className = 'btn ' + (danger === false ? '' : 'danger');
    return new Promise((resolve) => {
      d.addEventListener('close', () => resolve(d.returnValue === 'ok'), { once: true });
      d.returnValue = '';
      d.showModal();
    });
  }

  // ---------------------------------------------------------------- API
  class ApiError extends Error { constructor(status, message) { super(message); this.status = status; } }

  function qs(query) {
    // Brackets stay literal like the official app sends them (filter[status][in]=live).
    return Object.entries(query || {}).filter(([, v]) => v != null)
      .map(([k, v]) => encodeURIComponent(k).replace(/%5B/g, '[').replace(/%5D/g, ']') + '=' + encodeURIComponent(v)).join('&');
  }
  function errorText(body, status) {
    const e = body && body.errors && body.errors[0];
    const msg = e && (e.message || e.code);
    return msg ? String(msg).trim() : 'Request failed (HTTP ' + status + ').';
  }

  async function api(method, path, query, body) {
    const q = Object.assign({ locale: 'en' }, query || {});
    if (isDemo()) {
      const r = await window.BruceDemo.request(method, path, q, body && Object.assign({ locale: 'en' }, body));
      if (r.status >= 300) throw new ApiError(r.status, errorText(r.body, r.status));
      return r.body;
    }
    const headers = { Accept: 'application/json' };
    if (S.session && S.session.token) headers['X-Access-Token'] = S.session.token;
    const init = { method, headers };
    if (body) { headers['Content-Type'] = 'application/json'; init.body = JSON.stringify(Object.assign({ locale: 'en' }, body)); }
    const base = (S.settings.apiBase || DEFAULT_API).replace(/\/+$/, '');
    let res;
    try { res = await fetch(base + '/' + path + '?' + qs(q), init); }
    catch (e) { throw new ApiError(0, 'Could not reach the Bruce server. Check your connection.'); }
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : {}; } catch (e) { json = null; }
    if (res.status === 401 && S.session) { endSession(); toast('Your session ended. Please log in again.'); route(); }
    if (!res.ok) throw new ApiError(res.status, errorText(json, res.status));
    return json || {};
  }

  /** Pages a list endpoint by `metadata.pagination.next_cursor`; `onPage` sees each page's items. */
  async function paged(path, query, key, onPage, maxPages) {
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

  const Bruce = {
    login: (email, password) => api('POST', 'v52/access/authenticate', null, { authenticator: 'PASSWORD', email, password }),
    logout: () => api('DELETE', 'v52/access/logout', null, {}),
    cities: () => api('GET', 'v52/location/city', { include_country: 'true' }).then((r) => (r.cities || []).filter((c) => !c.hidden)),
    categories: () => api('GET', 'v52/category', { 'filter[main][eq]': 'true' }).then((r) => r.categories || []),
    studio: (id) => api('GET', 'v52/studio/' + id, {
      include_addresses: 'true', include_addresses_address: 'true', include_studio_photos: 'true', include_studio_photos_photo: 'true',
      include_facilities: 'true', include_categories: 'true', include_alerts: 'true', exclude_expired_alerts: 'true',
    }).then((r) => r.studio),
    klass: (id) => api('GET', 'v52/class/' + id, {
      include_studio: 'true', include_info: 'true', include_class_categories: 'true', include_absolute_times: 'true',
      include_booking_credit_costs: 'true', include_studio_alerts: 'true', exclude_studio_expired_alerts: 'true',
      include_dynamic_prices: 'true', include_studio_user_attendance_info: 'true',
    }).then((r) => r.class),
    classes(key, opts, onPage) {
      const q = {
        start_time_after: key + 'T00:00:00', start_time_before: addDays(key, 1) + 'T00:00:00', limit: 30,
        is_recurring_base: 'false', is_master: 'false', dedicated: 'false', opening: 'false', studio_status: 'live', deleted: 'false',
        include_absolute_times: 'true', include_class_categories: 'true', include_booking_credit_costs: 'true', include_dynamic_prices: 'true',
      };
      if (opts.studioId) { q.studio_id = opts.studioId; q.presentation_studio_id = opts.studioId; } else q.studio_city_id = opts.cityId;
      return paged('v52/class', q, 'classes', onPage);
    },
    bookings: () => paged('v52/booking', {
      user_id: S.session.userId, limit: 30, deleted: 'false', include_class: 'true', include_class_studio: 'true',
      class_start_time_after: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
    }, 'bookings', null, 15),
    standbys: () => api('GET', 'v52/standby', {
      user_id: S.session.userId, include_class: 'true', include_class_studio: 'true', deleted: 'false', class_start_time_after: new Date().toISOString(),
    }).then((r) => r.standbys || []),
    book: (classId) => api('POST', 'v52/booking', null, { class_id: classId, booked_via: 'HOMESCREEN_SPOTLIGHT', include_user: false }),
    cancel: (bookingId) => api('DELETE', 'v52/booking/' + bookingId, null, { include_user: false }),
    joinWaitlist: (classId) => api('POST', 'v52/standby', null, { class_id: classId }),
    leaveWaitlist: (id) => api('DELETE', 'v52/standby/' + id, null, {}),
    favorites: () => api('GET', 'v52/favorite').then((r) => r.favorites || []),
    addFavorite: (studioId) => api('POST', 'v52/favorite', null, { studio_id: studioId }).then((r) => r.favorite),
    removeFavorite: (id) => api('DELETE', 'v52/favorite/' + id, null, {}),
    similar: (classId) => api('GET', 'v52/studio/class/alternative_recommendation', { class_id: classId }).then((r) => r.class_cards || []),
    user: () => api('GET', 'v52/user/' + S.session.userId).then((r) => r.user || r),
    membership: () => api('GET', 'v52/membership/user_info', { user_id: S.session.userId }).then((r) => r.user_membership_info),
    limits: () => api('GET', 'v52/studio/user_visit_limit', { user_id: S.session.userId }).then((r) => r.limits || []),
    blockInfo: () => api('GET', 'v52/user_block/info', { user_id: S.session.userId }).then((r) => r.user_block_info),
  };

  // ---------------------------------------------------------------- data loading
  function slimStudio(s) {
    const a = (s.studio_addresses || []).map((x) => x.address).filter(Boolean)[0] || {};
    return {
      id: s.id, name: s.name, vicinity: s.vicinity, photo: s.photo, city_id: s.city_id, label: s.label, rating: s.rating,
      cats: (s.studio_categories || []).map((c) => c.category && c.category.title).filter(Boolean),
      address: a.address, lat: a.latitude, lon: a.longitude, door: s.integration_door_type,
    };
  }
  function countryCode() { const c = city(); return ((c.country && c.country.code) || 'SE').toUpperCase(); }

  function loadStudios(onProgress) {
    if (S.studiosLoading) return S.studiosLoading;
    const key = 'bruce.studios.' + (isDemo() ? 'demo' : countryCode());
    const cached = ls.get(key, null);
    if (cached && Date.now() - cached.at < STUDIO_CACHE_MS && cached.studios.length) {
      cached.studios.forEach((s) => S.studios.set(s.id, s));
      S.studiosLoading = Promise.resolve();
      return S.studiosLoading;
    }
    S.studiosLoading = paged('v52/studio/filter', {
      'filter[status][in]': 'live', 'filter[country_code][eq]': countryCode(), fields: STUDIO_FIELDS,
      include: 'addresses,addresses_address,categories,categories_category,visit_limit', limit: 30,
    }, 'studios', (items, all) => { items.forEach((s) => S.studios.set(s.id, slimStudio(s))); if (onProgress) onProgress(all.length); }, 200)
      .then(() => ls.set(key, { at: Date.now(), studios: [...S.studios.values()] }))
      .catch((e) => { S.studiosLoading = null; throw e; });
    return S.studiosLoading;
  }

  async function loadMine() {
    const [b, s] = await Promise.all([Bruce.bookings(), Bruce.standbys().catch(() => [])]);
    S.bookings.clear(); S.standbys.clear();
    b.filter((x) => !x.deleted && x.class).forEach((x) => S.bookings.set(x.class_id || x.class.id, x));
    s.filter((x) => x.class).forEach((x) => S.standbys.set(x.class.id, x));
  }
  async function loadFavorites() {
    const f = await Bruce.favorites().catch(() => []);
    S.favorites.clear(); f.forEach((x) => S.favorites.set(x.studio_id, x.id));
  }
  async function bootstrap() {
    const [cities, cats] = await Promise.all([Bruce.cities().catch(() => []), Bruce.categories().catch(() => [])]);
    if (cities.length) S.cities = cities;
    S.categories = cats;
    // Bookings, favourites and studio names arrive after the first screen; redraw the class list once they do.
    loadMine().then(() => refreshIfOn('classes')).catch(() => {});
    loadFavorites().catch(() => {});
    loadStudios().then(() => refreshIfOn('classes')).catch(() => {});
  }
  function refreshIfOn(...tabs) { if (tabs.includes(currentTab)) route(); }

  function endSession() {
    S.session = null; ls.del('bruce.session');
    S.bookings.clear(); S.standbys.clear(); S.favorites.clear(); S.classCache.clear(); S.studios.clear(); S.studiosLoading = null;
  }

  // ---------------------------------------------------------------- class state
  function classState(c) {
    const b = S.bookings.get(c.id);
    if (b) return b.checked_in_at ? { label: 'Checked in', cls: 'booked' } : { label: 'Booked', cls: 'booked' };
    if (S.standbys.has(c.id)) return { label: 'Waitlist', cls: 'wait' };
    if (c.available_spots == null) return null;
    if (c.available_spots <= 0) return { label: 'Full', cls: 'full' };
    return { label: c.available_spots + ' left', cls: c.available_spots <= 3 ? '' : 'ok' };
  }
  function studioName(c) {
    const s = S.studios.get(c.studio_id) || c.studio;
    return s ? s.name : 'Studio ' + c.studio_id;
  }
  function classRow(c, opts) {
    const s = S.studios.get(c.studio_id) || c.studio || {};
    const st = classState(c);
    const dur = minutes(c.start_time, c.end_time);
    const sub = [(opts && opts.hideStudio) ? null : esc(s.name || 'Studio ' + c.studio_id), (opts && opts.hideStudio) ? null : esc(s.vicinity), esc(instructor(c.instructor))].filter(Boolean).join(' · ');
    return '<a class="item" href="#/class/' + c.id + '">' +
      '<div class="time"><b>' + timeOf(c.start_time) + '</b><small>' + (dur ? dur + ' min' : '') + '</small></div>' +
      '<div class="body"><h3>' + esc(c.title) + '</h3><p>' + (opts && opts.withDay ? esc(longDay(c.start_time)) + ' · ' : '') + sub + '</p></div>' +
      (st ? '<span class="badge ' + st.cls + '">' + st.label + '</span>' : '') + '</a>';
  }

  // ---------------------------------------------------------------- views
  let currentTab = null;
  let renderToken = 0;

  function setTab(tab) {
    currentTab = tab;
    document.querySelectorAll('#tabs a').forEach((a) => {
      if (a.dataset.tab === tab) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
  }
  function demoBanner() {
    return isDemo() ? '<div class="demo-banner">Demo mode with placeholder data. <button type="button" data-act="exit-demo">Log in for real</button></div>' : '';
  }
  /** Header photo; removed again if Cloudinary has no such image. */
  function hero(id) { return id ? '<img class="hero" src="' + img(id, 760, 428) + '" alt="" onerror="this.remove()">' : ''; }
  function backLink() { return '<button type="button" class="back" data-act="back">‹ Back</button>'; }

  function viewLogin() {
    setTab(null);
    $('#tabs').hidden = true;
    main.innerHTML = '<section class="login">' +
      '<img class="mark" src="../favicon.svg" alt="">' +
      '<h1>Brüce in your browser</h1>' +
      '<p class="muted">Book classes, manage your bookings and browse studios with your Bruce Studios account.</p>' +
      '<form id="login-form" class="card" autocomplete="on">' +
      '<label class="field"><span>Email</span><input type="email" name="email" autocomplete="username" required></label>' +
      '<label class="field"><span>Password</span><input type="password" name="password" autocomplete="current-password" required></label>' +
      '<p class="error small" id="login-error" role="alert"></p>' +
      '<button class="btn block" type="submit">Log in</button></form>' +
      '<div class="divider">or</div>' +
      '<button class="btn ghost block" type="button" data-act="demo">Try the demo</button>' +
      '<p class="disclaimer">Unofficial and not affiliated with Bruce Studios AB. Your password goes straight to api.bruce.app; the access token is kept only in this browser. ' +
      'Brüce Web cannot buy tickets or open doors. <a href="../">About Brüce</a> · <a href="https://github.com/djui/bruce">Source</a></p></section>';
    $('#login-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = e.target; const btn = f.querySelector('button');
      btn.disabled = true; $('#login-error').textContent = '';
      try {
        const r = await Bruce.login(f.email.value.trim(), f.password.value);
        S.session = { token: r.access_token, userId: r.user_id, demo: false };
        ls.set('bruce.session', S.session);
        start();
      } catch (err) {
        $('#login-error').textContent = err.status === 401 || err.status === 400 || err.status === 403 ? 'Wrong email or password.' : err.message;
        btn.disabled = false;
      }
    });
  }

  async function viewClasses(params) {
    setTab('classes');
    const t = ++renderToken;
    const today = todayKey();
    const day = params.get('day') || today;
    const f = S.filters;
    const days = Array.from({ length: 7 }, (_, i) => addDays(today, i));
    const cats = S.categories.slice().sort((a, b) => (a.order || 0) - (b.order || 0));
    main.innerHTML = demoBanner() + '<h1>Classes in ' + esc(city().name) + '</h1>' +
      '<div class="toolbar">' +
      '<div class="chips" role="group" aria-label="Day">' + days.map((d) => { const [a, b] = dayLabel(d); return '<button class="chip" data-day="' + d + '" aria-pressed="' + (d === day) + '">' + a + '<small>' + b + '</small></button>'; }).join('') + '</div>' +
      '<input type="search" id="q" placeholder="Search class, studio or instructor" value="' + esc(f.q) + '" aria-label="Search classes">' +
      '<div class="chips" role="group" aria-label="Filters">' +
      '<button class="chip" data-filter="free" aria-pressed="' + f.free + '">Free spots</button>' +
      '<button class="chip" data-filter="favs" aria-pressed="' + f.favs + '">Favourite studios</button>' +
      cats.map((c) => '<button class="chip" data-cat="' + c.id + '" aria-pressed="' + (f.cat === c.id) + '">' + esc(c.title) + '</button>').join('') +
      '</div></div><div id="class-list"><div class="loading">Loading classes…</div></div>';

    $('#q').addEventListener('input', (e) => { f.q = e.target.value; draw(); });
    main.querySelectorAll('[data-day]').forEach((b) => b.addEventListener('click', () => { location.hash = '#/classes?day=' + b.dataset.day; }));
    main.querySelectorAll('[data-filter]').forEach((b) => b.addEventListener('click', () => { f[b.dataset.filter] = !f[b.dataset.filter]; b.setAttribute('aria-pressed', f[b.dataset.filter]); draw(); }));
    main.querySelectorAll('[data-cat]').forEach((b) => b.addEventListener('click', () => {
      const id = +b.dataset.cat; f.cat = f.cat === id ? null : id;
      main.querySelectorAll('[data-cat]').forEach((x) => x.setAttribute('aria-pressed', +x.dataset.cat === f.cat)); draw();
    }));

    const cacheKey = S.settings.cityId + ':' + day;
    let classes = []; let done = false;
    function draw() {
      if (t !== renderToken) return;
      const q = f.q.trim().toLowerCase();
      const now = Date.now();
      const list = classes.filter((c) => {
        if (!isListed(c)) return false;
        if (day === today && c.end_time && new Date(c.end_time) < now) return false;
        if (f.free && !(c.available_spots > 0)) return false;
        if (f.favs && !S.favorites.has(c.studio_id)) return false;
        if (f.cat && !(c.class_categories || []).some((x) => x.category_id === f.cat)) return false;
        if (q) {
          const s = S.studios.get(c.studio_id) || {};
          if (![c.title, s.name, s.vicinity, instructor(c.instructor)].some((x) => x && x.toLowerCase().includes(q))) return false;
        }
        return true;
      });
      const el = $('#class-list');
      if (!el) return;
      el.innerHTML = list.length
        ? '<div class="list">' + list.map((c) => classRow(c)).join('') + '</div>' + (done ? '' : '<div class="loading">Loading more…</div>')
        : (done ? '<p class="empty">No classes match.</p>' : '<div class="loading">Loading classes… ' + (classes.length || '') + '</div>');
    }
    const cached = S.classCache.get(cacheKey);
    if (cached && Date.now() - cached.at < 60000) { classes = cached.classes; done = true; draw(); return; }
    try {
      await Bruce.classes(day, { cityId: S.settings.cityId }, (items, all) => {
        classes = all.slice().sort((a, b) => a.start_time.localeCompare(b.start_time)); draw();
      });
      done = true; S.classCache.set(cacheKey, { at: Date.now(), classes }); draw();
    } catch (e) {
      if (t === renderToken) $('#class-list').innerHTML = '<p class="empty error">' + esc(e.message) + '</p>';
    }
  }

  async function viewStudios() {
    setTab('studios');
    const t = ++renderToken;
    main.innerHTML = demoBanner() + '<h1>Studios in ' + esc(city().name) + '</h1>' +
      '<div class="toolbar"><input type="search" id="sq" placeholder="Search studio, area or category" value="' + esc(S.studioQuery) + '" aria-label="Search studios">' +
      '<div class="chips"><button class="chip" id="sfav" aria-pressed="' + !!S.filters.studioFavs + '">Favourites</button></div></div>' +
      '<div id="studio-list"><div class="loading">Loading studios…</div></div>';
    const draw = () => {
      if (t !== renderToken) return;
      const q = S.studioQuery.trim().toLowerCase();
      const list = [...S.studios.values()].filter((s) => s.city_id === S.settings.cityId)
        .filter((s) => !S.filters.studioFavs || S.favorites.has(s.id))
        .filter((s) => !q || [s.name, s.vicinity, s.address, ...(s.cats || [])].some((x) => x && x.toLowerCase().includes(q)))
        .sort((a, b) => (S.favorites.has(b.id) - S.favorites.has(a.id)) || a.name.localeCompare(b.name, 'sv'));
      const shown = list.slice(0, 150);
      $('#studio-list').innerHTML = list.length
        ? '<p class="muted small">' + list.length + ' studios</p><div class="list">' + shown.map((s) =>
          '<a class="item" href="#/studio/' + s.id + '"><div class="thumb" style="background-image:url(\'' + img(s.photo, 112, 112) + '\')"></div>' +
          '<div class="body"><h3>' + esc(s.name) + (S.favorites.has(s.id) ? ' <span aria-label="favourite">♥</span>' : '') + '</h3><p>' +
          [esc(s.vicinity), esc((s.cats || []).slice(0, 2).join(', '))].filter(Boolean).join(' · ') + '</p></div>' +
          (rating(s.rating) ? '<span class="badge">★ ' + rating(s.rating) + '</span>' : '') + '</a>').join('') + '</div>' +
          (list.length > shown.length ? '<p class="muted small empty">Search to see more of the ' + list.length + ' studios.</p>' : '')
        : '<p class="empty">No studios match.</p>';
    };
    $('#sq').addEventListener('input', (e) => { S.studioQuery = e.target.value; draw(); });
    $('#sfav').addEventListener('click', (e) => { S.filters.studioFavs = !S.filters.studioFavs; e.target.setAttribute('aria-pressed', S.filters.studioFavs); draw(); });
    try {
      await loadStudios((n) => { if (t === renderToken) $('#studio-list').innerHTML = '<div class="loading">Loading studios… ' + n + '</div>'; });
      draw();
    } catch (e) { if (t === renderToken) $('#studio-list').innerHTML = '<p class="empty error">' + esc(e.message) + '</p>'; }
  }

  function currentAlert(alerts) {
    const now = Date.now();
    return (alerts || []).filter((a) => a.message && (!a.start_date || new Date(a.start_date) <= now) && (!a.end_date || new Date(a.end_date) > now))
      .sort((a, b) => ((a.type === 'CRITICAL' ? 0 : 1) - (b.type === 'CRITICAL' ? 0 : 1)) || ((a.order || 0) - (b.order || 0)))[0];
  }

  async function viewClass(id) {
    setTab(currentTab || 'classes');
    const t = ++renderToken;
    main.innerHTML = demoBanner() + backLink() + '<div class="loading">Loading class…</div>';
    let c;
    try { c = await Bruce.klass(id); } catch (e) { main.innerHTML = demoBanner() + backLink() + '<p class="empty error">' + esc(e.message) + '</p>'; return; }
    if (t !== renderToken) return;
    const s = c.studio || S.studios.get(c.studio_id) || {};
    const known = S.studios.get(c.studio_id) || {};
    const booking = S.bookings.get(c.id);
    const standby = S.standbys.get(c.id);
    const started = new Date(c.start_time) <= Date.now();
    const att = c.user_attendance_info || c.studio_user_attendance_info || {};
    const dur = minutes(c.start_time, c.end_time);
    const studioAlert = currentAlert(s.alerts);
    const cats = (c.class_categories || []).map((x) => (S.categories.find((k) => k.id === x.category_id) || {}).title).filter(Boolean);
    const spots = c.spots ? (c.available_spots != null ? c.available_spots + ' of ' + c.spots + ' free' : c.spots + ' spots') : (c.available_spots != null ? c.available_spots + ' free' : '');
    const photo = c.photo || s.photo || known.photo;

    let actions = '';
    if (booking) {
      actions = booking.checked_in_at ? '<p class="muted">You are checked in.</p>'
        : (started ? '<p class="muted">This class has started.</p>' : '<button class="btn danger block" data-act="cancel">Cancel booking</button>');
    } else if (started) {
      actions = '<button class="btn ghost block" disabled>This class has started</button>';
    } else if (standby) {
      actions = (c.available_spots > 0 ? '<button class="btn block" data-act="book">Book the free spot</button>' : '') +
        '<button class="btn ghost block" data-act="leave">Leave waitlist</button>';
    } else if (att.visit_limit_reached) {
      actions = '<button class="btn ghost block" disabled>Visit limit reached</button>' +
        (att.price > 0 ? '<p class="muted small">The official app sells a drop-in for ' + (att.currency || c.currency || 'SEK').toUpperCase() + ' ' + Math.round(att.price / 100) + '. Brüce does not sell tickets.</p>' : '');
    } else if (c.available_spots != null && c.available_spots <= 0) {
      actions = '<button class="btn warn block" data-act="join">Join waitlist</button>';
    } else {
      actions = '<button class="btn block" data-act="book">Book</button>';
    }

    main.innerHTML = demoBanner() + backLink() +
      hero(photo) +
      '<h1>' + esc(c.title) + '</h1>' +
      '<p><a href="#/studio/' + c.studio_id + '">' + esc(s.name || known.name || 'Studio') + '</a>' + (s.vicinity || known.vicinity ? ' <span class="muted">· ' + esc(s.vicinity || known.vicinity) + '</span>' : '') + '</p>' +
      (studioAlert ? '<div class="notice' + (studioAlert.type === 'CRITICAL' ? ' critical' : '') + '">' + esc(studioAlert.message) + '</div>' : '') +
      (c.alert ? '<div class="notice critical">' + esc(c.alert) + '</div>' : '') +
      '<div class="facts">' +
      '<div class="fact"><small>When</small><b>' + esc(longDay(c.start_time)) + '</b></div>' +
      '<div class="fact"><small>Time</small><b>' + timeOf(c.start_time) + (c.end_time ? '–' + timeOf(c.end_time) : '') + (dur ? ' (' + dur + ' min)' : '') + '</b></div>' +
      (instructor(c.instructor) ? '<div class="fact"><small>Instructor</small><b>' + esc(instructor(c.instructor)) + '</b></div>' : '') +
      (spots ? '<div class="fact"><small>Spots</small><b>' + esc(spots) + '</b></div>' : '') +
      '</div>' +
      (cats.length ? '<div class="tags">' + cats.map((x) => '<span class="tag">' + esc(x) + '</span>').join('') + '</div>' : '') +
      '<div class="actions sticky">' + actions + '</div>' +
      (c.description ? '<div class="rich">' + rich(c.description) + '</div>' : '') +
      ((booking || !started) ? '<p class="muted small">' + esc(rulesText(c)) + '</p>' : '') +
      '<div id="similar"></div>';

    const on = (act, fn) => { const b = main.querySelector('[data-act="' + act + '"]'); if (b) b.addEventListener('click', () => run(b, fn)); };
    on('book', async () => { await Bruce.book(c.id); toast('Booked ' + c.title); await afterChange(c.id); });
    on('cancel', async () => {
      if (!(await confirmDialog('Cancel booking?', cancelText(c), 'Cancel booking'))) return;
      await Bruce.cancel(booking.id); toast('Booking cancelled'); await afterChange(c.id);
    });
    on('join', async () => { await Bruce.joinWaitlist(c.id); toast('You are on the waitlist'); await afterChange(c.id); });
    on('leave', async () => {
      if (!(await confirmDialog('Leave the waitlist?', 'You will lose your place in the queue.', 'Leave waitlist'))) return;
      await Bruce.leaveWaitlist(standby.id); toast('Left the waitlist'); await afterChange(c.id);
    });

    if (!booking && !started && c.available_spots != null && c.available_spots <= 0) {
      Bruce.similar(c.id).then((cards) => {
        if (t !== renderToken || !cards.length) return;
        $('#similar').innerHTML = '<h2>Similar classes</h2><div class="list">' + cards.map((k) =>
          '<a class="item" href="#/class/' + k.id + '"><div class="time"><b>' + timeOf(k.start_time) + '</b><small>' + (minutes(k.start_time, k.end_time) || '') + ' min</small></div>' +
          '<div class="body"><h3>' + esc(k.title) + '</h3><p>' + esc(k.studio && k.studio.name) + (k.distance ? ' · ' + (k.distance / 1000).toFixed(1) + ' km' : '') + '</p></div></a>').join('') + '</div>';
      }).catch(() => {});
    }
  }

  function lateCancelAt(c) {
    if (c.unbookable_latest_time) return new Date(c.unbookable_latest_time);
    return new Date(new Date(c.start_time).getTime() - (c.unbookable_latest != null ? c.unbookable_latest : 43200) * 1000);
  }
  function rulesText(c) {
    const at = lateCancelAt(c).toISOString();
    const when = dayKey(new Date(at)) === todayKey() ? 'today' : fmt(at, { weekday: 'short', day: 'numeric', month: 'short' });
    return 'Free cancellation until ' + when + ' ' + timeOf(at) + '. Late cancellations and no-shows give strikes; 3 strikes pause class booking.';
  }
  function cancelText(c) {
    const hours = (new Date(c.start_time) - Date.now()) / 3600000;
    if (Date.now() < lateCancelAt(c).getTime() && hours >= 12) return 'Cancelling now is free.';
    if (hours >= 3) return 'This is a late cancellation (3 to 12 hours before start) and gives 1 strike.';
    return 'This is a very late cancellation (under 3 hours before start) and gives 2 strikes.';
  }
  async function run(btn, fn) {
    btn.disabled = true;
    try { await fn(); } catch (e) { toast(e.message); btn.disabled = false; }
  }
  async function afterChange(classId) {
    S.classCache.clear();
    await loadMine().catch(() => {});
    if (location.hash === '#/class/' + classId) viewClass(classId); else route();
  }

  async function viewStudio(id, params) {
    setTab(currentTab || 'studios');
    const t = ++renderToken;
    main.innerHTML = demoBanner() + backLink() + '<div class="loading">Loading studio…</div>';
    let s;
    try { s = await Bruce.studio(id); } catch (e) { main.innerHTML = demoBanner() + backLink() + '<p class="empty error">' + esc(e.message) + '</p>'; return; }
    if (t !== renderToken) return;
    const a = (s.studio_addresses || []).map((x) => x.address).filter(Boolean)[0];
    const alert = currentAlert(s.alerts);
    const photos = (s.studio_photos || []).sort((x, y) => (x.order || 0) - (y.order || 0)).map((p) => p.photo && p.photo.file_id).filter(Boolean);
    const today = todayKey();
    const day = params.get('day') || today;
    const fav = S.favorites.has(s.id);
    const cats = (s.studio_categories || []).map((c) => c.category && c.category.title).filter(Boolean);
    const facilities = (s.studio_facilities || []).map((f) => f.facility && f.facility.title).filter(Boolean);
    main.innerHTML = demoBanner() + backLink() +
      hero(photos[0] || s.photo) +
      '<div class="row"><h1 class="spacer">' + esc(s.name) + '</h1>' +
      '<button class="btn ghost sm" data-act="fav" aria-pressed="' + fav + '">' + (fav ? '♥ Favourite' : '♡ Add favourite') + '</button></div>' +
      '<p class="muted">' + [esc(s.vicinity), rating(s.rating) ? '★ ' + rating(s.rating) + (s.rating.total ? ' (' + s.rating.total + ')' : '') : null].filter(Boolean).join(' · ') + '</p>' +
      (alert ? '<div class="notice' + (alert.type === 'CRITICAL' ? ' critical' : '') + '">' + esc(alert.message) + '</div>' : '') +
      ((s.integration_door_type || '').toLowerCase() === 'parakey' ? '<p class="small muted">Doors here open with the Parakey app.</p>' : '') +
      (a ? '<p><a href="https://maps.apple.com/?q=' + encodeURIComponent(s.name) + '&ll=' + a.latitude + ',' + a.longitude + '" target="_blank" rel="noopener">' + esc([a.address, a.zip_code, a.city].filter(Boolean).join(', ')) + '</a></p>' : '') +
      (cats.length || facilities.length ? '<div class="tags">' + cats.concat(facilities).map((x) => '<span class="tag">' + esc(x) + '</span>').join('') + '</div>' : '') +
      '<h2>Classes</h2><div class="chips" role="group" aria-label="Day">' + Array.from({ length: 7 }, (_, i) => addDays(today, i)).map((d) => { const [x, y] = dayLabel(d); return '<button class="chip" data-day="' + d + '" aria-pressed="' + (d === day) + '">' + x + '<small>' + y + '</small></button>'; }).join('') + '</div>' +
      '<div id="studio-classes"><div class="loading">Loading classes…</div></div>' +
      (s.description ? '<h2>About</h2><div class="rich">' + rich(s.description) + '</div>' : '');
    main.querySelectorAll('[data-day]').forEach((b) => b.addEventListener('click', () => { location.hash = '#/studio/' + s.id + '?day=' + b.dataset.day; }));
    const favBtn = main.querySelector('[data-act="fav"]');
    favBtn.addEventListener('click', () => run(favBtn, async () => {
      if (S.favorites.has(s.id)) { await Bruce.removeFavorite(S.favorites.get(s.id)); S.favorites.delete(s.id); toast('Removed from favourites'); }
      else { const f = await Bruce.addFavorite(s.id); S.favorites.set(s.id, f.id); toast('Added to favourites'); }
      const on = S.favorites.has(s.id);
      favBtn.textContent = on ? '♥ Favourite' : '♡ Add favourite'; favBtn.setAttribute('aria-pressed', on); favBtn.disabled = false;
    }));
    try {
      const list = (await Bruce.classes(day, { studioId: s.id })).filter(isListed).filter((c) => day !== today || !c.end_time || new Date(c.end_time) > Date.now())
        .sort((x, y) => x.start_time.localeCompare(y.start_time));
      if (t !== renderToken) return;
      $('#studio-classes').innerHTML = list.length ? '<div class="list">' + list.map((c) => classRow(c, { hideStudio: true })).join('') + '</div>' : '<p class="empty">No classes this day.</p>';
    } catch (e) { if (t === renderToken) $('#studio-classes').innerHTML = '<p class="empty error">' + esc(e.message) + '</p>'; }
  }

  async function viewMine() {
    setTab('mine');
    const t = ++renderToken;
    main.innerHTML = demoBanner() + '<h1>My classes</h1><div id="mine"><div class="loading">Loading your bookings…</div></div>';
    try { await loadMine(); } catch (e) { $('#mine').innerHTML = '<p class="empty error">' + esc(e.message) + '</p>'; return; }
    if (t !== renderToken) return;
    const now = Date.now();
    const upcoming = [...S.bookings.values()].map((b) => b.class).filter((c) => c && (!c.end_time || new Date(c.end_time) > now - 3600000))
      .sort((a, b) => a.start_time.localeCompare(b.start_time));
    const waits = [...S.standbys.values()].map((s) => s.class).sort((a, b) => a.start_time.localeCompare(b.start_time));
    $('#mine').innerHTML = (upcoming.length ? '<div class="list">' + upcoming.map((c) => classRow(c, { withDay: true })).join('') + '</div>'
      : '<p class="empty">No upcoming bookings. <a href="#/classes">Find a class</a>.</p>') +
      (waits.length ? '<h2>Waitlist</h2><div class="list">' + waits.map((c) => classRow(c, { withDay: true })).join('') + '</div>' : '');
  }

  async function viewAccount() {
    setTab('account');
    const t = ++renderToken;
    main.innerHTML = demoBanner() + '<h1>Account</h1><div id="acct"><div class="loading">Loading…</div></div>';
    const [u, m, limits, block] = await Promise.all([Bruce.user().catch(() => null), Bruce.membership().catch(() => null), Bruce.limits().catch(() => []), Bruce.blockInfo().catch(() => null)]);
    if (t !== renderToken) return;
    const limitNames = { MONTHLY: 'Visits this month', WELLNESS_MONTHLY: 'Wellness visits this month', SIMULTANEOUS: 'Simultaneous bookings' };
    const limitRows = limits.filter((l) => limitNames[l.type] && l.total !== -1).map((l) =>
      '<div class="fact"><small>' + limitNames[l.type] + '</small><b>' + (l.total > 0 ? (l.used || 0) + ' of ' + l.total : (l.used || 0) + ' (unlimited)') + '</b>' +
      (l.total > 0 ? '<div class="meter"><i style="width:' + Math.min(100, Math.round(100 * (l.used || 0) / l.total)) + '%"></i></div>' : '') + '</div>').join('');
    $('#acct').innerHTML =
      '<div class="card"><h3>' + esc(u ? [u.first_name, u.last_name].filter(Boolean).join(' ') : 'Bruce member') + '</h3>' +
      (u && u.email ? '<p class="muted small">' + esc(u.email) + '</p>' : '') +
      (m ? '<dl class="kv">' +
        (m.membership_tier ? '<dt>Plan</dt><dd>' + esc(m.membership_tier) + (m.paused ? ' (paused)' : '') + '</dd>' : '') +
        (m.available_credits != null ? '<dt>Credits</dt><dd>' + m.available_credits + '</dd>' : '') +
        (m.next_payment ? '<dt>Next payment</dt><dd>' + esc(fmt(m.next_payment, { day: 'numeric', month: 'long' })) + '</dd>' : '') +
        (block && block.strike_count != null ? '<dt>Strikes</dt><dd>' + block.strike_count + (block.blocked ? ' (booking paused)' : '') + '</dd>' : '') +
        '</dl>' : '') + '</div>' +
      (limitRows ? '<div class="facts">' + limitRows + '</div>' : '') +
      '<h2>Settings</h2><div class="card">' +
      '<label class="field"><span>City</span><select id="city">' + (S.cities.length ? S.cities : [city()]).map((c) => '<option value="' + c.id + '"' + (c.id === S.settings.cityId ? ' selected' : '') + '>' + esc(c.name) + '</option>').join('') + '</select></label>' +
      '<label class="field"><span>Appearance</span><select id="theme"><option value="">System</option><option value="dark">Dark</option><option value="light">Light</option></select></label>' +
      '<details><summary class="small muted">Advanced</summary><label class="field" style="margin-top:12px"><span>API server</span><input type="url" id="api" value="' + esc(S.settings.apiBase) + '"></label>' +
      '<p class="small muted">Only change this to route requests through your own proxy.</p></details></div>' +
      '<div class="actions"><button class="btn danger block" data-act="logout">' + (isDemo() ? 'Leave demo' : 'Log out') + '</button></div>' +
      '<p class="disclaimer">Brüce Web is unofficial and not affiliated with Bruce Studios AB. It cannot buy tickets, check in or open doors; use the official app or Brüce for iPhone for that. ' +
      '<a href="../">About Brüce</a> · <a href="https://github.com/djui/bruce">Source</a> · <a href="../api/">API</a></p>';
    $('#city').addEventListener('change', (e) => { S.settings.cityId = +e.target.value; saveSettings(); S.classCache.clear(); toast('City set to ' + city().name); });
    const th = $('#theme');
    th.value = ls.get('theme', '') || '';
    th.addEventListener('change', () => {
      const v = th.value;
      try { if (v) localStorage.setItem('theme', v); else localStorage.removeItem('theme'); } catch (e) { /* ignore */ }
      if (v) document.documentElement.dataset.theme = v; else delete document.documentElement.dataset.theme;
    });
    $('#api').addEventListener('change', (e) => { S.settings.apiBase = e.target.value.trim() || DEFAULT_API; saveSettings(); toast('API server saved'); });
    const lo = main.querySelector('[data-act="logout"]');
    lo.addEventListener('click', () => run(lo, async () => {
      if (!isDemo()) await Bruce.logout().catch(() => {});
      endSession(); location.hash = '#/login';
    }));
  }

  // ---------------------------------------------------------------- router
  function route() {
    const h = location.hash.replace(/^#\/?/, '');
    const [path, query] = h.split('?');
    const params = new URLSearchParams(query || '');
    const parts = path.split('/');
    if (!S.session) { viewLogin(); return; }
    $('#tabs').hidden = false;
    window.scrollTo(0, 0);
    switch (parts[0]) {
      case 'class': return viewClass(+parts[1]);
      case 'studio': return viewStudio(+parts[1], params);
      case 'studios': return viewStudios();
      case 'mine': return viewMine();
      case 'account': return viewAccount();
      case 'classes': return viewClasses(params);
      default: location.replace('#/classes');
    }
  }

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el) return;
    const act = el.dataset.act;
    if (act === 'back') { if (history.length > 1) history.back(); else location.hash = '#/classes'; }
    if (act === 'demo') { S.session = { token: 'demo', userId: window.BruceDemo.userId, demo: true }; ls.set('bruce.session', S.session); start(); }
    if (act === 'exit-demo') { endSession(); location.hash = '#/login'; route(); }
  });
  window.addEventListener('hashchange', route);

  function start() {
    if (!S.session) { route(); return; }
    $('#tabs').hidden = false;
    main.innerHTML = '<div class="loading">Loading…</div>';
    if (!location.hash || location.hash === '#/login') history.replaceState(null, '', '#/classes');
    bootstrap().finally(route);
  }
  start();
})();
