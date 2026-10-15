// Sheets (BruceApp.swift SheetScreen): booking rules, similar classes, invite, visit limit, ticket, rating, check-in
// scanner, notifications, and the menu with account, statistics, payments and settings.
import { $, esc, icon, fmt, time, dayHeader, classDateLine, ruleTime, dayKey, todayKey, money, fullName, initials, byDay, minutes, instructor } from './util.js';
import { Bruce } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { sheet, toast, run, empty, loading, avatar, classRow, sectionHeader, confirmSheet, stars } from './ui.js';
import { openPlaces } from './foryou.js';
import { goalsCardHTML, openGoals, openGoalEditor } from './goalsui.js';
import { openWrapped } from './wrapped.js';

// ---------------------------------------------------------------- booking rules (book / cancel)

/** BookingRulesSheet: the class, its strike rules with times, then Book or Cancel booking. */
export function openRules(c, mode, action) {
  const r = St.rules(c);
  const now = Date.now();
  const rows = [
    ['checkin', 'Late check-in', 'Check-in after ' + ruleTime(r.lateCheckIn)],
    ['calendar', 'Late cancellation', 'Cancel after ' + ruleTime(r.lateCancel)],
    ['calendar', 'Short-notice cancellation', 'Cancel after ' + ruleTime(r.shortNotice)],
    ['calendar', 'Last-minute cancellation', 'Cancel after ' + ruleTime(r.lastMinute)],
    ['strike', 'No-show', 'Booked, but never checked in.'],
  ];
  let cost = '';
  if (mode === 'cancel') {
    cost = now < r.lateCancel ? 'Cancelling now is free.' : now < r.shortNotice ? 'This is a late cancellation and gives 1 strike.' : 'This is a very late cancellation and gives 2 strikes.';
  }
  const ore = St.city().user_strike_block_un_lock_price;
  const unlock = ore ? Math.round(ore / 100) : null;
  const s = sheet('', '<h2 class="sheet-title">' + esc(c.title.toUpperCase()) + '</h2><p class="center muted">' + esc(classDateLine(c)) + ' at ' + esc(St.studioName(c.studio_id, c.studio)) + '</p>' +
    '<div class="card rule-list">' + rows.map(([ic, t, d]) => '<div>' + icon(ic) + '<div><b>' + esc(t) + '</b><p class="muted">' + esc(d) + '</p></div></div>').join('') + '</div>' +
    (cost ? '<p class="center"><b>' + esc(cost) + '</b></p>' : '') +
    '<button class="btn ' + (mode === 'cancel' ? 'red' : 'lime') + '" data-go>' + (mode === 'cancel' ? 'Cancel booking' : 'Book') + '</button>' +
    '<p class="muted small note">' + icon('info') + ' Reaching 3 strikes pauses class booking for 14 days.' + (unlock ? ' You can lift a block early for ' + unlock + ' kr.' : '') + '</p>', { cls: 'tall' });
  const go = s.el.querySelector('[data-go]');
  go.addEventListener('click', () => run(go, async () => { await action(); s.close(); }));
}

// ---------------------------------------------------------------- similar classes, invite, visit limit

export function openSimilar(c, link) {
  const s = sheet('Similar classes', '<p class="center muted">Similar classes to</p><h3 class="center">' + esc(c.title) + ', ' + esc(time(c.start_time)) + '</h3><p class="center muted small">nearby ' + esc(St.studioName(c.studio_id, c.studio)) + '</p><div class="list" id="sim">' + loading() + '</div>');
  Bruce.similar(c.id).then((cards) => {
    $('#sim', s.el).innerHTML = cards.length ? cards.map((k) => '<a class="crow" href="' + link('class', k.id) + '" data-close>' +
      '<div class="crow-time"><b>' + time(k.start_time) + '</b><small>' + (minutes(k.start_time, k.end_time) || '') + ' min</small></div>' +
      '<div class="crow-body"><h3>' + esc(k.title) + '</h3><p>' + esc(k.studio && k.studio.name) + '</p>' + (k.distance ? '<p class="muted">' + (k.distance < 1000 ? k.distance + ' m' : (k.distance / 1000).toFixed(1).replace('.', ',') + ' km') + '</p>' : '') + '</div></a>').join('')
      : empty('search', 'No similar classes right now.');
  }).catch((e) => { $('#sim', s.el).innerHTML = empty('info', e.message); });
}

