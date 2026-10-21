// Races on the web (races.js; RaceViews.swift on iPhone): Explore › Races, the race page, My classes › Races, Home's
// "Next race" and the editor for a race added by hand. Race names are plain text on the app's own colours, sign-up
// always opens the race's own page, and every race page says Brüce is not affiliated with the organiser.
import { $, esc, icon, todayKey } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import * as R from './races.js';
import { glassBtn, empty, loading, toast, sheet, chip } from './ui.js';
import { addToCalendar, icsForRace, icsFileName } from './calendar.js';

export const NOT_AFFILIATED = "Brüce is not affiliated with this race or its organiser. Sign-up, prices and rules are theirs: check the race's own page before you sign up.";
const CATALOG_NOTE = "Races are picked by hand from each race's own page, with the day they were checked. Brüce links to those pages and is not affiliated with any race or organiser.";
const DEVICE_NOTE = 'My races stay in this browser. Reminders for sign-up and price steps are in the Brüce iPhone app.';
const CUSTOM_NOTE = 'You added this race. It stays in this browser; Brüce has no facts or prices for it.';
const GONE_NOTE = "This race is no longer in Brüce's list. The details are the ones you saved.";

/** Explore › Races chips (for this visit). */
export const rf = { types: [], countries: [], past: false };

// ---------------------------------------------------------------- My races (store.js keeps them in localStorage)

export const myEntries = () => R.entries(St.myRaces(), S.races || []);
export const mineFor = (key) => St.myRaces().find((m) => R.keyOf(m) === key) || null;
export function raceById(id) {
  const r = (S.races || []).find((x) => x.id === id);
  if (r) return r;
  const m = mineFor(id);
  return m ? R.resolve(m, S.races || []) : null;
}
export function addRace(r) {
  if (mineFor(r.id)) return;
  St.saveMyRaces(St.myRaces().concat(R.fromRace(r)));
  toast('Added to My races');
}
export function removeRace(key) {
  const list = St.myRaces();
  const i = list.findIndex((m) => R.keyOf(m) === key);
  if (i < 0) return;
  St.saveMyRaces(list.filter((_, j) => j !== i));
  toast('Removed from My races');
}
function updateMine(key, change) {
  St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === key ? Object.assign({}, m, change) : m)));
}

// ---------------------------------------------------------------- building blocks

/** Race-bib date: month, day, and the last day (multi-day events) or the weekday. */
function bib(r, day) {
  const d = day || r.date;
  const multi = !day && R.isMultiDay(r);
  const p = R.shortDay(d, true).split(' ');   // ["Sat", "15", "May"]
  return '<span class="bib" aria-hidden="true"><small>' + esc(p[2].toUpperCase()) + '</small><b>' + esc(p[1]) + '</b><small>' +
    esc(multi ? '–' + (+R.lastDay(r).slice(8)) : p[0].toUpperCase()) + '</small></span>';
}

/** Explore › Races card. */
export function raceCard(r, href, o) {
  const opt = o || {};
  const today = todayKey();
  const sub = [r.venue || r.format, R.distanceText(r), R.countdownShort(r, today)].filter(Boolean).join(' · ');
  const pill = R.pillText(r, today);
  return '<a class="rcard t-' + esc(r.type) + (opt.selected ? ' selected' : '') + '" href="' + href + '" aria-label="' + esc([r.name, R.dateText(r), R.kindLabel(r), sub, pill].filter(Boolean).join(', ')) + '">' +
    bib(r) + '<span class="rcard-body"><small>' + esc(R.kindLabel(r).toUpperCase()) + '</small><b>' + esc(r.name) + '</b>' +
    (sub ? '<span>' + esc(sub) + '</span>' : '') + (pill ? '<em>' + esc(pill) + '</em>' : '') + '</span>' +
    (opt.mine ? '<span class="rcard-mine" title="In My races">' + icon('check') + '</span>' : '') +
    icon(R.glyph(r), 'rcard-glyph') + '</a>';
}

