// Brüce Wrapped: the year to date as full-screen story cards (Spotify Wrapped style). Tap right or left (or swipe) to
// step, hold to pause, swipe down, X or Escape to close; cards advance on their own every ~6 s. The numbers come from
// wrapped-stats.js (this year's GET /booking history, computed on the device), the "Top N%" card from our server's
// GET /wrapped/percentiles (hidden when the server is off or the cohort is too small). The last card is the share
// card; its image is drawn by hand on a 1080x1920 <canvas> and handed to the Web Share API, or downloaded.
import { Bruce, Server } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { esc, icon, todayKey } from './util.js';
import { wrappedStats, together, cardsFor, topPercent, percentileMetrics, dayRange, shareStats, racesOfYear } from './wrapped-stats.js';
import * as R from './races.js';

const DURATION = 6000;          // ms per card
const HOLD = 260;               // a press longer than this pauses instead of stepping
const CONFETTI = { intro: ['#ff3d8b', '#dafc55', '#b18cff', '#fff', '#ffd400', '#3ae0ff'], streak: ['#fff', '#ff9ec7', '#ffd400'], top: ['#ff3d8b', '#fff', '#000', '#6a00ff'], share: ['#3ae0ff', '#dafc55', '#b18cff', '#fff', '#ffd400', '#ff3d8b'] };
const reduced = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
const plural = (n, one, many) => n + ' ' + (n === 1 ? one : (many || one + 's'));

// ---------------------------------------------------------------- data

async function load() {
  const year = new Date().getFullYear();
  const today = todayKey();
  const [, friendBookings, friends, user] = await Promise.all([
    St.loadHistory(),
    Bruce.friendsBookingsSince(year + '0101').catch(() => []),
    S.friends.length ? S.friends : Bruce.friends().catch(() => []),
    S.user || Bruce.user().catch(() => null),
  ]);
  const visits = St.visitList(false);
  const stats = wrappedStats(visits, { year, today, catTitle: St.catTitle, together: together(visits, friendBookings) });
  // The race chapter (races.js): this year's races in My races that are over, with the result when one was typed.
  await St.loadRaces().catch(() => {});
  stats.races = racesOfYear(R, R.entries(St.myRaces(), S.races || []), today);
  let pct = null, cohort = null;
  if (St.serverOn() && stats.total > 0) {
    const r = await Server.percentiles(year, percentileMetrics(stats)).catch(() => null);
    if (r && r.percentiles) { pct = r.percentiles; cohort = r.cohort; }
  }
  let studio = null;
  if (stats.favStudio) {
    const s = St.studio(stats.favStudio.id);
    studio = s ? s.name : await St.loadStudio(stats.favStudio.id).then((x) => x && x.name).catch(() => null);
  }
  const fu = stats.friend && (friends.find((f) => f.friend_user && f.friend_user.id === stats.friend.userId) || {}).friend_user;
  return {
    year, stats, pct, cohort, studio: studio || 'Your top studio',
    name: (user && user.first_name) || '', friend: fu ? { name: fu.first_name || 'your friend', initial: (fu.first_name || '?')[0].toUpperCase() } : null,
  };
}

// ---------------------------------------------------------------- cards

const confetti = (key) => (CONFETTI[key] ? ' data-confetti="' + key + '"' : '');
const pop = (d, html, cls, style) => '<div class="pop' + (cls ? ' ' + cls : '') + '" style="--d:' + d + 's' + (style ? ';' + style : '') + '">' + html + '</div>';
const count = (n, cls, style) => '<span class="wbig ' + (cls || '') + '" data-count="' + n + '"' + (style ? ' style="' + style + '"' : '') + '>' + n + '</span>';
const words = (t) => t.toUpperCase().split(/\s+/).map(esc).join('<br>');

function introCard(d) {
  const s = d.stats;
  const head = s.total ? (d.name ? esc(d.name.toUpperCase()) + ',<br>' : '') + 'YOU<br>SHOWED<br>UP.' : 'YOUR<br>YEAR<br>STARTS<br>NOW.';
  return '<div class="blob" style="width:180px;height:180px;background:#ffb800;right:-50px;bottom:12%"></div><div class="blob" style="width:120px;height:120px;background:#3ae0ff;left:-40px;top:34%;animation-delay:-2s"></div>' +
    pop(0.1, 'Your ' + d.year + ' in Brüce', 'wkicker') +
    pop(0.35, head, 'wbig', 'font-size:clamp(44px,14vw,60px);margin-top:22px') +
    pop(0.7, s.total ? 'January 1 to today. Every class, every drop-in, every early alarm. Ready?' : 'No visits yet this year. Book a class and come back: this story writes itself.', 'wcopy', 'margin-top:22px;opacity:.9');
}

