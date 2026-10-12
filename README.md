# Bruce: unofficial macOS and iOS clients for Bruce Studios

Native SwiftUI clients for the [Bruce Studios](https://www.brucestudios.com) fitness membership (Sweden, Norway,
Denmark), plus a reverse-engineered map of the app's v52 HTTP API.

**Project page: [djui.github.io/bruce](https://djui.github.io/bruce/)** · [API viewer](https://djui.github.io/bruce/api/)

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
| **BruceCore** ([`Shared/BruceCore/`](Shared/BruceCore)) | Code shared by both apps: API client, models, Keychain session, app state, booking rules, demo data |
| **API map** ([`API.md`](API.md), [`openapi.yaml`](openapi.yaml), [`swagger.html`](swagger.html)) | The Bruce Studios v52 API as observed from the official iOS app 14.4.2 |

## Features

Both apps follow the structure of the official app screen by screen: Home, Explore, Check in, Friends and
My classes tabs, with class and studio pages and account sheets.

- **Log in** with your Bruce Studios email and password. Only the session tokens are kept, in the Keychain.
- **Explore** all live studios (about 700 in Sweden) and the city-wide class schedule, with category,
  tier, Wellness and favourite filters, search, a map, and **custom areas**: draw an outline on the map and
  filter studios and classes to it. As in the official app, areas stay on the device.
- **Book, cancel and join waitlists** through a booking-rules sheet that shows the "book until",
  "cancel until" and check-in windows. Waitlist entries that turn into a spot show as booked.
- **Visit limits:** tap the visits pill (e.g. "1/1") for visits used and left, the reset date and each
  plan's limit at the studio. A class over your limit shows its drop-in price ("Buy for SEK 220").
- **Check in** by scanning the studio's door QR code with the camera, or with one tap from a suggestion
  (a booked class whose check-in window is open, the nearest studio, or the last one you visited).
  Every check-in asks for confirmation first.
- **Studio pages** show opening hours ("Solo training until 22:00"), notices, facilities, reviews, photos,
  per-studio visit limits and classes.
- **Friends' classes**, bookmarks, favourites, notifications, statistics, membership, credits, strikes,
  receipts, and notification and social settings.
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

### macOS

A 390×780 phone-sized window that recreates the mobile app on the Mac, including camera QR scanning
(AVFoundation and Vision) and freehand area drawing with the mouse.

## Repository layout

```
.
├── API.md                  Human-readable API map, with evidence references
├── openapi.yaml            OpenAPI 3.0 description of the same endpoints
├── swagger.html            Offline-friendly Swagger UI viewer (spec embedded)
├── docs/                   GitHub Pages site: landing page, screenshots, api/ (Swagger UI + openapi.yaml copy)
├── Shared/BruceCore/       Shared Swift code (API, models, AppModel, TokenStore, logic, demo data)
├── Bruce-MacOS/            SwiftPM package, executable target BruceMacOS
│   ├── Package.swift
│   ├── Sources/BruceMacOS/ macOS views; Shared -> ../../../Shared/BruceCore (symlink)
│   └── Support/Info.plist  Embedded for the camera permission prompt
└── Bruce-iOS/              Xcode project for the iPhone app "Brüce"
    ├── BruceiOS.xcodeproj  Folder-synchronised groups; also compiles ../Shared/BruceCore
    ├── BruceiOS/           iOS views and assets
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
`PRODUCT_BUNDLE_IDENTIFIER` if you don't own `net.dauernheim.bruce`.

### Demo mode (developer switch)

`BRUCE_DEMO=1` runs either app with fictional placeholder data: no API calls, no remote images, and no
map tiles except on the custom-area drawing map, which needs Apple Maps to draw on. Book, cancel and check-in only change local state. `BRUCE_SCREEN=<name>` opens a
specific screen (`explore`, `classes`, `studio`, `detail`, `checkin`, `friends`, `myclasses`, `account`,
`settings`, `welcome`, `mybookings`, …; the full list is in [`Shared/BruceCore/Demo.swift`](Shared/BruceCore/Demo.swift)).
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

You need your own App Store Connect app record. Set `BUNDLE_ID` and `PRODUCT_BUNDLE_IDENTIFIER` to its
bundle ID. See the [iOS README](Bruce-iOS/README.md#testflight) for all variables.

## API documentation

- [`API.md`](API.md): every observed endpoint with parameters, request and response shapes, and the
  booking, check-in and visit-limit rules the apps rely on. It also lists what has *not* been observed
  (token refresh, review submission, plan changes, and so on).
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
  protection was bypassed.
- No other members' accounts were accessed.
- Write calls were documented only where the author performed the action in the official app. Anything
  not observed is marked as such.

The raw captures contain the author's credentials and personal data, and some data about other members,
so they are **not** included in this repository. Examples in the docs use placeholders (`<USER_ID>`,
`<ACCESS_TOKEN>`, …) or public studio data.

## Privacy

- The apps talk only to Bruce Studios' own servers (`api.bruce.app`, and Cloudinary for studio images),
  plus Apple Maps. There is no analytics, tracking or third-party SDK.
- Your password is sent once to log in and never stored. The session tokens are stored only in the
  Keychain (iOS service `net.dauernheim.bruce`; macOS `net.dauernheim.BruceMacOS`). Log out removes them.
- Location (iOS, when in use) is used on the device for distances and the check-in suggestion. The
  approximate coordinates are sent to Bruce's home-screen endpoint for "Nearby gyms", as the official app
  does.
- Cached studio lists, images and custom areas are stored locally in the app's caches and Application
  Support folders.
- No personal data is hard-coded. Demo data is fictional.

## Responsible use

- **Use it only with your own account.** Don't use it to access anyone else's data.
- **Respect Bruce Studios' terms of service and membership rules.** Bookings, cancellations and check-ins
  made with this app are real and count like any others. Only check in where you are physically present.
- **Don't automate abuse:** no bulk or scripted booking, scraping, sniping spots, load testing, or
  circumventing limits, strikes or payments. The apps make the same kinds of requests at a similar rate as
  the official app; please keep it that way.
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
- The landing page and screenshots in [`docs/`](docs) show only demo-mode data and an original "Ü" mark.
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
- **[Charles Proxy](https://www.charlesproxy.com)** by Karl von Randow, used to observe the traffic.
- **[Swagger UI](https://github.com/swagger-api/swagger-ui)** (Apache 2.0), loaded by `swagger.html` and the
  [online API viewer](https://djui.github.io/bruce/api/).
- **Author:** Uwe Dauernheim ([@djui](https://github.com/djui)).
- Built with **[Claude Code](https://claude.com/claude-code)**.

## License

[MIT](LICENSE) © 2026 Uwe Dauernheim. See [Notice and trademarks](#notice-and-trademarks) for what the
license does not cover.
