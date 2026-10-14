# autobook: book weekly Bruce classes the moment booking opens

A small server-side scanner that books your weekly Bruce Studios classes as soon as their booking
window opens. Small classes fill within hours, so the first booking request goes out about 2 seconds
before the window opens and is retried about once a second.

One TypeScript code base, three ways to run it:

| Target | Entry point | Scheduler | State |
|---|---|---|---|
| **(a) VPS / Fly.io service** | `src/node/cli.ts run` | in-process loop, one tick every 5 min | JSON file |
| **(b) Cloudflare Worker** | `src/worker/worker.ts` | Cron Trigger `*/5 * * * *` | D1 (SQLite) |
| **(c) macOS launchd job** | `src/node/cli.ts tick` | launchd `StartInterval` 300 | JSON file |

No runtime dependencies. Node ≥ 22.18 runs the `.ts` sources directly (type stripping), and
Wrangler bundles the same files for the Worker. `typescript` and `@types/node` are dev-only.

> [!IMPORTANT]
> Unofficial and not endorsed by Bruce Studios. Bookings made by this tool are real bookings: they count
> against your limits, and late cancellations and no-shows count as usual. Use it only with your own
> account and only for classes you will attend. See [Responsible use](#responsible-use).

## How it works

Booking for a class opens at `start_time - bookable_earliest` seconds (`bookable_earliest_time` in the
class payload). For about 97% of classes that is 7 days before the start, at the class's own start
time; some studios use 3, 4, 5, 6, 10 or 14 days, and `null` means there is no window. Classes are listed
about 14 days ahead, before their window opens, so the scanner can see the open moment in advance.

Every **tick** (every 5 minutes):

1. For each rule it computes the next dates of the rule's weekly slot (weekday + `HH:MM`,
   Europe/Stockholm, DST-aware) up to 15 days ahead and asks `GET /v52/class` for that studio within
   ±1 minute of each start. The query does **not** send the app's `bookable_earliest_before=<now>`
   filter, which would hide classes whose window has not opened yet. Classes must match the studio,
   weekday and local time, plus `master_id` and/or a title substring if the rule has them. If several
   classes match, nothing is booked and a warning asks you to add `title` or `master_id`.
2. For each occurrence it reads the open moment, then decides:
   - **fire**: the window opens before the next tick (now + 5 min + 60 s slack), or is already open
     and `catch_up` is on;
   - **later**: it opens after the next tick, so a later tick handles it;
   - **ignore**: already booked or on the waitlist (by autobook or by you), handled by another run,
     started, or past "Book until".
3. Only when something is about to fire, it reads your bookings and waitlist and
   `GET /v52/studio/user_visit_limit` for the class's studio and month. It skips the class, with a
   reason, if you already booked it, or if the `SIMULTANEOUS`, `MONTHLY` or `STUDIO` limit is used up
   (or the class says `booking_limit_reached` / `visit_limit_reached`).
4. It **claims** the class in the state store (compare-and-set with a lease), so overlapping runs never
   book it twice. Then it **waits inside the same tick** until `open − 2 s` and fires
   `POST /v52/booking`, retrying every second for up to 60 s after the open moment:
   - 2xx: booked;
   - 4xx before `open + 3 s`: "not open yet", retried (the exact "too early" error was never
     captured, so every early 4xx counts as retryable);
   - 4xx after that: the class and your bookings are re-read (first time, then every 5th failure).
     Already booked means success (e.g. a lost response), full means stop, then join the waitlist with
     `POST /v52/standby` if `waitlist_if_full` is set, and cancelled or over a limit means stop;
   - 5xx, 429 and network errors: retried (429 waits 3 s);
   - **401: stop everything** and notify "log in again". The tool remembers which token failed and
     makes no more calls until `BRUCE_ACCESS_TOKEN` changes.
5. The outcome (`booked`, `waitlisted`, `full`, `failed`, `skipped`) is stored per class id and sent
   as a notification. A `failed` class is retried by up to 3 runs; a `full` class is retried when a
   later scan sees a free spot (`rebook_when_spot_frees`).

So the API sees one small scan per rule every 5 minutes. Requests per second only happen in the
minute around an open moment, and only for your own rules.

**Clock:** the first request is timed with the local clock. Each API response's `Date` header gives the
server's clock (to ±0.5 s); if the two differ by more than 2 s, the fire time is corrected. Keep NTP on.

## Rules (config)

Copy `autobook.config.example.json` to `autobook.config.json` (git-ignored) and edit it:

```json
{
  "rules": [
    { "name": "Thursday boxing", "studio_id": 135, "title": "Boxning", "weekday": "thu", "time": "18:00", "waitlist_if_full": true },
    { "name": "Sunday series", "studio_id": 6614, "master_id": 1234567, "weekday": "sun", "time": "10:30" }
  ]
}
```

