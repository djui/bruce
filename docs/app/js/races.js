// Races (Shared/BruceCore/Races.swift): the hand-curated catalog in ../races.json and My races on this device.
// Pure functions on plain objects, with race days as "YYYY-MM-DD" and `today` passed in (tests in
// test/races.test.js); racesui.js draws them. Brüce only links to each race's own page: nothing is signed up,
// paid for or read from a registration platform, and race names are plain text.

export const TYPES = [
  { key: 'running', title: 'Running', short: 'Running', glyph: 'run' },
  { key: 'hyrox', title: 'HYROX', short: 'HYROX', glyph: 'dumbbell' },
  { key: 'obstacle', title: 'Obstacle', short: 'Obstacle', glyph: 'flag' },
  { key: 'endurance', title: 'Ski, bike, swim', short: 'Endurance', glyph: 'ski' },
  { key: 'triathlon', title: 'Triathlon', short: 'Triathlon', glyph: 'swim' },
];
export const SPORTS = { ski: { title: 'Ski', glyph: 'ski' }, bike: { title: 'Bike', glyph: 'bike' }, swim: { title: 'Swim', glyph: 'swim' } };
export const STATUSES = ['open', 'opensSoon', 'soldOut', 'lottery', 'checkSite'];
export const COUNTRIES = [['SE', 'Sweden'], ['NO', 'Norway'], ['DK', 'Denmark']];
export const CURRENCIES = ['SEK', 'NOK', 'DKK', 'EUR'];
export const CUSTOM = 'custom-';

const type = (r) => TYPES.find((t) => t.key === r.type) || TYPES[0];
export const typeTitle = (key) => (TYPES.find((t) => t.key === key) || {}).title || key;
export const countryName = (code) => (COUNTRIES.find((c) => c[0] === code) || [code, code])[1];

// ---------------------------------------------------------------- days

const noon = (d) => new Date(d + 'T12:00:00Z');
/** A real calendar date written as YYYY-MM-DD. */
export const isDay = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(noon(s)) && noon(s).toISOString().slice(0, 10) === s;
export function addDay(d, n) { const t = noon(d); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10); }
/** Whole days from `a` to `b` (both YYYY-MM-DD). */
export const daysBetween = (a, b) => Math.round((noon(b) - noon(a)) / 86400000);
// Written out rather than from Intl, so every browser (and node) says the same as the Apple apps ("Sep", not "Sept").
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
/** "Sat 15 May 2027" style pieces: wd (Sat), weekday (Saturday), d (15), mon (May), month (May), y (2027). */
function pieces(d) {
  const t = noon(d), month = MONTHS[+d.slice(5, 7) - 1], weekday = WEEKDAYS[t.getUTCDay()];
  return { wd: weekday.slice(0, 3), weekday, d: String(+d.slice(8)), mon: month.slice(0, 3), month, y: d.slice(0, 4) };
}
/** "15 May", "Sat 15 May", "Sat 15 May 2027". */
export function shortDay(d, withWeekday, withYear) {
  const p = pieces(d);
  return (withWeekday ? p.wd + ' ' : '') + p.d + ' ' + p.mon + (withYear ? ' ' + p.y : '');
}

export const lastDay = (r) => r.endDate || r.date;
export const isMultiDay = (r) => !!r.endDate && r.endDate !== r.date;
/** Every day of the event. */
export function days(r) {
  const out = [r.date];
  while (out[out.length - 1] < lastDay(r) && out.length < 14) out.push(addDay(out[out.length - 1], 1));
  return out;
}
export const isCustom = (r) => String(r.id).startsWith(CUSTOM);
export const daysToGo = (r, today, day) => daysBetween(today, day || r.date);
/** The event (or the member's day of it) is over. */
export const isPast = (r, today, day) => daysBetween(today, day || lastDay(r)) < 0;
export function countdownText(r, today, day) {
  if (isPast(r, today, day)) return 'Done';
  const n = daysToGo(r, today, day);
  if (n <= 0) return 'Race day';
  return n === 1 ? 'Tomorrow' : n + ' days to go';
}
export const countdownShort = (r, today, day) => countdownText(r, today, day).replace(/ to go$/, '');
/** "Sat 15 May 2027", "Thu 10 – Sun 13 Dec 2026". */
export function dateText(r, day) {
  const a = day || r.date, b = day || lastDay(r);
  if (a === b) return shortDay(a, true, true);
  const pa = pieces(a);
  return (a.slice(0, 7) === b.slice(0, 7) ? pa.wd + ' ' + pa.d : shortDay(a, true)) + ' – ' + shortDay(b, true, true);
}
/** "Saturday 15 May 2027", "Thursday 10 to Sunday 13 December 2026". */
export function longDateText(r, day) {
  const a = day || r.date, b = day || lastDay(r);
  const pa = pieces(a), pb = pieces(b);
  const full = (p) => p.weekday + ' ' + p.d + ' ' + p.month + ' ' + p.y;
  if (a === b) return full(pa);
  return (a.slice(0, 7) === b.slice(0, 7) ? pa.weekday + ' ' + pa.d : pa.weekday + ' ' + pa.d + ' ' + pa.month) + ' to ' + full(pb);
}

