import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseConfig } from "../src/core/config.ts";
import { candidateStarts, closeTimeMs, matchesRule, openTimeMs, seriesKey } from "../src/core/rules.ts";
import { claimable, MemoryStore, OverlayStore, type Entry } from "../src/core/store.ts";
import { plan, limitBlock, type Occurrence } from "../src/core/tick.ts";
import { formatLocal, localHHMM, localParts, parseHHMM, parseWeekday, zonedToUtc } from "../src/core/time.ts";
import { klass, OPEN, opts, rule } from "./helpers.ts";

describe("time", () => {
  it("converts Stockholm wall-clock times across DST", () => {
    // Summer (CEST, +2) and winter (CET, +1); DST ends 2026-10-25.
    assert.equal(new Date(zonedToUtc(2026, 10, 22, 18, 0)).toISOString(), "2026-10-22T16:00:00.000Z");
    assert.equal(new Date(zonedToUtc(2026, 10, 29, 18, 0)).toISOString(), "2026-10-29T17:00:00.000Z");
    assert.equal(new Date(zonedToUtc(2026, 3, 30, 7, 15)).toISOString(), "2026-03-30T05:15:00.000Z");
  });
  it("reads local weekday and time", () => {
    const t = Date.parse("2026-10-22T16:00:00Z");
    assert.equal(localParts(t).weekday, 4);
    assert.equal(localHHMM(t), "18:00");
    assert.equal(formatLocal(t), "Thu 2026-10-22 18:00");
  });
  it("parses weekdays and times", () => {
    assert.equal(parseWeekday("Thu"), 4);
    assert.equal(parseWeekday("sunday"), 7);
    assert.equal(parseWeekday(1), 1);
    assert.throws(() => parseWeekday("funday"));
    assert.equal(parseHHMM("7:05"), "07:05");
    assert.throws(() => parseHHMM("24:00"));
  });
});

describe("config", () => {
  it("parses rules and options", () => {
    const c = parseConfig({
      user_id: 42,
      rules: [{ name: "Boxing", studio_id: 135, title: "Boxning", weekday: "thu", time: "18:00", waitlist_if_full: true }],
      options: { retry_interval_ms: 800, catch_up: false },
    });
    assert.equal(c.userId, 42);
    assert.deepEqual(c.rules[0], {
      id: "Boxing", name: "Boxing", studioId: 135, masterId: undefined, title: "Boxning", weekday: 4, time: "18:00", waitlistIfFull: true, enabled: true,
    });
    assert.equal(c.options.retryIntervalMs, 800);
    assert.equal(c.options.catchUp, false);
    assert.equal(c.options.tickSeconds, 300);
  });
  it("derives an id and rejects bad input", () => {
    assert.equal(parseConfig({ rules: [{ studio_id: 1, weekday: 2, time: "07:00", master_id: 9 }] }).rules[0].id, "studio1-wd2-0700-m9");
    assert.throws(() => parseConfig({ rules: [{ studio_id: "x", weekday: 2, time: "07:00" }] }), /rules\[0\]: studio_id/);
    assert.throws(() => parseConfig({ rules: [], options: { nope: 1 } }), /unknown option/);
    assert.throws(
      () => parseConfig({ rules: [{ studio_id: 1, weekday: 2, time: "07:00" }, { studio_id: 1, weekday: 2, time: "07:00" }] }),
      /duplicate rule id/,
    );
  });
});

describe("rules", () => {
  it("lists weekly candidates within the look-ahead, DST-aware", () => {
    const now = Date.parse("2026-10-14T10:00:00Z"); // Wed
    const c = candidateStarts(rule(), now, 16).map((t) => new Date(t).toISOString());
    assert.deepEqual(c, ["2026-10-15T16:00:00.000Z", "2026-10-22T16:00:00.000Z", "2026-10-29T17:00:00.000Z"]);
  });
  it("matches by studio, weekday, local time, master_id and title", () => {
    assert.ok(matchesRule(klass(), rule()));
    assert.ok(matchesRule(klass(), rule({ masterId: 555, title: "boxning" })));
    assert.ok(!matchesRule(klass(), rule({ masterId: 556 })));
    assert.ok(!matchesRule(klass(), rule({ title: "yoga" })));
    assert.ok(!matchesRule(klass(), rule({ time: "17:00" })));
    assert.ok(!matchesRule(klass(), rule({ weekday: 3 })));
    assert.ok(!matchesRule(klass({ studio_id: 9 }), rule()));
  });
  it("computes the open moment", () => {
    assert.equal(openTimeMs(klass()), OPEN);
    assert.equal(openTimeMs(klass({ bookable_earliest_time: null })), OPEN);
    assert.equal(openTimeMs(klass({ bookable_earliest_time: null, bookable_earliest: 3 * 86400 })), Date.parse("2026-10-19T16:00:00Z"));
    assert.equal(openTimeMs(klass({ bookable_earliest_time: null, bookable_earliest: null })), null);
    assert.equal(closeTimeMs(klass()), Date.parse("2026-10-22T15:55:00Z"));
  });
  it("builds series keys", () => {
    assert.equal(seriesKey(klass()), "m555|4|18:00");
    assert.equal(seriesKey(klass({ master_id: null })), "s135|boxning för tjejer - nybörjare|4|18:00");
  });
});