| Rule field | |
|---|---|
| `studio_id` | Required. The studio id (shown by `autobook classes`, or in the class/studio URL of the apps). |
| `weekday` | Required. `mon` … `sun` (or 1 = Monday … 7 = Sunday). |
| `time` | Required. Start time `HH:MM`, Stockholm time, as the app shows it. |
| `master_id` | Optional. The class's weekly series id. The most precise match. |
| `title` | Optional. Case-insensitive part of the class title. |
| `waitlist_if_full` | Optional, default `false`. Join the waitlist when the class is full. |
| `name` | Optional. Shown in logs and notifications; also the rule's id in the state. |
| `enabled` | Optional, default `true`. |

A weekly series is identified by `master_id + weekday + HH:MM`. Some classes have no `master_id`, so
for those use `title` (`studio_id + title + weekday + HH:MM`).

To find the values, list a studio's classes (needs the token, see below):

```sh
node src/node/cli.ts classes --studio 135
# Thu 2026-10-22 18:00  weekday thu  class 1001  master_id 555  "Boxning För Tjejer - Nybörjare"  spots 6/6  opens Thu 2026-10-15 18:00  series m555|4|18:00
```

Options (all optional, `options` object): `tick_seconds` (300; must match the scheduler),
`horizon_slack_seconds` (60), `lead_ms` (2000), `retry_interval_ms` (1000), `retry_window_seconds`
(60), `open_grace_ms` (3000), `catch_up` (true), `lookahead_days` (15), `max_tick_attempts` (3),
`rebook_when_spot_frees` (true). A `user_id` key at the top level can replace `BRUCE_USER_ID`.

## Secrets

| Variable | |
|---|---|
| `BRUCE_ACCESS_TOKEN` | Required. The session access token. Never commit it. |
| `BRUCE_USER_ID` | Required (or `user_id` in the config). Your numeric Bruce user id. |
| `AUTOBOOK_NOTIFY_URL` | Optional. Webhook for notifications: the message goes as a plain-text POST with `Title`, `Priority` and `Tags` headers, which is the [ntfy](https://ntfy.sh) format: `https://ntfy.sh/<long-random-topic>`. |
| `AUTOBOOK_DRY_RUN` | Optional. `1` = same as `--dry-run`. |

There is no token refresh: the server keeps accepting the access token until it answers HTTP 401
(see [API.md](../API.md)). To get a token and your user id, log in once:

```sh
node src/node/cli.ts login     # asks for email and password, prints BRUCE_ACCESS_TOKEN and BRUCE_USER_ID
```

The password is sent once to `POST /v52/access/authenticate` and not stored. When autobook later
reports "log in again", run `login` again and update the secret.

## Try it first

```sh
cd autobook
npm install                      # dev tools only (TypeScript, Node types)
npm test                         # unit tests, no network
cp autobook.config.example.json autobook.config.json   # then edit
printf 'BRUCE_ACCESS_TOKEN=...\nBRUCE_USER_ID=...\n' > .env && chmod 600 .env   # git-ignored
npm run plan                     # what would happen: matched classes, open times, state
node --env-file=.env src/node/cli.ts tick --dry-run   # a full tick without POSTs and without writing state
```

`--dry-run` does everything (scan, limits, waiting until the open moment) except
`POST /v52/booking` and `POST /v52/standby`, and keeps all state changes in memory.

## (a) VPS or Fly.io

### Fly.io

```sh
cd autobook
fly apps create bruce-autobook-<something>        # and put that name into fly.toml
fly volumes create autobook_data --region arn --size 1
fly secrets set BRUCE_ACCESS_TOKEN=... BRUCE_USER_ID=... AUTOBOOK_CONFIG="$(cat autobook.config.json)"
fly secrets set AUTOBOOK_NOTIFY_URL=https://ntfy.sh/<topic>     # optional
fly deploy
fly logs
```

The machine runs `node src/node/cli.ts run`: it ticks every 5 minutes (aligned to :00, :05, …). Bookings
fire in the background, so a wait for an open moment never delays the next tick. State lives on the
volume. Nothing listens on a port. After a new `login`, run `fly secrets set BRUCE_ACCESS_TOKEN=...`
(this restarts the machine).

### VPS with systemd

```sh
sudo mkdir -p /opt/bruce-autobook /etc/bruce-autobook
sudo cp -r package.json src /opt/bruce-autobook/
sudo cp autobook.config.json /etc/bruce-autobook/
sudo install -m 600 /dev/stdin /etc/bruce-autobook/env <<'EOF'
BRUCE_ACCESS_TOKEN=...
BRUCE_USER_ID=...
EOF
sudo cp deploy/bruce-autobook.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now bruce-autobook
journalctl -u bruce-autobook -f
```

Needs Node ≥ 22.18 at `/usr/bin/node` and a synced clock (`timedatectl` should say
`System clock synchronized: yes`). Or use the `Dockerfile` with any container runner and a volume on `/data`.

## (b) Cloudflare Worker

```sh
cd autobook
npx wrangler login
npx wrangler d1 create bruce-autobook          # paste the database_id into wrangler.toml
# edit AUTOBOOK_CONFIG in wrangler.toml (or: npx wrangler secret put AUTOBOOK_CONFIG)
npx wrangler secret put BRUCE_ACCESS_TOKEN
npx wrangler secret put BRUCE_USER_ID
npx wrangler secret put AUTOBOOK_NOTIFY_URL     # optional
npx wrangler deploy
npx wrangler tail                               # live logs
```

The tables are created on first run, so there is no migration step. The Cron Trigger `*/5 * * * *`
runs one tick per invocation. A tick that fires waits **inside the scheduled invocation** until
`open − 2 s`, so the precise part needs no extra infrastructure.

This depends on these Cloudflare limits (checked against
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/), October 2026):

