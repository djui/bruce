// Cloudflare Worker entry point. A Cron Trigger (`*/5 * * * *`) runs one tick. A tick that finds a
// window opening before the next tick waits inside the same invocation until ~2 s before the open
// moment and then fires: scheduled handlers may run up to 15 minutes of wall time, and waiting does
// not use CPU time. See README.md ("Cloudflare Worker") for the limits this relies on.
import { BruceApi } from "../core/api.ts";
import { systemClock } from "../core/clock.ts";
import { parseConfig } from "../core/config.ts";
import { makeNotifier, type Log } from "../core/notify.ts";
import { OverlayStore } from "../core/store.ts";
import { runTick, tokenFingerprint } from "../core/tick.ts";
import { D1Store, type D1Database } from "./d1-store.ts";

export interface Env {
  DB: D1Database;
  /** Secret: `wrangler secret put BRUCE_ACCESS_TOKEN`. */
  BRUCE_ACCESS_TOKEN: string;
  BRUCE_USER_ID?: string;
  /** The rules file as JSON (a var in wrangler.toml, or a secret). */
  AUTOBOOK_CONFIG: string;
  /** Secret, optional: e.g. https://ntfy.sh/<secret-topic>. */
  AUTOBOOK_NOTIFY_URL?: string;
  AUTOBOOK_DRY_RUN?: string;
  /** Max Bruce API requests per invocation. Free plan: 50 subrequests in total, so the default is 40. */
  AUTOBOOK_SUBREQUEST_BUDGET?: string;
}

interface ScheduledController {
  scheduledTime: number;
  cron: string;
}
interface ExecutionContext {
  waitUntil(p: Promise<unknown>): void;
}

const log: Log = (msg) => console.log(msg);

export async function scheduledTick(env: Env): Promise<void> {
  const config = parseConfig(JSON.parse(env.AUTOBOOK_CONFIG));
  const dryRun = /^(1|true|yes)$/i.test(env.AUTOBOOK_DRY_RUN ?? "");
  const api = new BruceApi({
    token: env.BRUCE_ACCESS_TOKEN,
    userId: Number(env.BRUCE_USER_ID ?? config.userId ?? 0),
    budget: Number(env.AUTOBOOK_SUBREQUEST_BUDGET ?? 40),
  });
  const d1 = new D1Store(env.DB);
  const r = await runTick({
    api,
    store: dryRun ? new OverlayStore(d1) : d1,
    notifier: makeNotifier(log, env.AUTOBOOK_NOTIFY_URL || undefined),
    clock: systemClock,
    config,
    log,
    dryRun,
    tokenFingerprint: await tokenFingerprint(env.BRUCE_ACCESS_TOKEN ?? ""),
  });
  await r.done;
}

export default {
  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(scheduledTick(env).catch((e) => log(`ERROR ${(e as Error).stack ?? e}`)));
  },
  // No public HTTP surface: the schedule and state are private.
  async fetch(): Promise<Response> {
    return new Response("Not found\n", { status: 404 });
  },
};
