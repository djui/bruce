// Test doubles: a virtual clock and an in-memory fake of the Bruce endpoints. No real network.
import { BruceApi, type BruceClass, type VisitLimit } from "../src/core/api.ts";
import type { Clock } from "../src/core/clock.ts";
import { DEFAULT_OPTIONS, type Options, type Rule } from "../src/core/config.ts";

export class FakeClock implements Clock {
  t: number;
  sleeps: number[] = [];
  constructor(t: number) {
    this.t = t;
  }
  now() {
    return this.t;
  }
  async sleep(ms: number) {
    this.sleeps.push(ms);
    this.t += Math.max(0, ms);
    await Promise.resolve();
  }
}

export interface Call {
  method: string;
  path: string;
  query: URLSearchParams;
  body?: unknown;
  at: number;
  headers: Record<string, string>;
}

export interface FakeServerOptions {
  clock: FakeClock;
  classes?: BruceClass[];
  bookings?: number[];
  standbys?: number[];
  limits?: VisitLimit[];
  /** Status for POST /v52/booking, by call time. Default: 400 before open, 200 after. */
  book?: (classId: number, at: number) => { status: number; body?: unknown } | "network-error";
  standbyStatus?: number;
  /** Answer every request with 401. */
  unauthorized?: boolean;
  serverDateOffsetMs?: number;
}

export class FakeServer {
  calls: Call[] = [];
  o: FakeServerOptions;
  constructor(o: FakeServerOptions) {
    this.o = o;
  }

  posts(path: string) {
    return this.calls.filter((c) => c.method === "POST" && c.path === path);
  }

  fetch = async (input: string, init?: RequestInit): Promise<Response> => {
    const url = new URL(input);
    const method = init?.method ?? "GET";
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined;
    const headers = Object.fromEntries(Object.entries((init?.headers ?? {}) as Record<string, string>));
    const at = this.o.clock.now();
    this.calls.push({ method, path: url.pathname, query: url.searchParams, body, at, headers });
    const date = new Date(at + (this.o.serverDateOffsetMs ?? 0)).toUTCString();
    const json = (status: number, b: unknown) =>
      new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json", date } });
    if (this.o.unauthorized) return json(401, { errors: [{ code: "unauthorized", message: "Unauthorized", status: "401" }] });

    if (method === "GET" && url.pathname === "/v52/class") {
      const sid = Number(url.searchParams.get("studio_id"));
      const after = Date.parse(url.searchParams.get("start_time_after")!);
      const before = Date.parse(url.searchParams.get("start_time_before")!);
      const classes = (this.o.classes ?? []).filter((c) => {
        const s = Date.parse(c.start_time);
        return c.studio_id === sid && s >= after && s < before;
      });
      return json(200, { classes, metadata: { pagination: { next_cursor: null } } });
    }
    const m = /^\/v52\/class\/(\d+)$/.exec(url.pathname);
    if (method === "GET" && m) {
      const c = (this.o.classes ?? []).find((x) => x.id === Number(m[1]));
      return c ? json(200, { class: c }) : json(404, { errors: [{ code: "not_found", message: "Not found", status: "404" }] });
    }
    if (method === "GET" && url.pathname === "/v52/booking") {
      return json(200, { bookings: (this.o.bookings ?? []).map((id, i) => ({ id: 900 + i, class_id: id, deleted: false })), metadata: { pagination: { next_cursor: null } } });
    }
    if (method === "GET" && url.pathname === "/v52/standby") {
      return json(200, { standbys: (this.o.standbys ?? []).map((id, i) => ({ id: 700 + i, class_id: id })), metadata: {} });
    }
    if (method === "GET" && url.pathname === "/v52/studio/user_visit_limit") {
      return json(200, { limits: this.o.limits ?? [] });
    }
    if (method === "POST" && url.pathname === "/v52/booking") {
      const cid = (body as { class_id: number }).class_id;
      const r = this.o.book ? this.o.book(cid, at) : { status: 200 };
      if (r === "network-error") throw new TypeError("fetch failed");
      if (r.status >= 200 && r.status < 300) {
        (this.o.bookings ??= []).push(cid);
        return json(r.status, r.body ?? { booking: { id: 4242, class_id: cid } });
      }
      return json(r.status, r.body ?? { errors: [{ code: "validation_error", message: "Booking not open", status: String(r.status) }] });
    }
    if (method === "POST" && url.pathname === "/v52/standby") {
      const cid = (body as { class_id: number }).class_id;
      const st = this.o.standbyStatus ?? 200;
      if (st === 200) (this.o.standbys ??= []).push(cid);
      return json(st, st === 200 ? { standby: { id: 77, class_id: cid } } : { errors: [{ code: "validation_error", message: "nope", status: String(st) }] });
    }
    return json(404, { errors: [{ code: "not_found", message: `no route ${method} ${url.pathname}`, status: "404" }] });
  };

  api(extra: { budget?: number } = {}) {
    return new BruceApi({ token: "test-token", userId: 1, fetch: this.fetch, now: () => this.o.clock.now(), ...extra });
  }
}

export function opts(over: Partial<Options> = {}): Options {
  return { ...DEFAULT_OPTIONS, ...over };
}

export function rule(over: Partial<Rule> = {}): Rule {
  return { id: "r1", studioId: 135, weekday: 4, time: "18:00", waitlistIfFull: false, enabled: true, ...over };
}

/** A class at studio 135, Thursday 2026-10-22 18:00 Stockholm (16:00Z), opening 7 days before. */
export function klass(over: Partial<BruceClass> = {}): BruceClass {
  return {
    id: 1001,
    studio_id: 135,
    title: "Boxning För Tjejer - Nybörjare",
    start_time: "2026-10-22T16:00:00Z",
    end_time: "2026-10-22T17:00:00Z",
    time_zone: "Europe/Stockholm",
    master_id: 555,
    spots: 6,
    available_spots: 6,
    canceled: false,
    deleted: false,
    bookable_earliest: 604800,
    bookable_earliest_time: "2026-10-15T16:00:00Z",
    bookable_latest: 300,
    bookable_latest_time: "2026-10-22T15:55:00Z",
    user_attendance_info: { admission_access: true, booking_limit_reached: false, visit_limit_reached: false },
    ...over,
  };
}

export const OPEN = Date.parse("2026-10-15T16:00:00Z");

export function collectLog() {
  const lines: string[] = [];
  return { lines, log: (m: string) => void lines.push(m) };
}
