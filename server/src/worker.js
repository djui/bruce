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
//
// Skipped habits: the same daily read spots a weekly class the user did 3+ weeks in a row and then skipped (nothing
// visited or booked for 4 days after), picks upcoming classes from their history and pushes them at 08:00 local
// (table `nudges`). The pure logic is in ./habits.js.
//
// Race reminders (Train for it): races in My races with a race-week or day-before reminder (`PUT /me/races`, table
// `user_races`) get a push and an email at 08:00 local on the Monday of race week and a push at 18:00 the day before,
// each once, from the minute cron.
//
// Friends going and race crews: a race in My races marked going (`PUT /me/races` `going`) is shown to the member's
// Bruce friends who share a race too (`GET /races/going`, friends checked with Bruce on each call). A crew is a
// challenge with `race_id` and `weekly` that ends on race day; the minute cron tells its members on Sunday at 19:00 how
// many hit their sessions that week (table `crew_updates`, once per crew and week).

import {
  localDay, addDays, monthStart, visitsFromBookings, dailyRows, fromDetail, goalReminders, challengePeriod, challengeStats,
  cleanChallenge, cohortValues, percentiles, PERCENTILE_METRICS, crewWeeks, crewMessage, mondayOf,
} from "./insights.js";
import { brokenHabit, recommendClasses, nudgeMessage, cleanLapseDays, HABIT_LOOKBACK_DAYS, RECOMMEND_DAYS, LAPSE_DAYS } from "./habits.js";

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
/// One-off "Book when booking opens" watches (a listed class that is not bookable yet; `PUT /me/opening/<id>`): booked
/// once at its open moment like a weekly class, same retries and late-spot rule. Capped per user, no polling.
const MAX_OPENS = 5;
const WATCH_NEAR_MS = 24 * 3600_000;
const WATCH_FAR_EVERY_MIN = 5;
/// After a failed booking attempt on a free spot the watch waits this long, and is dropped after MAX_WATCH_FAILS.
const WATCH_RETRY_MS = 5 * 60_000;
const MAX_WATCH_FAILS = 5;
/// Late spots (Bruce's strike policy since June 2026, Copy.swift): cancelling is free until the class's
/// `unbookable_latest_time` (12 h before when the class does not say), costs 1 strike until 3 h before, 2 until 1 h
/// before, then 3, as does a no-show (3 strikes block booking for 14 days). A spot that frees up after the free
/// cancellation is booked or offered as the user chose (`lateSpots`, default "ask"); from 3 h before the class, when
/// cancelling costs 2 strikes or more, it is always offered: a push with a Book button (category LATE_SPOT), not a booking.
const FREE_CANCEL_S = 12 * 3600;
const ALWAYS_ASK_MS = 3 * 3600_000;
const LAST_MINUTE_MS = 3600_000;
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
/// Skipped-habit pushes go out at this local hour (the daily run plans them at night).
const NUDGE_HOUR = 8;
/// Class list pages per studio when picking classes for a skipped-habit push (30 classes each).
const NUDGE_PAGES = 4;
/// Races with race-day reminders per user (`PUT /me/races`), and the web app's race page for the email link.
const MAX_RACES = 20;
const RACE_URL = "https://djui.github.io/bruce/app/#/mine/race/";
/// Race reminders go out at these local hours; one that is due is still sent this long after (the cron missed a
/// minute, the race was added late), later it is dropped.
const RACE_WEEK_HOUR = 8;
const RACE_EVE_HOUR = 18;
const RACE_PRICE_HOUR = 9;   // "Price goes up tomorrow", the day before the step (as the apps' local notification)
const RACE_LATE_MS = 12 * 3600_000;
/// The crew push goes out on Sunday at this local hour, at most this long after; each minute run spends at most
/// CREW_BUDGET requests on it (booking pages for today's visits of members not at their target yet, and APNs pushes).
const CREW_HOUR = 19;
const CREW_LATE_MS = 2 * 3600_000;
const CREW_BUDGET = 20;

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

