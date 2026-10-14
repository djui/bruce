# Auto-book server

A small [Cloudflare Worker](https://developers.cloudflare.com/workers/) that books the weekly classes of every app
user who switches it on, the moment their booking window opens, and tells them with an Apple push. The apps work
without it: the Mac app books while it runs, and the iPhone shows a notification with a **Book** button at the open
moment. Back to the [project README](../README.md).

## How it works

A class opens for booking at `bookable_earliest_time`, a fixed time before it starts (7 days for about 97% of
classes, see [API.md](../API.md#booking-windows-measured-2026-10-14)). Classes are listed about 14 days ahead,
so the server knows next week's class a week before it opens.

- The cron trigger runs **every minute**, but most minutes make no request to Bruce.
- **Every 5 minutes** it re-reads each user's classes (one request per studio and matching day in the next
  15 days; users are spread over the five minutes) and remembers when each one opens.
- **In the minute before a class opens** it waits for the open moment and sends `POST /v52/booking`,
  retrying every second for 20 seconds. A class is tried once: if you cancel it later, it is not booked again.
- The result ("Booked: Reformer", or why not) goes to the user's iPhones as an Apple push; tapping it opens the class.

## Waitlist: book as soon as a spot frees up

Bruce does not book waitlisters itself: a "Free spot" notification only tells them, and the first to book wins
(see [API.md](../API.md#bookmarks-favourites-waitlist)). On a full class the apps offer **Book when a spot opens**
(iOS, Mac and web). Switching it on joins the waitlist if needed and asks the server to watch the class.

- The server reads the class (`GET /v52/class/<id>`, one request) and, as soon as `available_spots` is above 0, sends
  `POST /v52/booking`, then pushes "Booked: Reformer" to the user's iPhones.
- Polling: every minute in the last 24 hours before the class (a freed spot goes to whoever books first), every
  5 minutes before that. At most 10 watched classes per user.
- It stops when the class is booked, started, cancelled or removed from the list, when the user switches it off or
  leaves the waitlist in the app, or after 5 failed booking attempts on a free spot (it waits 5 minutes between
  them; a lost race just keeps watching). The last case sends a push too.
- Each user's watches are separate and use that user's own login. Web users have no push device, so they see the
  result in My classes.

## Users and what is stored

There is no shared key. The app signs in with the user's own Bruce login (`X-Access-Token` and `X-User-Id`
headers), and the server checks it with Bruce (`GET /v52/user/<id>`) on every request, so each user only reads and
changes their own data. Set `ALLOWED_USERS` (comma-separated Bruce user ids) to limit who may use the server.

One row per user in a D1 table: the Bruce access token (to book with), the rules (studio, weekday, time, class
series), push device tokens, upcoming classes and a short log. Bruce's server does not expire access tokens in
practice (see API.md "Refresh"), so whoever can read the database can use those accounts until they log out of
Bruce. Switching "Let the server book for me" off in the app deletes the user's row; a 401 from Bruce deletes it
too (and pushes "Auto-book paused"; the app sends the new login on its next start).

## Set up

```sh
cd server
npx wrangler login
npx wrangler d1 create bruce-autobook          # paste the database_id into wrangler.toml
npx wrangler secret put APNS_KEY               # contents of the APNs AuthKey_XXXXXXXXXX.p8
npx wrangler secret put APNS_KEY_ID            # its Key ID
npx wrangler secret put APNS_TEAM_ID           # Apple team id
npx wrangler deploy
```

`APNS_TOPIC` (the app's bundle id, `net.dauernheim.bruce`) is set in `wrangler.toml`. The APNs key comes from
developer.apple.com › Certificates, IDs & Profiles › Keys (enable "Apple Push Notifications service"); without it
everything works except the push. The table is created on first use.

The apps have the author's worker address built in (`AutoBookServer.defaultURL` in `Shared/BruceCore/AutoBook.swift`);
change it for your own deployment, or override it in the app (Menu › Auto-book › Server address). With the
server on (the default), the app sends the user's rules, push token and login by itself.

Cost: the Workers and D1 free plans cover a handful of users. One cron run may make 50 requests on the free plan,
which limits it to roughly 10-20 weekly classes per scan minute across users.

## HTTP API

All requests need the user's Bruce login (CORS is open, the web app calls the server from the browser): `X-Access-Token: <access token>` and `X-User-Id: <user id>`.

| Request | Body | Effect |
|---|---|---|
| `PUT /me` | `{"rules":[{"id","studioId","masterId","title","weekday","minuteOfDay"}],"device":{"token","env"}}` | Stores the login, replaces the rules (weekday 1 = Sunday, local time in Europe/Stockholm), adds the device (`env` `production` or `sandbox`) |
| `GET /me` | | `{hasSession, rules, lastScan, upcoming:[{classId,title,at}], waitlist:[{classId,title,start}], log:[{classId,title,at,outcome}], devices}` |
| `DELETE /me` | | Deletes the user's row |
| `PUT /me/waitlist/<classId>` | | Watches a full class and books it when a spot frees up (404 if the class is gone or started, 409 over 10 watches). Stores the login; creates the user's row if needed |
| `DELETE /me/waitlist/<classId>` | | Stops watching it |
| `POST /me/test-push` | | Sends a test push to the user's devices |

## Develop

```sh
npm test            # node --test, no dependencies
npx wrangler dev --test-scheduled   # then curl "http://localhost:8787/__scheduled?cron=*+*+*+*+*"
```
