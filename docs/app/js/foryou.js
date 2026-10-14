// "For you" on Home (picks from recommend.js with the reasons as chips) and Settings > Places & commute.
// Places are stored on this device only (store.js `placesState`); travel times are estimated from distance.
import { $, esc, icon, fmt, time, minutes, todayKey, dayKey, addDays, instructor, metres } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import { sheet, toast, avatar, loadLeaflet, empty, loading } from './ui.js';
import { recommend, MODES, travelMinutes } from './recommend.js';

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const state = { loading: null, ready: false, error: null };

/** Loads what the scoring needs once (history, studios with coordinates, the next days' classes); Home re-renders. */
export function ensureForYou() {
  if (state.ready || state.loading) return;
  const today = todayKey();
  state.loading = Promise.all([
    St.loadHistory().catch(() => []), St.loadStudios().catch(() => {}),
    ...[0, 1, 2].map((i) => St.dayClasses(addDays(today, i)).catch(() => [])),
  ]).then(() => { state.ready = true; state.day = today; })
    .catch((e) => { state.error = e.message; })
    .finally(() => { state.loading = null; St.emit(); });
}

/** The ranked picks right now. */
export function picks(limit) {
  if (!state.ready) return null;
  if (state.day !== todayKey()) { state.ready = false; ensureForYou(); return null; }
  const p = St.placesState();
  const classes = [0, 1, 2].flatMap((i) => (S.classCache.get(S.settings.cityId + ':' + addDays(state.day, i)) || {}).classes || []);
  const studios = new Map([...S.studios.values()].map((s) => [s.id, { lat: s.lat, lon: s.lon, name: s.name }]));
  const friends = S.friendsBookings.map((b) => ({ userId: b.user_id, classId: b.class_id, name: (St.friendUser(b.user_id) || {}).first_name }));
  return recommend({
    classes, visits: St.visitList(false), now: Date.now(), zone: St.city().time_zone, booked: new Set(S.bookings.keys()),
    friends, studios, catTitle: St.catTitle, places: p.places, prefs: p, limit: limit || 8,
  });
}

function chips(r) {
  return '<div class="why">' + r.reasons.map((x) => '<span class="why-chip' + (x.tone ? ' ' + x.tone : '') + '">' +
    (x.faces ? '<span class="faces">' + x.faces.slice(0, 3).map((id) => avatar(St.friendUser(id) || { first_name: '?' }, 20)).join('') + '</span>' : x.icon ? icon(x.icon) : '') +
    esc(x.text) + '</span>').join('') + '</div>';
}
function recCard(r, href, sel) {
  const c = r.class;
  const st = St.studio(c.studio_id) || c.studio || {};
  const dur = minutes(c.start_time, c.end_time);
  const line = [st.vicinity, instructor(c.instructor)].filter(Boolean).join(' | ');
  return '<a class="card fy-rec' + (sel ? ' selected' : '') + '" href="' + href + '"><div class="crow-time"><b>' + time(c.start_time) + '</b><small>' + (dur ? dur + ' min' : '') + '</small></div>' +
    '<div class="crow-body"><h3>' + esc(c.title) + '</h3><p>' + esc(st.name || '') + '</p>' + (line ? '<p class="muted">' + esc(line) + '</p>' : '') + '</div>' + chips(r) + '</a>';
}
/** "Tomorrow, Thu 15 Oct". */
function whenLine(iso) {
  const k = dayKey(iso);
  const word = k === todayKey() ? 'Today, ' : k === addDays(todayKey(), 1) ? 'Tomorrow, ' : '';
  return word + fmt(iso, { weekday: 'short', day: 'numeric', month: 'short' });
}

