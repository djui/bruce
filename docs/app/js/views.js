// The five tabs (BruceApp.swift RootView): Home, Explore, Check in, Friends, My classes.
import { $, esc, icon, fmt, time, todayKey, addDays, dayChip, dayHeader, instructor, isListed, rating, distance, metres, byDay, ls, media as photoMedia } from './util.js';
import { Bruce } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { classRow, classList, photoCard, underlineTabs, chip, empty, loading, sectionHeader, avatar, toast, makeMap } from './ui.js';
import { openNotifications, openMenu, openReview, openScanner, openTicket, checkInFlow } from './sheets.js';
import { forYouHTML, forYouClick } from './foryou.js';
import { challengesHTML, challengesClick, openNewChallenge, loadIfAllowed } from './challenges.js';
import { goalsCardHTML, openGoals, openGoalEditor } from './goalsui.js';

/** Page header of a main tab: big wide uppercase title, the tab's own glass buttons, then Notifications and
 *  Menu, which end every tab's header (on wide screens they live in the sidebar instead). */
function header(title, right) {
  return '<div class="page-head"><h1 class="screen-title">' + esc(title) + '</h1><div class="head-btns">' + (right || '') + headButtons() + '</div></div>';
}
function headButtons() {
  // main.js badges() keeps the dot in sync after the header is drawn.
  const dot = '<i class="dot"' + (St.unseenNotifications() ? '' : ' hidden') + '></i>';
  return '<button class="glass-btn head-global" data-act="notifications" aria-label="Notifications">' + icon('bell') + dot + '</button>' +
    '<button class="glass-btn head-global" data-act="menu" aria-label="Menu">' + icon('menu') + '</button>';
}
const link = (tab, kind, id) => '#/' + tab + '/' + kind + '/' + id;

// ---------------------------------------------------------------- Home

async function homeData() {
  if (S.home) return S.home;
  let lat = St.city().coordinates ? St.city().coordinates.latitude : 59.3293;
  let lon = St.city().coordinates ? St.city().coordinates.longitude : 18.0686;
  try {
    const p = navigator.permissions && await navigator.permissions.query({ name: 'geolocation' });
    if (p && p.state === 'granted') {
      const pos = await new Promise((res, rej) => navigator.geolocation.getCurrentPosition(res, rej, { timeout: 4000, maximumAge: 600000 }));
      lat = pos.coords.latitude; lon = pos.coords.longitude; S.here = { lat, lon };
    }
  } catch (e) { /* city centre */ }
  S.home = await Bruce.home(lat, lon);
  return S.home;
}

