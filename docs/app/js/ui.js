// Building blocks shared by the views: rows, cards, tabs, sheets, toasts (Theme.swift counterparts).
import { $, esc, icon, media, time, minutes, instructor, imgURL, initials, dayHeader, byDay } from './util.js';
import { S, studio, classBadge, friendsOn, isWellness } from './store.js';

/** Shrinks a page title to fit beside its header buttons (down to 60%, like iOS minimumScaleFactor),
 *  again whenever the row changes width (e.g. the My classes count arrives). */
const titleFit = window.ResizeObserver && new ResizeObserver((entries) => entries.forEach(({ target: t }) => {
  if (!t.isConnected) { titleFit.unobserve(t); return; }
  t.style.fontSize = '';
  const s = t.clientWidth / t.scrollWidth;
  if (s < 1) t.style.fontSize = Math.floor(Math.max(0.6, s) * parseFloat(getComputedStyle(t).fontSize) * 4) / 4 + 'px';
}));
export function fitTitle(t) { if (t && titleFit) titleFit.observe(t); }

let toastTimer;
export function toast(msg) {
  const t = $('#toast');
  t.textContent = msg; t.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2800);
}

/** Bottom sheet on phones, centred panel on wide screens. Returns {el, close}. `onClose` runs once. */
export function sheet(title, html, opts) {
  const d = document.createElement('dialog');
  d.className = 'sheet' + (opts && opts.cls ? ' ' + opts.cls : '');
  d.innerHTML = '<div class="sheet-bar"><button class="glass-btn" data-close aria-label="Close">' + icon('close') + '</button>' +
    '<h2>' + esc(title || '') + '</h2>' + ((opts && opts.trailing) || '<span class="glass-spacer"></span>') + '</div><div class="sheet-body">' + html + '</div>';
  document.body.appendChild(d);
  const close = () => { if (d.open) d.close(); };
  d.addEventListener('close', () => { d.remove(); if (opts && opts.onClose) opts.onClose(); });
  d.addEventListener('click', (e) => { if (e.target === d || e.target.closest('[data-close]')) close(); });
  d.showModal();
  return { el: d, body: d.querySelector('.sheet-body'), close };
}

export function confirmSheet(title, text, okLabel, tone) {
  return new Promise((resolve) => {
    let answer = false;
    const s = sheet(title, '<p class="sheet-text">' + esc(text) + '</p><div class="stack">' +
      '<button class="btn ' + (tone || 'red') + '" data-ok>' + esc(okLabel) + '</button><button class="btn glass" data-close>Not now</button></div>',
    { cls: 'small', onClose: () => resolve(answer) });
    s.el.querySelector('[data-ok]').addEventListener('click', () => { answer = true; s.close(); });
  });
}

/** Runs an async action from a button: disables it, shows errors as a toast. */
export async function run(btn, fn) {
  if (btn) btn.disabled = true;
  try { await fn(); } catch (e) { toast(e.message || String(e)); }
  finally { if (btn && btn.isConnected) btn.disabled = false; }
}

export const empty = (ic, text) => '<div class="empty">' + icon(ic) + '<p>' + esc(text) + '</p></div>';
export const loading = (text) => '<div class="loading">' + esc(text || 'Loading…') + '</div>';
export const sectionHeader = (text) => '<div class="section-head">' + esc(text) + '</div>';

