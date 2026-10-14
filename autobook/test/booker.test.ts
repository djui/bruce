import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { AuthError } from "../src/core/api.ts";
import { fireBooking } from "../src/core/booker.ts";
import { collectLog, FakeClock, FakeServer, klass, OPEN, opts } from "./helpers.ts";

function setup(server: Partial<ConstructorParameters<typeof FakeServer>[0]> = {}, start = OPEN - 60_000) {
  const clock = new FakeClock(start);
  const srv = new FakeServer({ clock, classes: [klass()], ...server });
  const { lines, log } = collectLog();
  return { clock, srv, lines, log, api: srv.api() };
}

describe("fireBooking", () => {
  it("waits until open - 2 s, retries the early 4xx and books right after opening", async () => {
    const { clock, srv, api, log } = setup({ book: (_id, at) => (at >= OPEN ? { status: 200 } : { status: 400 }) });
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false });
    assert.equal(out.status, "booked");
    const posts = srv.posts("/v52/booking");
    assert.equal(posts[0].at, OPEN - 2000);
    assert.equal(posts.length, 3); // -2 s, -1 s, 0 s
    assert.equal(posts.at(-1)!.at, OPEN);
    assert.deepEqual(posts[0].body, { class_id: 1001, booked_via: "HOMESCREEN_SPOTLIGHT", include_user: false, locale: "en" });
    assert.equal(posts[0].headers["X-Access-Token"], "test-token");
    assert.equal(posts[0].headers.Authorization, undefined);
  });

  it("detects a full class after opening and joins the waitlist", async () => {
    const full = klass({ available_spots: 0 });
    const { clock, srv, api, log } = setup({ classes: [full], book: () => ({ status: 400 }) });
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: true, dryRun: false });
    assert.equal(out.status, "waitlisted");
    assert.equal(srv.posts("/v52/standby").length, 1);
    // Stopped retrying once the class read showed it full (not the whole 60 s window).
    assert.ok(srv.posts("/v52/booking").length < 10);
  });

  it("reports full without waitlist when not wanted", async () => {
    const { clock, srv, api, log } = setup({ classes: [klass({ available_spots: 0 })], book: () => ({ status: 400 }) });
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false });
    assert.equal(out.status, "full");
    assert.equal(srv.posts("/v52/standby").length, 0);
  });

  it("goes straight to the waitlist when catching up on a class that was already full", async () => {
    const { clock, srv, api, log } = setup({}, OPEN + 3_600_000);
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass({ available_spots: 0 }), openMs: OPEN, waitlistIfFull: true, dryRun: false });
    assert.equal(out.status, "waitlisted");
    assert.equal(srv.posts("/v52/booking").length, 0);
  });

  it("treats a lost response as booked when the booking shows up", async () => {
    let n = 0;
    const { clock, srv, api, log } = setup({
      book: (id, at) => {
        if (at < OPEN) return { status: 400 };
        n++;
        if (n === 1) {
          srv.o.bookings = [id]; // server booked it, but the response never arrived
          return "network-error";
        }
        return { status: 400, body: { errors: [{ code: "validation_error", message: "Already booked", status: "400" }] } };
      },
    });
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false });
    assert.equal(out.status, "booked");
    assert.match(out.detail, /already booked/);
  });

  it("gives up after the retry window", async () => {
    const { clock, srv, api, log } = setup({ book: () => ({ status: 503 }) });
    const out = await fireBooking({ api, clock, log, opts: opts({ retryWindowSeconds: 10 }), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false });
    assert.equal(out.status, "failed");
    assert.match(out.detail, /HTTP 503/);
    assert.ok(clock.now() <= OPEN + 10_000);
    assert.equal(srv.posts("/v52/booking").length, 13); // -2 s .. +10 s, once a second
  });

  it("stops on 401", async () => {
    const { clock, api, log } = setup({ unauthorized: true });
    await assert.rejects(
      fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false }),
      AuthError,
    );
  });

  it("stops when the request budget is used up", async () => {
    const clock = new FakeClock(OPEN - 60_000);
    const srv = new FakeServer({ clock, classes: [klass()], book: () => ({ status: 503 }) });
    const { log } = collectLog();
    const out = await fireBooking({ api: srv.api({ budget: 5 }), clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false });
    assert.equal(out.status, "failed");
    assert.match(out.detail, /budget/);
    assert.equal(srv.calls.length, 5);
  });

  it("dry run waits but sends nothing", async () => {
    const { clock, srv, api, log, lines } = setup();
    const out = await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: true, dryRun: true });
    assert.equal(out.status, "dry-run");
    assert.equal(srv.calls.length, 0);
    assert.equal(clock.now(), OPEN - 2000);
    assert.ok(lines.some((l) => l.includes("DRY RUN")));
  });

  it("corrects for a clearly skewed local clock", async () => {
    // Local clock 5 s behind the server: the server's open moment comes 5 s earlier locally.
    const { clock, srv, api, log } = setup();
    await fireBooking({ api, clock, log, opts: opts(), cls: klass(), openMs: OPEN, waitlistIfFull: false, dryRun: false, skewMs: 5000 });
    assert.equal(srv.posts("/v52/booking")[0].at, OPEN - 5000 - 2000);
  });
});
