import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Config } from "../src/core/config.ts";
import type { Notice, Notifier } from "../src/core/notify.ts";
import { MemoryStore, OverlayStore, type Store } from "../src/core/store.ts";
import { runTick, tokenFingerprint, type TickDeps } from "../src/core/tick.ts";
import { collectLog, FakeClock, FakeServer, klass, OPEN, opts, rule } from "./helpers.ts";

class Recorder implements Notifier {
  notices: Notice[] = [];
  async notify(n: Notice) {
    this.notices.push(n);
  }
}

async function deps(srv: FakeServer, clock: FakeClock, over: Partial<TickDeps> = {}, config?: Partial<Config>) {
  const { log, lines } = collectLog();
  const notifier = new Recorder();
  const store: Store = over.store ?? new MemoryStore();
  const d: TickDeps = {
    api: srv.api(),
    store,
    notifier,
    clock,
    config: { rules: [rule({ waitlistIfFull: true })], options: opts(), ...config },
    log,
    dryRun: false,
    tokenFingerprint: await tokenFingerprint("test-token"),
    ...over,
  };
  return { d, notifier, lines, store };
}

describe("runTick", () => {
  it("does nothing but scan when no window opens before the next tick", async () => {
    const clock = new FakeClock(OPEN - 3_600_000);
    const srv = new FakeServer({ clock, classes: [klass()] });
    const { d } = await deps(srv, clock);
    const r = await runTick(d);
    assert.deepEqual(r.items.map((i) => i.action), ["later"]);
    assert.deepEqual(await r.done, []);
    assert.ok(srv.calls.every((c) => c.method === "GET" && c.path === "/v52/class"));
    // Never the app's `bookable_earliest_before`, which hides not-yet-open classes.
    assert.ok(srv.calls.every((c) => !c.query.has("bookable_earliest_before")));
  });

  it("books an imminent class once, records it, and the next tick leaves it alone", async () => {
    const clock = new FakeClock(OPEN - 240_000);
    const srv = new FakeServer({ clock, classes: [klass()], book: (_id, at) => (at >= OPEN ? { status: 200 } : { status: 400 }) });
    const { d, notifier, store } = await deps(srv, clock);
    const r = await runTick(d);
    assert.deepEqual(r.items.map((i) => i.action), ["fire"]);
    const res = await r.done;
    assert.equal(res[0].outcome.status, "booked");
    assert.equal((await store.get(1001))?.entry.status, "booked");
    assert.deepEqual(notifier.notices.map((n) => n.kind), ["booked"]);

    const posts = srv.posts("/v52/booking").length;
    clock.t += 300_000;
    const r2 = await runTick(d);
    assert.equal(r2.items[0].action, "ignore");
    await r2.done;
    assert.equal(srv.posts("/v52/booking").length, posts);
  });

  it("an overlapping run does not fire a class another run has claimed", async () => {
    const clock = new FakeClock(OPEN - 240_000);
    // Run A's wait for the open moment blocks until released, so run B starts while A holds the lease.
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const blocking = { now: () => clock.now(), sleep: async (ms: number) => { await gate; await clock.sleep(ms); } };
    const srv = new FakeServer({ clock, classes: [klass()] });
    const store = new MemoryStore();
    const a = await deps(srv, clock, { store, clock: blocking });
    const b = await deps(srv, clock, { store });
    const ra = await runTick(a.d); // claims, then waits for the open moment
    const rb = await runTick(b.d);
    release();
    assert.equal(rb.items[0].action, "ignore");
    assert.equal(rb.items[0].why, "in progress in another run");
    await Promise.all([ra.done, rb.done]);
    assert.equal(srv.posts("/v52/booking").length, 1);
  });

  it("skips a class you already booked yourself", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()], bookings: [1001] });
    const { d, store } = await deps(srv, clock);
    await (await runTick(d)).done;
    assert.equal(srv.posts("/v52/booking").length, 0);
    assert.equal((await store.get(1001))?.entry.status, "booked");
  });

  it("skips with a reason when the SIMULTANEOUS limit is used up, and notifies once", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()], limits: [{ type: "SIMULTANEOUS", total: 3, used: 3, remaining: 0 }] });
    const { d, notifier, store } = await deps(srv, clock);
    await (await runTick(d)).done;
    assert.equal(srv.posts("/v52/booking").length, 0);
    const e = (await store.get(1001))?.entry;
    assert.equal(e?.status, "skipped");
    assert.match(e?.reason ?? "", /simultaneous/);
    clock.t += 300_000; // catch-up re-checks on the next tick, but does not notify again
    await (await runTick(d)).done;
    assert.equal(notifier.notices.filter((n) => n.kind === "skipped").length, 1);
  });

  it("asks the month of the class for limits", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()] });
    const { d } = await deps(srv, clock);
    await (await runTick(d)).done;
    const call = srv.calls.find((c) => c.path === "/v52/studio/user_visit_limit");
    assert.equal(call?.query.get("month"), "202610");
    assert.equal(call?.query.get("studio_id"), "135");
  });

  it("warns and skips when a rule matches several classes", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass(), klass({ id: 1002, title: "Yoga", master_id: 777 })] });
    const { d, lines } = await deps(srv, clock);
    const r = await runTick(d);
    await r.done;
    assert.equal(r.items.length, 0);
    assert.equal(r.warnings.length, 1);
    assert.ok(lines.some((l) => l.includes('add "title" or "master_id"')));
    assert.equal(srv.posts("/v52/booking").length, 0);
  });

  it("on 401 notifies once and stops calling the API until the token changes", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()], unauthorized: true });
    const { d, notifier } = await deps(srv, clock);
    const r = await runTick(d);
    assert.equal(r.authFailed, true);
    assert.deepEqual(notifier.notices.map((n) => n.kind), ["auth"]);
    assert.match(notifier.notices[0].message, /log in again/);
    const calls = srv.calls.length;
    const r2 = await runTick(d);
    assert.equal(r2.authFailed, true);
    assert.equal(srv.calls.length, calls);
    assert.equal(notifier.notices.length, 1);
    // A new token is tried again.
    srv.o.unauthorized = false;
    const r3 = await runTick({ ...d, tokenFingerprint: await tokenFingerprint("new-token") });
    await r3.done;
    assert.equal(r3.authFailed, false);
  });

  it("dry run sends no POST and leaves the real store untouched", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()] });
    const base = new MemoryStore();
    const { d, notifier } = await deps(srv, clock, { store: new OverlayStore(base), dryRun: true });
    await (await runTick(d)).done;
    assert.equal(srv.calls.filter((c) => c.method !== "GET").length, 0);
    assert.equal(base.entries.size, 0);
    assert.deepEqual(notifier.notices.map((n) => n.kind), ["dry-run"]);
  });

  it("re-books a class that was full once a spot frees up", async () => {
    const clock = new FakeClock(OPEN + 3_600_000);
    const srv = new FakeServer({ clock, classes: [klass({ available_spots: 1 })] });
    const store = new MemoryStore();
    await store.put(1001, { classId: 1001, ruleId: "r1", title: "", studioId: 135, start: "2026-10-22T16:00:00.000Z", status: "full", updatedAt: "", attempts: 0 });
    const { d } = await deps(srv, clock, { store }, { rules: [rule()] });
    const r = await runTick(d);
    assert.equal((await r.done)[0].outcome.status, "booked");
  });
});