export const Home = {
  render(el, ctx) {
    this.el = el; this.ctx = ctx;
    el.innerHTML = header('Home') + '<div id="home-body">' + loading() + '</div>';
    el.addEventListener('click', (e) => forYouClick(e, (id) => link('home', 'class', id)));
    homeData().then(() => this.refresh()).catch((e) => { const b = $('#home-body', el); if (b) b.innerHTML = empty('info', e.message); });
  },
  refresh() {
    const b = $('#home-body', this.el);
    if (!b || !S.home) return;
    const sel = this.ctx.detail;
    const sec = (type) => S.home.find((s) => s.type === type);
    let html = '';
    const rv = St.pendingReviews()[0];
    if (rv) {
      html += '<div class="card prompt"><div>' + icon('star') + '</div><div class="grow"><b>How was ' + esc(rv.class.title) + '?</b><p class="muted">' +
        esc(dayHeader(rv.class.start_time)) + ' at ' + esc(St.studioName(rv.class.studio_id, rv.class.studio)) + '</p></div><button class="btn lime sm" data-review="' + rv.id + '">Rate</button></div>';
    }
    const next = St.upcomingBookings().sort((a, c) => a.class.start_time.localeCompare(c.class.start_time))[0];
    if (next) {
      const open = St.openWindowTargets().find((o) => o.c.id === next.class.id);
      html += '<h2 class="sec-title">Next up</h2><div class="list">' + classRow(next.class, link('home', 'class', next.class.id), { meta: dayHeader(next.class.start_time), selected: sel && sel.id === next.class.id }) + '</div>' +
        (open ? '<button class="btn lime" data-checkin="' + next.class.studio_id + '">' + icon('checkSeal') + ' Check in at ' + esc(open.t.name) + '</button>' : '');
    }
    html += forYouHTML((id) => link('home', 'class', id), sel);
    const spot = sec('SPOTLIGHT');
    if (spot && spot.items.length) {
      html += '<h2 class="sec-title">' + esc((spot.title || 'Spotlight').toUpperCase()) + '</h2><div class="hscroll spotlight">' + spot.items.map((it) => photoCard({
        href: link('home', 'class', it.class_id), photo: it.photo, glyph: it.class_name, title: it.class_name, cls: 'wide',
        topRight: '<span class="glass-pill">' + esc(it.studio_name) + '</span>',
        sub: it.start_time ? fmt(it.start_time, { weekday: 'long' }) + ' | ' + fmt(it.start_time, { day: 'numeric', month: 'long' }) + ' | ' + time(it.start_time) : '',
      })).join('') + '</div>';
    }
    const cats = sec('CATEGORIES');
    if (cats && cats.items.length) {
      html += '<div class="sec-row"><h2 class="sec-title">CATEGORIES</h2><a class="btn glass sm" href="#/explore?tab=studios">Show all</a></div><div class="hscroll cats">' + cats.items.map((it) =>
        '<a class="pcard cat" href="#/explore?tab=studios&cat=' + it.category_id + '">' + photoMedia(it.photo, 400, 400, it.title) + '<span class="glass-pill bottom">' + esc(it.title) + '</span></a>').join('') + '</div>';
    }
    ['NEARBY_GYMS', 'NEW_STUDIO'].forEach((type) => {
      const s = sec(type);
      if (!s || !s.items.length) return;
      html += '<h2 class="sec-title">' + esc((s.title || '').toUpperCase()) + '</h2><div class="hscroll studios">' + s.items.map((it) => photoCard({
        href: link('home', 'studio', it.studio_id), photo: it.photo, glyph: (it.categories || []).join(' ') || it.studio_name, title: it.studio_name,
        sub: [(it.vicinities || [])[0], it.distance ? distance(it.distance) : null].filter(Boolean).join(' | '),
        topRight: (it.categories || [])[0] ? '<span class="glass-pill">' + esc(it.categories[0]) + '</span>' : '', selected: sel && sel.id === it.studio_id,
      })).join('') + '</div>';
    });
    b.innerHTML = html || empty('home', 'Nothing here yet.');
  },
};

// ---------------------------------------------------------------- Explore

const ex = ls.get('bruce.explore', { tab: 'studios', q: '', favs: false, free: false, map: false });
const saveEx = () => ls.set('bruce.explore', { tab: ex.tab, favs: ex.favs, free: ex.free, map: ex.map, q: '' });
const classCache = (key) => S.classCache.get(S.settings.cityId + ':' + key);

function studioMatches(s, q, cat) {
  if (ex.favs && !S.favorites.has(s.id)) return false;
  if (cat && !(s.cats || []).includes(cat.title)) return false;
  if (!q) return true;
  return [s.name, s.vicinity, s.address, ...(s.cats || [])].some((x) => x && x.toLowerCase().includes(q));
}
function filteredStudios(cat) {
  const q = ex.q.trim().toLowerCase();
  const here = S.here || (St.city().coordinates ? { lat: St.city().coordinates.latitude, lon: St.city().coordinates.longitude } : null);
  return St.cityStudios().filter((s) => studioMatches(s, q, cat)).map((s) => Object.assign({ dist: here && s.lat ? metres(here.lat, here.lon, s.lat, s.lon) : null }, s))
    .sort((a, b) => (S.favorites.has(b.id) - S.favorites.has(a.id)) || ((a.dist == null ? 1e9 : a.dist) - (b.dist == null ? 1e9 : b.dist)) || a.name.localeCompare(b.name, 'sv'));
}
function filteredClasses(list, cat, day) {
  const q = ex.q.trim().toLowerCase();
  const now = Date.now();
  return (list || []).filter((c) => {
    if (!isListed(c)) return false;
    if (day === todayKey() && c.end_time && new Date(c.end_time) < now) return false;
    if (ex.free && !(c.available_spots > 0)) return false;
    if (ex.favs && !S.favorites.has(c.studio_id)) return false;
    if (cat && !(c.class_categories || []).some((x) => x.category_id === cat.id)) return false;
    if (q) {
      const s = St.studio(c.studio_id) || {};
      if (![c.title, s.name, s.vicinity, instructor(c.instructor)].some((x) => x && x.toLowerCase().includes(q))) return false;
    }
    return true;
  });
}

