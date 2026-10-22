// Entry point: login, layout (tab bar on phones, sidebar and side-by-side panes on wide screens) and the router.
// Routes: #/<tab>[/class|studio|challenge|race|product|shop/<id>][?query], tab = home | explore | checkin | friends | mine.
// Share links: #challenge/<id> opens the challenge in Friends (after logging in when needed).
import { $, $$, esc, icon, setZone, ls } from './util.js';
import { Bruce, session } from './api.js';
import * as St from './store.js';
import { S } from './store.js';
import { Home, Explore, CheckIn, Friends, Mine, wireCommon, placeholderPane } from './views.js';
import { renderClass, renderStudio } from './detail.js';
import { toast, fitTitle } from './ui.js';
import { renderChallenge } from './challenges.js';
import { renderRace } from './racesui.js';
import { renderShop, renderProduct, openOrders } from './shopui.js';
import { challengeIdFromHash, challengeRoute } from './links.js';
import { openNotifications, openMenu } from './sheets.js';

const TABS = [
  ['home', 'Home', 'home', Home], ['explore', 'Explore', 'explore', Explore], ['checkin', 'Check in', 'checkin', CheckIn],
  ['friends', 'Friends', 'friends', Friends], ['mine', 'My classes', 'mine', Mine],
];
const main = $('#main');
const pane = $('#pane');
const wideQuery = window.matchMedia('(min-width: 900px)');
const isWide = () => wideQuery.matches;
let current = { tab: null, query: null, detail: null, view: null };
// Details opened from another detail (a class from a studio's schedule, the studio from a class, a similar class),
// newest last, so the pane's close button returns to the detail it came from instead of the empty pane.
// Only links outside the list (the pane, a sheet) stack up; picking another row in the list replaces the detail.
let backStack = [];
let linkOutsideList = false;
document.addEventListener('click', (e) => {
  const a = e.target.closest && e.target.closest('a[href^="#/"]');
  linkOutsideList = !!a && !main.contains(a);
}, true);

function parse() {
  const h = location.hash.replace(/^#\/?/, '');
  const [path, query] = h.split('?');
  const parts = path.split('/').filter(Boolean);
  const tab = TABS.some((t) => t[0] === parts[0]) ? parts[0] : null;
  const detail = parts[1] === 'class' || parts[1] === 'studio' ? { kind: parts[1], id: +parts[2] }
    : (parts[1] === 'challenge' || parts[1] === 'race' || parts[1] === 'product' || parts[1] === 'shop') && parts[2] ? { kind: parts[1], id: decodeURIComponent(parts[2]) } : null;
  return { tab, detail, query: query || '', params: new URLSearchParams(query || '') };
}

function chrome() {
  const nav = TABS.map(([k, t, ic]) => '<a href="#/' + k + '" data-tab="' + k + '">' + icon(ic) + '<span>' + t + '</span><b class="tab-badge" data-badge="' + k + '"></b></a>').join('');
  $('#tabbar').innerHTML = nav;
  $('#side-nav').innerHTML = nav;
}
function markTab(tab) {
  $$('[data-tab]').forEach((a) => { if (a.dataset.tab === tab) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); });
}
function badges() {
  const n = St.upcomingBookings().length;
  $$('[data-badge="mine"]').forEach((b) => { b.textContent = n || ''; });
  const dot = St.unseenNotifications();
  $$('.notif-dot').forEach((d) => { d.hidden = !dot; });
  $$('[data-act="notifications"] .dot').forEach((d) => { d.hidden = !dot; });
}

