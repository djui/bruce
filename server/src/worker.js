// Bruce auto-book server: a Cloudflare Worker that books weekly classes the moment their booking window opens.
//
// A class opens for booking at `bookable_earliest_time` = start - `bookable_earliest` (7 days for ~97% of classes),
// and classes are listed about 14 days ahead (see ../../API.md "Booking windows"). The cron runs every minute but
// only talks to Bruce when there is something to do:
// - every 5 minutes it re-reads the classes of each rule (scan),
// - in the minute before a class opens it waits for the open moment and books it.
// Other minutes only read the stored state.
//
// Storage (KV namespace AUTOBOOK): "rules" (from the app), "session" (Bruce access token, only after the user sent
// it), "state" (upcoming classes, handled class ids, log). HTTP API (Bearer API_KEY): see ../README.md.

const API = "https://api.bruce.app";
const USER_AGENT = "Bruce/14.4.2_538 (iOS27.0.0; Apple)";
const TZ = "Europe/Stockholm";
const DEFAULT_WINDOW_S = 7 * 24 * 3600;
const LOOKAHEAD_DAYS = 15;
const SCAN_EVERY_MIN = 5;
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

// MARK: Cron

async function load(env) {
  const [rules, session, state] = await Promise.all([
    env.AUTOBOOK.get("rules", "json"), env.AUTOBOOK.get("session", "json"), env.AUTOBOOK.get("state", "json"),
  ]);
  return { rules: rules ?? [], session, state: state ?? { upcoming: [], handled: {}, log: [], lastScan: null } };
}

async function notify(env, text) {
  if (!env.NTFY_TOPIC) return;
  await fetch(`https://ntfy.sh/${env.NTFY_TOPIC}`, { method: "POST", body: text, headers: { Title: "Bruce auto-book" } }).catch(() => {});
}

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

export async function tick(env, now, { force = false } = {}) {
  const { rules, session, state } = await load(env);
  if (!session || !rules.length) return;
  const before = JSON.stringify(state);
  let loggedOut = false;
  // Book first: a due class must not wait for a scan.
  const due = state.upcoming.filter((o) => o.opens <= now + DUE_AHEAD_MS && o.start > now && !state.handled[o.classId]);
  const results = await Promise.all(due.map((o) => book(session, o).then((outcome) => ({ o, outcome }))));
  for (const { o, outcome } of results) {
    // Tried once: an auto-booked class that is cancelled later is not booked again.
    state.handled[o.classId] = o.start;
    state.log.unshift({ classId: o.classId, title: o.title, at: new Date().toISOString(), outcome });
    await notify(env, `${outcome}: ${o.title}, ${new Date(o.start).toLocaleString("en-GB", { timeZone: TZ, weekday: "short", hour: "2-digit", minute: "2-digit" })}`);
    if (outcome === "Login expired") loggedOut = true;
  }
  state.upcoming = state.upcoming.filter((o) => !state.handled[o.classId] && o.start > now);
  const minute = Math.floor(now / 60_000);
  if (!loggedOut && (force || minute % SCAN_EVERY_MIN === 0 || !state.lastScan)) {
    try { await scan(rules, session, state, now); }
    catch (e) {
      if (e instanceof LoggedOut) loggedOut = true;
      else console.log("scan failed:", e.message);   // keep the last known classes; next scan retries
    }
  }
  if (loggedOut) {
    await env.AUTOBOOK.delete("session");
    state.log.unshift({ classId: 0, title: "Bruce login expired: send it again from the app", at: new Date().toISOString(), outcome: "Stopped" });
    await notify(env, "Bruce login expired. Open the app, Auto-book, and send the login again.");
  }
  // Forget handled classes once they are over, keep the log short.
  for (const [id, start] of Object.entries(state.handled)) if (start < now - 86400_000) delete state.handled[id];
  state.log = state.log.slice(0, LOG_SIZE);
  const after = JSON.stringify(state);
  if (after !== before) await env.AUTOBOOK.put("state", after);   // KV writes are limited: only on change
}

// MARK: HTTP API

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(tick(env, event.scheduledTime));
  },

  async fetch(request, env, ctx) {
    if (!env.API_KEY || request.headers.get("Authorization") !== `Bearer ${env.API_KEY}`) return json({ error: "unauthorized" }, 401);
    const { pathname } = new URL(request.url);
    const route = `${request.method} ${pathname.replace(/\/+$/, "")}`;
    switch (route) {
      case "PUT /rules": {
        const { rules } = await request.json();
        if (!Array.isArray(rules)) return json({ error: "rules must be an array" }, 400);
        const clean = rules.map((r) => ({ id: String(r.id), studioId: +r.studioId, masterId: r.masterId ?? null, title: String(r.title),
                                          weekday: +r.weekday, minuteOfDay: +r.minuteOfDay }));
        await env.AUTOBOOK.put("rules", JSON.stringify(clean));
        ctx.waitUntil(tick(env, Date.now(), { force: true }));
        return json({ ok: true, rules: clean.length });
      }
      case "PUT /session": {
        const { access_token, user_id } = await request.json();
        if (typeof access_token !== "string" || !access_token) return json({ error: "access_token missing" }, 400);
        await env.AUTOBOOK.put("session", JSON.stringify({ access_token, user_id: user_id ?? null }));
        ctx.waitUntil(tick(env, Date.now(), { force: true }));
        return json({ ok: true });
      }
      case "DELETE /session":
        await env.AUTOBOOK.delete("session");
        return json({ ok: true });
      case "GET /status": {
        const { rules, session, state } = await load(env);
        const iso = (o) => ({ classId: o.classId, title: o.title, at: new Date(o.opens).toISOString(), outcome: "Opens" });
        return json({ hasSession: !!session, rules, lastScan: state.lastScan, upcoming: state.upcoming.map(iso), log: state.log });
      }
      default:
        return json({ error: "not found" }, 404);
    }
  },
};
