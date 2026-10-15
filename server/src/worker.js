// Bruce auto-book server: a Cloudflare Worker that books weekly classes the moment their booking window opens,
// for every user of the app who switches it on, and tells them with an Apple push.
//
// A class opens for booking at `bookable_earliest_time` = start - `bookable_earliest` (7 days for ~97% of classes),
// and classes are listed about 14 days ahead (see ../../API.md "Booking windows"). The cron runs every minute but
// only talks to Bruce when there is something to do:
// - each user's classes are re-read every 5 minutes (users are spread over the 5 minutes),
// - in the minute before a class opens it waits for the open moment and books it.
//
// Users identify with their own Bruce login (`X-Access-Token` + `X-User-Id`); the server checks it with Bruce
// (`GET /v52/user/<id>`), so nobody can read or change another user's data. Storage: D1 table `users`, one row per
// Bruce user (login, rules, push device tokens, state). Optional `ALLOWED_USERS` (comma-separated Bruce user ids)
// limits who may use the server. Push: APNs token auth (`APNS_KEY` .p8 contents, `APNS_KEY_ID`, `APNS_TEAM_ID`,
// `APNS_TOPIC` = app bundle id). Email: the same booking results go to the address on the user's Bruce account, sent
// with Resend (`RESEND_API_KEY` secret, `EMAIL_FROM` var); without the key no email is sent. HTTP API: see ../README.md.
//
// Challenges with friends, goal reminders and Wrapped percentiles (tables from ../migrations): a daily cron reads each
// stored user's booking history and keeps per-day counts in `daily_counts` (plus per-visit detail while the user is
// in a challenge). The pure logic is in ./insights.js.

import {
  localDay, addDays, monthStart, visitsFromBookings, dailyRows, fromDetail, goalReminders, challengePeriod, challengeStats,
  cleanChallenge, cohortValues, percentiles, PERCENTILE_METRICS,
} from "./insights.js";

const API = "https://api.bruce.app";
const USER_AGENT = "Bruce/14.4.2_538 (iOS27.0.0; Apple)";
const TZ = "Europe/Stockholm";
const DEFAULT_WINDOW_S = 7 * 24 * 3600;
const LOOKAHEAD_DAYS = 15;
const SCAN_EVERY_MIN = 5;
const MAX_DEVICES = 5;
/// A class opening within this many ms of the cron tick is booked in this run (cron ticks once a minute).
const DUE_AHEAD_MS = 65_000;
const RETRY_WINDOW_MS = 20_000;
const LOG_SIZE = 30;
/// Waitlist watches: a class starting within a day is polled every minute (a freed spot is taken by whoever books
/// first), a later one every WATCH_FAR_EVERY_MIN minutes, one request per class. Capped per user.
const MAX_WATCHES = 10;
const WATCH_NEAR_MS = 24 * 3600_000;
const WATCH_FAR_EVERY_MIN = 5;
/// After a failed booking attempt on a free spot the watch waits this long, and is dropped after MAX_WATCH_FAILS.
const WATCH_RETRY_MS = 5 * 60_000;
const MAX_WATCH_FAILS = 5;
/// The daily history refresh (challenges, goal reminders, Wrapped percentiles); must match a cron in wrangler.toml.
export const DAILY_CRON = "30 2 * * *";
/// Bruce requests (booking pages of 30) one daily run may spend; users not refreshed today go first. The Workers free
/// plan allows 50 subrequests per invocation; set DAILY_BUDGET higher on a paid plan.
const DAILY_BUDGET = 45;
/// At most this many pages (30 bookings each) for one user's first read (year to date, or since a challenge began).
const BACKFILL_PAGES = 40;
const MAX_INVITES = 20;
const MAX_GOALS = 10;
const SHARE_URL = "https://djui.github.io/bruce/app/#challenge/";
const DEFAULT_PUBLIC_URL = "https://bruce-autobook.uwe-af1.workers.dev";
const CLASS_URL = "https://djui.github.io/bruce/app/#/home/class/";

// MARK: Time in Europe/Stockholm

const partsFmt = new Intl.DateTimeFormat("en-US", {
  timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit", weekday: "short", hourCycle: "h23",
});
const WEEKDAYS = { Sun: 1, Mon: 2, Tue: 3, Wed: 4, Thu: 5, Fri: 6, Sat: 7 };

/** Local date parts; `weekday` uses Apple's numbering (1 = Sunday), like the app's rules. */
export function localParts(ms) {
  const p = Object.fromEntries(partsFmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, hour: +p.hour, minute: +p.minute, second: +p.second, weekday: WEEKDAYS[p.weekday] };
}

/** UTC ms of local midnight on the given local date. */
export function localMidnight(y, m, d) {
  const guess = Date.UTC(y, m - 1, d);
  const p = localParts(guess);
  const offset = Date.UTC(p.y, p.m - 1, p.d, p.hour, p.minute, p.second) - guess;
  const t = guess - offset;
  // Across a DST change the offset at midnight can differ from the guess's; one correction settles it.
  const q = localParts(t);
  return t - (Date.UTC(q.y, q.m - 1, q.d, q.hour, q.minute, q.second) - Date.UTC(y, m - 1, d));
}

// MARK: Rules

/** Same as AutoBookRule.matches in the app: studio, local weekday + start time, and series (or title). */
export function matches(rule, c) {
  if (c.studio_id !== rule.studioId || c.deleted || c.deleted_at || c.canceled) return false;
  const p = localParts(Date.parse(c.start_time));
  if (p.weekday !== rule.weekday || p.hour * 60 + p.minute !== rule.minuteOfDay) return false;
  if (rule.masterId != null && c.master_id != null) return c.master_id === rule.masterId;
  return String(c.title).toLowerCase() === String(rule.title).toLowerCase();
}

export function opensAt(c) {
  const t = c.bookable_earliest_time ? Date.parse(c.bookable_earliest_time) : NaN;
  if (!Number.isNaN(t)) return t;
  const window = Number.isFinite(+c.bookable_earliest) && c.bookable_earliest != null ? +c.bookable_earliest : DEFAULT_WINDOW_S;
  return Date.parse(c.start_time) - window * 1000;
}