export function openInvite(c) {
  const picked = new Set();
  const s = sheet(c.title, '<p class="muted center">Pick friends to invite to this class.</p><div class="list" id="inv">' + S.friends.map((f) => {
    const u = f.friend_user || {};
    return '<button class="trow pick" data-u="' + u.id + '">' + avatar(u, 44) + '<b class="grow">' + esc(fullName(u)) + '</b><span class="check">' + icon('check') + '</span></button>';
  }).join('') + '</div><button class="btn lime" data-go disabled>Invite friends</button>');
  const go = s.el.querySelector('[data-go]');
  s.el.querySelectorAll('[data-u]').forEach((b) => b.addEventListener('click', () => {
    const id = +b.dataset.u;
    if (picked.has(id)) picked.delete(id); else picked.add(id);
    b.classList.toggle('on', picked.has(id)); go.disabled = !picked.size;
  }));
  go.addEventListener('click', () => run(go, async () => { await Bruce.invite(c.id, [...picked]); toast(picked.size === 1 ? 'Invite sent' : 'Invites sent'); s.close(); }));
}

export function openVisitLimit(studioId) {
  const s = sheet('Visit limit', loading());
  const month = new Date().toISOString().slice(0, 7).replace('-', '');
  Bruce.studioLimits(studioId, month).then((limits) => {
    const l = limits.find((x) => x.type === 'STUDIO') || limits[0];
    const items = (l && l.items) || (St.studio(studioId) || {}).limits || [];
    const reset = l && l.resets_at ? fmt(l.resets_at, { day: 'numeric', month: 'long' }) : null;
    const head = !l ? '' : l.total > 0 ? '<h2 class="big-num">' + (l.used || 0) + ' / ' + l.total + '</h2><p class="center muted">visits this month' + (reset ? ' · resets ' + esc(reset) : '') + '</p>'
      : l.total === 0 ? '<h2 class="big-num">' + icon('infinity') + '</h2><p class="center muted">Unlimited visits on your plan</p>' : '<h2 class="big-num">0 / 0</h2><p class="center muted">Not included in your plan</p>';
    s.body.innerHTML = '<h3 class="center">' + esc(St.studioName(studioId)) + '</h3>' + head +
      (items.length ? '<div class="card kv">' + items.map((i) => '<span>' + esc(i.label) + '</span><b>' + (i.limit === 0 ? 'Unlimited' : i.limit === -1 ? 'Not included' : i.limit + ' per month') + '</b>').join('') + '</div>' : '');
  }).catch((e) => { s.body.innerHTML = empty('info', e.message); });
}

// ---------------------------------------------------------------- ticket and check-in

/** TicketSheet: the user's name, the day, a big check mark, the class or "Solo training", the check-in time. */
export function openTicket(bookingId) {
  const b = [...S.bookings.values()].find((x) => x.id === bookingId) || (S.visits || []).find((x) => x.id === bookingId);
  if (!b) { toast('Ticket not found'); return; }
  const sid = b.studio_id || (b.class && b.class.studio_id);
  sheet('Ticket', '<div class="ticket">' + '<div class="ticket-head">' + avatar(S.user || {}, 64) + '<div><h2>' + esc(fullName(S.user) || 'Member') + '</h2><p class="muted">' + esc(fmt(b.checked_in_at, { weekday: 'long', day: 'numeric', month: 'long' })) + '</p></div></div>' +
    '<div class="ticket-main">' + icon('checkSeal', 'seal') + '<div class="grow"><b>' + esc((b.class && b.class.title) || 'Solo training') + '</b><p class="muted">' + esc(St.studioName(sid)) + '</p></div>' +
    '<div class="ticket-time"><small>CHECKED IN</small><b>' + esc(time(b.checked_in_at)) + '</b></div></div><div class="ticket-live"><i></i>' + esc(St.studioName(sid)) + ' · Brüce</div></div>', { cls: 'tall' });
}

let checkInBusy = false;
/** Confirm, then one POST /v52/studio/check_in. A non-2xx answer is not proof of failure (API.md): the bookings are
 *  re-read and a check-in at that studio today counts as success. */