- **Wall time:** a scheduled invocation may run for up to **15 minutes**. A tick waits at most about
  6 minutes plus the 60 s retry window, which fits. Waiting does not use CPU time.
- **CPU time:** Free 10 ms per invocation; Paid 30 s for cron intervals under 1 hour. A tick needs
  little CPU (small JSON responses), but 10 ms is tight, so **the Workers Paid plan is recommended**.
- **Subrequests:** Free **50** per invocation in total, Paid 10,000. Every Bruce API call and webhook
  POST counts. `AUTOBOOK_SUBREQUEST_BUDGET` caps the Bruce calls (default 40, so on Free about 30
  booking attempts remain after the scan, i.e. ~30 s of retries). On Paid, set it to `1000`.

Overlapping invocations (the 17:55 tick still waiting for an 18:00 opening when the 18:00 tick starts)
are safe: the class is claimed in D1 with a versioned compare-and-set, and D1 is strongly consistent.
KV would not be safe here, because its reads can be stale for up to 60 s. Durable Object alarms would
also work (an alarm at `open − 2 s`), but are not needed while cron wall time is 15 minutes.

Local test without deploying (dry run, secrets in a git-ignored `.dev.vars`):

```sh
printf 'BRUCE_ACCESS_TOKEN=...\nBRUCE_USER_ID=...\nAUTOBOOK_DRY_RUN=1\n' > .dev.vars
npx wrangler dev --test-scheduled
curl "http://localhost:8787/__scheduled?cron=*/5+*+*+*+*"
```

The Worker has no public HTTP endpoint (`fetch` returns 404).

## (c) macOS launchd

```sh
cd autobook
cp autobook.config.example.json autobook.config.json   # edit
security add-generic-password -s bruce-autobook -a access-token -w   # prompts for the token (login Keychain)
echo 'BRUCE_USER_ID=...' > .env                          # or "user_id" in the config
./scripts/install-launchd.sh
tail -f ~/Library/Logs/bruce-autobook.log
```

`install-launchd.sh` writes `~/Library/LaunchAgents/net.dauernheim.bruce.autobook.plist` from
`deploy/net.dauernheim.bruce.autobook.plist` (filling in the paths and your `node`) and loads it with
`launchctl bootstrap`. launchd starts `scripts/macos-tick.sh` every 300 s (`StartInterval`) and once at
load. The script reads the token from the Keychain (or `.env`) and runs one `tick` under
`caffeinate -i`, so the Mac does not idle-sleep while a tick waits for an open moment. launchd never
starts a second copy while one is still running.

Limits of this option: launchd does not run jobs while the Mac sleeps or is shut down, and it does not
wake it. A missed open moment is caught up at the next tick (`catch_up`), when the class may already be
full. For classes that fill in minutes, use (a) or (b), or keep the Mac awake (e.g. on power with sleep
disabled).

To uninstall:

```sh
launchctl bootout gui/$(id -u)/net.dauernheim.bruce.autobook
rm ~/Library/LaunchAgents/net.dauernheim.bruce.autobook.plist
```

After a new `login`, update the Keychain item:
`security add-generic-password -U -s bruce-autobook -a access-token -w`.

## Layout

```
autobook/
├── src/core/        Shared logic, no Node or Workers APIs: time zones, config, rule matching,
│                    open-time, tick planning, the retry loop, API client, state + notifications
├── src/node/        CLI (run | tick | plan | classes | login) and the JSON file store
├── src/worker/      Worker entry (scheduled handler) and the D1 store
├── test/            node:test unit tests with a virtual clock and a fake API (no network)
├── deploy/          systemd unit, launchd plist
├── scripts/         launchd tick wrapper and installer
├── Dockerfile, fly.toml, wrangler.toml
└── autobook.config.example.json
```

## Responsible use

This is personal automation for your own account. It books one spot for you in classes you have
chosen to attend every week, at the moment any member could book them. It sends about one small request
per rule every 5 minutes, plus about one request a second in the minute around an open moment. Please
keep it that way. Don't use it for other people's accounts or to book spots you will not use, and don't
lower the intervals. Cancel in time if you can't go: late cancellations and no-shows can lead to
strikes as usual.

## Not done yet

- Rules are edited in a JSON file. Managing them in the iOS/macOS apps (e.g. "Auto-book this class
  weekly" on the class page) would need a small sync API to the server-side store.
- One user per deployment.
- The "too early" error of `POST /v52/booking` was never captured. If a capture shows a specific code,
  early 4xx answers could be told apart from real refusals.
