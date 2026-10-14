# Auto-book server (optional)

A small [Cloudflare Worker](https://developers.cloudflare.com/workers/) that books your weekly classes the
moment their booking window opens, even when your phone is locked and your Mac is asleep. The apps work without
it: the Mac app books while it runs, and the iPhone shows a notification with a **Book** button at the open
moment. Back to the [project README](../README.md).

## How it works

A class opens for booking at `bookable_earliest_time`, a fixed time before it starts (7 days for about 97% of
classes, see [API.md](../API.md#booking-windows-measured-2026-10-14)). Classes are listed about 14 days ahead,
so the server knows next week's class a week before it opens.

- The cron trigger runs **every minute**, but most minutes only read the stored state and make no request to Bruce.
- **Every 5 minutes** it re-reads the classes of your rules (one request per studio and matching day in the next
  15 days) and remembers when each one opens.
- **In the minute before a class opens** it waits for the open moment and sends `POST /v52/booking`,
  retrying every second for 20 seconds. A class is tried once: if you cancel it later, it is not booked again.
- Optional: results go to an [ntfy](https://ntfy.sh) topic as push notifications.

## What it stores

In a KV namespace: your rules (studio, weekday, time, class series), the list of upcoming classes and a short
log, and, while "Let the server book for me" is on in the app (the default once a server is set up), your Bruce
access token and user id.
Bruce's server does not expire access tokens in practice (see API.md "Refresh"), so whoever can read the KV
namespace can use your account until you log out of Bruce. Switching "Let the server book for me" off deletes it, and a
401 from Bruce deletes it too. The HTTP API is protected by a key you choose (`API_KEY`).

## Set up

```sh
cd server
npx wrangler login
npx wrangler kv namespace create AUTOBOOK      # paste the printed id into wrangler.toml
npx wrangler secret put API_KEY                # a long random string, e.g. `openssl rand -hex 32`
npx wrangler secret put NTFY_TOPIC             # optional: a private, hard-to-guess ntfy topic
npx wrangler deploy
```

The apps have the author's worker address built in (`AutoBookServer.defaultURL` in
`Shared/BruceCore/AutoBook.swift`); change it for your own deployment, or override it in the app (Menu › Auto-book ›
Server address and key). The key never goes into the repository: put it in the git-ignored
`Bruce-iOS/Config/Local.xcconfig` as `AUTOBOOK_SERVER_KEY = …` (built into your iOS build), and for the Mac app run
`security add-generic-password -U -s net.dauernheim.BruceMacOS -a autobook-server-key -w <key>` (or type it in the
app). With address and key in place the app syncs your rules and hands the server your login by itself;
"Let the server book for me" in Menu › Auto-book switches that off and removes the login from the server.

Cost: within the Workers free plan (1,440 cron runs and a few hundred KV writes a day).

## HTTP API

All requests need `Authorization: Bearer <API_KEY>`.

| Request | Body | Effect |
|---|---|---|
| `PUT /rules` | `{"rules":[{"id","studioId","masterId","title","weekday","minuteOfDay"}]}` | Replaces the rules (weekday 1 = Sunday, local time in Europe/Stockholm) and rescans |
| `PUT /session` | `{"access_token","user_id"}` | Lets the server book |
| `DELETE /session` | | Removes the token |
| `GET /status` | | `{hasSession, rules, lastScan, upcoming:[{classId,title,at}], log:[{classId,title,at,outcome}]}` |

## Develop

```sh
npm test            # node --test, no dependencies
npx wrangler dev --test-scheduled   # then curl "http://localhost:8787/__scheduled?cron=*+*+*+*+*"
```
