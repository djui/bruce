// Minimal Bruce Studios v52 client for auto-booking. Routes, headers and bodies follow API.md and
// Shared/BruceCore/API.swift: auth is the `X-Access-Token` header (no Bearer), there is no token
// refresh, and the server accepts the token until it answers HTTP 401.

export const BASE_URL = "https://api.bruce.app";
export const USER_AGENT = "Bruce/14.4.2_538 (iOS27.0.0; Apple)";

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface AttendanceInfo {
  admission_access?: boolean | null;
  booking_limit_reached?: boolean | null;
  visit_limit_reached?: boolean | null;
  visit_limit_reached_types?: string[] | null;
}

/** The fields of a class object this tool reads (`GET /v52/class`, `include_absolute_times=true`). */
export interface BruceClass {
  id: number;
  studio_id: number;
  title: string | null;
  start_time: string;
  end_time?: string | null;
  time_zone?: string | null;
  master_id?: number | null;
  spots?: number | null;
  available_spots?: number | null;
  canceled?: boolean | null;
  deleted?: boolean | null;
  /** Seconds before start when booking opens; null = no window (bookable as soon as listed). */
  bookable_earliest?: number | null;
  bookable_earliest_time?: string | null;
  /** Seconds before start when booking closes. */
  bookable_latest?: number | null;
  bookable_latest_time?: string | null;
  user_attendance_info?: AttendanceInfo | null;
}

export interface VisitLimit {
  type: string; // STUDIO | MONTHLY | WELLNESS_MONTHLY | SIMULTANEOUS
  total: number | null;
  used: number | null;
  remaining: number | null;
  within_limit?: boolean | null;
}

export interface RawResult {
  status: number;
  body: unknown;
  text: string;
}

/** HTTP 401: the access token is no longer accepted. The user has to log in again. */
export class AuthError extends Error {
  constructor(message = "Bruce rejected the access token (HTTP 401): log in again and update BRUCE_ACCESS_TOKEN") {
    super(message);
    this.name = "AuthError";
  }
}

export class HttpError extends Error {
  status: number;
  body: string;
  constructor(status: number, body: string, what: string) {
    super(`${what}: HTTP ${status}${errorMessage(body) ? ` (${errorMessage(body)})` : ""}`);
    this.name = "HttpError";
    this.status = status;
    this.body = body;
  }
}

/** Thrown when the per-invocation request budget (Cloudflare subrequest limit) is used up. */
export class BudgetError extends Error {
  constructor() {
    super("request budget for this run is used up");
    this.name = "BudgetError";
  }
}

/** First message of an error body `{"errors":[{"code","message","status"}]}`. */
export function errorMessage(body: unknown): string | undefined {
  let b = body;
  if (typeof body === "string") {
    try {
      b = JSON.parse(body);
    } catch {
      return body.trim().slice(0, 200) || undefined;
    }
  }
  const first = (b as { errors?: { message?: string; code?: string }[] } | null)?.errors?.[0];
  const msg = (first?.message ?? first?.code ?? "").trim();
  return msg || undefined;
}

export interface ApiOptions {
  token: string;
  userId: number;
  fetch?: FetchLike;
  baseUrl?: string;
  /** Maximum number of HTTP requests for this client (Cloudflare Workers subrequest limit). */
  budget?: number;
  /** Per-request timeout. */
  timeoutMs?: number;
  now?: () => number;
}

const isoZ = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

export class BruceApi {
  readonly userId: number;
  private readonly token: string;
  private readonly fetchFn: FetchLike;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly now: () => number;
  private budget: number;
  /** Server clock minus local clock, from the last response's `Date` header (±0.5 s resolution). */
  serverSkewMs = 0;
  requests = 0;

  constructor(o: ApiOptions) {
    if (!o.token) throw new Error("BRUCE_ACCESS_TOKEN is not set");
    if (!o.userId) throw new Error("Bruce user id is not set (BRUCE_USER_ID or config user_id)");
    this.token = o.token;
    this.userId = o.userId;
    this.fetchFn = o.fetch ?? ((input, init) => fetch(input, init));
    this.baseUrl = o.baseUrl ?? BASE_URL;
    this.budget = o.budget ?? Infinity;
    this.timeoutMs = o.timeoutMs ?? 10_000;
    this.now = o.now ?? Date.now;
  }

  get remainingBudget(): number {
    return this.budget - this.requests;
  }