/** UTC ms of `hour`:00 local on a local date, also on the days summer time starts or ends. */
export function localAt(y, m, d, hour) {
  const t = localMidnight(y, m, d) + hour * 3600_000;
  return t + (hour - localParts(t).hour) * 3600_000;
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

// MARK: Late spots

/** When cancelling a booking of this class starts to cost a strike. */
export function freeCancelUntil(c) {
  const t = c.unbookable_latest_time ? Date.parse(c.unbookable_latest_time) : NaN;
  if (!Number.isNaN(t)) return t;
  const s = Number.isFinite(+c.unbookable_latest) && c.unbookable_latest != null ? +c.unbookable_latest : FREE_CANCEL_S;
  return Date.parse(c.start_time) - s * 1000;
}

/** "book" or "ask" for a spot that is free now: booked while cancelling is free, then as the user chose, under 3 h asked. */
export function lateSpotAction(start, freeUntil, now, lateSpots) {
  if (now < freeUntil) return "book";
  if (start - now < ALWAYS_ASK_MS) return "ask";
  return lateSpots === "book" ? "book" : "ask";
}

/** Strikes a cancellation costs at `now`: 0 while free, 1 until 3 h before, 2 until 1 h before, then 3. */
export function cancelStrikes(start, freeUntil, now) {
  if (now < freeUntil) return 0;
  return start - now < LAST_MINUTE_MS ? 3 : start - now < ALWAYS_ASK_MS ? 2 : 1;
}
const strikes = (n) => `${n} strike${n === 1 ? "" : "s"}`;

/** The line about cancelling under a "Booked" push. */
export function cancelNote(start, freeUntil, now) {
  switch (cancelStrikes(start, freeUntil, now)) {
    case 0: return `Free cancel until ${clock(freeUntil)}.`;
    case 1: return `Can't make it? Cancel before ${clock(start - ALWAYS_ASK_MS)}: 1 strike. Before ${clock(start - LAST_MINUTE_MS)}: 2. After that, or a no-show: 3.`;
    case 2: return `Can't make it? Cancel before ${clock(start - LAST_MINUTE_MS)}: 2 strikes. After that, or a no-show: 3.`;
    default: return "Cancelling or a no-show now costs 3 strikes.";
  }
}

/** The push for a spot that is offered instead of booked (always after the free cancellation). */
export function askMessage(title, start, now, waitlist) {
  return { title: `${waitlist ? "Spot free" : "Open for booking"}: ${title}`,
           body: `${when(start)}. Cancelling after booking costs ${strikes(cancelStrikes(start, now, now))}. Book only if you'll go.` };
}

// MARK: Bruce API

function bruce(method, path, token, { query, body } = {}) {
  const url = new URL(path, API);
  for (const [k, v] of query ?? []) url.searchParams.append(k, v);
  const headers = { Accept: "application/json", "User-Agent": USER_AGENT, "Accept-Language": "en-US", "X-Access-Token": token };
  if (body) headers["Content-Type"] = "application/json";
  return fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
}

export async function fetchClasses(token, studioId, from, to, { maxPages = 10, meter = {} } = {}) {
  const out = [];
  let cursor;
  for (let page = 0; page < maxPages; page++) {
    const query = [
      ["studio_id", String(studioId)], ["presentation_studio_id", String(studioId)],
      ["start_time_after", new Date(from).toISOString().replace(/\.\d{3}Z$/, "Z")],
      ["start_time_before", new Date(to).toISOString().replace(/\.\d{3}Z$/, "Z")],
      ["limit", "30"], ["is_recurring_base", "false"], ["is_master", "false"], ["dedicated", "false"],
      ["opening", "false"], ["deleted", "false"], ["include_absolute_times", "true"], ["locale", "en"],
    ];
    if (cursor) query.push(["next_cursor", cursor]);
    const res = await bruce("GET", "/v52/class", token, { query });
    meter.pages = (meter.pages ?? 0) + 1;
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

/** Sends one booking result (or race reminder, with `link`) to the user's Bruce email (if known, not unsubscribed and
 *  Resend is set up). */
export async function email(env, u, title, body, classId, { link: other, linkText = "Open the class" } = {}) {
  const to = u.state.email;
  if (!emailConfigured(env) || !to || u.state.emailOff) return;
  const off = `${env.PUBLIC_URL ?? DEFAULT_PUBLIC_URL}/email/off?u=${u.userId}&t=${await unsubscribeToken(env, u.userId)}`;
  const link = other ?? (classId ? CLASS_URL + classId : null);
  const text = [body, link && `${linkText}: ${link}`, "", `Sent by the Brüce auto-book server. No more emails: ${off}`].filter((l) => l != null).join("\n");
  const html = `<p style="font-size:16px">${escapeHtml(body)}</p>${link ? `<p><a href="${escapeHtml(link)}">${escapeHtml(linkText)}</a></p>` : ""}`
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

/**
 * A booking result: an Apple push to the user's iPhones and an email; drops the devices Apple says are gone. Category
 * AUTOBOOK_BOOKED (a booking: Cancel button), LATE_SPOT (an offered spot: Book button) or AUTOBOOK_RESULT (the rest).
 */
async function notify(env, u, title, body, classId, category = "AUTOBOOK_RESULT") {
  const [gone] = await Promise.all([push(env, u.devices, title, body, classId ? { classId } : {}, category), email(env, u, title, body, classId)]);
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
// goals: goals with "Reminder when behind" (PUT /me/goals); goalPings: when each goal last pushed a reminder;
// nudges: false when the user switched off skipped-habit pushes (on by default); nudgeDays: their quiet days (default 4);
// lateSpots: "book" or "ask" (default) for spots that free up after the free cancellation (see FREE_CANCEL_S).
const emptyState = () => ({ upcoming: [], handled: {}, log: [], lastScan: null, watches: [], opens: [],
                            goals: [], goalPings: {}, statsFrom: null, statsAt: null, detailFrom: null, nudges: true });

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
  const DB = await db(env);
  await DB.batch([DB.prepare("DELETE FROM users WHERE user_id = ?").bind(userId), DB.prepare("DELETE FROM nudges WHERE user_id = ?").bind(userId),
                  DB.prepare("DELETE FROM user_races WHERE user_id = ?").bind(userId)]);
}

async function hasRaces(env, userId) {
  return !!(await (await db(env)).prepare("SELECT 1 AS x FROM user_races WHERE user_id = ? LIMIT 1").bind(userId).first());
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
 * watches, goal reminders, race reminders, a push device or a challenge. Otherwise the row and the stored history go.
 */
async function keepOrDelete(env, u) {
  if (u.rules.length || u.state.watches.length || u.state.opens?.length || u.state.goals?.length || u.devices.length
      || (await hasRaces(env, u.userId)) || (await inChallenge(env, u.userId))) {
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
      if (rule) found.set(c.id, { classId: c.id, ruleId: rule.id, title: c.title, studioId: c.studio_id, start, opens: opensAt(c),
                                  freeUntil: freeCancelUntil(c) });
    }
  }
  state.upcoming = [...found.values()].sort((a, b) => a.opens - b.opens);
  state.lastScan = new Date(now).toISOString();
}

const when = (ms) => new Date(ms).toLocaleString("en-GB", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit" });
const clock = (ms) => new Date(ms).toLocaleString("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit" });

/**
 * Waitlist watches ("book me as soon as a spot frees up"). Bruce does not book waitlisters itself (a "Free spot"
 * only notifies, see API.md), so the server polls the class and books when `available_spots` is above 0.
 * A watch ends when the class is booked, started, gone, or the user removes it; a lost race (someone else was
 * faster) keeps it. After the free cancellation a free spot may be offered instead (`lateSpotAction`): one push per
 * freed spot (`offered` until the class is full again), and the watch stays. Returns false if the login died.
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
    if (!(c.available_spots > 0)) { delete w.offered; continue; }
    const start = Date.parse(c.start_time) || w.start;
    const freeUntil = freeCancelUntil({ ...c, start_time: new Date(start).toISOString() });
    if (lateSpotAction(start, freeUntil, now, state.lateSpots) === "ask") {
      if (w.offered) continue;
      w.offered = true;
      state.log.unshift({ classId: w.classId, title: w.title, at: new Date().toISOString(), outcome: "Spot offered (waitlist)" });
      const m = askMessage(w.title, start, now, true);
      await notify(env, u, m.title, m.body, w.classId, "LATE_SPOT");
      continue;
    }
    const outcome = await bookFn(session, { classId: w.classId, opens: 0 });
    if (outcome === "Login expired") { ok = false; continue; }
    if (outcome === "Booked" || outcome === "Already booked") {
      keep.pop();
      state.log.unshift({ classId: w.classId, title: w.title, at: new Date().toISOString(), outcome: `${outcome} (waitlist)` });
      await notify(env, u, `${outcome}: ${w.title}`, `${when(w.start)} · a waitlist spot opened. ${cancelNote(start, freeUntil, now)}`,
                   w.classId, "AUTOBOOK_BOOKED");
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

/**
 * One user's minute: book what opens now, rescan when it is this user's turn. A class that only opens (or is only
 * found) after its free cancellation is offered instead as `lateSpotAction` says. Returns false if the login died.
 */
export async function tickUser(env, u, now, { force = false, bookFn = book, classFn = fetchClass } = {}) {
  const { rules, session, state } = u;
  let loggedOut = false;
  // Weekly occurrences plus one-off "book when it opens" watches (a class in both is tried once).
  const all = [...state.upcoming, ...(state.opens ?? []).filter((o) => !state.upcoming.some((x) => x.classId === o.classId))];
  const due = all.filter((o) => o.opens <= now + DUE_AHEAD_MS && o.start > now && !state.handled[o.classId]);
  // At the open moment; an occurrence from before freeUntil was stored counts 12 h.
  const freeUntil = (o) => o.freeUntil ?? o.start - FREE_CANCEL_S * 1000;
  const at = (o) => Math.max(now, o.opens);
  const offer = due.filter((o) => lateSpotAction(o.start, freeUntil(o), at(o), state.lateSpots) === "ask");
  for (const o of offer) {
    state.handled[o.classId] = o.start;
    state.log.unshift({ classId: o.classId, title: o.title, at: new Date().toISOString(), outcome: o.once ? "Offered (opened late, one-off)" : "Offered (opened late)" });
    const m = askMessage(o.title, o.start, at(o), false);
    await notify(env, u, m.title, m.body, o.classId, "LATE_SPOT");
  }
  const results = await Promise.all(due.filter((o) => !offer.includes(o)).map((o) => bookFn(session, o).then((outcome) => ({ o, outcome }))));
  for (const { o, outcome } of results) {
    // Tried once: an auto-booked class that is cancelled later is not booked again.
    state.handled[o.classId] = o.start;
    state.log.unshift({ classId: o.classId, title: o.title, at: new Date().toISOString(), outcome: o.once ? `${outcome} (one-off)` : outcome });
    if (outcome === "Login expired") { loggedOut = true; continue; }
    const booked = outcome === "Booked" || outcome === "Already booked";
    await notify(env, u, `${outcome}: ${o.title}`, `${when(o.start)} · ${o.once ? "booked when it opened" : "auto-book"}${booked ? `. ${cancelNote(o.start, freeUntil(o), at(o))}` : ""}`,
                 o.classId, booked ? "AUTOBOOK_BOOKED" : "AUTOBOOK_RESULT");
  }
  state.upcoming = state.upcoming.filter((o) => !state.handled[o.classId] && o.start > now);
  state.opens = (state.opens ?? []).filter((o) => !state.handled[o.classId] && o.start > now);
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
  await sendNudges(env, now).catch((e) => console.log("nudges failed:", e.message));
  await sendRaceReminders(env, now).catch((e) => console.log("race reminders failed:", e.message));
  await sendCrewUpdates(env, now).catch((e) => console.log("crew updates failed:", e.message));
}

/** Pushes the skipped-habit recommendations planned by the daily run whose time has come. */
export async function sendNudges(env, now) {
  const DB = await db(env);
  const { results } = await DB.prepare("SELECT * FROM nudges WHERE sent_at IS NULL AND send_at <= ?").bind(now).all();
  for (const n of results) {
    await DB.prepare("UPDATE nudges SET sent_at = ? WHERE user_id = ?").bind(now, n.user_id).run();
    const u = await getUser(env, n.user_id);
    if (!u?.devices.length || u.state.nudges === false) continue;
    const gone = await push(env, u.devices, n.title, n.body, JSON.parse(n.data), "RECOMMENDATION");
    if (gone.length) { u.devices = u.devices.filter((d) => !gone.includes(d.token)); await saveUser(env, u); }
  }
}

// MARK: Race reminders (Train for it)

/** When a race's reminders are due, UTC ms: 08:00 local on the Monday of race week (null for a race on a Monday: the
 *  evening before covers it), 18:00 the day before, and race day's midnight (nothing is sent from then on). */
export function raceReminderTimes(date) {
  const [y, m, d] = date.split("-").map(Number);
  const back = (localParts(localMidnight(y, m, d) + 12 * 3600_000).weekday + 5) % 7;   // days since Monday
  return { week: back === 0 ? null : localAt(y, m, d - back, RACE_WEEK_HOUR), eve: localAt(y, m, d - 1, RACE_EVE_HOUR), day: localMidnight(y, m, d) };
}

const hostOf = (url) => { try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return null; } };

/** "Race week: HYROX Stockholm" / "Saturday is race day. Booked this week: Mobility Wed 18:00, Hyrox Thu 07:00." (or
 *  the plan's race-week mix when nothing is booked). The same words as the apps' local notification. */
export function raceWeekMessage(r, booked = []) {
  const [y, m, d] = r.date.split("-").map(Number);
  const weekday = new Date(Date.UTC(y, m - 1, d, 12)).toLocaleDateString("en-GB", { weekday: "long", timeZone: "UTC" });
  let body = `${weekday} is race day.`;
  const plan = r.plan ? JSON.parse(r.plan) : null;
  const mix = (plan?.raceWeek ?? []).filter((x) => x.count > 0).map((x) => `${x.count} ${x.title}`);
  if (booked.length) body += ` Booked this week: ${booked.map((b) => `${b.title} ${when(b.start)}`).join(", ")}.`;
  else if (mix.length) body += ` Your class mix this week: ${mix.length > 1 ? mix.slice(0, -1).join(", ") + " and " + mix.at(-1) : mix[0]}.`;
  return { title: `Race week: ${r.name}`, body };
}
export function raceEveMessage(r) {
  const host = r.url ? hostOf(r.url) : null;
  return { title: `Tomorrow: ${r.name}`, body: host ? `Race day tomorrow. Start times and what to bring are on ${host}.` : "Race day tomorrow." };
}
/** 09:00 local the day before the price changes (`price_at`), UTC ms. */
export function racePriceTime(priceAt) {
  const [y, m, d] = priceAt.split("-").map(Number);
  return localAt(y, m, d - 1, RACE_PRICE_HOUR);
}
/** The device's words for the step ("HYROX Stockholm: 750 SEK until today, 775 SEK from tomorrow. Sign up on hyrox.com."),
 *  else a plain line. */
export function racePriceMessage(r) {
  const host = r.url ? hostOf(r.url) : null;
  return { title: "Price goes up tomorrow", body: r.price_body || `${r.name}: the entry fee changes tomorrow.${host ? ` Check ${host}.` : ""}` };
}

/** The user's booked classes from now until race day (the first page of `GET /v52/booking`), for the race-week push. */
export async function raceWeekBookings(u, r, now) {
  const [y, m, d] = r.date.split("-").map(Number);
  const until = localMidnight(y, m, d);
  const res = await bruce("GET", "/v52/booking", u.session.access_token, { query: [["user_id", String(u.userId)], ["limit", "30"], ["deleted", "false"],
    ["include_class", "true"], ["class_start_time_after", new Date(now).toISOString()], ["locale", "en"]] });
  if (!res.ok) return [];
  return ((await res.json()).bookings ?? []).filter((b) => b?.class && !b.deleted && !b.class.canceled && !b.class.deleted)
    .map((b) => ({ title: String(b.class.title ?? "Class").replace(/\*\*/g, "").trim(), start: Date.parse(b.class.start_time) }))
    .filter((b) => b.start > now && b.start < until).sort((a, b) => a.start - b.start).slice(0, 4);
}

/**
 * The minute cron's race reminders: each one whose time has come is marked sent first (so it goes out once), then
 * pushed (category RACE_REMINDER, payload {raceId}); the race-week one is also emailed, with a link to the race page and
 * the stop link. One that is more than RACE_LATE_MS late is only marked.
 */
export async function sendRaceReminders(env, now, { bookingsFn = raceWeekBookings } = {}) {
  const DB = await db(env);
  const today = localDay(now);
  // Race-day reminders in the week of the race; the price step the day before it changes (its `price_at` is tomorrow
  // or, when a minute was missed, today).
  const { results } = await DB.prepare(`SELECT * FROM user_races WHERE (date >= ?1 AND date <= ?2
      AND ((remind_week = 1 AND week_sent_at IS NULL) OR (remind_eve = 1 AND eve_sent_at IS NULL)))
      OR (remind_price = 1 AND price_sent_at IS NULL AND price_at >= ?1 AND price_at <= ?3)`).bind(today, addDays(today, 7), addDays(today, 1)).all();
  for (const r of results) {
    const t = raceReminderTimes(r.date);
    for (const kind of ["week", "eve", "price"]) {
      const on = kind === "week" ? r.remind_week && r.week_sent_at == null : kind === "eve" ? r.remind_eve && r.eve_sent_at == null
        : r.remind_price && r.price_sent_at == null && r.price_at;
      // A Monday race has no race week before it: its race-week switch is the evening before (once, if both are on).
      const due = kind === "price" ? (r.price_at ? racePriceTime(r.price_at) : null) : kind === "week" && t.week == null ? (r.remind_eve ? null : t.eve) : t[kind];
      if (!on || now < (due ?? t.week ?? t.eve)) continue;
      // Marked first and only once (overlapping runs), so it goes out once.
      const mine = await DB.prepare(`UPDATE user_races SET ${kind}_sent_at = ? WHERE user_id = ? AND race_id = ? AND ${kind}_sent_at IS NULL RETURNING race_id`)
        .bind(now, r.user_id, r.race_id).first();
      if (!mine || due == null || now >= Math.min(due + RACE_LATE_MS, t.day)) continue;
      const u = await getUser(env, r.user_id);
      if (!u) continue;
      const weekly = kind === "week" && t.week != null;
      const booked = weekly ? await bookingsFn(u, r, now).catch(() => []) : [];
      const msg = kind === "price" ? racePriceMessage(r) : weekly ? raceWeekMessage(r, booked) : raceEveMessage(r);
      // Race week and the price step by push and email (web users have no device); the evening before by push.
      const mail = weekly || kind === "price";
      const [gone] = await Promise.all([push(env, u.devices, msg.title, msg.body, { raceId: r.race_id }, "RACE_REMINDER"),
                                        mail && email(env, u, msg.title, msg.body, null, { link: RACE_URL + encodeURIComponent(r.race_id), linkText: "Open the race" })]);
      if (gone.length) { u.devices = u.devices.filter((x) => !gone.includes(x.token)); await saveUser(env, u); }
    }
  }
}

/** The daily cron: races whose day is over leave the table, and users with nothing else to do with them. */
export async function pruneRaces(env, now) {
  const DB = await db(env);
  const before = addDays(localDay(now), -1);
  const { results } = await DB.prepare("SELECT DISTINCT user_id FROM user_races WHERE date < ?").bind(before).all();
  if (!results.length) return 0;
  await DB.prepare("DELETE FROM user_races WHERE date < ?").bind(before).run();
  for (const { user_id } of results) { const u = await getUser(env, user_id); if (u) await keepOrDelete(env, u); }
  return results.length;
}

// MARK: Race crews: the Sunday push

/**
 * The minute cron on Sunday from 19:00 local (for two hours): each crew still training (race day after today) with at
 * least two members and a whole week behind it tells them how many hit the weekly target this week, Monday to today,
 * once (a `crew_updates` row is written first). Visits come from the daily history read (up to last night); members
 * not at their target yet get today's visits from their first `GET /v52/booking` pages. A run spends at most
 * CREW_BUDGET requests (those pages and the APNs pushes): a crew that doesn't fit waits for the next minute, one that
 * never would goes without today's visits. Members who switched crew updates off (`PUT /me` `crewUpdates: false`) or
 * have no device get nothing; the push names nobody. Category CREW_UPDATE, payload {challengeId} (opens the crew).
 */
export async function sendCrewUpdates(env, now, { fetchFn = fetchBookings } = {}) {
  const p = localParts(now);
  if (p.weekday !== 1) return 0;
  const at = localAt(p.y, p.m, p.d, CREW_HOUR);
  if (now < at || now >= at + CREW_LATE_MS) return 0;
  const DB = await db(env);
  const today = localDay(now), monday = mondayOf(today);
  const { results } = await DB.prepare(`SELECT c.id FROM challenges c WHERE c.race_id IS NOT NULL AND c.weekly IS NOT NULL
      AND c.start_day <= ?1 AND c.end_day > ?1 AND NOT EXISTS (SELECT 1 FROM crew_updates u WHERE u.challenge_id = c.id AND u.week = ?2)`)
    .bind(today, monday).all();
  const full = +(env.CREW_BUDGET ?? CREW_BUDGET);
  let budget = full, sent = 0;
  for (const { id } of results) {
    const l = await loadChallenge(DB, id);
    if (!l) continue;
    const ch = l.ch, accepted = l.participants.filter((x) => x.status === "accepted");
    const mark = () => DB.prepare("INSERT INTO crew_updates (challenge_id, week, sent_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING RETURNING week")
      .bind(id, monday, now).first();
    // Two members at least, and a whole week: a crew started after Monday is told from its first full week.
    if (accepted.length < 2 || ch.start > monday) { await mark(); continue; }
    const ids = accepted.map((x) => x.userId);
    const visits = await crewVisits(DB, ids, monday, addDays(today, -1));
    const stats = crewWeeks(ch, accepted, visits, today);
    const { results: rows } = await DB.prepare("SELECT * FROM users WHERE user_id IN (SELECT value FROM json_each(?))").bind(JSON.stringify(ids)).all();
    const users = new Map(rows.map((r) => [r.user_id, rowToUser(r)]));
    const below = stats.members.filter((m) => m.thisWeek < stats.weekly && users.has(m.userId));
    const pushes = stats.members.reduce((n, m) => { const u = users.get(m.userId); return n + (u && u.state.crewUpdates !== false ? u.devices.length : 0); }, 0);
    // Bruce pages for today's visits (up to two each) and one APNs request per device. A crew that doesn't fit waits
    // for the next minute's budget; one that never would goes without today's visits.
    let topUp = true;
    if (2 * below.length + pushes > budget) {
      if (budget < full) break;
      topUp = 2 * below.length + pushes <= full;
    }
    if (!(await mark())) continue;   // another run has it
    if (topUp) {
      for (const m of below) {
        const u = users.get(m.userId);
        try {
          const r = await fetchFn(u.session.access_token, u.userId, localMidnight(p.y, p.m, p.d), 2);
          budget -= r.pages ?? 1;
          m.thisWeek += visitsFromBookings(r.bookings, now).filter((v) => v.day === today).length;
        } catch (e) { budget -= 1; console.log("crew visits failed:", m.userId, e.message); }
      }
    }
    const hit = stats.members.filter((m) => m.thisWeek >= stats.weekly).length;
    for (const m of stats.members) {
      const u = users.get(m.userId);
      if (!u?.devices.length || u.state.crewUpdates === false) continue;
      budget -= u.devices.length;
      const msg = crewMessage(ch.title, hit, stats.size, stats.weekly, m.thisWeek);
      const gone = await push(env, u.devices, msg.title, msg.body, { challengeId: id }, "CREW_UPDATE");
      if (gone.length) { u.devices = u.devices.filter((d) => !gone.includes(d.token)); await saveUser(env, u); }
      sent++;
    }
  }
  return sent;
}

/** Visits per user from the stored per-visit detail, `from` to `to` (local days). */
async function crewVisits(DB, userIds, from, to) {
  const { results } = await DB.prepare(`SELECT user_id, day, detail FROM daily_counts WHERE day >= ? AND day <= ? AND detail IS NOT NULL
      AND user_id IN (SELECT value FROM json_each(?))`).bind(from, to, JSON.stringify(userIds)).all();
  const out = new Map();
  for (const r of results) {
    const list = out.get(r.user_id) ?? [];
    for (const d of JSON.parse(r.detail)) list.push(fromDetail(d, r.day));
    out.set(r.user_id, list);
  }
  return out;
}

// MARK: Friends going

/**
 * `GET /races/going[?ids=a,b]`: the caller's Bruce friends (as Bruce lists them for the caller, `GET /v52/friend`)
 * who marked an upcoming race going, by race. Only for a caller who shares a race themselves: otherwise
 * `{going: {}, sharing: false}` and nothing is read. Nobody else is ever listed, so the answer says nothing about who
 * uses Brüce beyond the caller's own friends.
 */
async function goingRoute(request, env) {
  const auth = await authenticate(request, env);
  if (!auth) return json({ error: "unauthorized" }, 401);
  const DB = await db(env);
  const today = localDay(Date.now());
  const mine = await DB.prepare("SELECT race_id FROM user_races WHERE user_id = ? AND visibility = 'friends' AND date >= ?").bind(auth.userId, today).all();
  const own = mine.results.map((r) => r.race_id);
  if (!own.length) return json({ going: {}, sharing: false, mine: [] });
  let friends;
  try { friends = await fetchFriends(auth.token, auth.userId); } catch (e) {
    if (e instanceof LoggedOut) return json({ error: "unauthorized" }, 401);
    return json({ error: "Bruce is not answering" }, 502);
  }
  const names = new Map(friends.filter((f) => f.id !== auth.userId).map((f) => [f.id, f.name]));
  const wanted = (new URL(request.url).searchParams.get("ids") ?? "").split(",").filter((x) => /^[a-z0-9]+(-[a-z0-9]+)*$/.test(x)).slice(0, 100);
  if (!names.size) return json({ going: {}, sharing: true, mine: own });
  const { results } = await DB.prepare(`SELECT user_id, race_id FROM user_races WHERE visibility = 'friends' AND date >= ?1
      AND user_id IN (SELECT value FROM json_each(?2))${wanted.length ? " AND race_id IN (SELECT value FROM json_each(?3))" : ""}
      ORDER BY race_id, user_id`).bind(today, JSON.stringify([...names.keys()]), ...(wanted.length ? [JSON.stringify(wanted)] : [])).all();
  const going = {};
  for (const r of results) (going[r.race_id] ??= []).push({ userId: r.user_id, name: names.get(r.user_id) ?? "" });
  return json({ going, sharing: true, mine: own });
}

/** The races of a `PUT /me/races` body: valid ids and days, a reminder on or going, at most MAX_RACES (null when over).
 *  Going is only kept for catalog races: a race added by hand ("custom-…") has no shared record to meet friends on. */
export function cleanRaces(list, now = Date.now()) {
  const isDay = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + "T12:00:00Z"))
    && new Date(s + "T12:00:00Z").toISOString().slice(0, 10) === s;
  const out = [];
  for (const r of list) {
    if (!r || typeof r.id !== "string" || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id) || r.id.length > 100 || !isDay(r.date)) continue;
    const going = r.going === true && !r.id.startsWith("custom-");
    // The price step needs the day it changes; the words are the device's (at most a short paragraph).
    const price = r.remindPrice === true && isDay(r.priceAt) && !r.id.startsWith("custom-");
    if (r.remindWeek !== true && r.remindEve !== true && !price && !going) continue;
    if (out.length >= MAX_RACES + 1) break;
    if (out.some((x) => x.id === r.id)) continue;
    const url = typeof r.url === "string" && /^https:\/\/[^\s]+$/.test(r.url) && r.url.length <= 300 ? r.url : null;
    let plan = null;
    if (r.plan && typeof r.plan === "object") {
      const p = r.plan;
      plan = { perWeek: Number.isInteger(p.perWeek) ? p.perWeek : null, weeks: Number.isInteger(p.weeks) ? p.weeks : null, startedOn: isDay(p.startedOn) ? p.startedOn : null,
               raceWeek: (Array.isArray(p.raceWeek) ? p.raceWeek : []).slice(0, 6).filter((x) => x && typeof x.title === "string" && Number.isInteger(x.count))
                 .map((x) => ({ key: String(x.key ?? "").slice(0, 30), title: x.title.slice(0, 30), count: Math.max(0, Math.min(9, x.count)) })) };
    }
    out.push({ id: r.id, name: String(r.name ?? "Race").slice(0, 120) || "Race", date: r.date, url, remindWeek: r.remindWeek === true, remindEve: r.remindEve === true, plan,
               remindPrice: price, priceAt: price ? r.priceAt : null, priceBody: price && typeof r.priceBody === "string" ? r.priceBody.slice(0, 240).trim() || null : null,
               going, goingAt: goingTime(r, now) });
  }
  return out.length > MAX_RACES ? null : out;
}