export const Explore = {
  render(el, ctx) {
    this.el = el; this.ctx = ctx;
    const p = ctx.params;
    if (p.get('tab')) ex.tab = p.get('tab');
    this.day = p.get('day') || todayKey();
    this.cat = p.get('cat') ? S.categories.find((c) => c.id === +p.get('cat')) || { id: +p.get('cat'), title: '' } : null;
    this.shown = 40;
    const days = Array.from({ length: 7 }, (_, i) => addDays(todayKey(), i));
    el.innerHTML = header('Explore', '<button class="glass-btn" data-x="map" aria-pressed="' + ex.map + '" aria-label="Map">' + icon(ex.map ? 'menu' : 'map') + '</button>') +
      '<div class="sticky-tools"><div id="x-tabs"></div>' +
      '<label class="search">' + icon('search') + '<input type="search" id="xq" placeholder="Studios, classes, instructors" value="' + esc(ex.q) + '" aria-label="Search"></label>' +
      '<div class="chips">' + chip(icon('heart'), ex.favs, 'data-x="favs" aria-label="Favourites"') + (ex.tab === 'classes' ? chip('Free spots', ex.free, 'data-x="free"') : '') +
      S.categories.map((c) => chip(esc(c.title), this.cat && this.cat.id === c.id, 'data-cat="' + c.id + '"')).join('') + '</div>' +
      (ex.tab === 'classes' ? '<div class="chips days">' + days.map((d) => { const [a, b] = dayChip(d); return chip(a + '<small>' + b + '</small>', d === this.day, 'data-day="' + d + '"'); }).join('') + '</div>' : '') +
      '</div><div id="x-list"></div>';
    const qEl = $('#xq', el);
    qEl.addEventListener('input', () => { ex.q = qEl.value; this.shown = 40; this.refresh(); });
    el.addEventListener('click', (e) => {
      const x = e.target.closest('[data-x]');
      if (x) {
        const k = x.dataset.x;
        if (k === 'map') { ex.map = !ex.map; saveEx(); ctx.rerender(); return; }
        ex[k] = !ex[k]; saveEx(); x.setAttribute('aria-pressed', ex[k]); this.refresh(); return;
      }
      const c = e.target.closest('[data-cat]');
      if (c) { const id = +c.dataset.cat; location.hash = this.href({ cat: this.cat && this.cat.id === id ? null : id }); return; }
      const d = e.target.closest('[data-day]');
      if (d) { location.hash = this.href({ day: d.dataset.day }); return; }
      const t = e.target.closest('[data-xtab]');
      if (t) { ex.tab = t.dataset.xtab; saveEx(); location.hash = this.href({ tab: ex.tab }); return; }
      if (e.target.closest('[data-more]')) { this.shown += 60; this.refresh(); }
    });
    St.loadStudios().catch((e) => toast(e.message));
    this.loadClasses();
    this.refresh();
  },
  href(change) {
    const p = new URLSearchParams();
    const tab = change.tab || ex.tab;
    p.set('tab', tab);
    const cat = 'cat' in change ? change.cat : this.cat && this.cat.id;
    if (cat) p.set('cat', cat);
    const day = change.day || (tab === 'classes' && this.day !== todayKey() ? this.day : null);
    if (day) p.set('day', day);
    const d = this.ctx.detail;
    return '#/explore' + (d ? '/' + d.kind + '/' + d.id : '') + '?' + p.toString();
  },
  async loadClasses() {
    const day = this.day;
    const key = S.settings.cityId + ':' + day;
    const c = S.classCache.get(key);
    if (c && (c.done || c.loading) && Date.now() - c.at < 90000) return;
    const entry = { at: Date.now(), classes: [], loading: true, done: false };
    S.classCache.set(key, entry);
    try {
      await Bruce.classes(day, { cityId: S.settings.cityId }, (items, all) => { entry.classes = all.slice().sort((a, b) => a.start_time.localeCompare(b.start_time)); if (this.day === day) this.refresh(); });
      entry.done = true;
    } catch (e) { entry.error = e.message; S.classCache.delete(key); }
    entry.loading = false;
    if (this.day === day) this.refresh();
  },
  refresh() {
    const el = this.el;
    if (!el || !el.isConnected) return;
    const sel = this.ctx.detail;
    const studios = filteredStudios(this.cat);
    const cc = classCache(this.day);
    const classes = filteredClasses(cc && cc.classes, this.cat, this.day);
    $('#x-tabs', el).innerHTML = underlineTabs([
      { key: 'studios', title: 'Studios', badge: S.studios.size ? studios.length : '' },
      { key: 'classes', title: 'Classes', badge: cc && cc.done ? classes.length : '' }], ex.tab, 'data-xtab');
    const box = $('#x-list', el);
    if (ex.tab === 'studios') {
      if (ex.map) {
        if (!box.querySelector('.map')) { box.innerHTML = '<div class="map big"></div>'; }
        this.drawMap(box.querySelector('.map'), studios);
        return;
      }
      if (!S.studios.size) { box.innerHTML = loading('Loading studios…'); return; }
      if (!studios.length) { box.innerHTML = empty('search', 'No studios match.'); return; }
      box.innerHTML = '<div class="cards">' + studios.slice(0, this.shown).map((s) => photoCard({
        href: '#/explore/studio/' + s.id + location.hash.replace(/^[^?]*/, ''), photo: s.photo, glyph: (s.cats || []).join(' ') || s.name, title: s.name,
        sub: [s.vicinity, s.dist != null ? distance(Math.round(s.dist)) : null].filter(Boolean).join(' | '),
        topLeft: rating(s.rating) ? '<span class="glass-pill">' + icon('star') + rating(s.rating) + '</span>' : '<span></span>',
        topRight: (S.favorites.has(s.id) ? '<span class="glass-pill">' + icon('heart', 'fill') + '</span>' : '') + ((s.cats || [])[0] ? '<span class="glass-pill">' + esc(s.cats[0]) + '</span>' : ''),
        selected: sel && sel.kind === 'studio' && sel.id === s.id,
      })).join('') + '</div>' + (studios.length > this.shown ? '<button class="btn glass more" data-more>Show more (' + (studios.length - this.shown) + ')</button>' : '');
    } else {
      if (!cc || (!cc.classes.length && !cc.done)) { box.innerHTML = loading('Loading classes…'); return; }
      box.innerHTML = classes.length
        ? '<div class="list">' + classes.map((c) => classRow(c, '#/explore/class/' + c.id + location.hash.replace(/^[^?]*/, ''), { selected: sel && sel.id === c.id })).join('') + '</div>' + (cc.done ? '' : loading('Loading more…'))
        : (cc.done ? empty('calendar', 'No classes match.') : loading('Loading classes…'));
    }
  },
  async drawMap(el, studios) {
    const pts = studios.map((s) => ({ lat: s.lat, lon: s.lon, label: s.name, fav: S.favorites.has(s.id), href: '#/explore/studio/' + s.id + '?tab=studios' }));
    const sig = pts.length + ':' + ex.q + ':' + ex.favs + ':' + (this.cat && this.cat.id);
    if (el.dataset.sig === sig) return;
    el.dataset.sig = sig;
    if (el._map) { el._map.map.remove(); el._map = null; el.innerHTML = ''; }
    const c = St.city().coordinates;
    el._map = await makeMap(el, pts, { center: c ? [c.latitude, c.longitude] : [59.33, 18.07] });
  },
};

