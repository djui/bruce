// Class and studio pages (DetailViews.swift). On wide screens they open in the right-hand pane next to the list.
import { $, esc, icon, rich, fmt, time, dayKey, todayKey, addDays, dayChip, dayHeader, classDateLine, instructor, isListed, rating, slug, money, byStart, onDay } from './util.js';
import { Bruce } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { hero, classRow, glassBtn, underlineTabs, chip, empty, loading, avatar, stars, toast, run, confirmSheet, makeMap } from './ui.js';
import { openRules, openSimilar, openInvite, openVisitLimit, openTicket, openReview, checkInFlow } from './sheets.js';

let token = 0;
const closeBtn = (ctx) => glassBtn(ctx.wide ? 'close' : 'back', 'data-dact="back"', ctx.wide ? 'Close' : 'Back');

async function share(title, url) {
  try {
    if (navigator.share) { await navigator.share({ title, url }); return; }
    await navigator.clipboard.writeText(url); toast('Link copied');
  } catch (e) { /* cancelled */ }
}

function currentAlert(alerts) {
  const now = Date.now();
  return (alerts || []).filter((a) => a.message && (!a.start_date || new Date(a.start_date) <= now) && (!a.end_date || new Date(a.end_date) > now))
    .sort((a, b) => ((a.type === 'CRITICAL' ? 0 : 1) - (b.type === 'CRITICAL' ? 0 : 1)) || ((a.order || 0) - (b.order || 0)))[0];
}
const notice = (a) => (a ? '<div class="notice' + (a.type === 'CRITICAL' ? ' critical' : '') + '">' + icon('info') + '<span>' + esc(a.message) + '</span></div>' : '');

/** Visit pill for the hero: "n / m", "∞" or "0 / 0" (StudioLimitPill). */
function limitPill(studioId) {
  const s = St.studio(studioId);
  const tier = ((S.membership && (S.membership.admission_tier || S.membership.membership_tier)) || '').toUpperCase();
  const item = s && s.limits && s.limits.find((i) => (i.label || '').toUpperCase() === tier);
  if (!item) return '';
  const used = (S.visits || []).filter((v) => (v.studio_id || (v.class && v.class.studio_id)) === studioId && v.checked_in_at && v.checked_in_at.slice(0, 7) === new Date().toISOString().slice(0, 7)).length;
  const label = item.limit === 0 ? icon('infinity') : item.limit === -1 ? '0 / 0' : used + ' / ' + item.limit;
  return '<button class="glass-btn wide" data-dact="limit" aria-label="Visit limit at this studio">' + label + '</button>';
}

// ---------------------------------------------------------------- class page