// ---------------------------------------------------------------- money, prices, status

/** "2,685". */
export const grouped = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
/** "2,685 SEK". */
export const money = (amount, cur) => grouped(amount) + ' ' + String(cur).toUpperCase();
/** "2,685 SEK", "From 799 SEK", "4,700 NOK per team". */
export const priceText = (s) => (s.lowest ? 'From ' : '') + money(s.amount, s.currency) + (s.per ? ' per ' + s.per : '');
const applies = (s, day) => (!s.from || s.from <= day) && (!s.until || day <= s.until);
const stepKey = (s) => s.from || s.until || '';
export const steps = (r) => (r.priceSteps || []).slice().sort((a, b) => (stepKey(a) < stepKey(b) ? -1 : stepKey(a) > stepKey(b) ? 1 : 0));
export function currentStep(r, today) { const m = steps(r).filter((s) => applies(s, today)); return m[m.length - 1] || null; }
export const nextStep = (r, today) => steps(r).find((s) => (s.from || '') > today) || null;
/** The day the price changes next: the next step's first day, else the day after the current step's last day. */
export function nextPriceChange(r, today) {
  const n = nextStep(r, today);
  if (n && n.from) return n.from;
  const c = currentStep(r, today);
  return c && c.until ? addDay(c.until, 1) : null;
}
/** Days until sign-up opens (0 on the day), for opensSoon races; null otherwise. */
export const daysToSignup = (r, today) => (r.status === 'opensSoon' && r.opensOn ? daysBetween(today, r.opensOn) : null);
/** Sign-up opens today or on a day still ahead. */
export const opensLater = (r, today) => (daysToSignup(r, today) ?? -1) >= 0;
/** "1 Nov" (or "Sun 1 Nov"), "today" on the opening day. */
export const opensText = (r, today, weekday) => (daysToSignup(r, today) === 0 ? 'today' : shortDay(r.opensOn, weekday));
/** The race page's status line; null for races added by hand. */
export function statusText(r, today) {
  if (isCustom(r) || !r.checkedOn) return null;
  switch (r.status) {
    case 'open': return 'Sign-up open';
    case 'opensSoon':
      if (!r.opensOn) return 'Sign-up opens soon';
      return opensLater(r, today) ? 'Sign-up opens ' + opensText(r, today, true) : 'Sign-up was due to open on ' + shortDay(r.opensOn) + ' · check the site';
    case 'soldOut': return 'Sold out';
    case 'lottery': return 'Places by lottery';
    default: return "Check the race's page for sign-up";
  }
}
/** The list pill: the current price ("2,685 SEK until 5 Nov"), else the status ("Sold out", "Opens 1 Nov"). */
export function pillText(r, today) {
  if (isCustom(r)) return '';
  if (isPast(r, today)) return 'Done';
  switch (r.status) {
    case 'soldOut': return 'Sold out';
    case 'lottery': return 'Lottery';
    case 'checkSite': return 'Check site';
    case 'opensSoon': return opensLater(r, today) ? 'Opens ' + opensText(r, today) : 'Check site';
    default: {
      const s = currentStep(r, today);
      return s ? priceText(s) + (s.until ? ' until ' + shortDay(s.until) : '') : 'Sign-up open';
    }
  }
}

// ---------------------------------------------------------------- formats, start waves

