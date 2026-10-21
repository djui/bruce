// Challenges with friends (our server, CONTRACT.md): the Challenges segment in Friends, the challenge page with its
// leaderboard (in the right-hand pane on wide screens), participant details, the New challenge sheet, invites and the
// share link #challenge/<id> (preview + Join for someone who is not in it yet).
import { $, esc, icon, fmt, time, ls, todayKey } from './util.js';
import { Server } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { sheet, toast, run, empty, loading, avatar, confirmSheet, glassBtn, chip } from './ui.js';
import { challengeShareUrl, challengeRoute } from './links.js';
import { fromRace, keyOf, countdownShort, shortDay } from './races.js';
import { isCrew, weeklyText, thisWeekText, lastWeekText, doneThisWeekText, crewName, defaultWeekly, WEEKLY } from './crews.js';
import { rewardCardHTML, shopClick } from './shopui.js';

const CREW_PRIVACY = 'Friends in this crew see your visits: sessions each week, class types and studios. Each friend accepts separately. Leave anytime; your numbers are deleted.';
const CREW_INTRO = 'A crew trains for the race together: a challenge until race day where everyone aims for the same sessions a week. On Sundays the Brüce iPhone app tells you how the crew did.';

const METRICS = { classes: ['Most classes', 'classes'], visits: ['Most visits', 'visits'], minutes: ['Most minutes', 'minutes'], target: ['Everyone hits', 'visits'] };
const me = () => S.auth && S.auth.userId;
const shortDate = (key) => (key ? new Date(key + 'T12:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }) : '');
const monthName = (key) => new Date(key + 'T12:00:00Z').toLocaleDateString('en-GB', { month: 'long', timeZone: 'UTC' });
function userFor(id, name) {
  if (id === me()) return S.user || { first_name: name };
  const u = St.friendUser(id);
  if (u) return u;
  const [f, ...l] = String(name || '?').split(' ');
  return { first_name: f, last_name: l.join(' ') };
}
const counts = (c) => (c.category == null ? 'everything counts' : (c.categoryTitle || 'one category') + ' counts');
const unit = (c) => (c.metric === 'minutes' ? 'min' : c.metric === 'classes' ? 'classes' : 'visits');

/** Before a challenge sends the Bruce login to our server while it is switched off in Settings: say so, once. */
export async function serverConsent() {
  if (St.serverOn() || ls.get('bruce.challengeConsent', false)) return true;
  const yes = await confirmSheet('Challenges use our server',
    "Our server is switched off in Settings. Challenges need it: joining one stores your Bruce login on our server, which reads your visits once a day for the leaderboard. Leave a challenge and your numbers are deleted.", 'Continue', 'lime');
  if (yes) ls.set('bruce.challengeConsent', true);
  return yes;
}
const canAsk = () => St.serverOn() || ls.get('bruce.challengeConsent', false);

export function loadIfAllowed() {
  if (!canAsk() || S.challengesLoading) return;
  S.challengesLoading = St.loadChallenges().catch((e) => { S.challengesError = e.message; St.emit(); }).finally(() => { S.challengesLoading = null; });
}

/** Gradient summary card (list and page header). */
function headCard(c, big) {
  const p = c.period || {};
  if (isCrew(c)) {
    const n = (c.participants || []).filter((x) => x.status === 'accepted').length || c.participantCount || 0;
    return '<div class="ch-card crew' + (big ? ' big' : '') + '"><div class="row-between"><span class="ch-month">' + icon('run') + 'Crew</span>' +
      '<span class="ch-left">' + (p.daysLeft != null ? (p.daysLeft === 0 ? 'Race day' : p.daysLeft + ' days to race day') : '') + '</span></div>' +
      '<h3>' + esc(c.title || 'Race crew') + '</h3><p>' + esc([n + (n === 1 ? ' person' : ' people'), weeklyText(c.weekly)].join(' · ')) + '</p></div>';
  }
  const n = (c.participants || []).filter((x) => x.status === 'accepted').length || c.participantCount || 0;
  const started = p.start && p.day > 0 ? 'started ' + shortDate(c.repeatMonthly ? p.start : c.start || p.start) : 'starts ' + shortDate(p.start);
  const metricTitle = c.metric === 'target' ? 'Everyone hits ' + c.target : c.title || METRICS[c.metric][0];
  return '<div class="ch-card' + (big ? ' big' : '') + '"><div class="row-between"><span class="ch-month">' + icon('trophy') + esc(c.repeatMonthly && p.start ? monthName(p.start) : p.label || '') + '</span>' +
    '<span class="ch-left">' + (p.daysLeft != null ? (p.daysLeft === 0 ? 'Last day' : p.daysLeft + ' days left') : '') + '</span></div>' +
    '<h3>' + esc(c.title || metricTitle) + '</h3><p>' + esc([n + (n === 1 ? ' person' : ' people'), counts(c), started].join(' · ')) + '</p></div>';
}

/** The Challenges segment of the Friends tab. */
export function challengesHTML(sel) {
  if (!canAsk()) {
    return '<div class="card ch-intro">' + icon('trophy') + '<h3>Challenge your friends</h3><p class="muted">Most classes this month, or everyone hits 12. Challenges run on our server, which is switched off in Settings.</p>' +
      '<button class="btn lime" data-ch="consent">Continue</button></div>';
  }
  loadIfAllowed();
  if (!S.challenges) return S.challengesError ? '<div class="card">' + empty('info', S.challengesError) + '<button class="btn glass" data-ch="retry">Try again</button></div>' : loading('Loading challenges…');
  const list = S.challenges.challenges || [];
  const start = '<button class="btn lime" data-ch="new">' + icon('plus') + ' New challenge</button>';
  if (!list.length) return '<div class="card ch-intro">' + icon('trophy') + '<h3>No challenges yet</h3><p class="muted">Challenge friends to a month of classes. Everyone who joins sees totals, class types and studios.</p>' + start + '</div>';
  return list.map((c) => {
    const invited = c.myStatus === 'invited';
    return '<div class="ch-item' + (sel && sel.id === c.id ? ' selected' : '') + '"><a href="' + challengeRoute(c.id) + '">' + headCard(c) + '</a>' +
      (invited ? '<div class="ch-invite"><span class="grow"><b>' + esc(c.ownerName) + '</b> invited you' + (isCrew(c) ? ' to a crew' : '') + '</span><button class="btn glass sm" data-ch="decline" data-id="' + esc(c.id) + '">Decline</button><button class="btn lime sm" data-ch="accept" data-id="' + esc(c.id) + '">Accept</button></div>' : '') + '</div>';
  }).join('') + start;
}

/** Clicks in the segment (delegated from the Friends view). */
export function challengesClick(e, rerender) {
  const b = e.target.closest('[data-ch]');
  if (!b) return false;
  const a = b.dataset.ch, id = b.dataset.id;
  if (a === 'consent') serverConsent().then((ok) => { if (ok) { loadIfAllowed(); rerender(); } });
  else if (a === 'retry') { S.challengesError = null; loadIfAllowed(); rerender(); }
  else if (a === 'new') openNewChallenge();
  else if (a === 'accept') respond(b, id, true);
  else if (a === 'decline') respond(b, id, false);
  return true;
}
async function respond(btn, id, yes) {
  if (yes && !(await serverConsent())) return;
  const crew = isCrew(((S.challenges && S.challenges.challenges) || []).find((c) => c.id === id));
  const what = crew ? 'crew' : 'challenge';
  if (!yes && !(await confirmSheet('Decline the ' + what + '?', 'You can join again later with the share link.', 'Decline'))) return;
  await run(btn, async () => {
    if (yes) await Server.accept(id); else await Server.leave(id);
    await St.loadChallenges();
    toast(yes ? "You're in. Your visits count from today's refresh." : (crew ? 'Crew declined' : 'Challenge declined'));
    if (yes) location.hash = challengeRoute(id);
  });
}

// ---------------------------------------------------------------- challenge page

let token = 0;
export async function renderChallenge(el, id, ctx) {
  const t = ++token;
  const close = glassBtn(ctx.wide ? 'close' : 'back', 'data-cact="back"', ctx.wide ? 'Close' : 'Back');
  el.innerHTML = '<div class="pane-pad">' + close + loading('Loading challenge…') + '</div>';
  el.onclick = (e) => { if (e.target.closest('[data-cact="back"]')) ctx.close(); };
  if (!canAsk()) {
    el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '</div><div class="card ch-intro">' + icon('trophy') + '<h3>Open the challenge</h3><p class="muted">Challenges run on our server, which is switched off in Settings.</p><button class="btn lime" data-cact="consent">Continue</button></div></div>';
    el.querySelector('[data-cact="consent"]').addEventListener('click', () => serverConsent().then((ok) => { if (ok) renderChallenge(el, id, ctx); }));
    return;
  }
  let d;
  try { d = await Server.challenge(id); } catch (e) {
    if (t === token) el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '</div>' + empty('info', e.status === 404 ? 'This challenge does not exist anymore.' : e.message) + '</div>';
    return;
  }
  if (t !== token) return;
  if (d.joinable !== undefined) { preview(d); return; }
  draw(d);
  // The finisher tee (shopui.js, mockup 4): only once the server unlocked it for this member.
  St.loadShop().then(() => { if (t === token && el.isConnected && !d.crew) draw(d); });

  function preview(d) {
    const c = d.challenge;
    el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '</div>' + headCard(Object.assign({ participants: [] }, c), true) +
      '<div class="card ch-preview"><p><b>' + esc(c.ownerName || 'A friend') + '</b> started this ' + (isCrew(c) ? 'crew' : 'challenge') + (c.participantCount ? ' with ' + (c.participantCount - 1) + (c.participantCount === 2 ? ' friend' : ' friends') : '') + '.</p>' +
      '<p class="muted small">' + esc(isCrew(c) ? 'Everyone aims for ' + weeklyText(c.weekly) + ' until race day.' : METRICS[c.metric] ? (c.metric === 'target' ? 'Everyone tries to reach ' + c.target + ' visits.' : 'Whoever has the most ' + METRICS[c.metric][1] + ' wins.') : '') + '</p></div>' +
      (d.joinable ? '<button class="btn lime" data-cact="join">' + (isCrew(c) ? 'Join crew' : 'Join challenge') + '</button>' : '<p class="notice">' + icon('info') + '<span>Only friends of ' + esc(c.ownerName || 'the owner') + ' on Bruce can join. Add each other as friends in the Bruce app first.</span></p>') +
      '<p class="muted small foot">' + icon('lock') + ' ' + esc(isCrew(c) ? CREW_PRIVACY : 'Friends in this challenge see your visits: totals, class types and studios. Leave anytime; your numbers are deleted.') + '</p></div>';
    const j = el.querySelector('[data-cact="join"]');
    if (j) j.addEventListener('click', async () => {
      if (!(await serverConsent())) return;
      run(j, async () => { await Server.join(id); await St.loadChallenges().catch(() => {}); toast('You joined ' + (c.title || 'the challenge')); renderChallenge(el, id, ctx); });
    });
  }

  function drawCrew(d) {
    const c = d.challenge;
    el.innerHTML = crewPageHTML(d, close);
    el.querySelectorAll('[data-p]').forEach((b) => b.addEventListener('click', () => openParticipant((d.leaderboard || []).find((r) => r.userId === +b.dataset.p), c)));
    el.onclick = (e) => {
      const b = e.target.closest('[data-cact]');
      if (!b) return;
      const a = b.dataset.cact;
      if (a === 'back') ctx.close();
      else if (a === 'share') shareLink(c);
      else if (a === 'accept' || a === 'decline') respond(b, c.id, a === 'accept').then(() => renderChallenge(el, id, ctx));
      else if (a === 'leave') confirmSheet('Leave ' + (c.title || 'the crew') + '?', 'Your numbers in this crew are deleted from our server.', 'Leave crew').then((yes) => yes && run(b, async () => {
        await Server.leave(c.id); await St.loadChallenges().catch(() => {}); toast('You left the crew'); ctx.close();
      }));
    };
  }

  function draw(d) {
    const c = d.challenge;
    if (d.crew) { drawCrew(d); return; }
    const board = d.leaderboard || [];
    const mine = board.find((r) => r.userId === me());
    const accepted = board.filter((r) => r.status === 'accepted');
    const invited = c.myStatus === 'invited';
    const days = (mine && mine.daily) || [];
    const maxDay = Math.max(1, ...days);
    const score = (r) => (c.metric === 'target' ? r.score + '<small>/' + c.target + '</small>' : c.metric === 'minutes' ? r.score + '<small>min</small>' : String(r.score));
    el.innerHTML = '<div class="pane-pad"><div class="pane-bar">' + close + '<span class="spacer"></span>' + glassBtn('share', 'data-cact="share"', 'Share link') + '</div>' +
      headCard(c, true) +
      (invited ? '<div class="ch-invite card"><span class="grow"><b>' + esc(c.ownerName) + '</b> invited you. Your visits count once you accept.</span><button class="btn glass sm" data-cact="decline">Decline</button><button class="btn lime sm" data-cact="accept">Accept</button></div>' : '') +
      '<div class="lb">' + board.map((r) => {
        const isMe = r.userId === me();
        return '<button class="lbrow' + (isMe ? ' me' : '') + (r.status !== 'accepted' ? ' pending' : '') + '" data-p="' + r.userId + '">' +
          '<span class="rk">' + (r.rank || '–') + '</span>' + avatar(userFor(r.userId, r.name), 38) +
          '<span class="nm"><b>' + esc(isMe ? 'You' : r.name) + (r.done ? ' ' + icon('checkSeal') : '') + '</b><small>' + esc(lineFor(r, c, accepted)) + '</small></span><span class="sc">' + (r.status === 'accepted' ? score(r) : '') + '</span></button>';
      }).join('') + '</div>' + rewardCardHTML(c, 'friends') +
      (mine && mine.status === 'accepted' ? '<h2 class="sec-title">Your days <small class="muted">' + mine.score + ' ' + unit(c) + ' in ' + days.length + ' days</small></h2>' +
        '<div class="card"><div class="spark">' + days.map((n, i) => '<i class="' + (n ? 'on' : '') + '" style="height:' + (n ? Math.max(12, Math.round(100 * n / maxDay)) : 4) + '%" title="' + (i + 1) + ': ' + n + '"></i>').join('') + '</div>' +
        '<div class="row-between muted small"><span>' + esc(shortDate(c.period.start)) + '</span><span>Today</span></div></div>' : '') +
      (d.months && d.months.length ? '<h2 class="sec-title">Month by month</h2>' + d.months.map((m) => '<div class="card ch-month-card"><div class="row-between"><b>' + esc(m.label) + '</b><span class="muted small">' +
        m.entries.reduce((a, x) => a + x.visits, 0) + ' visits in all</span></div>' + m.entries.map((x, i) => '<div class="ch-mrow"><span class="rk">' + (i === 0 && x.score ? icon('trophy') : i + 1) + '</span><span class="grow">' + esc(x.userId === me() ? 'You' : x.name) + '</span><span class="muted small">' + x.classes + ' classes · ' + x.dropins + ' drop-ins · ' + Math.round(x.minutes / 60) + ' h</span><b>' + x.score + '</b></div>').join('') + '</div>').join('') : '') +
      '<p class="muted small foot">' + icon('lock') + ' Friends in this challenge see your visits: totals, class types and studios.' + (d.updatedAt ? ' Updated ' + esc(fmt(d.updatedAt, { day: 'numeric', month: 'short' }) + ', ' + time(d.updatedAt)) + '.' : '') + '</p>' +
      '<div class="row2"><button class="btn glass" data-cact="share">' + icon('share') + ' Share link</button><button class="btn glass red-text" data-cact="leave">Leave</button></div></div>';
    el.querySelectorAll('[data-p]').forEach((b) => b.addEventListener('click', () => openParticipant(board.find((r) => r.userId === +b.dataset.p), c)));
    el.onclick = (e) => {
      if (shopClick(e, () => draw(d))) return;
      const b = e.target.closest('[data-cact]');
      if (!b) return;
      const a = b.dataset.cact;
      if (a === 'back') ctx.close();
      else if (a === 'share') shareLink(c);
      else if (a === 'accept' || a === 'decline') respond(b, c.id, a === 'accept').then(() => renderChallenge(el, id, ctx));
      else if (a === 'leave') confirmSheet('Leave ' + (c.title || 'the challenge') + '?', 'Your numbers in this challenge are deleted from our server.', 'Leave challenge').then((yes) => yes && run(b, async () => {
        await Server.leave(c.id); await St.loadChallenges().catch(() => {}); toast('You left the challenge'); ctx.close();
      }));
    };
  }
}

/** A crew's page: everyone's week, last week, the race, the share link and Leave. */
function crewPageHTML(d, close) {
  const c = d.challenge, w = d.crew, weekly = w.weekly || 1;
  const invited = c.myStatus === 'invited';
  const race = (S.races || []).find((r) => r.id === c.raceId);
  const invitedNames = (c.participants || []).filter((p) => p.status === 'invited').map((p) => p.name);
  const bar = (n) => '<span class="crew-bar" aria-hidden="true">' + Array.from({ length: weekly }, (_, i) => '<i class="' + (i < n ? 'on' : '') + '"></i>').join('') + '</span>';
  return '<div class="pane-pad"><div class="pane-bar">' + close + '<span class="spacer"></span>' + glassBtn('share', 'data-cact="share"', 'Share link') + '</div>' +
    headCard(c, true) +
    (invited ? '<div class="ch-invite card"><span class="grow"><b>' + esc(c.ownerName) + '</b> invited you to this crew. Your visits count once you accept.</span><button class="btn glass sm" data-cact="decline">Decline</button><button class="btn lime sm" data-cact="accept">Accept</button></div>' : '') +
    '<div class="sec-row"><h2 class="sec-title">This week</h2><small class="muted">' + esc(doneThisWeekText(w)) + '</small></div>' +
    '<div class="lb">' + w.members.map((m) => {
      const isMe = m.userId === me();
      return '<button class="lbrow crew-row' + (isMe ? ' me' : '') + '" data-p="' + m.userId + '">' + avatar(userFor(m.userId, m.name), 38) +
        '<span class="nm"><b>' + esc(isMe ? 'You' : m.name) + ((m.thisWeek || 0) >= weekly ? ' ' + icon('checkSeal') : '') + '</b>' + bar(m.thisWeek || 0) + '</span>' +
        '<span class="sc">' + (m.thisWeek || 0) + '<small>/' + weekly + '</small></span></button>';
    }).join('') + '</div>' +
    (lastWeekText(w) ? '<p class="crew-last">' + icon('flag') + esc(lastWeekText(w)) + '</p>' : '') +
    (invitedNames.length ? '<p class="muted small">Invited: ' + esc(invitedNames.join(', ')) + '. They count once they accept.</p>' : '') +
    (race ? '<a class="card crew-race" href="' + '#/mine/race/' + encodeURIComponent(race.id) + '?tab=races"><span class="grow"><b>' + esc(race.name) + '</b><small class="muted block">' +
      esc(countdownShort(race, todayKey())) + '</small></span>' + icon('chevron') + '</a>' : '') +
    '<p class="muted small foot">' + icon('lock') + ' ' + esc(CREW_PRIVACY) + (d.updatedAt ? ' Updated ' + esc(fmt(d.updatedAt, { day: 'numeric', month: 'short' }) + ', ' + time(d.updatedAt)) + '.' : '') + '</p>' +
    '<div class="row2"><button class="btn glass" data-cact="share">' + icon('share') + ' Share link</button><button class="btn glass red-text" data-cact="leave">Leave crew</button></div></div>';
}

/** Race page (racesui.js): the member's crew for this race, an invite to one, or Start a crew. */
export function crewBlockHTML(r) {
  const list = ((S.challenges && S.challenges.challenges) || []).filter((c) => isCrew(c) && c.raceId === r.id);
  const crew = list.find((c) => c.myStatus === 'accepted') || list[0];
  if (crew && crew.myStatus === 'invited') {
    return '<div class="crew-block"><p><b>' + esc(crew.ownerName || 'A friend') + '</b> invited you to a crew: ' + esc(crew.title) + ' · ' + esc(weeklyText(crew.weekly)) + '</p>' +
      '<div class="row2"><button class="btn lime sm" data-crew="accept" data-id="' + esc(crew.id) + '">Accept</button><button class="btn glass sm" data-crew="decline" data-id="' + esc(crew.id) + '">Decline</button></div>' +
      '<p class="muted small">' + esc(CREW_PRIVACY) + '</p></div>';
  }
  if (crew) {
    const n = (crew.participants || []).filter((x) => x.status === 'accepted').length;
    return '<a class="crew-block crew-link" href="' + challengeRoute(crew.id) + '"><span class="grow"><b>' + icon('run') + esc(crew.title) + '</b><small class="muted block">' +
      esc(n + (n === 1 ? ' person' : ' people') + ' · ' + weeklyText(crew.weekly)) + '</small></span>' + icon('chevron') + '</a>';
  }
  return '<div class="crew-block"><p><b>Train with friends</b><br><span class="muted small">' + esc(CREW_INTRO) + '</span></p>' +
    '<button class="btn glass sm" data-crew="new" data-race="' + esc(r.id) + '">' + icon('plus') + ' Start a crew</button></div>';
}

/** Clicks in a race page's crew block; true when it was one. */
export function crewClick(e, rerender) {
  const b = e.target.closest('[data-crew]');
  if (!b) return false;
  const a = b.dataset.crew;
  if (a === 'new') {
    const r = (S.races || []).find((x) => x.id === b.dataset.race);
    if (r) openNewCrew(r);
  } else if (a === 'accept' || a === 'decline') respond(b, b.dataset.id, a === 'accept').then(() => rerender && rerender());
  return true;
}

/** Start a crew: name, sessions a week (from the Train for it plan) and friends; ends on your race day. */
export async function openNewCrew(r) {
  if (!(await serverConsent())) return;
  const mine = St.myRaces().find((m) => keyOf(m) === r.id);
  const f = { name: crewName(r), weekly: defaultWeekly(mine && mine.plan), invite: new Set() };
  const s = sheet('Start a crew', loading(), { cls: 'tall' });
  if (!S.challenges) await St.loadChallenges().catch(() => {});
  if (!S.friends.length) await St.loadSocial().catch(() => {});
  const uses = new Set((S.challenges && S.challenges.usesBruce) || []);
  const going = new Set(St.friendsGoing(r.id).map((u) => u.id));
  const friends = S.friends.map((x) => x.friend_user).filter(Boolean).sort((a, b) => (uses.has(b.id) - uses.has(a.id)) || (a.first_name || '').localeCompare(b.first_name || ''));
  const day = (mine && mine.day) || r.date;
  draw();

  function draw() {
    s.body.innerHTML = '<p class="sheet-text">' + esc(CREW_INTRO) + '</p>' +
      '<div class="card form-rows"><label class="frow"><span class="grow">Crew name</span><input type="text" id="nc-name" maxlength="80" value="' + esc(f.name) + '"></label>' +
      '<div class="frow"><span class="grow">' + esc(weeklyText(f.weekly)) + '<small class="muted block">From your Train for it plan. Everything counts, Monday to Sunday.</small></span>' +
      '<span class="stepper"><button data-step="-1" aria-label="Fewer">−</button><b>' + f.weekly + '</b><button data-step="1" aria-label="More">+</button></span></div>' +
      '<div class="frow"><span class="grow">Until race day</span><span class="muted">' + esc(shortDay(day, true, true)) + '</span></div></div>' +
      '<h3 class="section-head">Invite friends</h3>' + (friends.length ? '<div class="card menu">' + friends.map((u) => {
        const on = f.invite.has(u.id);
        return '<button class="mrow pick-row' + (on ? ' on' : '') + '" data-u="' + u.id + '" aria-pressed="' + on + '">' + avatar(u, 34) + '<span class="grow"><b>' + esc(u.first_name || '') + ' ' + esc(u.last_name || '') + '</b><small class="muted block">' +
          (uses.has(u.id) ? (going.has(u.id) ? 'Going · uses Brüce' : 'Uses Brüce') : 'Not on Brüce yet · send link') + '</small></span><span class="check">' + icon(uses.has(u.id) || on ? 'check' : 'share') + '</span></button>';
      }).join('') + '</div>' : '<p class="muted">Add friends in the Bruce app to invite them.</p>') +
      '<p class="muted small foot">' + icon('lock') + ' ' + esc(CREW_PRIVACY) + '</p>' +
      '<button class="btn lime" data-go>Start crew · ' + (f.invite.size + 1) + (f.invite.size ? ' people' : ' person') + '</button>';
    s.body.querySelectorAll('[data-step]').forEach((b) => b.addEventListener('click', () => { f.weekly = Math.max(WEEKLY.min, Math.min(WEEKLY.max, f.weekly + +b.dataset.step)); draw(); }));
    s.body.querySelectorAll('[data-u]').forEach((b) => b.addEventListener('click', () => { const id = +b.dataset.u; if (f.invite.has(id)) f.invite.delete(id); else f.invite.add(id); draw(); }));
    $('#nc-name', s.body).addEventListener('input', (e) => { f.name = e.target.value; });
    const go = s.body.querySelector('[data-go]');
    go.addEventListener('click', () => run(go, async () => {
      const title = f.name.trim() || crewName(r);
      const created = await Server.createChallenge({ title, raceId: r.id, weekly: f.weekly, metric: 'visits', start: todayKey(), end: day, repeatMonthly: false, invite: [...f.invite] });
      if (!St.myRaces().some((m) => keyOf(m) === r.id)) St.saveMyRaces(St.myRaces().concat(fromRace(r)));
      await St.loadChallenges().catch(() => {});
      s.close();
      toast('Crew started');
      const outside = friends.filter((u) => f.invite.has(u.id) && !uses.has(u.id));
      location.hash = challengeRoute(created.id);
      if (outside.length) sendLinkSheet(created, outside);
    }));
  }
}

function lineFor(r, c, accepted) {
  if (r.status !== 'accepted') return 'Invited';
  const days = r.lastVisit ? Math.floor((Date.now() - new Date(r.lastVisit)) / 86400000) : null;
  if (r.userId === me()) {
    const i = accepted.indexOf(r);
    if (c.metric === 'target') return r.done ? 'Target reached' : (c.target - r.score) + ' to go';
    if (i > 0) { const up = accepted[i - 1]; return (up.score - r.score) + ' behind ' + up.name + (up.together ? ' · ' + up.together + ' together' : ''); }
    if (accepted[1]) return (r.score - accepted[1].score) + ' ahead of ' + accepted[1].name;
    return 'Leading';
  }
  if (days != null && days >= 4) return 'Last visit ' + days + ' days ago';
  if (r.topClass && r.topClass.count > 1) return r.topClass.title + ' ×' + r.topClass.count + (r.studios > 1 ? ' · ' + r.studios + ' studios' : '');
  if (!r.visits) return 'No visits yet';
  return r.visits + ' visits' + (r.studios > 1 ? ' · ' + r.studios + ' studios' : '');
}

async function shareLink(c) {
  const url = c.shareUrl || challengeShareUrl(c.id);
  try {
    if (navigator.share) { await navigator.share({ title: c.title || 'Brüce challenge', text: 'Join my challenge on Brüce', url }); return; }
    await navigator.clipboard.writeText(url); toast('Link copied');
  } catch (e) { if (e && e.name !== 'AbortError') toast(url); }
}

/** A participant's visits: friends in a challenge see totals, class types and studios. */
function openParticipant(r, c) {
  if (!r) return;
  const isMe = r.userId === me();
  const studio = (x) => (x && x.id ? St.studioName(x.id, { name: x.name }) : (x && x.name) || 'Studio');
  const catName = (k) => (k === 'gym' ? 'Gym drop-ins' : St.catTitle(k) || 'Category ' + k);
  sheet(isMe ? 'You' : r.name, '<div class="menu-head">' + avatar(userFor(r.userId, r.name), 56) + '<div><h2>' + esc(isMe ? 'You' : r.name) + '</h2><p class="muted">' +
    (r.status === 'accepted' ? (r.rank ? '#' + r.rank + ' · ' : '') + esc(c.title || '') : 'Invited, not joined yet') + '</p></div></div>' +
    (r.status !== 'accepted' ? '' :
      '<div class="ch-stats">' + [[r.visits, 'visits'], [r.classes, 'classes'], [r.dropins, 'drop-ins'], [Math.round(r.minutes / 60) + ' h', 'trained'], [r.studios, 'studios'], [r.together || 0, isMe ? 'score' : 'with you']].map(([v, l], i) =>
        '<div><b>' + esc(isMe && i === 5 ? r.score : v) + '</b><span>' + esc(l) + '</span></div>').join('') + '</div>' +
      (r.topClass || r.topStudio ? '<div class="card kv">' + (r.topClass ? '<span>Top class</span><b>' + esc(r.topClass.title) + ' ×' + r.topClass.count + '</b>' : '') +
        (r.topStudio ? '<span>Top studio</span><b>' + esc(studio(r.topStudio)) + ' ×' + r.topStudio.count + '</b>' : '') + '</div>' : '') +
      (r.categories && r.categories.length ? '<h3 class="section-head">Class types</h3><div class="chips wrap">' + r.categories.map((x) => '<span class="chip">' + esc(catName(x.key)) + ' <b>' + x.count + '</b></span>').join('') + '</div>' : '') +
      (r.recent && r.recent.length ? '<h3 class="section-head">Recent visits</h3><div class="list">' + r.recent.map((v) =>
        '<div class="crow"><div class="crow-time"><b>' + esc(time(v.at)) + '</b><small>' + esc(fmt(v.at, { day: 'numeric', month: 'short' })) + '</small></div><div class="crow-body"><h3>' + esc(v.kind === 'dropin' ? 'Solo training' : v.title || 'Class') + '</h3><p>' + esc(St.studioName(v.studioId, { name: v.studio })) + '</p></div></div>').join('') + '</div>' : '')),
  { cls: 'tall' });
}

// ---------------------------------------------------------------- new challenge

function monthRange(offset) {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth() + offset, 1);
  const end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  const k = (x) => x.getFullYear() + '-' + String(x.getMonth() + 1).padStart(2, '0') + '-' + String(x.getDate()).padStart(2, '0');
  return { start: k(d), end: k(end), label: d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' }) };
}

export async function openNewChallenge() {
  if (!(await serverConsent())) return;
  const f = { metric: 'classes', target: 12, period: 'this', start: monthRange(0).start, end: monthRange(1).end, category: '', repeat: true, invite: new Set() };
  const s = sheet('New challenge', loading(), { cls: 'tall' });
  if (!S.challenges) await St.loadChallenges().catch(() => {});
  if (!S.friends.length) await St.loadSocial().catch(() => {});
  const uses = new Set((S.challenges && S.challenges.usesBruce) || []);
  const friends = S.friends.map((x) => x.friend_user).filter(Boolean).sort((a, b) => (uses.has(b.id) - uses.has(a.id)) || (a.first_name || '').localeCompare(b.first_name || ''));
  draw();

  function draw() {
    const r = f.period === 'this' ? monthRange(0) : f.period === 'next' ? monthRange(1) : null;
    s.body.innerHTML = '<h3 class="section-head">Who wins</h3><div class="chips wrap">' +
      ['classes', 'visits', 'minutes', 'target'].map((m) => chip(m === 'target' ? 'Everyone hits ' + f.target : METRICS[m][0], f.metric === m, 'data-metric="' + m + '"').replace('class="chip"', 'class="chip glassy"')).join('') + '</div>' +
      (f.metric === 'target' ? '<div class="card form-rows"><div class="frow"><span class="grow">Visits each</span><span class="stepper"><button data-step="-1" aria-label="Fewer">−</button><b>' + f.target + '</b><button data-step="1" aria-label="More">+</button></span></div></div>' : '') +
      '<h3 class="section-head">Period</h3><div class="chips wrap">' + [['this', monthRange(0).label], ['next', monthRange(1).label], ['custom', 'Custom']].map(([k, t]) =>
        chip(esc(t), f.period === k, 'data-period="' + k + '"').replace('class="chip"', 'class="chip glassy"')).join('') + '</div>' +
      '<div class="card form-rows">' +
      (f.period === 'custom' ? '<div class="frow"><span class="grow">From</span><input type="date" id="nc-start" value="' + f.start + '"></div><div class="frow"><span class="grow">To</span><input type="date" id="nc-end" value="' + f.end + '"></div>' : '') +
      '<label class="frow"><span class="grow">Counts</span><select id="nc-cat"><option value="">All categories</option><option value="gym"' + (f.category === 'gym' ? ' selected' : '') + '>Gym drop-ins</option>' +
      S.categories.map((c) => '<option value="' + c.id + '"' + (String(c.id) === f.category ? ' selected' : '') + '>' + esc(c.title) + '</option>').join('') + '</select></label>' +
      (f.period === 'custom' ? '' : '<label class="toggle"><span>Repeat monthly<small class="muted">Starts over every month' + (r ? ', from ' + esc(r.label) : '') + '.</small></span><input type="checkbox" id="nc-repeat"' + (f.repeat ? ' checked' : '') + '><i></i></label>') + '</div>' +
      '<h3 class="section-head">Invite friends</h3>' + (friends.length ? '<div class="card menu">' + friends.map((u) => {
        const on = f.invite.has(u.id);
        return '<button class="mrow pick-row' + (on ? ' on' : '') + '" data-u="' + u.id + '" aria-pressed="' + on + '">' + avatar(u, 34) + '<span class="grow"><b>' + esc(u.first_name || '') + ' ' + esc(u.last_name || '') + '</b><small class="muted block">' +
          (uses.has(u.id) ? 'Uses Brüce' : 'Not on Brüce yet · send link') + '</small></span>' + (uses.has(u.id) ? '<span class="check">' + icon('check') + '</span>' : '<span class="check share">' + icon(on ? 'check' : 'share') + '</span>') + '</button>';
      }).join('') + '</div>' : '<p class="muted">Add friends in the Bruce app to invite them.</p>') +
      '<p class="muted small foot">' + icon('lock') + ' Friends in this challenge see your visits: totals, class types and studios. Each friend accepts separately. Leave anytime; your numbers are deleted.</p>' +
      '<button class="btn lime" data-go>Start challenge · ' + (f.invite.size + 1) + (f.invite.size ? ' people' : ' person') + '</button>';
    s.body.querySelectorAll('[data-metric]').forEach((b) => b.addEventListener('click', () => { f.metric = b.dataset.metric; draw(); }));
    s.body.querySelectorAll('[data-step]').forEach((b) => b.addEventListener('click', () => { f.target = Math.max(1, Math.min(99, f.target + +b.dataset.step)); draw(); }));
    s.body.querySelectorAll('[data-period]').forEach((b) => b.addEventListener('click', () => { f.period = b.dataset.period; draw(); }));
    s.body.querySelectorAll('[data-u]').forEach((b) => b.addEventListener('click', () => { const id = +b.dataset.u; if (f.invite.has(id)) f.invite.delete(id); else f.invite.add(id); draw(); }));
    const st = $('#nc-start', s.body), en = $('#nc-end', s.body);
    if (st) st.addEventListener('change', () => { f.start = st.value; });
    if (en) en.addEventListener('change', () => { f.end = en.value; });
    $('#nc-cat', s.body).addEventListener('change', (e) => { f.category = e.target.value; });
    const rp = $('#nc-repeat', s.body); if (rp) rp.addEventListener('change', () => { f.repeat = rp.checked; });
    const go = s.body.querySelector('[data-go]');
    go.addEventListener('click', () => run(go, async () => {
      const range = f.period === 'custom' ? { start: f.start, end: f.end } : monthRange(f.period === 'next' ? 1 : 0);
      if (!range.start || !range.end || range.end < range.start) throw new Error('Pick a period that ends after it starts.');
      const cat = f.category ? (f.category === 'gym' ? 'Gym drop-ins' : St.catTitle(f.category)) : null;
      const created = await Server.createChallenge({
        title: f.metric === 'target' ? 'Everyone hits ' + f.target : METRICS[f.metric][0], metric: f.metric, target: f.metric === 'target' ? f.target : null,
        category: f.category || null, categoryTitle: cat, start: range.start, end: range.end, repeatMonthly: f.period !== 'custom' && f.repeat, invite: [...f.invite],
      });
      await St.loadChallenges().catch(() => {});
      s.close();
      toast('Challenge started');
      const outside = friends.filter((u) => f.invite.has(u.id) && !uses.has(u.id));
      location.hash = challengeRoute(created.id);
      if (outside.length) sendLinkSheet(created, outside);
    }));
  }
}

/** Friends who are not on Brüce yet get the link (sharing needs a fresh tap, so it's a button). */
function sendLinkSheet(c, people) {
  const s = sheet('Send the link', '<p class="sheet-text">' + esc(people.map((u) => u.first_name).join(', ')) + ' ' + (people.length === 1 ? "isn't" : "aren't") + ' on Brüce yet. Send them the link; they log in with Bruce and join.</p>' +
    '<p class="center mono small">' + esc(c.shareUrl || challengeShareUrl(c.id)) + '</p><div class="stack"><button class="btn lime" data-go>' + icon('share') + ' Share link</button><button class="btn glass" data-close>Later</button></div>', { cls: 'small' });
  s.el.querySelector('[data-go]').addEventListener('click', () => { shareLink(c); s.close(); });
}

