// Races on the web (races.js; RaceViews.swift on iPhone): Explore › Races, the race page, My classes › Races, Home's
// "Next race" and the editor for a race added by hand. Race names are plain text on the app's own colours, sign-up
// always opens the race's own page, and every race page says Brüce is not affiliated with the organiser.
import { $, esc, icon, todayKey, ls } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import * as R from './races.js';
import { glassBtn, empty, loading, toast, sheet, chip, avatar, confirmSheet } from './ui.js';
import { addToCalendar, icsForRace, icsFileName } from './calendar.js';
import { bannerPlanHTML, promptHTML, weekSectionHTML, homePlan, raceCardHTML, planClick, planOf, refreshPlanGoals } from './raceplanui.js';
import { goingText, goingNames, resultsUrl, recovery } from './crews.js';
import { crewBlockHTML, crewClick, loadIfAllowed as loadChallengesIfAllowed } from './challenges.js';

export const NOT_AFFILIATED = "Brüce is not affiliated with this race or its organiser. Sign-up, prices and rules are theirs: check the race's own page before you sign up.";
const CATALOG_NOTE = "Races are picked by hand from each race's own page, with the day they were checked. Brüce links to those pages and is not affiliated with any race or organiser.";
const DEVICE_NOTE = 'My races stay in this browser. Reminders for sign-up and price steps are in the Brüce iPhone app; race-week reminders come from our server while it is on.';
const CUSTOM_NOTE = 'You added this race. It stays in this browser; Brüce has no facts or prices for it.';
const GONE_NOTE = "This race is no longer in Brüce's list. The details are the ones you saved.";
const GOING_HINT = "Your Bruce friends who share their races in Brüce see that you're going, and you see theirs. Off by default, per race.";
const GOING_SERVER = 'Going is shared through our server, which is off in Settings.';
const GOING_SHARE = 'Friends who share their races show up here once you share one too.';
const GOING_CONSENT = "Our server stores your Bruce user id, this race and that your Bruce friends may see it. Only friends who share a race themselves see it, nobody else. It's deleted when you switch this off, remove the race, after race day, or with your data on the server.";
const RECOVERY_HINT = 'An easy week after the race, from the Train for it mix. Brüce books nothing for you.';

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
  // Monthly goals made from its Train for it plan go with it.
  if (St.goals().some((g) => g.raceKey === key)) St.saveGoals(St.goals().filter((g) => g.raceKey !== key));
  toast('Removed from My races');
}
function updateMine(key, change) {
  St.saveMyRaces(St.myRaces().map((m) => (R.keyOf(m) === key ? Object.assign({}, m, change) : m)));
}
/** "Show friends I'm going" (opt-in per race, catalog races only): adds the race to My races if needed; says once what
 *  the server keeps. Returns whether it changed. */
export async function setGoing(r, on) {
  if (R.isCustom(r)) return false;
  if (on && !St.canShareGoing()) { toast(GOING_SERVER); return false; }
  if (on && !St.isDemo() && !ls.get('bruce.goingConsent', false)) {
    if (!(await confirmSheet("Show friends you're going?", GOING_CONSENT, 'Show friends', 'lime'))) return false;
    ls.set('bruce.goingConsent', true);
  }
  // The moment it was flipped goes with it: the last flip wins on every device.
  if (!mineFor(r.id)) St.saveMyRaces(St.myRaces().concat(Object.assign(R.fromRace(r), { going: on, goingAt: Date.now() })));
  else updateMine(r.id, { going: on, goingAt: Date.now() });
  toast(on ? "Friends can see you're going" : 'Not shared any more');
  return true;
}