/** Local days (UTC ranges) in the lookahead on which some rule's weekday falls, per studio. */
export function scanPlan(rules, now) {
  const today = localParts(now);
  const plan = new Map();
  for (let i = 0; i < LOOKAHEAD_DAYS; i++) {
    const from = localMidnight(today.y, today.m, today.d + i);
    const p = localParts(from + 12 * 3600_000);
    const to = localMidnight(p.y, p.m, p.d + 1);
    for (const r of rules) {
      if (r.weekday !== p.weekday) continue;
      const key = `${r.studioId}-${from}`;
      if (!plan.has(key)) plan.set(key, { studioId: r.studioId, from, to });
    }
  }
  return [...plan.values()];
}

// MARK: Bruce API

function bruce(method, path, token, { query, body } = {}) {
  const url = new URL(path, API);
  for (const [k, v] of query ?? []) url.searchParams.append(k, v);
  const headers = { Accept: "application/json", "User-Agent": USER_AGENT, "Accept-Language": "en-US", "X-Access-Token": token };
  if (body) headers["Content-Type"] = "application/json";
  return fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
}

async function fetchClasses(token, studioId, from, to) {
  const out = [];
  let cursor;
  for (let page = 0; page < 10; page++) {
    const query = [
      ["studio_id", String(studioId)], ["presentation_studio_id", String(studioId)],
      ["start_time_after", new Date(from).toISOString().replace(/\.\d{3}Z$/, "Z")],
      ["start_time_before", new Date(to).toISOString().replace(/\.\d{3}Z$/, "Z")],
      ["limit", "30"], ["is_recurring_base", "false"], ["is_master", "false"], ["dedicated", "false"],
      ["opening", "false"], ["deleted", "false"], ["include_absolute_times", "true"], ["locale", "en"],
    ];
    if (cursor) query.push(["next_cursor", cursor]);
    const res = await bruce("GET", "/v52/class", token, { query });
    if (res.status === 401) throw new LoggedOut();
    if (!res.ok) throw new Error(`classes HTTP ${res.status}`);
    const r = await res.json();
    out.push(...(r.classes ?? []));
    cursor = r.metadata?.pagination?.next_cursor;
    if (!cursor || !(r.classes ?? []).length) break;
  }
  return out;
}

/** `GET /v52/class/<id>`; null when the class does not exist (any more). */
export async function fetchClass(token, classId) {
  const res = await bruce("GET", `/v52/class/${classId}`, token, { query: [["include_absolute_times", "true"], ["locale", "en"]] });
  if (res.status === 401) throw new LoggedOut();
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`class HTTP ${res.status}`);
  return (await res.json()).class ?? null;
}

export class LoggedOut extends Error {}

const bookingTime = (b) => {
  for (const t of [b.class?.start_time, b.checked_in_at, b.created_at]) { const ms = t ? Date.parse(t) : NaN; if (Number.isFinite(ms)) return ms; }
  return NaN;
};

/**
 * The user's bookings back to `fromMs`, newest first (the order of the booking list [c7:64]), paged by `next_cursor`
 * like the apps' Statistics list. Stops at a page that is entirely older than `fromMs`, at the end, or after `maxPages`
 * (then `complete` is false).
 */
export async function fetchBookings(token, userId, fromMs, maxPages = BACKFILL_PAGES) {
  const bookings = [];
  let cursor, pages = 0, complete = false;
  while (pages < maxPages) {
    const query = [["user_id", String(userId)], ["limit", "30"], ["deleted", "false"], ["include_class", "true"],
                   ["include_class_studio", "true"], ["include_class_categories", "true"], ["locale", "en"]];
    if (cursor) query.push(["next_cursor", cursor]);
    const res = await bruce("GET", "/v52/booking", token, { query });
    pages++;
    if (res.status === 401) throw new LoggedOut();
    if (!res.ok) throw new Error(`bookings HTTP ${res.status}`);
    const r = await res.json();
    const page = r.bookings ?? [];
    bookings.push(...page);
    cursor = r.metadata?.pagination?.next_cursor;
    if (!cursor || !page.length || page.every((b) => !(bookingTime(b) >= fromMs))) { complete = true; break; }
  }
  return { bookings, pages, complete };
}

/** The caller's Bruce friends as `{ id, name }` (`GET /v52/friend`, as the apps' Friends tab). */
export async function fetchFriends(token, userId) {
  const res = await bruce("GET", "/v52/friend", token, { query: [["user_id", String(userId)], ["include_friend_user", "true"], ["locale", "en"]] });
  if (res.status === 401) throw new LoggedOut();
  if (!res.ok) throw new Error(`friends HTTP ${res.status}`);
  return ((await res.json()).friends ?? []).map((f) => f.friend_user).filter((u) => u?.id)
    .map((u) => ({ id: u.id, name: String(u.first_name ?? u.display_name ?? "").slice(0, 60) }));
}

function errorMessage(text, status) {
  try { const e = JSON.parse(text).errors?.[0]; if (e?.message || e?.code) return e.message || e.code; } catch {}
  return `HTTP ${status}`;
}

/** POST /v52/booking at the open moment; failures are retried every second until RETRY_WINDOW_MS after opening. */
export async function book(session, o, { sleep = (ms) => new Promise((r) => setTimeout(r, ms)), now = Date.now } = {}) {
  const wait = o.opens - 300 - now();
  if (wait > 0) await sleep(wait);
  let last = "no answer";
  for (;;) {
    try {
      const res = await bruce("POST", "/v52/booking", session.access_token, {
        body: { class_id: o.classId, booked_via: "HOMESCREEN_SPOTLIGHT", include_user: false, locale: "en" },
      });
      if (res.ok) return "Booked";
      if (res.status === 401) return "Login expired";
      last = errorMessage(await res.text(), res.status);
    } catch (e) { last = String(e.message ?? e); }
    if (now() > o.opens + RETRY_WINDOW_MS) break;
    await sleep(1000);
  }
  // Booked elsewhere (the app on a device) also counts.
  if (session.user_id) {
    const res = await bruce("GET", "/v52/booking", session.access_token, {
      query: [["user_id", String(session.user_id)], ["limit", "30"], ["deleted", "false"],
              ["class_start_time_after", new Date(now() - 86400_000).toISOString()], ["locale", "en"]],
    }).catch(() => null);
    const mine = res?.ok ? (await res.json()).bookings ?? [] : [];
    if (mine.some((b) => b.class_id === o.classId)) return "Already booked";
  }
  return `Not booked: ${last}`;
}

// MARK: Apple push (APNs, token-based auth)

let apnsJwt = { token: null, at: 0, keyId: null };