/** The Home section. `link(id)` gives a class link; `sel` the selected detail. */
export function forYouHTML(link, sel) {
  ensureForYou();
  const list = picks(8);
  const head = (sub) => '<div class="sec-row"><h2 class="sec-title">For you' + (sub ? ' <small>' + esc(sub) + '</small>' : '') + '</h2>' +
    '<button class="glass-btn sm" data-fy="places" aria-label="Places and commute">' + icon('pin') + '</button></div>';
  if (!list) return head('') + (state.error ? '' : '<div class="card fy-wait">' + loading('Finding classes for you…') + '</div>');
  if (!list.length) return head('') + '<div class="card">' + empty('spark', 'No picks right now. Classes for the next two days show up here.') + '</div>';
  const [top, ...more] = list;
  const c = top.class;
  const st = St.studio(c.studio_id) || c.studio || {};
  const when = whenLine(c.start_time);
  const dur = minutes(c.start_time, c.end_time);
  let html = head(when) +
    '<a class="fy-hero' + (sel && sel.id === c.id ? ' selected' : '') + '" href="' + link(c.id) + '">' +
    '<span class="fy-match">' + top.match + '% match</span><span class="glass-pill fy-studio">' + esc(st.name || 'Studio') + '</span>' +
    '<h3>' + esc(c.title) + '</h3><p>' + esc(fmt(c.start_time, { weekday: 'long' }) + ' | ' + fmt(c.start_time, { day: 'numeric', month: 'long' }) + ' | ' + time(c.start_time) + (dur ? ' · ' + dur + ' min' : '')) + '</p>' +
    chips(top) + '</a>';
  if (more.length) {
    html += '<div class="sec-row"><h2 class="sec-title">More picks</h2><button class="btn glass sm" data-fy="all">Show all</button></div>' +
      more.slice(0, 3).map((r) => recCard(r, link(r.class.id), sel && sel.id === r.class.id)).join('');
  }
  if (!St.placesState().places.length) {
    html += '<button class="card row-card" data-fy="places">' + icon('pin') + '<div class="grow"><b>Add home and work</b><p class="muted">Picks with travel times, and classes on your way home.</p></div>' + icon('chevron') + '</button>';
  }
  return html;
}

/** Click handling for the section (delegated from Home). Returns true when handled. */
export function forYouClick(e, link) {
  const b = e.target.closest('[data-fy]');
  if (!b) return false;
  if (b.dataset.fy === 'places') openPlaces();
  else if (b.dataset.fy === 'all') {
    const list = picks(20) || [];
    sheet('For you', '<p class="muted center">The next two days, best match first.</p>' + list.map((r) =>
      '<div class="fy-all"><span class="fy-pct">' + r.match + '%</span>' + recCard(r, link(r.class.id)).replace('<a ', '<a data-close ') + '</div>').join(''), { cls: 'tall' });
  }
  return true;
}

// ---------------------------------------------------------------- Places & commute

function placeIcon(p) { return p.kind === 'home' ? 'home' : p.kind === 'work' ? 'brief' : 'pin'; }
function placeSub(p) {
  const days = p.kind === 'work' ? workdaysText(p.workdays || [0, 1, 2, 3, 4]) : '';
  return [p.label, days].filter(Boolean).join(' · ');
}
function workdaysText(ds) {
  const d = [...ds].sort();
  if (!d.length) return 'No workdays';
  const run = d.every((x, i) => i === 0 || x === d[i - 1] + 1);
  return run && d.length > 2 ? WEEKDAYS[d[0]] + '–' + WEEKDAYS[d[d.length - 1]] : d.map((x) => WEEKDAYS[x]).join(', ');
}
/** "Near Example Yoga Studio, Vasastan": the nearest studio names a point without sending it anywhere. */
function nearLabel(lat, lon) {
  let best = null, bd = Infinity;
  for (const s of S.studios.values()) {
    if (s.lat == null) continue;
    const d = metres(lat, lon, s.lat, s.lon);
    if (d < bd) { bd = d; best = s; }
  }
  return best ? (bd < 150 ? 'At ' : 'Near ') + best.name + (best.vicinity ? ', ' + best.vicinity : '') : lat.toFixed(4) + ', ' + lon.toFixed(4);
}

/** Leaflet map with the places, a sample route home - work and its travel time. */
async function placesMap(el, p, onPick) {
  const L = await loadLeaflet();
  if (!L || !el.isConnected) { el.innerHTML = '<p class="muted map-off">' + icon('map') + ' Map unavailable</p>'; return null; }
  const c = St.city().coordinates || { latitude: 59.33, longitude: 18.07 };
  const map = L.map(el, { zoomControl: false, attributionControl: true });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map);
  const layer = L.layerGroup().addTo(map);
  const draw = (state) => {
    layer.clearLayers();
    const pts = state.places.filter((x) => x.lat != null);
    pts.forEach((x) => L.marker([x.lat, x.lon], { icon: L.divIcon({ className: 'place-pin ' + x.kind, html: '<span>' + icon(placeIcon(x)) + '</span>', iconSize: [30, 30], iconAnchor: [15, 15] }) })
      .addTo(layer).bindTooltip(x.name || x.kind, { direction: 'top', offset: [0, -14] }));
    const home = pts.find((x) => x.kind === 'home'), work = pts.find((x) => x.kind === 'work');
    if (home && work) {
      L.polyline([[home.lat, home.lon], [work.lat, work.lon]], { color: '#2c2c2e', weight: 3.5, dashArray: '7 6', className: 'route-line' }).addTo(layer);
      const mode = MODES[state.mode] ? state.mode : 'bike';
      L.marker([(home.lat + work.lat) / 2, (home.lon + work.lon) / 2], { icon: L.divIcon({ className: 'route-pill', html: '<span>' + icon(MODES[mode].icon) + travelMinutes(home, work, mode) + ' min</span>', iconSize: [84, 26], iconAnchor: [42, 13] }) }).addTo(layer);
    }
    if (pts.length > 1) map.fitBounds(L.latLngBounds(pts.map((x) => [x.lat, x.lon])).pad(0.35));
    else if (pts.length === 1) map.setView([pts[0].lat, pts[0].lon], 14);
    else map.setView([c.latitude, c.longitude], 12);
  };
  draw(p);
  if (onPick) map.on('click', (e) => onPick(e.latlng.lat, e.latlng.lng));
  setTimeout(() => map.invalidateSize(), 60);
  return { map, draw };
}