/** Faces and "2 friends going". */
export function goingHTML(users, size) {
  if (!users.length) return '';
  return '<span class="going" role="img" aria-label="' + esc(goingNames(users.map((u) => u.first_name))) + '"><span class="going-faces">' +
    users.slice(0, 3).map((u) => avatar(u, size || 24)).join('') + (users.length > 3 ? '<span class="going-more">+' + (users.length - 3) + '</span>' : '') +
    '</span><span>' + esc(goingText(users.length)) + '</span></span>';
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
    (sub ? '<span>' + esc(sub) + '</span>' : '') + (pill || (opt.going && opt.going.length) ? '<span class="rcard-row">' + (pill ? '<em>' + esc(pill) + '</em>' : '') +
      goingHTML(opt.going || [], 22) + '</span>' : '') + '</span>' +
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
    g.races.map((r) => raceCard(r, hrefOf(r.id), { mine: mine.has(r.id), selected: selectedId === r.id, going: St.friendsGoing(r.id) })).join('') + '</div>').join('') +
    '<p class="muted small note">' + esc(CATALOG_NOTE) + '</p>';
}

/** Home: the next race in My races, above Spotlight. */
export function nextRaceHTML(hrefOf) {
  const today = todayKey();
  const e = R.upcoming(myEntries(), today)[0];
  if (!e) return '';
  const r = e.race, n = R.daysToGo(r, today, e.mine.day);
  const h = R.hint(e, today);
  const plan = homePlan(e);   // Train for it: the week line, and the next class to book under the card
  return '<div class="sec-row"><h2 class="sec-title">Next race</h2><a class="btn glass sm" href="#/mine?tab=races">My races</a></div>' +
    '<a class="race-next t-' + esc(r.type) + '" href="' + hrefOf(r.id) + '"><span class="race-count"><b>' + (n <= 0 ? 'RACE' : n) + '</b><small>' + (n === 1 || n <= 0 ? 'DAY' : 'DAYS') + '</small></span>' +
    '<span class="race-next-body"><b>' + esc(r.name) + '</b><span>' + esc(R.whenLine(e)) + '</span>' + (R.placeLine(r) ? '<span>' + esc(R.placeLine(r).replace(' | ', ', ')) + '</span>' : '') + '</span>' +
    (plan ? plan.line : h ? '<em>' + icon('info') + esc(h) + '</em>' : '') + icon(R.glyph(r), 'rcard-glyph') + '</a>' + (plan ? plan.after : '');
}
export { planClick, refreshPlanGoals };