/** When the member flipped going for a race (`goingAt`, UTC ms; 0 when not sent, never later than now). */
const goingTime = (r, now) => Math.max(0, Math.min(now, Number.isFinite(+r.goingAt) && r.goingAt != null ? Math.round(+r.goingAt) : 0));

/**
 * The going switches of a `PUT /me/races` body: `{id, going, goingAt}` for each catalog race that says `going` true or
 * false (also a race sent only to switch going off). Going is the member's, not a device's: the switch flipped last
 * (`goingAt`) wins on every device, so a device that has not heard of a change cannot undo it.
 */
export function goingSwitches(list, now = Date.now()) {
  const out = [];
  for (const r of Array.isArray(list) ? list : []) {
    if (!r || typeof r.going !== "boolean" || typeof r.id !== "string" || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id) || r.id.length > 100
        || r.id.startsWith("custom-") || out.some((x) => x.id === r.id)) continue;
    out.push({ id: r.id, going: r.going, goingAt: goingTime(r, now) });
    if (out.length >= 2 * MAX_RACES) break;
  }
  return out;
}

const rowToRace = (r) => ({ id: r.race_id, name: r.name, date: r.date, url: r.url ?? null, remindWeek: !!r.remind_week, remindEve: !!r.remind_eve,
  plan: r.plan ? JSON.parse(r.plan) : null, weekSentAt: r.week_sent_at ?? null, eveSentAt: r.eve_sent_at ?? null, going: r.visibility === "friends",
  goingAt: r.going_at ?? null, remindPrice: !!r.remind_price, priceAt: r.price_at ?? null, priceSentAt: r.price_sent_at ?? null });

