# Bruce API map (Charles captures 1–6 of the iOS app 14.4.2 build 538)

> Unofficial, reverse-engineered by observing the author's own account traffic. Not affiliated with or
> endorsed by Bruce Studios AB. The raw captures contain personal data and are **not** part of this
> repository; the bracketed evidence numbers below refer to them for the author's own reference.
> Machine-readable version: [`openapi.yaml`](openapi.yaml) (browse it with [`swagger.html`](swagger.html)).

Evidence numbers without a prefix refer to capture 1; `c2:N` refers to capture 2, `c3:N` to capture 3, `c4:N` to capture 4, `c5:N` to capture 5, `c6:N` to capture 6.

Base: `https://api.bruce.app/v52/` (older `/v1/studios` is a separate, unauthenticated public list).
Numbers in brackets are capture file numbers (`N-meta.json` / `N-req.json` / `N-res.*`).

## Common
- Auth: header `X-Access-Token: <ACCESS_TOKEN>` on every v52 call. No `Authorization`/Bearer, no cookies.
- Other headers: `User-Agent: Bruce/<ver>_<build> (iOS<ver>; Apple)`, `Accept-Language`, Sentry `baggage`/`sentry-trace` (optional).
- Almost all calls take `locale=en`; user-scoped calls take `user_id=<USER_ID>`.
- Lists: `{"<items>":[...], "metadata":{"pagination":{count,limit,offset,next_offset,next_cursor,prev_cursor},"cache_expire_seconds"}}`; page with `limit` + `next_cursor` (base64, e.g. `id:<n>`) [75, 86].

## Login / auth (capture 2)
- `POST /v52/access/authenticate` [c2:461] - NO `X-Access-Token` header.
  ```json
  {"authenticator":"PASSWORD","email":"<EMAIL>","password":"<PASSWORD>","locale":"en"}
  ```
  -> 200 `{"user_id":<USER_ID>,"user_created":false,"access_token":"<64 chars>","refresh_token":"<64 chars>","access_token_expires_at":"<ISO8601, ns precision>","refresh_token_expires_at":"<ISO8601>","user_agent":"Bruce/14.4.2_538 (iOS..; Apple)"}`.
  Observed lifetimes: access token 3 hours, refresh token ~3 months. The new access token is used as `X-Access-Token` on all following calls.
- `DELETE /v52/access/logout` [c2:442] header `X-Access-Token`, body `{"locale":"en"}` -> 200, empty body.
- Refresh: NOT captured. No request in capture 2 sends `refresh_token` (grep over all req/meta files), and no 401 occurs. The refresh route/body is unknown; the app treats an expired access token as "log in again".

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
- `GET /v52/studio/class/alternative_recommendation?class_id=<id>&locale=en` [c2:53].
- `GET /v52/favorite` [c2:152, 213], `GET /v52/bookmark` [c2:52], `GET /v52/standby` [c2:474], `GET /v52/admission` [c2:423], `GET /v52/membership/info` [c2:426] (context only).

### Class list - capture 2
`GET /v52/class` [c2:20, 28, 30 ... 1142-1144; 506 requests]
- City/day schedule: `studio_city_id=1` (Stockholm), `start_time_after=YYYY-MM-DDT00:00:00`, `start_time_before=<next day>T00:00:00` (local, no zone), `limit=30`, `next_cursor=<base64 "id:<n>">`, plus `is_recurring_base=false&is_master=false&dedicated=false&opening=false&studio_status=live&include_absolute_times=true&include_class_categories=true&include_booking_credit_costs=true&include_dynamic_prices=true&locale=en`. The app pages through each day separately (Oct 11 to Oct 18 captured).
- Per studio [c2:214, 216, 1017, 1019]: `studio_id=<id>&presentation_studio_id=<id>` with UTC range (`...Z`), optional `bookable_earliest_before=<now>`, `include_address=true`, `include_studio_user_attendance_info=true`; `opening=true` returns opening-hour slots instead of classes.
- -> `{"classes":[{id,studio_id,presentation_studio_id,title,description,start_time,end_time (UTC Z),time_zone,spots,available_spots,canceled,instructor,bookable_earliest,bookable_latest,unbookable_latest,auto_check_in,late_check_in_minutes,early_check_in_minutes,booking_credit_costs{BASE,BLACK,EPIC,FREE},dynamic_prices,class_categories[...]}],"metadata":{"pagination":{...,"next_cursor":"..."},"cache_expire_seconds":55}}`. Class objects carry no studio name; join with the studio list by `studio_id`.
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

