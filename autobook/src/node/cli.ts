#!/usr/bin/env node
// Node entry point for the VPS / Fly.io service (`run`) and the macOS launchd job (`tick`).
// Needs Node >= 22.18 (runs the TypeScript sources directly, no build step).
import { existsSync, readFileSync } from "node:fs";
import { createInterface } from "node:readline";
import { parseArgs } from "node:util";
import { authenticate, BruceApi } from "../core/api.ts";
import { systemClock } from "../core/clock.ts";
import { parseConfig, type Config } from "../core/config.ts";
import { consoleLog, makeNotifier } from "../core/notify.ts";
import { seriesKey, openTimeMs } from "../core/rules.ts";
import { OverlayStore, type Store } from "../core/store.ts";
import { plan, runTick, scan, tokenFingerprint, type TickDeps } from "../core/tick.ts";
import { formatLocal, localParts } from "../core/time.ts";
import { FileStore } from "./file-store.ts";

const USAGE = `Usage: autobook <command> [options]

Commands:
  run       Long-running service: one tick every tick_seconds (default 300 s). For a VPS / Fly.io.
  tick      Run one tick (incl. waiting for and firing imminent bookings), then exit. For launchd/cron.
  plan      Show what the next tick would do. Sends no booking, waits for nothing.
  classes   List a studio's upcoming classes, to write rules:  classes --studio <id> [--days 14]
  login     Log in with email and password and print BRUCE_ACCESS_TOKEN / BRUCE_USER_ID.

Options:
  --config <file>   Rules file (default: $AUTOBOOK_CONFIG_FILE or ./autobook.config.json).
                    $AUTOBOOK_CONFIG may instead hold the JSON itself.
  --state <file>    State file (default: $AUTOBOOK_STATE or ./state/autobook-state.json).
  --dry-run         Do everything except POST /v52/booking and /v52/standby; no state is written.

Environment:
  BRUCE_ACCESS_TOKEN   Access token (required). Never commit it.
  BRUCE_USER_ID        Your Bruce user id (or "user_id" in the config).
  AUTOBOOK_NOTIFY_URL  Optional webhook for notifications, e.g. https://ntfy.sh/<secret-topic>.
  AUTOBOOK_DRY_RUN=1   Same as --dry-run.
`;

function loadConfig(path?: string): Config {
  if (!path && process.env.AUTOBOOK_CONFIG?.trim().startsWith("{")) {
    return parseConfig(JSON.parse(process.env.AUTOBOOK_CONFIG));
  }
  const file = path ?? process.env.AUTOBOOK_CONFIG_FILE ?? "autobook.config.json";
  if (!existsSync(file)) throw new Error(`config file ${file} not found (copy autobook.config.example.json)`);
  try {
    return parseConfig(JSON.parse(readFileSync(file, "utf8")));
  } catch (e) {
    throw new Error(`${file}: ${(e as Error).message}`);
  }
}

function makeApi(config: Config): BruceApi {
  const userId = Number(process.env.BRUCE_USER_ID ?? config.userId ?? 0);
  return new BruceApi({ token: process.env.BRUCE_ACCESS_TOKEN ?? "", userId });
}

async function makeDeps(values: { config?: string; state?: string; "dry-run"?: boolean }): Promise<TickDeps> {
  const config = loadConfig(values.config);
  const dryRun = values["dry-run"] === true || /^(1|true|yes)$/i.test(process.env.AUTOBOOK_DRY_RUN ?? "");
  const fileStore: Store = new FileStore(values.state ?? process.env.AUTOBOOK_STATE ?? "state/autobook-state.json");
  const api = makeApi(config);
  return {
    api,
    store: dryRun ? new OverlayStore(fileStore) : fileStore,
    notifier: makeNotifier(consoleLog, process.env.AUTOBOOK_NOTIFY_URL || undefined),
    clock: systemClock,
    config,
    log: consoleLog,
    dryRun,
    tokenFingerprint: await tokenFingerprint(process.env.BRUCE_ACCESS_TOKEN ?? ""),
  };
}

async function cmdTick(deps: TickDeps): Promise<number> {
  if (deps.dryRun) deps.log("DRY RUN: no booking or waitlist request will be sent");
  const r = await runTick(deps);
  const results = await r.done;
  return r.authFailed || results.some((x) => x.outcome.status === "auth") ? 2 : 0;
}