/** Ways to enter, when the race prices or sizes them apart (HYROX singles, doubles, relay). */
export const hasFormats = (r) => !!(r.formats && r.formats.length);
/** A format by its code; null for an unknown code (a format the catalog dropped). */
export const formatOf = (r, code) => (code && (r.formats || []).find((f) => f.code === code)) || null;
/** The fees of a format: its own steps, else the race's. */
export const stepsFor = (r, f) => (f && f.priceSteps ? steps({ priceSteps: f.priceSteps }) : steps(r));
/** Today's fee for a format (the race's when the format has none of its own). */
export function currentStepFor(r, f, today) { const m = stepsFor(r, f).filter((s) => applies(s, today)); return m[m.length - 1] || null; }
/** "2 people · Open or Pro", "15 km"; null without details. */
export function formatDetail(f) {
  return [f.distanceKm ? num(f.distanceKm, 1) + ' km' : null, f.teamSize > 1 ? f.teamSize + ' people' : null, f.note].filter(Boolean).join(' · ') || null;
}
/** "Be there by 12:50" needs the start wave; HYROX wants 90 minutes, others an hour by default. */
export const arriveMinutes = (r) => (Number.isInteger(r.arriveMinutesBefore) && r.arriveMinutesBefore > 0 ? r.arriveMinutesBefore : 60);

