// Shared helpers: storage, formatting (Stockholm time by default), escaping, a small Markdown subset and icons.

export const ls = {
  get(k, fallback) { try { const v = localStorage.getItem(k); return v == null ? fallback : JSON.parse(v); } catch (e) { return fallback; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* quota or private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } },
};

export const $ = (sel, root) => (root || document).querySelector(sel);
export const $$ = (sel, root) => [...(root || document).querySelectorAll(sel)];
export const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const IMG = 'https://res.cloudinary.com/dbo5hzaqa/image/upload/c_fill,dpr_2,h_{h},q_60,w_{w}/{id}.jpg';
export const imgURL = (id, w, h) => (id ? IMG.replace('{w}', w || 400).replace('{h}', h || 250).replace('{id}', encodeURIComponent(id)) : '');

let zone = 'Europe/Stockholm';
export const setZone = (z) => { zone = z || 'Europe/Stockholm'; };
export const getZone = () => zone;

export function fmt(iso, opts) {
  if (!iso) return '';
  try { return new Intl.DateTimeFormat('en-GB', Object.assign({ timeZone: zone }, opts)).format(new Date(iso)); } catch (e) { return ''; }
}
export const time = (iso) => fmt(iso, { hour: '2-digit', minute: '2-digit', hour12: false });
/** Orders two timestamps by the instant they name, not their text: the API mixes "Z" and offset spellings. Missing ones go last. */
export function byInstant(a, b) {
  const x = a ? Date.parse(a) : NaN, y = b ? Date.parse(b) : NaN;
  return (isNaN(x) ? Infinity : x) - (isNaN(y) ? Infinity : y) || 0;
}
/** Sort comparator for classes by start time. */
export const byStart = (a, b) => byInstant(a.start_time, b.start_time);
/** Whether a class starts on `day` (YYYY-MM-DD in the city's time zone). A studio's day query also returns classes from other days. */
export const onDay = (c, day) => !!c.start_time && dayKey(c.start_time) === day;
/** YYYY-MM-DD of an instant in the city's time zone. */
export function dayKey(d) {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(d));
  const g = (t) => p.find((x) => x.type === t).value;
  return g('year') + '-' + g('month') + '-' + g('day');
}
export function addDays(key, n) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n, 12)).toISOString().slice(0, 10);
}
export const todayKey = () => dayKey(new Date());
const noon = (key) => new Date(key + 'T12:00:00Z');
/** ["Today", "14 Oct"] for the day chips. */
export function dayChip(key) {
  const t = todayKey();
  const num = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(noon(key));
  if (key === t) return ['Today', num];
  if (key === addDays(t, 1)) return ['Tomorrow', num];
  return [new Intl.DateTimeFormat('en-GB', { weekday: 'short', timeZone: 'UTC' }).format(noon(key)), num];
}
/** "Today, 14 October" / "Monday, 12 October" (section headers). */
export function dayHeader(iso) {
  const k = dayKey(iso);
  if (k === todayKey()) return 'Today, ' + fmt(iso, { day: 'numeric', month: 'long' });
  if (k === addDays(todayKey(), 1)) return 'Tomorrow, ' + fmt(iso, { day: 'numeric', month: 'long' });
  return fmt(iso, { weekday: 'long', day: 'numeric', month: 'long' });
}
/** "Tomorrow, 12 October, 11:30 - 12:15" (class page). */
export function classDateLine(c) {
  return dayHeader(c.start_time) + ', ' + time(c.start_time) + (c.end_time ? ' - ' + time(c.end_time) : '');
}
/** "11:20, Monday, 12 October" (booking rules). */
export const ruleTime = (d) => time(d) + ', ' + fmt(d, { weekday: 'long', day: 'numeric', month: 'long' });
export const minutes = (a, b) => (a && b ? Math.round((new Date(b) - new Date(a)) / 60000) : null);
export const instructor = (s) => (s ? s.replace(/\*\*/g, '').trim() || null : null);
export const isListed = (c) => c && c.deleted !== true && !c.deleted_at && c.canceled !== true;
export const rating = (r) => (r && r.average > 0 ? (r.average / 100).toFixed(1).replace('.', ',') : null);
export const distance = (m) => (m < 1000 ? Math.round(m / 10) * 10 + ' m' : (m / 1000).toFixed(1).replace('.', ',') + ' km');
export function metres(lat1, lon1, lat2, lon2) {
  const R = 6371000, r = Math.PI / 180;
  const a = Math.sin((lat2 - lat1) * r / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin((lon2 - lon1) * r / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
export const initials = (u) => ((u && (u.first_name || '')[0] || '') + (u && (u.last_name || '')[0] || '')).toUpperCase();
export const fullName = (u) => (u ? [u.first_name, u.last_name].filter(Boolean).join(' ') : '');
export const money = (ore, cur) => ((cur || 'SEK').toUpperCase() + ' ' + Math.round((ore || 0) / 100));

/** Groups items by day of `dateOf(item)`, in order. */
export function byDay(items, dateOf) {
  const out = [];
  for (const it of items) {
    const d = dateOf(it); if (!d) continue;
    const k = dayKey(d);
    let g = out.find((x) => x.key === k);
    if (!g) { g = { key: k, iso: d, items: [] }; out.push(g); }
    g.items.push(it);
  }
  return out;
}

/** Tiny Markdown subset (paragraphs, **bold**, *italic*, lists, links) on escaped text. */
export function rich(md) {
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

/** "STC Södermalm" -> "stc-sodermalm" (share links, as in ShareURL.swift). */
export const slug = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// Line icons in the spirit of SF Symbols (24px grid, stroked with currentColor).
const P = {
  home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v9.5h5v-5.5h3v5.5h5V10"/>',
  explore: '<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5z"/>',
  checkin: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3"/><path d="M8 8h3v3H8zM13 8h3v3h-3zM8 13h3v3H8zM14 14h2v2h-2z"/>',
  friends: '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c.8-3.3 3.2-5 6-5s5.2 1.7 6 5"/><circle cx="17" cy="9" r="2.6"/><path d="M16 14.2c2.4 0 4.3 1.5 5 4.3"/>',
  mine: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M8 3v4M16 3v4M3.5 10h17"/><path d="m9 15 2 2 4-4"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  back: '<path d="m15 5-7 7 7 7"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  down: '<path d="m6 9 6 6 6-6"/>',
  share: '<path d="M12 3v12M8 7l4-4 4 4"/><path d="M6 11v8.5h12V11"/>',
  heart: '<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10Z"/>',
  bookmark: '<path d="M7 3.5h10v17l-5-3.6-5 3.6z"/>',
  map: '<path d="m3.5 6 5.5-2 6 2 5.5-2v14l-5.5 2-6-2-5.5 2z"/><path d="M9 4v14M15 6v14"/>',
  star: '<path d="m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1 5.8-5.2-2.8-5.2 2.8 1-5.8-4.3-4.1 5.9-.8z"/>',
  person: '<circle cx="12" cy="8" r="3.6"/><path d="M5 20c.9-3.8 3.7-6 7-6s6.1 2.2 7 6"/>',
  people: '<circle cx="8" cy="9" r="2.6"/><circle cx="16" cy="9" r="2.6"/><path d="M3 18c.6-2.6 2.6-4 5-4s4.4 1.4 5 4M11 18c.6-2.6 2.6-4 5-4s4.4 1.4 5 4"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M8 3v4M16 3v4M3.5 10h17"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  ticket: '<path d="M3.5 7.5h17v3a1.5 1.5 0 0 0 0 3v3h-17v-3a1.5 1.5 0 0 0 0-3z"/><path d="M14.5 7.5v9" stroke-dasharray="1.5 1.8"/>',
  infinity: '<path d="M12 12c-2-2.6-3.6-4-5.5-4a4 4 0 0 0 0 8c1.9 0 3.5-1.4 5.5-4Zm0 0c2 2.6 3.6 4 5.5 4a4 4 0 0 0 0-8c-1.9 0-3.5 1.4-5.5 4Z"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
  filter: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  pin: '<path d="M12 21s-6.5-5.8-6.5-11a6.5 6.5 0 0 1 13 0c0 5.2-6.5 11-6.5 11Z"/><circle cx="12" cy="10" r="2.3"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  checkSeal: '<path d="M12 2.8 14.3 4.5l2.8-.2.9 2.7 2.4 1.5-.9 2.7.9 2.7-2.4 1.5-.9 2.7-2.8-.2L12 21.2l-2.3-1.7-2.8.2-.9-2.7L3.6 15.5l.9-2.7-.9-2.7L6 8.6l.9-2.7 2.8.2z"/><path d="m8.5 12 2.4 2.4 4.6-4.8"/>',
  door: '<path d="M6 20.5V4.5a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v16M3.5 20.5h17"/><circle cx="14.5" cy="12" r=".9"/>',
  camera: '<path d="M4 8h3l1.5-2.5h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',
  chart: '<path d="M4 20h16"/><path d="M7 16v-5M12 16V7M17 16v-8"/>',
  card: '<rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="M3 10h18"/>',
  receipt: '<path d="M6 3.5h12v17l-2-1.3-2 1.3-2-1.3-2 1.3-2-1.3-2 1.3z"/><path d="M9 8h6M9 12h6"/>',
  gift: '<rect x="4" y="9" width="16" height="11" rx="1"/><path d="M3 9h18M12 9v11M12 9c-1.5-3.5-5-4-5-1.5S12 9 12 9Zm0 0c1.5-3.5 5-4 5-1.5S12 9 12 9Z"/>',
  logout: '<path d="M14 4h-8v16h8M10 12h10M17 8.5l3.5 3.5-3.5 3.5"/>',
  strike: '<circle cx="12" cy="12" r="8.5"/><path d="m6 6 12 12"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M5.2 18.8l1.4-1.4M17.4 6.6l1.4-1.4"/>',
  dumbbell: '<path d="M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/>',
  run: '<circle cx="14.5" cy="4.5" r="1.8"/><path d="m8 21 3-6 3 2.5V22M6 11.5 9 8l4 1 2.5 3.5 3 .5M11 15l2-6"/>',
  yoga: '<circle cx="12" cy="5" r="1.8"/><path d="M4 12c3 0 5-1.5 8-1.5s5 1.5 8 1.5M12 10.5V15l-4 5M12 15l4 5"/>',
  spa: '<path d="M12 20c-4.5 0-7.5-3-7.5-7.5 3 0 5.5 1 7.5 3 2-2 4.5-3 7.5-3 0 4.5-3 7.5-7.5 7.5Z"/><path d="M12 15.5c-1.5-2-1.5-5.5 0-9.5 1.5 4 1.5 7.5 0 9.5Z"/>',
  building: '<path d="M5 21V4h9v17M14 9h5v12M3 21h18"/><path d="M8 7h3M8 11h3M8 15h3"/>',
  bike: '<circle cx="5.5" cy="16.5" r="3.5"/><circle cx="18.5" cy="16.5" r="3.5"/><path d="M5.5 16.5 9 9h6l3.5 7.5M9 9l3 7.5h-1M14 5h2l-1 4"/>',
  walk: '<circle cx="13" cy="4" r="2"/><path d="m9 21 2-6 3 3v3M7 12l3-4 4 1 3 4M11 15l1-5"/>',
  tram: '<rect x="5" y="4" width="14" height="13" rx="3"/><path d="M5 11h14M8 21l2-4M16 21l-2-4"/><path d="M9 14h.01M15 14h.01"/>',
  car: '<path d="M3 16v-3l2-5h14l2 5v3zM5 16v2M19 16v2"/><path d="M7.5 13h.01M16.5 13h.01"/>',
  brief: '<rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M9 7V5h6v2M3 12.5h18"/>',
  history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5M12 7v5l3 2"/>',
  flame: '<path d="M12 21.5c3.9 0 6.5-2.6 6.5-6.4 0-3.7-2.7-6-3.6-9.4-1.9 1.8-2.8 3.7-2.8 5.6-.9-.9-1.8-1.9-2-3.3-2 2.3-4.6 4.5-4.6 7.1 0 3.8 2.6 6.4 6.5 6.4Z"/>',
  trophy: '<path d="M8 4h8v5a4 4 0 0 1-8 0zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8 20h8M10 17h4"/>',
  swim: '<path d="M2 18c2 0 2-1.5 4-1.5S8 18 10 18s2-1.5 4-1.5 2 1.5 4 1.5 2-1.5 4-1.5M2 14c2 0 2-1.5 4-1.5S8 14 10 14s2-1.5 4-1.5 2 1.5 4 1.5"/><circle cx="17" cy="6" r="2"/><path d="m6 11 4-4 4 3"/>',
  target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r=".6"/>',
  spark: '<path d="M12 2.5l2 6.8 6.8 2.7-6.8 2.7-2 6.8-2-6.8-6.8-2.7 6.8-2.7z"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  location: '<path d="m4 11 16-7-7 16-2-7z"/>',
};
export const icon = (name, cls) => '<svg class="i' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" aria-hidden="true">' + (P[name] || '') + '</svg>';

/** Glyph for a placeholder card: category words -> a matching icon. */
export function glyphFor(text) {
  const t = (text || '').toLowerCase();
  if (/yoga|pilates|meditat|mobility|stretch|barre/.test(t)) return 'yoga';
  if (/spa|sauna|massage|wellness|cryo|red light|salt|bastu|naprapat/.test(t)) return 'spa';
  if (/gym|strength|crossfit|hyrox|lift/.test(t)) return 'dumbbell';
  if (/studio|club/.test(t)) return 'building';
  return 'run';
}
/** Same palettes and hash as RemotePhoto.placeholder in the iOS app. */
const PALETTES = [['#333d29', '#8ca829'], ['#1a4045', '#299e8f'], ['#40291f', '#c77533'], ['#242438', '#6b66b3'], ['#1f1f1f', '#616166']];
export function palette(key) {
  let h = 0;
  for (const ch of String(key || '')) h = (h * 31 + ch.codePointAt(0)) & 0xffff;
  return PALETTES[h % PALETTES.length];
}
/** Photo layer for a card: deterministic gradient with a faint glyph, covered by the Cloudinary photo when it loads. */
export function media(id, w, h, glyphText) {
  const [a, b] = palette(id || glyphText);
  return '<div class="media" style="background:linear-gradient(135deg,' + a + ',' + b + ')">' + icon(glyphFor(glyphText), 'glyph') +
    (id ? '<img src="' + imgURL(id, w, h) + '" alt="" loading="lazy" onerror="this.remove()">' : '') + '</div>';
}