/** `PUT /me/races` (replace the set) and `DELETE /me/races/<id>`. */
async function racesRoute(request, env, raceId) {
  const auth = await authenticate(request, env);
  if (!auth) return json({ error: "unauthorized" }, 401);
  const DB = await db(env);
  const known = await getUser(env, auth.userId);
  if (request.method === "DELETE") {
    // Any device may remove a race (Remove from My races, a reminder switched off).
    await DB.prepare("DELETE FROM user_races WHERE user_id = ? AND race_id = ?").bind(auth.userId, raceId).run();
    if (known) { signIn(known, auth); await keepOrDelete(env, known); }
    const n = await DB.prepare("SELECT COUNT(*) AS n FROM user_races WHERE user_id = ?").bind(auth.userId).first();
    return json({ ok: true, races: n?.n ?? 0 });
  }
  const body = await request.json().catch(() => ({}));
  if (!Array.isArray(body.races)) return json({ error: "races must be an array" }, 400);
  const now = Date.now();
  const races = cleanRaces(body.races, now);
  if (!races) return json({ error: `at most ${MAX_RACES} races` }, 409);
  const switches = goingSwitches(body.races, now);
  // My races are per device: each device's PUT replaces the races it sent before, not another device's.
  const source = typeof body.device === "string" && /^[A-Za-z0-9-]{1,64}$/.test(body.device) ? body.device : "";
  if (!races.length && !known) return json({ ok: true, races: 0, ids: [], going: [] });
  const u = known ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
  signIn(u, auth);
  await saveUser(env, u);
  // A reminder already sent stays sent while the race keeps its day.
  const { results: before } = await DB.prepare(`SELECT race_id, date, week_sent_at, eve_sent_at, source, visibility, going_at, price_at, price_sent_at
      FROM user_races WHERE user_id = ?`).bind(auth.userId).all();
  // Other devices' races stay; all devices together keep at most twice the cap.
  const others = before.filter((b) => b.source !== source && !races.some((r) => r.id === b.race_id)).length;
  if (races.length + others > 2 * MAX_RACES) return json({ error: `at most ${2 * MAX_RACES} races on all devices` }, 409);
  const at = new Date().toISOString();
  const upsert = DB.prepare(`INSERT INTO user_races (user_id, race_id, name, date, url, remind_week, remind_eve, plan, week_sent_at, eve_sent_at, source, updated_at,
        visibility, going_at, remind_price, price_at, price_body, price_sent_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
      ON CONFLICT(user_id, race_id) DO UPDATE SET name = ?3, date = ?4, url = ?5, remind_week = ?6, remind_eve = ?7, plan = ?8,
        week_sent_at = ?9, eve_sent_at = ?10, source = ?11, updated_at = ?12, visibility = ?13, going_at = ?14,
        remind_price = ?15, price_at = ?16, price_body = ?17, price_sent_at = ?18`);
  // Going: kept from the row as it was, then each switch in the body applies when it is at least as recent as the
  // row's (last flip wins, on whichever device it happened). Switching off also reaches a row another device sent.
  const flip = DB.prepare(`UPDATE user_races SET visibility = ?1, going_at = ?2 WHERE user_id = ?3 AND race_id = ?4
      AND (going_at IS NULL OR going_at <= ?2)`);
  await DB.batch([
    DB.prepare("DELETE FROM user_races WHERE user_id = ? AND source = ?").bind(auth.userId, source),
    ...races.map((r) => {
      const old = before.find((b) => b.race_id === r.id);
      const sent = old && old.date === r.date ? old : null;
      // The price reminder stays sent while the step keeps its day; a new day reminds again.
      const priceSent = old && r.priceAt && old.price_at === r.priceAt ? old.price_sent_at ?? null : null;
      return upsert.bind(auth.userId, r.id, r.name, r.date, r.url, r.remindWeek ? 1 : 0, r.remindEve ? 1 : 0, r.plan ? JSON.stringify(r.plan) : null,
                         sent?.week_sent_at ?? null, sent?.eve_sent_at ?? null, source, at, old?.visibility ?? "private", old?.going_at ?? null,
                         r.remindPrice ? 1 : 0, r.priceAt, r.priceBody, priceSent);
    }),
    ...switches.map((g) => flip.bind(g.going ? "friends" : "private", g.goingAt, auth.userId, g.id)),
  ]);
  await keepOrDelete(env, u);
  const { results: shared } = await DB.prepare("SELECT race_id FROM user_races WHERE user_id = ? AND visibility = 'friends' ORDER BY race_id").bind(auth.userId).all();
  // `ids`: the races whose reminders the server sends (the device leaves those out); `going`: shared races.
  return json({ ok: true, races: races.length, ids: races.filter((r) => r.remindWeek || r.remindEve || r.remindPrice).map((r) => r.id), going: shared.map((r) => r.race_id),
                push: apnsConfigured(env) && u.devices.length > 0, email: emailTo(env, u) });
}