/** "14:20" (also "14.20", "1420", "9:05") as minutes after midnight; null when it isn't a time of day. */
export function clockMinutes(s) {
  const t = String(s || '').trim();
  if (!t) return null;
  const digits = t.replace(/\D/g, '');
  if (digits.length !== t.replace(/[:. ]/g, '').length || digits.length < 3 || digits.length > 4) return null;
  const h = +digits.slice(0, -2), m = +digits.slice(-2);
  return h <= 23 && m <= 59 ? h * 60 + m : null;
}
/** "09:05". */
export const clockText = (minutes) => { const m = ((minutes % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
/** The typed time, tidied ("1420" → "14:20"); null when it isn't one. */
export const clockNormalized = (s) => { const m = clockMinutes(s); return m == null ? null : clockText(m); };
/** "12:50": the start wave less the minutes the organiser wants you there before it. */
export function arriveBy(wave, minutesBefore) { const w = clockMinutes(wave); return w == null ? null : clockText(Math.max(0, w - minutesBefore)); }

// ---------------------------------------------------------------- the register link, results, feeds, training clubs

/** The sign-up link as the Register button opens it: the race's page, with the affiliate code (`affiliate: {param, code}`)
 *  when the catalog has one. None is set yet; nothing is tracked. */
export function registerURL(r) {
  const a = r.affiliate;
  if (!a || !a.param || !a.code || !host(r.signupUrl)) return r.signupUrl;
  try { const u = new URL(r.signupUrl); u.searchParams.set(a.param, a.code); return u.href; } catch (e) { return r.signupUrl; }
}
/** "1:08:52", "38:10". */
export function timeText(s) {
  const t = Math.max(0, s | 0), two = (n) => String(n).padStart(2, '0');
  return t >= 3600 ? Math.floor(t / 3600) + ':' + two(Math.floor(t / 60) % 60) + ':' + two(t % 60) : Math.floor(t / 60) + ':' + two(t % 60);
}
/** "1:08:52", "68:52", "38:10", "1h 08m", "1.08.52" as seconds; null when it isn't a time. */
export function parseSeconds(text) {
  const t = String(text || '').trim().toLowerCase();
  if (!t) return null;
  if (/[hms]/.test(t)) {
    if (!/^(\d+\s*h\s*)?(\d+\s*m\s*)?(\d+\s*s?\s*)?$/.test(t)) return null;
    const h = /(\d+)\s*h/.exec(t), m = /(\d+)\s*m/.exec(t), s = /(\d+)\s*s?\s*$/.exec(t.replace(/\d+\s*[hm]/g, '').trim() ? t : '');
    const rest = t.replace(/\d+\s*h/, '').replace(/\d+\s*m/, '').replace(/s/, '').trim();
    return (h ? +h[1] * 3600 : 0) + (m ? +m[1] * 60 : 0) + (rest ? +rest : 0);
  }
  const p = t.split(/[:.]/);
  if (p.length < 2 || p.length > 3 || p.some((x) => !/^\d+$/.test(x)) || p.slice(1).some((x) => +x > 59)) return null;
  return p.length === 3 ? +p[0] * 3600 + +p[1] * 60 + +p[2] : +p[0] * 60 + +p[1];
}
/** "Place 212 of 1,040"; null without a place. */
export const placeText = (res) => (res && res.place ? 'Place ' + grouped(res.place) + (res.field ? ' of ' + grouped(res.field) : '') : null);
/** "1:08:52 · Place 212 of 1,040", or "Did not finish". */
export const resultSummary = (res) => (res.dnf ? 'Did not finish' : [timeText(res.seconds), placeText(res)].filter(Boolean).join(' · '));
/** The split rows an organiser's result sheet has: HYROX's stations and the runs; nothing for the rest. */
export const splitTemplate = (type) => (type === 'hyrox' ? ['8 × 1 km runs', 'SkiErg', 'Sled push', 'Sled pull', 'Burpee broad jumps', 'Row', 'Farmers carry', 'Sandbag lunges', 'Wall balls'] : []);
/** The catalog with an organiser feed laid over it (GET /races on our server): a feed race replaces the catalog's when
 *  its facts are as new or newer (checkedOn); one the catalog doesn't have is added. Never shorter than the catalog. */
export function mergeFeed(catalog, feed) {
  const out = catalog.slice();
  for (const r of feed || []) {
    const i = out.findIndex((x) => x.id === r.id);
    if (i < 0) out.push(r); else if ((r.checkedOn || '') >= (out[i].checkedOn || '')) out[i] = r;
  }
  return sorted(out);
}
/** The catalog's training clubs: studios with an organiser's training status ({studioId, name, badge, raceType}). */
export function decodeClubs(json) {
  return (json && Array.isArray(json.trainingClubs) ? json.trainingClubs : []).filter((c) => c && Number.isInteger(c.studioId) && typeof c.name === 'string' && c.name
    && typeof c.badge === 'string' && c.badge && (c.raceType == null || TYPES.some((t) => t.key === c.raceType)));
}
/** The clubs for a race's type (a club without a type counts for all), by name. */
export const clubsFor = (clubs, r) => (clubs || []).filter((c) => !c.raceType || c.raceType === r.type).sort((a, b) => a.name.localeCompare(b.name));

// ---------------------------------------------------------------- labels

export function host(url) {
  try {
    const u = new URL(url);
    if (!/^https?:$/.test(u.protocol)) return null;
    return u.hostname.toLowerCase().replace(/^www\./, '');
  } catch (e) { return null; }
}
export const glyph = (r) => (r.sport && SPORTS[r.sport] ? SPORTS[r.sport].glyph : type(r).glyph);
/** "HYROX · Solna", "Ski · Klassiker". */
export const kindLabel = (r) => [(r.sport && SPORTS[r.sport] ? SPORTS[r.sport].title : type(r).short), r.klassiker ? 'Klassiker' : r.city].filter(Boolean).join(' · ');
export const heroTag = (r) => (r.sport && SPORTS[r.sport] ? SPORTS[r.sport].title : type(r).title);
/** "Strawberry Arena | Solna", the city alone, or the venue alone when it names the city ("Sälen to Mora"). */
export const placeLine = (r) => (r.venue && r.city && r.venue.toLowerCase().includes(r.city.toLowerCase()) ? r.venue : [r.venue, r.city].filter(Boolean).join(' | '));
const num = (v, decimals) => (Number.isInteger(v) ? String(v) : v.toFixed(decimals).replace(/\.?0+$/, ''));
/** "8 km", "42.195 km", "42.2 / 21.1 / 5 km"; null without distances. */
export function distanceText(r) {
  const d = r.distancesKm || [];
  if (!d.length) return null;
  return d.map((v) => num(v, d.length > 1 ? 1 : 3)).join(' / ') + ' km';
}
export const factsLine = (r) => [distanceText(r), r.format].filter(Boolean).join(' · ') || null;
export function checkedText(r, today) {
  if (!r.checkedOn) return null;
  return 'checked ' + shortDay(r.checkedOn, false, r.checkedOn.slice(0, 4) !== today.slice(0, 4));
}
/** "Sign-up on RaceID · checked 21 Oct". */
export function signupLine(r, today) {
  if (isCustom(r)) return null;
  const where = r.platform || host(r.signupUrl);
  if (!where) return null;
  return ['Sign-up on ' + where, checkedText(r, today)].filter(Boolean).join(' · ');
}

// ---------------------------------------------------------------- lists

export const sorted = (races) => races.slice().sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.name.localeCompare(b.name)));
/** Races under month headers: [{key: "2026-12", title: "December 2026", races}]. */
export function byMonth(races) {
  const out = [];
  for (const r of sorted(races)) {
    const key = r.date.slice(0, 7);
    let g = out[out.length - 1];
    if (!g || g.key !== key) { const p = pieces(key + '-01'); g = { key, title: p.month + ' ' + p.y, races: [] }; out.push(g); }
    g.races.push(r);
  }
  return out;
}
const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
export function matches(r, query) {
  // An endurance race is found by its sport ("ski"), not by the "Ski, bike, swim" chip title.
  const hay = [r.name, r.city, r.venue, countryName(r.country), r.sport && SPORTS[r.sport] ? SPORTS[r.sport].title : type(r).title,
    distanceText(r), r.format, r.klassiker ? 'Klassiker' : null].filter(Boolean).map(fold);
  return fold(query).split(/\s+/).filter(Boolean).every((w) => hay.some((h) => h.includes(w)));
}
/** Explore › Races: by type and country (empty = all), a search text, upcoming only unless `includePast`. */
export function filterRaces(races, o) {
  const f = o || {};
  const types = f.types || [], countries = f.countries || [], q = (f.query || '').trim();
  return sorted(races.filter((r) => (!types.length || types.includes(r.type)) && (!countries.length || countries.includes(r.country))
    && (f.includePast || !isPast(r, f.today)) && (!q || matches(r, q))));
}
/** Home's "Upcoming races": the next catalog races by date that aren't in My races, open or opening (sold-out and
 *  lottery races stay in Explore), at most `limit`. Races in `country` first when given. */
export function upcomingOnHome(races, mine, today, country, limit) {
  const have = new Set((mine || []).map((m) => m.raceId).filter(Boolean));
  const list = sorted(races).filter((r) => !isPast(r, today) && !have.has(r.id) && (r.status === 'open' || r.status === 'opensSoon'));
  const n = limit || 8;
  if (!country || !list.some((r) => r.country === country)) return list.slice(0, n);
  return list.filter((r) => r.country === country).concat(list.filter((r) => r.country !== country)).slice(0, n);
}
/** The carousel pill: the next price step ("750 → 775 SEK on 1 Nov"), else the list pill. */
export function homePill(r, today) {
  const c = currentStep(r, today), n = nextStep(r, today);
  if (r.status === 'open' && c && n && n.from && c.currency === n.currency) return grouped(c.amount) + ' → ' + grouped(n.amount) + ' ' + n.currency.toUpperCase() + ' on ' + shortDay(n.from);
  return pillText(r, today);
}

// ---------------------------------------------------------------- the catalog file

/** The readable races of a catalog file, by date; an entry with an unknown type or status or a bad date is left out
 *  (as RaceCatalog.decode does), so a newer catalog never breaks an older page. */
export function decode(json) {
  const list = (json && Array.isArray(json.races)) ? json.races : [];
  const day = (d) => d == null || isDay(d);
  const stepsOK = (r) => r.priceSteps == null || (Array.isArray(r.priceSteps) && r.priceSteps.every((s) => s && Number.isFinite(s.amount)
    && typeof s.currency === 'string' && day(s.from) && day(s.until)));
  // Formats this version can't read are dropped one by one, not the race.
  const formatsOf = (r) => {
    const list = Array.isArray(r.formats) ? r.formats.filter((f) => f && typeof f.code === 'string' && f.code && typeof f.title === 'string' && f.title && stepsOK(f)) : [];
    return list.length ? list : undefined;
  };
  return sorted(list.filter((r) => r && typeof r.id === 'string' && typeof r.name === 'string' && TYPES.some((t) => t.key === r.type)
    && STATUSES.includes(r.status) && isDay(r.date) && day(r.endDate) && (r.endDate || r.date) >= r.date && day(r.opensOn)
    && (!r.checkedOn || isDay(r.checkedOn)) && stepsOK(r) && host(r.signupUrl))
    .map((r) => Object.assign({ distancesKm: [], city: '', country: '', checkedOn: '' }, r, { distancesKm: Array.isArray(r.distancesKm) ? r.distancesKm.filter((x) => typeof x === 'number' && x > 0) : [],
      formats: formatsOf(r), arriveMinutesBefore: Number.isInteger(r.arriveMinutesBefore) && r.arriveMinutesBefore > 0 ? r.arriveMinutesBefore : undefined })));
}

/** Everything wrong with a catalog file, as readable lines (empty when it is valid). The schema is in README.md. */
export function validate(json) {
  const errors = [];
  const err = (r, msg) => errors.push((r && r.id ? r.id : '?') + ': ' + msg);
  if (!json || typeof json !== 'object') return ['not a JSON object'];
  if (json.version !== 1) errors.push('version must be 1');
  if (!isDay(json.checkedOn)) errors.push('top-level checkedOn must be YYYY-MM-DD');
  if (!Array.isArray(json.races) || !json.races.length) return errors.concat('races must be a non-empty array');
  const ids = new Set();
  const https = (u) => { try { return new URL(u).protocol === 'https:'; } catch (e) { return false; } };
  const known = ['id', 'name', 'type', 'sport', 'date', 'endDate', 'city', 'country', 'venue', 'distancesKm', 'format', 'signupUrl', 'platform',
    'priceNote', 'priceSteps', 'status', 'opensOn', 'klassiker', 'resultsUrl', 'checkedOn', 'formats', 'changeRule', 'startInfo', 'arriveMinutesBefore', 'affiliate'];
  if (json.trainingClubs != null) {
    if (!Array.isArray(json.trainingClubs)) errors.push('trainingClubs must be an array');
    else json.trainingClubs.forEach((c, i) => {
      const at = 'trainingClubs[' + i + '] ';
      if (!c || typeof c !== 'object') { errors.push(at + 'is not an object'); return; }
      Object.keys(c).filter((k) => !['studioId', 'name', 'badge', 'raceType'].includes(k)).forEach((k) => errors.push(at + 'unknown field ' + k));
      if (!Number.isInteger(c.studioId) || c.studioId <= 0) errors.push(at + 'studioId must be a Bruce studio id');
      ['name', 'badge'].forEach((k) => { if (typeof c[k] !== 'string' || !c[k].trim()) errors.push(at + k + ' missing'); });
      if (c.raceType != null && !TYPES.some((t) => t.key === c.raceType)) errors.push(at + 'raceType must be a race type');
    });
  }
  const checkSteps = (r, list, at0) => {
    list.forEach((s, i) => {
      const at = at0 + '[' + i + '] ';
      if (!Number.isInteger(s.amount) || s.amount <= 0) err(r, at + 'amount must be a positive whole number');
      if (!CURRENCIES.includes(s.currency)) err(r, at + 'currency must be one of ' + CURRENCIES.join(', '));
      if (s.from != null && !isDay(s.from)) err(r, at + 'from must be YYYY-MM-DD');
      if (s.until != null && !isDay(s.until)) err(r, at + 'until must be YYYY-MM-DD');
      if (s.from && s.until && s.until < s.from) err(r, at + 'until is before from');
      if (s.lowest != null && typeof s.lowest !== 'boolean') err(r, at + 'lowest must be true or false');
      Object.keys(s).filter((k) => !['from', 'until', 'amount', 'currency', 'lowest', 'per'].includes(k)).forEach((k) => err(r, at + 'unknown field ' + k));
    });
    // Dated steps must not share a day (an open end runs to the start or end of time).
    const dated = list.filter((s) => s.from || s.until);
    const overlap = dated.some((a, i) => dated.slice(i + 1).some((b) => (a.from || '') <= (b.until || '9999') && (b.from || '') <= (a.until || '9999')));
    if (overlap) err(r, at0 + ': price steps overlap');
  };
  let prev = '';
  for (const r of json.races) {
    if (!r || typeof r !== 'object') { errors.push('a race is not an object'); continue; }
    Object.keys(r).filter((k) => !known.includes(k)).forEach((k) => err(r, 'unknown field ' + k));
    if (typeof r.id !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id)) err(r, 'id must be lower-case words joined by "-"');
    else if (r.id.startsWith(CUSTOM)) err(r, 'id must not start with "' + CUSTOM + '"');
    if (ids.has(r.id)) err(r, 'duplicate id'); ids.add(r.id);
    if (typeof r.name !== 'string' || !r.name.trim()) err(r, 'name missing');
    if (!TYPES.some((t) => t.key === r.type)) err(r, 'type must be one of ' + TYPES.map((t) => t.key).join(', '));
    if (r.sport != null && (r.type !== 'endurance' || !SPORTS[r.sport])) err(r, 'sport (ski, bike, swim) only for endurance races');
    if (r.type === 'endurance' && !SPORTS[r.sport]) err(r, 'endurance races need a sport');
    if (!isDay(r.date)) err(r, 'date must be a real YYYY-MM-DD');
    if (r.endDate != null && (!isDay(r.endDate) || r.endDate < r.date)) err(r, 'endDate must be a YYYY-MM-DD on or after date');
    if (isDay(r.date) && r.date < prev) err(r, 'races must be sorted by date');
    if (isDay(r.date)) prev = r.date;
    if (typeof r.city !== 'string' || !r.city.trim()) err(r, 'city missing');
    if (!COUNTRIES.some((c) => c[0] === r.country)) err(r, 'country must be SE, NO or DK');
    if (!Array.isArray(r.distancesKm) || r.distancesKm.some((d) => typeof d !== 'number' || !(d > 0))) err(r, 'distancesKm must be an array of positive numbers');
    if (!https(r.signupUrl)) err(r, 'signupUrl must be an https URL');
    if (r.resultsUrl != null && !https(r.resultsUrl)) err(r, 'resultsUrl must be an https URL');
    if (!STATUSES.includes(r.status)) err(r, 'status must be one of ' + STATUSES.join(', '));
    if (r.status === 'opensSoon' && !isDay(r.opensOn)) err(r, 'opensSoon needs opensOn');
    if (r.opensOn != null && (!isDay(r.opensOn) || r.opensOn > r.date)) err(r, 'opensOn must be a YYYY-MM-DD before the race');
    if (r.klassiker != null && typeof r.klassiker !== 'boolean') err(r, 'klassiker must be true or false');
    ['venue', 'format', 'platform', 'priceNote'].forEach((k) => { if (r[k] != null && (typeof r[k] !== 'string' || !r[k].trim())) err(r, k + ' must be a non-empty string'); });
    if (!isDay(r.checkedOn)) err(r, 'checkedOn must be YYYY-MM-DD');
    if (r.priceSteps != null) {
      if (!Array.isArray(r.priceSteps) || !r.priceSteps.length) err(r, 'priceSteps must be a non-empty array when present');
      else checkSteps(r, r.priceSteps, 'priceSteps');
    }
    ['changeRule', 'startInfo'].forEach((k) => { if (r[k] != null && (typeof r[k] !== 'string' || !r[k].trim())) err(r, k + ' must be a non-empty string'); });
    if (r.arriveMinutesBefore != null && (!Number.isInteger(r.arriveMinutesBefore) || r.arriveMinutesBefore <= 0 || r.arriveMinutesBefore > 360)) err(r, 'arriveMinutesBefore must be whole minutes, up to 360');
    if (r.affiliate != null && (typeof r.affiliate !== 'object' || !/^[A-Za-z0-9_-]{1,40}$/.test(r.affiliate.param || '') || !/^[A-Za-z0-9_-]{1,60}$/.test(r.affiliate.code || '')
      || Object.keys(r.affiliate).some((k) => !['param', 'code'].includes(k)))) err(r, 'affiliate must be {param, code} (letters, digits, - and _)');
    if (r.formats != null) {
      if (!Array.isArray(r.formats) || !r.formats.length) err(r, 'formats must be a non-empty array when present');
      else {
        const codes = new Set();
        r.formats.forEach((f, i) => {
          const at = 'formats[' + i + '] ';
          if (!f || typeof f !== 'object') { err(r, at + 'is not an object'); return; }
          Object.keys(f).filter((k) => !['code', 'title', 'distanceKm', 'teamSize', 'priceSteps', 'note'].includes(k)).forEach((k) => err(r, at + 'unknown field ' + k));
          if (typeof f.code !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(f.code)) err(r, at + 'code must be lower-case words joined by "-"');
          if (codes.has(f.code)) err(r, at + 'duplicate code'); codes.add(f.code);
          if (typeof f.title !== 'string' || !f.title.trim()) err(r, at + 'title missing');
          if (f.distanceKm != null && (typeof f.distanceKm !== 'number' || !(f.distanceKm > 0))) err(r, at + 'distanceKm must be a positive number');
          if (f.teamSize != null && (!Number.isInteger(f.teamSize) || f.teamSize < 1)) err(r, at + 'teamSize must be a whole number from 1');
          if (f.note != null && (typeof f.note !== 'string' || !f.note.trim())) err(r, at + 'note must be a non-empty string');
          if (f.priceSteps != null) {
            if (!Array.isArray(f.priceSteps) || !f.priceSteps.length) err(r, at + 'priceSteps must be a non-empty array when present');
            else checkSteps(r, f.priceSteps, at + 'priceSteps');
          }
        });
      }
    }
  }
  return errors;
}