export async function renderClass(el, id, ctx) {
  const t = ++token;
  const known = S.classDetails.get(id);
  if (!known) el.innerHTML = '<div class="pane-pad">' + closeBtn(ctx) + loading('Loading class…') + '</div>';
  else draw(known);
  let c;
  try { c = await St.loadClass(id); } catch (e) { if (t === token) el.innerHTML = '<div class="pane-pad">' + closeBtn(ctx) + empty('info', e.message) + '</div>'; return; }
  if (t !== token) return;
  draw(c);
  St.loadStudio(c.studio_id).then(() => { if (t === token) draw(S.classDetails.get(id) || c); }).catch(() => {});
  // Which classes the auto-book server watches: only asked for a class that can be (or is) waitlisted.
  {
    const r = St.rules(c);
    if (r.start > Date.now() && ((c.available_spots != null && c.available_spots <= 0) || S.standbys.has(c.id))) {
      St.loadWatches().then(() => { if (t === token) draw(S.classDetails.get(id) || c); }).catch(() => {});
    }
  }
  Bruce.attendees(id).then((a) => { if (t === token) { S.attendees = { id, list: a }; drawFriends(c); } }).catch(() => {});

  function draw(c) {
    const s = S.studioDetails.get(c.studio_id) || c.studio || {};
    const lite = St.studio(c.studio_id) || {};
    const booking = S.bookings.get(c.id);
    const standby = S.standbys.get(c.id);
    const bm = S.bookmarks.get(c.id);
    const r = St.rules(c);
    const now = Date.now();
    const started = r.start <= now;
    const att = c.user_attendance_info || c.studio_user_attendance_info || {};
    const cats = (c.class_categories || []).map((x) => (S.categories.find((k) => k.id === x.category_id) || {}).title).filter(Boolean);
    const facilities = (s.studio_facilities || []).map((f) => f.facility && f.facility.title).filter(Boolean);
    const spots = c.available_spots == null ? null : c.available_spots <= 0 ? '<span class="red">' + icon('people') + 'Fully booked</span>'
      : '<span>' + icon('people') + c.available_spots + ' spot' + (c.available_spots === 1 ? '' : 's') + ' left</span>';
    const window = St.openWindowTargets().find((o) => o.c.id === c.id);

    let actions = '';
    if (booking && booking.checked_in_at) {
      actions = '<button class="btn lime" data-dact="ticket">' + icon('ticket') + ' Show ticket</button>' +
        (S.reviewable.find((x) => x.class_id === c.id) ? '<button class="btn glass" data-dact="rate">' + icon('star') + ' Rate the class</button>' : '');
    } else if (booking) {
      actions = (window ? '<button class="btn lime" data-dact="checkin">' + icon('checkSeal') + ' Check in</button>' : '') +
        (started ? '' : '<button class="btn red" data-dact="cancel">Cancel booking</button>');
    } else if (started) {
      actions = '<button class="btn glass" disabled>' + (r.end && r.end < now ? 'This class has ended' : 'This class has started') + '</button>';
    } else if (standby) {
      actions = '<div class="row2"><button class="btn red" data-dact="leave">Leave waitlist</button>' +
        (c.available_spots > 0 ? '<button class="btn lime" data-dact="book">Book</button>' : '<button class="btn glass" data-dact="similar">Similar classes</button>') + '</div>';
    } else if (att.visit_limit_reached) {
      actions = att.price > 0 ? '<button class="btn lime" data-dact="dropin">Buy for ' + esc(money(att.price, att.currency || c.currency)) + '</button>'
        : '<button class="btn glass" disabled>Visit limit reached</button>';
    } else if (c.available_spots != null && c.available_spots <= 0) {
      actions = '<div class="row2"><button class="btn orange" data-dact="join">Join waitlist</button><button class="btn glass" data-dact="similar">Similar classes</button></div>';
    } else if (r.bookUntil < now) {
      actions = '<button class="btn glass" disabled>Booking has closed</button>';
    } else {
      actions = '<button class="btn lime" data-dact="book">Book</button>';
    }

    el.innerHTML = hero({
      photo: c.photo || s.photo || lite.photo, glyph: cats.join(' ') + ' ' + c.title, tag: cats[0], title: c.title,
      sub: esc([s.name || lite.name, s.vicinity || lite.vicinity].filter(Boolean).join(' | ')),
      left: closeBtn(ctx), right: limitPill(c.studio_id) + glassBtn('share', 'data-dact="share"', 'Share') +
        glassBtn('bookmark', 'data-dact="bookmark" aria-pressed="' + !!bm + '"', bm ? 'Remove bookmark' : 'Bookmark'),
    }) + '<div class="pane-pad">' +
      '<h2 class="date-line">' + esc(classDateLine(c)) + '</h2>' +
      '<div class="facts">' + (instructor(c.instructor) ? '<span>' + icon('person') + esc(instructor(c.instructor)) + '</span>' : '') + (spots || '') + '</div>' +
      notice(currentAlert(s.alerts || (c.studio && c.studio.alerts))) + (c.alert ? notice({ message: c.alert, type: 'CRITICAL' }) : '') +
      '<div class="card rules">' +
      '<div>' + icon('calendar') + 'Book until ' + esc(time(r.bookUntil)) + '</div>' +
      '<div>' + icon('checkin') + 'Check-in ' + esc(time(r.checkInFrom)) + ' – ' + esc(time(r.lateCheckIn)) + '</div>' +
      '<div>' + icon('calendar') + 'Cancel until ' + esc(time(r.lateCancel)) + ', ' + esc(fmt(r.lateCancel, { weekday: 'long', day: 'numeric', month: 'long' })) + '</div></div>' +
      '<div id="class-friends" class="who"></div>' +
      (facilities.length ? '<div class="card facilities">' + facilities.map((f) => '<span>' + icon(f.toLowerCase().includes('shower') ? 'spa' : f.toLowerCase().includes('lock') ? 'door' : 'person') + esc(f) + '</span>').join('') + '</div>' : '') +
      watchToggle(c, standby, started, booking) +
      '<div class="actions sticky">' + actions + '</div>' +
      (c.description ? '<div class="rich">' + rich(c.description) + '</div>' : '') +
      '<a class="card row-card" href="' + ctx.link('studio', c.studio_id) + '">' + icon('building') + '<div class="grow"><b>' + esc(s.name || lite.name || 'Studio') + '</b><p class="muted">' + esc(lite.address || s.vicinity || '') + '</p></div>' + icon('chevron') + '</a>' +
      '</div>';
    drawFriends(c);
    wire(c, booking, standby, bm);
  }

  /** "Book when a spot opens": on a full or waitlisted class. The auto-book server books it (see server/README.md). */
  function watchToggle(c, standby, started, booking) {
    const full = c.available_spots != null && c.available_spots <= 0;
    if (started || booking || !(full || standby || S.watches.has(c.id))) return '';
    if (!St.serverOn() && !S.watches.has(c.id)) return '';   // our server is switched off in Settings
    return '<div class="card"><label class="toggle"><span>Book when a spot opens<small class="muted">' +
      (standby ? 'The auto-book server books it the moment a waitlist spot is free. Open My classes to see the result.' : 'Joins the waitlist, then the auto-book server books it the moment a spot is free.') +
      '</small></span><input type="checkbox" data-watch' + (S.watches.has(c.id) ? ' checked' : '') + '><i></i></label></div>';
  }

  function drawFriends(c) {
    const box = $('#class-friends', el);
    if (!box) return;
    const list = S.attendees && S.attendees.id === c.id ? S.attendees.list : [];
    const me = S.auth && S.auth.userId;
    const ids = new Set(S.friends.map((f) => f.friend_user && f.friend_user.id));
    const friends = list.filter((a) => a.user && ids.has(a.user_id));
    const others = list.filter((a) => a.user_id !== me && !ids.has(a.user_id)).length;
    const canInvite = S.friends.length && !(St.rules(c).start < Date.now());
    box.innerHTML = (canInvite ? '<button class="who-item" data-dact="invite"><span class="avatar plus" style="--s:58px">' + icon('plus') + '</span><span>Invite</span></button>' : '') +
      friends.map((a) => '<div class="who-item">' + avatar(a.user, 58) + '<span>' + esc(a.user.first_name || '') + '</span></div>').join('') +
      (others ? '<div class="who-item"><span class="avatar more" style="--s:58px"><span>+' + others + '</span></span><span>Others</span></div>' : '') +
      (!friends.length && canInvite ? '<p class="muted">No friends have booked this class yet</p>' : '');
  }

  // One delegated handler (replaced on each draw), so buttons drawn later, like Invite, work too.
  function wire(c, booking, standby, bm) {
    el.onchange = (e) => {
      const box = e.target.closest('[data-watch]');
      if (!box) return;
      const on = box.checked;
      run(box, async () => {
        try {
          if (on && !standby) await Bruce.joinWaitlist(c.id);
          await St.setWatch(c.id, on);
          if (on) toast("You're on the waitlist. It will be booked for you as soon as a spot opens up.");
        } finally { await after(); }
      });
    };
    el.onclick = (e) => {
      const b = e.target.closest('[data-dact]');
      if (!b) return;
      const a = b.dataset.dact;
      if (a === 'back') ctx.close();
      else if (a === 'share') share(c.title, 'https://app.brucestudios.com/classes/' + c.id + '/' + slug(c.title));
      else if (a === 'limit') openVisitLimit(c.studio_id);
      else if (a === 'bookmark') run(b, async () => {
        if (bm) { await Bruce.removeBookmark(bm.id); toast('Bookmark removed'); } else { await Bruce.addBookmark(c.id); toast('Bookmark added'); }
        await St.loadMine(); draw(S.classDetails.get(c.id) || c);
      });
      else if (a === 'book') openRules(c, 'book', async () => { await Bruce.book(c.id); toast('Booked ' + c.title); await after(); });
      else if (a === 'cancel') openRules(c, 'cancel', async () => { await Bruce.cancel(booking.id); toast('Booking cancelled'); await after(); });
      else if (a === 'join') run(b, async () => { await Bruce.joinWaitlist(c.id); toast("You're on the waitlist. You'll get a notification if a spot opens up."); await after(); });
      else if (a === 'leave') confirmSheet('Leave the waitlist?', 'You will lose your place in the queue for ' + c.title + '.', 'Leave waitlist')
        .then((yes) => yes && run(null, async () => {
          await Bruce.leaveWaitlist(standby.id);
          if (S.watches.has(c.id)) await St.setWatch(c.id, false).catch(() => {});
          toast('Left the waitlist'); await after();
        }));
      else if (a === 'similar') openSimilar(c, ctx.link);
      else if (a === 'invite') openInvite(c);
      else if (a === 'ticket') openTicket(booking.id);
      else if (a === 'rate') { const r = S.reviewable.find((x) => x.class_id === c.id); if (r) openReview(r); }
      else if (a === 'checkin') checkInFlow(c.studio_id, b);
      else if (a === 'dropin') toast("Buying a single visit isn't available in this unofficial client. Use the Bruce app to buy it.");
    };
  }
  async function after() {
    S.classCache.clear();
    await Promise.all([St.loadMine().catch(() => {}), St.loadClass(id).catch(() => {}), St.loadAccount().catch(() => {})]);
    // Booked, or no longer waitlisted: the server has nothing left to watch (it drops a booked class by itself).
    if (S.watches.has(id) && !S.standbys.has(id)) { S.watches.delete(id); St.setWatch(id, false).catch(() => {}); }
    if (t === token) draw(S.classDetails.get(id));
  }
}