/** Home, above Spotlight (mockup 1): the next catalog races as a carousel, with the next price step and friends going. */
export function upcomingRacesHTML(hrefOf) {
  const today = todayKey();
  const list = R.upcomingOnHome(S.races || [], St.myRaces(), today, St.homeCountry());
  if (!list.length) return '';
  return '<div class="sec-row"><h2 class="sec-title">UPCOMING RACES</h2><a class="btn glass sm" href="#/explore?tab=races">Show all</a></div><div class="hscroll race-mini-row">' +
    list.map((r) => {
      const pill = R.homePill(r, today), going = St.friendsGoing(r.id);
      return '<a class="race-mini t-' + esc(r.type) + '" href="' + hrefOf(r.id) + '" aria-label="' + esc([r.name, R.dateText(r), r.city, pill].filter(Boolean).join(', ')) + '">' +
        '<span class="race-mini-top">' + bib(r) + icon(R.glyph(r), 'race-mini-glyph') + '</span><b>' + esc(r.name) + '</b>' +
        '<span>' + esc([R.shortDay(r.date, true), r.city].filter(Boolean).join(' · ')) + '</span>' +
        (pill ? '<em>' + esc(pill) + '</em>' : '') + goingHTML(going, 20) + '</a>';
    }).join('') + '</div>';
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
    const past = R.isPast(e.race, today, e.mine.day), results = past && resultsUrl(e.race);
    const right = past ? (results ? '' : 'Done') : R.daysToGo(e.race, today, e.mine.day) <= 0 ? 'Today' : R.daysToGo(e.race, today, e.mine.day) + ' d';
    const going = past ? [] : St.friendsGoing(e.race.id);
    return '<div class="race-row-wrap"><a class="trow race-row' + (selectedId === e.race.id ? ' selected' : '') + '" href="' + hrefOf(e.race.id) + '">' + bib(e.race, e.mine.day) +
      '<span class="grow"><b>' + esc(e.race.name) + '</b><p class="muted">' + esc(h || [e.race.venue || e.race.city, R.distanceText(e.race)].filter(Boolean).join(' · ')) + '</p>' +
      goingHTML(going, 20) + '</span>' + (right ? '<b class="muted">' + esc(right) + '</b>' : '') + '</a>' +
      (results ? '<a class="btn glass sm race-results" href="' + esc(results) + '" target="_blank" rel="noopener noreferrer">See results</a>' : '') + '</div>';
  };
  let html = '';
  const jr = done.map((e) => ({ e, rec: recovery(e, today) })).find((x) => x.rec && !planOf(x.e));
  if (jr) html += afterHTML(jr.e.race, jr.rec, 'After ' + jr.e.race.name);
  const next = up[0];
  if (next) {
    const r = next.race, h = R.hint(next, today);
    html += '<a class="race-banner t-' + esc(r.type) + (selectedId === r.id ? ' selected' : '') + '" href="' + hrefOf(r.id) + '">' +
      '<span class="race-banner-top"><em>' + esc([R.heroTag(r), R.startText(next)].filter(Boolean).join(' · ')) + '</em><b>' + esc(R.countdownShort(r, today, next.mine.day)) + '</b></span>' +
      '<b class="race-banner-name">' + esc(r.name) + '</b><span>' + esc([R.shortDay(next.day, true), r.venue || r.city].filter(Boolean).join(' · ')) + '</span>' +
      (planOf(next) ? bannerPlanHTML(next) : h ? '<small>' + icon('info') + esc(h) + '</small>' : '') + goingHTML(St.friendsGoing(r.id), 22) + icon(R.glyph(r), 'rcard-glyph') + '</a>';
    if (!planOf(next) && R.daysToGo(r, today, next.mine.day) > 0) html += promptHTML(R.keyOf(next.mine));
  }
  html += weekSectionHTML();
  if (up.length > 1) html += '<div class="sec-row"><h2 class="sec-title">Later</h2><small class="muted">' + (up.length - 1) + (up.length - 1 === 1 ? ' race' : ' races') + '</small></div><div class="list card flush">' + up.slice(1).map(row).join('') + '</div>';
  if (done.length) html += '<div class="sec-row"><h2 class="sec-title">Past</h2><small class="muted">' + done.length + (done.length === 1 ? ' race' : ' races') + '</small></div><div class="list card flush">' + done.map(row).join('') + '</div>';
  return html + '<p class="muted small note">' + esc(DEVICE_NOTE) + '</p>';
}

/** After the race: results on the race's own site and the recovery week's mix with Find buttons. */
function afterHTML(r, rec, title) {
  const results = resultsUrl(r);
  return '<div class="card race-after"><p class="race-after-title">' + icon('flag') + '<b>' + esc(title || (results ? "The race is over. Results are on the race's own site." : 'The race is over.')) + '</b></p>' +
    (results ? '<a class="btn lime" href="' + esc(results) + '" target="_blank" rel="noopener noreferrer">See results on ' + esc(R.host(results)) + icon('external') + '</a>' : '') +
    (rec ? '<p><b>Recovery week: ' + esc(rec.text) + '</b><br><span class="muted small">' + esc(RECOVERY_HINT) + '</span></p><div class="row2">' +
      rec.mix.map((x) => '<button class="btn glass sm" data-plan-find="' + esc(x.key) + '">Find ' + esc(x.title) + '</button>').join('') + '</div>' : '') + '</div>';
}

/** Race page: "Show friends I'm going" and the crew (challenges.js). */
function friendsCardHTML(r, mine) {
  const on = !!(mine && mine.going), can = St.canShareGoing();
  return '<div class="card form-rows race-friends"><h3 class="section-head">With friends</h3>' +
    '<label class="toggle"><span>Show friends I\'m going<small class="muted">' + esc(can ? GOING_HINT : GOING_SERVER) + '</small></span><input type="checkbox" data-rgoing' +
      (on ? ' checked' : '') + (!can && !on ? ' disabled' : '') + '><i></i></label>' +
    (can && !S.raceGoing.sharing && !St.friendsGoing(r.id).length ? '<p class="muted small">' + esc(GOING_SHARE) + '</p>' : '') +
    crewBlockHTML(r) + '</div>';
}