/** Chips: All, the types, the countries and past races. */
export function raceChipsHTML() {
  return chip('All', !rf.types.length, 'data-rtype=""') +
    R.TYPES.map((t) => chip('<i class="tdot t-' + t.key + '"></i>' + esc(t.title), rf.types.includes(t.key), 'data-rtype="' + t.key + '"')).join('') +
    R.COUNTRIES.map(([c, n]) => chip(esc(n), rf.countries.includes(c), 'data-rcountry="' + c + '"')).join('') +
    chip('Past', rf.past, 'data-rpast');
}
/** Handles a chip click; true when it was one. */
export function raceChipsClick(e) {
  const t = e.target.closest('[data-rtype]');
  if (t) { const k = t.dataset.rtype; rf.types = !k ? [] : rf.types.includes(k) ? rf.types.filter((x) => x !== k) : rf.types.concat(k); return true; }
  const c = e.target.closest('[data-rcountry]');
  if (c) { const k = c.dataset.rcountry; rf.countries = rf.countries.includes(k) ? rf.countries.filter((x) => x !== k) : rf.countries.concat(k); return true; }
  if (e.target.closest('[data-rpast]')) { rf.past = !rf.past; return true; }
  return false;
}
export const filteredRaces = (query) => R.filterRaces(S.races || [], { types: rf.types, countries: rf.countries, includePast: rf.past, query, today: todayKey() });

/** Explore › Races: cards under month headers. */
export function racesListHTML(query, hrefOf, selectedId) {
  if (!S.races) return loading('Loading races…');
  if (!S.races.length) return empty('info', S.racesError || 'No races.');
  const list = filteredRaces(query);
  if (!list.length) return empty('flag', 'No races match. Brüce lists about 30 races in Sweden, Norway and Denmark.');
  const mine = new Set(St.myRaces().map(R.keyOf));
  return R.byMonth(list).map((g) => '<h3 class="section-head">' + esc(g.title) + '</h3><div class="rcards">' +
    g.races.map((r) => raceCard(r, hrefOf(r.id), { mine: mine.has(r.id), selected: selectedId === r.id })).join('') + '</div>').join('') +
    '<p class="muted small note">' + esc(CATALOG_NOTE) + '</p>';
}

/** Home: the next race in My races, above Spotlight. */
export function nextRaceHTML(hrefOf) {
  const today = todayKey();
  const e = R.upcoming(myEntries(), today)[0];
  if (!e) return '';
  const r = e.race, n = R.daysToGo(r, today, e.mine.day);
  const h = R.hint(e, today);
  return '<div class="sec-row"><h2 class="sec-title">Next race</h2><a class="btn glass sm" href="#/mine?tab=races">My races</a></div>' +
    '<a class="race-next t-' + esc(r.type) + '" href="' + hrefOf(r.id) + '"><span class="race-count"><b>' + (n <= 0 ? 'RACE' : n) + '</b><small>' + (n === 1 || n <= 0 ? 'DAY' : 'DAYS') + '</small></span>' +
    '<span class="race-next-body"><b>' + esc(r.name) + '</b><span>' + esc(R.whenLine(e)) + '</span>' + (R.placeLine(r) ? '<span>' + esc(R.placeLine(r).replace(' | ', ', ')) + '</span>' : '') + '</span>' +
    (h ? '<em>' + icon('info') + esc(h) + '</em>' : '') + icon(R.glyph(r), 'rcard-glyph') + '</a>';
}