export async function checkInFlow(studioOrTarget, btn) {
  const t = typeof studioOrTarget === 'object' ? studioOrTarget : St.target(studioOrTarget, '');
  if (!t) { toast('This studio has no check-in code.'); return; }
  if (checkInBusy) return;
  const yes = await confirmSheet('Check in at ' + t.name + '?', 'Only check in when you are at the studio. It counts like a check-in in the official app.', 'Check in', 'lime');
  if (!yes) return;
  checkInBusy = true;
  try {
    await run(btn, async () => {
      const r = await Bruce.checkIn(t.qr, t.door);
      const ok = r.status >= 200 && r.status < 300;
      if (ok && t.door) St.rememberDoor(t.studioId, t.door);
      await St.loadMine().catch(() => {});
      S.visits = null; S.history = null;
      const b = St.todaysCheckIn(t.studioId) || (ok && r.body && r.body.bookings && r.body.bookings[0]);
      if (b && b.checked_in_at) {
        if (!S.bookings.has(b.class_id || 's' + b.id)) S.bookings.set(b.class_id || 's' + b.id, b);
        toast('Checked in at ' + t.name); St.emit(); openTicket(b.id); return;
      }
      if (ok) { toast('Checked in at ' + t.name); return; }
      const e = r.body && r.body.errors && r.body.errors[0];
      throw new Error('Check-in failed: ' + ((e && (e.message || e.code)) || 'HTTP ' + r.status));
    });
  } finally { checkInBusy = false; }
}

/** Door QR scanner: BarcodeDetector where the browser has it, else jsQR (vendor/jsQR.js) on camera frames. */
export function openScanner() {
  const s = sheet('Scan door QR code', '<div class="scanner"><video playsinline muted></video><div class="frame"></div></div><p class="center muted" id="scan-msg">Point the camera at the QR code on the studio door.</p>' +
    '<details class="card"><summary>Enter the code instead</summary><input type="text" id="scan-code" placeholder="stc://open-door?major=…&minor=…"><button class="btn glass" data-manual>Use code</button></details>',
  { cls: 'tall', onClose: stop });
  const video = s.el.querySelector('video');
  let stream = null, timer = null, stopped = false;
  function stop() { stopped = true; clearTimeout(timer); if (stream) stream.getTracks().forEach((x) => x.stop()); }
  function found(code) {
    const t = St.targetForScan(code);
    if (!t) { $('#scan-msg', s.el).textContent = 'This is not a studio check-in code.'; return false; }
    stop(); s.close(); checkInFlow(t); return true;
  }
  s.el.querySelector('[data-manual]').addEventListener('click', () => found($('#scan-code', s.el).value));
  (async () => {
    try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false }); }
    catch (e) { $('#scan-msg', s.el).textContent = 'No camera access. You can enter the code instead.'; return; }
    if (stopped) { stop(); return; }
    video.srcObject = stream; await video.play().catch(() => {});
    let detect;
    if ('BarcodeDetector' in window) {
      const d = new window.BarcodeDetector({ formats: ['qr_code'] });
      detect = async () => { const r = await d.detect(video); return r[0] && r[0].rawValue; };
    } else {
      await new Promise((res) => { if (window.jsQR) return res(); const js = document.createElement('script'); js.src = 'vendor/jsQR.js'; js.onload = res; js.onerror = res; document.head.appendChild(js); });
      const cv = document.createElement('canvas'); const cx = cv.getContext('2d', { willReadFrequently: true });
      detect = async () => {
        if (!window.jsQR || !video.videoWidth) return null;
        cv.width = video.videoWidth; cv.height = video.videoHeight; cx.drawImage(video, 0, 0);
        const r = window.jsQR(cx.getImageData(0, 0, cv.width, cv.height).data, cv.width, cv.height);
        return r && r.data;
      };
    }
    const loop = async () => {
      if (stopped) return;
      try { const code = await detect(); if (code && found(code)) return; } catch (e) { /* next frame */ }
      timer = setTimeout(loop, 250);
    };
    loop();
  })();
}

// ---------------------------------------------------------------- rating a class

