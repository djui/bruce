// Config file: a list of weekly rules plus tuning options. Input keys are snake_case, like the API.
import { parseHHMM, parseWeekday } from "./time.ts";

export interface Rule {
  /** Stable id used in state and logs: `name`, or derived from the rule fields. */
  id: string;
  name?: string;
  studioId: number;
  /** The class's weekly series (`master_id` in the class payload). Most precise match when set. */
  masterId?: number;
  /** Case-insensitive substring of the class title, to tell apart classes at the same studio and time. */
  title?: string;
  /** ISO weekday, 1 = Monday. */
  weekday: number;
  /** Local start time "HH:MM" (Europe/Stockholm). */
  time: string;
  /** Join the waitlist (`POST /v52/standby`) when the class is already full. */
  waitlistIfFull: boolean;
  enabled: boolean;
}

export interface Options {
  /** Scan interval. Must match the scheduler (service loop, cron, launchd StartInterval). */
  tickSeconds: number;
  /** Extra look-ahead past the next tick, to absorb scheduler jitter. */
  horizonSlackSeconds: number;
  /** Fire the first booking attempt this long before the open moment. */
  leadMs: number;
  /** Pause between booking attempts. */
  retryIntervalMs: number;
  /** Keep retrying this long after the open moment (or after the first attempt, if later). */
  retryWindowSeconds: number;
  /** A 4xx this long after the open moment counts as "really open", and the class gets re-read. */
  openGraceMs: number;
  /** Book matching classes whose window is already open (e.g. a rule added late, or a missed tick). */
  catchUp: boolean;
  /** How far ahead to look for occurrences (booking windows are at most 14 days). */
  lookaheadDays: number;
  /** Give up on a class after this many ticks ended in "failed". */
  maxTickAttempts: number;
  /** Try again when a class that was full (and not waitlisted) shows a free spot in a later scan. */
  rebookWhenSpotFrees: boolean;
}

export interface Config {
  rules: Rule[];
  options: Options;
  /** Bruce user id; can also come from BRUCE_USER_ID. */
  userId?: number;
}

export const DEFAULT_OPTIONS: Options = {
  tickSeconds: 300,
  horizonSlackSeconds: 60,
  leadMs: 2000,
  retryIntervalMs: 1000,
  retryWindowSeconds: 60,
  openGraceMs: 3000,
  catchUp: true,
  lookaheadDays: 15,
  maxTickAttempts: 3,
  rebookWhenSpotFrees: true,
};

const OPTION_KEYS: Record<string, keyof Options> = {
  tick_seconds: "tickSeconds",
  horizon_slack_seconds: "horizonSlackSeconds",
  lead_ms: "leadMs",
  retry_interval_ms: "retryIntervalMs",
  retry_window_seconds: "retryWindowSeconds",
  open_grace_ms: "openGraceMs",
  catch_up: "catchUp",
  lookahead_days: "lookaheadDays",
  max_tick_attempts: "maxTickAttempts",
  rebook_when_spot_frees: "rebookWhenSpotFrees",
};

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function positiveInt(v: unknown, what: string): number {
  if (typeof v === "number" && Number.isInteger(v) && v > 0) return v;
  if (typeof v === "string" && /^\d+$/.test(v) && Number(v) > 0) return Number(v);
  throw new Error(`${what} must be a positive integer, got ${JSON.stringify(v)}`);
}

export function parseRule(raw: unknown, index: number): Rule {
  const where = `rules[${index}]`;
  if (!isObject(raw)) throw new Error(`${where} must be an object`);
  try {
    const studioId = positiveInt(raw.studio_id, "studio_id");
    const weekday = parseWeekday(raw.weekday);
    const time = parseHHMM(raw.time);
    const masterId = raw.master_id == null ? undefined : positiveInt(raw.master_id, "master_id");
    let title: string | undefined;
    if (raw.title != null) {
      if (typeof raw.title !== "string" || !raw.title.trim()) throw new Error("title must be a non-empty string");
      title = raw.title.trim();
    }
    let name: string | undefined;
    if (raw.name != null) {
      if (typeof raw.name !== "string" || !raw.name.trim()) throw new Error("name must be a non-empty string");
      name = raw.name.trim();
    }
    const waitlistIfFull = raw.waitlist_if_full == null ? false : raw.waitlist_if_full === true;
    const enabled = raw.enabled == null ? true : raw.enabled === true;
    const id =
      name ??
      [`studio${studioId}`, `wd${weekday}`, time.replace(":", ""), masterId ? `m${masterId}` : title ? `t:${title.toLowerCase()}` : ""]
        .filter(Boolean)
        .join("-");
    return { id, name, studioId, masterId, title, weekday, time, waitlistIfFull, enabled };
  } catch (e) {
    throw new Error(`${where}: ${(e as Error).message}`);
  }
}

/** Parses and validates the config object (from JSON). Throws with a readable message. */
export function parseConfig(raw: unknown): Config {
  if (!isObject(raw)) throw new Error("config must be a JSON object");
  if (!Array.isArray(raw.rules)) throw new Error("config.rules must be an array");
  const rules = raw.rules.map(parseRule);
  const ids = new Set<string>();
  for (const r of rules) {
    if (ids.has(r.id)) throw new Error(`duplicate rule id "${r.id}" (give the rules distinct names)`);
    ids.add(r.id);
  }
  const options: Options = { ...DEFAULT_OPTIONS };
  if (raw.options != null) {
    if (!isObject(raw.options)) throw new Error("config.options must be an object");
    for (const [k, v] of Object.entries(raw.options)) {
      const key = OPTION_KEYS[k];
      if (!key) throw new Error(`unknown option "${k}"`);
      if (typeof DEFAULT_OPTIONS[key] === "boolean") {
        if (typeof v !== "boolean") throw new Error(`option ${k} must be true or false`);
        (options as unknown as Record<string, unknown>)[key] = v;
      } else {
        (options as unknown as Record<string, unknown>)[key] = positiveInt(v, `option ${k}`);
      }
    }
  }
  if (options.lookaheadDays > 31) throw new Error("option lookahead_days must be at most 31");
  const userId = raw.user_id == null ? undefined : positiveInt(raw.user_id, "user_id");
  return { rules, options, userId };
}