// ---------------------------------------------------------------- My races (localStorage, see store.js)

/** The key a race page and its link use: the catalog id, or "custom-<id>" for a race added by hand. */
export const keyOf = (m) => m.raceId || CUSTOM + m.id;
/** The catalog race (fresh facts) when the catalog has it, else a race built from what was saved. */
export function resolve(m, catalog) {
  const r = m.raceId && (catalog || []).find((x) => x.id === m.raceId);
  if (r) return r;
  return { id: keyOf(m), name: m.name, type: m.type || 'running', sport: m.sport || undefined, date: m.date, endDate: m.endDate || undefined, city: m.city || '',
    country: '', distancesKm: [], signupUrl: m.url || '', status: 'checkSite', checkedOn: '' };
}
export function fromRace(r) {
  return { id: newId(), raceId: r.id, name: r.name, date: r.date, endDate: r.endDate || null, city: r.city, url: r.signupUrl, type: r.type, sport: r.sport || null, addedAt: new Date().toISOString() };
}
export const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
export const entries = (mine, catalog) => (mine || []).map((m) => ({ mine: m, race: resolve(m, catalog), day: m.day || resolve(m, catalog).date }));
export const upcoming = (list, today) => list.filter((e) => !isPast(e.race, today, e.mine.day)).sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
export const past = (list, today) => list.filter((e) => isPast(e.race, today, e.mine.day)).sort((a, b) => (a.day > b.day ? -1 : 1));
/** "Doubles · Open" (the catalog format and the note), "10 km" (the note alone), null without either. */
export function startText(e) {
  const f = formatOf(e.race, e.mine.format);
  return [f && f.title, e.mine.note].filter(Boolean).join(' · ') || null;
}
/** "Sat 12 Dec · Doubles · Open". */
export const whenLine = (e) => [shortDay(e.day, true), startText(e)].filter(Boolean).join(' · ');
/** "12:50": when the organiser wants the member there (their wave less the race's arrival minutes); null without a wave. */
export const entryArriveBy = (e) => arriveBy(e.mine.wave, arriveMinutes(e.race));
/** Race day is today (the member's day of the event). */
export const isRaceDay = (e, today) => daysToGo(e.race, today, e.mine.day) === 0;
/** My classes' race-day card (mockup 5): today's race, else tomorrow's from 18:00 the evening before; null otherwise.
 *  `hour` is the local hour now. */