export function openReview(b) {
  let n = 0, anon = false;
  const c = b.class;
  const s = sheet('Rate the class', '<h2 class="sheet-title">' + esc(c.title.toUpperCase()) + '</h2><p class="center muted">' + esc(classDateLine(c)) + ' at ' + esc(St.studioName(c.studio_id, c.studio)) + '</p>' +
    '<div class="rate">' + [1, 2, 3, 4, 5].map((i) => '<button data-n="' + i + '" aria-label="' + i + ' stars">' + icon('star') + '</button>').join('') + '</div>' +
    '<textarea id="rv-comment" rows="3" placeholder="Comment (optional)"></textarea><p class="muted small" id="rv-hint" hidden>' + icon('info') + ' Tell the studio what could be better: a comment is needed for ratings of 1 or 2.</p>' +
    '<label class="toggle"><span>Hide my name and photo</span><input type="checkbox" id="rv-anon"><i></i></label>' +
    '<p class="muted small note">' + icon('info') + ' Ratings with a comment show your first name and photo on the studio page unless you hide them.</p>' +
    '<button class="btn lime" data-send disabled>Send</button><button class="btn glass" data-skip>Skip</button>', { cls: 'tall' });
  const send = s.el.querySelector('[data-send]');
  const comment = $('#rv-comment', s.el);
  const update = () => {
    s.el.querySelectorAll('[data-n]').forEach((x) => x.classList.toggle('on', +x.dataset.n <= n));
    const need = n > 0 && n <= 2 && !comment.value.trim();
    $('#rv-hint', s.el).hidden = !(n > 0 && n <= 2);
    send.disabled = !n || need;
    send.textContent = anon ? 'Send anonymously' : 'Send';
  };
  s.el.querySelectorAll('[data-n]').forEach((x) => x.addEventListener('click', () => { n = +x.dataset.n; update(); }));
  comment.addEventListener('input', update);
  $('#rv-anon', s.el).addEventListener('change', (e) => { anon = e.target.checked; update(); });
  s.el.querySelector('[data-skip]').addEventListener('click', () => { St.skipReview(b.id); toast('Skipped. You can rate this class later from My classes.'); s.close(); });
  send.addEventListener('click', () => run(send, async () => {
    await Bruce.review(b.id, n, comment.value.trim(), !anon);
    S.reviewable = S.reviewable.filter((x) => x.id !== b.id); St.emit();
    toast('Thanks for rating ' + c.title); s.close();
  }));
}

// ---------------------------------------------------------------- notifications

const NOTE = {
  STANDBY_AVAILABLE: ['bell', 'teal', 'Free spot'], BOOKING_REMINDER: ['clock', '', 'Reminder'], BOOKING_CANCELLED: ['close', 'red', 'Cancelled'],
  CLASS_MESSAGE: ['info', '', 'Message'], CHECK_IN_REMINDER: ['checkin', '', 'Check-in'], USER_STRIKE: ['strike', 'red', 'Strike'],
  USER_BLOCK: ['strike', 'red', 'Blocked'], USER_STRIKE_UNBLOCKED: ['check', 'teal', 'Unblocked'], CLASS_INVITE: ['friends', 'lime', 'Invite'], PAUSE_ENDING: ['calendar', '', 'Pause'],
};
export function openNotifications() {
  const s = sheet('Notifications', '<div id="notes">' + loading() + '</div>');
  const draw = () => {
    const box = $('#notes', s.el);
    if (!box) return;
    box.innerHTML = S.notifications.length ? S.notifications.map((n) => {
      const [ic, tone, label] = NOTE[n.type] || ['bell', '', ''];
      const href = n.meta && n.meta.class_id ? '#/home/class/' + n.meta.class_id : n.meta && n.meta.studio_id ? '#/home/studio/' + n.meta.studio_id : null;
      const fresh = new Date(n.created_at).getTime() > S.seenNotifications;
      return '<' + (href ? 'a href="' + href + '" data-close' : 'div') + ' class="note-row' + (fresh ? ' fresh' : '') + '"><span class="note-ic ' + tone + '">' + icon(ic) + '</span>' +
        '<div class="grow"><div class="row-between"><b>' + esc(n.title || label) + '</b><span class="muted small">' + esc(relTime(n.created_at)) + '</span></div><p class="muted">' + esc(n.message || '') + '</p></div></' + (href ? 'a' : 'div') + '>';
    }).join('') : empty('bell', 'No notifications.');
  };
  St.loadNotifications().then(() => { draw(); St.markNotificationsSeen(); });
  if (S.notifications.length) draw();
}
function relTime(iso) {
  const d = (Date.now() - new Date(iso)) / 60000;
  if (d < 60) return Math.max(1, Math.round(d)) + ' min';
  if (d < 1440) return Math.round(d / 60) + ' h';
  if (d < 7 * 1440) return Math.round(d / 1440) + ' d';
  return fmt(iso, { day: 'numeric', month: 'short' });
}