/** Desktop right pane when nothing is selected: the studios on a map (Explore), else a hint. */
export function placeholderPane(el, tab) {
  if (tab === 'explore' && ex.tab === 'studios' && !ex.map) {
    el.innerHTML = '<div class="map fill"></div>';
    const pts = filteredStudios(Explore.cat).map((s) => ({ lat: s.lat, lon: s.lon, label: s.name, fav: S.favorites.has(s.id), href: '#/explore/studio/' + s.id + '?tab=studios' }));
    const c = St.city().coordinates;
    makeMap(el.firstChild, pts, { center: c ? [c.latitude, c.longitude] : [59.33, 18.07] });
    return;
  }
  const hint = { home: 'Pick a class or studio to see it here.', explore: 'Pick a class to see it here.', mine: 'Pick one of your classes to see it here.',
    friends: "Pick a friend's class to see it here.", checkin: 'Check in at a studio, or scan the door QR code.' }[tab];
  el.innerHTML = '<div class="pane-empty"><img src="icon-rounded.png" alt="" width="72" height="72"><p>' + esc(hint || '') + '</p></div>';
}

// ---------------------------------------------------------------- Check in

export const CheckIn = {
  render(el, ctx) {
    this.el = el; this.ctx = ctx; this.q = '';
    el.innerHTML = header('Check in') + '<div id="ci-body">' + loading() + '</div>';
    if (!S.visits) Bruce.visits().then((v) => { S.visits = v.filter((x) => x.checked_in_at && !x.deleted); this.refresh(); }).catch(() => { S.visits = []; this.refresh(); });
    St.loadStudios().catch(() => {});
    el.addEventListener('input', (e) => { if (e.target.id === 'ciq') { this.q = e.target.value; this.drawList(); } });
    this.refresh();
  },
  refresh() {
    const b = $('#ci-body', this.el);
    if (!b) return;
    const open = St.openWindowTargets();
    const recent = St.recentTargets(S.visits);
    const sug = open[0] ? { t: open[0].t, label: 'BOOKED ' + time(open[0].c.start_time) + ' · WINDOW OPEN', ic: 'clock' } : recent[0] ? { t: recent[0], label: 'LAST VISITED', ic: 'clock' } : null;
    const today = sug && St.todaysCheckIn(sug.t.studioId);
    let html = '';
    if (sug) {
      html += '<div class="card checkin-card"><span class="eyebrow">' + icon(sug.ic) + esc(sug.label) + '</span><h2 class="checkin-name">' + esc(sug.t.name) + '</h2>' +
        '<p class="muted">' + esc(sug.t.subtitle) + '</p>' +
        (today ? '<button class="btn lime" data-ticket="' + today.id + '">' + icon('ticket') + ' Show ticket</button>'
          : '<button class="btn lime" data-checkin="' + sug.t.studioId + '">' + icon('checkSeal') + ' Check in</button>') + '</div>';
    } else if (S.visits) {
      html += '<div class="card">' + empty('checkin', 'Book a class or scan a door QR code to check in.') + '</div>';
    }
    html += '<button class="card row-card" data-act="scan">' + icon('camera') + '<div class="grow"><b>Scan door QR code</b><p class="muted">Use your camera at the studio door</p></div>' + icon('chevron') + '</button>';
    if (open.length > 1 || recent.length > 1) {
      html += '<h2 class="sec-title">Your studios</h2><div class="list">' + open.slice(1).map((o) => targetRow(o.t)).join('') + recent.slice(sug && !open[0] ? 1 : 0).map(targetRow).join('') + '</div>';
    }
    html += '<h2 class="sec-title">Other studios</h2><label class="search">' + icon('search') + '<input type="search" id="ciq" placeholder="Search studios" value="' + esc(this.q) + '"></label><div id="ci-list" class="list"></div>' +
      '<p class="muted small note">' + icon('info') + ' Only check in where you are. A check-in counts like one in the official app. Studios that open with Parakey need the Parakey app.</p>';
    b.innerHTML = html;
    this.drawList();
  },
  drawList() {
    const box = $('#ci-list', this.el);
    if (!box) return;
    const q = this.q.trim().toLowerCase();
    if (!q) { box.innerHTML = '<p class="muted small">Type to find a studio.</p>'; return; }
    const ts = St.cityStudios().filter((s) => s.name.toLowerCase().includes(q) || (s.vicinity || '').toLowerCase().includes(q)).slice(0, 30)
      .map((s) => St.target(s.id, s.vicinity || '')).filter(Boolean);
    box.innerHTML = ts.length ? ts.map(targetRow).join('') : '<p class="muted small">No studio with a check-in code matches.</p>';
  },
};
function targetRow(t) {
  return '<div class="trow"><a class="grow" href="#/checkin/studio/' + t.studioId + '"><b>' + esc(t.name) + '</b><p class="muted">' + esc(t.subtitle) + '</p></a>' +
    '<button class="btn lime sm" data-checkin="' + t.studioId + '">Check in</button></div>';
}