/** My classes › Races: the next race big, then later and past races. */
export function myRacesHTML(hrefOf, selectedId) {
  const today = todayKey();
  const all = myEntries();
  const up = R.upcoming(all, today), done = R.past(all, today);
  if (!all.length) {
    return empty('flag', 'No races yet. Pick one in Explore › Races, or add your own.') +
      '<div class="row2"><a class="btn lime" href="#/explore?tab=races">Find a race</a><button class="btn glass" data-addrace>Add your own</button></div>';
  }
  const row = (e) => {
    const h = R.hint(e, today);
    const right = R.isPast(e.race, today, e.mine.day) ? 'Done' : R.daysToGo(e.race, today, e.mine.day) <= 0 ? 'Today' : R.daysToGo(e.race, today, e.mine.day) + ' d';
    return '<a class="trow race-row' + (selectedId === e.race.id ? ' selected' : '') + '" href="' + hrefOf(e.race.id) + '">' + bib(e.race, e.mine.day) +
      '<span class="grow"><b>' + esc(e.race.name) + '</b><p class="muted">' + esc(h || [e.race.venue || e.race.city, R.distanceText(e.race)].filter(Boolean).join(' · ')) + '</p></span>' +
      '<b class="muted">' + esc(right) + '</b></a>';
  };
  let html = '';
  const next = up[0];
  if (next) {
    const r = next.race, h = R.hint(next, today);
    html += '<a class="race-banner t-' + esc(r.type) + (selectedId === r.id ? ' selected' : '') + '" href="' + hrefOf(r.id) + '">' +
      '<span class="race-banner-top"><em>' + esc([R.heroTag(r), next.mine.note].filter(Boolean).join(' · ')) + '</em><b>' + esc(R.countdownShort(r, today, next.mine.day)) + '</b></span>' +
      '<b class="race-banner-name">' + esc(r.name) + '</b><span>' + esc([R.shortDay(next.day, true), r.venue || r.city].filter(Boolean).join(' · ')) + '</span>' +
      (h ? '<small>' + icon('info') + esc(h) + '</small>' : '') + icon(R.glyph(r), 'rcard-glyph') + '</a>';
  }
  if (up.length > 1) html += '<div class="sec-row"><h2 class="sec-title">Later</h2><small class="muted">' + (up.length - 1) + (up.length - 1 === 1 ? ' race' : ' races') + '</small></div><div class="list card flush">' + up.slice(1).map(row).join('') + '</div>';
  if (done.length) html += '<div class="sec-row"><h2 class="sec-title">Done</h2><small class="muted">' + done.length + (done.length === 1 ? ' race' : ' races') + '</small></div><div class="list card flush">' + done.map(row).join('') + '</div>';
  return html + '<p class="muted small note">' + esc(DEVICE_NOTE) + '</p>';
}

// ---------------------------------------------------------------- race page

