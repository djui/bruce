// One scheduler tick (every 5 minutes): scan the rules, find each upcoming occurrence and its open
// moment, and fire the booking for every occurrence that opens before the next tick (or is already
// open). Firing waits inside this tick until ~2 s before the open moment.
import { AuthError, type BruceApi, type BruceClass, type VisitLimit } from "./api.ts";
import { fireBooking, type Outcome } from "./booker.ts";
import type { Clock } from "./clock.ts";
import type { Config, Options, Rule } from "./config.ts";
import type { Log, Notifier } from "./notify.ts";
import { candidateStarts, closeTimeMs, isListed, matchesRule, openTimeMs, startMs } from "./rules.ts";
import { claimable, type Entry, type Status, type Store, type Versioned } from "./store.ts";
import { formatLocal, yearMonth } from "./time.ts";

export interface Occurrence {
  rule: Rule;
  cls: BruceClass;
  startMs: number;
  /** Server-time open moment; null = no booking window. */
  openMs: number | null;
  closeMs: number | null;
}

export type PlanAction = "fire" | "later" | "ignore";

export interface PlanItem {
  occ: Occurrence;
  action: PlanAction;
  /** For "fire": when the first attempt goes out (local clock, before skew correction). */
  fireAtMs?: number;
  why: string;
}

export interface TickDeps {
  api: BruceApi;
  store: Store;
  notifier: Notifier;
  clock: Clock;
  config: Config;
  log: Log;
  dryRun: boolean;
  /** Short hash of the access token; a 401 is remembered per token so a dead token is not retried. */
  tokenFingerprint: string;
}

export interface FireResult {
  occ: Occurrence;
  outcome: Outcome | { status: "auth"; attempts: number; detail: string };
}

export interface TickResult {
  items: PlanItem[];
  warnings: string[];
  /** Resolves when every booking fired by this tick has finished. */
  done: Promise<FireResult[]>;
  authFailed: boolean;
}

const AUTH_META = "auth_failed_token";

export async function tokenFingerprint(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest).slice(0, 6), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Lists the classes that match each enabled rule. Narrow GETs: one per rule and candidate date. */
export async function scan(api: BruceApi, rules: Rule[], nowMs: number, opts: Options): Promise<{ occurrences: Occurrence[]; warnings: string[] }> {
  const occurrences: Occurrence[] = [];
  const warnings: string[] = [];
  for (const rule of rules.filter((r) => r.enabled)) {
    for (const start of candidateStarts(rule, nowMs, opts.lookaheadDays)) {
      const classes = (await api.listClasses(rule.studioId, start - 60_000, start + 60_000)).filter(
        (c) => isListed(c) && matchesRule(c, rule),
      );
      const unique = [...new Map(classes.map((c) => [c.id, c])).values()];
      if (unique.length === 0) continue; // not listed yet (classes appear ~14 days ahead) or no class that week
      if (unique.length > 1) {
        warnings.push(
          `rule ${rule.id}: ${unique.length} classes match on ${formatLocal(start)} (${unique
            .map((c) => `${c.id} "${c.title}" master_id=${c.master_id ?? "null"}`)
            .join("; ")}); add "title" or "master_id" to the rule. Skipped.`,
        );
        continue;
      }
      const cls = unique[0];
      occurrences.push({ rule, cls, startMs: startMs(cls), openMs: openTimeMs(cls), closeMs: closeTimeMs(cls) });
    }
  }
  return { occurrences, warnings };
}

/**
 * Pure planning. An occurrence is fired in this tick when its window opens before the next tick
 * (plus slack), or is already open and `catch_up` is on. Everything else waits for a later tick.
 */
export function plan(occs: Occurrence[], entries: Map<number, Entry | undefined>, nowMs: number, opts: Options): PlanItem[] {
  const horizon = nowMs + (opts.tickSeconds + opts.horizonSlackSeconds) * 1000;
  return occs.map((occ): PlanItem => {
    const { cls } = occ;
    if (occ.startMs <= nowMs) return { occ, action: "ignore", why: "already started" };
    if (occ.closeMs != null && occ.closeMs <= nowMs) return { occ, action: "ignore", why: "booking closed" };
    const c = claimable(entries.get(cls.id), nowMs, opts, cls.available_spots);
    if (!c.ok) return { occ, action: "ignore", why: c.why };
    if (occ.openMs == null || occ.openMs <= nowMs) {
      if (!opts.catchUp) return { occ, action: "ignore", why: "window already open (catch_up is off)" };
      return { occ, action: "fire", fireAtMs: nowMs, why: occ.openMs == null ? "no booking window" : "window already open" };
    }
    if (occ.openMs <= horizon) {
      return { occ, action: "fire", fireAtMs: Math.max(nowMs, occ.openMs - opts.leadMs), why: `opens ${formatLocal(occ.openMs)}` };
    }
    return { occ, action: "later", why: `opens ${formatLocal(occ.openMs)}` };
  });
}

