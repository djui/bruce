# Bruce API map (Charles captures 1–8 of the iOS app 14.4.2 build 538)

> Unofficial, reverse-engineered by observing the author's own account traffic. Not affiliated with or
> endorsed by Bruce Studios AB. The raw captures contain personal data and are **not** part of this
> repository; the bracketed evidence numbers below refer to them for the author's own reference.
> Machine-readable version: [`openapi.yaml`](openapi.yaml) (browse it with [`swagger.html`](swagger.html)).

Evidence numbers without a prefix refer to capture 1; `c2:N` refers to capture 2, `c3:N` to capture 3, `c4:N` to capture 4, `c5:N` to capture 5, `c6:N` to capture 6, `c7:N` to capture 7, `c8:N` to capture 8.

Base: `https://api.bruce.app/v52/` (older `/v1/studios` is a separate, unauthenticated public list).
Numbers in brackets are capture file numbers (`N-meta.json` / `N-req.json` / `N-res.*`).

## Common
- Auth: header `X-Access-Token: <ACCESS_TOKEN>` on every v52 call. No `Authorization`/Bearer, no cookies.
- Other headers: `User-Agent: Bruce/<ver>_<build> (iOS<ver>; Apple)`, `Accept-Language`, Sentry `baggage`/`sentry-trace` (optional).
- Almost all calls take `locale=en`; user-scoped calls take `user_id=<USER_ID>`.
- CORS (checked live on 2026-10-14 with `Origin: https://djui.github.io`, `http://localhost:8000` and others): preflights answer 200 with `Access-Control-Allow-Origin: *`, echoing the requested method and headers (`Content-Type`, `X-Access-Token`) in `Access-Control-Allow-Methods`/`-Headers`; GETs carry `Access-Control-Allow-Origin: *` and `Vary: Origin`. No `Access-Control-Allow-Credentials` and no `Access-Control-Expose-Headers`. So a web page can call the API directly with the token in `X-Access-Token` (the web version in `docs/app/` does), but cannot use cookies or read custom response headers such as `X-Cache-Expires`.
- Lists: `{"<items>":[...], "metadata":{"pagination":{count,limit,offset,next_offset,next_cursor,prev_cursor},"cache_expire_seconds"}}`; page with `limit` + `next_cursor` (base64, e.g. `id:<n>`) [75, 86].

## Login / auth (capture 2)
- `POST /v52/access/authenticate` [c2:461] - NO `X-Access-Token` header.
  ```json
  {"authenticator":"PASSWORD","email":"<EMAIL>","password":"<PASSWORD>","locale":"en"}
  ```
  -> 200 `{"user_id":<USER_ID>,"user_created":false,"access_token":"<64 chars>","refresh_token":"<64 chars>","access_token_expires_at":"<ISO8601, ns precision>","refresh_token_expires_at":"<ISO8601>","user_agent":"Bruce/14.4.2_538 (iOS..; Apple)"}`.
  Observed lifetimes: access token 3 hours, refresh token ~3 months. The new access token is used as `X-Access-Token` on all following calls.
- `DELETE /v52/access/logout` [c2:442] header `X-Access-Token`, body `{"locale":"en"}` -> 200, empty body.
- Refresh: none. No request in captures 1-8 sends `refresh_token`, no 401 occurs, and no response header carries a new token. The access token from the c2 login (`access_token_expires_at` 3 h later) was still sent on all 211 requests of capture 8, about 27 h after that time, and every one got 200 [c8]. The official app's local data model stores only the access token (its `Session` entity has `accessToken`, `role`, `user`; no refresh token). So the server does not enforce `access_token_expires_at` in practice, and the clients ignore it: only an HTTP 401 ends the session ("log in again").

## Studios / classes / explore
- `GET /v52/home_screen?coordinates=<lat>,<lng>&locale=en` [46] -> `{sections:[{title,type,items}]}`; types `CATEGORIES`, `SPOTLIGHT` (class_id, class_name, studio_id, studio_name, start_time, distance), `NEARBY_GYMS`, `NEW_STUDIO` (studio_id, studio_name, categories, open_from/open_to, has_openings, opening_hours_schedule_today).
- `GET /v52/category?filter[main][eq]=true&locale=en` [19, 49, 161, 180] -> `{categories:[{id,code,icon,title,main,parent_id,...}]}`.
- `GET /v52/location/city?code=STO&include_country=true&include_booking_methods=true` [43, 44, 115] -> `{cities:[{id,name,time_zone,coordinates,credit_price,booking_methods,country}]}`.
- `GET /v52/studio/user_visit_limit?user_id=` [62, ...] -> `{limits:[{total,used,remaining,within_limit,resets_at,type,items}]}`.
- Full studio list / class schedule: see below (capture 2).

### Studio list (Explore / map) - capture 2
`GET /v52/studio/filter` [c2:153, 162, 170, 178, 184 ... 1098, 1111, 1133; 39 pages]
- Query: `filter[status][in]=live`, `filter[country_code][eq]=se` (later pages `SE`), `fields=checkin_studio_id,city_id,deleted,has_address,has_classes,has_openings,id,integration_door_type,keyword,label,name,photo,qr_code_id,rating,remote,requires_additional_cost,status,tier_level,time_zone,vicinity,visit_limit_id`, `include=addresses,addresses_address,categories,categories_category,visit_limit,photos,photos_photo`, `limit=30`, `locale=en`, `next_cursor=<base64 "id::<n>">`.
- -> `{"studios":[{id,name,photo,status:"LIVE",city_id,vicinity,rating{total,distribution,average},remote,tier_level,qr_code_id,has_classes,has_openings,has_address,time_zone,deleted,requires_additional_cost,studio_addresses[{address{address,city,latitude,longitude,...}}],studio_categories[{category{code,title}}],studio_photos[...]}],"metadata":{"pagination":{"count":0,"limit":30,"next_cursor":"..."}}}`.
- 39 pages = 691 unique studios for SE; the last captured page still had a `next_cursor` (user stopped scrolling), so the end-of-list marker is assumed to be an empty page / missing cursor.
- `qr_code_id` is `"stc:<major>"` for 287 studios (STC gyms; e.g. studio 1724 -> `stc:13994`, 1764 -> `stc:13816`, matching the check-in `major`), otherwise a plain number or hex string. `status` is upper case (`LIVE`).

