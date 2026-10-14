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
// `APNS_TOPIC` = app bundle id). HTTP API: see ../README.md.

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

class LoggedOut extends Error {}

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
export async function push(env, devices, title, body, data = {}) {
  if (!apnsConfigured(env) || !devices.length) return [];
  const jwt = await apnsToken(env);
  const gone = [];
  await Promise.all(devices.map(async (d) => {
    const host = d.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    try {
      const res = await fetch(`https://${host}/3/device/${d.token}`, {
        method: "POST",
        headers: { authorization: `bearer ${jwt}`, "apns-topic": env.APNS_TOPIC, "apns-push-type": "alert", "apns-priority": "10" },
        body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", category: "AUTOBOOK_RESULT" }, ...data }),
      });
      if (res.status === 410 || (res.status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(await res.text()))) gone.push(d.token);
      else if (!res.ok) console.log("apns", res.status, await res.text());
    } catch (e) { console.log("apns failed:", e.message); }
  }));
  return gone;
}

// MARK: Users (D1)

let schemaReady = false;
async function db(env) {
  if (!schemaReady) {
    await env.DB.prepare(`CREATE TABLE IF NOT EXISTS users (
      user_id INTEGER PRIMARY KEY, access_token TEXT NOT NULL, rules TEXT NOT NULL DEFAULT '[]',
      devices TEXT NOT NULL DEFAULT '[]', state TEXT NOT NULL DEFAULT '{}', updated_at TEXT)`).run();
    schemaReady = true;
  }
  return env.DB;
}

const emptyState = () => ({ upcoming: [], handled: {}, log: [], lastScan: null });

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

/** One user's minute: book what opens now, rescan when it is this user's turn. Returns false if the login died. */
export async function tickUser(env, u, now, { force = false, bookFn = book } = {}) {
  const { rules, session, state } = u;
  let loggedOut = false;
  const due = state.upcoming.filter((o) => o.opens <= now + DUE_AHEAD_MS && o.start > now && !state.handled[o.classId]);
  const results = await Promise.all(due.map((o) => bookFn(session, o).then((outcome) => ({ o, outcome }))));
  for (const { o, outcome } of results) {
    // Tried once: an auto-booked class that is cancelled later is not booked again.
    state.handled[o.classId] = o.start;
    state.log.unshift({ classId: o.classId, title: o.title, at: new Date().toISOString(), outcome });
    if (outcome === "Login expired") { loggedOut = true; continue; }
    const gone = await push(env, u.devices, `${outcome}: ${o.title}`, `${when(o.start)} · auto-book`, { classId: o.classId });
    u.devices = u.devices.filter((d) => !gone.includes(d.token));
  }
  state.upcoming = state.upcoming.filter((o) => !state.handled[o.classId] && o.start > now);
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
      await push(env, u.devices, "Auto-book paused", "Your Bruce login expired. Open Brüce to continue.");
      await deleteUser(env, u.userId);
      return;
    }
    if (JSON.stringify([u.state, u.devices]) !== before) await saveUser(env, u);
  }));
}

// MARK: HTTP API

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
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
  return body?.user?.id === userId ? { userId, token } : null;
}

function cleanRules(rules) {
  return rules.slice(0, 30).map((r) => ({ id: String(r.id), studioId: +r.studioId, masterId: r.masterId ?? null, title: String(r.title).slice(0, 200),
                                          weekday: +r.weekday, minuteOfDay: +r.minuteOfDay }));
}

function cleanDevice(d) {
  if (!d || typeof d.token !== "string" || !/^[0-9a-f]{32,200}$/i.test(d.token)) return null;
  return { token: d.token.toLowerCase(), env: d.env === "sandbox" ? "sandbox" : "production" };
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(tick(env, event.scheduledTime));
  },

  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    const route = `${request.method} ${pathname.replace(/\/+$/, "")}`;
    if (!["PUT /me", "GET /me", "DELETE /me", "POST /me/test-push"].includes(route)) return json({ error: "not found" }, 404);
    const auth = await authenticate(request, env);
    if (!auth) return json({ error: "unauthorized" }, 401);
    switch (route) {
      case "PUT /me": {
        // Upsert: the current login, the rules, and this device's push token.
        const body = await request.json().catch(() => ({}));
        if (!Array.isArray(body.rules)) return json({ error: "rules must be an array" }, 400);
        const u = (await getUser(env, auth.userId)) ?? { userId: auth.userId, rules: [], devices: [], state: emptyState() };
        u.session = { access_token: auth.token, user_id: auth.userId };
        const rulesChanged = JSON.stringify(u.rules) !== JSON.stringify(cleanRules(body.rules));
        u.rules = cleanRules(body.rules);
        const d = cleanDevice(body.device);
        if (d) u.devices = [d, ...u.devices.filter((x) => x.token !== d.token)].slice(0, MAX_DEVICES);
        if (rulesChanged) await tickUser(env, u, Date.now(), { force: true }).catch((e) => console.log("scan failed:", e.message));
        await saveUser(env, u);
        return json({ ok: true, rules: u.rules.length, push: apnsConfigured(env) && u.devices.length > 0 });
      }
      case "GET /me": {
        const u = await getUser(env, auth.userId);
        const opens = (o) => ({ classId: o.classId, title: o.title, at: new Date(o.opens).toISOString(), outcome: "Opens" });
        return json({ hasSession: !!u, rules: u?.rules ?? [], lastScan: u?.state.lastScan ?? null,
                      upcoming: (u?.state.upcoming ?? []).map(opens), log: u?.state.log ?? [], devices: u?.devices.length ?? 0 });
      }
      case "DELETE /me":
        await deleteUser(env, auth.userId);
        return json({ ok: true });
      case "POST /me/test-push": {
        const u = await getUser(env, auth.userId);
        if (!u?.devices.length || !apnsConfigured(env)) return json({ error: "no device or push not configured" }, 409);
        await push(env, u.devices, "Auto-book is set up", "You'll get a push like this when a class is booked.");
        return json({ ok: true });
      }
    }
  },
};
