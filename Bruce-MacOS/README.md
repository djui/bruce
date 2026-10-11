# BruceMacOS

A small SwiftUI macOS app for Bruce Studios: log in, browse all studios and
classes, book/cancel classes, and check in at a door. API details: [`../API.md`](../API.md).
Back to the [project README](../README.md) · iPhone version: [`../Bruce-iOS`](../Bruce-iOS/README.md).

> **Unofficial.** Not affiliated with or endorsed by Bruce Studios AB. "Bruce Studios" is their trademark.

## Build & run

Requires macOS 14+ and a Swift 5.9+ toolchain (Xcode 16 or later).

```sh
cd Bruce-MacOS
swift build
swift run BruceMacOS
```

## Shared code

API client, models, Keychain session, `AppModel`, demo data and booking-rule helpers live in
`../Shared/BruceCore/` and are compiled here through the symlink `Sources/BruceMacOS/Shared` (also used by
`../Bruce-iOS`). Demo mode also accepts the launch argument `-BRUCE_DEMO 1`.

## UI

A phone-sized (390x780) SwiftUI recreation of the Bruce iOS app: tab bar
Home / Explore / Check in / Friends / My classes, class + studio pages, and
sheets for Notifications, the menu, Account (Membership, Wellness, Total monthly
visits, Credits, Strikes, Payment methods) and Settings. Account/payment pages
are display-only.

- Offline preview with placeholder data (no network): `BRUCE_DEMO=1 swift run`,
  optionally `BRUCE_SCREEN=explore|classes|detail|studio|friends|myclasses|notifications|menu|account|membership|wellness|credits|strikes|payment|settings|checkin|categories|filter|selectcity|newarea|search|map|welcome|createaccount|login|reset|sneakpeek`.
- Logged out: welcome screen (Create account, Log in, Sneak peek). Login calls `POST /v52/access/authenticate`; create account, reset password and Apple/Google sign-in are display-only.
- Check in tab: camera QR scanning (AVFoundation + Vision; Info.plist embedded via a
  linker flag for the camera prompt). Home top bar: check-in list of booked classes and
  gyms with a known door (studio `qr_code_id`, plus an internal door map for two STC gyms).

## How it works

- **Login (Account tab):** `POST /v52/access/authenticate` with email + password
  (`authenticator: "PASSWORD"`). Access token, refresh token, expiries and user id
  are stored in the macOS Keychain (`net.dauernheim.BruceMacOS` / `bruce-session`);
  the password is never stored. Access tokens last ~3 h. No refresh call has been
  captured yet, so an expired token means logging in again. `BRUCE_ACCESS_TOKEN`
  env var still works.
- **Studios:** logged in -> full list via `GET /v52/studio/filter` (paged, live, SE).
  Logged out -> public `GET /v1/studios` (~100). "Check-in capable" = live and a
  `stc:<major>` QR code or a door integration. Saved doors are starred.
- **Classes tab:** `GET /v52/class` for a day, city-wide (Stockholm) or for the
  picked studio. Book = `POST /v52/booking`.
- **Account tab:** your bookings (`GET /v52/booking`), cancel = `DELETE /v52/booking/<id>`.

## Account screens

Edit profile, Pause membership (with the date-range picker), Membership plans and Checkout are
**display-only**: Save, Done, Upgrade, Pay and New payment method never call an endpoint. The ID
number is masked as `YYYYMMDD-****`. Wired for real (user-initiated): book/cancel, waitlist
join/leave, bookmarks, favourites, check-in, notification/marketing toggles and the Social toggle.

## Safety

There is no dry-run mode: **Book, Cancel booking and Check in send real requests** when you click
them (Book/Cancel go through the booking-rules sheet; check-in asks for confirmation first).
`BRUCE_DEMO=1` is fully offline: no API calls, no remote images or map tiles (set
`BRUCE_DEMO_ASSETS=1` to allow public Cloudinary images and Apple map tiles), and Book/Cancel/
Check-in only change local demo state.