export function renderRace(el, id, ctx) {
  const draw = () => {
    const r = raceById(id);
    const back = glassBtn(ctx.wide ? 'close' : 'back', 'data-ract="back"', ctx.wide ? 'Close' : 'Back');
    if (!r) { el.innerHTML = '<div class="pane-pad">' + back + (S.races ? empty('flag', GONE_NOTE) : loading('Loading race…')) + '</div>'; return; }
    const today = todayKey();
    const mine = mineFor(id);
    const day = mine && mine.day;
    const custom = R.isCustom(r);
    const facts = [];
    const fl = R.factsLine(r);
    if (fl) facts.push(['flag', fl]);
    facts.push(['clock', R.countdownText(r, today, day)]);
    const su = R.signupLine(r, today);
    if (su) facts.push(['ticket', su]);
    if (r.status !== 'open' && !custom && r.checkedOn && !R.opensLater(r, today)) facts.push(['info', R.statusText(r, today)]);
    if (r.klassiker) facts.push(['trophy', 'A leg of En Svensk Klassiker']);
    const h = R.host(r.signupUrl);
    const openLabel = !custom && (r.status === 'open' || r.status === 'opensSoon') ? 'Sign up on ' + h : 'Open ' + h;

    el.innerHTML = '<header class="hero race-hero t-' + esc(r.type) + '">' + icon(R.glyph(r), 'race-hero-glyph') +
      '<div class="hero-bar">' + back + '<span class="spacer"></span>' + (h ? glassBtn('share', 'data-ract="share"', 'Share the race page') : '') + '</div>' +
      '<div class="hero-text"><span class="hero-tag">' + esc(R.heroTag(r)) + '</span><h1>' + esc(r.name) + '</h1>' + (R.placeLine(r) ? '<p>' + esc(R.placeLine(r)) + '</p>' : '') + '</div></header>' +
      '<div class="pane-pad"><h2 class="date-line">' + esc(R.longDateText(r, day)) + '</h2>' +
      '<div class="facts race-facts">' + facts.map(([ic, t]) => '<span>' + icon(ic) + esc(t) + '</span>').join('') + '</div>' +
      (h ? '<a class="btn glass race-link" href="' + esc(r.signupUrl) + '" target="_blank" rel="noopener noreferrer">' + esc(openLabel) + icon('external') + '</a>' : '') +
      (!custom && r.checkedOn ? feeCard(r, today) : '') +
      (R.opensLater(r, today) ? '<div class="card notice-card">' + icon('calendar') + '<p><b>' + esc(R.statusText(r, today)) + '</b><br><span class="muted small">Places can go fast. The Brüce iPhone app can remind you that morning.</span></p></div>' : '') +
      (mine ? yourRace(r, mine) : '') +
      '<p class="muted small note">' + (custom ? esc(CUSTOM_NOTE) : !r.checkedOn ? esc(GONE_NOTE)
        : "Facts as shown on the race's own page on " + esc(R.shortDay(r.checkedOn, false, true)) + '. They change; the link is always one tap away.') +
        '<br>' + esc(NOT_AFFILIATED) + '</p>' +
      '<div class="actions sticky">' + (mine ? '<button class="btn lime" data-ract="ics">' + icon('calendar') + ' Add to Calendar</button>'
        : '<button class="btn lime" data-ract="add">' + icon('plus') + ' Add to My races</button>') + '</div></div>';
  };

  function feeCard(r, today) {
    const st = R.steps(r), cur = R.currentStep(r, today);
    const head = cur ? R.priceText(cur) + (st.length > 1 ? ' now' : '') : r.status === 'soldOut' ? 'Sold out' : 'On the race page';
    const amounts = st.map((s) => s.amount), lo = Math.min(...amounts), hi = Math.max(...amounts);
    const label = (s) => (s.from ? 'from ' + R.shortDay(s.from) : s.until ? 'until ' + R.shortDay(s.until) : 'now');
    const next = R.nextStep(r, today);
    const nextLine = r.status === 'open' && !R.isPast(r, today) ? (next && next.from ? R.priceText(next) + ' from ' + R.shortDay(next.from)
      : cur && cur.until ? R.priceText(cur) + ' until ' + R.shortDay(cur.until) : null) : null;
    return '<div class="card race-fees"><div class="row-between"><span class="muted">Entry fee</span><b>' + esc(head) + '</b></div>' +
      (st.length > 1 ? '<div class="ladder" role="img" aria-label="' + esc(st.map((s) => R.priceText(s) + ' ' + label(s)).join(', ')) + '">' + st.map((s) =>
        '<div class="' + (s === cur ? 'on' : '') + '"><b>' + esc(R.grouped(s.amount)) + '</b><i style="height:' + Math.round(22 + 34 * (s.amount - lo) / Math.max(hi - lo, 1)) + 'px"></i><small>' + esc(label(s)) + '</small></div>').join('') + '</div>' : '') +
      (r.priceNote ? '<p class="muted small">' + esc(r.priceNote) + '</p>' : '') +
      (nextLine ? '<p class="small race-next-step">' + icon('bell') + esc(nextLine) + '</p>' : '') + '</div>';
  }

  function yourRace(r, mine) {
    const ds = R.days(r);
    return '<div class="card form-rows race-mine"><h3 class="section-head">Your race</h3>' +
      (R.isMultiDay(r) ? '<label class="frow"><span class="grow">Your day</span><select data-rday><option value="">Every day</option>' +
        ds.map((d) => '<option value="' + d + '"' + (mine.day === d ? ' selected' : '') + '>' + esc(R.shortDay(d, true)) + '</option>').join('') + '</select></label>' : '') +
      '<label class="frow"><span class="grow">Your start</span><input type="text" data-rnote maxlength="60" placeholder="Doubles Open, 10 km…" value="' + esc(mine.note || '') + '"></label>' +
      '<div class="frow">' + (R.isCustom(r) ? '<button class="btn glass sm" data-ract="edit">' + icon('pencil') + ' Edit</button>' : '') +
      '<span class="spacer"></span><button class="btn glass sm red-text" data-ract="remove">Remove from My races</button></div></div>';
  }

  el.onclick = (e) => {
    const b = e.target.closest('[data-ract]');
    if (!b) return;
    const r = raceById(id);
    const a = b.dataset.ract;
    if (a === 'back') { ctx.close(); return; }
    if (!r) return;
    if (a === 'add') { addRace(r); draw(); }
    else if (a === 'remove') { removeRace(id); if (R.isCustom(r)) ctx.close(); else draw(); }
    else if (a === 'edit') openRaceEditor(mineFor(id), (removed) => (removed ? ctx.close() : draw()));
    else if (a === 'share') {
      const url = r.signupUrl;
      if (navigator.share) navigator.share({ title: r.name, url }).catch(() => {});
      else navigator.clipboard.writeText(url).then(() => toast('Link copied'), () => {});
    } else if (a === 'ics') {
      const mine = mineFor(id);
      addToCalendar(icsForRace(r, { day: mine && mine.day, facts: R.factsLine(r), url: R.host(r.signupUrl) ? r.signupUrl : null }),
        icsFileName(r.name, (mine && mine.day) || r.date));
      toast('Event file ready. It doesn\'t follow changes on the race page.');
    }
  };
  el.onchange = (e) => {
    if (e.target.matches('[data-rday]')) { updateMine(id, { day: e.target.value || null }); draw(); }
    else if (e.target.matches('[data-rnote]')) updateMine(id, { note: e.target.value.trim() || null });
  };
  draw();
  St.loadRaces().then(() => { if (el.isConnected && !el.contains(document.activeElement)) draw(); });
}

