// Monthly goals: the "<Month> goals" screen (ring, goal cards with pace markers, streak, month calendar), the
// New goal sheet, and the compact card on My classes. Logic in goals.js; goals are stored on this device.
import { $, esc, icon, fmt, todayKey } from './util.js';
import * as St from './store.js';
import { S } from './store.js';
import { sheet, toast, loading, confirmSheet } from './ui.js';
import { summary, calendar, suggestions, goalTitle, monthInfo } from './goals.js';

const MONTH = (today) => new Date(today + 'T12:00:00Z').toLocaleDateString('en-GB', { month: 'long', timeZone: 'UTC' });
const isCategory = (k) => k != null && k !== '' && k !== 'anyClass' && k !== 'gym' && k !== 'newStudios';
const title = (g) => goalTitle(g.category, St.catTitle);

function goalIcon(k) {
  if (k === 'gym') return 'dumbbell';
  if (k == null || k === '') return 'checkSeal';
  if (k === 'anyClass') return 'calendar';
  if (k === 'newStudios') return 'spark';
  const t = (St.catTitle(k) || '').toLowerCase();
  if (/swim/.test(t)) return 'swim';
  if (/yoga|pilates|medita|stretch|barre/.test(t)) return 'yoga';
  if (/spa|sauna|wellness/.test(t)) return 'spa';
  if (/strength|gym|hyrox|lift/.test(t)) return 'dumbbell';
  return 'run';
}

function ring(done, target, size) {
  const r = 50, c = 2 * Math.PI * r;
  const pct = target ? Math.min(1, done / target) : 0;
  return '<div class="ring" style="--size:' + (size || 132) + 'px"><svg viewBox="0 0 120 120" aria-hidden="true"><circle cx="60" cy="60" r="50" class="track"/>' +
    '<circle cx="60" cy="60" r="50" class="fill" stroke-dasharray="' + c.toFixed(1) + '" stroke-dashoffset="' + (c * (1 - pct)).toFixed(1) + '"/></svg>' +
    '<div class="ring-c"><b>' + done + '</b><small>of ' + target + '</small></div></div>';
}
const streakChip = (n) => (n >= 2 ? '<span class="why-chip lime">' + icon('flame') + n + ' weeks in a row</span>' : '');

/** Compact card for My classes: ring, status and the month; opens the goals screen. */
export function goalsCardHTML() {
  const goals = St.goals();
  if (!goals.length) {
    return '<button class="card row-card goals-mini" data-goals>' + icon('target') + '<div class="grow"><b>Set a monthly goal</b><p class="muted">Like 12 gym visits or 2 swims a month.</p></div>' + icon('chevron') + '</button>';
  }
  if (!S.history) { St.loadHistory().catch(() => {}); return '<div class="card goals-mini">' + loading('Loading goals…') + '</div>'; }
  const today = todayKey();
  const sm = summary(goals, St.visitList(true), today);
  return '<button class="card goals-mini" data-goals>' + ring(sm.done, sm.target, 64) + '<div class="grow"><b>' + esc(MONTH(today)) + ' goals · ' + esc(sm.status) + '</b>' +
    '<p class="muted">' + sm.progress.map((p, i) => esc(title(goals[i])) + ' ' + p.done + '/' + p.target).join(' · ') + '</p>' + streakChip(sm.streak) + '</div>' + icon('chevron') + '</button>';
}