// MARK: Race feed (organiser imports, phase 3)

const FEED_TYPES = ["running", "hyrox", "obstacle", "endurance", "triathlon"];
const FEED_STATUSES = ["open", "opensSoon", "soldOut", "lottery", "checkSite"];
const MAX_FEED = 200;

/** One race of a feed as the apps need it (README.md "Race catalog": id, name, type, date, signupUrl, status, checkedOn);
 *  null when they couldn't read it. Other fields are kept as sent: the apps skip what they don't know. */
export function cleanFeedRace(r) {
  const isDay = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(s + "T12:00:00Z").toISOString().slice(0, 10) === s;
  if (!r || typeof r !== "object" || Array.isArray(r)) return null;
  if (typeof r.id !== "string" || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id) || r.id.startsWith("custom-") || r.id.length > 100) return null;
  if (typeof r.name !== "string" || !r.name.trim() || !FEED_TYPES.includes(r.type) || !FEED_STATUSES.includes(r.status)) return null;
  if (!isDay(r.date) || !isDay(r.checkedOn) || (r.endDate != null && (!isDay(r.endDate) || r.endDate < r.date))) return null;
  if (typeof r.signupUrl !== "string" || !/^https:\/\/[^\s]+$/.test(r.signupUrl) || r.signupUrl.length > 300) return null;
  if (JSON.stringify(r).length > 8000) return null;
  return r;
}