// ---------------------------------------------------------------- menu and account

const MENU = [
  ['person', 'Account', openAccount], ['chart', 'Statistics', openStatistics], ['receipt', 'Payments and receipts', openPayments],
  ['gift', 'Invite friends', openVouchers], ['spark', 'Your ' + new Date().getFullYear() + ' Wrapped', () => openWrapped()], ['gear', 'Settings', openSettings],
];
export function openMenu() {
  const u = S.user;
  const s = sheet('', '<div class="menu-head">' + avatar(u || {}, 56) + '<div><h2>' + esc(fullName(u) || 'Member') + '</h2><p class="muted">' + (u ? 'Member #' + u.id : '') + (St.isDemo() ? ' · Demo' : '') + '</p></div></div>' +
    '<div class="card menu">' + MENU.map(([ic, t], i) => '<button class="mrow" data-m="' + i + '">' + icon(ic) + '<span class="grow">' + esc(t) + '</span>' + icon('chevron') + '</button>').join('') + '</div>' +
    '<div class="card menu"><a class="mrow" href="https://github.com/djui/bruce" target="_blank" rel="noopener">' + icon('info') + '<span class="grow">About Brüce</span>' + icon('chevron') + '</a>' +
    '<button class="mrow red" data-logout>' + icon('logout') + '<span class="grow">' + (St.isDemo() ? 'Leave demo' : 'Log out') + '</span></button></div>' +
    '<p class="muted small note">Unofficial and not affiliated with Bruce Studios AB. Tickets and memberships are only sold in the official app.</p>');
  s.el.querySelectorAll('[data-m]').forEach((b) => b.addEventListener('click', () => { s.close(); MENU[+b.dataset.m][2](); }));
  s.el.querySelector('[data-logout]').addEventListener('click', () => { s.close(); window.dispatchEvent(new Event('bruce:logout')); });
}

function openAccount() {
  const s = sheet('Account', loading());
  St.loadAccount().then(() => {
    const m = S.membership || {}, b = S.block || {}, u = S.user || {};
    const names = { MONTHLY: 'Visits this month', WELLNESS_MONTHLY: 'Wellness visits this month', SIMULTANEOUS: 'Simultaneous bookings' };
    const limits = S.limits.filter((l) => names[l.type] && l.total !== -1);
    const strikes = b.strike_count || 0;
    s.body.innerHTML = '<div class="card kv">' + [
      ['Name', fullName(u)], ['Email', u.email], ['Plan', m.membership_tier ? m.membership_tier + (m.paused ? ' (paused)' : '') : null],
      ['Price', m.current_membership_price ? money(m.current_membership_price, m.currency) + ' / month' : null], ['Next payment', m.next_payment ? fmt(m.next_payment, { day: 'numeric', month: 'long' }) : null],
      ['Committed until', m.committed_until ? fmt(m.committed_until, { day: 'numeric', month: 'long', year: 'numeric' }) : null], ['Credits', m.available_credits],
      ['Pause days left', m.remaining_pause_days],
    ].filter(([, v]) => v != null && v !== '').map(([k, v]) => '<span>' + esc(k) + '</span><b>' + esc(v) + '</b>').join('') + '</div>' +
      (limits.length ? '<h3 class="sec-title">VISITS</h3><div class="card">' + limits.map((l) => '<div class="meter-row"><div class="row-between"><span>' + names[l.type] + '</span><b>' +
        (l.total > 0 ? (l.used || 0) + ' / ' + l.total : (l.used || 0) + ' · unlimited') + '</b></div>' + (l.total > 0 ? '<div class="meter"><i style="width:' + Math.min(100, Math.round(100 * (l.used || 0) / l.total)) + '%"></i></div>' : '') + '</div>').join('') + '</div>' : '') +
      '<h3 class="sec-title">STRIKES</h3><div class="card"><div class="strikes">' + [0, 1, 2].map((i) => '<i class="' + (i < strikes ? 'on' : '') + '"></i>').join('') + '<b>' + strikes + ' of 3</b></div>' +
      '<p class="muted small">' + esc(b.blocked ? 'Class booking is blocked' + (b.block_end_date ? ' until ' + fmt(b.block_end_date, { day: 'numeric', month: 'long' }) : '') + '.' : 'At 3 strikes, class booking pauses for 14 days.') +
      ' Free unlocks left: ' + (b.free_unlocks_remaining || 0) + (b.total_free_unlocks ? ' of ' + b.total_free_unlocks : '') + '.</p>' +
      '<ul class="muted small"><li>Late cancellation (3 to 12 hours before) or late check-in: 1 strike</li><li>Very late cancellation (under 3 hours) or no-show: 2 strikes</li></ul></div>' +
      '<p class="muted small note">Edit your profile, pause or change your plan in the official Bruce app.</p>';
  });
}

