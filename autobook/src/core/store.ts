// State: one entry per class id, so a class is never booked twice. Writes are compare-and-set on a
// version number, which lets overlapping runs (e.g. two cron invocations) claim a class at most once.
import type { Options } from "./config.ts";

export type Status = "pending" | "booked" | "waitlisted" | "full" | "skipped" | "failed";

export interface Entry {
  classId: number;
  ruleId: string;
  title: string;
  studioId: number;
  /** Class start (ISO, UTC); used for pruning. */
  start: string;
  status: Status;
  updatedAt: string;
  /** While `pending`: the run that claimed it owns it until this time (ms). */
  leaseUntil?: number;
  /** Runs that ended in `failed`. */
  attempts: number;
  reason?: string;
}

export interface Versioned {
  entry: Entry;
  version: number;
}

export interface Store {
  get(classId: number): Promise<Versioned | undefined>;
  /** Writes `entry` only if the stored version is `expected` (`null` = must not exist). */
  cas(classId: number, expected: number | null, entry: Entry): Promise<boolean>;
  /** Unconditional write (used by the run that holds the lease). */
  put(classId: number, entry: Entry): Promise<void>;
  getMeta(key: string): Promise<string | undefined>;
  setMeta(key: string, value: string | undefined): Promise<void>;
  /** Removes entries for classes that started before `beforeIso`. */
  prune(beforeIso: string): Promise<number>;
}

export type Claimability = { ok: true } | { ok: false; why: string };

/** May a new run work on this class, given its stored entry? */
export function claimable(e: Entry | undefined, nowMs: number, opts: Options, availableSpots?: number | null): Claimability {
  if (!e) return { ok: true };
  switch (e.status) {
    case "pending":
      return e.leaseUntil != null && e.leaseUntil > nowMs ? { ok: false, why: "in progress in another run" } : { ok: true };
    case "booked":
      return { ok: false, why: "already booked" };
    case "waitlisted":
      return { ok: false, why: "on the waitlist" };
    case "full":
      return opts.rebookWhenSpotFrees && (availableSpots ?? 0) > 0
        ? { ok: true }
        : { ok: false, why: "was full" };
    case "skipped":
      return { ok: true };
    case "failed":
      return e.attempts < opts.maxTickAttempts ? { ok: true } : { ok: false, why: `gave up after ${e.attempts} runs` };
  }
}

export class MemoryStore implements Store {
  entries = new Map<number, Versioned>();
  meta = new Map<string, string>();

  async get(classId: number) {
    const v = this.entries.get(classId);
    return v ? { entry: { ...v.entry }, version: v.version } : undefined;
  }
  async cas(classId: number, expected: number | null, entry: Entry) {
    const cur = this.entries.get(classId);
    if ((cur?.version ?? null) !== expected) return false;
    this.entries.set(classId, { entry: { ...entry }, version: (cur?.version ?? 0) + 1 });
    return true;
  }
  async put(classId: number, entry: Entry) {
    const cur = this.entries.get(classId);
    this.entries.set(classId, { entry: { ...entry }, version: (cur?.version ?? 0) + 1 });
  }
  async getMeta(key: string) {
    return this.meta.get(key);
  }
  async setMeta(key: string, value: string | undefined) {
    if (value === undefined) this.meta.delete(key);
    else this.meta.set(key, value);
  }
  async prune(beforeIso: string) {
    let n = 0;
    for (const [id, v] of this.entries) {
      if (v.entry.start < beforeIso) {
        this.entries.delete(id);
        n++;
      }
    }
    return n;
  }
}

/** Dry-run store: reads fall through to the real store, writes stay in memory. */
export class OverlayStore implements Store {
  private readonly base: Store;
  private readonly mem = new MemoryStore();
  constructor(base: Store) {
    this.base = base;
  }
  async get(classId: number) {
    return (await this.mem.get(classId)) ?? (await this.base.get(classId));
  }
  async cas(classId: number, expected: number | null, entry: Entry) {
    const cur = await this.get(classId);
    if ((cur?.version ?? null) !== expected) return false;
    this.mem.entries.set(classId, { entry: { ...entry }, version: (cur?.version ?? 0) + 1 });
    return true;
  }
  async put(classId: number, entry: Entry) {
    const cur = await this.get(classId);
    this.mem.entries.set(classId, { entry: { ...entry }, version: (cur?.version ?? 0) + 1 });
  }
  async getMeta(key: string) {
    return this.mem.meta.has(key) ? this.mem.meta.get(key) : this.base.getMeta(key);
  }
  async setMeta(key: string, value: string | undefined) {
    await this.mem.setMeta(key, value);
  }
  async prune() {
    return 0;
  }
}