/**
 * `GET /races`: every imported race (the catalog's schema) with its source, for the apps to lay over races.json.
 * `POST /races/import` with `Authorization: Bearer <RACE_FEED_TOKEN>` and `{"source","races":[...]}`: replaces that
 * source's races; a race another source posted first stays that source's (reported under `skipped`). Nothing here
 * sells, registers or reads a registration platform: it is the catalog, kept current by whoever posts.
 */
export async function feedRoute(request, env) {
  const DB = await db(env);
  if (request.method === "GET") {
    const { results } = await DB.prepare("SELECT race, source, imported_at FROM race_feed ORDER BY race_id").all();
    return json({ races: results.map((x) => JSON.parse(x.race)), sources: [...new Set(results.map((x) => x.source))].sort(),
                  importedAt: results.length ? Math.max(...results.map((x) => x.imported_at)) : null });
  }
  if (!env.RACE_FEED_TOKEN) return json({ error: "no feed token configured" }, 503);
  if ((request.headers.get("authorization") ?? "") !== `Bearer ${env.RACE_FEED_TOKEN}`) return json({ error: "unauthorized" }, 401);
  const body = await request.json().catch(() => null);
  const source = typeof body?.source === "string" && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(body.source) && body.source.length <= 40 ? body.source : null;
  if (!source || !Array.isArray(body.races)) return json({ error: "source (lower case with dashes) and races (an array) are required" }, 400);
  if (body.races.length > MAX_FEED) return json({ error: `at most ${MAX_FEED} races` }, 409);
  const races = [], skipped = [];
  for (const r of body.races) {
    const c = cleanFeedRace(r);
    if (c && !races.some((x) => x.id === c.id)) races.push(c); else skipped.push(String(r?.id ?? "?"));
  }
  const { results: taken } = await DB.prepare("SELECT race_id FROM race_feed WHERE source != ?").bind(source).all();
  const theirs = new Set(taken.map((x) => x.race_id));
  const mine = races.filter((r) => !theirs.has(r.id));
  const now = Date.now();
  await DB.batch([DB.prepare("DELETE FROM race_feed WHERE source = ?").bind(source),
    ...mine.map((r) => DB.prepare("INSERT INTO race_feed (race_id, source, race, imported_at) VALUES (?, ?, ?, ?)").bind(r.id, source, JSON.stringify(r), now))]);
  return json({ ok: true, source, imported: mine.length, skipped: skipped.concat(races.filter((r) => theirs.has(r.id)).map((r) => r.id)) });
}