/** Top of Statistics: this month's goals. */
function statsExtras() {
  return '<button class="wrapped-banner" data-wrapped><span class="grow"><small>Year to date</small><b>Your ' + new Date().getFullYear() + ' Wrapped</b></span>' + icon('spark') + '</button>' + goalsCardHTML();
}
export function openStatistics() {
  const s = sheet('Statistics', loading(), { cls: 'tall' });
  s.body.addEventListener('click', (e) => {
    if (e.target.closest('[data-wrapped]')) openWrapped();
    else if (e.target.closest('[data-goals]')) { if (St.goals().length) openGoals(); else openGoalEditor(null); }
  });
  Promise.all([Bruce.aggregate().catch(() => []), St.loadHistory().then(() => S.visits)])
    .then(([agg, visits]) => {
      const counts = {};
      agg.forEach((a) => { const k = String(a.day).slice(0, 6); counts[k] = (counts[k] || 0) + a.count; });
      const months = [];
      const d = new Date(); d.setDate(1);
      const keys = Object.keys(counts).sort();
      const first = keys[0] && keys[0] < monthKey(addMonths(d, -5)) ? keys[0] : monthKey(addMonths(d, -5));
      for (let m = new Date(+first.slice(0, 4), +first.slice(4) - 1, 1); monthKey(m) <= monthKey(d); m = addMonths(m, 1)) months.push({ key: monthKey(m), date: new Date(m), count: counts[monthKey(m)] || 0 });
      let sel = months[months.length - 1].key;
      const top = Math.max(1, ...months.map((m) => m.count));
      const draw = () => {
        const inMonth = visits.filter((v) => monthKeyOf(visitDate(v)) === sel).sort((a, b) => visitDate(b).localeCompare(visitDate(a)));
        s.body.innerHTML = statsExtras() + '<div class="bars-chart" role="group" aria-label="Visits per month">' + months.map((m) => '<button data-mk="' + m.key + '" class="' + (m.key === sel ? 'sel' : '') + '" aria-label="' + esc(m.date.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })) + ': ' + m.count + ' visits">' +
          '<span>' + m.count + '</span><i style="height:' + Math.max(2, Math.round(150 * m.count / top)) + 'px"></i><small>' + m.date.toLocaleDateString('en-GB', { month: 'short' }) + '</small></button>').join('') + '</div>' +
          (inMonth.length ? byDay(inMonth, visitDate).map((g) => sectionHeader(dayHeader(g.iso)) + g.items.map(visitRow).join('')).join('') : empty('chart', 'No visits this month.'));
        s.body.querySelectorAll('[data-mk]').forEach((b) => b.addEventListener('click', () => { sel = b.dataset.mk; draw(); }));
        const chart = s.body.querySelector('.bars-chart'); chart.scrollLeft = chart.scrollWidth;
      };
      draw();
    });
}
const addMonths = (d, n) => new Date(d.getFullYear(), d.getMonth() + n, 1);
const monthKey = (d) => d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0');
const monthKeyOf = (iso) => (iso ? dayKey(iso).slice(0, 7).replace('-', '') : '');
const isSolo = (v) => !v.class || v.class.opening || !v.class.title;
const visitDate = (v) => (isSolo(v) ? v.checked_in_at : (v.class && v.class.start_time) || v.checked_in_at);
function visitRow(v) {
  const c = v.class || {};
  const st = St.studio(v.studio_id || c.studio_id) || c.studio || {};
  const solo = isSolo(v);
  const title = solo ? (c.opening && c.start_time ? 'Solo training ' + time(c.start_time) + ' - ' + time(c.end_time) : 'Solo training') : c.title;
  const dur = solo ? null : minutes(c.start_time, c.end_time);
  return '<div class="crow"><div class="crow-time"><b>' + time(visitDate(v)) + '</b><small>' + (dur ? dur + ' min' : '') + '</small></div><div class="crow-body"><h3>' + esc(title) + '</h3><p>' + esc(st.name || '') + '</p>' +
    '<p class="muted">' + esc([st.vicinity, instructor(c.instructor)].filter(Boolean).join(' | ')) + '</p></div></div>';
}