function occ(over = {}): Occurrence {
  const c = klass(over);
  return { rule: rule(), cls: c, startMs: Date.parse(c.start_time), openMs: openTimeMs(c), closeMs: closeTimeMs(c) };
}

function entry(over: Partial<Entry>): Entry {
  return { classId: 1001, ruleId: "r1", title: "", studioId: 135, start: "2026-10-22T16:00:00.000Z", status: "pending", updatedAt: "", attempts: 0, ...over };
}

describe("plan", () => {
  const none = new Map<number, Entry | undefined>();
  it("fires when the window opens before the next tick, ~2 s early", () => {
    const now = OPEN - 4 * 60_000;
    const [p] = plan([occ()], none, now, opts());
    assert.equal(p.action, "fire");
    assert.equal(p.fireAtMs, OPEN - 2000);
  });
  it("also takes an open moment exactly at the next tick (slack)", () => {
    assert.equal(plan([occ()], none, OPEN - 300_000, opts())[0].action, "fire");
    assert.equal(plan([occ()], none, OPEN - 300_000 - 61_000, opts())[0].action, "later");
  });
  it("waits for a later tick otherwise", () => {
    const [p] = plan([occ()], none, OPEN - 3_600_000, opts());
    assert.equal(p.action, "later");
  });
  it("catches up on windows that are already open, unless disabled", () => {
    assert.equal(plan([occ()], none, OPEN + 3_600_000, opts())[0].action, "fire");
    assert.equal(plan([occ()], none, OPEN + 3_600_000, opts({ catchUp: false }))[0].action, "ignore");
    assert.equal(plan([occ({ bookable_earliest: null, bookable_earliest_time: null })], none, OPEN, opts())[0].why, "no booking window");
  });
  it("ignores started, closed, booked and in-flight classes", () => {
    assert.equal(plan([occ()], none, Date.parse("2026-10-22T16:00:00Z"), opts())[0].why, "already started");
    assert.equal(plan([occ()], none, Date.parse("2026-10-22T15:56:00Z"), opts())[0].why, "booking closed");
    const now = OPEN - 60_000;
    assert.equal(plan([occ()], new Map([[1001, entry({ status: "booked" })]]), now, opts())[0].action, "ignore");
    assert.equal(plan([occ()], new Map([[1001, entry({ status: "pending", leaseUntil: now + 1 })]]), now, opts())[0].why, "in progress in another run");
    assert.equal(plan([occ()], new Map([[1001, entry({ status: "pending", leaseUntil: now - 1 })]]), now, opts())[0].action, "fire");
  });
});

describe("claimable", () => {
  const o = opts();
  it("retries failed classes a limited number of runs", () => {
    assert.ok(claimable(entry({ status: "failed", attempts: 2 }), 0, o).ok);
    assert.ok(!claimable(entry({ status: "failed", attempts: 3 }), 0, o).ok);
  });
  it("re-books a full class only when a spot is free", () => {
    assert.ok(!claimable(entry({ status: "full" }), 0, o, 0).ok);
    assert.ok(claimable(entry({ status: "full" }), 0, o, 1).ok);
    assert.ok(!claimable(entry({ status: "full" }), 0, opts({ rebookWhenSpotFrees: false }), 1).ok);
    assert.ok(!claimable(entry({ status: "waitlisted" }), 0, o, 1).ok);
  });
});

describe("limits", () => {
  it("blocks on exhausted SIMULTANEOUS / MONTHLY / STUDIO limits and attendance flags", () => {
    const c = klass();
    assert.equal(limitBlock([{ type: "SIMULTANEOUS", total: 3, used: 3, remaining: 0 }], c), "simultaneous bookings limit reached (3/3)");
    assert.equal(limitBlock([{ type: "MONTHLY", total: 20, used: 20, remaining: 0 }], c), "monthly visit limit reached (20/20)");
    assert.equal(limitBlock([{ type: "STUDIO", total: -1, used: 0, remaining: 0 }], c), "this studio is not included in your plan");
    assert.equal(limitBlock([{ type: "STUDIO", total: 0, used: 5, remaining: 0 }], c), undefined); // 0 = unlimited
    assert.equal(limitBlock([{ type: "SIMULTANEOUS", total: 3, used: 1, remaining: 2 }], c), undefined);
    assert.equal(limitBlock([], klass({ user_attendance_info: { booking_limit_reached: true } })), "booking limit reached");
  });
});

describe("stores", () => {
  it("compare-and-set claims a class once", async () => {
    const s = new MemoryStore();
    assert.equal(await s.cas(1, null, entry({})), true);
    assert.equal(await s.cas(1, null, entry({})), false);
    assert.equal(await s.cas(1, 1, entry({ status: "booked" })), true);
    assert.equal(await s.cas(1, 1, entry({})), false);
    assert.equal((await s.get(1))?.entry.status, "booked");
  });
  it("overlay keeps dry-run writes out of the real store", async () => {
    const base = new MemoryStore();
    await base.put(2, entry({ classId: 2, status: "failed" }));
    const o = new OverlayStore(base);
    assert.equal(await o.cas(2, 1, entry({ classId: 2, status: "pending" })), true);
    assert.equal((await o.get(2))?.entry.status, "pending");
    assert.equal((await base.get(2))?.entry.status, "failed");
    await o.setMeta("k", "v");
    assert.equal(await base.getMeta("k"), undefined);
  });
});