/** The goals screen. */
export function openGoals() {
  let editing = false;
  const today = todayKey();
  const s = sheet(MONTH(today) + ' goals', loading(), { cls: 'tall', trailing: '<button class="glass-btn wide" data-edit>Edit</button>' });
  const editBtn = s.el.querySelector('[data-edit]');
  editBtn.addEventListener('click', () => { editing = !editing; editBtn.textContent = editing ? 'Done' : 'Edit'; editBtn.setAttribute('aria-pressed', editing); draw(); });
  const unsub = () => St.S.listeners.delete(redraw);
  const redraw = () => { if (!s.el.isConnected) { unsub(); return; } draw(); };
  St.S.listeners.add(redraw);
  St.loadHistory().then(draw).catch((e) => { s.body.innerHTML = '<p class="muted center">' + esc(e.message) + '</p>'; });

  function draw() {
    if (!S.history) return;
    const goals = St.goals();
    const visits = St.visitList(true);
    const sm = summary(goals, visits, today);
    const m = monthInfo(today);
    const cal = calendar(today, visits, goals);
    s.body.innerHTML = '<div class="card goal-sum">' + ring(sm.done, sm.target) + '<div class="grow"><h3 class="goal-status ' + (sm.status === 'Behind' ? 'orange' : '') + '">' + esc(sm.status) + '</h3>' +
      '<p class="muted">' + esc(sm.hint) + '</p>' + streakChip(sm.streak) + '</div></div>' +
      goals.map((g, i) => {
        const p = sm.progress[i];
        const blue = isCategory(g.category);
        const last = p.last ? 'Last: ' + St.studioName(p.last.studioId) + ', ' + fmt(p.last.at, { day: 'numeric', month: 'short' }) : 'No visits yet this month';
        return '<div class="card goal-card' + (blue ? ' blue' : '') + '" data-gi="' + i + '" role="button" tabindex="0">' +
          '<div class="goal-top"><span class="goal-ic">' + icon(goalIcon(g.category)) + '</span><span class="grow"><b>' + esc(title(g)) + '</b>' +
          (g.studioId ? '<small class="muted block">Only at ' + esc(St.studioName(g.studioId)) + '</small>' : '') + '</span>' +
          (editing ? '<button class="glass-btn" data-gedit="' + i + '" aria-label="Edit goal">' + icon('pencil') + '</button><button class="glass-btn" data-gdel="' + i + '" aria-label="Delete goal">' + icon('trash') + '</button>'
            : '<span class="goal-num">' + p.done + ' / ' + p.target + '</span>') + '</div>' +
          '<div class="goal-bar" role="img" aria-label="' + p.done + ' of ' + p.target + ', ' + esc(p.pace) + '"><i style="width:' + p.pct + '%"></i>' + (p.status === 'done' ? '' : '<b style="left:' + p.pacePct + '%"></b>') + '</div>' +
          '<div class="goal-meta"><span class="' + (p.status === 'behind' ? 'orange' : '') + '">' + esc(p.pace) + '</span><span>' + esc(p.toGo) + '</span></div>' +
          '<p class="goal-last muted">' + esc(last) + (g.remind ? ' · ' + icon('bell') + ' reminder' : '') + '</p></div>';
      }).join('') +
      '<button class="btn ' + (goals.length ? 'glass' : 'lime') + '" data-gadd>' + icon('plus') + ' Add goal</button>' +
      '<h2 class="sec-title">This month <small class="muted">' + visits.filter((v) => v.month === m.month).length + ' visits</small></h2>' +
      '<div class="dots" role="img" aria-label="Visits this month">' + ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) => '<span class="h">' + d + '</span>').join('') +
      '<span class="x"></span>'.repeat(cal.lead) + cal.cells.map((c) => '<span class="' + [c.goal ? 'goal' : c.visit ? 'visit' : '', c.today ? 'today' : '', c.future ? 'future' : ''].join(' ').trim() + '">' + c.day + '</span>').join('') + '</div>' +
      '<p class="muted small foot"><i class="dot lime"></i> visit <i class="dot blue"></i> counts for a category goal. Checked-in visits only.</p>';
    s.body.querySelector('[data-gadd]').addEventListener('click', () => openGoalEditor(null));
    s.body.querySelectorAll('[data-gi]').forEach((c) => c.addEventListener('click', (e) => {
      const del = e.target.closest('[data-gdel]');
      if (del) {
        const g = St.goals()[+del.dataset.gdel];
        confirmSheet('Delete this goal?', title(g) + ': ' + g.target + ' a month.', 'Delete goal').then((yes) => { if (yes) St.saveGoals(St.goals().filter((x) => x.id !== g.id)); });
        return;
      }
      openGoalEditor(St.goals()[+c.dataset.gi]);
    }));
  }
}