function visitsCard(d) {
  const s = d.stats;
  const max = Math.max(1, ...s.months);
  const bars = s.months.map((c, i) => {
    const fut = i > s.monthNow;
    const h = fut ? 30 : Math.max(4, Math.round(96 * c / max));
    const cls = fut ? 'fut' : (s.bestMonth && i === s.bestMonth.index ? 'top' : '');
    return '<div><i style="--j:' + i + ';height:' + h + 'px" class="' + cls + '" title="' + (fut ? '' : c + ' visits') + '"></i>' + 'JFMAMJJASOND'[i] + '</div>';
  }).join('');
  const parts = [plural(s.classes, 'class', 'classes')];
  if (s.dropins) parts.push(plural(s.dropins, 'gym drop-in'));
  const pace = s.every == null ? '' : s.every <= 1 ? ' That is a visit a day.' : ' One visit every ' + String(s.every).replace(/\.0$/, '') + ' days.';
  const b = s.bestMonth;
  const best = b ? '<b class="neon">' + b.name + '</b> ' + (b.index === s.monthNow ? 'is your month so far: ' : 'was your month: ') + plural(b.count, 'visit') + '.' : '';
  return pop(0.05, 'So far this year', 'wkicker', 'color:var(--wr-neon)') +
    '<div style="margin-top:10px">' + count(s.total, 'neon glow', 'font-size:clamp(84px,28vw,120px)') + '</div>' +
    pop(0.2, s.total === 1 ? 'VISIT' : 'VISITS', 'wbig', 'font-size:34px') +
    pop(0.5, parts.join(' + ') + '.<br>' + plural(s.hours, 'hour') + '.' + pace, 'wcopy', 'margin-top:12px;opacity:.85') +
    '<div class="wr-bars" aria-hidden="true">' + bars + '</div>' +
    pop(1.4, best, 'wcopy', 'font-size:15px;margin-top:12px');
}

const PERSONA_ICON = { lunchBreaker: 'sun', weekendWarrior: 'trophy', zenMaster: 'yoga', ironRegular: 'dumbbell', explorer: 'map', loyalist: 'heart' };
function personaCard(d) {
  const a = d.stats.archetype;
  const art = a.key === 'earlyBird' ? '<div class="sunrise"><div class="rays"></div><div class="sun"></div></div>'
    : a.key === 'nightOwl' ? '<div class="moon"><div class="stars"></div><div class="disc"></div></div>'
      : '<div class="orb">' + icon(PERSONA_ICON[a.key] || 'spark') + '</div>';
  const t = d.stats.topHour;
  return pop(0.05, 'Your class personality', 'wkicker') +
    pop(0.2, art, 'wr-art') +
    pop(0.45, words(a.title), 'wbig', 'font-size:clamp(40px,13vw,52px);margin-top:10px') +
    pop(0.75, esc(a.blurb), 'wcopy', 'margin-top:14px') +
    (t ? pop(1, icon('clock') + ' Top time of day: ' + t.label, 'wr-chip', 'margin-top:16px') : '');
}

function placeCard(d) {
  const s = d.stats;
  const long = d.studio.length > 16;
  return '<div class="blob" style="width:220px;height:220px;background:#3ae0ff;right:-80px;top:120px"></div>' +
    pop(0.05, 'Your second living room', 'wkicker') +
    pop(0.25, esc(d.studio.toUpperCase()), 'wbig wr-studio', 'font-size:' + (long ? 'clamp(28px,9vw,36px)' : 'clamp(34px,11vw,44px)') + ';margin-top:16px') +
    '<div style="display:flex;align-items:baseline;gap:10px;margin-top:14px">' + count(s.favStudio.count, '', 'font-size:84px') + '<span class="wbig" style="font-size:24px">' + (s.favStudio.count === 1 ? 'VISIT' : 'VISITS') + '</span></div>' +
    pop(0.9, (s.topClass ? '<div><b class="wbig">' + s.topClass.count + '×</b><span>' + esc(s.topClass.title) + ', top class</span></div>' : '') +
      '<div><b class="wbig">' + s.studios + '</b><span>' + (s.studios === 1 ? 'studio, all year' : 'studios tried') + '</span></div>', 'wr-tiles');
}

