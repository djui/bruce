// Time-zone helpers built on Intl only (no dependencies), so they run on Node and Cloudflare Workers.

/** Class times in the rules are Stockholm wall-clock times, like the app shows them. */
export const TZ = "Europe/Stockholm";

export interface LocalParts {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  second: number;
  /** ISO weekday: 1 = Monday ... 7 = Sunday. */
  weekday: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();
const WEEKDAYS: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      weekday: "short",
    });
    formatters.set(tz, f);
  }
  return f;
}

/** Wall-clock parts of an instant in a time zone. */
export function localParts(ms: number, tz: string = TZ): LocalParts {
  const out: Record<string, string> = {};
  for (const p of formatter(tz).formatToParts(new Date(ms))) out[p.type] = p.value;
  return {
    year: Number(out.year),
    month: Number(out.month),
    day: Number(out.day),
    hour: Number(out.hour) % 24,
    minute: Number(out.minute),
    second: Number(out.second),
    weekday: WEEKDAYS[out.weekday] ?? 0,
  };
}

/** Offset of `tz` from UTC at instant `ms`, in milliseconds (Stockholm: +1 h winter, +2 h summer). */
export function tzOffsetMs(ms: number, tz: string = TZ): number {
  const p = localParts(ms, tz);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(ms / 1000) * 1000;
}

/** The instant at which the wall clock in `tz` shows the given local date and time. */
export function zonedToUtc(year: number, month: number, day: number, hour: number, minute: number, tz: string = TZ): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const off1 = tzOffsetMs(guess - tzOffsetMs(guess, tz), tz);
  return guess - off1;
}

export function pad2(n: number): string {
  return String(n).padStart(2, "0");
}

/** "HH:MM" of an instant in `tz`. */
export function localHHMM(ms: number, tz: string = TZ): string {
  const p = localParts(ms, tz);
  return `${pad2(p.hour)}:${pad2(p.minute)}`;
}

/** "Thu 2026-10-15 18:00" (local), for logs and notifications. */
export function formatLocal(ms: number, tz: string = TZ): string {
  const p = localParts(ms, tz);
  const wd = Object.keys(WEEKDAYS)[p.weekday - 1] ?? "?";
  return `${wd} ${p.year}-${pad2(p.month)}-${pad2(p.day)} ${pad2(p.hour)}:${pad2(p.minute)}`;
}

/** "Thu 2026-10-15 18:00:05.250" (local, with seconds), for precise fire logs. */
export function formatLocalPrecise(ms: number, tz: string = TZ): string {
  const p = localParts(ms, tz);
  const millis = String(((ms % 1000) + 1000) % 1000).padStart(3, "0");
  return `${formatLocal(ms, tz)}:${pad2(p.second)}.${millis}`;
}

const WEEKDAY_NAMES: Record<string, number> = {
  mon: 1, monday: 1, tue: 2, tues: 2, tuesday: 2, wed: 3, wednesday: 3, thu: 4, thur: 4, thurs: 4, thursday: 4,
  fri: 5, friday: 5, sat: 6, saturday: 6, sun: 7, sunday: 7,
};

/** Accepts "thu", "Thursday" or ISO numbers 1 (Monday) to 7 (Sunday). */
export function parseWeekday(v: unknown): number {
  if (typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= 7) return v;
  if (typeof v === "string") {
    const n = WEEKDAY_NAMES[v.trim().toLowerCase()];
    if (n) return n;
    if (/^[1-7]$/.test(v.trim())) return Number(v.trim());
  }
  throw new Error(`invalid weekday ${JSON.stringify(v)} (use mon..sun or 1..7, 1 = Monday)`);
}

/** Validates and normalises "H:MM"/"HH:MM" to "HH:MM". */
export function parseHHMM(v: unknown): string {
  if (typeof v === "string") {
    const m = /^(\d{1,2}):(\d{2})$/.exec(v.trim());
    if (m && Number(m[1]) < 24 && Number(m[2]) < 60) return `${pad2(Number(m[1]))}:${m[2]}`;
  }
  throw new Error(`invalid time ${JSON.stringify(v)} (use HH:MM, Stockholm time)`);
}

/** "YYYYMM" of an instant in `tz` (the `month` parameter of user_visit_limit). */
export function yearMonth(ms: number, tz: string = TZ): string {
  const p = localParts(ms, tz);
  return `${p.year}${pad2(p.month)}`;
}
