# Bruce: unofficial macOS and iOS clients for Bruce Studios

Native SwiftUI clients for the [Bruce Studios](https://www.brucestudios.com) fitness membership (Sweden, Norway,
Denmark), plus a reverse-engineered map of the app's v52 HTTP API.

**Project page: [djui.github.io/bruce](https://djui.github.io/bruce/)** · [Web app](https://djui.github.io/bruce/app/) · [API viewer](https://djui.github.io/bruce/api/)

> [!IMPORTANT]
> **Unofficial: not affiliated with or endorsed by Bruce Studios AB.** "Bruce Studios" and "Bruce" are
> trademarks of Bruce Studios AB. This is a personal hobby project. It is not the Bruce Studios app, is not
> supported by Bruce Studios, and may stop working whenever their API changes. You need your own Bruce
> Studios membership to use it.

## Screenshots

Captured in [demo mode](#demo-mode-developer-switch) with fictional data. They follow your light or
dark setting on GitHub; every screen is in [`docs/screenshots/`](docs/screenshots) in both appearances.

<p align="center">
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-home-light.webp"><img src="docs/screenshots/iphone-home-dark.webp" width="200" alt="Home screen with spotlight, categories and nearby gyms"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-explore-light.webp"><img src="docs/screenshots/iphone-explore-dark.webp" width="200" alt="Explore tab listing studios with filter chips"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-studio-light.webp"><img src="docs/screenshots/iphone-studio-dark.webp" width="200" alt="Studio page with Show ticket, opening status and facilities"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-detail-light.webp"><img src="docs/screenshots/iphone-detail-dark.webp" width="200" alt="Class page with booking windows and a Book button"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-similar-light.webp"><img src="docs/screenshots/iphone-similar-dark.webp" width="200" alt="Similar classes sheet for a fully booked class"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-quickcheckin-light.webp"><img src="docs/screenshots/iphone-quickcheckin-dark.webp" width="200" alt="Quick check-in sheet suggesting the last visited studio"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-drawarea-light.webp"><img src="docs/screenshots/iphone-drawarea-dark.webp" width="200" alt="Map with a hand-drawn custom area"></picture>
<picture><source media="(prefers-color-scheme: light)" srcset="docs/screenshots/iphone-mybookings-light.webp"><img src="docs/screenshots/iphone-mybookings-dark.webp" width="200" alt="My classes with two bookings"></picture>
</p>

<p align="center">
<img src="docs/screenshots/mac-explore.webp" width="240" alt="macOS window showing the Explore list">
<img src="docs/screenshots/mac-studio.webp" width="240" alt="macOS window showing a studio page">
</p>

## What's in here

| | |
|---|---|
| **Brüce for iPhone** ([`Bruce-iOS/`](Bruce-iOS/README.md)) | iOS 26+ app built with Liquid Glass throughout |
| **BruceMacOS** ([`Bruce-MacOS/`](Bruce-MacOS/README.md)) | Phone-sized SwiftUI app for macOS 14+, run with `swift run` |
| **Brüce Web** ([`docs/app/`](docs/app), [live](https://djui.github.io/bruce/app/)) | Browser version on GitHub Pages: plain HTML, CSS and JavaScript, no build step |
| **BruceCore** ([`Shared/BruceCore/`](Shared/BruceCore)) | Code shared by both apps: API client, models, Keychain session, app state, booking rules, demo data |
| **Auto-book server** ([`server/`](server/README.md)) | Cloudflare Worker that books users' weekly classes the moment they open and sends the result by push and email |
| **API map** ([`API.md`](API.md), [`openapi.yaml`](openapi.yaml), [`swagger.html`](swagger.html)) | The Bruce Studios v52 API as observed from the official iOS app 14.4.2 |

## Features

Both apps follow the structure of the official app screen by screen: Home, Explore, Check in, Friends and
My classes tabs, with class and studio pages and account sheets.

- **Log in** with your Bruce Studios email and password. Only the session tokens are kept, in the Keychain.
  As in the official app there is no token refresh: the server keeps accepting the access token after its
  nominal 3-hour expiry, so you are only asked to log in again when the server rejects it (HTTP 401).
- **Explore** all live studios (about 700 in Sweden) and the city-wide class schedule, with category,
  tier, Wellness and favourite filters, search, a map, and **custom areas**: draw an outline on the map and
  filter studios and classes to it. Long-press (iOS) or right-click (macOS) an area to show it on the map,
  rename it or delete it. As in the official app, areas stay on the device. The Classes list can also be
  narrowed by **time of day** (Early, Morning, Lunch, Afternoon, Evening, Late), **duration** (≤ 45, 45–60, 60+ min)
  and **"Bookable now"**, and sorted by start, distance, travel time (your commute mode from Places & commute) or
  spots left, all in the same filter sheet and on the device.
  Class rows mark Wellness classes, show a "Waitlist" pill when you are on the waitlist ("Spot open" once it has a free spot) and "Fully
  booked" otherwise, and show the faces of friends who booked the class;
  lists say "Filter active" at the end while filters apply. Deleted classes are hidden, as in the official app.
- **Parakey doors**: studios whose doors open with the Parakey app say so on the class and studio pages,
  with a sheet that shows whether your account is linked and opens Parakey.
- **Book, cancel and join waitlists** through a booking-rules sheet that shows the "book until",
  "cancel until" and check-in windows. Waitlist entries that turn into a spot show as booked. A "Free spot"
  notification does not book for you: the class page then offers Book next to Leave waitlist. A fully booked class also offers **Book when a spot opens** (the auto-book server joins the waitlist for you and books the spot the moment one frees up; once cancelling would cost a strike it asks first, see [Late spots](server/README.md#late-spots-ask-before-booking-what-costs-a-strike-to-cancel)) and **Similar classes**: nearby classes
  around the same time, as swipeable cards.
- **Book when booking opens** a one-off class (a workshop listed two weeks ahead but bookable only a week
  before): the button replaces the greyed-out Book on its class page. The server (or, without it, the iPhone's
  notification with a Book button / the Mac while it runs) books it once at the open moment with the same retries
  and late-spot rule as weekly classes; at most 5 classes wait this way, nothing is polled in between. Menu ›
  Auto-book lists them.
- **Auto-book** a weekly class: switch on "Book every week" on a class page. A class opens for booking a
  fixed time before it starts (7 days for almost all classes), so the apps know the moment in advance. The
  Mac app books by itself at that moment while it runs; the iPhone shows a notification at that moment
  whose **Book** button books from the lock screen (and books by itself while the app is open). An optional
  small server ([`server/`](server/README.md), a Cloudflare Worker) books even when no device is awake and
  sends you the result by push and by email (to your Bruce account's address; every email has a link to
  stop them); the app signs in to it with your Bruce login and syncs your classes by
  itself (one switch turns that off). Menu › Auto-book lists the classes and the
  server settings.
- **Add to Calendar** a booked class from My classes (long-press a row), its ⋯ menu or the class page: the
  iPhone opens the system event editor (no calendar permission needed), the Mac writes the event with EventKit
  (or opens an .ics file in Calendar), the web app downloads an .ics file. The event has the check-in window and
  the free-cancel deadline in its notes and a 1 h alert. Settings › **Calendar subscription** opens Bruce's own
  `webcal://` feed of all your bookings directly (long-press to copy the link instead); a one-off event does not
  follow changes to the class, the feed does.
- **Book again**: a past class in Statistics, My classes (long-press), the rating sheet and an attended class's page
  offers "Book again": the next class of the same series (same studio, weekday and time; same `master_id` or
  title) with Book, or "Booking opens Sat 24 Oct" when it is not bookable yet, plus "Book every week", which hands
  the series to auto-book. One or two class-list requests for that studio only.
- **Free cancel until 18:30**: every booked row in My classes says what cancelling costs right now, green while it is
  free, amber once it costs 1 or 2 strikes ("Cancel now: 2 strikes · 3 from 18:30"), red at 3. Settings › **Last
  free cancel reminder** (off by default) sends a local notification one hour before the free deadline; nothing is
  ever cancelled for you.
- **Visit limits:** tap the visits pill (e.g. "1/1") for visits used and left, the reset date and each
  plan's limit at the studio. A class over your limit shows its drop-in price ("Buy for SEK 220").
- **Descriptions and alerts:** studio and class descriptions are rendered as Markdown (bold, lists, links).
  Active alerts (e.g. "Women only") show in red; alerts have a start and an optional end, and expired ones
  are hidden. **Translate** turns descriptions and alerts into your device language with Apple's
  on-device Translation framework (iOS, macOS 15+); no online translation service is used.
- **Check in** by scanning the studio's door QR code with the camera, or with one tap from a suggestion
  (a booked class whose check-in window is open, the nearest studio, or the last one you visited).
  Every check-in asks for confirmation first, and the ticket opens when it went through. The server can
  answer an error even though the check-in was registered, so the apps re-read your bookings before
  reporting a failure (and then show the server's reason). A scanned door QR is remembered for later
  one-tap check-ins at that door.
- **My classes** keeps a class after you check in (with a "Checked in" badge and the ticket), as the
  official app does, until it leaves the 24-hour window.
- **Rate the class** after attending: like the official app, the apps ask at start for each checked-in
  class that has ended and is not rated yet (stars, optional comment, optional anonymity). Skipped classes
  can be rated later from My classes or the class page.
- **Studio pages** show opening hours ("Solo training until 22:00"), notices, facilities, reviews, photos,
  per-studio visit limits and classes. The Reviews tab shows the **last 90 days** next to the all-time rating
  (from the comments the page loads, and labelled so) and says "Rated lower lately" when they differ.
- **First visit here?**: until your first check-in at a studio, its page and its class pages show when to check in
  (the class's window), how the door works (Parakey or the QR code), the facilities and that a late check-in costs
  a strike. Built only from the fields the page already has; nothing is crawled.
- **Class pages** show the studio's notice banner, everyone booked on the class (friends and members with a
  public profile by name, the rest as "Hidden"), and an **Invite** button that sends the class to the
  friends you pick, as in the official app.
- **Notifications** open the class they are about (or its studio, strikes or membership). Each icon shows what happened
  (free spot, reminder, check-in, cancellation, studio message, strike, block…) and a corner badge for whether it is about
  a class, a studio or Bruce itself, lime for good news and red for bad.
- **Statistics** as in the official app: a bar chart of visits per month, and below it every visit of the
  selected month by day (class or solo training, studio, area and instructor).
- **For you** (iPhone and web): Home ranks upcoming classes for you on the device, from the class lists, your
  past visits, friends' bookings and the travel time from your saved places (Settings › Places & commute: home,
  work with its days and hours, and how you get around; MapKit travel times on the iPhone, a distance estimate on
  the web). Each pick says why ("2 friends going · 8 min from work · you do Yoga often"). Places never leave the
  device.
- **Skipped a habit?** (iPhone, needs the [server](server/README.md#skipped-a-habit)): did the same class 3 weeks
  in a row, then skipped it and booked nothing for 4 days (a Saturday class: by Wednesday; 2 or 7 days in Menu › Auto-book)? A morning push
  "Missing your Saturday morning Reformer?" names up to three upcoming classes picked from your history; tapping it
  opens the best one on top of For you. Menu › Auto-book › "Suggest classes when I skip a habit" turns it off.
- **Milestones** (iPhone and web): your 10th, 25th, 50th and 100th class, 5, 10 and 25 studios, the first class in a
  new category and 4-, 8- and 12-week streaks, each with its own SF Symbol badge: a Home card when one is fresh
  (with Share), and all of them under Statistics. Computed on the device from the visit history.
- **New to you** (iPhone and web): studios you never checked in at, within your plan, in categories you do or close
  by, as a Home row; a **"Try new studios"** monthly goal counts first visits at new studios.
- **Races** (iPhone, Mac and web): about 30 Nordic races of the 2026–27 season (running, HYROX, obstacle, ski, bike
  and swim, triathlon) in a hand-curated catalog, [`docs/app/races.json`](docs/app/races.json) (see
  [Race catalog](#race-catalog)). **Explore › Races** lists them by month with type chips, a country filter, search and
  a pill with today's entry fee or the sign-up status ("2,685 SEK until 5 Nov", "Sold out", "Opens 25 Nov"). A
  **race page** has the date, distances, days to go, where sign-up happens and the day the facts were checked, the
  known price steps, and a link to the race's own page: Brüce never signs you up, takes payment or reads a
  registration platform, and every race page says it is not affiliated with the organiser. **My races** (My classes ›
  Races, and on the Mac a fourth tab) follows races from the list or races you add by hand (name, date, city, link),
  with your day of a multi-day event and your start ("Doubles Open"); Home shows the **next race** with its countdown
  above Spotlight. **Add to Calendar** makes an all-day event (EventKit on iPhone and Mac, an .ics file on the web).
  The iPhone and Mac can remind you at 09:00 when **sign-up opens** and the day before the **next price step**, each
  switched on per race (local notifications). My races stay on the device.
- **Train for it** (iPhone, Mac and web; see [Train for it](#train-for-it)): the race page's own action turns a race
  in My races into a weekly **class mix** of Bruce classes up to race day: Base, Build, Peak, race week and a
  recovery week, as a phase strip and a weeks × categories grid you can change week by week, with 2 to 6 classes a
  week. My classes › Races shows the week ("Week 3 of 10 · Base") and **This week** with each planned class Done,
  Booked, Auto-book (a weekly rule books it) or a class near you to **Book** (hold for Book every week); Home's Next
  race card adds the week and the next class to book. Race week offers to pause weekly bookings of hard classes. The
  plan can make this month's **monthly goals**, and **race week** (Monday 08:00) and **the day before** (18:00)
  reminders come as notifications, or with the server on as a push and an email. It is not coaching: it doesn't
  plan long runs, rides or swims and says so.
- **Monthly goals** (iPhone and web): e.g. 20 gym visits and 2 swims a month, counted from your checked-in
  visits, with pace, a streak and a calendar of the month, on My classes and under Statistics. Goals stay on the
  device; with the server on, "Reminder when behind" sends a push.
- **Challenges with friends** (iPhone and web, needs the [server](server/README.md#challenges-with-friends)):
  most classes, visits or minutes, or everyone hits a number, for a month (optionally repeating) or a date range.
  Friends are invited by push or a share link and each accepts separately; participants see each other's totals,
  class types and studios, a leaderboard, daily and monthly stats.
- **Brüce Wrapped** (iPhone and web): your year so far as full-screen animated story cards, any time of the year:
  visits counting up, months, your class personality, favourite studio, top time of day, streak, the friend you
  trained with most, how you compare with other Brüce users (anonymous percentiles from the server), and a share
  image.
- **Home Screen and Lock Screen widgets** (iPhone): *Next class* (time, studio and the free-cancel deadline, which
  turns amber and red at the strike steps), *Visits left* (a ring with this month's remaining visits) and a Lock
  Screen *Check in* button, plus a Control Center control. They read a snapshot the app writes into an App Group;
  no login or token ever enters the widget extension, and the button and control only **open** the quick check-in
  sheet, where check-in stays confirmed and location-aware. Every face says "Brüce (unofficial)".
- **Live Activity for today's class** (iPhone): from 90 minutes before a booked class the Lock Screen and Dynamic
  Island show "Leave by 17:42 · 12 min by bike" (MapKit travel time from where you are, or from home, by your
  commute mode), then "Check-in open until 18:10" with a **Check in** button that opens the app, then the checked-in
  ticket. Started and updated while the app runs (no push); the countdowns tick on their own. Nothing is checked in
  from the Lock Screen.
- **Apple Health** (iPhone): Settings › Apple Health saves every class you attended as a workout, with the
  workout type guessed from the class and its category (Hyrox as HIIT, yoga, cycling, swimming…), start and end
  time and estimated active calories (MET value × duration × your weight from Health, else 75 kg). Solo gym visits
  count as 60-minute strength workouts (can be switched off); sauna and spa visits are left out. The whole history
  is added the first time, then new visits whenever the app opens. A class your Apple Watch already recorded is
  not added again.
- **Friends' classes**, bookmarks, favourites, membership, credits, strikes,
  receipts, and notification and social settings.
- **Siri and Shortcuts** (App Intents): ask "What's my next class in Brüce", "Book a class in Brüce"
  (one of your saved classes), "Cancel a class in Brüce", "How many visits do I have left in Brüce" or
  "Check in with Brüce" (opens the quick check-in sheet). Booking and cancelling ask you to confirm first, and
  a cancel past the late-cancel time warns that it may count as a strike. Siri also accepts "Bruce" as the
  app name. On the Mac the actions only show up in Shortcuts when the app runs as a bundled `.app`; `swift
  run` does not register them.
- **Fast:** studios stream in page by page, then load in parallel and are cached on disk. Class days load
  in parallel time windows, and images are cached and downsampled. Measurements are in the
  [iOS README](Bruce-iOS/README.md#performance-measured-against-the-public-endpoints-logged-out-simulator).
- **Offline demo mode** for screenshots and UI work (see below).

Account changes, membership plans, pausing, checkout, payments, vouchers, sign-up and password reset are
**display-only**: they show the screens but never send a request. Buying tickets and drop-in classes is
deliberately not implemented.

### iOS: Liquid Glass

The iPhone app uses iOS 26's Liquid Glass design: a glass tab bar that minimises on scroll, glass
toolbars, `.glassEffect()` cards, chips and capsules grouped in `GlassEffectContainer`s,
`.glassProminent` lime and red action buttons, glass partial-height sheets, soft scroll-edge effects, and a
full-screen camera Check in tab with clear-glass overlays. It supports light and dark mode. Details are in
[Bruce-iOS/README.md](Bruce-iOS/README.md#liquid-glass).

**Dynamic Type and VoiceOver:** every text in the iPhone app follows Settings › Display & Brightness › Text Size and
the accessibility sizes (the design sizes scale with the nearest text style, up to twice their size so layouts hold),
row time columns scale with it, and icon-only controls, chips, pills and friend faces carry VoiceOver labels.

### macOS

A 390×780 phone-sized window that recreates the mobile app on the Mac, including camera QR scanning
(AVFoundation and Vision) and freehand area drawing with the mouse.

### Web

[djui.github.io/bruce/app](https://djui.github.io/bruce/app/) runs in any modern browser, on a phone too (it can be
added to the home screen). It calls `api.bruce.app` straight from the page, with the same routes and parameters as
the Swift apps: the API answers CORS requests with `Access-Control-Allow-Origin: *`, so no proxy is needed.

It follows the iOS app's look (wide uppercase titles, lime actions, glass buttons, photo cards, light and dark
mode) and uses the extra room a browser has. On a phone it has the same five tabs in a floating tab bar. From
900px wide there is a sidebar, and the list and the selected class or studio sit side by side; with nothing
selected, Explore shows the city's studios on a map next to the list.

- **Home**: reviews to give, your next class with a Check in button, your next race, Spotlight, categories, nearby and new studios.
- **Explore**: Studios, Classes and Races with counts, search (studio, class, instructor; race, city, distance),
  favourite, category and "Free spots" filters, 7 days of classes, and a studio map.
- **Class page**: time, instructor, spots, notices, the booking rules (book until, check-in window, cancel until),
  friends and classmates booked, Invite friends, facilities, and Book, Cancel booking, Add to Calendar (an .ics
  file), Join or Leave waitlist, Similar classes, Check in, Show ticket and Rate the class. Booking and cancelling
  show the strike rules first.
- **Studio page**: opening hours, notices, Parakey door note, facilities, description, map with Apple and Google
  Maps links, classes per day, a favourite toggle, the visit limit for your plan, and reviews with a rating summary.
- **Check in**: suggests the studio whose check-in window is open, or the last visited one, then does one
  check-in request and shows the ticket. Scan the door QR code with the camera (BarcodeDetector, or jsQR where
  that is missing) or type the code. Studios that open with Parakey still need the Parakey app.
- **Races**: Explore › Races, race pages with the price steps and the official link, My classes › Races (kept in
  localStorage), the next race on Home, and Add to Calendar as an .ics file. **Train for it** with the plan sheet,
  This week and Book (no Book every week: the web has no weekly auto-book), monthly goals from the plan, and race-week
  reminders sent by the server while it is on.
- **Friends** (their upcoming classes), **My classes** (bookings, waitlist, bookmarks under Classes; your races under
  Races) and **Notifications**.
- **Account menu**: plan, visit meters and strikes, statistics (visits per month and the visits behind each bar),
  payments with PDF receipts, invite codes, and settings (city, appearance, social visibility, notification
  types, API server, calendar subscription).
- **Demo**: "Try the demo" on the login screen runs the whole app against an in-browser fake of the API
  ([`docs/app/js/demo.js`](docs/app/js/demo.js)) with placeholder data; nothing is sent anywhere.

Push notifications still go to the official app. The code is plain ES modules in
[`docs/app/js/`](docs/app/js); [Leaflet](https://leafletjs.com) and [jsQR](https://github.com/cozmo/jsQR) are
vendored in [`docs/app/vendor/`](docs/app/vendor), so the page loads nothing from a CDN (map tiles come from
OpenStreetMap, the Unbounded font from Google Fonts). To try it locally, serve `docs/` (for example
`python3 -m http.server -d docs`) and open `http://localhost:8000/app/`. GitHub Pages publishes `docs/` from
`main`, so a merge deploys it.

## Race catalog

[`docs/app/races.json`](docs/app/races.json) is the one list of races all three apps read: GitHub Pages publishes it at
[djui.github.io/bruce/app/races.json](https://djui.github.io/bruce/app/races.json), the iPhone and Mac apps fetch it
(at most every 6 hours) and keep the last good copy, and the web app reads it next to its page. Demo mode uses a slice
of it built into the apps and never fetches it. Each race:

| Field | |
|---|---|
| `id` | Stable, lower case with dashes, with the year (`tough-viking-stadion-2027`). My races and, later, friends refer to it |
| `name` | Plain text, as the organiser writes it. No logos, no brand colours, nothing that suggests Brüce speaks for the race |
| `type` | `running`, `hyrox`, `obstacle`, `endurance` (with `sport`: `ski`, `bike` or `swim`) or `triathlon` |
| `date`, `endDate` | Local race days, `YYYY-MM-DD`; `endDate` only for multi-day events |
| `city`, `country`, `venue` | `country` is `SE`, `NO` or `DK` |
| `distancesKm`, `format` | Distances in km (may be empty) and a few words ("solo, duo, trio or team", "15-leg relay") |
| `signupUrl` | The race's own page (https), never a registration platform's API |
| `platform` | The named sign-up platform ("RaceID", "Haku"); left out when the race runs its own sign-up |
| `priceNote`, `priceSteps` | The fees as the page words them, and the known steps `{from, until, amount, currency, lowest, per}` (days inclusive; `lowest`: "From 799 SEK"; `per`: "per team") |
| `status`, `opensOn` | `open`, `opensSoon` (with `opensOn`), `soldOut`, `lottery` or `checkSite` (when the page was unclear) |
| `klassiker`, `resultsUrl` | A leg of En Svensk Klassiker; a link to the official results (optional) |
| `checkedOn` | The day the facts were read off the race's own page, shown on every race page |

`node --test docs/app/test/` validates the file (unique ids, real dates, `endDate` on or after `date`, known values,
https links, sorted by date, price steps that don't overlap) and checks that the demo races match it. Apps skip an
entry they can't read (a new type, say) instead of failing on the whole file.

**Upkeep** (about an hour a season, a few minutes a month): run the link check by hand, then fix what it reports by
reading the race's own page and editing `races.json` in a pull request with a new `checkedOn`:

```sh
node scripts/check-races.mjs                 # every race
node scripts/check-races.mjs --only vasaloppet-2027
node scripts/check-races.mjs --dry-run       # only reads robots.txt, lists what it would fetch
```

[`scripts/check-races.mjs`](scripts/check-races.mjs) reads each host's robots.txt once and honours it for its
`BruceRaceCheck` user agent (a crawl delay over a minute means "check by hand"), never contacts registration or results
platforms (vivenu, RaceID, Haku, njuko, Onreg, Sportstiming, EQ Timing, RACE RESULT, Let's Do This, Ahotu), sends one
GET per link with a named User-Agent and reports the HTTP status and whether the race date appears on the page. It
never edits the catalog and nothing runs it automatically.

**Not planned:** selling entries, affiliate links, scraped results, Strava sync, pace coaching, races outside Sweden,
Norway and Denmark (for now).

## Train for it

[`Shared/BruceCore/RacePlanner.swift`](Shared/BruceCore/RacePlanner.swift) (and the same logic in
[`docs/app/js/raceplan.js`](docs/app/js/raceplan.js), tested with the same cases) turns a race day into weeks:

- **The block** ends in race week (the ISO week of your day of the race) and is 10 weeks by default (4 to 16), never
  starting before the week you started the plan. Race week is last, Peak the two weeks before it, Build about a third
  of the rest, Base the remainder; a block of six weeks or fewer (a race under six weeks away) skips Base, and very
  short ones keep Peak, then Build. One recovery week follows race week.
- **The class mix** per race type, by Bruce category id with a title fallback (ids as in the demo data; when the API's
  list has the id under another title, a category with a matching title or code is used instead):

| Race type | Categories (id) | A Build week with 4 classes | Race week | Recovery |
|---|---|---|---|---|
| HYROX | Hyrox 13, Strength 26, Running 23, High-intensity 12, Mobility 16 | 2 Hyrox, 1 Strength, 1 Running | 1 Hyrox, 1 Mobility | Mobility, Sauna 24 |
| Running | Running 23, Cycling 9, Strength 26, Mobility 16, Yoga 2 | 1 Running, 1 Cycling, 1 Strength, 1 Mobility | 1 Mobility | Massage & Naprapathy 15, Mobility |
| Obstacle | Strength 26, CrossFit 8, Climbing 7, Running 23, Outdoor 18 | 1 Strength, 1 CrossFit, 1 Climbing, 1 Running | 1 Climbing, 1 Mobility | Mobility, Sauna |
| Ski | Cardio 6, Strength 26, Cycling 9 | 2 Cardio, 1 Strength, 1 Cycling | 1 Cardio, 1 Mobility | Mobility, Sauna |
| Bike | Cycling 9, Strength 26, Cardio 6 | 2 Cycling, 1 Strength, 1 Cardio | 1 Cycling, 1 Mobility | Mobility, Sauna |
| Swim | Swimming 27, Strength 26, Cardio 6 | 2 Swimming, 1 Strength, 1 Cardio | 1 Swimming, 1 Mobility | Mobility, Sauna |
| Triathlon | Swimming 27, Cycling 9, Running 23, Strength 26 | 1 each | 1 Swimming, 1 Mobility | Mobility, Sauna |

- **Your changes**: the number of classes a week (2 to 6, for Base, Build and Peak) and the count of any category in
  any week ahead (the grid). They are saved with the race in My races (`plan`: `startedOn`, `weeks`, `perWeek`,
  `edits` as `"<Monday>|<category>"`), so a file from an older version still loads and one with an unreadable plan
  keeps the race.
- **This week** counts your check-ins (the visit history goals and Statistics read) and bookings: each fills a slot
  of one of its categories. Open slots get a class from the city schedule for the rest of the week, ranked like For
  you (your places and commute, history, friends), within your visit limits, your plan's tiers and the selected area,
  one class per slot, preferring days without another class and classes still free to cancel (a class inside the
  free cancellation shows "Cancelling costs a strike"). **Book** opens the usual booking rules sheet; **Book every
  week** is the existing auto-book with its late-spot rule. In race week only classes before race day are
  suggested, and from the week before race week My classes offers to **pause** weekly bookings of hard classes
  (Hyrox, Strength, High-intensity, CrossFit) until race day is over; nothing is cancelled without you.
- **Monthly goals** from the plan: this month's planned classes per category (a week counts for the month its
  Thursday is in, the four biggest categories) become monthly goals with "Reminder when behind"; their targets
  follow the plan each month and they go when the plan stops or ends. A category you already have a goal for keeps
  yours, and a plan goal you delete stays deleted.
- **Reminders**: race week (08:00 on the Monday; for a race on a Monday either switch means the evening before) and
  the day before (18:00), each switched on per race. On the device they are local notifications; with the server on,
  each device sends its races with `PUT /me/races` and the server pushes them (the race-week one also by email, with
  what you booked that week), and the device leaves out the ones the server confirmed
  ([server/README.md](server/README.md#race-reminders)).

## Repository layout

```
.
├── API.md                  Human-readable API map, with evidence references
├── openapi.yaml            OpenAPI 3.0 description of the same endpoints
├── swagger.html            Offline-friendly Swagger UI viewer (spec embedded)
├── docs/                   GitHub Pages site: landing page, screenshots, app/ (web version), api/ (Swagger UI + openapi.yaml copy)
├── Shared/BruceCore/       Shared Swift code (API, models, AppModel, TokenStore, logic, demo data)
├── scripts/check-races.mjs Hand-run link check for the race catalog (docs/app/races.json)
├── Bruce-MacOS/            SwiftPM package, executable target BruceMacOS
│   ├── Package.swift
│   ├── Sources/BruceMacOS/ macOS views; Shared -> ../../../Shared/BruceCore (symlink)
│   └── Support/Info.plist  Embedded for the camera permission prompt
├── Shared/BruceWidgetKit/  Widget snapshot and faces, compiled into the app and the widget extension
└── Bruce-iOS/              Xcode project for the iPhone app "Brüce"
    ├── BruceiOS.xcodeproj  Folder-synchronised groups; also compiles ../Shared/BruceCore
    ├── BruceiOS/           iOS views and assets
    ├── BruceWidgets/       Widget extension: Home Screen widgets, Lock Screen accessories, check-in Control
    ├── Config/             Base.xcconfig, Info.plist, ExportOptions.plist, Local.xcconfig.example
    ├── scripts/            testflight.sh, make-icon.swift
    └── .env.example        Template for TestFlight credentials
```

## Building and running

There are no third-party dependencies, only Apple frameworks.

### macOS app

Requires macOS 14+ and Xcode 16+ (Swift 5.9+).

```sh
cd Bruce-MacOS
swift build
swift run BruceMacOS
swift test            # unit tests for the shared logic in Shared/BruceCore (Bruce-MacOS/Tests/BruceCoreTests)
```

### iOS app

Requires Xcode 27 (iOS 27 SDK). The deployment target is iOS 26.0, iPhone only.

```sh
cd Bruce-iOS
open BruceiOS.xcodeproj
# or build for the simulator from the command line:
xcodebuild -project BruceiOS.xcodeproj -scheme BruceiOS \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

Simulator builds need no signing setup. To run on a device, copy `Config/Local.xcconfig.example` to
`Config/Local.xcconfig` (git-ignored) and set your `DEVELOPMENT_TEAM`, plus your own
`BRUCE_BUNDLE_ID` if you don't own `net.dauernheim.bruce` (the widget extension becomes `<id>.widgets`).

### Demo mode (developer switch)

`BRUCE_DEMO=1` runs either app with fictional placeholder data: no API calls, no remote images, and no
map tiles except on the custom-area drawing map, which needs Apple Maps to draw on. Book, cancel and check-in only change local state. `BRUCE_SCREEN=<name>` opens a
specific screen (`explore`, `classes`, `studio`, `detail`, `checkin`, `friends`, `myclasses`, `account`,
`settings`, `welcome`, `mybookings`, `similar`, `alerts`, `area`, `races` (Explore › Races), `race` (a race page),
`myraces` (My classes › Races with This week of a plan in week 3 of 10), `myrace` (a race in My races), `addrace`
(add a race by hand), `trainforit` (a race page with Train for it), `planstart` (the plan sheet before starting),
`raceplan` (the plan sheet in week 3 of 10), …; the full list is in
[`Shared/BruceCore/Demo.swift`](Shared/BruceCore/Demo.swift)). Demo Home shows the Next race card with the plan's week.
Demo mode is not reachable from the UI.

```sh
# macOS
BRUCE_DEMO=1 BRUCE_SCREEN=studio swift run BruceMacOS
# iOS simulator (after building and installing the app)
SIMCTL_CHILD_BRUCE_DEMO=1 SIMCTL_CHILD_BRUCE_SCREEN=studio xcrun simctl launch booted net.dauernheim.bruce
```

In Xcode, enable the `-BRUCE_DEMO 1` launch argument in the BruceiOS scheme. `BRUCE_DEMO_ASSETS=1`
additionally allows public studio images and Apple map tiles in demo mode.

> [!WARNING]
> Outside demo mode there is no dry run. **Book, Cancel and Check in send real requests** to Bruce Studios
> for your account, with the same consequences as in the official app (credits, late-cancellation strikes,
> door check-ins).

### TestFlight

[`Bruce-iOS/scripts/testflight.sh`](Bruce-iOS/scripts/testflight.sh) archives, exports and uploads a build
for internal TestFlight testing, using an App Store Connect API key for automatic signing. Your team and key
IDs are never committed; they live in a git-ignored `.env`:

```sh
cd Bruce-iOS
cp .env.example .env                 # set TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID
# key file: ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (or set ASC_KEY_PATH)
scripts/testflight.sh                # archive + upload
scripts/testflight.sh --no-upload    # archive + export an .ipa locally
```

You need your own App Store Connect app record. Set `BUNDLE_ID` and `BRUCE_BUNDLE_ID` to its
bundle ID. See the [iOS README](Bruce-iOS/README.md#testflight) for all variables.

## API documentation

- [`API.md`](API.md): every observed endpoint with parameters, request and response shapes, and the
  booking, check-in and visit-limit rules the apps rely on. It also lists what has *not* been observed
  (plan changes, invite responses, and so on), and that the API has no token refresh call.
- [`openapi.yaml`](openapi.yaml): OpenAPI 3.0 description of the core endpoints.
- [`swagger.html`](swagger.html): open it in a browser for an interactive Swagger UI with the spec
  embedded. Swagger UI is loaded from the jsDelivr CDN.

Base URL `https://api.bruce.app/v52/`. Authentication is a single `X-Access-Token` header, obtained from
`POST /v52/access/authenticate`.

### How the API was mapped

The API was mapped by **observing the author's own account traffic**. The official iOS app was used
normally on the author's own device, and its HTTPS requests were recorded with
[Charles Proxy](https://www.charlesproxy.com). Endpoints, parameters and response shapes were then read
off those recordings.

- The app binary was not decrypted, disassembled or modified, and no certificate pinning or other
  protection was bypassed. The only other source was the plain resource files in the installed app
  bundle (localized UI strings and the Core Data model's entity names), read to confirm that the official
  app stores no refresh token and how its rating dialog behaves.
- No other members' accounts were accessed.
- Write calls were documented only where the author performed the action in the official app. Anything
  not observed is marked as such.

The raw captures contain the author's credentials and personal data, and some data about other members,
so they are **not** included in this repository. Examples in the docs use placeholders (`<USER_ID>`,
`<ACCESS_TOKEN>`, …) or public studio data.

## Privacy

- The apps talk only to Bruce Studios' own servers (`api.bruce.app`, and Cloudinary for studio images),
  plus Apple Maps. There is no analytics, tracking or third-party SDK. The race list is read from this project's
  own GitHub Pages site (`djui.github.io/bruce/app/races.json`, no data sent); race links open in your browser.
- My races, their reminders, Train for it plans and your race notes stay on the device (Application Support on
  iPhone and Mac, localStorage on the web). Only with the server on and a race-week or day-before reminder switched on
  does a race (its id, name, your day and the plan's race-week mix) go to the server, which deletes it with your
  account.
- Your password is sent once to log in and never stored. The session tokens are stored only in the
  Keychain (iOS service `net.dauernheim.bruce`; macOS `net.dauernheim.BruceMacOS`). Log out removes them.
- Location (iOS, when in use) is used on the device for distances and the check-in suggestion. The
  approximate coordinates are sent to Bruce's home-screen endpoint for "Nearby gyms", as the official app
  does.
- Translation uses Apple's Translation framework, which translates on the device. The system may download
  a language model the first time; the texts themselves are not sent to any translation service.
- Apple Health (iOS, off until you switch it on): the app writes workouts and reads only your latest weight
  and other apps' workouts at the same time, on the device. Nothing from Health is sent anywhere.
- Cached studio lists, images and custom areas are stored locally in the app's caches and Application
  Support folders.
- The web version keeps its access token, settings and a cached studio list in the browser's localStorage for
  djui.github.io; it sends the token only to `api.bruce.app`. Log out removes the token. The camera is used only
  while the QR scanner is open, and the frames stay in the browser.
- No personal data is hard-coded. Demo data is fictional.

## Responsible use

- **Use it only with your own account.** Don't use it to access anyone else's data.
- **Respect Bruce Studios' terms of service and membership rules.** Bookings, cancellations and check-ins
  made with this app are real and count like any others. Only check in where you are physically present.
- **Don't automate abuse:** no bulk booking, scraping, load testing, or circumventing limits, strikes or
  payments. The apps make the same kinds of requests at a similar rate as the official app; please keep it
  that way. Auto-book is the one exception to "only by hand", and it stays within that: for your own
  account, it sends the single booking request you would send yourself for a class you attend every week,
  at the moment booking opens, and tries each class once. Don't use it to hold spots you won't use; cancel
  in time if you can't make it.
- If Bruce Studios asks for this project to change or be taken down, the author will comply.

## Notice and trademarks

The [MIT license](LICENSE) covers **only the code and documentation written for this repository**.

- "Bruce Studios", "Bruce", their logos and the look of the official app are trademarks or property of
  Bruce Studios AB. No rights to them are granted.
- The apps load studio names, descriptions, photos, schedules and reviews **at runtime** from Bruce
  Studios' servers. None of that content is redistributed here. The studio photo IDs, studio and door IDs
  and the public studio address used as examples identify public places, not people.
- All help, rule and policy texts are written for this project in its own words
  ([`Shared/BruceCore/Copy.swift`](Shared/BruceCore/Copy.swift)). Where the API returns the facts (strike-unblock
  price, pause allowance, free unlocks, plan prices and limits, invite codes, notification descriptions), the
  texts are built from that live data. Short generic labels such as "Book" or "Check in" are kept.
- The landing page and screenshots in [`docs/`](docs) show only demo-mode data and an original "Ü" mark. The web
  app uses the same original iOS app icon (see below).
- **Trademark-sensitive asset:** the iOS app icon
  ([`Bruce-iOS/BruceiOS/Assets.xcassets/AppIcon.appiconset`](Bruce-iOS/BruceiOS/Assets.xcassets/AppIcon.appiconset))
  is an original rendering generated by [`scripts/make-icon.swift`](Bruce-iOS/scripts/make-icon.swift): a
  gradient in colours similar to the official icon with a system-font "Ü". It contains no Bruce artwork, but
  it deliberately evokes the original brand. If you distribute a build, replace it with your own icon.
- The home-screen name "Brüce" and the "Unofficial client" label are there so the app cannot be mistaken
  for the official one. Please keep the app clearly marked as unofficial if you fork it.

## Credits

- **[Bruce Studios](https://www.brucestudios.com)** for the service, the studios, and the original app whose
  design and screen structure these clients follow.
- **Apple** for SwiftUI, Liquid Glass, SF Symbols (used for all icons, under Apple's SF Symbols license
  terms), MapKit, AVFoundation and Vision.
- **[Leaflet](https://leafletjs.com)** (BSD 2-Clause) and **[jsQR](https://github.com/cozmo/jsQR)**
  (Apache 2.0), vendored with their licenses in [`docs/app/vendor/`](docs/app/vendor), and
  **[OpenStreetMap](https://www.openstreetmap.org/copyright)** contributors for the map tiles (ODbL).
- **[Unbounded](https://fonts.google.com/specimen/Unbounded)** (SIL Open Font License) for the web app's titles.
- **[Charles Proxy](https://www.charlesproxy.com)** by Karl von Randow, used to observe the traffic.
- **[Swagger UI](https://github.com/swagger-api/swagger-ui)** (Apache 2.0), loaded by `swagger.html` and the
  [online API viewer](https://djui.github.io/bruce/api/).
- **Author:** Uwe Dauernheim ([@djui](https://github.com/djui)).
- Built with **[Claude Code](https://claude.com/claude-code)**.

## License

[MIT](LICENSE) © 2026 Uwe Dauernheim. See [Notice and trademarks](#notice-and-trademarks) for what the
license does not cover.