function streakCard(d) {
  const s = d.stats, w = s.streak.weeks, f = s.friend && d.friend;
  const boxes = Array.from({ length: Math.min(w, 8) }, (_, i) => '<i>' + (i === 7 && w > 8 ? '+' + (w - 7) : i + 1) + '</i>').join('');
  const me = (d.name || 'Y')[0].toUpperCase();
  let html = '';
  if (w >= 2) {
    html += pop(0.05, 'Longest streak', 'wkicker', 'text-align:center') +
      pop(0.15, '<svg class="flame" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 22c4 0 7-2.7 7-7 0-4-3-6.5-4-10-2 2-3 4-3 6-1-1-2-2-2.2-3.5C7.5 9.5 5 12 5 15c0 4.3 3 7 7 7z" fill="currentColor"/></svg>') +
      pop(0.35, w + ' WEEKS', 'wbig', 'font-size:clamp(44px,15vw,58px);text-align:center') +
      pop(0.55, boxes, 'weeks') +
      pop(0.6, 'in a row, ' + dayRange(s.streak.from, s.streak.to), '', 'text-align:center;font-size:14px;font-weight:700;opacity:.85');
  } else {
    html += pop(0.05, 'Your training buddy', 'wkicker', 'text-align:center;margin-top:40px');
  }
  if (f) {
    html += pop(1, '<span class="me">' + esc(me) + '</span><span class="f1">' + esc(d.friend.initial) + '</span>', 'duo' + (w >= 2 ? '' : ' big')) +
      pop(1.2, 'You and ' + esc(d.friend.name) + ' did ' + count(s.friend.count, 'inline') + ' ' + (s.friend.count === 1 ? 'class' : 'classes') + ' together.<br><span style="opacity:.8;font-weight:500">Same time next year?</span>', 'wcopy', 'text-align:center;font-weight:700');
  }
  return html;
}

function topCard(d) {
  const p = d.pct;
  const chips = [['minutes', 'Minutes trained'], ['studios', 'Studios tried'], ['streak', 'Longest streak']].filter(([k]) => p[k] != null)
    .map(([k, t], i) => pop(0.8 + i * 0.15, '<span>' + t + '</span><b>Top ' + topPercent(p[k]) + '%</b>')).join('');
  return '<div class="ring2"></div><div class="ring2 b"></div>' +
    pop(0.05, 'You vs. Brüce', 'wkicker') +
    '<div class="wr-top">' + pop(0.15, 'TOP&nbsp;', 'wbig', 'font-size:44px;margin-top:22px') + count(topPercent(p.visits), '', 'font-size:clamp(110px,36vw,140px);line-height:.85') + pop(0.3, '%', 'wbig', 'font-size:60px') + '</div>' +
    pop(0.5, 'of Brüce users by visits this year.', 'wcopy', 'font-weight:700;margin-top:8px') +
    '<div class="pchips">' + chips + '</div>' +
    pop(1.3, 'Anonymous: compared with ' + (d.cohort || 'other') + ' Brüce users, only percentiles leave the server.', '', 'font-size:12px;font-weight:600;opacity:.65;margin-top:12px');
}