// ---------------------------------------------------------------- Friends

export const Friends = {
  render(el, ctx) {
    this.el = el; this.ctx = ctx;
    this.tab = ctx.params.get('tab') || this.tab || 'classes';
    el.innerHTML = header('Friends', '<span id="fr-head"></span>') + '<div id="fr-tabs" class="sticky-tools"></div><div id="fr-body">' + loading() + '</div>';
    el.addEventListener('click', (e) => {
      const t = e.target.closest('[data-ftab]');
      if (t) { this.tab = t.dataset.ftab; const d = this.ctx.detail; location.hash = '#/friends' + (d && d.kind !== 'challenge' ? '/' + d.kind + '/' + d.id : '') + '?tab=' + this.tab; return; }
      if (e.target.closest('[data-fnew]')) { openNewChallenge(); return; }
      challengesClick(e, () => this.refresh());
    });
    St.loadSocial().then(() => this.refresh());
    loadIfAllowed();
    this.refresh();
  },
  refresh() {
    const b = $('#fr-body', this.el);
    if (!b) return;
    const sel = this.ctx.detail;
    const items = S.friendsBookings.filter((x) => x.class && new Date(x.class.start_time) > Date.now() - 3600000)
      .sort((a, c) => a.class.start_time.localeCompare(c.class.start_time));
    const pending = St.pendingInvites().length;
    $('#fr-head', this.el).innerHTML = this.tab === 'challenges' ? '<button class="glass-btn" data-fnew aria-label="New challenge">' + icon('plus') + '</button>' : '';
    $('#fr-tabs', this.el).innerHTML = underlineTabs([{ key: 'classes', title: 'Classes', badge: items.length || '' },
      { key: 'challenges', title: 'Challenges', badge: pending || '' }, { key: 'friends', title: 'Friends', badge: S.friends.length || '' }], this.tab, 'data-ftab');
    const tabs = $('#fr-tabs .utabs', this.el);
    if (tabs && pending) tabs.querySelector('[data-ftab="challenges"] .count').classList.add('alert');
    if (this.tab === 'challenges') { b.innerHTML = challengesHTML(sel && sel.kind === 'challenge' ? sel : null); return; }
    if (this.tab === 'friends') {
      const uses = new Set((S.challenges && S.challenges.usesBruce) || []);
      b.innerHTML = S.friends.length ? '<div class="list">' + S.friends.map((f) => {
        const u = f.friend_user || {};
        return '<div class="trow">' + avatar(u, 44) + '<div class="grow"><b>' + esc([u.first_name, u.last_name].filter(Boolean).join(' ')) + '</b>' +
          (S.challenges ? '<p class="muted">' + (uses.has(u.id) ? 'Uses Brüce' : 'Not on Brüce yet') + '</p>' : '') + '</div></div>';
      }).join('') + '</div><p class="muted small note">Friends come from the Bruce app. Challenge them from the Challenges tab.</p>' : empty('friends', 'Add friends in the Bruce app to see what they train.');
      return;
    }
    let html = '';
    if (S.friends.length) {
      html += '<div class="hscroll friends">' + S.friends.map((f) => '<div class="friend">' + avatar(f.friend_user, 58) + '<span>' + esc((f.friend_user || {}).first_name || '') + '</span></div>').join('') + '</div>';
    }
    if (!items.length) { b.innerHTML = html + empty('friends', S.friends.length ? "Your friends' upcoming classes will show up here." : 'Add friends in the Bruce app to see what they train.'); return; }
    html += byDay(items, (x) => x.class.start_time).map((g) => sectionHeader(dayHeader(g.iso)) + g.items.map((x) =>
      classRow(x.class, link('friends', 'class', x.class.id) + '?tab=classes', { friends: false, selected: sel && sel.id === x.class.id, trailing: avatar(St.friendUser(x.user_id), 40) })).join('')).join('');
    b.innerHTML = html;
  },
};