// MARK: History (daily cron): challenges, goal reminders, Wrapped percentiles

/**
 * Re-reads one user's booking history into `daily_counts`. The first read goes back to January 1 (or the start of the
 * user's earliest challenge); later reads only the last few days (a check-in can be recorded late) and, with goal
 * reminders, the current month (with skipped-habit pushes, the last 6 weeks). Per-visit detail is stored only while
 * the user is in a challenge. Sends due goal reminders and plans a skipped-habit push. Returns the number of Bruce
 * requests made. Throws LoggedOut if Bruce rejects the login.
 */
export async function refreshHistory(env, u, now, { maxPages = BACKFILL_PAGES, fetchFn = fetchBookings, classesFn = fetchClasses } = {}) {
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
  // Skipped habits need the last few weeks, and the upcoming bookings (the first page of the list).
  const nudging = s.nudges !== false && u.devices.length > 0 && apnsConfigured(env);
  if (nudging && addDays(today, -HABIT_LOOKBACK_DAYS) < from) from = addDays(today, -HABIT_LOOKBACK_DAYS);
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
  return pages + (nudging ? await planNudge(env, u, bookings, now, maxPages - pages, classesFn) : 0);
}

/**
 * Skipped habit: when the history shows a weekly class done 3+ weeks in a row and then skipped (nothing visited or
 * booked since), picks upcoming classes at that studio and the user's other favourite studio and plans a push for
 * 08:00 local (sent by the minute cron). Each break is told once. Returns the number of Bruce requests made.
 */
export async function planNudge(env, u, bookings, now, budget, classesFn = fetchClasses) {
  if (budget <= 0) return 0;
  const habit = brokenHabit(bookings, now, { lapseDays: u.state.nudgeDays ?? LAPSE_DAYS });
  if (!habit) return 0;
  const DB = await db(env);
  const prev = await DB.prepare("SELECT habit, missed_day FROM nudges WHERE user_id = ?").bind(u.userId).first();
  if (prev && prev.habit === habit.key && prev.missed_day === habit.missedDay) return 0;
  const counts = new Map();
  for (const v of visitsFromBookings(bookings, now)) if (v.studioId != null) counts.set(v.studioId, (counts.get(v.studioId) ?? 0) + 1);
  const other = [...counts].filter(([id]) => id !== habit.studioId).sort((a, b) => b[1] - a[1])[0]?.[0];
  const meter = { pages: 0 };
  const classes = [];
  for (const studioId of [habit.studioId, other].filter((x) => x != null)) {
    if (meter.pages >= budget) break;
    try {
      classes.push(...await classesFn(u.session.access_token, studioId, now, now + RECOMMEND_DAYS * 86400_000,
                                      { maxPages: Math.min(NUDGE_PAGES, budget - meter.pages), meter }));
    } catch (e) {
      if (e instanceof LoggedOut) throw e;
      console.log("nudge classes failed:", u.userId, studioId, e.message);
    }
  }
  const picks = recommendClasses(classes, bookings, habit, now, opensAt);
  const { title, body } = nudgeMessage(habit, picks);
  const p = localParts(now);
  const sendAt = Math.max(now, localMidnight(p.y, p.m, p.d) + NUDGE_HOUR * 3600_000);
  await DB.prepare(`INSERT INTO nudges (user_id, habit, missed_day, send_at, sent_at, title, body, data) VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?7)
      ON CONFLICT(user_id) DO UPDATE SET habit = ?2, missed_day = ?3, send_at = ?4, sent_at = NULL, title = ?5, body = ?6, data = ?7`)
    .bind(u.userId, habit.key, habit.missedDay, sendAt, title, body, JSON.stringify({ recommend: picks.map((x) => x.classId) })).run();
  return meter.pages;
}