/** What the share card shows, on screen and in the image. */
function shareData(d) {
  const s = d.stats;
  return {
    year: d.year, name: (d.name ? d.name + ' · ' : '') + 'so far this year', persona: s.archetype.title,
    tiles: shareStats(s, { studio: d.studio, friend: d.friend && d.friend.name }),
    left: d.pct && d.pct.visits != null ? 'Top ' + topPercent(d.pct.visits) + '% of Brüce users' : s.total ? plural(s.total, 'visit') + ' in ' + d.year : 'Brüce ' + d.year,
    right: s.topHour ? 'Top time ' + s.topHour.label : '',
  };
}
function shareCard(d) {
  const x = shareData(d);
  return '<div class="wr-sharehead"><span class="wbig">WRAPPED</span></div>' +
    '<div class="wr-sharecard"><div class="row-top"><div class="wbig wr-sharetitle">BRÜCE<br>' + x.year + '</div>' + icon('spark', 'spin-spark') + '</div>' +
    '<div class="who">' + esc(x.name) + '</div><div class="persona-tag">' + icon('spark') + ' ' + esc(x.persona) + '</div>' +
    '<div class="wstat">' + x.tiles.map((t, k) => '<div style="--k:' + k + '"><b>' + esc(t.value) + '</b><span>' + esc(t.label) + '</span></div>').join('') + '</div>' +
    '<div class="foot"><span>' + esc(x.left) + '</span><span>' + esc(x.right) + '</span></div></div>' +
    '<div class="wr-actions"><button class="btn lime" data-share>' + icon('share') + ' Share</button><button class="btn wr-ghost" data-save>Save image</button></div>';
}

/** The race chapter: each race of the year with its day and the result the member typed. */
function raceCard(d) {
  const races = d.stats.races || [];
  const one = races.length === 1;
  return pop(0.05, one ? 'Race day' : 'Your races', 'wkicker') +
    pop(0.2, one ? esc(races[0].name.toUpperCase()) : races.length + ' RACES', 'wbig', 'font-size:clamp(32px,10vw,44px);margin-top:16px') +
    (one ? pop(0.4, races[0].timeText ? '<b class="wbig" style="font-size:72px">' + esc(races[0].timeText) + '</b>' : '<span class="wcopy">' + esc(R.shortDay(races[0].day)) + ' · ' + esc(races[0].kind) + '</span>') : '') +
    pop(0.6, races.slice(0, 5).map((r) => '<div><b class="wbig">' + esc(r.timeText || R.shortDay(r.day)) + '</b><span>' + esc(one ? (r.placeText || r.kind) : r.name + (r.placeText ? ' · ' + r.placeText : '')) + '</span></div>').join('') +
      (races.length > 5 ? '<div><b class="wbig">+' + (races.length - 5) + '</b><span>more</span></div>' : ''), 'wr-tiles') +
    pop(0.9, races.some((r) => r.timeText) ? 'Typed by you, from the organiser\'s results.' : 'Add your results on the race pages to see your times here.', 'wcopy', 'margin-top:16px;opacity:.85');
}

const CARDS = { intro: introCard, visits: visitsCard, persona: personaCard, place: placeCard, streak: streakCard, race: raceCard, top: topCard, share: shareCard };
const GRADIENT = { intro: 'g-intro', visits: 'g-visits', persona: 'g-persona', place: 'g-place', streak: 'g-streak', race: 'g-race', top: 'g-top', share: 'g-share' };

// ---------------------------------------------------------------- the story player

let current = null;

