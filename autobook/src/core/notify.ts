// Notifications: always a log line; optionally a webhook (ntfy.sh-compatible plain-text POST).
import type { FetchLike } from "./api.ts";

export type NoticeKind = "booked" | "waitlisted" | "full" | "failed" | "skipped" | "auth" | "dry-run" | "error";

export interface Notice {
  kind: NoticeKind;
  title: string;
  message: string;
  classId?: number;
}

export interface Notifier {
  notify(n: Notice): Promise<void>;
}

export type Log = (msg: string) => void;

export const consoleLog: Log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);

export class LogNotifier implements Notifier {
  private readonly log: Log;
  constructor(log: Log) {
    this.log = log;
  }
  async notify(n: Notice) {
    this.log(`NOTIFY [${n.kind}] ${n.title}: ${n.message}`);
  }
}

const PRIORITY: Record<NoticeKind, string> = {
  booked: "default",
  waitlisted: "default",
  "dry-run": "low",
  skipped: "low",
  full: "high",
  failed: "high",
  error: "high",
  auth: "urgent",
};

/**
 * POSTs the message as text/plain with `Title`, `Priority` and `Tags` headers. That is the ntfy.sh
 * publish format (e.g. AUTOBOOK_NOTIFY_URL=https://ntfy.sh/<your-secret-topic>); other webhooks get the
 * same plain-text body. Failures are logged, never thrown.
 */
export class WebhookNotifier implements Notifier {
  private readonly url: string;
  private readonly fetchFn: FetchLike;
  private readonly log: Log;
  constructor(url: string, log: Log, fetchFn: FetchLike = (i, n) => fetch(i, n)) {
    this.url = url;
    this.log = log;
    this.fetchFn = fetchFn;
  }
  async notify(n: Notice) {
    try {
      const res = await this.fetchFn(this.url, {
        method: "POST",
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          // Header values must be ByteStrings: strip non-Latin-1 characters from the title.
          Title: n.title.replace(/[^\x20-\xff]/g, "?"),
          Priority: PRIORITY[n.kind],
          Tags: `bruce,${n.kind}`,
        },
        body: n.message,
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) this.log(`webhook notification failed: HTTP ${res.status}`);
    } catch (e) {
      this.log(`webhook notification failed: ${(e as Error).message}`);
    }
  }
}

export class MultiNotifier implements Notifier {
  private readonly targets: Notifier[];
  constructor(targets: Notifier[]) {
    this.targets = targets;
  }
  async notify(n: Notice) {
    await Promise.all(this.targets.map((t) => t.notify(n)));
  }
}

export function makeNotifier(log: Log, webhookUrl?: string, fetchFn?: FetchLike): Notifier {
  const list: Notifier[] = [new LogNotifier(log)];
  if (webhookUrl) list.push(new WebhookNotifier(webhookUrl, log, fetchFn));
  return new MultiNotifier(list);
}