/** The daily cron: refreshes users not yet refreshed today, least recently refreshed first, within DAILY_BUDGET. */
export async function daily(env, now, { fetchFn = fetchBookings, classesFn = fetchClasses } = {}) {
  await pruneRaces(env, now).catch((e) => console.log("race prune failed:", e.message));
  const { results } = await (await db(env)).prepare("SELECT * FROM users").all();
  const users = results.map(rowToUser).sort((a, b) => String(a.state.statsAt ?? "").localeCompare(String(b.state.statsAt ?? "")));
  let budget = +(env.DAILY_BUDGET ?? DAILY_BUDGET);
  const today = localDay(now);
  for (const u of users) {
    if (budget <= 0) break;
    if (u.state.statsAt && localDay(Date.parse(u.state.statsAt)) === today) continue;
    try {
      budget -= await refreshHistory(env, u, now, { maxPages: Math.min(budget, BACKFILL_PAGES), fetchFn, classesFn });
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

/** `PUT|DELETE /me/opening/<classId>`: book a listed, not yet bookable class once, the moment its window opens. */
async function openingRoute(request, env, classId, now = Date.now()) {
  const auth = await authenticate(request, env);
  if (!auth) return json({ error: "unauthorized" }, 401);
  const u = (await getUser(env, auth.userId)) ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
  signIn(u, auth);
  u.state.opens ??= [];
  if (request.method === "DELETE") {
    u.state.opens = u.state.opens.filter((o) => o.classId !== classId);
    await keepOrDelete(env, u);
    return json({ ok: true, opens: u.state.opens.length, max: MAX_OPENS });
  }
  if (!u.state.opens.some((o) => o.classId === classId)) {
    if (u.state.opens.length >= MAX_OPENS) return json({ error: `at most ${MAX_OPENS} classes waiting to open` }, 409);
    let c;
    try { c = await fetchClass(auth.token, classId); } catch { return json({ error: "Bruce is not answering" }, 502); }
    const start = c ? Date.parse(c.start_time) : NaN;
    if (!c || c.deleted || c.deleted_at || c.canceled || !(start > now)) return json({ error: "class not found or already started" }, 404);
    const opens = opensAt(c);
    if (opens <= now) return json({ error: "booking is already open: book it in the app" }, 409);
    u.state.opens.push({ classId, title: String(c.title).slice(0, 200), studioId: c.studio_id, start, opens, freeUntil: freeCancelUntil(c), once: true });
  }
  await saveUser(env, u);
  return json({ ok: true, opens: u.state.opens.length, max: MAX_OPENS, push: apnsConfigured(env) && u.devices.length > 0 });
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
  repeatMonthly: !!r.repeat_monthly, createdAt: r.created_at, raceId: r.race_id ?? null, weekly: r.weekly ?? null });

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
      if (c.raceId) {
        // One crew per race: the race page shows it.
        const dup = await DB.prepare(`SELECT c.id FROM challenges c JOIN participants p ON p.challenge_id = c.id
            WHERE c.race_id = ? AND p.user_id = ? AND p.status = 'accepted' AND c.end_day >= ? LIMIT 1`).bind(c.raceId, auth.userId, today).first();
        if (dup) return json({ error: "you are already in a crew for this race", challengeId: dup.id }, 409);
      }
      let friends;
      try { friends = await fetchFriends(auth.token, auth.userId); } catch { return json({ error: "Bruce is not answering" }, 502); }
      const wanted = new Set((Array.isArray(body.invite) ? body.invite : []).map(Number));
      const invitees = friends.filter((f) => wanted.has(f.id) && f.id !== auth.userId).slice(0, MAX_INVITES);
      const chId = newId();
      const at = new Date(now).toISOString();
      await DB.batch([
        DB.prepare(`INSERT INTO challenges (id, owner_id, title, metric, target, category, category_title, start_day, end_day, repeat_monthly, created_at, race_id, weekly)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)`)
          .bind(chId, auth.userId, c.title, c.metric, c.target, c.category, c.categoryTitle, c.start, c.end, c.repeatMonthly ? 1 : 0, at, c.raceId, c.weekly),
        DB.prepare("INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?, ?, ?, 'accepted', NULL, ?)")
          .bind(chId, auth.userId, auth.name, at),
        ...invitees.map((f) => DB.prepare("INSERT INTO participants (challenge_id, user_id, name, status, invited_by, joined_at) VALUES (?, ?, ?, 'invited', ?, NULL)")
          .bind(chId, f.id, f.name, auth.userId)),
      ]);
      const u = await rememberLogin(env, auth);
      backfill(env, ctx, u);
      const loaded = await loadChallenge(DB, chId);
      const label = challengePeriod(loaded.ch, today).label;
      const invite = c.raceId
        ? { title: `${auth.name || "A friend"} invited you to a crew`, body: `${c.title} · ${c.weekly} ${c.weekly === 1 ? "session" : "sessions"} a week until race day. Tap to accept.` }
        : { title: `${auth.name || "A friend"} challenged you`, body: `${c.title} · ${label}. Tap to accept.` };
      await Promise.all(invitees.map((f) => pushTo(env, f.id, invite.title, invite.body, { challengeId: chId }, "CHALLENGE_INVITE")));
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
        const { id: cid, title, metric, target, categoryTitle, raceId, weekly } = l.ch;
        return json({ challenge: { id: cid, title, metric, target, categoryTitle, raceId, weekly, period: challengePeriod(l.ch, today),
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
                    crew: l.ch.raceId ? crewWeeks(l.ch, l.participants, visitsByUser, today) : undefined,
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
          await pushTo(env, l.ch.ownerId, `${auth.name || "A friend"} joined ${l.ch.title}`, l.ch.raceId ? "Your crew has a new member." : "Your challenge has a new rival.",
                       { challengeId: id }, "CHALLENGE_INVITE");
        }
      }
      return json({ ok: true, challenge: summary(await loadChallenge(DB, id), auth.userId, today) });
    }

    case "POST /challenges/:id/leave": {
      const l = await loadChallenge(DB, id);
      if (!l || !l.participants.some((p) => p.userId === auth.userId)) return json({ ok: true });
      await DB.prepare("DELETE FROM participants WHERE challenge_id = ? AND user_id = ?").bind(id, auth.userId).run();
      if (!l.participants.some((p) => p.userId !== auth.userId && p.status === "accepted")) {
        await DB.batch([DB.prepare("DELETE FROM participants WHERE challenge_id = ?").bind(id), DB.prepare("DELETE FROM crew_updates WHERE challenge_id = ?").bind(id),
                        DB.prepare("DELETE FROM challenges WHERE id = ?").bind(id)]);
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
    const opening = path.match(/^\/me\/opening\/(\d+)$/);
    if (opening && (request.method === "PUT" || request.method === "DELETE")) return openingRoute(request, env, +opening[1]);
    if (route === "PUT /me/races") return racesRoute(request, env, null);
    if (route === "GET /races/going") return goingRoute(request, env);
    if (route === "GET /races" || route === "POST /races/import") return feedRoute(request, env);
    const race = path.match(/^\/me\/races\/([a-z0-9-]{1,100})$/);
    if (race && request.method === "DELETE") return racesRoute(request, env, race[1]);
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
        if (typeof body.nudges === "boolean") u.state.nudges = body.nudges;
        if (typeof body.crewUpdates === "boolean") u.state.crewUpdates = body.crewUpdates;
        if (cleanLapseDays(body.nudgeDays)) u.state.nudgeDays = body.nudgeDays;
        if (body.lateSpots === "book" || body.lateSpots === "ask") u.state.lateSpots = body.lateSpots;
        if (rulesChanged) await tickUser(env, u, Date.now(), { force: true }).catch((e) => console.log("scan failed:", e.message));
        await saveUser(env, u);
        return json({ ok: true, rules: u.rules.length, push: apnsConfigured(env) && u.devices.length > 0, email: emailTo(env, u) });
      }
      case "GET /me": {
        const u = await getUser(env, auth.userId);
        const { results: races } = await (await db(env)).prepare("SELECT * FROM user_races WHERE user_id = ? ORDER BY date, race_id").bind(auth.userId).all();
        const opens = (o) => ({ classId: o.classId, title: o.title, at: new Date(o.opens).toISOString(), outcome: "Opens" });
        return json({ hasSession: !!u, rules: u?.rules ?? [], lastScan: u?.state.lastScan ?? null,
                      upcoming: (u?.state.upcoming ?? []).map(opens),
                      waitlist: (u?.state.watches ?? []).map((w) => ({ classId: w.classId, title: w.title, start: new Date(w.start).toISOString() })),
                      opening: (u?.state.opens ?? []).map((o) => ({ classId: o.classId, title: o.title, start: new Date(o.start).toISOString(), opens: new Date(o.opens).toISOString() })),
                      maxOpening: MAX_OPENS, log: u?.state.log ?? [], devices: u?.devices.length ?? 0,
                      email: u ? emailTo(env, u) : null, nudges: u ? u.state.nudges !== false : true,
                      nudgeDays: u?.state.nudgeDays ?? LAPSE_DAYS, lateSpots: u?.state.lateSpots ?? "ask", crewUpdates: u ? u.state.crewUpdates !== false : true,
                      races: races.map(rowToRace) });
      }
      case "DELETE /me": {
        // Auto-book off: forget rules, watches, goals, races and push devices. The login stays while the user is in a challenge.
        const u = await getUser(env, auth.userId);
        if (u && (await inChallenge(env, auth.userId))) {
          // The server is off for this user: no more pushes either (challenge and crew pushes go to devices sent with it on).
          u.rules = [];
          u.devices = [];
          Object.assign(u.state, { upcoming: [], watches: [], opens: [], goals: [], goalPings: {} });
          await saveUser(env, u);
          await (await db(env)).prepare("DELETE FROM user_races WHERE user_id = ?").bind(auth.userId).run();
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
        // Also a test email, so the test button checks both ways a booking result arrives.
        const u = await getUser(env, auth.userId);
        if (u) { signIn(u, auth); await saveUser(env, u); }
        const canPush = !!u?.devices.length && apnsConfigured(env);
        if (!canPush && !(u && emailTo(env, u))) return json({ error: "no device or push not configured" }, 409);
        await Promise.all([canPush && push(env, u.devices, "Auto-book is set up", "You'll get a push like this when a class is booked."),
                           email(env, u, "Auto-book is set up", "You'll get an email like this when a class is booked.")]);
        return json({ ok: true, email: emailTo(env, u) });
      }
    }
  },
};