### Studio detail
- `GET /v52/studio/<id>?include_addresses=true&include_addresses_address=true&include_categories=true&include_facilities=true&include_studio_photos=true&include_studio_photos_photo=true&include_user_booking_limit=true&include_alerts=true&exclude_expired_alerts=true&locale=en` [c2:51, 212, 1015] -> `{"studio":{id,name,description,integration_type,integration_door_type,integration_door_config,qr_code_id,geofencing_enabled,schedule_type,studio_facilities,...}}`.
- `GET /v52/studio/<id>/opening_hour/schedule` [c2:215, 1018] -> `{"schedule":[{id,start,end,is_all_day,opening_hour{start_hour,end_hour,recurring_rule,unmanned},studio_user_attendance_info{admission_access,booking_credit_access,price,trial,visit_limit_reached,...}}]}`.
- `GET /v52/studio/class/alternative_recommendation?class_id=<id>&locale=en` [c2:53, c7:24, c7:41]: "Similar classes" (see capture 7).
- `GET /v52/favorite` [c2:152, 213], `GET /v52/bookmark` [c2:52], `GET /v52/standby` [c2:474], `GET /v52/admission` [c2:423], `GET /v52/membership/info` [c2:426] (context only).

### Class list - capture 2
`GET /v52/class` [c2:20, 28, 30 ... 1142-1144; 506 requests]
- City/day schedule: `studio_city_id=1` (Stockholm), `start_time_after=YYYY-MM-DDT00:00:00`, `start_time_before=<next day>T00:00:00` (local, no zone), `limit=30`, `next_cursor=<base64 "id:<n>">`, plus `is_recurring_base=false&is_master=false&dedicated=false&opening=false&studio_status=live&include_absolute_times=true&include_class_categories=true&include_booking_credit_costs=true&include_dynamic_prices=true&locale=en`. The app pages through each day separately (Oct 11 to Oct 18 captured).
- Per studio [c2:214, 216, 1017, 1019]: `studio_id=<id>&presentation_studio_id=<id>` with UTC range (`...Z`), optional `bookable_earliest_before=<now>`, `include_address=true`, `include_studio_user_attendance_info=true`; `opening=true` returns opening-hour slots instead of classes.
- Day bounds per studio are loose (checked live 2026-10-15, studio 6, Sun 18 Oct): with `studio_id` the API ignores `start_time_before` and also returned classes on 19 and 20 Oct, with or without `presentation_studio_id`, local or `Z` bounds. `presentation_studio_id` alone does not filter by studio. The clients drop classes whose start (city time zone) is not on the chosen day. The city query (`studio_city_id=1`) accepts both local and `Z` bounds and returned the same 517 classes for 18 Oct either way (no classes near midnight to tell them apart).
- -> `{"classes":[{id,studio_id,presentation_studio_id,title,description,start_time,end_time (UTC Z),time_zone,spots,available_spots,canceled,instructor,bookable_earliest,bookable_latest,unbookable_latest,auto_check_in,late_check_in_minutes,early_check_in_minutes,booking_credit_costs{BASE,BLACK,EPIC,FREE},dynamic_prices,class_categories[...]}],"metadata":{"pagination":{...,"next_cursor":"..."},"cache_expire_seconds":55}}`. Class objects carry no studio name; join with the studio list by `studio_id`.
- Soft-deleted classes: the list responses (as sent by the official app, without a `deleted` parameter) include classes with `deleted:true` and a `deleted_at` timestamp. In captures 1–6 that is 931 of 6,453 unique classes (about 14%); 236 of them sit at the same studio and start time as a live class. The official app does not list them. Adding `deleted=false` drops them server-side (checked live on 2026-10-12 against studio 6614: 30 of 30 returned classes were not deleted, without the parameter the same page held a deleted one). Example: class 10893685 ("Signature Reformer - Kod till dörr 8065 - ...", Energii Brunkebergstorg) got `deleted_at` 2026-10-11T20:04:14Z, with its title rewritten before the delete. The clients send `deleted=false` and also drop `deleted`/`deleted_at` rows client-side.
- `instructor` is free text from the studio's booking system. Every Energii class (studios 6481, 6614, 8065, 8626, integration `flexybox`; 243 of 243 in the captures) prefixes it with Markdown bold markers and no closing pair, e.g. `"**Millie Jabol - English speaking"`. This is not a hidden/private flag: those classes are otherwise ordinary live classes. The clients strip the `**`.
- Wellness classes: the class payload has no wellness flag. A class counts as Wellness when its studio has `label:"WELLNESS"` (46 of 691 studios), the same label that drives the Wellness filter and the `WELLNESS_MONTHLY` visit limit. Examples: "Red Light", "Cryo", "EMS" at DNA by SLVK, "Bastu: Pollux" at Folkbastu. The same titles at studios without the label (e.g. "EMS" at iPulse Studios) are not Wellness.
- Waitlist vs. fully booked: `available_spots:0` means fully booked. Whether *you* are on the waitlist is not in the class payload; it comes from `GET /v52/standby` (see below).
- `GET /v52/class/<id>?include_studio=true&include_info=true&include_address=true&include_studio_alerts=true&exclude_studio_expired_alerts=true&include_absolute_times=true&include_dynamic_prices=true&include_booking_credit_costs=true&include_studio_user_attendance_info=true&locale=en` [c2:50, 58, 93, 100] - class detail before booking.

