# Auto-book and challenges server

A small [Cloudflare Worker](https://developers.cloudflare.com/workers/) that books the weekly classes of every app
user who switches it on, the moment their booking window opens, and tells them with an Apple push and an email. The apps work
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
  It also goes by email, see below.

## Email

Every push about a booking (auto-book result, waitlist spot booked, waitlist watch stopped, login expired) is also
sent as an email to the address on the user's Bruce account (`email` in `GET /v52/user/<id>`, read when the app signs
in). Web users, who have no push device, learn about bookings this way too. The email links to the class in the
web app and has a "No more emails" link (`/email/off`, also sent as a one-click `List-Unsubscribe` header); the
apps can switch it with `PUT /me/email`. Push stays on either way.

Sending uses [Resend](https://resend.com) (free tier: 3,000 emails a month, 100 a day), because Cloudflare's own
Email Service only sends to arbitrary addresses on the Workers Paid plan. `EMAIL_FROM` in `wrangler.toml` is the
sender; its domain has to be verified in Resend. Without the `RESEND_API_KEY` secret no email is sent.

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

## Challenges with friends

Bruce does not show friends' past visits, so challenges need the server: each participant's row holds their login,
and a **daily cron** (02:30 UTC) reads every stored user's `GET /v52/booking` history.

- A challenge has a goal (most classes, most visits, most minutes, or "everyone hits N"), a period (fixed days, or
  repeating month after month), optionally one category (a Bruce category id, or `gym` for drop-ins), and friends.
- **Everything counts**, deduplicated: class bookings (checked in or not, once the class has started), check-ins and
  drop-in gym visits. The same class counts once; a drop-in at the same studio within 3 hours of a class there is
  that class's door check-in; two drop-ins at one studio on one day are one visit. A drop-in counts 60 minutes.
- Only the creator's Bruce friends can be invited (checked with `GET /v52/friend`), and **each friend accepts each
  challenge separately**. Nothing of a friend is read or shown before they accept. Invitees with Brüce on their
  iPhone get a push; anyone can be sent the share link `https://djui.github.io/bruce/app/#challenge/<id>`, which
  shows a preview and lets friends of the creator join.
- **Friends see everything** in a challenge they share: totals, class types and studios, recent visits and how many
  classes they did together, plus monthly stats.
- Leaving deletes your per-visit detail (if you are in no other challenge). A challenge without accepted
  participants is deleted.

The history is kept per user and day in `daily_counts` (`server/migrations/0001_challenges.sql`): counts for every
stored user, and per-visit detail (class, studio, categories) only while they are in a challenge. The first read
goes back to January 1 (or the start of the earliest challenge); later reads cover only the last few days. One daily
run spends at most `DAILY_BUDGET` (45) Bruce requests, least recently refreshed users first, so on the free plan a
few dozen users are refreshed per day.

**Goal reminders** (optional): the apps keep monthly goals on the device; goals with "Reminder when behind" are sent
with `PUT /me/goals`, and the daily run pushes "Behind on your goal" from day 8 of the month when checked-in visits
are behind pace, at most once a week per goal.

**Wrapped percentiles**: `GET /wrapped/percentiles` compares the year-to-date numbers the app computed with the
other stored users (checked-in visits, minutes, studios, longest weekly streak) and returns only percentiles, and
nothing when fewer than 5 other users have data.

## Skipped a habit

The same daily run looks for a broken weekly habit in each user's history (users with a push device who did not
switch it off with `"nudges": false`), logic in `src/habits.js`:

- A **habit** is the same class title at the same studio, weekday and local start time, visited at least **3 weeks
  in a row**. It is **broken** when the next week's slot passed without a visit and the user then visited nothing
  and has **no upcoming booking** for **4 days** (a Saturday class: on Wednesday; the user can pick 1-7 with
  `"nudgeDays"`, the apps offer 2, 4 and 7, where 7 is the morning of the next slot). Of several, the longest run wins.
  Each break is told once; the next week's slot ends it.
- **Picks**: classes in the next 7 days at the habit's studio and the user's other most visited studio (at most
  4 class-list pages each), listed, not full and bookable before they start, scored like the apps' For you: the
  same class, the user's classes and categories, the studio, closeness to the habit's time and weekday, and sooner
  first. Up to three, one per class.
- The push ("Missing your Saturday morning Reformer?", body "3 Saturdays in a row at 09:00, then a break. Picked
  for you: Reformer, Sat 09:00 at STC Rosenlundsparken · …", category `RECOMMENDATION`, payload
  `{"recommend":[classId,…]}`) is planned in table `nudges` (`migrations/0002_nudges.sql`) and sent by the minute
  cron at **08:00 local**. Tapping it opens the best pick on top of For you.
- Cost: the history read covers the last 6 weeks (often one or two pages instead of one), plus at most 8 class-list
  requests on a day with a broken habit, all within `DAILY_BUDGET`.

## Users and what is stored

There is no shared key. The app signs in with the user's own Bruce login (`X-Access-Token` and `X-User-Id`
headers), and the server checks it with Bruce (`GET /v52/user/<id>`) on every request, so each user only reads and
changes their own data. Set `ALLOWED_USERS` (comma-separated Bruce user ids) to limit who may use the server.