export function avatar(u, size) {
  const s = size || 40;
  return '<span class="avatar" style="--s:' + s + 'px"><span>' + esc(initials(u)) + '</span>' +
    (u && u.photo ? '<img src="' + imgURL(u.photo, 132, 132) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '</span>';
}

/** Underline tabs with optional count badges ("Studios 6 · Classes 3"). */
export function underlineTabs(items, selected, attr) {
  return '<div class="utabs" role="tablist">' + items.map((it) => '<button role="tab" ' + attr + '="' + it.key + '" aria-selected="' + (it.key === selected) + '">' +
    esc(it.title) + (it.badge != null && it.badge !== '' ? '<span class="count">' + esc(it.badge) + '</span>' : '') + '</button>').join('') + '</div>';
}

export function chip(label, pressed, attrs) {
  return '<button class="chip" aria-pressed="' + !!pressed + '" ' + (attrs || '') + '>' + label + '</button>';
}

const badgeTone = { Waitlist: 'orange', Booked: 'teal', 'Checked in': 'teal', 'Spot open': 'teal' };
const badgeIcon = { Waitlist: 'bell', Booked: 'check', 'Checked in': 'checkSeal', 'Spot open': 'plus' };
export function pill(text, tone, ic) {
  return '<span class="pill ' + (tone || '') + '">' + (ic ? icon(ic) : '') + esc(text) + '</span>';
}

/** Class row (Theme.swift ClassRow): time + length, title, studio, "area | instructor", state pill, friends' faces. */
export function classRow(c, href, opts) {
  const o = opts || {};
  const st = studio(c.studio_id) || c.studio || {};
  const badge = o.badge !== undefined ? o.badge : classBadge(c);
  const line = o.meta || [st.vicinity, instructor(c.instructor)].filter(Boolean).join(' | ');
  const friends = o.friends === false ? [] : friendsOn(c.id);
  const dur = minutes(c.start_time, c.end_time);
  let state = '';
  if (badge) state = pill(badge, badgeTone[badge], badgeIcon[badge]);
  else if (c.available_spots != null && c.available_spots <= 0) state = '<span class="full">Fully booked</span>';
  return '<a class="crow' + (o.selected ? ' selected' : '') + '" href="' + href + '" data-class="' + c.id + '">' +
    '<div class="crow-time"><b>' + time(c.start_time) + '</b><small>' + (dur ? dur + ' min' : '') + '</small>' + (isWellness(c.studio_id) ? '<span class="wellness">Wellness</span>' : '') + '</div>' +
    '<div class="crow-body"><h3>' + esc(c.title) + '</h3>' + (o.hideStudio ? '' : '<p>' + esc(st.name || '') + '</p>') +
    (line ? '<p class="muted">' + esc(line) + '</p>' : '') + state +
    (friends.length ? '<div class="faces">' + friends.slice(0, 4).map((u) => avatar(u, 22)).join('') + '</div>' : '') + '</div>' +
    (o.trailing || (o.trailingOf ? o.trailingOf(c) : '')) + '</a>';
}

/** Class rows grouped under day headers. `hrefOf(c)` gives each row's link. */
export function classList(items, hrefOf, opts) {
  return byDay(items, (c) => c.start_time).map((g) => sectionHeader(dayHeader(g.iso)) +
    g.items.map((c) => classRow(c, hrefOf(c), Object.assign({}, opts, { selected: opts && opts.selectedId === c.id }))).join('')).join('');
}

/** Big photo card (Explore studio card / Home spotlight). */
export function photoCard(opts) {
  return '<a class="pcard ' + (opts.cls || '') + (opts.selected ? ' selected' : '') + '" href="' + opts.href + '">' + media(opts.photo, opts.w || 760, opts.h || 440, opts.glyph) +
    '<div class="pcard-top">' + (opts.topLeft || '<span></span>') + (opts.topRight || '') + '</div>' +
    '<div class="pcard-text"><h3>' + esc(opts.title) + '</h3>' + (opts.sub ? '<p>' + esc(opts.sub) + '</p>' : '') + '</div></a>';
}

/** Hero for class and studio pages: photo or gradient, title and subtitle on a dark fade, glass buttons on top. */
export function hero(opts) {
  return '<header class="hero">' + media(opts.photo, 900, 560, opts.glyph) +
    '<div class="hero-bar">' + opts.left + '<span class="spacer"></span>' + (opts.right || '') + '</div>' +
    '<div class="hero-text">' + (opts.tag ? '<span class="hero-tag">' + esc(opts.tag) + '</span>' : '') +
    '<h1>' + esc(opts.title) + '</h1>' + (opts.sub ? '<p>' + opts.sub + '</p>' : '') + '</div></header>';
}

export const glassBtn = (ic, attrs, label) => '<button class="glass-btn" ' + (attrs || '') + ' aria-label="' + esc(label || ic) + '">' + icon(ic) + '</button>';
export const glassLink = (ic, href, label) => '<a class="glass-btn" href="' + href + '" aria-label="' + esc(label || ic) + '">' + icon(ic) + '</a>';

export function stars(n, size) {
  let s = '<span class="stars" style="--s:' + (size || 14) + 'px" aria-label="' + n + ' of 5">';
  for (let i = 1; i <= 5; i++) s += icon('star', i <= n ? 'on' : '');
  return s + '</span>';
}

/** Leaflet map (vendored in vendor/leaflet, loaded on first use). Resolves to the map or null when it can't load. */
let leaflet;
export function loadLeaflet() {
  if (leaflet) return leaflet;
  leaflet = new Promise((resolve) => {
    const css = document.createElement('link');
    css.rel = 'stylesheet'; css.href = 'vendor/leaflet/leaflet.css';
    document.head.appendChild(css);
    const js = document.createElement('script');
    js.src = 'vendor/leaflet/leaflet.js';
    js.onload = () => resolve(window.L); js.onerror = () => resolve(null);
    document.head.appendChild(js);
  });
  return leaflet;
}
export async function makeMap(el, points, opts) {
  const L = await loadLeaflet();
  if (!L || !el.isConnected) { el.innerHTML = '<p class="muted map-off">' + icon('map') + ' Map unavailable</p>'; return null; }
  const map = L.map(el, { zoomControl: !(opts && opts.small), attributionControl: true, scrollWheelZoom: !(opts && opts.small) });
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map);
  const pts = points.filter((p) => p.lat && p.lon);
  const markers = pts.map((p) => {
    const m = L.marker([p.lat, p.lon], { icon: L.divIcon({ className: 'map-pin' + (p.fav ? ' fav' : ''), html: '<span></span>', iconSize: [18, 18], iconAnchor: [9, 9] }) }).addTo(map);
    if (p.label) m.bindTooltip(p.label, { direction: 'top', offset: [0, -8] });
    if (p.href) m.on('click', () => { location.hash = p.href; });
    return m;
  });
  if (pts.length === 1) map.setView([pts[0].lat, pts[0].lon], (opts && opts.zoom) || 15);
  else if (pts.length) map.fitBounds(L.latLngBounds(pts.map((p) => [p.lat, p.lon])).pad(0.1));
  else if (opts && opts.center) map.setView(opts.center, 12);
  setTimeout(() => map.invalidateSize(), 50);
  return { map, markers };
}