## Check-in (confirmed, capture 1 only; no check-in in capture 2)
`POST /v52/studio/check_in` [163]
```json
{"locale":"en","qr_code_id":"stc:<MAJOR>","meta":{"major":"<MAJOR>","minor":"<DOOR_ID>","door_id":"<DOOR_ID>"},"include_class":true}
```
-> 200 `{"bookings":[{id,studio_id,place_id,checked_in_at,opening_hour_occurrence_id,class_id:null,...}],"payable_openings":[],"payable_opening_hours":[],"integration_door_data":null}`.
A drop-in (gym, no class) check-in creates the booking itself. Note `MAJOR` (QR/beacon id) is not the studio id.

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
- `GET /v52/booking?user_id=&reviewable=true&include_class=true` [c3:27] lists bookings that can be reviewed. Submitting a review was not captured.

### Friends
- Friends' upcoming classes: `GET /v52/booking?friends=true&user_id=<me>&class_day_after=YYYYMMDD&deleted=false&limit=30&include_class=true&include_class_studio=true&include_class_dynamic_prices=true` [c3:106] -> `{"bookings":[{id,class_id,studio_id,user_id(friend),class{...,studio}}]}`. Join `user_id` with `GET /v52/friend` for name and photo.
- Class attendees: `GET /v52/booking?class_id=<id>&include_user=true&include_message=true&deleted=false&limit=30` [c3:58, 573; c2:55] returns bookings without `user_id`/`user`. Attendees are anonymised, so "who's booked" can only use the friends feed.
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
- `GET /v52/faq?locale=en` [c3:407] -> `{faqs:[{id,section_id,question,answer,published_at}]}`; `GET /v52/faq/section` [c3:410] -> `{sections:[{id,title,tags}]}`.
- `GET /v52/search?query=<q>&type=studio,class&latitude=&longitude=&city_code=STO&search_mode=indexed&locale=en` [c3:603, 605] -> `{"result":[]}` (only empty results captured).
- `POST /v52/voucher/redeem` [c3:275] `{"code","user_id","locale"}` -> error `{"errors":[{code,message,status}]}` (invalid code).

### Confirmed by capture 3 (rules used by the app)
- Check-in window = `[start - early_check_in_minutes, start - late_check_in_minutes]`; "Book until" = `start - bookable_latest` (s); "Cancel until" (late cancellation) = `start - unbookable_latest` (s). Values seen: (5, 30, 43200, 600/300) and (10, 60, 43200, 600) [c3:49 and 55 class payloads].
- Notifications still carry `read:false` everywhere and no read/mark-seen call exists, so the red dot is client-side "new since last opened".

### Plan prices (capture 2)
- `GET /v52/membership/info?city_code=STO&tier_code=BASE|BLACK|EPIC&commitment_months=12&user_id=&locale=en` [c2:426] -> `{"membership_info":{price,original_price(öre, annual/month),original_flex_price(öre, no commitment),pre_pay_price,pre_pay_periods[...],discounts[...],start_date,end_date,tier_code,city_code}}`. Used for the Membership plans screen. Changing plans was not captured.

## Capture 4 additions (`c4:N`)
- Per-studio limits: `GET /v52/studio/user_visit_limit?user_id=&studio_id=<id>&month=YYYYMM&locale=en` [c4:34, 73, 85; also c3:56, 63, 66]. It returns `limits[]` with `type`:
  - `STUDIO`: the per-studio monthly visit limit for the user's tier. This drives the studio/class top-bar pill: `total>0` gives "used / total"; `total==0` means unlimited and shows ∞ (STC gyms); `total==-1` means not included in the tier and shows "0 / 0" (e.g. Wellness spas for BASE).
  - `MONTHLY`: account-wide visits ("Total monthly visits", e.g. 3/20).
  - `WELLNESS_MONTHLY`: wellness visits (-1 for BASE, 4 BLACK, 8 EPIC).
  - `SIMULTANEOUS`: bookings at a time (3 BASE / 4 BLACK / 5 EPIC). This is the "0 / 3" pill on My classes.