  async request(method: string, path: string, query: [string, string][] = [], body?: unknown): Promise<RawResult> {
    if (this.requests >= this.budget) throw new BudgetError();
    this.requests++;
    const qs = query.length ? "?" + query.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&") : "";
    const headers: Record<string, string> = {
      Accept: "application/json",
      "Accept-Language": "en-US",
      "User-Agent": USER_AGENT,
      "X-Access-Token": this.token,
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    const t0 = this.now();
    const res = await this.fetchFn(`${this.baseUrl}${path}${qs}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    const t1 = this.now();
    const date = res.headers.get("date");
    if (date) {
      const server = Date.parse(date);
      if (!Number.isNaN(server)) this.serverSkewMs = server + 500 - (t0 + t1) / 2;
    }
    const text = await res.text();
    let parsed: unknown = undefined;
    try {
      parsed = text ? JSON.parse(text) : undefined;
    } catch {
      parsed = text;
    }
    if (res.status === 401) throw new AuthError();
    return { status: res.status, body: parsed, text };
  }

  private async get<T>(path: string, query: [string, string][], what: string): Promise<T> {
    const r = await this.request("GET", path, query);
    if (r.status < 200 || r.status >= 300) throw new HttpError(r.status, r.text, what);
    return r.body as T;
  }

  /**
   * Classes of one studio starting in [fromMs, toMs), like the official app's per-studio query
   * (UTC range, studio_id + presentation_studio_id). Deliberately WITHOUT `bookable_earliest_before`,
   * which would hide classes whose booking window has not opened yet.
   */
  async listClasses(studioId: number, fromMs: number, toMs: number, maxPages = 5): Promise<BruceClass[]> {
    const out: BruceClass[] = [];
    let cursor: string | undefined;
    for (let page = 0; page < maxPages; page++) {
      const q: [string, string][] = [
        ["studio_id", String(studioId)],
        ["presentation_studio_id", String(studioId)],
        ["start_time_after", isoZ(fromMs)],
        ["start_time_before", isoZ(toMs)],
        ["limit", "30"],
        ["is_recurring_base", "false"],
        ["is_master", "false"],
        ["dedicated", "false"],
        ["opening", "false"],
        ["deleted", "false"],
        ["include_absolute_times", "true"],
        ["include_studio_user_attendance_info", "true"],
        ["locale", "en"],
      ];
      if (cursor) q.push(["next_cursor", cursor]);
      const r = await this.get<{ classes?: BruceClass[]; metadata?: { pagination?: { next_cursor?: string | null } } }>(
        "/v52/class",
        q,
        `list classes of studio ${studioId}`,
      );
      const classes = r.classes ?? [];
      out.push(...classes);
      const next = r.metadata?.pagination?.next_cursor;
      if (!next || classes.length === 0) break;
      cursor = next;
    }
    return out;
  }

  async getClass(classId: number): Promise<BruceClass> {
    const r = await this.get<{ class: BruceClass }>(
      `/v52/class/${classId}`,
      [
        ["include_absolute_times", "true"],
        ["include_studio_user_attendance_info", "true"],
        ["locale", "en"],
      ],
      `read class ${classId}`,
    );
    return r.class;
  }

  /** Class ids of the user's non-deleted bookings for classes starting after `sinceMs`. */
  async bookedClassIds(sinceMs: number, maxPages = 10): Promise<Set<number>> {
    const ids = new Set<number>();
    let cursor: string | undefined;
    for (let page = 0; page < maxPages; page++) {
      const q: [string, string][] = [
        ["user_id", String(this.userId)],
        ["limit", "30"],
        ["deleted", "false"],
        ["class_start_time_after", isoZ(sinceMs)],
        ["locale", "en"],
      ];
      if (cursor) q.push(["next_cursor", cursor]);
      const r = await this.get<{
        bookings?: { class_id?: number | null; deleted?: boolean | null; cancelled?: boolean | null }[];
        metadata?: { pagination?: { next_cursor?: string | null } };
      }>("/v52/booking", q, "list bookings");
      const list = r.bookings ?? [];
      for (const b of list) if (b.class_id && !b.deleted && !b.cancelled) ids.add(b.class_id);
      const next = r.metadata?.pagination?.next_cursor;
      if (!next || list.length === 0) break;
      cursor = next;
    }
    return ids;
  }

  /** Class ids the user is on the waitlist for. */
  async standbyClassIds(sinceMs: number): Promise<Set<number>> {
    const r = await this.get<{ standbys?: { class_id?: number | null; deleted?: boolean | null }[] }>(
      "/v52/standby",
      [
        ["user_id", String(this.userId)],
        ["class_start_time_after", isoZ(sinceMs)],
        ["deleted", "false"],
        ["locale", "en"],
      ],
      "list waitlist",
    );
    return new Set((r.standbys ?? []).filter((s) => s.class_id && !s.deleted).map((s) => s.class_id as number));
  }

  /** `GET /v52/studio/user_visit_limit?studio_id=&month=YYYYMM`: STUDIO, MONTHLY, WELLNESS_MONTHLY, SIMULTANEOUS. */
  async visitLimits(studioId: number, month: string): Promise<VisitLimit[]> {
    const r = await this.get<{ limits?: VisitLimit[] }>(
      "/v52/studio/user_visit_limit",
      [
        ["user_id", String(this.userId)],
        ["studio_id", String(studioId)],
        ["month", month],
        ["locale", "en"],
      ],
      `read visit limits for studio ${studioId}`,
    );
    return r.limits ?? [];
  }

  /** `POST /v52/booking`. Returns the raw result (no throw on 4xx/5xx) except 401 -> AuthError. */
  book(classId: number): Promise<RawResult> {
    return this.request("POST", "/v52/booking", [], {
      class_id: classId,
      booked_via: "HOMESCREEN_SPOTLIGHT",
      include_user: false,
      locale: "en",
    });
  }

  /** `POST /v52/standby` (join the waitlist). */
  joinWaitlist(classId: number): Promise<RawResult> {
    return this.request("POST", "/v52/standby", [], { class_id: classId, locale: "en" });
  }
}

/** `POST /v52/access/authenticate` (no token). Used only by the `login` helper command. */
export async function authenticate(email: string, password: string, fetchFn: FetchLike = (i, n) => fetch(i, n)) {
  const res = await fetchFn(`${BASE_URL}/v52/access/authenticate`, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json", "User-Agent": USER_AGENT },
    body: JSON.stringify({ authenticator: "PASSWORD", email, password, locale: "en" }),
  });
  const text = await res.text();
  if (!res.ok) throw new HttpError(res.status, text, "log in");
  const j = JSON.parse(text) as { user_id: number; access_token: string };
  return { userId: j.user_id, accessToken: j.access_token };
}