export async function openWrapped() {
  if (current) return;
  const back = document.activeElement;
  const dlg = document.createElement('dialog');
  dlg.className = 'wr';
  dlg.setAttribute('aria-label', 'Brüce Wrapped');
  dlg.innerHTML = '<div class="wr-stage"><div class="wr-prog" aria-hidden="true"></div>' +
    '<button class="wr-close" data-wr-close aria-label="Close">' + icon('close') + '</button>' +
    '<div class="wr-story g-intro on wr-loading"><div class="pop wkicker" style="--d:.1s">Brüce Wrapped</div><div class="pop wbig" style="--d:.25s;font-size:44px;margin-top:22px">UNWRAPPING<br>YOUR<br>YEAR…</div><div class="wr-dots"><i></i><i></i><i></i></div></div>' +
    '<canvas class="wr-confetti" aria-hidden="true"></canvas>' +
    '<button class="wr-nav prev" data-wr-prev aria-label="Previous card">' + icon('back') + '</button><button class="wr-nav next" data-wr-next aria-label="Next card">' + icon('chevron') + '</button></div>';
  document.body.appendChild(dlg);
  const stage = dlg.querySelector('.wr-stage');
  const st = { dlg, stage, idx: 0, elapsed: 0, paused: false, closed: false, cards: [], els: [], raf: 0, last: 0, confetti: makeConfetti(dlg.querySelector('.wr-confetti')) };
  current = st;
  const prevOverflow = document.documentElement.style.overflow;
  document.documentElement.style.overflow = 'hidden';
  const close = () => {
    if (st.closed) return;
    st.closed = true; current = null;
    cancelAnimationFrame(st.raf); st.confetti.stop();
    document.removeEventListener('visibilitychange', onVis);
    document.documentElement.style.overflow = prevOverflow;
    if (dlg.open) dlg.close();
    dlg.remove();
    if (back && back.focus) back.focus();
  };
  st.close = close;
  const onVis = () => { st.last = performance.now(); };
  document.addEventListener('visibilitychange', onVis);
  dlg.addEventListener('cancel', (e) => { e.preventDefault(); close(); });
  dlg.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight' || e.key === 'PageDown') { e.preventDefault(); go(st, st.idx + 1); }
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); go(st, st.idx - 1); }
    else if (e.key === ' ' && !(e.target.closest && e.target.closest('button'))) { e.preventDefault(); st.paused = !st.paused; stage.classList.toggle('held', st.paused); }
  });
  dlg.addEventListener('click', (e) => {
    if (e.target.closest('[data-wr-close]')) close();
    else if (e.target.closest('[data-wr-prev]')) go(st, st.idx - 1);
    else if (e.target.closest('[data-wr-next]')) go(st, st.idx + 1);
    else if (e.target.closest('[data-share]')) shareImage(st.data, false, e.target.closest('button'));
    else if (e.target.closest('[data-save]')) shareImage(st.data, true, e.target.closest('button'));
  });
  bindGestures(st);
  dlg.showModal();
  dlg.querySelector('.wr-close').focus();

  let data;
  try { data = await load(); } catch (e) {
    if (st.closed) return;
    stage.querySelector('.wr-loading').innerHTML = '<div class="wkicker">Brüce Wrapped</div><div class="wbig" style="font-size:36px;margin-top:22px">COULD NOT<br>LOAD YOUR<br>YEAR.</div><p class="wcopy" style="margin-top:18px">' + esc(e.message || 'Try again in a moment.') + '</p>';
    return;
  }
  if (st.closed) return;
  st.data = data;
  st.cards = cardsFor(data.stats, data.pct);
  stage.querySelector('.wr-loading').remove();
  stage.querySelector('.wr-prog').innerHTML = st.cards.map(() => '<i><b></b></i>').join('');
  const html = st.cards.map((k, i) => '<section class="wr-story ' + GRADIENT[k] + (k === 'persona' && data.stats.archetype.key === 'nightOwl' ? ' g-night' : '') + '" data-card="' + k + '"' + confetti(k) +
    ' aria-roledescription="card" aria-label="' + (i + 1) + ' of ' + st.cards.length + '">' + CARDS[k](data) + '</section>').join('');
  stage.querySelector('.wr-prog').insertAdjacentHTML('afterend', html);
  st.els = [...stage.querySelectorAll('.wr-story')];
  if (st.cards.length > 1) stage.insertAdjacentHTML('beforeend', '<div class="wr-hint" aria-hidden="true"><span>‹ tap to go back</span><span>tap for next ›</span></div>');
  go(st, 0, true);
  st.last = performance.now();
  const tick = (now) => {
    if (st.closed) return;
    const dt = Math.min(100, now - st.last); st.last = now;
    if (!st.paused && !document.hidden && st.idx < st.cards.length - 1) {
      st.elapsed += dt;
      if (st.elapsed >= DURATION) go(st, st.idx + 1);
    }
    const bars = stage.querySelectorAll('.wr-prog b');
    bars.forEach((b, i) => { b.style.transform = 'scaleX(' + (i < st.idx ? 1 : i > st.idx ? 0 : (st.idx === st.cards.length - 1 ? 1 : Math.min(1, st.elapsed / DURATION))) + ')'; });
    st.raf = requestAnimationFrame(tick);
  };
  st.raf = requestAnimationFrame(tick);
}

/** Shows card `i`: restarts its entrance animations, count-ups and confetti. Past the last card nothing happens. */
function go(st, i, first) {
  if (!st.els.length || i < 0 || i >= st.els.length || (i === st.idx && !first)) return;
  st.idx = i; st.elapsed = 0;
  st.els.forEach((el, k) => {
    el.classList.remove('on');
    el.setAttribute('aria-hidden', k === i ? 'false' : 'true');
    el.inert = k !== i;
  });
  const el = st.els[i];
  void el.offsetWidth;            // restart the CSS entrance animations
  el.classList.add('on');
  const hint = st.stage.querySelector('.wr-hint');
  if (hint) hint.classList.toggle('show', i === 0);
  el.querySelectorAll('[data-count]').forEach((c) => countUp(c, +c.dataset.count, st));
  st.confetti.set(reduced() ? null : CONFETTI[el.dataset.confetti] || null);
}