function b64url(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsToken(env, now = Date.now()) {
  // Apple accepts a provider token for up to an hour and rejects refreshing it more than every 20 minutes.
  if (apnsJwt.token && apnsJwt.keyId === env.APNS_KEY_ID && now - apnsJwt.at < 50 * 60_000) return apnsJwt.token;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const input = `${enc({ alg: "ES256", kid: env.APNS_KEY_ID })}.${enc({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  apnsJwt = { token: `${input}.${b64url(sig)}`, at: now, keyId: env.APNS_KEY_ID };
  return apnsJwt.token;
}

export const apnsConfigured = (env) => !!(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_TOPIC);

/** Sends one alert to each device; returns the devices Apple says are gone (to drop them). */
export async function push(env, devices, title, body, data = {}, category = "AUTOBOOK_RESULT") {
  if (!apnsConfigured(env) || !devices.length) return [];
  const jwt = await apnsToken(env);
  const gone = [];
  await Promise.all(devices.map(async (d) => {
    const host = d.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const res = await fetch(`https://${host}/3/device/${d.token}`, {
        method: "POST",
        headers: { authorization: `bearer ${jwt}`, "apns-topic": env.APNS_TOPIC, "apns-push-type": "alert", "apns-priority": "10" },
        body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", category }, ...data }),
      });
      if (res.status === 410 || (res.status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(await res.text()))) gone.push(d.token);
      else if (!res.ok) console.log("apns", res.status, await res.text());
    } catch (e) { console.log("apns failed:", e.message); }
  }));
  return gone;
}

// MARK: Email (Resend)

export const emailConfigured = (env) => !!(env.RESEND_API_KEY && env.EMAIL_FROM);
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

/** The token in a user's unsubscribe link: HMAC-SHA256 of the user id, keyed with the Resend key. */
export async function unsubscribeToken(env, userId) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.RESEND_API_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`unsubscribe:${userId}`))).slice(0, 32);
}