/** Why the user's limits rule out booking this class, or undefined if they don't. */
export function limitBlock(limits: VisitLimit[], cls: BruceClass): string | undefined {
  const by = (t: string) => limits.find((l) => l.type === t);
  const exhausted = (l: VisitLimit | undefined) => l != null && (l.total ?? 0) > 0 && (l.remaining ?? 1) <= 0;
  const sim = by("SIMULTANEOUS");
  if (exhausted(sim)) return `simultaneous bookings limit reached (${sim!.used}/${sim!.total})`;
  const monthly = by("MONTHLY");
  if (exhausted(monthly)) return `monthly visit limit reached (${monthly!.used}/${monthly!.total})`;
  const studio = by("STUDIO");
  if (studio && studio.total === -1) return "this studio is not included in your plan";
  if (exhausted(studio)) return `visit limit at this studio reached (${studio!.used}/${studio!.total})`;
  const a = cls.user_attendance_info;
  if (a?.booking_limit_reached) return "booking limit reached";
  if (a?.visit_limit_reached) return `visit limit reached (${(a.visit_limit_reached_types ?? []).join(", ") || "?"})`;
  return undefined;
}

function entryFor(occ: Occurrence, status: Status, nowMs: number, prev: Entry | undefined, extra: Partial<Entry> = {}): Entry {
  return {
    classId: occ.cls.id,
    ruleId: occ.rule.id,
    title: occ.cls.title ?? "",
    studioId: occ.cls.studio_id,
    start: new Date(occ.startMs).toISOString(),
    status,
    updatedAt: new Date(nowMs).toISOString(),
    attempts: prev?.attempts ?? 0,
    ...extra,
  };
}

function describeOcc(occ: Occurrence): string {
  return `${occ.cls.title ?? "class"} ${formatLocal(occ.startMs)} (studio ${occ.cls.studio_id}, class ${occ.cls.id}${occ.rule.name ? `, rule "${occ.rule.name}"` : ""})`;
}