// ---------------------------------------------------------------- add or edit a race by hand

export function openRaceEditor(existing, after) {
  const m = Object.assign({ id: R.newId(), raceId: null, name: '', date: '', city: '', url: '', type: 'running', note: '' }, existing || {});
  const s = sheet(existing ? 'Edit race' : 'Add a race', '<form class="form" id="race-form">' +
    (existing ? '' : '<a class="btn glass" href="#/explore?tab=races">' + icon('flag') + ' Pick one from Explore › Races</a>') +
    '<label><span>Name</span><input type="text" name="name" required maxlength="80" value="' + esc(m.name) + '"></label>' +
    '<label><span>Date</span><input type="date" name="date" required value="' + esc(m.date) + '"></label>' +
    '<label><span>Type</span><select name="type">' + R.TYPES.map((t) => '<option value="' + t.key + '"' + (m.type === t.key ? ' selected' : '') + '>' + esc(t.title) + '</option>').join('') + '</select></label>' +
    '<label><span>City</span><input type="text" name="city" maxlength="60" value="' + esc(m.city || '') + '"></label>' +
    '<label><span>Link to the race page (optional)</span><input type="text" inputmode="url" autocapitalize="off" spellcheck="false" name="url" placeholder="toughviking.se" value="' + esc(m.url || '') + '"></label>' +
    '<label><span>Your start (optional)</span><input type="text" name="note" maxlength="60" placeholder="10 km, Doubles Open…" value="' + esc(m.note || '') + '"></label>' +
    '<p class="error small" id="race-error" role="alert"></p>' +
    '<button class="btn lime" type="submit">' + (existing ? 'Save' : 'Add to My races') + '</button>' +
    (existing ? '<button class="btn glass red-text" type="button" data-del>Remove from My races</button>' : '') +
    '<p class="muted small">' + esc(CUSTOM_NOTE) + '</p></form>', { cls: 'tall' });
  const f = $('#race-form', s.body);
  f.addEventListener('submit', (e) => {
    e.preventDefault();
    const v = (k) => f.elements[k].value.trim();   // f.name is the form's own name, so read the fields by name
    const name = v('name'), date = v('date'), link = v('url');
    const url = link ? R.webURL(link) : null;
    if (!name || !R.isDay(date)) { $('#race-error', s.body).textContent = 'Add a name and a date.'; return; }
    if (link && !url) { $('#race-error', s.body).textContent = "That link doesn't look like a web address."; return; }
    const next = Object.assign({}, m, { name, date, type: v('type'), city: v('city') || null, url, note: v('note') || null });
    const list = St.myRaces();
    St.saveMyRaces(existing ? list.map((x) => (x.id === m.id ? next : x)) : list.concat(Object.assign(next, { addedAt: new Date().toISOString() })));
    s.close();
    toast(existing ? 'Race saved' : 'Added to My races');
    if (after) after(false);
  });
  const del = s.body.querySelector('[data-del]');
  if (del) del.addEventListener('click', () => { removeRace(R.keyOf(m)); s.close(); if (after) after(true); });
  const pick = s.body.querySelector('a[href^="#/explore"]');
  if (pick) pick.addEventListener('click', () => s.close());
}