/** New goal / edit goal sheet. */
export function openGoalEditor(goal) {
  const editing = !!goal;
  const g = Object.assign({ id: 'g' + Date.now().toString(36), category: 'gym', target: 8, studioId: null, remind: false }, goal || {});
  const today = todayKey();
  const s = sheet(editing ? 'Edit goal' : 'New goal', loading(), { trailing: '<button class="glass-btn lime-btn" data-save aria-label="Save goal">' + icon('check') + '</button>', cls: 'tall' });
  const keys = [['gym', 'Gym', 'dumbbell']].concat(S.categories.filter((c) => !/^gym$/i.test(c.title)).map((c) => [String(c.id), c.title, goalIcon(String(c.id))]), [['newStudios', 'New studios', 'spark'], ['anyClass', 'Any class', 'calendar'], ['', 'Any visit', 'checkSeal']]);
  St.loadHistory().catch(() => []).then(draw);

  function draw() {
    const visits = St.visitList(true);
    const sug = suggestions(visits, today, St.goals().filter((x) => x.id !== g.id));
    const used = new Map();
    visits.forEach((v) => used.set(v.studioId, (used.get(v.studioId) || 0) + 1));
    const studios = [...used.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id).filter(Boolean).slice(0, 25);
    if (g.studioId && !studios.includes(g.studioId)) studios.unshift(g.studioId);
    s.body.innerHTML = '<h3 class="section-head">What counts</h3><div class="chips wrap">' + keys.map(([k, t, ic]) =>
      '<button class="chip glassy" data-k="' + esc(k) + '" aria-pressed="' + (String(g.category == null ? '' : g.category) === k) + '">' + icon(ic) + esc(t) + '</button>').join('') + '</div>' +
      '<h3 class="section-head">Target</h3><div class="card form-rows">' +
      '<div class="frow"><span class="grow">Times per month</span><span class="stepper"><button data-step="-1" aria-label="Fewer">−</button><b id="g-n">' + g.target + '</b><button data-step="1" aria-label="More">+</button></span></div>' +
      '<label class="frow"><span class="grow">Only at</span><select id="g-studio"><option value="">Any studio</option>' + studios.map((id) => '<option value="' + id + '"' + (id === g.studioId ? ' selected' : '') + '>' + esc(St.studioName(id)) + '</option>').join('') + '</select></label>' +
      '<label class="toggle"><span>Reminder when behind<small class="muted">' + (St.serverOn() ? 'Our server sends a push to the Brüce iPhone app when you fall behind pace.' : 'Needs our server, which is off in Settings.') + '</small></span><input type="checkbox" id="g-remind"' + (g.remind ? ' checked' : '') + '><i></i></label></div>' +
      '<p class="muted small foot">Counts classes and drop-in visits you checked in to. Booked but not checked in does not count.</p>' +
      (sug.length ? '<h3 class="section-head">Suggested from your last 3 months</h3><div class="card menu">' + sug.map((x, i) =>
        '<div class="mrow"><span class="goal-ic' + (isCategory(x.category) ? ' blue' : '') + '">' + icon(goalIcon(x.category)) + '</span><span class="grow"><b>' + x.target + ' ' + esc(goalTitle(x.category, St.catTitle).toLowerCase()) + '</b><small class="muted block">You averaged ' + x.avg + '</small></span><button class="chip glassy" data-sug="' + i + '">Add</button></div>').join('') + '</div>' : '') +
      '<button class="btn lime" data-save>' + (editing ? 'Save goal' : 'Add goal') + '</button>' +
      (editing ? '<button class="btn glass red-text" data-delete>' + icon('trash') + ' Delete goal</button>' : '');
    s.body.querySelectorAll('[data-k]').forEach((b) => b.addEventListener('click', () => { g.category = b.dataset.k === '' ? null : b.dataset.k; draw(); }));
    s.body.querySelectorAll('[data-step]').forEach((b) => b.addEventListener('click', () => { g.target = Math.max(1, Math.min(60, g.target + +b.dataset.step)); $('#g-n', s.body).textContent = g.target; }));
    $('#g-studio', s.body).addEventListener('change', (e) => { g.studioId = +e.target.value || null; });
    $('#g-remind', s.body).addEventListener('change', (e) => { g.remind = e.target.checked; });
    s.body.querySelectorAll('[data-sug]').forEach((b) => b.addEventListener('click', () => {
      const x = sug[+b.dataset.sug];
      St.saveGoals(St.goals().concat([{ id: 'g' + Date.now().toString(36), category: x.category, target: x.target, studioId: null, remind: false }]));
      toast('Goal added: ' + x.target + ' ' + goalTitle(x.category, St.catTitle).toLowerCase());
      draw();
    }));
    const del = s.body.querySelector('[data-delete]');
    if (del) del.addEventListener('click', () => { St.saveGoals(St.goals().filter((x) => x.id !== g.id)); s.close(); toast('Goal deleted'); });
    s.body.querySelector('[data-save]').addEventListener('click', save);
  }
  function save() {
    const list = St.goals();
    const i = list.findIndex((x) => x.id === g.id);
    if (i >= 0) list[i] = g; else list.push(g);
    St.saveGoals(list);
    toast(editing ? 'Goal saved' : 'Goal added: ' + g.target + ' ' + title(g).toLowerCase() + ' a month');
    s.close();
  }
  s.el.querySelector('.sheet-bar [data-save]').addEventListener('click', save);
}