export async function runTick(d: TickDeps): Promise<TickResult> {
  const { api, store, notifier, clock, config, log } = d;
  const opts = config.options;
  const none = (authFailed = false): TickResult => ({ items: [], warnings: [], done: Promise.resolve([]), authFailed });

  if ((await store.getMeta(AUTH_META)) === d.tokenFingerprint) {
    log("access token was rejected earlier (HTTP 401); waiting for a new BRUCE_ACCESS_TOKEN. Nothing to do.");
    return none(true);
  }
  const onAuth = async () => {
    await store.setMeta(AUTH_META, d.tokenFingerprint);
    await notifier.notify({ kind: "auth", title: "Bruce autobook: log in again", message: new AuthError().message });
  };

  const now = clock.now();
  let occurrences: Occurrence[];
  let warnings: string[];
  try {
    ({ occurrences, warnings } = await scan(api, config.rules, now, opts));
  } catch (e) {
    if (e instanceof AuthError) {
      await onAuth();
      return none(true);
    }
    throw e;
  }
  for (const w of warnings) log(`WARNING ${w}`);

  const versions = new Map<number, Versioned | undefined>();
  for (const o of occurrences) versions.set(o.cls.id, await store.get(o.cls.id));
  const entries = new Map([...versions].map(([k, v]) => [k, v?.entry]));
  const items = plan(occurrences, entries, now, opts);
  for (const it of items) log(`${it.action.padEnd(6)} ${describeOcc(it.occ)}: ${it.why}`);

  const toFire = items.filter((it) => it.action === "fire");
  if (toFire.length === 0) {
    await store.prune(new Date(now - 3 * 86_400_000).toISOString());
    return { items, warnings, done: Promise.resolve([]), authFailed: false };
  }

  // Pre-checks, once per tick and only when something is about to be fired.
  let booked = new Set<number>();
  let standby = new Set<number>();
  const limitCache = new Map<string, Promise<VisitLimit[]>>();
  const ready: PlanItem[] = [];
  try {
    booked = await api.bookedClassIds(now - 86_400_000);
    standby = await api.standbyClassIds(now);
    for (const it of toFire) {
      const { cls } = it.occ;
      const prev = versions.get(cls.id);
      if (booked.has(cls.id)) {
        log(`skip ${describeOcc(it.occ)}: you already have a booking`);
        await store.put(cls.id, entryFor(it.occ, "booked", now, prev?.entry, { reason: "booked outside autobook" }));
        continue;
      }
      if (standby.has(cls.id)) {
        log(`skip ${describeOcc(it.occ)}: you are on the waitlist`);
        await store.put(cls.id, entryFor(it.occ, "waitlisted", now, prev?.entry, { reason: "joined outside autobook" }));
        continue;
      }
      const key = `${cls.studio_id}|${yearMonth(it.occ.startMs)}`;
      if (!limitCache.has(key)) limitCache.set(key, api.visitLimits(cls.studio_id, yearMonth(it.occ.startMs)));
      let limits: VisitLimit[] = [];
      try {
        limits = await limitCache.get(key)!;
      } catch (e) {
        if (e instanceof AuthError) throw e;
        log(`could not read visit limits (${(e as Error).message}); booking anyway`);
      }
      const block = limitBlock(limits, cls);
      if (block) {
        const changed = prev?.entry.status !== "skipped" || prev.entry.reason !== block;
        log(`skip ${describeOcc(it.occ)}: ${block}`);
        await store.put(cls.id, entryFor(it.occ, "skipped", now, prev?.entry, { reason: block }));
        if (changed && !d.dryRun) await notifier.notify({ kind: "skipped", title: "Bruce autobook: skipped", message: `${describeOcc(it.occ)}: ${block}`, classId: cls.id });
        continue;
      }
      ready.push(it);
    }
  } catch (e) {
    if (e instanceof AuthError) {
      await onAuth();
      return { items, warnings, done: Promise.resolve([]), authFailed: true };
    }
    throw e;
  }

  // Claim (compare-and-set) so that an overlapping run never fires the same class.
  const claimed: PlanItem[] = [];
  for (const it of ready) {
    const { cls } = it.occ;
    const prev = versions.get(cls.id);
    const leaseUntil = Math.max(now, it.occ.openMs ?? now) + (opts.retryWindowSeconds + opts.tickSeconds) * 1000;
    const ok = await store.cas(cls.id, prev?.version ?? null, entryFor(it.occ, "pending", now, prev?.entry, { leaseUntil }));
    if (ok) claimed.push(it);
    else log(`skip ${describeOcc(it.occ)}: claimed by another run`);
  }

  let authNotified = false;
  const done = Promise.all(
    claimed.map(async (it): Promise<FireResult> => {
      const { occ } = it;
      const prev = (await store.get(occ.cls.id))?.entry;
      try {
        const outcome = await fireBooking({
          api,
          clock,
          log,
          opts,
          cls: occ.cls,
          openMs: occ.openMs,
          waitlistIfFull: occ.rule.waitlistIfFull,
          dryRun: d.dryRun,
          skewMs: api.serverSkewMs,
        });
        const t = clock.now();
        if (outcome.status === "dry-run") {
          await store.put(occ.cls.id, entryFor(occ, "skipped", t, prev, { reason: "dry run" }));
          await notifier.notify({ kind: "dry-run", title: "Bruce autobook (dry run)", message: `Would book ${describeOcc(occ)}`, classId: occ.cls.id });
        } else {
          const attempts = (prev?.attempts ?? 0) + (outcome.status === "failed" ? 1 : 0);
          await store.put(occ.cls.id, entryFor(occ, outcome.status, t, prev, { attempts, reason: outcome.detail }));
          const title = {
            booked: "Bruce autobook: booked",
            waitlisted: "Bruce autobook: on the waitlist",
            full: "Bruce autobook: class full",
            failed: "Bruce autobook: booking failed",
          }[outcome.status];
          await notifier.notify({ kind: outcome.status, title, message: `${describeOcc(occ)}: ${outcome.detail}`, classId: occ.cls.id });
        }
        return { occ, outcome };
      } catch (e) {
        if (e instanceof AuthError) {
          // Not counted as an attempt: after logging in again the class is tried once more.
          await store.put(occ.cls.id, entryFor(occ, "failed", clock.now(), prev, { reason: "access token rejected (401)" }));
          if (!authNotified) {
            authNotified = true;
            await onAuth();
          }
          return { occ, outcome: { status: "auth", attempts: 0, detail: e.message } };
        }
        const msg = (e as Error).message;
        await store.put(occ.cls.id, entryFor(occ, "failed", clock.now(), prev, { attempts: (prev?.attempts ?? 0) + 1, reason: msg }));
        await notifier.notify({ kind: "error", title: "Bruce autobook: error", message: `${describeOcc(occ)}: ${msg}`, classId: occ.cls.id });
        return { occ, outcome: { status: "failed", attempts: 0, detail: msg } };
      }
    }),
  ).then(async (r) => {
    await store.prune(new Date(clock.now() - 3 * 86_400_000).toISOString());
    return r;
  });

  return { items, warnings, done, authFailed: false };
}