- Paid tickets (Wellness): `GET /v52/studio/<id>/opening_hour/schedule?...&include_studio_user_attendance_info=true` [c4:31] gives `schedule[].studio_user_attendance_info{admission_access:false, price:28000 (öre), currency:"SEK", visit_limit_reached:true, visit_limit_reached_types:["STUDIO","WELLNESS_MONTHLY"]}`. That pair is what the app shows as "Buy ticket for SEK 280". Class payloads carry `dynamic_prices{BASE:23000,...}` and `user_attendance_info{admission_access:false, booking_limit_reached, visit_limit_reached}` for the same case [c4:96]. The purchase call itself was not captured (and is deliberately not implemented).
- Studio `label:"WELLNESS"` [c4:97] is the "Wellness" tag. Studio photos come from `studio_photos[].photo.file_id` with `order` (`include_studio_photos=true&include_studio_photos_photo=true`).
- `tier_level` on studios does NOT map 1:1 to the access tier: the spa in c4 has `tier_level:3` but per-studio limits BASE -1 / BLACK 2 / EPIC 4, and another Wellness studio has `tier_level:1`. Use the `STUDIO` limit items instead.
- c4 has no new write endpoints. The only request body is `POST /v52/booking/offline/done` `{"locale":"en"}` [c4:15].

### Studio page rules (from app screenshots, Oct 2026)
- Notice banner = studio `alerts[].message` (type `INFO`, sorted by `order`; request `include_alerts=true&exclude_expired_alerts=true`) [c2:212]. The `alert` string field was null in all captures.
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

## Capture 7 additions (`c7:N`)
- Class detail with the visit limit reached [c7:125] (request `include_studio_user_attendance_info=true`): `class.user_attendance_info` = `{id, admission_access:false, booking_credit_access, booking_credit_amount, price:22000 (öre), booking_voucher_access, booking_voucher_id, trial, user_tier_code:"BASE", booking_limit_reached:true, visit_limit_reached:true, visit_limit_reached_types:["STUDIO"]}`. That is the original's "Buy for SEK 220". `dynamic_prices` is `{"BASE":0,"BLACK":0,"EPIC":0,"FREE":-1}` there too, so it is not the drop-in price; the class has `currency:"sek"`. Classes within the limit [c7:70, 84, 97] have `admission_access:true`, `price:null`, `visit_limit_reached:false`.
- `GET /v52/studio/user_visit_limit?studio_id=&user_id=&month=YYYYMM` [c7:132, 122, 76, 91, 106] -> `limits[{id, total, total_trial, used, remaining, within_limit, resolvable_by_unbooking, resets_at:"2026-10-31T23:00:00Z" (UTC; 1 Nov local), month:202610, note, type:"STUDIO"|"MONTHLY"|"SIMULTANEOUS", visit_limit_type, items:[{id, visit_limit_id, label, limit, period:"MONTHLY"}]}]`. `STUDIO` items come as EPIC, BLACK, BASE; the original's visit-limit sheet lists them BASE, BLACK, EPIC. An unlimited studio has `total:0, remaining:0, within_limit:true`.
- Waitlist promotion: standby `booking_id` is null on every entry [c7:80]. Once the user gets a spot, the entry is gone from `GET /v52/standby` and the booking shows in `GET /v52/booking` (same `class_id`) [c7:64].
- The original's booking list: `GET /v52/booking?limit=30&deleted=false&class_start_time_after=<now-24h>&user_id=&include_class=true&include_class_dynamic_prices=true` [c7:64], newest first; `metadata.pagination{count,limit,offset,next_offset,next_cursor:null,prev_cursor}`. Clients should follow `next_cursor` until null; a waitlist entry that vanished from `/v52/standby` while a booking with its `class_id` exists was promoted, not dropped.
- Still no purchase call for the drop-in ("Buy for SEK n"); the apps show a "not available" message instead.

### Still not captured
Token refresh; check-in other than the STC door QR (`POST /v52/studio/check_in` appears only in capture 1); membership upgrade, pause and cancel (prices: `GET /v52/membership/info`, c2:426); profile photo upload; review submission; notification mark-read; drop-in/ticket purchase; ticket (no endpoint; the app renders it from the checked-in booking).
