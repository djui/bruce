// Pure rule logic: weekly candidates, class matching and the booking-window open moment.
import type { BruceClass } from "./api.ts";
import type { Rule } from "./config.ts";
import { localHHMM, localParts, TZ, zonedToUtc } from "./time.ts";

const DAY_MS = 86_400_000;

/**
 * Start instants (UTC ms) of the rule's weekly slot after `nowMs`, up to `lookaheadDays` ahead.
 * DST-safe: each candidate is the local wall-clock time on that local date.
 */
export function candidateStarts(rule: Rule, nowMs: number, lookaheadDays: number, tz: string = TZ): number[] {
  const today = localParts(nowMs, tz);
  const [hh, mm] = rule.time.split(":").map(Number);
  const out: number[] = [];
  for (let i = 0; i <= lookaheadDays; i++) {
    // Calendar arithmetic on the local date, done in UTC to avoid DST effects.
    const d = new Date(Date.UTC(today.year, today.month - 1, today.day) + i * DAY_MS);
    const isoWeekday = ((d.getUTCDay() + 6) % 7) + 1;
    if (isoWeekday !== rule.weekday) continue;
    const t = zonedToUtc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), hh, mm, tz);
    if (t > nowMs && t <= nowMs + lookaheadDays * DAY_MS) out.push(t);
  }
  return out;
}

export function startMs(c: BruceClass): number {
  return Date.parse(c.start_time);
}

/**
 * When booking opens: `bookable_earliest_time` when present, else `start - bookable_earliest` seconds.
 * `null` means the class has no window (bookable as soon as it is listed).
 */
export function openTimeMs(c: BruceClass): number | null {
  if (c.bookable_earliest_time) {
    const t = Date.parse(c.bookable_earliest_time);
    if (!Number.isNaN(t)) return t;
  }
  if (typeof c.bookable_earliest === "number") return startMs(c) - c.bookable_earliest * 1000;
  return null;
}

/** When booking closes ("Book until"), or null if unknown. */
export function closeTimeMs(c: BruceClass): number | null {
  if (c.bookable_latest_time) {
    const t = Date.parse(c.bookable_latest_time);
    if (!Number.isNaN(t)) return t;
  }
  if (typeof c.bookable_latest === "number") return startMs(c) - c.bookable_latest * 1000;
  return null;
}

export function normalizeTitle(s: string | null | undefined): string {
  return (s ?? "").toLocaleLowerCase("sv").replace(/\s+/g, " ").trim();
}

/** Does this class belong to the rule's weekly slot? */
export function matchesRule(c: BruceClass, rule: Rule, tz: string = TZ): boolean {
  if (c.studio_id !== rule.studioId) return false;
  const start = startMs(c);
  if (Number.isNaN(start)) return false;
  if (localParts(start, tz).weekday !== rule.weekday) return false;
  if (localHHMM(start, tz) !== rule.time) return false;
  if (rule.masterId != null && c.master_id !== rule.masterId) return false;
  if (rule.title != null && !normalizeTitle(c.title).includes(normalizeTitle(rule.title))) return false;
  return true;
}

/**
 * Series key of a class: `master_id + weekday + HH:MM`, or `(studio, title, weekday, HH:MM)`
 * when `master_id` is null. Used to suggest rules (`autobook plan`).
 */
export function seriesKey(c: BruceClass, tz: string = TZ): string {
  const start = startMs(c);
  const wd = localParts(start, tz).weekday;
  const hm = localHHMM(start, tz);
  return c.master_id ? `m${c.master_id}|${wd}|${hm}` : `s${c.studio_id}|${normalizeTitle(c.title)}|${wd}|${hm}`;
}

export function isListed(c: BruceClass): boolean {
  return !c.deleted && !c.canceled;
}