// ---------------------------------------------------------------- race page

export function renderRace(el, id, ctx) {
  let formatPick = null;   // the format looked at before the race is in My races (then it is saved with the race)
  const shownFormat = (r) => R.formatOf(r, (mineFor(id) || {}).format || formatPick) || (r.formats || [])[0] || null;
  const draw = () => {
    const r = raceById(id);
    const back = glassBtn(ctx.wide ? 'close' : 'back', 'data-ract="back"', ctx.wide ? 'Close' : 'Back');
    if (!r) { el.innerHTML = '<div class="pane-pad">' + back + (S.races ? empty('flag', GONE_NOTE) : loading('Loading race…')) + '</div>'; return; }
    const today = todayKey();
    const mine = mineFor(id);
    const day = mine && mine.day;
    const custom = R.isCustom(r);
    const past = R.isPast(r, today, day);
    const facts = [];
    const fl = R.factsLine(r);
    if (fl) facts.push(['flag', fl]);
    facts.push(['clock', R.countdownText(r, today, day)]);
    const su = !past && R.signupLine(r, today);
    if (su) facts.push(['ticket', su]);
    if (!past && r.startInfo) facts.push(['clock', r.startInfo]);
    if (!past && r.status !== 'open' && !custom && r.checkedOn && !R.opensLater(r, today)) facts.push(['info', R.statusText(r, today)]);
    if (r.klassiker) facts.push(['trophy', 'A leg of En Svensk Klassiker']);
    const h = R.host(r.signupUrl);
    const openLabel = !custom && !past && (r.status === 'open' || r.status === 'opensSoon') ? 'Sign up on ' + h : 'Open ' + h;
    const entry = mine && myEntries().find((x) => R.keyOf(x.mine) === id);

    el.innerHTML = '<header class="hero race-hero t-' + esc(r.type) + '">' + icon(R.glyph(r), 'race-hero-glyph') +
      '<div class="hero-bar">' + back + '<span class="spacer"></span>' + (h ? glassBtn('share', 'data-ract="share"', 'Share the race page') : '') + '</div>' +
      '<div class="hero-text"><span class="hero-tag">' + esc(R.heroTag(r)) + '</span><h1>' + esc(r.name) + '</h1>' + (R.placeLine(r) ? '<p>' + esc(R.placeLine(r)) + '</p>' : '') + '</div></header>' +
      '<div class="pane-pad"><h2 class="date-line">' + esc(R.longDateText(r, day)) + '</h2>' +
      '<div class="facts race-facts">' + facts.map(([ic, t]) => '<span>' + icon(ic) + esc(t) + '</span>').join('') + '</div>' +
      (past ? afterHTML(r, entry && !planOf(entry) ? recovery(entry, today) : null) : goingHTML(St.friendsGoing(r.id), 30)) +
      (h ? '<a class="btn glass race-link" href="' + esc(r.signupUrl) + '" target="_blank" rel="noopener noreferrer">' + esc(openLabel) + icon('external') + '</a>' : '') +
      (!past && !custom && r.checkedOn ? feeCard(r, today) : '') +
      (!past && R.opensLater(r, today) ? '<div class="card notice-card">' + icon('calendar') + '<p><b>' + esc(R.statusText(r, today)) + '</b><br><span class="muted small">Places can go fast. The Brüce iPhone app can remind you that morning.</span></p></div>' : '') +
      (mine && mine.plan ? raceCardHTML(id) : '') +
      (!past && !custom ? friendsCardHTML(r, mine) : '') +
      (mine ? yourRace(r, mine) : '') +
      '<p class="muted small note">' + (custom ? esc(CUSTOM_NOTE) : !r.checkedOn ? esc(GONE_NOTE)
        : "Facts as shown on the race's own page on " + esc(R.shortDay(r.checkedOn, false, true)) + '. They change; the link is always one tap away.') +
        '<br>' + esc(NOT_AFFILIATED) + '</p>' +
      '<div class="actions sticky">' + (R.isPast(r, today, day) ? (mine ? '' : '<button class="btn lime" data-ract="add">' + icon('plus') + ' Add to My races</button>')
        : '<button class="btn lime" data-plan-open="' + esc(id) + '">' + icon('run') + (mine && mine.plan ? ' Your plan' : ' Train for it') + '</button>' +
          (mine ? '<button class="btn glass" data-ract="ics">' + icon('calendar') + ' Add to Calendar</button>' : '<button class="btn glass" data-ract="add">' + icon('plus') + ' Add to My races</button>')) + '</div></div>';
  };

  function feeCard(r, today) {
    // Mockup 2: the ways to enter first; the fee follows the one picked.
    const f = shownFormat(r);
    const st = R.stepsFor(r, f), cur = R.currentStepFor(r, f, today);
    const head = cur ? R.priceText(cur) + (st.length > 1 ? ' now' : '') : r.status === 'soldOut' ? 'Sold out' : 'On the race page';
    const amounts = st.map((s) => s.amount), lo = Math.min(...amounts), hi = Math.max(...amounts);
    const label = (s) => (s.from ? 'from ' + R.shortDay(s.from) : s.until ? 'until ' + R.shortDay(s.until) : 'now');
    const next = R.nextStep(r, today);
    const nextLine = r.status === 'open' && !R.isPast(r, today) ? (next && next.from ? R.priceText(next) + ' from ' + R.shortDay(next.from)
      : R.currentStep(r, today) && R.currentStep(r, today).until ? R.priceText(R.currentStep(r, today)) + ' until ' + R.shortDay(R.currentStep(r, today).until) : null) : null;
    const detail = f && R.formatDetail(f);
    return '<div class="card race-fees">' +
      (R.hasFormats(r) ? '<div class="chips race-formats" role="group" aria-label="Format">' + r.formats.map((x) =>
        '<button class="chip' + (f && x.code === f.code ? ' on' : '') + '" data-rfmt="' + esc(x.code) + '" aria-pressed="' + (f && x.code === f.code) + '">' + esc(x.title) + '</button>').join('') + '</div>' +
        (detail ? '<p class="muted small">' + esc(detail) + '</p>' : '') : '') +
      '<div class="row-between"><span class="muted">' + esc(f ? 'Entry fee · ' + f.title : 'Entry fee') + '</span><b>' + esc(head) + '</b></div>' +
      (st.length > 1 ? '<div class="ladder" role="img" aria-label="' + esc(st.map((s) => R.priceText(s) + ' ' + label(s)).join(', ')) + '">' + st.map((s) =>
        '<div class="' + (s === cur ? 'on' : '') + '"><b>' + esc(R.grouped(s.amount)) + '</b><i style="height:' + Math.round(22 + 34 * (s.amount - lo) / Math.max(hi - lo, 1)) + 'px"></i><small>' + esc(label(s)) + '</small></div>').join('') + '</div>' : '') +
      (r.priceNote ? '<p class="muted small">' + esc(r.priceNote) + '</p>' : '') +
      (r.changeRule ? '<p class="small race-rule">' + icon('info') + esc(r.changeRule) + '</p>' : '') +
      (nextLine ? '<p class="small race-next-step">' + icon('bell') + esc(nextLine) + '</p>' : '') + '</div>';
  }

  function yourRace(r, mine) {
    const ds = R.days(r);
    const past = R.isPast(r, todayKey(), mine.day);
    const e = myEntries().find((x) => R.keyOf(x.mine) === id);
    const by = e && R.entryArriveBy(e);
    return '<div class="card form-rows race-mine"><h3 class="section-head">Your race</h3>' +
      (R.isMultiDay(r) ? '<label class="frow"><span class="grow">Your day</span><select data-rday><option value="">Every day</option>' +
        ds.map((d) => '<option value="' + d + '"' + (mine.day === d ? ' selected' : '') + '>' + esc(R.shortDay(d, true)) + '</option>').join('') + '</select></label>' : '') +
      (R.hasFormats(r) ? '<label class="frow"><span class="grow">Format</span><select data-rformat><option value="">Not picked</option>' +
        r.formats.map((f) => '<option value="' + esc(f.code) + '"' + (mine.format === f.code ? ' selected' : '') + '>' + esc(f.title) + '</option>').join('') + '</select></label>' : '') +
      '<label class="frow"><span class="grow">' + (R.hasFormats(r) ? 'Division' : 'Your start') + '</span><input type="text" data-rnote maxlength="60" placeholder="' + (R.hasFormats(r) ? 'Open, Pro…' : 'Doubles Open, 10 km…') + '" value="' + esc(mine.note || '') + '"></label>' +
      // Mockup 3: the start wave and bib come from the organiser later and are added by hand.
      '<label class="frow"><span class="grow">Start wave</span><input type="text" data-rwave maxlength="8" inputmode="numeric" placeholder="14:20" value="' + esc(mine.wave || '') + '"></label>' +
      '<label class="frow"><span class="grow">Bib</span><input type="text" data-rbib maxlength="12" inputmode="numeric" placeholder="1427" value="' + esc(mine.bib || '') + '"></label>' +
      (by ? '<p class="muted small">Be there by ' + esc(by) + ' (' + R.arriveMinutes(r) + ' minutes before your start).</p>'
        : past ? '' : '<p class="muted small">The start wave and bib come from the organiser; add them here when they arrive. The Brüce iPhone app can remind you three days before.</p>') +
      (past ? '' : '<label class="toggle"><span>Race week: Monday 08:00</span><input type="checkbox" data-rremind="remindWeek"' + (mine.remindWeek ? ' checked' : '') + '><i></i></label>' +
        '<label class="toggle"><span>The day before: 18:00<small class="muted">' + esc(St.serverOn() ? 'Our server sends a push to the Brüce iPhone app and an email.' : 'Needs our server, which is off in Settings.') + '</small></span><input type="checkbox" data-rremind="remindEve"' + (mine.remindEve ? ' checked' : '') + '><i></i></label>') +
      '<div class="frow">' + (R.isCustom(r) ? '<button class="btn glass sm" data-ract="edit">' + icon('pencil') + ' Edit</button>' : '') +
      '<span class="spacer"></span><button class="btn glass sm red-text" data-ract="remove">Remove from My races</button></div></div>';
  }

  el.onclick = (e) => {
    if (planClick(e)) return;
    if (crewClick(e, draw)) return;
    const fb = e.target.closest('[data-rfmt]');
    if (fb) {
      const r = raceById(id);
      if (r && mineFor(id)) updateMine(id, { format: fb.dataset.rfmt }); else formatPick = fb.dataset.rfmt;
      draw();
      return;
    }
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
    else if (e.target.matches('[data-rformat]')) { updateMine(id, { format: e.target.value || null }); draw(); }
    else if (e.target.matches('[data-rnote]')) updateMine(id, { note: e.target.value.trim() || null });
    else if (e.target.matches('[data-rwave]')) { updateMine(id, { wave: R.clockNormalized(e.target.value) || e.target.value.trim() || null }); draw(); }
    else if (e.target.matches('[data-rbib]')) updateMine(id, { bib: e.target.value.trim() || null });
    else if (e.target.matches('[data-rremind]')) updateMine(id, { [e.target.dataset.rremind]: e.target.checked });
    else if (e.target.matches('[data-rgoing]')) {
      const r = raceById(id), want = e.target.checked;
      if (r) setGoing(r, want).then((changed) => { if (!changed) e.target.checked = !want; draw(); });
    }
  };
  draw();
  // With a plan, the week's check-ins too (the Train for it card counts them).
  loadChallengesIfAllowed();
  Promise.all([St.loadRaces(), St.loadGoing(), S.challengesLoading, mineFor(id) && mineFor(id).plan ? St.loadHistory().catch(() => []) : null])
    .then(() => { if (el.isConnected && !el.contains(document.activeElement)) draw(); });
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