// ---------------------------------------------------------------- studio page

export async function renderStudio(el, id, ctx) {
  const t = ++token;
  const state = { tab: 'info', day: ctx.params.get('day') || todayKey() };
  el.innerHTML = '<div class="pane-pad">' + closeBtn(ctx) + loading('Loading studio…') + '</div>';
  let s;
  try { s = await St.loadStudio(id); } catch (e) { if (t === token) el.innerHTML = '<div class="pane-pad">' + closeBtn(ctx) + empty('info', e.message) + '</div>'; return; }
  if (t !== token) return;
  if (!S.visits) Bruce.visits().then((v) => { S.visits = v.filter((x) => x.checked_in_at && !x.deleted); }).catch(() => {});
  draw();
  loadSchedule();
  loadDay();

  function draw() {
    const lite = St.studio(id) || {};
    const fav = S.favorites.has(id);
    const cats = (s.studio_categories || []).map((c) => c.category && c.category.title).filter(Boolean);
    const sub = [rating(s.rating) ? icon('star') + ' ' + rating(s.rating) : null, esc(s.vicinity), esc(cats[0])].filter(Boolean).join(' | ');
    const photo = ((s.studio_photos || []).find((p) => p.main) || (s.studio_photos || [])[0] || {}).photo;
    el.innerHTML = hero({
      photo: (photo && photo.file_id) || s.photo, glyph: cats.join(' ') || s.name, title: s.name, sub,
      left: closeBtn(ctx), right: limitPill(id) + glassBtn('share', 'data-sact="share"', 'Share') + glassBtn('heart', 'data-sact="fav" aria-pressed="' + fav + '"', fav ? 'Remove favourite' : 'Add favourite'),
    }) + '<div class="sticky-tools pane-tabs">' + underlineTabs([{ key: 'info', title: 'Information' }, { key: 'reviews', title: 'Reviews', badge: s.rating && s.rating.total ? s.rating.total : '' }], state.tab, 'data-stab') + '</div>' +
      '<div class="pane-pad" id="studio-body"></div>';
    el.querySelectorAll('[data-stab]').forEach((b) => b.addEventListener('click', () => { state.tab = b.dataset.stab; draw(); }));
    el.querySelectorAll('[data-sact]').forEach((b) => b.addEventListener('click', () => {
      const a = b.dataset.sact;
      if (a === 'share') share(s.name, 'https://www.brucestudios.com/studios/' + s.id + '/' + slug(s.name));
      else if (a === 'fav') run(b, async () => {
        if (S.favorites.has(id)) { await Bruce.removeFavorite(S.favorites.get(id)); S.favorites.delete(id); toast('Removed from favourites'); }
        else { const f = await Bruce.addFavorite(id); S.favorites.set(id, f.id); toast('Added to favourites'); }
        St.emit(); draw();
      });
    }));
    el.querySelector('[data-dact="back"]').addEventListener('click', () => ctx.close());
    const lb = el.querySelector('[data-dact="limit"]');
    if (lb) lb.addEventListener('click', () => openVisitLimit(id));
    if (state.tab === 'info') drawInfo(lite); else drawReviews();
  }

  function drawInfo(lite) {
    const body = $('#studio-body', el);
    const a = (s.studio_addresses || []).map((x) => x.address).filter(Boolean)[0];
    const facilities = (s.studio_facilities || []).map((f) => f.facility && f.facility.title).filter(Boolean);
    const ticket = St.todaysCheckIn(id);
    const tg = St.target(id, s.vicinity || '');
    const today = todayKey();
    body.innerHTML =
      (ticket ? '<button class="btn lime" data-x="ticket">' + icon('ticket') + ' Show ticket</button>' : tg ? '<button class="btn lime" data-x="checkin">' + icon('checkSeal') + ' Check in</button>' : '') +
      '<div id="hours"></div>' + notice(currentAlert(s.alerts)) +
      ((s.integration_door_type || '').toLowerCase() === 'parakey' ? '<div class="card parakey">' + icon('door') + '<div class="grow"><b>Doors open with Parakey</b><p class="muted">Use the Parakey app at the door. It is linked to your Bruce account at check-in.</p></div><a class="btn glass sm" href="https://parakey.co" target="_blank" rel="noopener">Parakey</a></div>' : '') +
      (facilities.length ? '<div class="card facilities">' + facilities.map((f) => '<span>' + icon(f.toLowerCase().includes('shower') ? 'spa' : f.toLowerCase().includes('lock') ? 'door' : 'person') + esc(f) + '</span>').join('') + '</div>' : '') +
      (s.description ? '<div class="rich">' + rich(s.description) + '</div>' : '') +
      (a && a.latitude ? '<div class="map small" id="studio-map"></div><p class="address">' + icon('pin') + '<span>' + esc([a.address, a.zip_code, a.city].filter(Boolean).join(', ')) + '</span>' +
        '<a href="https://maps.apple.com/?q=' + encodeURIComponent(s.name) + '&ll=' + a.latitude + ',' + a.longitude + '" target="_blank" rel="noopener">Apple Maps</a>' +
        '<a href="https://www.google.com/maps/search/?api=1&query=' + a.latitude + ',' + a.longitude + '" target="_blank" rel="noopener">Google Maps</a></p>' : '') +
      '<h2 class="sec-title">CLASSES</h2><div class="chips days">' + Array.from({ length: 7 }, (_, i) => addDays(today, i)).map((d) => { const [x, y] = dayChip(d); return chip(x + '<small>' + y + '</small>', d === state.day, 'data-sday="' + d + '"'); }).join('') + '</div>' +
      '<div id="studio-classes" class="list">' + loading('Loading classes…') + '</div>';
    body.querySelectorAll('[data-sday]').forEach((b) => b.addEventListener('click', () => { state.day = b.dataset.sday; drawInfo(lite); loadDay(); }));
    const tb = body.querySelector('[data-x="ticket"]'); if (tb) tb.addEventListener('click', () => openTicket(ticket.id));
    const cb = body.querySelector('[data-x="checkin"]'); if (cb) cb.addEventListener('click', () => checkInFlow(id, cb));
    if (a && a.latitude) makeMap($('#studio-map', body), [{ lat: a.latitude, lon: a.longitude, label: s.name }], { small: true, zoom: 15 });
    drawHours(); drawDay();
  }

  async function loadSchedule() {
    if (!s.has_openings && !(St.studio(id) || {}).openings) return;
    const from = new Date(); from.setHours(0, 0, 0, 0);
    const to = new Date(from.getTime() + 2 * 86400000);
    try { state.schedule = await Bruce.schedule(id, from, to); } catch (e) { state.schedule = []; }
    if (t === token) drawHours();
  }
  function drawHours() {
    const box = $('#hours', el);
    if (!box || !state.schedule || !state.schedule.length) { if (box) box.innerHTML = ''; return; }
    const now = Date.now();
    const cur = state.schedule.find((x) => new Date(x.start) <= now && now < new Date(x.end));
    const next = state.schedule.find((x) => new Date(x.start) > now);
    const soon = cur && new Date(cur.end) - now < 3600000;
    const line = cur ? (soon ? '<span class="orange">' : '<span class="teal">') + 'Solo training until ' + time(cur.end) + '</span>'
      : '<span class="red">Closed for solo training right now</span>' + (next ? '<span class="muted"> · opens ' + (dayKey(next.start) === todayKey() ? '' : fmt(next.start, { weekday: 'short' }) + ' ') + time(next.start) + '</span>' : '');
    box.innerHTML = '<details class="card hours"><summary><i class="dot ' + (cur ? (soon ? 'orange' : 'teal') : 'red') + '"></i>' + line + icon('down') + '</summary>' +
      state.schedule.map((x) => '<div class="hours-row"><span>' + esc(dayHeader(x.start)) + '</span><b>' + (x.is_all_day ? 'All day' : time(x.start) + ' – ' + time(x.end)) + '</b></div>').join('') + '</details>';
  }
  async function loadDay() {
    const day = state.day;
    state.classes = null; drawDay();
    try {
      const list = await Bruce.classes(day, { studioId: id });
      if (t !== token || state.day !== day) return;
      state.classes = list.filter(isListed).filter((c) => onDay(c, day)).filter((c) => day !== todayKey() || !c.end_time || new Date(c.end_time) > Date.now()).sort(byStart);
    } catch (e) { state.classes = []; state.error = e.message; }
    drawDay();
  }
  function drawDay() {
    const box = $('#studio-classes', el);
    if (!box) return;
    if (!state.classes) { box.innerHTML = loading('Loading classes…'); return; }
    box.innerHTML = state.classes.length ? state.classes.map((c) => classRow(c, ctx.link('class', c.id), { hideStudio: true })).join('') : empty('calendar', 'No classes this day.');
  }

  async function drawReviews() {
    const body = $('#studio-body', el);
    const r = s.rating || {};
    const dist = r.distribution || {};
    const total = Object.values(dist).reduce((a, b) => a + b, 0) || r.total || 0;
    body.innerHTML = (r.average ? '<div class="card rating-sum"><div class="big"><b>' + rating(r) + '</b>' + stars(Math.round(r.average / 100), 16) + '<span class="muted">' + (r.total || 0) + ' ratings</span></div><div class="bars">' +
      [5, 4, 3, 2, 1].map((n) => '<div><span>' + n + '</span><i><b style="width:' + (total ? Math.round(100 * (dist[n] || 0) / total) : 0) + '%"></b></i></div>').join('') + '</div></div>' : '') +
      '<div id="reviews">' + loading('Loading reviews…') + '</div>';
    let list;
    try { list = await Bruce.reviews(id); } catch (e) { list = []; }
    if (t !== token || state.tab !== 'reviews') return;
    $('#reviews', el).innerHTML = list.length ? list.map((v) => {
      const u = v.booking && v.booking.user;
      const act = v.booking && v.booking.class && v.booking.class.opening ? 'Solo training' : (v.booking && v.booking.class && v.booking.class.title) || 'Class';
      return '<div class="review">' + avatar(u || { first_name: '?' }, 40) + '<div class="grow"><div class="row-between"><b>' + esc((u && (u.display_name || u.first_name)) || 'Member') + '</b><span class="muted small">' + esc(fmt(v.created_at, { day: 'numeric', month: 'short', year: 'numeric' })) + '</span></div>' +
        stars(v.rating) + '<p class="muted small">' + esc(act) + '</p>' + (v.comment ? '<p>' + esc(v.comment) + '</p>' : '') + (v.response ? '<p class="response"><b>Studio:</b> ' + esc(v.response) + '</p>' : '') + '</div></div>';
    }).join('') : empty('star', 'No written reviews yet.');
  }
}