## Booking
- `GET /v52/booking?user_id=&limit=30&deleted=false&include_class=true&include_class_info=true&include_class_studio=true&include_class_categories=true&include_class_dynamic_prices=true[&next_cursor=]` [75, 86, ...] -> `{bookings:[{id,class_id,studio_id,place_id,user_id,checked_in_at,opening_hour_occurrence_id,deleted,cancelled,...}]}`; short variant with `reviewable=true` [17].
- `GET /v52/booking/aggregate?user_id=` [70] -> `{booking_aggregates:[{day,count}]}`.
- `GET /v52/booking/voucher?owner_id=` [33] -> `{booking_vouchers:[...]}`.
- `POST /v52/booking/offline/done` body `{"locale":"en"}` [13, 47, 48, 160, 179] -> empty; syncs offline check-ins at app start.
- Create (capture 2): `POST /v52/booking` [c2:84] header `X-Access-Token`, body
  `{"class_id":<CLASS_ID>,"booked_via":"HOMESCREEN_SPOTLIGHT","include_user":true,"locale":"en"}`
  -> 200 `{"booking":{id,user_id,studio_id,class_id,checked_in_at:null,booking_credits,trial_period,integration_type,created_at,user{...},class{...}}}`. `booked_via` is an analytics source tag (only this value observed). `include_user:false` should avoid the user object in the response (not verified).
- Cancel (capture 2): `DELETE /v52/booking/<BOOKING_ID>` [c2:120] body `{"locale":"en","include_user":true}` -> 200 `{"booking":{id,deleted:true,deleted_at,class_id,...,user{...}}}` (soft delete). Booking 84 -> cancelled in 120 (same id).
- Re-reads after book/cancel: `GET /v52/booking`, `/v52/booking/aggregate`, `/v52/studio/user_visit_limit`, `/v52/class/<id>` [c2:93-129].