/** Settings > Places & commute. */
export function openPlaces() {
  let p = St.placesState();
  St.loadStudios().catch(() => {});
  const s = sheet('Places & commute', '<div class="map places-map" id="pl-map"></div><div id="pl-body"></div>', { cls: 'tall' });
  let m = null;
  placesMap($('#pl-map', s.el), p).then((x) => { m = x; });
  const save = () => { St.savePlaces(p); if (m) m.draw(p); };
  const draw = () => {
    const body = $('#pl-body', s.el);
    const opt = (v, cur, label) => '<option value="' + v + '"' + (String(v) === String(cur) ? ' selected' : '') + '>' + esc(label) + '</option>';
    body.innerHTML = '<h3 class="section-head">Places</h3><div class="card menu">' +
      p.places.map((x, i) => '<button class="mrow" data-pl="' + i + '"><span class="place-ic ' + x.kind + '">' + icon(placeIcon(x)) + '</span><span class="grow"><b>' + esc(x.name) + '</b><small class="muted block">' + esc(placeSub(x)) + '</small></span>' + icon('chevron') + '</button>').join('') +
      '<button class="mrow lime-ink" data-pl="new">' + icon('plus') + '<span class="grow">Add place</span></button></div>' +
      '<p class="muted small foot">' + icon('lock') + ' Saved on this device only. Never sent to Bruce or our server.</p>' +
      '<h3 class="section-head">How you get around</h3><div class="chips wrap">' + Object.entries(MODES).map(([k, v]) =>
        '<button class="chip glassy" aria-pressed="' + (p.mode === k) + '" data-mode="' + k + '">' + icon(v.icon) + esc(v.label) + '</button>').join('') + '</div>' +
      '<div class="card form-rows">' +
      '<label class="frow"><span class="grow">Max detour</span><select id="pl-detour">' + [5, 10, 15, 20, 30].map((n) => opt(n, p.maxDetour, n + ' min')).join('') + '</select></label>' +
      '<div class="frow"><span class="grow">Workdays near work</span><input type="time" id="pl-from" value="' + esc(p.workFrom) + '" aria-label="From"><span class="muted">–</span><input type="time" id="pl-to" value="' + esc(p.workTo) + '" aria-label="To"></div>' +
      '<label class="toggle"><span>Use friends’ bookings<small class="muted">Picks classes your friends booked.</small></span><input type="checkbox" id="pl-friends"' + (p.useFriends ? ' checked' : '') + '><i></i></label></div>' +
      '<p class="muted small foot">Travel times are estimates from the distance. On workdays, classes in the time window count from work, and evening classes on the way home show the extra minutes.</p>';
    body.querySelectorAll('[data-pl]').forEach((b) => b.addEventListener('click', () => editPlace(b.dataset.pl === 'new' ? null : +b.dataset.pl)));
    body.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => { p.mode = b.dataset.mode; save(); draw(); }));
    $('#pl-detour', body).addEventListener('change', (e) => { p.maxDetour = +e.target.value; save(); });
    $('#pl-from', body).addEventListener('change', (e) => { p.workFrom = e.target.value || '11:30'; save(); });
    $('#pl-to', body).addEventListener('change', (e) => { p.workTo = e.target.value || '13:30'; save(); });
    $('#pl-friends', body).addEventListener('change', (e) => { p.useFriends = e.target.checked; save(); });
  };
  draw();

  function editPlace(i) {
    const isNew = i == null;
    const has = (k) => p.places.some((x) => x.kind === k);
    const x = isNew ? { id: 'p' + Date.now().toString(36), kind: !has('home') ? 'home' : !has('work') ? 'work' : 'other', name: '', label: '', lat: null, lon: null, workdays: [0, 1, 2, 3, 4] } : Object.assign({}, p.places[i]);
    const studios = St.cityStudios().filter((z) => z.lat != null).sort((a, b) => a.name.localeCompare(b.name, 'sv'));
    const e = sheet(isNew ? 'Add place' : x.name, '<div class="chips wrap" id="ep-kind">' + [['home', 'Home'], ['work', 'Work'], ['other', 'Other']].map(([k, t]) =>
      '<button class="chip glassy" data-kind="' + k + '" aria-pressed="' + (x.kind === k) + '">' + icon(placeIcon({ kind: k })) + t + '</button>').join('') + '</div>' +
      '<label class="form" id="ep-name-wrap"><span>Name</span><input type="text" id="ep-name" value="' + esc(x.name) + '" placeholder="Gym bag stop"></label>' +
      '<p class="ep-where" id="ep-where"></p>' +
      '<div class="map places-map small-pick" id="ep-map"></div><p class="muted small center">Tap the map to set the place.</p>' +
      '<div class="row2"><button class="btn glass" data-ep="here">' + icon('location') + ' My location</button>' +
      '<label class="btn glass select-btn">' + icon('building') + ' Studio<select id="ep-studio" aria-label="Studio address"><option value="">Studio address</option>' + studios.map((z) => '<option value="' + z.id + '">' + esc(z.name) + '</option>').join('') + '</select></label></div>' +
      '<div id="ep-days"></div>' +
      '<button class="btn lime" data-ep="save">' + (isNew ? 'Add place' : 'Save') + '</button>' + (isNew ? '' : '<button class="btn glass red-text" data-ep="delete">' + icon('trash') + ' Delete place</button>'), { cls: 'tall' });
    let pm = null;
    const set = (lat, lon, label) => { x.lat = lat; x.lon = lon; x.label = label || nearLabel(lat, lon); paint(); if (pm) pm.draw({ places: [x], mode: p.mode }); };
    const paint = () => {
      $('#ep-where', e.el).innerHTML = x.lat != null ? icon('pin') + ' ' + esc(x.label) : '<span class="muted">' + icon('pin') + ' No location yet</span>';
      $('#ep-name-wrap', e.el).hidden = x.kind !== 'other';
      e.el.querySelectorAll('[data-kind]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.kind === x.kind));
      $('#ep-days', e.el).innerHTML = x.kind === 'work' ? '<h3 class="section-head">Workdays</h3><div class="chips wrap">' + WEEKDAYS.map((d, k) =>
        '<button class="chip glassy" data-wd="' + k + '" aria-pressed="' + (x.workdays || []).includes(k) + '">' + d + '</button>').join('') + '</div>' : '';
      e.el.querySelectorAll('[data-wd]').forEach((b) => b.addEventListener('click', () => {
        const k = +b.dataset.wd; const w = new Set(x.workdays || []);
        if (w.has(k)) w.delete(k); else w.add(k);
        x.workdays = [...w].sort(); paint();
      }));
    };
    paint();
    placesMap($('#ep-map', e.el), { places: x.lat != null ? [x] : [], mode: p.mode }, (lat, lon) => set(lat, lon)).then((mm) => { pm = mm; });
    e.el.querySelectorAll('[data-kind]').forEach((b) => b.addEventListener('click', () => { x.kind = b.dataset.kind; paint(); }));
    $('#ep-studio', e.el).addEventListener('change', (ev) => {
      const z = St.studio(+ev.target.value);
      if (z && z.lat != null) set(z.lat, z.lon, (z.address || z.name) + (z.vicinity ? ', ' + z.vicinity : ''));
    });
    e.el.querySelector('[data-ep="here"]').addEventListener('click', () => {
      if (!navigator.geolocation) { toast('Location is not available in this browser.'); return; }
      navigator.geolocation.getCurrentPosition((pos) => set(pos.coords.latitude, pos.coords.longitude),
        () => toast('No location access. Tap the map or pick a studio instead.'), { timeout: 8000, maximumAge: 60000 });
    });
    e.el.querySelector('[data-ep="save"]').addEventListener('click', () => {
      if (x.lat == null) { toast('Set the place on the map first.'); return; }
      x.name = x.kind === 'home' ? 'Home' : x.kind === 'work' ? 'Work' : ($('#ep-name', e.el).value.trim() || 'Place');
      if (x.kind !== 'other') p.places = p.places.filter((y, k) => !(y.kind === x.kind && k !== i));
      const j = isNew ? -1 : p.places.indexOf(p.places.find((y) => y.id === x.id));
      if (j >= 0) p.places[j] = x; else p.places.push(x);
      p.places.sort((a, b) => ['home', 'work', 'other'].indexOf(a.kind) - ['home', 'work', 'other'].indexOf(b.kind));
      save(); draw(); e.close(); toast(x.name + ' saved on this device');
    });
    const del = e.el.querySelector('[data-ep="delete"]');
    if (del) del.addEventListener('click', () => { p.places = p.places.filter((y) => y.id !== x.id); save(); draw(); e.close(); });
  }
}