function openPayments() {
  const s = sheet('Payments and receipts', loading());
  Promise.all([Bruce.payments().catch(() => []), Bruce.paymentMethods().catch(() => [])]).then(([pays, methods]) => {
    const title = (t) => ({ MEMBERSHIP_RENEWAL: 'Membership', MEMBERSHIP_UPGRADE: 'Membership upgrade', USER_BLOCK_UNLOCK: 'Strike unblock', BOOKING: 'Booking', FREE: 'Free' }[t] || (t || 'Payment'));
    s.body.innerHTML = (methods.length ? '<h3 class="sec-title">PAYMENT METHOD</h3><div class="card kv">' + methods.map((m) => '<span>' + icon('card') + esc(m.name || m.type) + '</span><b>' + (m.default ? 'Default' : '') + '</b>').join('') + '</div>' : '') +
      '<h3 class="sec-title">RECEIPTS</h3>' + (pays.length ? '<div class="card menu">' + pays.map((p) => '<button class="mrow" data-p="' + p.id + '"><div class="grow"><b>' + esc(title(p.type)) + '</b><p class="muted small">' + esc(fmt(p.created_at, { day: 'numeric', month: 'long', year: 'numeric' })) + '</p></div><b>' + esc(money(p.amount, p.currency)) + '</b>' + icon('receipt') + '</button>').join('') + '</div>' : empty('receipt', 'No payments.'));
    s.body.querySelectorAll('[data-p]').forEach((b) => b.addEventListener('click', () => run(b, async () => {
      if (St.isDemo()) { toast('Receipts are not available in the demo'); return; }
      const blob = await Bruce.receipt(+b.dataset.p);
      const url = URL.createObjectURL(blob);
      window.open(url, '_blank') || (location.href = url);
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    })));
  });
}

function openVouchers() {
  const s = sheet('Invite friends', loading());
  Bruce.vouchers().then((v) => {
    s.body.innerHTML = '<p class="muted">Give a friend one of your invite codes. They redeem it in the Bruce app.</p>' +
      (v.length ? '<div class="card menu">' + v.map((x) => '<button class="mrow" data-code="' + esc(x.code) + '"' + (x.used ? ' disabled' : '') + '><b class="grow mono">' + esc(x.code) + '</b><span class="muted small">' + (x.used ? 'Used' : 'Copy') + '</span></button>').join('') + '</div>' : empty('gift', 'No invite codes right now.'));
    s.body.querySelectorAll('[data-code]').forEach((b) => b.addEventListener('click', async () => { try { await navigator.clipboard.writeText(b.dataset.code); toast('Code copied'); } catch (e) { toast(b.dataset.code); } }));
  }).catch((e) => { s.body.innerHTML = empty('info', e.message); });
}