function countUp(el, to, st) {
  if (reduced() || to <= 0) { el.textContent = to; return; }
  const delay = 300, dur = Math.min(1600, 700 + to * 6);
  const start = performance.now();
  const card = st.idx;
  el.textContent = '0';
  const step = (now) => {
    if (st.closed || st.idx !== card) { el.textContent = to; return; }
    const t = Math.max(0, Math.min(1, (now - start - delay) / dur));
    el.textContent = Math.round(to * (1 - Math.pow(1 - t, 3)));
    if (t < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Taps (left third back, rest forward), hold to pause, horizontal swipes to step, swipe down to close. */
function bindGestures(st) {
  const { stage } = st;
  let p = null;
  stage.addEventListener('pointerdown', (e) => {
    if (e.button > 0 || e.target.closest('button, a') || !st.els.length) return;
    p = { id: e.pointerId, x: e.clientX, y: e.clientY, t: performance.now(), dy: 0, dx: 0 };
    p.timer = setTimeout(() => { if (p) { p.held = true; st.paused = true; stage.classList.add('held'); } }, HOLD);
    try { stage.setPointerCapture(e.pointerId); } catch (_) { /* not capturable */ }
  });
  stage.addEventListener('pointermove', (e) => {
    if (!p || e.pointerId !== p.id) return;
    p.dx = e.clientX - p.x; p.dy = e.clientY - p.y;
    if (p.dy > 10 && Math.abs(p.dy) > Math.abs(p.dx) && !reduced()) {
      stage.style.transform = 'translateY(' + p.dy + 'px) scale(' + Math.max(0.9, 1 - p.dy / 2000) + ')';
      stage.style.transition = 'none';
    }
  });
  const end = (e, cancel) => {
    if (!p || e.pointerId !== p.id) return;
    clearTimeout(p.timer);
    const { dx, dy, held } = p;
    p = null;
    stage.style.transition = ''; stage.style.transform = '';
    st.paused = false; stage.classList.remove('held');
    if (cancel) return;
    if (dy > 90 && dy > Math.abs(dx)) return st.close();
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) return go(st, st.idx + (dx < 0 ? 1 : -1));
    if (held || Math.abs(dx) > 10 || Math.abs(dy) > 10) return;
    const r = stage.getBoundingClientRect();
    go(st, st.idx + (e.clientX - r.left < r.width / 3 ? -1 : 1));
  };
  stage.addEventListener('pointerup', (e) => end(e, false));
  stage.addEventListener('pointercancel', (e) => end(e, true));
  stage.addEventListener('contextmenu', (e) => e.preventDefault());
}

/** Falling confetti on a canvas over the card; `set(colors)` keeps it raining, `set(null)` lets it fall out. */
function makeConfetti(canvas) {
  const ctx = canvas.getContext('2d');
  let colors = null, parts = [], raf = 0, w = 0, h = 0, last = 0;
  const size = () => {
    const r = canvas.getBoundingClientRect(), dpr = Math.min(2, window.devicePixelRatio || 1);
    w = r.width; h = r.height; canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  };
  const spawn = (top) => ({
    x: Math.random() * w, y: top ? -20 - Math.random() * h * 0.6 : -20, vy: 150 + Math.random() * 170, sway: Math.random() * 6.28,
    rot: Math.random() * 6.28, vr: (Math.random() - 0.5) * 8, shape: Math.floor(Math.random() * 3), c: colors[Math.floor(Math.random() * colors.length)],
  });
  const frame = (now) => {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (canvas.width === 0 || w === 0) size();
    ctx.clearRect(0, 0, w, h);
    parts = parts.filter((q) => q.y < h + 30);
    if (colors) while (parts.length < 36) parts.push(spawn(false));
    for (const q of parts) {
      q.y += q.vy * dt; q.sway += dt * 2; q.rot += q.vr * dt;
      ctx.save(); ctx.translate(q.x + Math.sin(q.sway) * 14, q.y); ctx.rotate(q.rot); ctx.fillStyle = q.c;
      if (q.shape === 0) ctx.fillRect(-4, -7, 8, 14);
      else if (q.shape === 1) { ctx.beginPath(); ctx.arc(0, 0, 5, 0, 6.29); ctx.fill(); }
      else ctx.fillRect(-2.5, -8, 5, 16);
      ctx.restore();
    }
    raf = parts.length || colors ? requestAnimationFrame(frame) : 0;
  };
  window.addEventListener('resize', size);
  return {
    set(c) {
      const was = colors;
      colors = c;
      if (c && c !== was) { size(); parts = parts.concat(Array.from({ length: 40 }, () => spawn(true))).slice(-70); }
      if (!raf && (colors || parts.length)) { last = performance.now(); raf = requestAnimationFrame(frame); }
    },
    stop() { colors = null; parts = []; cancelAnimationFrame(raf); raf = 0; window.removeEventListener('resize', size); },
  };
}

// ---------------------------------------------------------------- share image

const DISPLAY = '"Unbounded", "SF Pro Display", system-ui, sans-serif';
const TEXT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI", Roboto, sans-serif';

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function spark(ctx, cx, cy, r) {
  ctx.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = -Math.PI / 2 + i * Math.PI / 4, rr = i % 2 ? r * 0.3 : r;
    ctx[i ? 'lineTo' : 'moveTo'](cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
  }
  ctx.closePath(); ctx.fill();
}
/** Wraps `text` to lines no wider than `w` (at most `max` lines, the last one ellipsised). */
function wrapLines(ctx, text, w, max) {
  const out = []; let line = '';
  for (const word of String(text).split(/\s+/)) {
    const t = line ? line + ' ' + word : word;
    if (ctx.measureText(t).width <= w || !line) line = t; else { out.push(line); line = word; }
  }
  if (line) out.push(line);
  if (out.length > max) { out.length = max; let l = out[max - 1]; while (l && ctx.measureText(l + '…').width > w) l = l.slice(0, -1); out[max - 1] = l + '…'; }
  return out;
}
/** Fits a font size so `text` is at most `w` wide. */
function fit(ctx, text, font, size, w) {
  let s = size;
  do { ctx.font = font.replace('$', s); s -= 2; } while (ctx.measureText(text).width > w && s > 20);
}

/** Draws the share card (the still frame of the last card) on a new 1080x1920 canvas. */
export async function shareCanvas(x) {
  try { await Promise.all([document.fonts.load('900 64px Unbounded'), document.fonts.load('800 64px Unbounded')]); } catch (_) { /* fall back to system fonts */ }
  const W = 1080, H = 1920;
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const ctx = c.getContext('2d');
  let g = ctx.createRadialGradient(540, 560, 0, 540, 560, 1400);
  g.addColorStop(0, '#1d2b0a'); g.addColorStop(0.7, '#000'); ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // Confetti, seeded so the image is the same every time.
  let seed = 11; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const cols = CONFETTI.share;
  for (let i = 0; i < 70; i++) {
    const px = rnd() * W, py = rnd() * H;
    if (px > 40 && px < 1040 && py > 260 && py < 1660) continue;
    ctx.save(); ctx.translate(px, py); ctx.rotate(rnd() * 6.28); ctx.fillStyle = cols[i % cols.length];
    if (i % 3 === 0) { ctx.beginPath(); ctx.arc(0, 0, 13, 0, 6.29); ctx.fill(); } else ctx.fillRect(-10, -18, 20, 36);
    ctx.restore();
  }
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = '#fff'; ctx.font = '900 60px ' + DISPLAY; ctx.fillText('WRAPPED', 90, 190);
  // The card.
  const cx = 70, cy = 270, cw = 940, ch = 1380;
  ctx.save();
  ctx.shadowColor = 'rgba(218,252,85,.35)'; ctx.shadowBlur = 90; ctx.shadowOffsetY = 30;
  g = ctx.createLinearGradient(cx, cy, cx + cw, cy + ch);
  g.addColorStop(0, '#dafc55'); g.addColorStop(0.55, '#3ae0ff'); g.addColorStop(1, '#b18cff');
  ctx.fillStyle = g; roundRect(ctx, cx, cy, cw, ch, 84); ctx.fill();
  ctx.restore();
  ctx.save(); roundRect(ctx, cx, cy, cw, ch, 84); ctx.clip();
  g = ctx.createLinearGradient(cx + 200, cy, cx + 700, cy + ch);
  g.addColorStop(0.35, 'rgba(255,255,255,0)'); g.addColorStop(0.5, 'rgba(255,255,255,.4)'); g.addColorStop(0.65, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(cx, cy, cw, ch);
  ctx.restore();
  const L = cx + 70, R = cx + cw - 70;
  ctx.fillStyle = '#000'; ctx.font = '900 112px ' + DISPLAY;
  ctx.fillText('BRÜCE', L, cy + 180); ctx.fillText(String(x.year), L, cy + 300);
  spark(ctx, R - 50, cy + 120, 56);
  ctx.fillStyle = 'rgba(0,0,0,.7)'; ctx.font = '700 40px ' + TEXT; ctx.fillText(x.name, L, cy + 380);
  // Persona pill.
  ctx.font = '800 38px ' + TEXT;
  const pw = ctx.measureText(x.persona).width + 120;
  ctx.fillStyle = '#000'; roundRect(ctx, L, cy + 420, pw, 84, 42); ctx.fill();
  ctx.fillStyle = '#dafc55'; spark(ctx, L + 48, cy + 462, 20); ctx.fillText(x.persona, L + 82, cy + 476);
  // Stat tiles, two columns.
  const colW = (R - L - 40) / 2;
  x.tiles.forEach((t, i) => {
    const tx = L + (i % 2) * (colW + 40), ty = cy + 640 + Math.floor(i / 2) * 230;
    ctx.fillStyle = '#000'; fit(ctx, t.value, '900 $px ' + DISPLAY, 88, colW); ctx.fillText(t.value, tx, ty);
    ctx.fillStyle = 'rgba(0,0,0,.72)'; ctx.font = '700 34px ' + TEXT;
    wrapLines(ctx, t.label, colW, 2).forEach((l, k) => ctx.fillText(l, tx, ty + 56 + k * 42));
  });
  // Footer.
  const fy = cy + ch - 130;
  ctx.fillStyle = 'rgba(0,0,0,.18)'; ctx.fillRect(L, fy, R - L, 4);
  ctx.fillStyle = '#000'; ctx.font = '800 36px ' + TEXT;
  ctx.fillText(x.left, L, fy + 76);
  ctx.textAlign = 'right'; ctx.fillText(x.right, R, fy + 76); ctx.textAlign = 'left';
  ctx.fillStyle = 'rgba(255,255,255,.6)'; ctx.font = '700 34px ' + TEXT; ctx.textAlign = 'center';
  ctx.fillText('Brüce · djui.github.io/bruce', W / 2, H - 120);
  ctx.textAlign = 'left';
  return c;
}

/** A toast inside Wrapped (the app's toast sits below the modal dialog). */
function say(msg) {
  const stage = current && current.stage;
  if (!stage) return;
  let t = stage.querySelector('.wr-toast');
  if (!t) { t = document.createElement('div'); t.className = 'wr-toast'; t.setAttribute('role', 'status'); stage.appendChild(t); }
  t.textContent = msg; t.classList.add('show');
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 2400);
}

async function shareImage(d, save, btn) {
  if (!d || (btn && btn.disabled)) return;
  if (btn) btn.disabled = true;
  try {
    const c = await shareCanvas(shareData(d));
    const blob = await new Promise((r) => c.toBlob(r, 'image/png'));
    if (!blob) throw new Error('Could not draw the image.');
    const name = 'bruce-wrapped-' + d.year + '.png';
    const file = typeof File === 'function' ? new File([blob], name, { type: 'image/png' }) : null;
    if (!save && file && navigator.canShare && navigator.canShare({ files: [file] })) {
      try { await navigator.share({ files: [file], title: 'My Brüce Wrapped ' + d.year }); return; }
      catch (e) { if (e && e.name === 'AbortError') return; }
    }
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    say('Image saved');
  } catch (e) {
    say(e.message || 'Could not share the image.');
  } finally {
    if (btn) btn.disabled = false;
  }
}

/** The share image of the open Wrapped as a canvas (for checks in the browser console). */
export const currentShareCanvas = () => (current && current.data ? shareCanvas(shareData(current.data)) : null);
