// The precise part: wait until just before the booking window opens, then POST and retry until the
// class is booked, turns out full (optionally join the waitlist), or the retry window ends.
import { AuthError, BudgetError, errorMessage, type BruceApi, type BruceClass, type RawResult } from "./api.ts";
import { sleepUntil, type Clock } from "./clock.ts";
import type { Options } from "./config.ts";
import type { Log } from "./notify.ts";
import { formatLocalPrecise } from "./time.ts";

export type Outcome =
  | { status: "booked"; attempts: number; bookingId?: number; detail: string }
  | { status: "waitlisted"; attempts: number; detail: string }
  | { status: "full"; attempts: number; detail: string }
  | { status: "failed"; attempts: number; detail: string }
  | { status: "dry-run"; attempts: number; detail: string };

export interface FireInput {
  api: BruceApi;
  clock: Clock;
  log: Log;
  opts: Options;
  cls: BruceClass;
  /** Server-time open moment; null = no booking window. */
  openMs: number | null;
  waitlistIfFull: boolean;
  dryRun: boolean;
  /** Server clock minus local clock; only applied when it is clearly off (> 2 s). */
  skewMs?: number;
}

type ClassState = "open" | "full" | "booked" | "gone" | "limit";

/** Re-reads the class (and the user's bookings) to tell "full" from "not open yet" or "already booked". */
async function inspect(api: BruceApi, classId: number, sinceMs: number): Promise<{ state: ClassState; why: string }> {
  const booked = await api.bookedClassIds(sinceMs);
  if (booked.has(classId)) return { state: "booked", why: "found in your bookings" };
  const c = await api.getClass(classId);
  if (c.deleted || c.canceled) return { state: "gone", why: "class was cancelled or removed" };
  const a = c.user_attendance_info;
  if (a?.booking_limit_reached) return { state: "limit", why: "booking limit reached" };
  if (a?.visit_limit_reached) return { state: "limit", why: `visit limit reached (${(a.visit_limit_reached_types ?? []).join(", ") || "?"})` };
  if (c.available_spots != null && c.available_spots <= 0) return { state: "full", why: `fully booked (${c.spots ?? "?"} spots)` };
  return { state: "open", why: `${c.available_spots ?? "?"} spots left` };
}

function describe(r: RawResult): string {
  const msg = errorMessage(r.body ?? r.text);
  return `HTTP ${r.status}${msg ? `: ${msg}` : ""}`;
}

export async function fireBooking(i: FireInput): Promise<Outcome> {
  const { api, clock, log, opts, cls } = i;
  const skew = i.skewMs != null && Math.abs(i.skewMs) > 2000 ? i.skewMs : 0;
  // Server time = local time + skew, so the server's open moment is `open - skew` on the local clock.
  const openLocal = i.openMs == null ? clock.now() : i.openMs - skew;
  const fireAt = openLocal - opts.leadMs;
  const label = `class ${cls.id} "${cls.title ?? "?"}"`;
  if (fireAt > clock.now()) {
    log(`${label}: waiting until ${formatLocalPrecise(fireAt)} (opens ${formatLocalPrecise(openLocal)}${skew ? `, server clock skew ${Math.round(skew)} ms` : ""})`);
    await sleepUntil(clock, fireAt);
  }
  const deadline = Math.max(openLocal, clock.now()) + opts.retryWindowSeconds * 1000;
  const since = clock.now() - 86_400_000;
  let attempts = 0;
  let checks = 0;
  let last = "no attempt";
  let full = false;

  if (i.dryRun) {
    log(`DRY RUN ${label}: would POST /v52/booking now (${formatLocalPrecise(clock.now())})`);
    return { status: "dry-run", attempts: 0, detail: "dry run: no request sent" };
  }

  // Already open and visibly full at scan time: skip straight to the waitlist / full handling.
  if (clock.now() >= openLocal && cls.available_spots != null && cls.available_spots <= 0 && i.openMs != null) {
    full = true;
    last = "fully booked when scanned";
  }

  while (!full) {
    attempts++;
    let res: RawResult | undefined;
    try {
      res = await api.book(cls.id);
    } catch (e) {
      if (e instanceof AuthError) throw e;
      if (e instanceof BudgetError) return { status: "failed", attempts, detail: `${e.message} (last: ${last})` };
      last = `network error: ${(e as Error).message}`;
    }
    if (res && res.status >= 200 && res.status < 300) {
      const bookingId = (res.body as { booking?: { id?: number } } | undefined)?.booking?.id;
      log(`${label}: booked on attempt ${attempts} at ${formatLocalPrecise(clock.now())}`);
      return { status: "booked", attempts, bookingId, detail: `booked on attempt ${attempts}` };
    }
    if (res) last = describe(res);
    log(`${label}: attempt ${attempts} -> ${last}`);

    // A 4xx after the window has surely opened: find out why (full? already booked? limit?).
    // Checked on the first such answer and then every 5th, to keep the request rate low.
    if (res && res.status >= 400 && res.status < 500 && res.status !== 429 && clock.now() >= openLocal + opts.openGraceMs) {
      if (checks++ % 5 === 0) {
        try {
          const s = await inspect(api, cls.id, since);
          log(`${label}: class check -> ${s.state} (${s.why})`);
          if (s.state === "booked") return { status: "booked", attempts, detail: `already booked (${s.why})` };
          if (s.state === "gone" || s.state === "limit") return { status: "failed", attempts, detail: `${s.why}; last answer ${last}` };
          if (s.state === "full") {
            full = true;
            last = s.why;
            break;
          }
        } catch (e) {
          if (e instanceof AuthError) throw e;
          if (e instanceof BudgetError) return { status: "failed", attempts, detail: `${e.message} (last: ${last})` };
          log(`${label}: class check failed: ${(e as Error).message}`);
        }
      }
    }
    const pause = res?.status === 429 ? opts.retryIntervalMs * 3 : opts.retryIntervalMs;
    if (clock.now() + pause > deadline) break;
    await clock.sleep(pause);
  }

  if (!full) return { status: "failed", attempts, detail: `not booked within ${opts.retryWindowSeconds} s; last answer ${last}` };
  if (!i.waitlistIfFull) return { status: "full", attempts, detail: last };
  try {
    const w = await api.joinWaitlist(cls.id);
    if (w.status >= 200 && w.status < 300) return { status: "waitlisted", attempts, detail: `${last}; joined the waitlist` };
    return { status: "full", attempts, detail: `${last}; joining the waitlist failed (${describe(w)})` };
  } catch (e) {
    if (e instanceof AuthError) throw e;
    return { status: "full", attempts, detail: `${last}; joining the waitlist failed (${(e as Error).message})` };
  }
}