// ---------------------------------------------------------------- My classes

export const Mine = {
  render(el, ctx) {
    this.el = el; this.ctx = ctx;
    this.tab = ctx.params.get('tab') || this.tab || 'bookings';
    el.innerHTML = header('My classes', '<span class="glass-pill count-pill" id="mine-count"></span>') + '<div id="mine-tabs" class="sticky-tools"></div><div id="mine-body">' + loading() + '</div>';
    el.addEventListener('click', (e) => {
      const t = e.target.closest('[data-mtab]'); if (t) { this.tab = t.dataset.mtab; this.refresh(); return; }
      if (e.target.closest('[data-goals]')) { if (St.goals().length) openGoals(); else openGoalEditor(null); }
    });
    St.loadMine().then(() => this.refresh()).catch((e) => toast(e.message));
    St.loadReviewable();
    this.refresh();
  },
  refresh() {
    const b = $('#mine-body', this.el);
    if (!b) return;
    const sel = this.ctx.detail;
    const bookings = [...S.bookings.values()].filter((x) => x.class && new Date(x.class.end_time || x.class.start_time) > Date.now() - 3600000).map((x) => x.class);
    const waits = [...S.standbys.values()].map((x) => x.class);
    const marks = [...S.bookmarks.values()].map((x) => x.class).filter((c) => new Date(c.start_time) > Date.now() - 3600000);
    const lim = St.simultaneousLimit();
    $('#mine-count', this.el).textContent = St.upcomingBookings().length + (lim ? ' / ' + lim : '');
    $('#mine-tabs', this.el).innerHTML = underlineTabs([
      { key: 'bookings', title: 'Bookings', badge: bookings.length || '' }, { key: 'waitlist', title: 'Waitlist', badge: waits.length || '' },
      { key: 'bookmarks', title: 'Bookmarks' }], this.tab, 'data-mtab');
    const list = { bookings, waitlist: waits, bookmarks: marks }[this.tab].sort((a, c) => a.start_time.localeCompare(c.start_time));
    const msg = { bookings: ['mine', 'You have no bookings.'], waitlist: ['bell', "You're not on any waitlists."], bookmarks: ['bookmark', 'No bookmarked classes yet.'] }[this.tab];
    const rv = this.tab === 'bookings' ? St.pendingReviews() : [];
    b.innerHTML = (this.tab === 'bookings' ? goalsCardHTML() : '') + rv.map((r) => '<div class="card prompt">' + icon('star') + '<div class="grow"><b>Rate ' + esc(r.class.title) + '</b><p class="muted">' + esc(dayHeader(r.class.start_time)) + '</p></div><button class="btn lime sm" data-review="' + r.id + '">Rate</button></div>').join('') +
      (list.length ? classList(list, (c) => link('mine', 'class', c.id) + '?tab=' + this.tab, { selectedId: sel && sel.id }) : empty(msg[0], msg[1]));
  },
};

// ---------------------------------------------------------------- shared click handling for tab views

export function wireCommon(root) {
  root.addEventListener('click', (e) => {
    const t = e.target.closest('[data-act],[data-review],[data-checkin],[data-ticket]');
    if (!t) return;
    if (t.dataset.review) { const r = S.reviewable.find((x) => x.id === +t.dataset.review); if (r) openReview(r); return; }
    if (t.dataset.checkin) { e.preventDefault(); checkInFlow(+t.dataset.checkin, t); return; }
    if (t.dataset.ticket) { openTicket(+t.dataset.ticket); return; }
    const a = t.dataset.act;
    if (a === 'notifications') openNotifications();
    else if (a === 'menu') openMenu();
    else if (a === 'scan') openScanner();
  });
}