const escapeHtml = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** Sends one booking result to the user's Bruce email (if known, not unsubscribed and Resend is set up). */
export async function email(env, u, title, body, classId) {
  const to = u.state.email;
  if (!emailConfigured(env) || !to || u.state.emailOff) return;
  const off = `${env.PUBLIC_URL ?? DEFAULT_PUBLIC_URL}/email/off?u=${u.userId}&t=${await unsubscribeToken(env, u.userId)}`;
  const link = classId ? CLASS_URL + classId : null;
  const text = [body, link && `Open the class: ${link}`, "", `Sent by the Brüce auto-book server. No more emails: ${off}`].filter((l) => l != null).join("\n");
  const html = `<p style="font-size:16px">${escapeHtml(body)}</p>${link ? `<p><a href="${link}">Open the class</a></p>` : ""}`
    + `<p style="color:#888;font-size:12px">Sent by the Brüce auto-book server. <a href="${off}" style="color:#888">No more emails</a></p>`;
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: env.EMAIL_FROM, to: [to], subject: title, text, html,
                             headers: { "List-Unsubscribe": `<${off}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" } }),
    });
    if (!res.ok) console.log("email", res.status, await res.text());
  } catch (e) { console.log("email failed:", e.message); }
}

/** A booking result: an Apple push to the user's iPhones and an email; drops the devices Apple says are gone. */
async function notify(env, u, title, body, classId) {
  const [gone] = await Promise.all([push(env, u.devices, title, body, classId ? { classId } : {}), email(env, u, title, body, classId)]);
  u.devices = u.devices.filter((d) => !gone.includes(d.token));
}

// MARK: Users (D1)

// `users` predates migrations and is created on first use; challenges, participants and daily_counts come from
// ../migrations (npx wrangler d1 migrations apply bruce-autobook --remote).
const schemaReady = new WeakSet();
async function db(env) {
  if (!schemaReady.has(env.DB)) {
    await env.DB.prepare(`CREATE TABLE IF NOT EXISTS users (
      user_id INTEGER PRIMARY KEY, access_token TEXT NOT NULL, rules TEXT NOT NULL DEFAULT '[]',
      devices TEXT NOT NULL DEFAULT '[]', state TEXT NOT NULL DEFAULT '{}', updated_at TEXT)`).run();
    schemaReady.add(env.DB);
  }
  return env.DB;
}

// statsFrom/statsAt/detailFrom: how far back daily_counts (and its detail) are filled and when they were last read;
// goals: goals with "Reminder when behind" (PUT /me/goals); goalPings: when each goal last pushed a reminder.
const emptyState = () => ({ upcoming: [], handled: {}, log: [], lastScan: null, watches: [],
                            goals: [], goalPings: {}, statsFrom: null, statsAt: null, detailFrom: null });

function rowToUser(r) {
  return { userId: r.user_id, session: { access_token: r.access_token, user_id: r.user_id },
           rules: JSON.parse(r.rules), devices: JSON.parse(r.devices), state: { ...emptyState(), ...JSON.parse(r.state) } };
}

async function getUser(env, userId) {
  const r = await (await db(env)).prepare("SELECT * FROM users WHERE user_id = ?").bind(userId).first();
  return r ? rowToUser(r) : null;
}

async function saveUser(env, u) {
  await (await db(env)).prepare(`INSERT INTO users (user_id, access_token, rules, devices, state, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      ON CONFLICT(user_id) DO UPDATE SET access_token = ?2, rules = ?3, devices = ?4, state = ?5, updated_at = ?6`)
    .bind(u.userId, u.session.access_token, JSON.stringify(u.rules), JSON.stringify(u.devices), JSON.stringify(u.state), new Date().toISOString())
    .run();
}

async function deleteUser(env, userId) {
  await (await db(env)).prepare("DELETE FROM users WHERE user_id = ?").bind(userId).run();
}

/** Writes only the history fields of a user's state, so the daily refresh does not undo the minute cron's changes. */
async function saveStats(env, u) {
  const s = u.state;
  await (await db(env)).prepare(`UPDATE users SET state = json_set(state, '$.statsFrom', ?1, '$.statsAt', ?2, '$.detailFrom', ?3,
      '$.goalPings', json(?4)), devices = ?5 WHERE user_id = ?6`)
    .bind(s.statsFrom, s.statsAt, s.detailFrom, JSON.stringify(s.goalPings ?? {}), JSON.stringify(u.devices), u.userId).run();
}

async function inChallenge(env, userId) {
  return !!(await (await db(env)).prepare("SELECT 1 AS x FROM participants WHERE user_id = ? AND status = 'accepted' LIMIT 1").bind(userId).first());
}

/**
 * Keeps a user's row (and login) only while the server has something to do for them: auto-book rules, waitlist
 * watches, goal reminders, a push device or a challenge. Otherwise the row and the stored history go.
 */
async function keepOrDelete(env, u) {
  if (u.rules.length || u.state.watches.length || u.state.goals?.length || u.devices.length || (await inChallenge(env, u.userId))) {
    await saveUser(env, u);
    return true;
  }
  await deleteUser(env, u.userId);
  await (await db(env)).prepare("DELETE FROM daily_counts WHERE user_id = ?").bind(u.userId).run();
  return false;
}

// MARK: Cron

export async function scan(rules, session, state, now) {
  const found = new Map();
  for (const day of scanPlan(rules, now)) {
    for (const c of await fetchClasses(session.access_token, day.studioId, day.from, day.to)) {
      const start = Date.parse(c.start_time);
      if (start <= now || state.handled[c.id] || found.has(c.id)) continue;
      const rule = rules.find((r) => matches(r, c));
      if (rule) found.set(c.id, { classId: c.id, ruleId: rule.id, title: c.title, studioId: c.studio_id, start, opens: opensAt(c) });
    }
  }
  state.upcoming = [...found.values()].sort((a, b) => a.opens - b.opens);
  state.lastScan = new Date(now).toISOString();
}

const when = (ms) => new Date(ms).toLocaleString("en-GB", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit" });

/**
 * Waitlist watches ("book me as soon as a spot frees up"). Bruce does not book waitlisters itself (a "Free spot"
 * only notifies, see API.md), so the server polls the class and books when `available_spots` is above 0.
 * A watch ends when the class is booked, started, gone, or the user removes it; a lost race (someone else was
 * faster) keeps it. Returns false if the login died.
 */
export async function watchWaitlists(env, u, now, { bookFn = book, classFn = fetchClass } = {}) {
  const { state, session } = u;
  const minute = Math.floor(now / 60_000);
  const keep = [];
  let ok = true;
  for (const w of state.watches ?? []) {
    if (!ok || w.start <= now) continue;
    keep.push(w);
    if (w.retryAt && w.retryAt > now) continue;
    const near = w.start - now <= WATCH_NEAR_MS;
    if (!near && (minute + w.classId) % WATCH_FAR_EVERY_MIN !== u.userId % WATCH_FAR_EVERY_MIN) continue;
    let c;
    try { c = await classFn(session.access_token, w.classId); }
    catch (e) {
      if (e instanceof LoggedOut) { ok = false; continue; }
      console.log("watch failed:", u.userId, w.classId, e.message);   // try again next minute
      continue;
    }
    if (!c || c.deleted || c.deleted_at || c.canceled) { keep.pop(); continue; }
    if (!(c.available_spots > 0)) continue;
    const outcome = await bookFn(session, { classId: w.classId, opens: 0 });
    if (outcome === "Login expired") { ok = false; continue; }
    if (outcome === "Booked" || outcome === "Already booked") {
      keep.pop();
      state.log.unshift({ classId: w.classId, title: w.title, at: new Date().toISOString(), outcome: `${outcome} (waitlist)` });
      await notify(env, u, `${outcome}: ${w.title}`, `${when(w.start)} · a waitlist spot opened`, w.classId);
      continue;
    }
    // Spot taken by someone else in the meantime, or Bruce refuses (visit limit, ...): wait and look again.
    w.fails = (w.fails ?? 0) + 1;
    w.retryAt = now + WATCH_RETRY_MS;
    if (w.fails >= MAX_WATCH_FAILS) {
      keep.pop();
      state.log.unshift({ classId: w.classId, title: w.title, at: new Date().toISOString(), outcome: `Waitlist stopped: ${outcome}` });
      await notify(env, u, `Waitlist watch stopped: ${w.title}`, outcome, w.classId);
    }
  }
  state.watches = keep;
  return ok;
}

/** One user's minute: book what opens now, rescan when it is this user's turn. Returns false if the login died. */
export async function tickUser(env, u, now, { force = false, bookFn = book, classFn = fetchClass } = {}) {
  const { rules, session, state } = u;
  let loggedOut = false;
  const due = state.upcoming.filter((o) => o.opens <= now + DUE_AHEAD_MS && o.start > now && !state.handled[o.classId]);
  const results = await Promise.all(due.map((o) => bookFn(session, o).then((outcome) => ({ o, outcome }))));
  for (const { o, outcome } of results) {
    // Tried once: an auto-booked class that is cancelled later is not booked again.
    state.handled[o.classId] = o.start;
    state.log.unshift({ classId: o.classId, title: o.title, at: new Date().toISOString(), outcome });
    if (outcome === "Login expired") { loggedOut = true; continue; }
    await notify(env, u, `${outcome}: ${o.title}`, `${when(o.start)} · auto-book`, o.classId);
  }
  state.upcoming = state.upcoming.filter((o) => !state.handled[o.classId] && o.start > now);
  if (state.watches?.length && !loggedOut && !(await watchWaitlists(env, u, now, { bookFn, classFn }))) loggedOut = true;
  const minute = Math.floor(now / 60_000);
  if (!loggedOut && rules.length && (force || minute % SCAN_EVERY_MIN === u.userId % SCAN_EVERY_MIN || !state.lastScan)) {
    try { await scan(rules, session, state, now); }
    catch (e) {
      if (e instanceof LoggedOut) loggedOut = true;
      else console.log("scan failed:", u.userId, e.message);   // keep the last known classes; the next scan retries
    }
  }
  for (const [id, start] of Object.entries(state.handled)) if (start < now - 86400_000) delete state.handled[id];
  state.log = state.log.slice(0, LOG_SIZE);
  return !loggedOut;
}

export async function tick(env, now) {
  const { results } = await (await db(env)).prepare("SELECT * FROM users").all();
  await Promise.all(results.map(async (r) => {
    const u = rowToUser(r);
    const before = JSON.stringify([u.state, u.devices]);
    if (!(await tickUser(env, u, now))) {
      // Bruce rejected the login: forget it, and tell the user to open the app (which sends the new one).
      await notify(env, u, "Auto-book paused", "Your Bruce login expired. Open Brüce to continue.");
      await deleteUser(env, u.userId);
      return;
    }
    if (JSON.stringify([u.state, u.devices]) !== before) await saveUser(env, u);
  }));
}

// MARK: History (daily cron): challenges, goal reminders, Wrapped percentiles

/**
 * Re-reads one user's booking history into `daily_counts`. The first read goes back to January 1 (or the start of the
 * user's earliest challenge); later reads only the last few days (a check-in can be recorded late) and, with goal
 * reminders, the current month. Per-visit detail is stored only while the user is in a challenge. Sends due goal
 * reminders. Returns the number of Bruce requests made. Throws LoggedOut if Bruce rejects the login.
 */
export async function refreshHistory(env, u, now, { maxPages = BACKFILL_PAGES, fetchFn = fetchBookings } = {}) {
  const DB = await db(env);
  const s = u.state;
  const today = localDay(now);
  const yearStart = `${today.slice(0, 4)}-01-01`;
  const first = await DB.prepare(`SELECT MIN(c.start_day) AS start FROM challenges c JOIN participants p ON p.challenge_id = c.id
      WHERE p.user_id = ? AND p.status = 'accepted'`).bind(u.userId).first();
  const challengeStart = first?.start ?? null;
  const detail = challengeStart != null;
  const want = challengeStart && challengeStart < yearStart ? challengeStart : yearStart;
  const full = !s.statsFrom || s.statsFrom > want || (detail && (!s.detailFrom || s.detailFrom > want));
  let from = full ? want : [want, addDays(localDay(Date.parse(s.statsAt)), -3)].sort()[1];
  if (s.goals?.length && monthStart(today) < from) from = monthStart(today);
  const [y, m, d] = from.split("-").map(Number);
  const { bookings, pages, complete } = await fetchFn(u.session.access_token, u.userId, localMidnight(y, m, d), maxPages);
  let visits = visitsFromBookings(bookings, now);
  // A cut-off read (page budget) only replaces the days it fully covers.
  if (!complete && visits.length) from = [from, addDays(visits[visits.length - 1].day, 1)].sort()[1];
  visits = visits.filter((v) => v.day >= from);
  const insert = DB.prepare(`INSERT INTO daily_counts (user_id, day, visits, classes, dropins, minutes, checkins, checkin_minutes, studios, detail)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)`);
  await DB.batch([
    DB.prepare("DELETE FROM daily_counts WHERE user_id = ? AND day >= ?").bind(u.userId, from),
    ...dailyRows(visits, { detail }).map((r) => insert.bind(u.userId, r.day, r.visits, r.classes, r.dropins, r.minutes, r.checkins,
                                                            r.checkin_minutes, JSON.stringify(r.studios), r.detail ? JSON.stringify(r.detail) : null)),
  ]);
  if (full && complete) { s.statsFrom = want; s.detailFrom = detail ? want : null; }
  if (!detail) s.detailFrom = null;
  s.statsAt = new Date(now).toISOString();
  // Goal reminders: this month's checked-in visits are in `visits` (from <= the 1st when there are goals).
  s.goalPings = Object.fromEntries(Object.entries(s.goalPings ?? {}).filter(([id]) => s.goals?.some((g) => g.id === id)));
  for (const r of goalReminders(s.goals, visits, today, s.goalPings, now)) {
    const gone = await push(env, u.devices, "Behind on your goal", `${r.goal.title}: ${r.count} of ${r.goal.target} so far, ${r.daysLeft} days left.`,
                            { goalId: r.goal.id }, "GOAL_REMINDER");
    u.devices = u.devices.filter((x) => !gone.includes(x.token));
    s.goalPings[r.goal.id] = now;
  }
  return pages;
}

/** The daily cron: refreshes users not yet refreshed today, least recently refreshed first, within DAILY_BUDGET. */
export async function daily(env, now, { fetchFn = fetchBookings } = {}) {
  const { results } = await (await db(env)).prepare("SELECT * FROM users").all();
  const users = results.map(rowToUser).sort((a, b) => String(a.state.statsAt ?? "").localeCompare(String(b.state.statsAt ?? "")));
  let budget = +(env.DAILY_BUDGET ?? DAILY_BUDGET);
  const today = localDay(now);
  for (const u of users) {
    if (budget <= 0) break;
    if (u.state.statsAt && localDay(Date.parse(u.state.statsAt)) === today) continue;
    try {
      budget -= await refreshHistory(env, u, now, { maxPages: Math.min(budget, BACKFILL_PAGES), fetchFn });
      await saveStats(env, u);
    } catch (e) {
      if (!(e instanceof LoggedOut)) { console.log("history failed:", u.userId, e.message); continue; }
      await push(env, u.devices, "Brüce paused", "Your Bruce login expired. Open Brüce to continue.");
      await deleteUser(env, u.userId);
    }
  }
}

// MARK: HTTP API

// The web app calls this server from the browser; it authenticates with headers, not cookies, so any origin is fine.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, PUT, DELETE, POST, OPTIONS",
  "Access-Control-Allow-Headers": "X-Access-Token, X-User-Id, Content-Type",
};

function json(data, status = 200) {
  return new Response(status === 204 ? null : JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...CORS } });
}

/** `GET|POST /email/off?u=<userId>&t=<token>`: the unsubscribe link in every email (POST is the one-click header). */
async function unsubscribeRoute(request, env) {
  const q = new URL(request.url).searchParams;
  const userId = parseInt(q.get("u") ?? "", 10);
  const page = (msg, status = 200) => new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">`
    + `<title>Brüce auto-book</title><p style="font:17px -apple-system,sans-serif;margin:3em auto;max-width:30em;padding:0 1em">${msg}</p>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } });
  if (!emailConfigured(env) || !userId || q.get("t") !== (await unsubscribeToken(env, userId))) return page("This link is not valid.", 400);
  const u = await getUser(env, userId);
  if (u && !u.state.emailOff) { u.state.emailOff = true; await saveUser(env, u); }
  return page("Done. The auto-book server won't email you any more. Push notifications in the app stay on.");
}

/** `PUT|DELETE /me/waitlist/<classId>`: start or stop watching a full class. Creates the user's row if needed. */
async function watchRoute(request, env, classId) {
  const auth = await authenticate(request, env);
  if (!auth) return json({ error: "unauthorized" }, 401);
  const u = (await getUser(env, auth.userId)) ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
  signIn(u, auth);
  if (request.method === "DELETE") {
    u.state.watches = u.state.watches.filter((w) => w.classId !== classId);
    // Keep the row only while it has something to do.
    await keepOrDelete(env, u);
    return json({ ok: true, watches: u.state.watches.length });
  }
  const existing = u.state.watches.find((w) => w.classId === classId);
  if (!existing) {
    if (u.state.watches.length >= MAX_WATCHES) return json({ error: `at most ${MAX_WATCHES} waitlist watches` }, 409);
    let c;
    try { c = await fetchClass(auth.token, classId); } catch { return json({ error: "Bruce is not answering" }, 502); }
    const start = c ? Date.parse(c.start_time) : NaN;
    if (!c || c.deleted || c.deleted_at || c.canceled || !(start > Date.now())) return json({ error: "class not found or already started" }, 404);
    u.state.watches.push({ classId, title: String(c.title).slice(0, 200), studioId: c.studio_id, start });
  }
  await saveUser(env, u);
  return json({ ok: true, watches: u.state.watches.length, push: apnsConfigured(env) && u.devices.length > 0 });
}

/** The caller's Bruce user id if `X-Access-Token` is a live Bruce login for `X-User-Id`, else null. */
export async function authenticate(request, env) {
  const token = request.headers.get("X-Access-Token");
  const userId = parseInt(request.headers.get("X-User-Id") ?? "", 10);
  if (!token || !userId) return null;
  const allowed = (env.ALLOWED_USERS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (allowed.length && !allowed.includes(String(userId))) return null;
  const res = await bruce("GET", `/v52/user/${userId}`, token, { query: [["locale", "en"]] }).catch(() => null);
  if (!res?.ok) return null;
  const body = await res.json().catch(() => null);
  if (body?.user?.id !== userId) return null;
  const email = typeof body.user.email === "string" && /^[^\s@]+@[^\s@]+$/.test(body.user.email) ? body.user.email.slice(0, 200) : null;
  return { userId, token, email, name: String(body.user.first_name ?? body.user.display_name ?? "").slice(0, 60) };
}

/** Stores the caller's current login and Bruce email on their row. */
function signIn(u, auth) {
  u.session = { access_token: auth.token, user_id: auth.userId };
  if (auth.email) u.state.email = auth.email;
}

function cleanRules(rules) {
  return rules.slice(0, 30).map((r) => ({ id: String(r.id), studioId: +r.studioId, masterId: r.masterId ?? null, title: String(r.title).slice(0, 200),
                                          weekday: +r.weekday, minuteOfDay: +r.minuteOfDay }));
}

function cleanDevice(d) {
  if (!d || typeof d.token !== "string" || !/^[0-9a-f]{32,200}$/i.test(d.token)) return null;
  return { token: d.token.toLowerCase(), env: d.env === "sandbox" ? "sandbox" : "production" };
}

// MARK: Challenges, goals and percentiles (HTTP)

/** The address booking results are emailed to, or null (no Resend key, no address, or unsubscribed). */
const emailTo = (env, u) => (emailConfigured(env) && !u.state.emailOff && u.state.email) || null;

const newId = () => {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  return [...crypto.getRandomValues(new Uint8Array(12))].map((b) => abc[b % abc.length]).join("");
};

const rowToChallenge = (r) => ({ id: r.id, ownerId: r.owner_id, title: r.title, metric: r.metric, target: r.target ?? null,
  category: r.category ?? null, categoryTitle: r.category_title ?? null, start: r.start_day, end: r.end_day,
  repeatMonthly: !!r.repeat_monthly, createdAt: r.created_at });

async function loadChallenge(DB, id) {
  const r = await DB.prepare("SELECT * FROM challenges WHERE id = ?").bind(id).first();
  if (!r) return null;
  const { results } = await DB.prepare("SELECT user_id, name, status FROM participants WHERE challenge_id = ? ORDER BY joined_at IS NULL, joined_at, user_id").bind(id).all();
  return { ch: rowToChallenge(r), participants: results.map((p) => ({ userId: p.user_id, name: p.name, status: p.status })) };
}

function summary({ ch, participants }, userId, today) {
  const me = participants.find((p) => p.userId === userId);
  return { ...ch, ownerName: participants.find((p) => p.userId === ch.ownerId)?.name ?? null, myStatus: me?.status ?? null,
           participants, period: challengePeriod(ch, today), shareUrl: SHARE_URL + ch.id };
}

/** The caller's row with their current login, created if needed (joining a challenge stores the login, auto-book or not). */
async function rememberLogin(env, auth) {
  const u = (await getUser(env, auth.userId)) ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
  signIn(u, auth);
  await saveUser(env, u);
  return u;
}

/** Reads the user's history in the background (after joining a challenge), within the request's own budget. */
function backfill(env, ctx, u) {
  ctx.waitUntil(refreshHistory(env, u, Date.now()).then(() => saveStats(env, u)).catch((e) => console.log("backfill failed:", u.userId, e.message)));
}

async function pushTo(env, userId, title, body, data, category) {
  const u = await getUser(env, userId);
  if (!u?.devices.length) return;
  const gone = await push(env, u.devices, title, body, data, category);
  if (gone.length) { u.devices = u.devices.filter((d) => !gone.includes(d.token)); await saveUser(env, u); }
}

function cleanGoals(goals) {
  return goals.filter((g) => g && g.remind !== false).slice(0, MAX_GOALS).map((g) => ({
    id: String(g.id ?? "").slice(0, 64), title: String(g.title ?? "Goal").slice(0, 80),
    category: g.category == null || g.category === "" ? null : String(g.category).slice(0, 40),
    studioId: Number.isInteger(g.studioId) ? g.studioId : null, target: Math.max(1, Math.min(200, Math.round(+g.target) || 1)),
  })).filter((g) => g.id);
}

/** `/challenges...`, `GET /wrapped/percentiles`, `PUT /me/goals` (see ../README.md). */
async function insightsRoute(request, env, ctx, path) {
  const auth = await authenticate(request, env);
  if (!auth) return json({ error: "unauthorized" }, 401);
  const DB = await db(env);
  const now = Date.now();
  const today = localDay(now);
  const route = `${request.method} ${path.replace(/^\/challenges\/[^/]+/, "/challenges/:id")}`;
  const id = path.split("/")[2];

  // Keep the stored login current: the daily cron reads history with it.
  const known = await getUser(env, auth.userId);
  if (known && known.session.access_token !== auth.token) { known.session.access_token = auth.token; await saveUser(env, known); }

  switch (route) {
    case "PUT /me/goals": {
      const body = await request.json().catch(() => ({}));
      if (!Array.isArray(body.goals)) return json({ error: "goals must be an array" }, 400);
      const goals = cleanGoals(body.goals);
      if (!goals.length && !known) return json({ ok: true, goals: 0 });
      const u = known ?? (await rememberLogin(env, auth));
      u.state.goals = goals;
      await keepOrDelete(env, u);
      if (goals.length && !u.state.statsAt) backfill(env, ctx, u);
      return json({ ok: true, goals: goals.length });
    }

    case "GET /wrapped/percentiles": {
      const q = new URL(request.url).searchParams;
      const year = /^\d{4}$/.test(q.get("year") ?? "") ? q.get("year") : today.slice(0, 4);
      const mine = Object.fromEntries(PERCENTILE_METRICS.filter((k) => q.has(k)).map((k) => [k, Number(q.get(k))]));
      const { results } = await DB.prepare(`SELECT user_id, day, checkins, checkin_minutes, studios FROM daily_counts
          WHERE day >= ? AND day <= ? AND user_id != ? AND checkins > 0`).bind(`${year}-01-01`, `${year}-12-31`, auth.userId).all();
      const cohort = cohortValues(results);
      return json({ year: +year, cohort: cohort.length, percentiles: percentiles(cohort, mine) });
    }

    case "POST /challenges": {
      const body = await request.json().catch(() => ({}));
      const c = cleanChallenge(body, today);
      if (c.error) return json({ error: c.error }, 400);
      let friends;
      try { friends = await fetchFriends(auth.token, auth.userId); } catch { return json({ error: "Bruce is not answering" }, 502); }
      const wanted = new Set((Array.isArray(body.invite) ? body.invite : []).map(Number));
      const invitees = friends.filter((f) => wanted.has(f.id) && f.id !== auth.userId).slice(0, MAX_INVITES);
      const chId = newId();
      const at = new Date(now).toISOString();
      await DB.batch([
        DB.prepare(`INSERT INTO challenges (id, owner_id, title, metric, target, category, category_title, start_day, end_day, repeat_monthly, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`)
          .bind(chId, auth.userId, c.title, c.metric, c.target, c.category, c.categoryTitle, c.start, c.end, c.repeatMonthly ? 1 : 0, at),
        DB.prepare("INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?, ?, ?, 'accepted', NULL, ?)")
          .bind(chId, auth.userId, auth.name, at),
        ...invitees.map((f) => DB.prepare("INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?, ?, ?, 'invited', ?, NULL)")
          .bind(chId, f.id, f.name, auth.userId)),
      ]);
      const u = await rememberLogin(env, auth);
      backfill(env, ctx, u);
      const loaded = await loadChallenge(DB, chId);
      const label = challengePeriod(loaded.ch, today).label;
      await Promise.all(invitees.map((f) => pushTo(env, f.id, `${auth.name || "A friend"} challenged you`, `${c.title} · ${label}. Tap to accept.`,
                                                   { challengeId: chId }, "CHALLENGE_INVITE")));
      return json({ challenge: summary(loaded, auth.userId, today) }, 201);
    }

    case "GET /challenges": {
      const { results } = await DB.prepare(`SELECT c.id FROM challenges c JOIN participants p ON p.challenge_id = c.id
          WHERE p.user_id = ? ORDER BY c.created_at DESC`).bind(auth.userId).all();
      const challenges = [];
      for (const r of results) { const l = await loadChallenge(DB, r.id); if (l) challenges.push(summary(l, auth.userId, today)); }
      let usesBruce = [];
      try {
        const friendIds = new Set((await fetchFriends(auth.token, auth.userId)).map((f) => f.id));
        const { results: rows } = await DB.prepare("SELECT user_id FROM users").all();
        usesBruce = rows.map((r) => r.user_id).filter((x) => friendIds.has(x));
      } catch (e) { console.log("friends failed:", e.message); }
      return json({ challenges, usesBruce });
    }

    case "GET /challenges/:id": {
      const l = await loadChallenge(DB, id);
      if (!l) return json({ error: "challenge not found" }, 404);
      if (!l.participants.some((p) => p.userId === auth.userId)) {
        // Share-link preview: no names besides the owner, no numbers.
        let joinable = false;
        try { joinable = (await fetchFriends(auth.token, auth.userId)).some((f) => f.id === l.ch.ownerId); } catch {}
        const { id: cid, title, metric, target, categoryTitle } = l.ch;
        return json({ challenge: { id: cid, title, metric, target, categoryTitle, period: challengePeriod(l.ch, today),
                                   ownerName: summary(l, auth.userId, today).ownerName,
                                   participantCount: l.participants.filter((p) => p.status === "accepted").length }, joinable });
      }
      const accepted = l.participants.filter((p) => p.status === "accepted").map((p) => p.userId);
      const { results } = await DB.prepare(`SELECT user_id, day, detail FROM daily_counts WHERE day >= ? AND day <= ? AND detail IS NOT NULL
          AND user_id IN (${accepted.map(() => "?").join(",") || "NULL"})`).bind(l.ch.start, today, ...accepted).all();
      const visitsByUser = new Map();
      for (const r of results) {
        const list = visitsByUser.get(r.user_id) ?? [];
        for (const d of JSON.parse(r.detail)) list.push(fromDetail(d, r.day));
        visitsByUser.set(r.user_id, list);
      }
      const stats = challengeStats(l.ch, l.participants, visitsByUser, auth.userId, today);
      return json({ challenge: summary(l, auth.userId, today), leaderboard: stats.leaderboard, months: stats.months,
                    updatedAt: known?.state.statsAt ?? null });
    }

    case "POST /challenges/:id/accept":
    case "POST /challenges/:id/join": {
      const l = await loadChallenge(DB, id);
      if (!l) return json({ error: "challenge not found" }, 404);
      const me = l.participants.find((p) => p.userId === auth.userId);
      if (!me && route.endsWith("/accept")) return json({ error: "you are not invited to this challenge" }, 403);
      if (!me) {
        // Share link: only the owner's Bruce friends may join (friends see each other's visits).
        let friends;
        try { friends = await fetchFriends(auth.token, auth.userId); } catch { return json({ error: "Bruce is not answering" }, 502); }
        if (!friends.some((f) => f.id === l.ch.ownerId)) return json({ error: "only friends of the creator can join" }, 403);
        if (l.participants.length > MAX_INVITES) return json({ error: "this challenge is full" }, 409);
      }
      if (me?.status !== "accepted") {
        await DB.prepare(`INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?1, ?2, ?3, 'accepted', NULL, ?4)
            ON CONFLICT(challenge_id, user_id) DO UPDATE SET status = 'accepted', name = CASE WHEN ?3 = '' THEN name ELSE ?3 END, joined_at = ?4`)
          .bind(id, auth.userId, auth.name, new Date(now).toISOString()).run();
        const u = await rememberLogin(env, auth);
        backfill(env, ctx, u);
        if (l.ch.ownerId !== auth.userId) {
          await pushTo(env, l.ch.ownerId, `${auth.name || "A friend"} joined ${l.ch.title}`, "Your challenge has a new rival.", { challengeId: id }, "CHALLENGE_INVITE");
        }
      }
      return json({ ok: true, challenge: summary(await loadChallenge(DB, id), auth.userId, today) });
    }

    case "POST /challenges/:id/leave": {
      const l = await loadChallenge(DB, id);
      if (!l || !l.participants.some((p) => p.userId === auth.userId)) return json({ ok: true });
      await DB.prepare("DELETE FROM participants WHERE challenge_id = ? AND user_id = ?").bind(id, auth.userId).run();
      if (!l.participants.some((p) => p.userId !== auth.userId && p.status === "accepted")) {
        await DB.batch([DB.prepare("DELETE FROM participants WHERE challenge_id = ?").bind(id), DB.prepare("DELETE FROM challenges WHERE id = ?").bind(id)]);
      }
      if (!(await inChallenge(env, auth.userId))) {
        // "Leave anytime; your numbers are deleted": the per-visit detail goes with the last challenge.
        await DB.prepare("UPDATE daily_counts SET detail = NULL WHERE user_id = ?").bind(auth.userId).run();
        if (known) { known.state.detailFrom = null; await keepOrDelete(env, known); }
      }
      return json({ ok: true });
    }
  }
  return json({ error: "not found" }, 404);
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(event.cron === DAILY_CRON ? daily(env, event.scheduledTime) : tick(env, event.scheduledTime));
  },

  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    const route = `${request.method} ${pathname.replace(/\/+$/, "")}`;
    if (request.method === "OPTIONS") return json({}, 204);
    const path = pathname.replace(/\/+$/, "");
    if (path === "/challenges" || path.startsWith("/challenges/") || path === "/wrapped/percentiles" || route === "PUT /me/goals") {
      return insightsRoute(request, env, ctx, path);
    }
    if (path === "/email/off" && (request.method === "GET" || request.method === "POST")) return unsubscribeRoute(request, env);
    const watch = path.match(/^\/me\/waitlist\/(\d+)$/);
    if (watch && (request.method === "PUT" || request.method === "DELETE")) return watchRoute(request, env, +watch[1]);
    if (!["PUT /me", "GET /me", "DELETE /me", "POST /me/test-push", "PUT /me/email"].includes(route)) return json({ error: "not found" }, 404);
    const auth = await authenticate(request, env);
    if (!auth) return json({ error: "unauthorized" }, 401);
    switch (route) {
      case "PUT /me": {
        // Upsert: the current login, the rules, and this device's push token.
        const body = await request.json().catch(() => ({}));
        if (!Array.isArray(body.rules)) return json({ error: "rules must be an array" }, 400);
        const u = (await getUser(env, auth.userId)) ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
        signIn(u, auth);
        const rulesChanged = JSON.stringify(u.rules) !== JSON.stringify(cleanRules(body.rules));
        u.rules = cleanRules(body.rules);
        const d = cleanDevice(body.device);
        if (d) u.devices = [d, ...u.devices.filter((x) => x.token !== d.token)].slice(0, MAX_DEVICES);
        if (rulesChanged) await tickUser(env, u, Date.now(), { force: true }).catch((e) => console.log("scan failed:", e.message));
        await saveUser(env, u);
        return json({ ok: true, rules: u.rules.length, push: apnsConfigured(env) && u.devices.length > 0, email: emailTo(env, u) });
      }
      case "GET /me": {
        const u = await getUser(env, auth.userId);
        const opens = (o) => ({ classId: o.classId, title: o.title, at: new Date(o.opens).toISOString(), outcome: "Opens" });
        return json({ hasSession: !!u, rules: u?.rules ?? [], lastScan: u?.state.lastScan ?? null,
                      upcoming: (u?.state.upcoming ?? []).map(opens),
                      waitlist: (u?.state.watches ?? []).map((w) => ({ classId: w.classId, title: w.title, start: new Date(w.start).toISOString() })), log: u?.state.log ?? [], devices: u?.devices.length ?? 0,
                      email: u ? emailTo(env, u) : null });
      }
      case "DELETE /me": {
        // Auto-book off: forget rules, watches and goals. The login stays while the user is in a challenge.
        const u = await getUser(env, auth.userId);
        if (u && (await inChallenge(env, auth.userId))) {
          u.rules = [];
          Object.assign(u.state, { upcoming: [], watches: [], goals: [], goalPings: {} });
          await saveUser(env, u);
          return json({ ok: true, kept: "challenges" });
        }
        await deleteUser(env, auth.userId);
        await (await db(env)).prepare("DELETE FROM daily_counts WHERE user_id = ?").bind(auth.userId).run();
        return json({ ok: true });
      }
      case "PUT /me/email": {
        // {"enabled": false} stops the booking emails, {"enabled": true} starts them again.
        const body = await request.json().catch(() => ({}));
        const u = await getUser(env, auth.userId);
        if (!u) return json({ error: "auto-book is off" }, 404);
        signIn(u, auth);
        u.state.emailOff = body.enabled === false;
        await saveUser(env, u);
        return json({ ok: true, email: emailTo(env, u) });
      }
      case "POST /me/test-push": {
        const u = await getUser(env, auth.userId);
        if (!u?.devices.length || !apnsConfigured(env)) return json({ error: "no device or push not configured" }, 409);
        await push(env, u.devices, "Auto-book is set up", "You'll get a push like this when a class is booked.");
        return json({ ok: true });
      }
    }
  },
};