export function raceDayTicket(entries, today, hour) {
  const t = entries.find((e) => daysToGo(e.race, today, e.mine.day) === 0);
  if (t) return { entry: t, tomorrow: false, title: 'Race day · today' };
  const n = (hour ?? 0) >= 18 && entries.find((e) => daysToGo(e.race, today, e.mine.day) === 1);
  return n ? { entry: n, tomorrow: true, title: 'Race day · tomorrow' } : null;
}
/** "Strawberry Arena, Solna" in Apple Maps, when the race names a place. */
export function mapsURL(r) {
  const q = [r.venue, r.city].filter(Boolean).join(', ');
  return q ? 'https://maps.apple.com/?q=' + encodeURIComponent(q) : null;
}
/** "Price goes up tomorrow", 09:00 the day before the next price step: the day it changes and the words (the same as
 *  the apps' notification; the server sends them while it is on). Null when no step is ahead. */
export function priceReminder(r, today) {
  if (isCustom(r) || r.status !== 'open' || isPast(r, today)) return null;
  const changeOn = nextPriceChange(r, today);
  if (!changeOn) return null;
  const site = host(r.signupUrl) || "the race's page";
  const current = currentStep(r, today), next = steps(r).find((s) => s.from === changeOn);
  const body = current && next ? r.name + ': ' + priceText(current) + ' until today, ' + priceText(next) + ' from tomorrow. Sign up on ' + site + '.'
    : current ? r.name + ': today is the last day for ' + priceText(current) + '. Sign up on ' + site + '.'
    : r.name + ': the entry fee changes tomorrow. Check ' + site + '.';
  return { changeOn, remindOn: addDay(changeOn, -1), title: 'Price goes up tomorrow', body };
}
/** What happens next for a race in My races: "Sign-up opens 1 Nov", "775 SEK from 1 Nov", "Sold out". */
export function hint(e, today) {
  const r = e.race;
  if (isCustom(r) || isPast(r, today, e.mine.day)) return null;
  if (opensLater(r, today)) return 'Sign-up opens ' + opensText(r, today);
  if (r.status === 'open') {
    const n = nextStep(r, today);
    if (n && n.from) return priceText(n) + ' from ' + shortDay(n.from);
    const c = currentStep(r, today);
    if (c && c.until) return priceText(c) + ' until ' + shortDay(c.until);
  }
  return r.status === 'soldOut' ? 'Sold out' : r.status === 'lottery' ? 'Places by lottery' : null;
}
/** A link typed for a race added by hand: "toughviking.se" -> "https://toughviking.se"; null without a host. */
export function webURL(s) {
  const t = String(s || '').trim();
  if (!t || /\s/.test(t)) return null;
  try {
    const u = new URL(/^https?:\/\//i.test(t) ? t : 'https://' + t);
    if (!/^https?:$/.test(u.protocol) || !/\./.test(u.hostname) || /^\.|\.$/.test(u.hostname)) return null;
    return u.href;
  } catch (e) { return null; }
}