async function cmdRun(deps: TickDeps): Promise<never> {
  const intervalMs = deps.config.options.tickSeconds * 1000;
  deps.log(`autobook service started: ${deps.config.rules.filter((r) => r.enabled).length} rule(s), tick every ${intervalMs / 1000} s${deps.dryRun ? ", DRY RUN" : ""}`);
  let stopping = false;
  for (const sig of ["SIGINT", "SIGTERM"] as const) {
    process.on(sig, () => {
      deps.log(`${sig}: stopping (an in-flight booking keeps its lease and is retried by the next run if needed)`);
      stopping = true;
      process.exit(0);
    });
  }
  for (;;) {
    try {
      const r = await runTick(deps);
      // Bookings fire in the background; the next tick is not delayed by them.
      r.done.catch((e) => deps.log(`ERROR in booking: ${(e as Error).stack ?? e}`));
    } catch (e) {
      deps.log(`ERROR in tick: ${(e as Error).message}`);
    }
    if (stopping) break;
    // Align ticks to the wall clock (…:00, :05, …) for readable logs; the planner does not depend on it.
    const now = Date.now();
    await new Promise((res) => setTimeout(res, Math.ceil((now + 1000) / intervalMs) * intervalMs - now));
  }
  process.exit(0);
}

async function cmdPlan(deps: TickDeps): Promise<number> {
  const now = Date.now();
  const { occurrences, warnings } = await scan(deps.api, deps.config.rules, now, deps.config.options);
  for (const w of warnings) console.log(`WARNING ${w}`);
  const entries = new Map();
  for (const o of occurrences) entries.set(o.cls.id, (await deps.store.get(o.cls.id))?.entry);
  const items = plan(occurrences, entries, now, deps.config.options);
  if (items.length === 0) console.log("No matching classes listed yet (classes are listed about 14 days ahead).");
  for (const it of items) {
    const e = entries.get(it.occ.cls.id);
    console.log(
      [
        it.action.padEnd(6),
        formatLocal(it.occ.startMs),
        `class ${it.occ.cls.id}`,
        JSON.stringify(it.occ.cls.title),
        `spots ${it.occ.cls.available_spots ?? "?"}/${it.occ.cls.spots ?? "?"}`,
        it.why,
        e ? `[state: ${e.status}${e.reason ? `: ${e.reason}` : ""}]` : "",
      ].join("  "),
    );
  }
  return 0;
}

async function cmdClasses(deps: TickDeps, studio: string | undefined, days: string | undefined): Promise<number> {
  const studioId = Number(studio);
  if (!studioId) throw new Error("--studio <id> is required");
  const now = Date.now();
  const classes = await deps.api.listClasses(studioId, now, now + Number(days ?? 14) * 86_400_000, 20);
  const wd = ["", "mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  for (const c of classes.filter((c) => !c.deleted && !c.canceled)) {
    const start = Date.parse(c.start_time);
    const open = openTimeMs(c);
    console.log(
      [
        formatLocal(start),
        `weekday ${wd[localParts(start).weekday]}`,
        `class ${c.id}`,
        `master_id ${c.master_id ?? "null"}`,
        JSON.stringify(c.title),
        `spots ${c.available_spots ?? "?"}/${c.spots ?? "?"}`,
        open == null ? "no booking window" : `opens ${formatLocal(open)}`,
        `series ${seriesKey(c)}`,
      ].join("  "),
    );
  }
  return 0;
}

function ask(question: string, hidden = false): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
  if (hidden) {
    const r = rl as unknown as { _writeToOutput: (s: string) => void };
    r._writeToOutput = (s: string) => {
      if (s.startsWith(question)) process.stdout.write(question);
    };
  }
  return new Promise((resolve) =>
    rl.question(question, (a) => {
      rl.close();
      if (hidden) process.stdout.write("\n");
      resolve(a.trim());
    }),
  );
}

async function cmdLogin(): Promise<number> {
  const email = await ask("Bruce email: ");
  const password = await ask("Password (not stored): ", true);
  const r = await authenticate(email, password);
  console.error("Logged in. Store these as secrets (never commit them):");
  console.log(`BRUCE_ACCESS_TOKEN=${r.accessToken}`);
  console.log(`BRUCE_USER_ID=${r.userId}`);
  return 0;
}

async function main(argv: string[]): Promise<number> {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      config: { type: "string" },
      state: { type: "string" },
      "dry-run": { type: "boolean" },
      studio: { type: "string" },
      days: { type: "string" },
      help: { type: "boolean", short: "h" },
    },
  });
  const cmd = positionals[0];
  if (values.help || !cmd) {
    console.log(USAGE);
    return cmd ? 0 : 1;
  }
  switch (cmd) {
    case "login":
      return cmdLogin();
    case "tick":
      return cmdTick(await makeDeps(values));
    case "run":
      return cmdRun(await makeDeps(values));
    case "plan":
      return cmdPlan(await makeDeps({ ...values, "dry-run": true }));
    case "classes":
      return cmdClasses(await makeDeps({ ...values, "dry-run": true }), values.studio, values.days);
    default:
      console.error(`unknown command "${cmd}"\n\n${USAGE}`);
      return 1;
  }
}

main(process.argv.slice(2)).then(
  (code) => process.exit(code),
  (e) => {
    consoleLog(`ERROR ${(e as Error).message}`);
    process.exit(1);
  },
);