## Booking windows (measured 2026-10-14)
From the logged-in class objects of captures 1-6 (6,453 classes) plus an unauthenticated crawl of 22 days of Stockholm classes (8,606 classes).
- Booking opens at `bookable_earliest_time` = `start_time - bookable_earliest` (seconds); the identity held for all 6,389 classes that have a window (64 have none, `null`). There is no daily release time: the open moment is the class's own start time of day, N days earlier.
- `bookable_earliest` is 604800 (7 days) for 96.8% of classes. Exceptions: 6 days (Barry's, `mariana_tek`), 14 days (Acid Training, `mana_app`), 4 days (CrossFit Södermalm), 5 days (CrossFit Nordic `brp`, Träningslabbet `wondr`), 10 days (The Workout Plan), 3 days (duCalme). Example: `bookable_earliest:604800`, `bookable_earliest_time:"2026-10-05T09:30:00Z"`, `start_time:"2026-10-12T09:30:00Z"`, `bookable_latest:600`, `unbookable_latest:43200`.
- Classes are listed about 14 days ahead (most are created 14 days before start), before they can be booked, with `available_spots == spots`. The official app's per-studio query sends `bookable_earliest_before=<now>` to hide them.
- The unauthenticated `GET /v52/class` returns a cut-down class (31 keys) without `bookable_earliest`, `bookable_earliest_time`, `master_id`, `integration_type` or `user_attendance_info`; `include_*` flags do not add them. Logged-in responses have 62 keys.
- Series: `master_id` is set on about 80% of classes and identifies a weekly class (2,767 of 2,768 weekly series share one); one master can cover several time slots, so a weekly slot is `master_id` + weekday + local start time. `recurring_id`/`recurring_index`/`integration_recurring_id` are almost never set; `is_master` is filtered out by the list query.
- Small classes fill fast after opening: e.g. a 2-spot class within 0.9 h, 3-5 spot classes within 2-3 h.
- No failed `POST /v52/booking` was captured (no "too early" or limit error body). Limits show as flags in `user_attendance_info` (`booking_limit_reached`, `visit_limit_reached`), and `GET /v52/studio/user_visit_limit` has a `SIMULTANEOUS` limit (3 BASE / 4 BLACK / 5 EPIC) besides the monthly ones.
- Auto-book (both apps, and the optional server in `server/`) uses these rules: a rule is studio + weekday + local time + `master_id` (or title), resolved to concrete classes over the next 15 days, booked at `bookable_earliest_time` (start - 7 days when missing) with retries for 20 s.

## Check-in (confirmed, capture 1 only; no check-in in captures 2-8)
`POST /v52/studio/check_in` [163]
```json
{"locale":"en","qr_code_id":"stc:<MAJOR>","meta":{"major":"<MAJOR>","minor":"<DOOR_ID>","door_id":"<DOOR_ID>"},"include_class":true}
```
-> 200 `{"bookings":[{id,studio_id,place_id,checked_in_at,opening_hour_occurrence_id,class_id:null,...}],"payable_openings":[],"payable_opening_hours":[],"integration_door_data":null}`.
A drop-in (gym, no class) check-in creates the booking itself. Note `MAJOR` (QR/beacon id) is not the studio id.
Remote check-in without `meta` (only the studio's `qr_code_id` "stc:<MAJOR>", from Bruce-iOS at STC Sturegatan Park, studio 12388, Oct 12) answered **HTTP 400, yet the booking was checked in**: the official app showed the ticket and `GET /v52/booking` returns it with `checked_in_at` [c8:404]. Our client sends exactly one request per confirmed tap, so the 400 is not a duplicate of ours; most likely the server registers the check-in and then fails a later step, e.g. the BRP door integration that has no door id. The response body was not recorded. So the status code is not reliable for check-in: the clients re-read the bookings after any non-2xx answer and treat a booking at that studio with `checked_in_at` today as success (ticket shown, no error). Door ids are optional: when known (built in, or remembered from the user's own scanned door QR) they are sent as `meta`.

## User / account (context)
- Capture 2 also has `PUT /v52/user/<USER_ID>` [c2:337, 580], `GET|POST /v52/user/<USER_ID>/address` [c2:279, 339], `DELETE /v52/user/<USER_ID>/address/<ID>` [c2:341] -> 204, `GET /v52/payment` [c2:388] (account editing; not used by the app).
- `GET /v52/config?locale=en` [7] -> min app versions. 
- `GET /v52/user/<USER_ID>?include_...=true` [15] -> `{user:{id,email,first_name,last_name,...}}`; `PUT /v52/user/<USER_ID>` `{first_name,last_name}` [55].
- `GET /v52/user/tos/current?country_code=SE` [16], `GET /v52/user/onboarding` [52], `GET /v52/membership/user_info?user_id=` [14] (membership, tier, available_credits).
- `GET /v52/payment/method?user_id=` [18], `GET /v52/payment?user_id=` [97], `GET /v52/notification?user_id=` [42], `GET /v52/user_strike/feed` [99], `GET /v52/user_block/info` [100], `GET /v52/friend` [182], `GET /v52/friend_request` [181].
- `GET /v52/image/<cloudinary transform>/<id>.jpg` [58, 199] - image proxy.

## Capture 3 additions (`c3:N`)

All write calls take a JSON body containing at least `{"locale":"en"}` and the `X-Access-Token` header.

### Bookmarks, favourites, waitlist
- `POST /v52/bookmark` [c3:73] `{"class_id":<CLASS_ID>,"locale":"en"}` -> `{"bookmark":{id,user_id,class_id,created_at}}`.
- `DELETE /v52/bookmark/<BOOKMARK_ID>` [c3:77] `{"locale":"en"}` -> empty body. The id is the bookmark id (from `GET /v52/bookmark`), not the class id.
- `GET /v52/favorite?studio_id=<id>&locale=en` [c3:88, 117] -> `{"favorites":[...]}` (empty = not a favourite). Without `studio_id` it returns all of the user's favourites [c5:39].
- `POST /v52/favorite` [c3:93] `{"studio_id":<STUDIO_ID>,"locale":"en"}` -> `{"favorite":{id,created_at,user_id,studio_id,order,place_id}}`.
- `DELETE /v52/favorite/<FAVORITE_ID>` [c3:96] `{"locale":"en"}` -> empty.
- Waitlist ("standby"):
  - `POST /v52/standby` [c3:65] `{"class_id":<CLASS_ID>,"locale":"en"}` -> `{"standby":{id,created_at,class_id,user_id}}`.
  - `DELETE /v52/standby/<STANDBY_ID>` [c3:69] `{"locale":"en"}` -> `{"waitlist":{...,deleted:true},"standby":{...,deleted:true,booking_id}}`.
  - `GET /v52/standby?user_id=&class_start_time_after=<ISO>&deleted=false&include_class=true&include_class_info=true&include_class_dynamic_prices=true` [c3:18] lists them.
  - The class payload has no "on waitlist" flag. State comes from this list, and `info.standby_count` is a count.

### Reviews
- `GET /v52/review?studio_id=<id>&comment=true&hidden=false&order_by=-id&limit=50&include_booking=true&include_booking_class=true&include_booking_user=true&locale=en` [c3:101, 121, 592] -> `{"reviews":[{id,rating(1-5),comment,created_at,public,hidden,response,studio_id,class_id,user_id,booking:{...,class:{start_time,opening,title},user:{id,first_name,photo,display_name,social}}}],"metadata":{...}}`.
- `booking.class.opening == true` (title null) is shown as "Solo training". The aggregate comes from studio `rating{total,average(x100),distribution{"1".."5"}}`.
- `GET /v52/booking?user_id=&reviewable=true&include_class=true` [c3:27] lists bookings that can be reviewed. Submitting a review: see capture 8.

### Friends
- Friends' upcoming classes: `GET /v52/booking?friends=true&user_id=<me>&class_day_after=YYYYMMDD&deleted=false&limit=30&include_class=true&include_class_studio=true&include_class_dynamic_prices=true` [c3:106] -> `{"bookings":[{id,class_id,studio_id,user_id(friend),class{...,studio}}]}`. Join `user_id` with `GET /v52/friend` for name and photo.
- Class attendees: `GET /v52/booking?class_id=<id>&include_user=true&include_message=true&deleted=false&limit=30` [c3:58, 573; c2:55; c7:160]. See capture 7 below: members with Social on come with `user_id` and a public `user`, everyone else without (shown as "Hidden").
- `POST /v52/friend_request` [c3:171] `{"from_user_id","to_user_id","include_from_user":true,"include_to_user":true,"locale"}`.
- `POST /v52/friend_request/<id>/respond` [c3:245] `{"accept":bool,"include_friend_user":true,"locale"}` -> `{}`.

### Settings, profile
- `GET /v52/user/<USER_ID>/notification_setting?locale=en` [c3:279, 326] -> `{"notification_settings":[{id,user_id,marketing_email,marketing_push,marketing_sms,types:[{id,key,name,description,enabled}]}]}`. The type keys are `new_studio`, `booking_reminder` and `check_in_reminder`.
- `PUT /v52/user/<USER_ID>/notification_setting/<SETTING_ID>` [c3:319-332] returns the full setting. Marketing toggles send one field, e.g. `{"marketing_push":false,"locale":"en"}` [c3:319-324]. Push types send the whole array: `{"types":[{"key":"booking_reminder","enabled":false},{"key":"check_in_reminder","enabled":true},{"key":"new_studio","enabled":true}],"locale":"en"}` [c3:327-332].
- `PUT /v52/user/<USER_ID>` [c3:280, 287] `{"social":true|false,"locale":"en"}` is the "Bruce Studios Social" toggle and returns `{"user":{...}}`. A profile/address save was not captured in c3; c2 has `PUT /v52/user/<id>` and `GET|POST|DELETE /v52/user/<id>/address`.
- User tier: `GET /v52/user/<id>?include_current_subscription=true&include_current_subscription_tier=true...` [c3:21] -> `current_subscription{tier{id,level,name,code}, commitment_months, committed_until, prolong_commitment, price, payment_interval_months}`. Level 1 = `BASE` is confirmed; levels 2 and 3 are not observed.

### Money, calendar, misc
- `GET /v52/payment?user_id=&locale=en[&next_cursor=]` [c3:454] -> `{"payments":[{id,created_at,amount,original_amount(öre),currency,type,status,payment_method_id,admission{start_day,end_day,tier_id}}]}`. Types seen: `BOOKING`, `MEMBERSHIP_RENEWAL`, `MEMBERSHIP_UPGRADE`, `USER_BLOCK_UNLOCK`, `FREE`; status `successful`.
- `GET /v52/payment/<PAYMENT_ID>/receipt.pdf` [c3:536, 549] and `GET /v52/payment/collective/invoice.pdf?payment_ids=<id>,<id>` [c3:543] return PDFs.
- Calendar subscription: `GET /v52/user/<USER_ID>/calendar/<USER_SECRET>.ics` [c3:341, 370] (also `/v50/...` [c3:345, 369]). This is a public, unauthenticated-style feed URL containing the user's secret; treat it as a credential. It returns a VCALENDAR (`X-WR-CALNAME`, `REFRESH-INTERVAL`, VEVENTs).
- `GET /v52/booking/aggregate?user_id=` [c3:396] -> `{"booking_aggregates":[{day:YYYYMMDD,count}]}` (statistics).
- Statistics screen (account menu): a bar chart of visits per month (from the aggregate, summed by month; months without visits show 0) over a list of past visits grouped by day, newest day first. Each row: the time, the class length for a class ("60 min"), the title, the studio, then "area | instructor". A drop-in gym visit (`class_id:null`, `opening_hour_occurrence_id` set [c8:404]) shows "Solo training" with the opening hours of that day, at the check-in time; a class shows at its start time. The list request itself is not captured (no capture opens Statistics). The clients page `GET /v52/booking?user_id=&limit=30&deleted=false&include_class=true&include_class_studio=true` by `next_cursor` without a time window and keep the bookings with `checked_in_at`. Drop-ins carry no class, so their studio name and area come from the studio list, and their opening hours are not in the booking (the clients show "Solo training" without hours).
- `GET /v52/faq?locale=en` [c3:407] -> `{faqs:[{id,section_id,question,answer,published_at}]}`; `GET /v52/faq/section` [c3:410] -> `{sections:[{id,title,tags}]}`.
- `GET /v52/search?query=<q>&type=studio,class&latitude=&longitude=&city_code=STO&search_mode=indexed&locale=en` [c3:603, 605] -> `{"result":[]}` (only empty results captured).
- `POST /v52/voucher/redeem` [c3:275] `{"code","user_id","locale"}` -> error `{"errors":[{code,message,status}]}` (invalid code).

### Confirmed by capture 3 (rules used by the app)
- Check-in window = `[start - early_check_in_minutes, start - late_check_in_minutes]`; "Book until" = `start - bookable_latest` (s); "Cancel until" (late cancellation) = `start - unbookable_latest` (s). Values seen: (5, 30, 43200, 600/300) and (10, 60, 43200, 600) [c3:49 and 55 class payloads].
- Notifications still carry `read:false` everywhere and no read/mark-seen call exists, so the red dot is client-side "new since last opened".
- Notification items [42, 159, 178]: `{id,user_id,created_at,type,title,message,read,hidden,im,push,email,sms,info,channel:"BRAZE",meta{class_id,studio_id,photo,user_photo,inviting_user_name}}`. `type` is one of `STANDBY_AVAILABLE` ("Free spot"), `BOOKING_REMINDER`, `BOOKING_CANCELLED`, `CLASS_MESSAGE`, `CHECK_IN_REMINDER`, `USER_STRIKE`, `USER_BLOCK`, `USER_STRIKE_UNBLOCKED`, `CLASS_INVITE`, `PAUSE_ENDING`. `meta.class_id` is set on the class types; `meta.studio_id` is often null even then; `meta` is missing on `USER_STRIKE_UNBLOCKED` and `PAUSE_ENDING`. No booking id, standby id or link. The apps open the class, else the studio.
- A "Free spot" (`STANDBY_AVAILABLE`) does not book: in capture 1 the user booked the class by hand about 20 s after it. Several waitlisters get it, first come first served, so the class's `available_spots` is what shows the spot is still there.

### Plan prices (capture 2)
- `GET /v52/membership/info?city_code=STO&tier_code=BASE|BLACK|EPIC&commitment_months=12&user_id=&locale=en` [c2:426] -> `{"membership_info":{price,original_price(öre, annual/month),original_flex_price(öre, no commitment),pre_pay_price,pre_pay_periods[...],discounts[...],start_date,end_date,tier_code,city_code}}`. Used for the Membership plans screen. Changing plans was not captured.

## Capture 4 additions (`c4:N`)
- Per-studio limits: `GET /v52/studio/user_visit_limit?user_id=&studio_id=<id>&month=YYYYMM&locale=en` [c4:34, 73, 85; also c3:56, 63, 66]. It returns `limits[]` with `type`:
  - `STUDIO`: the per-studio monthly visit limit for the user's tier. This drives the studio/class top-bar pill: `total>0` gives "used / total"; `total==0` means unlimited and shows ∞ (STC gyms); `total==-1` means not included in the tier and shows "0 / 0" (e.g. Wellness spas for BASE).
  - `MONTHLY`: account-wide visits ("Total monthly visits", e.g. 3/20).
  - `WELLNESS_MONTHLY`: wellness visits (-1 for BASE, 4 BLACK, 8 EPIC). `total` follows the same rule as `STUDIO`: -1 means not included (BASE gets `used:0, remaining:0`), so the clients show "Not included in your plan" rather than "0/-1".
  - `SIMULTANEOUS`: bookings at a time (3 BASE / 4 BLACK / 5 EPIC). This is the "0 / 3" pill on My classes.
- Paid tickets (Wellness): `GET /v52/studio/<id>/opening_hour/schedule?...&include_studio_user_attendance_info=true` [c4:31] gives `schedule[].studio_user_attendance_info{admission_access:false, price:28000 (öre), currency:"SEK", visit_limit_reached:true, visit_limit_reached_types:["STUDIO","WELLNESS_MONTHLY"]}`. That pair is what the app shows as "Buy ticket for SEK 280". Class payloads carry `dynamic_prices{BASE:23000,...}` and `user_attendance_info{admission_access:false, booking_limit_reached, visit_limit_reached}` for the same case [c4:96]. The purchase call itself was not captured (and is deliberately not implemented).
- Studio `label:"WELLNESS"` [c4:97] is the "Wellness" tag. Studio photos come from `studio_photos[].photo.file_id` with `order` (`include_studio_photos=true&include_studio_photos_photo=true`).
- `tier_level` on studios does NOT map 1:1 to the access tier: the spa in c4 has `tier_level:3` but per-studio limits BASE -1 / BLACK 2 / EPIC 4, and another Wellness studio has `tier_level:1`. Use the `STUDIO` limit items instead.
- c4 has no new write endpoints. The only request body is `POST /v52/booking/offline/done` `{"locale":"en"}` [c4:15].

### Studio page rules (from app screenshots, Oct 2026)
- Notice banner = studio `alerts[].message` (type `INFO`, sorted by `order`; request `include_alerts=true&exclude_expired_alerts=true`) [c2:212]. Only active alerts are shown: see capture 7 for `start_date`/`end_date`. The studio's `alert` string field was null in all captures; classes have their own `alert` (c7).
- Hours line: teal "Solo training until HH:MM" (open), orange "Solo training ends at HH:MM" (closing within ~60 min; orange seen at 29-38 min, teal at 2 h 38 min), red "Currently closed for solo training".
- Lime button only for "Show ticket" (checked in today) or "Buy ticket for SEK n" (paid access); none otherwise.
- Studios with classes get a "Classes" tab and a "Show classes / N classes" row, filled from `GET /v52/class?studio_id=<id>&presentation_studio_id=<id>` per day.

## Capture 5 additions (`c5:N`)
- All favourites: `GET /v52/favorite?locale=en` [c5:39] -> `{"favorites":[{id,created_at,user_id,studio_id,order,place_id}]}`. The app loads this at start for the heart filter.
- Search with results: `GET /v52/search?query=<q>&type=studio,class&latitude=&longitude=&city_code=STO&search_mode=indexed&locale=en` [c5:423, 424] -> `{"result":[{id:"<index id>",index,type:"STUDIO",fields:{id,name,city,distance,photo,qr_code_id,status,integration_type,created_at}}]}`. Only `STUDIO` hits were captured; a class hit's `fields` shape is unknown.
- Explore studio filter: the app's `GET /v52/studio/filter` [c5:38...] carries only `filter[status][in]`, `filter[country_code][eq]` and `include=...,visit_limit,...`. The tier/Wellness/Favourite chips are applied client-side. Tier access = the studio's `visit_limit.items[label=TIER].limit != -1` (c4).
- Profile email save: `PUT /v52/user/<USER_ID>` [c5:221] body `{"email":"<EMAIL>","locale":"en"}`. Documented only; the app keeps Edit profile display-only.
- Addresses: `GET /v52/user/<USER_ID>/address?include=address` [c5:215, 223] -> `{"user_addresses":[{id,address_id,primary,address:{address,city,zip_code,name,country,country_code,vicinity,latitude,longitude}}]}`. Writes are in c2 (`POST`/`DELETE`).
- Friend requests: `POST /v52/friend_request` [c5:375] and `POST /v52/friend_request/<id>/respond` [c5:406] have the same shapes as c3.
- No token refresh, check-in, notification-read, pause, plan-change or review-submit call appears in c5.

## Capture 6 additions (`c6:N`)
Capture 6 (about 347 files) covers creating and using custom areas ("New area" in the Explore filter).
- **Areas are local-only in the original app.** c6 shows no area, zone or polygon request. The class
  queries (`GET /v52/class`, 147 calls) carry only `studio_city_id` plus times, with no polygon or bounds
  parameter. So areas are stored on the device and applied as a client-side filter (point in polygon on the
  studio's coordinates; classes by their studio). Bruce-iOS and Bruce-MacOS do the same: see
  `Shared/BruceCore/Areas.swift`, where `LocalAreaStore` is a JSON file in Application Support.
- The only write is `POST /v52/booking/offline/done` with body `{"locale":"en"}` [c6:458, 459, 569].
- The other GETs are already documented: `/class`, membership, booking, user, tos, payment/method, config,
  category, studio, user_visit_limit, alternative_recommendation, location/city and bookmark.
- Public (no token) endpoints, verified unauthenticated: `GET /v52/studio/filter` (`limit` capped at 30;
  `next_cursor` = base64 `id::<last id>`, ids descending), `GET /v52/class` (cursor `id:<n>`) and
  `GET /v52/category`.

### Parakey doors (capture 6, Oct 2026 screenshots)
- Studios with `integration_door_type:"parakey"` (214 of the studio rows in the captures; others: `brp`, `wondr`, `zoezi`, `m3_fit`, `blx`, `ellions`, `tic_off`) open their doors with the Parakey app. The studio detail adds `parakey_config:{id, optional}` (`null` elsewhere) [c6:631, 638]; the list payload only has the door type.
- `GET /v52/user/<id>` carries `parakey_email` once the Bruce account is linked with Parakey [c6:451, 557]. No linking or key request was captured: the official app says checking in creates the access key, valid no earlier than ten minutes before class.
- Both clients show a "Doors open with Parakey" row on the class and studio pages and a sheet that explains it, shows the linked email and opens the Parakey app (App Store id 1001574067).

### Friends on class rows
- Class rows show the faces of friends booked on the class, from the same `GET /v52/booking?friends=true` + `GET /v52/friend` join as the Friends tab (so at most the 30 upcoming friend bookings that call returns).

## Capture 7 additions (`c7:N`)
Capture 7 (about 25 requests) opens two fully booked classes and their "Similar classes" sheet.
- **Class alert.** `GET /v52/class/<id>?...&include_studio_alerts=true&exclude_studio_expired_alerts=true` [c7:19, 30].
  The class object has an `alert` string, e.g. `"Only women are welcome here. Please respect this."` [c7:30]
  (null for most classes [c7:19]). The official app shows it in red under the description, with a translate
  button. It has no dates.
- **Studio alerts with dates.** The embedded `class.studio.alerts[]` [c7:30] (and the studio's `alerts[]`)
  are `{id, studio_id, message_string_id, type:"INFO", order, show_on_web, start_date, end_date, start_day,
  end_day, message, created_at, updated_at, deleted_at}`. `end_date` may be `null` (open-ended; `end_day` is
  then `0`), so an alert has a start and an optional end. `exclude_studio_expired_alerts=true` did **not**
  remove an alert whose `end_date` was 2023-08-23, so clients must filter: active = `start_date <= now` and
  (`end_date` null or `now < end_date`). Both apps show the class `alert` if present, otherwise the studio's
  active alerts, in red.
- **Similar classes.** `GET /v52/studio/class/alternative_recommendation?class_id=<id>&locale=en`
  [c7:24, 41] -> `{"class_cards":[{id, title, photo, time_zone, distance, start_time, end_time, created_at,
  studio:{id, name}}], "metadata":null}`. About ten cards: classes nearby (`distance` in metres from the
  original class's studio; `0` = same studio) around the same time, the same day. `id` is a class id
  (open it with `GET /v52/class/<id>`). The app requests it when a full class opens and shows the cards in
  a bottom sheet ("Similar classes to <title>, <HH:MM> nearby <studio>") from the "Similar classes" button
  next to "Join waitlist".
- **Descriptions are Markdown**: studio and class `description` use `**bold**`, `* item` lists and
  `[links](https://...)` [c7:19, 30]. Both apps render them as Markdown.
- No new write calls: the only POST is `POST /v52/booking/offline/done` [c7:26].

Capture 7 also covers opening a booked class and inviting a friend to it (Oct 2026):
- **Class attendees** `GET /v52/booking?class_id=<id>&include_user=true&include_message=true&include_class_dynamic_prices=true&deleted=false&limit=30` [c7:160] -> `{"bookings":[...],"metadata":{...}}`. Members with "Bruce Studios Social" on carry `user_id` and `user{id,first_name,photo,photo_valid,social,city_id,display_name}` (`display_name` was null). The others have neither `user_id` nor `user`; the original app shows them as a grey "Hidden" avatar. The caller's own booking carries their full user record. This is the "who's booked" row on the class page (the invite button, then the attendees).
- **Class invite** `POST /v52/class/<id>/invite` [c7:168] body `{"user_ids":[<friend user id>],"locale":"en"}` -> `{"invited":[<user>]}`. It is the class page's "Invite" button: a sheet titled with the class name lists the user's friends ("Contacts") with check marks and an "Invite friends" button. The membership invite codes (`GET /v52/booking/voucher`) are a separate feature under the account menu. Note that the response returns each invitee's **full private user record** (email, phone, national identity number, calendar secret, payment references); the apps ignore the response body.
- **Class notice banner**: the class detail's embedded studio has `alerts[]` when requested with `include_studio_alerts=true&exclude_studio_expired_alerts=true` [c7:157]. Each alert has `id,type,order,message,start_date,end_date,start_day,end_day,show_on_web`. `type` is `INFO` or `CRITICAL`; the original shows the critical one as a red banner at the top of the class page. An `INFO` alert that ended months earlier was still returned, so clients filter by `start_date`/`end_date`. The studio detail request the app sent on this screen [c7:158] did not ask for alerts.
- Class detail also carries `alert` and `message` fields on the class itself (both null here) and `user_attendance_info`.
- Other requests are already documented: user, tos, membership user_info, payment method, reviewable bookings, config, bookmark, alternative_recommendation, user_visit_limit, offline/done, category, friend.
- Class detail with the visit limit reached [c7:125] (request `include_studio_user_attendance_info=true`): `class.user_attendance_info` = `{id, admission_access:false, booking_credit_access, booking_credit_amount, price:22000 (öre), booking_voucher_access, booking_voucher_id, trial, user_tier_code:"BASE", booking_limit_reached:true, visit_limit_reached:true, visit_limit_reached_types:["STUDIO"]}`. That is the original's "Buy for SEK 220". `dynamic_prices` is `{"BASE":0,"BLACK":0,"EPIC":0,"FREE":-1}` there too, so it is not the drop-in price; the class has `currency:"sek"`. Classes within the limit [c7:70, 84, 97] have `admission_access:true`, `price:null`, `visit_limit_reached:false`.
- `GET /v52/studio/user_visit_limit?studio_id=&user_id=&month=YYYYMM` [c7:132, 122, 76, 91, 106] -> `limits[{id, total, total_trial, used, remaining, within_limit, resolvable_by_unbooking, resets_at:"2026-10-31T23:00:00Z" (UTC; 1 Nov local), month:202610, note, type:"STUDIO"|"MONTHLY"|"SIMULTANEOUS", visit_limit_type, items:[{id, visit_limit_id, label, limit, period:"MONTHLY"}]}]`. `STUDIO` items come as EPIC, BLACK, BASE; the original's visit-limit sheet lists them BASE, BLACK, EPIC. An unlimited studio has `total:0, remaining:0, within_limit:true`.
- Waitlist promotion: standby `booking_id` is null on every entry [c7:80]. Once the user gets a spot, the entry is gone from `GET /v52/standby` and the booking shows in `GET /v52/booking` (same `class_id`) [c7:64].
- The original's booking list: `GET /v52/booking?limit=30&deleted=false&class_start_time_after=<now-24h>&user_id=&include_class=true&include_class_dynamic_prices=true` [c7:64], newest first; `metadata.pagination{count,limit,offset,next_offset,next_cursor:null,prev_cursor}`. Clients should follow `next_cursor` until null; a waitlist entry that vanished from `/v52/standby` while a booking with its `class_id` exists was promoted, not dropped.
- Still no purchase call for the drop-in ("Buy for SEK n"); the apps show a "not available" message instead.

### Still not captured
Responding to a class invite; check-in other than the STC door QR (`POST /v52/studio/check_in` appears only in capture 1); membership upgrade, pause and cancel (prices: `GET /v52/membership/info`, c2:426); profile photo upload; a review with a comment; notification mark-read; drop-in/ticket purchase; ticket (no endpoint; the app renders it from the checked-in booking).

## Capture 8 additions (`c8:N`)
Capture 8 (about 220 requests, Oct 12 22:46-22:47 local) is an app start after a class the user had checked in to
(a "Hyrox" class at STC Sturegatan Park, studio 12388, starting 14:50Z; checked in at 14:34Z), followed by rating it and browsing.
It has no check-in request (the check-in happened before the capture, from Bruce-iOS; see Check-in above) and no token refresh.

- **Review trigger.** At start the app calls `GET /v52/booking?reviewable=true&user_id=<USER_ID>&include_class=true&locale=en`
  [c8:415] -> `{"bookings":[{id, class_id, checked_in_at, review_id:null, class{...}}],"metadata":{...,"cache_expire_seconds":0}}`.
  There is no review notification type and no silent push: the official app's Info.plist has no `UIBackgroundModes`
  (so no background `remote-notification`), its UI strings have no rating notification, the push setting types are
  only `new_studio`, `booking_reminder`, `check_in_reminder` [c3:279], and the notification list holds only `STANDBY_AVAILABLE`, `CHECK_IN_REMINDER`,
  `BOOKING_CANCELLED`, `BOOKING_REMINDER`, `USER_STRIKE`, `CLASS_MESSAGE`, `USER_STRIKE_UNBLOCKED`, `USER_BLOCK` [c8:418])
  and no pending-review endpoint: this list is the trigger. Four seconds later the rating went out.
- **Submit a review** `POST /v52/review` [c8:467] body
  ```json
  {"rating":5,"public":true,"booking_id":<BOOKING_ID>,"locale":"en","include_booking":true}
  ```
  -> 200 `{"review":{id,rating,comment:null,created_at,public,studio_id,class_id,user_id,booking:{id,...,review_id:<new id>,checked_in_at,...}}}`.
  The dialog of the official app (from its bundled UI strings): title "Rate class", stars, "Comment (optional)", an
  "Anonymous comment" switch, buttons "Send (public)" / "Send (anonymous)" (= `public`), and "Skip" (you can rate
  later from the statistics list). A low rating asks for confirmation and requires a comment. Skipping is stored on
  the device only (`skippedReview` in its data model); no request is sent. The comment field is not in the captured
  request; the clients send it as `comment`, the field name of review objects [c3:101] (unverified).
- **My classes keeps checked-in classes.** The app's list calls `GET /v52/booking?user_id=&limit=30&deleted=false&class_start_time_after=<now-24h>&include_class=true&include_class_studio=true&include_class_dynamic_prices=true`
  [c8:404] (and the same without `include_class_studio` [c8:410]). The response includes the rated class booking with
  `checked_in_at` set, and the official app still shows it. Bruce-iOS/-MacOS used to drop every booking with
  `checked_in_at` client-side; they now keep it with a "Checked in" badge, the ticket, and the rating action. Drop-in
  gym visits come back in the same list with `class_id:null` and `opening_hour_occurrence_id` set.
- `GET /v52/booking?friends=true&user_id=&class_day_after=YYYYMMDD&...` [c8:512] is the friends feed (as c3:106).
- Other requests are known: offline/done [c8:423, 424], class days, user, bookmark, standby, config, membership
  user_info, payment method, tos, vouchers, notification, city, home_screen, category, user_visit_limit, friend,
  friend_request, favorite, studio/filter and image redirects.