function route() {
  const shared = challengeIdFromHash(location.hash);
  if (shared) {
    if (!S.auth) { ls.set('bruce.pendingChallenge', shared); renderLogin(); return; }
    location.replace(challengeRoute(shared)); return;
  }
  if (!S.auth) { renderLogin(); return; }
  document.body.classList.remove('logged-out');
  const r = parse();
  if (!r.tab) { location.replace('#/home'); return; }
  // Stripe Checkout's way back (#/home/orders?paid=…) and a plain link to Menu › Orders: the sheet over Home.
  if (/^#\/[a-z]+\/orders(\?|$)/.test(location.hash)) { const paid = r.params.has('paid'); location.replace('#/' + r.tab); openOrders(paid); return; }
  const tabChanged = r.tab !== current.tab || r.query !== current.query;
  const detailChanged = JSON.stringify(r.detail) !== JSON.stringify(current.detail);
  trackBack(r, detailChanged);
  markTab(r.tab);
  document.body.classList.toggle('has-detail', !!r.detail);
  const ctx = {
    tab: r.tab, params: r.params, detail: r.detail, wide: isWide(),
    rerender: () => { current.tab = null; route(); },
    close: () => { location.hash = backStack.length ? backStack[backStack.length - 1] : '#/' + r.tab + (r.query ? '?' + r.query : ''); },
    link: (kind, id) => '#/' + r.tab + '/' + kind + '/' + id + (r.query ? '?' + r.query : ''),
  };
  if (tabChanged || !current.view) {
    const View = TABS.find((t) => t[0] === r.tab)[3];
    const el = document.createElement('div');
    el.className = 'view view-' + r.tab;
    main.replaceChildren(el);
    main.scrollTop = 0;
    if (!isWide() && !r.detail) window.scrollTo(0, 0);
    current.view = View;
    View.render(el, ctx);
    fitTitle($('.screen-title', el));
  } else if (detailChanged && current.view) {
    current.view.ctx = ctx;
    $$('.selected', main).forEach((x) => x.classList.remove('selected'));
    if (r.detail) $$('[href^="#/' + r.tab + '/' + r.detail.kind + '/' + r.detail.id + '"]', main).forEach((x) => x.classList.add('selected'));
  }
  if (detailChanged || tabChanged) {
    const el = document.createElement('div');
    el.className = 'detail';
    pane.replaceChildren(el);
    pane.scrollTop = 0;
    if (!isWide() && r.detail) window.scrollTo(0, 0);
    if (r.detail && r.detail.kind === 'class') renderClass(el, r.detail.id, ctx);
    else if (r.detail && r.detail.kind === 'studio') renderStudio(el, r.detail.id, ctx);
    else if (r.detail && r.detail.kind === 'challenge') renderChallenge(el, r.detail.id, ctx);
    else if (r.detail && r.detail.kind === 'race') renderRace(el, r.detail.id, ctx);
    else if (r.detail && r.detail.kind === 'shop') renderShop(el, ctx);
    else if (r.detail && r.detail.kind === 'product') renderProduct(el, r.detail.id, ctx);
    else if (isWide()) placeholderPane(el, r.tab);
  }
  current = Object.assign(current, { tab: r.tab, query: r.query, detail: r.detail, hash: location.hash });
  badges();
}

function trackBack(r, detailChanged) {
  const fromDetail = linkOutsideList;
  linkOutsideList = false;
  if (!r.detail || r.tab !== current.tab) { backStack = []; return; }
  if (!detailChanged) return;
  const at = backStack.indexOf(location.hash);
  if (at >= 0) { backStack.length = at; return; } // went back (close or browser back) to a detail already on the stack
  if (current.detail && fromDetail) backStack.push(current.hash);
  else backStack = [];
}

// ---------------------------------------------------------------- login

function renderLogin() {
  document.body.classList.add('logged-out');
  document.body.classList.remove('has-detail');
  current = { tab: null, query: null, detail: null, view: null };
  pane.replaceChildren();
  main.innerHTML = '<section class="login">' +
    '<img class="login-icon" src="icon-rounded.png" width="96" height="96" alt="">' +
    '<h1 class="screen-title">BRÜCE</h1><p class="tagline">BOOK. TRAIN. CHECK IN.</p>' +
    (ls.get('bruce.pendingChallenge', null) ? '<div class="card notice-card">' + icon('trophy') + '<p><b>A friend challenged you.</b> Log in with your Bruce account first, then you continue to the challenge.</p></div>' : '') +
    '<form id="login-form" class="card form" autocomplete="on">' +
    '<label><span>Email</span><input type="email" name="email" autocomplete="username" required></label>' +
    '<label><span>Password</span><input type="password" name="password" autocomplete="current-password" required></label>' +
    '<p class="error small" id="login-error" role="alert"></p>' +
    '<button class="btn lime" type="submit">Log in</button></form>' +
    '<button class="btn glass" type="button" id="demo-btn">Try the demo</button>' +
    '<p class="muted small note">Unofficial and not affiliated with Bruce Studios AB. Your password goes straight to api.bruce.app, and the access token is kept only in this browser. ' +
    '<a href="../">About Brüce</a> · <a href="https://github.com/djui/bruce">Source</a></p></section>';
  $('#login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const f = e.target; const btn = f.querySelector('button');
    btn.disabled = true; $('#login-error').textContent = '';
    try {
      St.setAuth({ token: null, userId: null, demo: false });
      const r = await Bruce.login(f.email.value.trim(), f.password.value);
      St.setAuth({ token: r.access_token, userId: r.user_id, demo: false });
      start();
    } catch (err) {
      St.setAuth(null);
      $('#login-error').textContent = [400, 401, 403, 404].includes(err.status) ? 'Wrong email or password.' : err.message;
      btn.disabled = false;
    }
  });
  $('#demo-btn').addEventListener('click', () => { St.setAuth({ token: 'demo', userId: 1, demo: true }); start(); });
}

function logout() {
  if (S.auth && !S.auth.demo) Bruce.logout().catch(() => {});
  St.setAuth(null); St.clearData();
  location.hash = '#/home';
  renderLogin();
}

// ---------------------------------------------------------------- start

let refreshTimer;
St.S.listeners.add(() => {
  badges();
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => { if (current.view && current.view.refresh) current.view.refresh(); }, 60);
});

function start() {
  St.applySession();
  main.innerHTML = '<div class="loading">Loading…</div>';
  $('#demo-flag').hidden = !St.isDemo();
  St.bootstrap().finally(() => {
    const pending = ls.get('bruce.pendingChallenge', null);
    if (pending) { ls.del('bruce.pendingChallenge'); location.replace(challengeRoute(pending)); }
    current.tab = null; route();
  });
}

session.onUnauthorized = () => { toast('Your session ended. Please log in again.'); logout(); };
window.addEventListener('hashchange', route);
window.addEventListener('bruce:logout', logout);
window.addEventListener('bruce:city', () => { setZone(St.city().time_zone); current.tab = null; route(); });
wideQuery.addEventListener('change', () => { current.tab = null; route(); });
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && current.detail && !document.querySelector('dialog[open]')) location.hash = '#/' + current.tab + (current.query ? '?' + current.query : '');
});
$('#side-actions').addEventListener('click', (e) => {
  const b = e.target.closest('[data-side]');
  if (!b) return;
  if (b.dataset.side === 'notifications') openNotifications(); else openMenu();
});
$('#demo-flag').addEventListener('click', () => logout());
wireCommon(document.body);
chrome();
if (S.auth) start(); else route();   // route() also remembers a shared challenge link for after the login