One row per user in a D1 table: the Bruce access token (to book with), the rules (studio, weekday, time, class
series), push device tokens, the Bruce email address (for booking emails), upcoming classes and a short log. Bruce's server does not expire access tokens in
practice (see API.md "Refresh"), so whoever can read the database can use those accounts until they log out of
Bruce. Switching "Let the server book for me" off in the app deletes the user's row, unless they are in a challenge:
then only the rules, watches and goals go and the login stays (joining a challenge stores it, auto-book on or off).
A 401 from Bruce deletes the row too (and pushes "Auto-book paused"; the app sends the new login on its next start).
Challenge, participant and history tables: see "Challenges with friends" above; the `nudges` table (one row per user:
the last skipped habit told and its push) under "Skipped a habit".

## Set up

```sh
cd server
npx wrangler login
npx wrangler d1 create bruce-autobook          # paste the database_id into wrangler.toml
npx wrangler secret put APNS_KEY               # contents of the APNs AuthKey_XXXXXXXXXX.p8
npx wrangler secret put APNS_KEY_ID            # its Key ID
npx wrangler secret put APNS_TEAM_ID           # Apple team id
npx wrangler secret put RESEND_API_KEY         # optional: Resend API key, for booking emails
npx wrangler d1 migrations apply bruce-autobook --remote   # challenges, participants, daily_counts, nudges
npx wrangler deploy
```

`APNS_TOPIC` (the app's bundle id, `net.dauernheim.bruce`) is set in `wrangler.toml`. The APNs key comes from
developer.apple.com › Certificates, IDs & Profiles › Keys (enable "Apple Push Notifications service"); without it
everything works except the push. The `users` table is created on first use; the other tables come from
`migrations/` (apply them before deploying a version that uses them). The cron triggers in `wrangler.toml` are every
minute (auto-book) and daily at 02:30 UTC (history; keep it equal to `DAILY_CRON` in `src/worker.js`).

The apps have the author's worker address built in (`AutoBookServer.defaultURL` in `Shared/BruceCore/AutoBook.swift`);
change it for your own deployment, or override it in the app (Menu › Auto-book › Server address). With the
server on (the default), the app sends the user's rules, push token and login by itself.

Cost: the Workers and D1 free plans cover a handful of users. One cron run may make 50 requests on the free plan,
which limits it to roughly 10-20 weekly classes per scan minute across users.

## HTTP API

All requests need the user's Bruce login (CORS is open, the web app calls the server from the browser): `X-Access-Token: <access token>` and `X-User-Id: <user id>`.

| Request | Body | Effect |
|---|---|---|
| `PUT /me` | `{"rules":[{"id","studioId","masterId","title","weekday","minuteOfDay"}],"device":{"token","env"},"nudges":true}` | Stores the login, replaces the rules (weekday 1 = Sunday, local time in Europe/Stockholm), adds the device (`env` `production` or `sandbox`); `nudges` (optional, default on) switches skipped-habit pushes, `nudgeDays` (1-7, default 4) sets their quiet days |
| `GET /me` | | `{hasSession, rules, lastScan, upcoming:[{classId,title,at}], waitlist:[{classId,title,start}], log:[{classId,title,at,outcome}], devices, email, nudges, nudgeDays}` |
| `DELETE /me` | | Deletes the user's row and history; in a challenge it keeps the login and clears rules, watches and goals |
| `PUT /me/waitlist/<classId>` | | Watches a full class and books it when a spot frees up (404 if the class is gone or started, 409 over 10 watches). Stores the login; creates the user's row if needed |
| `DELETE /me/waitlist/<classId>` | | Stops watching it |
| `POST /me/test-push` | | Sends a test push to the user's devices and a test email |
| `PUT /me/email` | `{"enabled":false}` | Stops (or with `true` restarts) the booking emails → `{email}`: the address used, or null |
| `GET /email/off?u=<userId>&t=<token>` | | The unsubscribe link in each email (no login needed; `POST` for one-click) |
| `PUT /me/goals` | `{"goals":[{"id","title","category","studioId","target","remind"}]}` | Stores the goals with `remind` for "Behind on your goal" pushes (max 10; `[]` clears) |
| `POST /challenges` | `{"title","metric","target","category","categoryTitle","start","end","repeatMonthly","invite":[userId]}` | Creates a challenge (`metric` `classes`, `visits`, `minutes` or `target`; days `YYYY-MM-DD`, at most 366), invites friends by push → 201 `{challenge}` |
| `GET /challenges` | | `{challenges:[…], usesBruce:[userId]}`: the caller's challenges and invites, and which friends use the server |
| `GET /challenges/<id>` | | Participants: `{challenge, leaderboard:[{userId,name,status,rank,score,visits,classes,dropins,minutes,studios,topStudio,topClass,categories,together,lastVisit,done,daily,recent}], months:[{month,label,entries}], updatedAt}`; others: a preview `{challenge, joinable}` |
| `POST /challenges/<id>/accept` | | Accepts an invite; stores the login and reads the history |
| `POST /challenges/<id>/join` | | Joins from the share link (friends of the creator only, else 403) |
| `POST /challenges/<id>/leave` | | Leaves; deletes the per-visit detail when in no other challenge |
| `GET /wrapped/percentiles?year=&visits=&minutes=&studios=&streak=` | | `{year, cohort, percentiles:{visits,…}}` (0-100 = share of other users below), `percentiles: null` under 5 users |

## Develop

```sh
npm test            # node --test, no dependencies (D1 is stood in by node:sqlite with the real migrations)
npx wrangler d1 migrations apply bruce-autobook --local
npx wrangler dev --test-scheduled   # then curl "http://localhost:8787/__scheduled?cron=*+*+*+*+*"
                                    # daily run: curl "http://localhost:8787/__scheduled?cron=30+2+*+*+*"
```