function openSettings() {
  let theme = '';
  try { theme = localStorage.getItem('theme') || ''; } catch (e) { /* private mode */ }
  const s = sheet('Settings', '<div class="card form">' +
    '<label><span>City</span><select id="set-city">' + (S.cities.length ? S.cities : [St.city()]).map((c) => '<option value="' + c.id + '"' + (c.id === S.settings.cityId ? ' selected' : '') + '>' + esc(c.name) + '</option>').join('') + '</select></label>' +
    '<label><span>Appearance</span><select id="set-theme"><option value="">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label></div>' +
    '<h3 class="sec-title">RECOMMENDATIONS</h3><div class="card menu"><button class="mrow" data-places>' + icon('pin') + '<span class="grow">Places &amp; commute<small class="muted block">' + esc(placesLine()) + '</small></span>' + icon('chevron') + '</button></div>' +
    '<h3 class="sec-title">OUR SERVER</h3><div class="card"><label class="toggle"><span>Use our server<small class="muted">Books a waitlisted class the moment a spot opens, sends goal reminders and runs challenges. It stores your Bruce login. Off: only challenges you join use it.</small></span><input type="checkbox" id="set-server"' + (St.serverOn() ? ' checked' : '') + '><i></i></label></div>' +
    '<h3 class="sec-title">SOCIAL</h3><div class="card"><label class="toggle"><span>Bruce Studios Social<small class="muted">Friends and classmates see your name and photo on classes you book.</small></span><input type="checkbox" id="set-social"' + (S.user && S.user.social ? ' checked' : '') + '><i></i></label></div>' +
    '<h3 class="sec-title">NOTIFICATIONS</h3><div class="card" id="set-push">' + loading() + '</div>' +
    '<details class="card"><summary>Advanced</summary><label class="form"><span>API server</span><input type="url" id="set-api" value="' + esc(S.settings.apiBase) + '"></label><p class="muted small">Only change this to route requests through your own proxy.</p></details>');
  s.el.querySelector('[data-places]').addEventListener('click', () => openPlaces());
  $('#set-server', s.el).addEventListener('change', (e) => { S.settings.serverOn = e.target.checked; St.saveSettings(); if (e.target.checked) St.syncGoals(); toast(e.target.checked ? 'Our server is on' : 'Our server is off'); });
  const th = $('#set-theme', s.el); th.value = theme;
  th.addEventListener('change', () => {
    try { if (th.value) localStorage.setItem('theme', th.value); else localStorage.removeItem('theme'); } catch (e) { /* private mode */ }
    if (th.value) document.documentElement.dataset.theme = th.value; else delete document.documentElement.dataset.theme;
  });
  $('#set-city', s.el).addEventListener('change', (e) => { St.selectCity(e.target.value); toast('City set to ' + St.city().name); });
  $('#set-api', s.el).addEventListener('change', (e) => { S.settings.apiBase = e.target.value.trim() || 'https://api.bruce.app'; St.saveSettings(); St.applySession(); toast('API server saved'); });
  $('#set-social', s.el).addEventListener('change', (e) => run(null, async () => { await Bruce.setSocial(e.target.checked); if (S.user) S.user.social = e.target.checked; toast(e.target.checked ? 'Social is on' : 'Social is off'); }));
  Bruce.notificationSetting().then((ns) => {
    const box = $('#set-push', s.el);
    if (!box) return;
    if (!ns) { box.innerHTML = '<p class="muted">No notification settings.</p>'; return; }
    const rows = (ns.types || []).map((t) => ['t:' + t.key, t.name || t.key, t.description || '', t.enabled])
      .concat([['marketing_push', 'News by push', '', ns.marketing_push], ['marketing_email', 'News by email', '', ns.marketing_email], ['marketing_sms', 'News by SMS', '', ns.marketing_sms]]);
    box.innerHTML = rows.map(([k, t, d, on]) => '<label class="toggle"><span>' + esc(t) + (d ? '<small class="muted">' + esc(d) + '</small>' : '') + '</span><input type="checkbox" data-k="' + k + '"' + (on ? ' checked' : '') + '><i></i></label>').join('') +
      '<p class="muted small">Push notifications go to the official Bruce app.</p>';
    box.querySelectorAll('[data-k]').forEach((cb) => cb.addEventListener('change', () => run(null, async () => {
      const k = cb.dataset.k;
      let body;
      if (k.startsWith('t:')) { ns.types.forEach((t) => { if ('t:' + t.key === k) t.enabled = cb.checked; }); body = { types: ns.types.map((t) => ({ key: t.key, enabled: t.enabled })) }; }
      else body = { [k]: cb.checked };
      await Bruce.updateNotificationSetting(ns.id, body);
    })));
  }).catch(() => { const box = $('#set-push', s.el); if (box) box.innerHTML = '<p class="muted">Could not load notification settings.</p>'; });
}

function placesLine() {
  const p = St.placesState();
  return p.places.length ? p.places.map((x) => x.name).join(', ') + ' · ' + ({ walk: 'Walk', bike: 'Bike', transit: 'Transit', car: 'Car' }[p.mode] || 'Bike') : 'Home, work and how you get around';
}
