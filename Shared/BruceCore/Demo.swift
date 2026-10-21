import Foundation

/// Offline placeholder data for `BRUCE_DEMO=1` (UI preview / screenshots). No personal data.
extension AppModel {
    /// One sample area around Södermalm for the demo filter chips.
    static let demoAreas: [SavedArea] = [SavedArea(name: "Södermalm", cityId: 1, points: [
        GeoPoint(lat: 59.3225, lon: 18.0280), GeoPoint(lat: 59.3230, lon: 18.0900), GeoPoint(lat: 59.3120, lon: 18.1050),
        GeoPoint(lat: 59.3030, lon: 18.0850), GeoPoint(lat: 59.3060, lon: 18.0300)])]

    func loadDemo() {
        let cal = BruceDate.calendar
        let iso = ISO8601DateFormatter()
        func at(_ dayOffset: Int, _ h: Int, _ min: Int) -> String {
            let d = cal.date(bySettingHour: h, minute: min, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: Date())!)!
            return iso.string(from: d)
        }
        func dec<T: Decodable>(_ t: T.Type, _ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }

        studios = dec([BruceAPI.Studio].self, """
        [{"id":1724,"name":"STC Rosenlundsparken","status":"LIVE","vicinity":"Södermalm","city_id":1,"qr_code_id":"stc:13994",
          "photo":"k5pxisc2ienijh72umlm","rating":{"total":270,"average":470,"distribution":{"1":1,"2":2,"3":11,"4":46,"5":210}},
          "studio_categories":[{"category_id":1,"main":true,"order":0,"category":{"id":1,"title":"Gym"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example street 1","zip_code":"118 00","city":"Stockholm","latitude":59.3165,"longitude":18.0600}}],
          "has_openings":true,"visit_limit":{"items":[{"label":"BASE","limit":0},{"label":"BLACK","limit":0},{"label":"EPIC","limit":0}]},
          "description":"A placeholder gym used for the offline demo. Strength and cardio areas, open early to late.\\n\\n**Good to know**\\n\\n* Showers in every changing room.\\n* Towels for rent at the desk.\\n* Indoor shoes only in the training hall.",
          "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}}]},
         {"id":1489,"name":"Example Yoga Studio","status":"LIVE","vicinity":"Stockholm","city_id":1,"qr_code_id":"930",
          "integration_door_type":"parakey","parakey_config":{"id":13,"optional":true},
          "photo":"mfrnofbzeqyucdflpasg","rating":{"total":120,"average":482},
          "studio_categories":[{"category_id":2,"main":true,"order":0,"category":{"id":2,"title":"Yoga"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example road 4","zip_code":"104 05","city":"Stockholm","latitude":59.3655,"longitude":18.0570}}],
          "studio_facilities":[{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"locker","title":"Locker"}}],
          "visit_limit":{"items":[{"label":"BASE","limit":2},{"label":"BLACK","limit":4},{"label":"EPIC","limit":8}]},
          "description":"A placeholder studio used for the offline demo."}]
        """)
        categories = BruceAPI.Category.demo
        home = dec([BruceAPI.HomeSection].self, """
        [{"title":"Spotlight","type":"SPOTLIGHT","items":[
          {"type":"CLASS","class_name":"High Intensity","class_id":9001,"studio_name":"Example Yoga Studio","studio_id":1489,"photo":"mfrnofbzeqyucdflpasg","start_time":"\(at(1, 11, 30))"},
          {"type":"CLASS","class_name":"Strength","class_id":9002,"studio_name":"STC Rosenlundsparken","studio_id":1724,"photo":"k5pxisc2ienijh72umlm","start_time":"\(at(2, 18, 45))"},
          {"type":"CLASS","class_name":"Hot Yoga","class_id":9003,"studio_name":"Example Yoga Studio","studio_id":1489,"photo":"xdz9eqgslqobguwuiqn8","start_time":"\(at(3, 17, 0))"}]},
         {"title":"Categories","type":"CATEGORIES","items":[
          {"type":"CATEGORY","category_id":1,"title":"Gym","photo":"ulopoksuf88nlz90lmsz"},
          {"type":"CATEGORY","category_id":5,"title":"Meditation","photo":"dgl20t8p7zqpugxw9ron"}]},
         {"title":"Nearby gyms","type":"NEARBY_GYMS","items":[
          {"type":"STUDIO","studio_name":"STC Rosenlundsparken","studio_id":1724,"vicinities":["Södermalm"],"categories":["Gym"],"distance":650,"photo":"k5pxisc2ienijh72umlm"},
          {"type":"STUDIO","studio_name":"Example Yoga Studio","studio_id":1489,"vicinities":["Stockholm"],"categories":["Yoga"],"distance":2400,"photo":"mfrnofbzeqyucdflpasg"}]},
         {"title":"New studios","type":"NEW_STUDIO","items":[
          {"type":"STUDIO","studio_name":"Example Yoga Studio","studio_id":1489,"vicinities":["Odenplan"],"categories":["Yoga"],"photo":"xdz9eqgslqobguwuiqn8"}]}]
        """)
        let classes = dec([BruceAPI.BruceClass].self, """
        [{"id":9001,"studio_id":1489,"title":"High Intensity","start_time":"\(at(1, 11, 30))","end_time":"\(at(1, 12, 15))","spots":20,"available_spots":2,
          "instructor":"Instructor A","description":"A placeholder interval class for the offline demo.\\n\\nShort, *hard* intervals with **active rest**:\\n\\n1. Warm-up\\n2. Four rounds of intervals\\n3. Stretch",
          "bookable_latest_time":"\(at(1, 11, 20))","unbookable_latest_time":"\(at(0, 23, 30))","unbookable_latest":43200,"early_check_in_minutes":30,"late_check_in_minutes":5,
          "class_categories":[{"category_id":12,"main":true}]},
         {"id":9004,"studio_id":1724,"title":"Full Body Strength","start_time":"\(at(0, 21, 0))","end_time":"\(at(0, 21, 45))","instructor":"Instructor B","available_spots":3},
         {"id":9005,"studio_id":1489,"title":"Hatha Flow","start_time":"\(at(0, 22, 0))","end_time":"\(at(0, 23, 30))","instructor":"Instructor C","available_spots":8,"class_categories":[{"category_id":2,"main":true}]},
         {"id":9008,"studio_id":1724,"title":"Functional","start_time":"\(at(0, 23, 25))","end_time":"\(at(0, 23, 59))","spots":12,"available_spots":0,
          "instructor":"Instructor F","alert":"Placeholder notice: this class is held in the outdoor area.","description":"A placeholder functional class for the offline demo.","bookable_latest_time":"\(at(0, 23, 15))","unbookable_latest_time":"\(at(0, 11, 25))","early_check_in_minutes":60,"late_check_in_minutes":10,
          "class_categories":[{"category_id":12,"main":true}]},
         {"id":9006,"studio_id":1489,"title":"Morning Flow","start_time":"\(at(1, 7, 0))","end_time":"\(at(1, 8, 0))","instructor":"Instructor D","available_spots":6,"class_categories":[{"category_id":2,"main":true}]},
         {"id":9011,"studio_id":9520,"title":"Sound Bath Workshop","start_time":"\(at(10, 14, 0))","end_time":"\(at(10, 15, 30))","instructor":"Instructor G","spots":12,"available_spots":12,
          "bookable_earliest_time":"\(at(3, 14, 0))","bookable_latest_time":"\(at(10, 13, 50))","unbookable_latest_time":"\(at(10, 2, 0))","unbookable_latest":43200,"early_check_in_minutes":30,"late_check_in_minutes":5,
          "description":"A placeholder one-off workshop for the offline demo. Listed two weeks ahead, bookable from a week before.","class_categories":[{"category_id":5,"main":true}]},
         {"id":9009,"studio_id":9520,"title":"Salt Cave","start_time":"\(at(0, 22, 30))","end_time":"\(at(0, 23, 15))","instructor":"**Instructor G - English speaking","spots":6,"available_spots":4},
         {"id":9010,"studio_id":1489,"title":"Deleted Placeholder","start_time":"\(at(0, 22, 45))","end_time":"\(at(0, 23, 30))","instructor":"Instructor H","available_spots":5,"deleted":true,"deleted_at":"\(at(0, 8, 0))"},
         {"id":9007,"studio_id":1489,"title":"Morning Meditation","start_time":"\(at(1, 9, 0))","end_time":"\(at(1, 9, 45))","instructor":"Instructor E","available_spots":9,"class_categories":[{"category_id":2,"main":true}]}]
        """)
        // Soft-deleted classes are dropped like in the live fetches (9010 must not show up).
        for c in classes where c.isListed {
            classDetails[c.id] = c
            classesByDay[cal.startOfDay(for: c.start!), default: []].append(c)
        }
        for k in classesByDay.keys { classesByDay[k]?.sort { $0.startTime < $1.startTime } }
        // Demo check-in today at the demo gym (drives "Show ticket").
        pastBookings = [BruceAPI.Booking(id: 5001, classId: nil, studioId: 1724, checkedInAt: at(0, 7, 51), class: nil)]
        schedules[1724] = (0..<7).map { i in
            BruceAPI.ScheduleEntry(start: at(i, 5, 0), end: at(i, 23, 0), isAllDay: false)
        }
        friendsBookings = dec([BruceAPI.FriendBooking].self, #"[{"id":1,"user_id":1,"class_id":9006},{"id":2,"user_id":2,"class_id":9001}]"#).map { b in
            BruceAPI.FriendBooking(id: b.id, userId: b.userId, classId: b.classId, class: classDetails[b.classId ?? 0])
        }
        classAttendees[9008] = dec([BruceAPI.ClassAttendee].self, """
        [{"id":11,"user":{"id":11,"first_name":"Alex","display_name":"Alex","social":true}},{"id":12,"user":{"id":12,"first_name":"Sam","display_name":"Sam","social":true}},
         {"id":13},{"id":14},{"id":15,"user_id":1}]
        """)
        // Public city facts (centre, strike-unblock price) so the policy texts show their API-driven values.
        cities = dec([BruceAPI.City].self, #"[{"id":1,"name":"Stockholm","code":"STO","coordinates":{"latitude":59.3293,"longitude":18.0686},"user_strike_block_un_lock_price":14000}]"#)
        invites = dec([BruceAPI.Voucher].self, #"[{"id":1,"code":"demo01"},{"id":2,"code":"demo02"},{"id":3,"code":"demo03"},{"id":4,"code":"demo04","user_id":1}]"#)
        notificationsSeenAt = Date().addingTimeInterval(-3600 * 30)
        notifications = dec([BruceAPI.BruceNotification].self, """
        [{"id":4,"created_at":"\(at(0, 0, 20))","type":"STANDBY_AVAILABLE","title":"Free spot","message":"Available spot for Functional today 23:25 (placeholder)","read":false,"meta":{"class_id":9008,"studio_id":null}},
         {"id":5,"created_at":"\(at(0, 0, 15))","type":"CHECK_IN_REMINDER","title":"Check In","message":"Time to check in at Hot Yoga (placeholder)","read":false,"meta":{"class_id":9003,"studio_id":null}},
         {"id":1,"created_at":"\(at(0, 0, 11))","type":"BOOKING_CANCELLED","title":"Booking cancelled","message":"Cancellation: High Intensity (placeholder)","read":false,"meta":{"class_id":9001,"studio_id":null}},
         {"id":6,"created_at":"\(at(0, 0, 8))","type":"USER_STRIKE","title":"Late cancellation","message":"You made a late cancellation on High Intensity (placeholder)","read":false,"meta":{"class_id":null,"studio_id":null}},
         {"id":3,"created_at":"\(at(0, 0, 5))","type":"CLASS_MESSAGE","title":"Hatha Flow has been cancelled.","message":"Too few bookings (placeholder)","read":false,"meta":{"class_id":9002,"studio_id":null,"photo":"k5pxisc2ienijh72umlm"}},
         {"id":2,"created_at":"\(at(-2, 19, 3))","type":"BOOKING_REMINDER","title":"Booking reminder","message":"Your class starts tomorrow (placeholder)","read":false,"meta":{"class_id":9003,"studio_id":null,"photo":"xdz9eqgslqobguwuiqn8"}}]
        """)
        friends = dec([BruceAPI.Friend].self, """
        [{"id":1,"friend_user":{"id":1,"first_name":"Friend","last_name":"One"}},{"id":2,"friend_user":{"id":2,"first_name":"Friend","last_name":"Two"}}]
        """)
        user = dec(BruceAPI.UserLite.self, #"{"id":0,"first_name":"Demo","last_name":"Member","email":"demo@example.com","email_confirmed":true,"national_identity":"199001011234","photo_valid":true,"social":true,"parakey_email":"demo@example.com","secret":"demo"}"#)
        social = true
        // Fictional spa: paid ticket (admission_access=false, price 28000 öre), slot ending within 2 h.
        let spa = dec(BruceAPI.Studio.self, """
        {"id":9520,"name":"Example Salt Spa","status":"LIVE","vicinity":"Gamla Stan","city_id":1,"qr_code_id":"9520","label":"WELLNESS",
         "has_openings":true,"rating":{"total":120,"average":490,"distribution":{"1":0,"2":1,"3":2,"4":10,"5":107}},
         "studio_categories":[{"category_id":25,"main":true,"order":0,"category":{"id":25,"title":"Spa"}}],
         "studio_photos":[{"order":0,"photo":{"file_id":"a"}},{"order":1,"photo":{"file_id":"b"}},{"order":2,"photo":{"file_id":"c"}}],
         "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"locker","title":"Locker"}}],
         "description":"A fictional salt spa used for the offline demo."}
        """)
        studios.append(spa)
        // Fictional bath house: open for solo training earlier today, closed now; favourite; 8 visits/month.
        let bath = dec(BruceAPI.Studio.self, """
        {"id":9600,"name":"Example Bath House","status":"LIVE","vicinity":"Södermalm","city_id":1,"qr_code_id":"9600","has_openings":true,
         "rating":{"total":300,"average":480,"distribution":{"1":2,"2":3,"3":10,"4":40,"5":245}},
         "studio_categories":[{"category_id":27,"main":true,"order":0,"category":{"id":27,"title":"Swimming"}},{"category_id":1,"main":false,"order":1,"category":{"id":1,"title":"Gym"}}],
         "studio_photos":[{"order":0,"photo":{"file_id":"a"}},{"order":1,"photo":{"file_id":"b"}},{"order":2,"photo":{"file_id":"c"}}],
         "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"sauna","title":"Sauna"}},{"facility":{"code":"locker","title":"Locker"}}],
         "description":"A fictional bath house used for the offline demo."}
        """)
        studios.append(bath)
        favoriteIds[9600] = 1
        // Fictional club with classes + solo training + notice banner (Hötorget-like), and a hall closing soon.
        let club = dec(BruceAPI.Studio.self, """
        {"id":9700,"name":"Example City Club","status":"LIVE","vicinity":"Norrmalm","city_id":1,"qr_code_id":"stc:99999","has_openings":true,"has_classes":true,
         "rating":{"total":500,"average":480},
         "alerts":[{"id":1,"message":"Scan the QR code at the entrance. Collect class tickets at the desk at least ten minutes before start.","type":"INFO","order":0,"start_date":"2026-01-01T00:00:00Z","end_date":null},
                   {"id":2,"message":"Expired placeholder notice (not shown).","type":"INFO","order":1,"start_date":"2025-01-01T00:00:00Z","end_date":"2025-02-01T00:00:00Z"}],
         "studio_categories":[{"category_id":21,"order":0,"category":{"id":21,"title":"Group training"}},{"category_id":1,"order":1,"category":{"id":1,"title":"Gym"}}],
         "studio_photos":[{"order":0,"photo":{"file_id":"a"}},{"order":1,"photo":{"file_id":"b"}},{"order":2,"photo":{"file_id":"c"}},{"order":3,"photo":{"file_id":"d"}}],
         "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"shower","title":"Shower"}}]}
        """)
        let hall = dec(BruceAPI.Studio.self, """
        {"id":9800,"name":"Example Climbing Hall","status":"LIVE","vicinity":"Akalla","city_id":1,"qr_code_id":"9800","has_openings":true,
         "rating":{"total":90,"average":500},
         "studio_categories":[{"category_id":7,"order":0,"category":{"id":7,"title":"Climbing"}},{"category_id":1,"order":1,"category":{"id":1,"title":"Gym"}}],
         "studio_facilities":[{"facility":{"code":"changing","title":"Changing room"}},{"facility":{"code":"parking","title":"Parking"}},{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"sauna","title":"Sauna"}},{"facility":{"code":"locker","title":"Locker"}}]}
        """)
        studios += [club, hall]
        favoriteIds[9700] = 2
        let nowD = Date()
        schedules[9700] = [BruceAPI.ScheduleEntry(start: iso.string(from: nowD.addingTimeInterval(-8 * 3600)), end: iso.string(from: nowD.addingTimeInterval(3 * 3600 + 36 * 60)), isAllDay: false)]
        schedules[9800] = [BruceAPI.ScheduleEntry(start: iso.string(from: nowD.addingTimeInterval(-8 * 3600)), end: iso.string(from: nowD.addingTimeInterval(37 * 60)), isAllDay: false)]
        studioLimits[9700] = dec([BruceAPI.VisitLimit].self, #"[{"type":"STUDIO","total":0,"used":0}]"#)
        studioLimits[9800] = dec([BruceAPI.VisitLimit].self, #"[{"type":"STUDIO","total":1,"used":0}]"#)
        studioClasses[9700] = (0..<5).map { i in
            dec(BruceAPI.BruceClass.self, """
            {"id":\(9900 + i),"studio_id":9700,"title":"\(["Spinning", "Body Pump", "Yoga", "HIIT", "Core"][i])","start_time":"\(at(i / 2 + 1, 7 + i * 2, 0))","end_time":"\(at(i / 2 + 1, 8 + i * 2, 0))","instructor":"Instructor \(i + 1)","available_spots":5}
            """)
        }
        schedules[9600] = [BruceAPI.ScheduleEntry(start: iso.string(from: Date().addingTimeInterval(-10 * 3600)), end: iso.string(from: Date().addingTimeInterval(-1 * 3600)), isAllDay: false)]
        studioLimits[9600] = dec([BruceAPI.VisitLimit].self, #"[{"type":"STUDIO","total":8,"used":0}]"#)
        let now = Date()
        schedules[9520] = [BruceAPI.ScheduleEntry(start: iso.string(from: now.addingTimeInterval(-6 * 3600)), end: iso.string(from: now.addingTimeInterval(29 * 60)),
                                                  isAllDay: false, attendance: BruceAPI.AttendanceInfo(admissionAccess: false, price: 28000, currency: "SEK"))]
        studioLimits[9520] = dec([BruceAPI.VisitLimit].self, #"[{"type":"STUDIO","total":-1,"used":0},{"type":"SIMULTANEOUS","total":3,"used":0}]"#)
        studioLimits[1724] = dec([BruceAPI.VisitLimit].self, #"[{"type":"STUDIO","total":0,"used":0},{"type":"SIMULTANEOUS","total":3,"used":0}]"#)
        reviews[1724] = dec([BruceAPI.Review].self, """
        [{"id":1,"rating":2,"comment":"Clean and quiet in the mornings.","created_at":"\(at(-3, 10, 0))","booking":{"class":{"opening":true},"user":{"first_name":"Alex"}}},
         {"id":2,"rating":5,"comment":"Good machines, friendly vibe.","created_at":"\(at(-12, 10, 0))","booking":{"class":{"opening":true},"user":{"first_name":"Sam"}}},
         {"id":3,"rating":4,"comment":"Busy after work, fine otherwise.","created_at":"\(at(-40, 10, 0))","booking":{"class":{"opening":true},"user":{"first_name":"Robin"}}},
         {"id":4,"rating":3,"comment":"Placeholder review text for the demo.","created_at":"2026-02-08T10:00:00Z","booking":{"class":{"opening":true},"user":{"first_name":"Exampleina Placeholder-Longname"}}}]
        """)
        notificationSetting = dec(BruceAPI.NotificationSetting.self, """
        {"id":1,"marketing_email":true,"marketing_push":true,"marketing_sms":false,"types":[{"key":"booking_reminder","enabled":true},{"key":"check_in_reminder","enabled":true},{"key":"new_studio","enabled":false}]}
        """)
        payments = dec([BruceAPI.Payment].self, #"[{"id":1,"created_at":"2026-10-01T06:00:00Z","amount":54900,"currency":"SEK","type":"MEMBERSHIP_RENEWAL","status":"successful"},{"id":2,"created_at":"2026-09-20T06:00:00Z","amount":23000,"currency":"SEK","type":"BOOKING","status":"successful"}]"#)
        aggregate = dec([BruceAPI.DayCount].self, #"[{"day":20261002,"count":1},{"day":20261005,"count":2},{"day":20260915,"count":1}]"#)
        membership = dec(BruceAPI.MembershipInfo.self, """
        {"membership":true,"paused":false,"membership_tier":"BASE","current_membership_price":549,"available_credits":0,
         "next_payment":"2026-11-01T00:00:00Z","admission_access_until":"2026-11-01T23:59:59Z","remaining_pause_days":60,"remaining_pause_periods":1,
         "pause_days_total":60,"total_pause_periods":2,"has_notice_period":false,"commitment_months":12,"committed_until":"2027-06-01T00:00:00Z","prolong_commitment":true}
        """)
        visitLimits = dec([BruceAPI.VisitLimit].self, #"[{"total":20,"used":3,"remaining":17,"type":"MONTHLY"}]"#)
        blockInfo = dec(BruceAPI.BlockInfo.self, #"{"strike_count":1,"blocked":false,"free_unlocks_remaining":1,"total_free_unlocks":3}"#)
        standbys = [BruceAPI.ClassHolder(id: 1, class: classes.first { $0.id == 9004 })]
        paymentMethods = dec([BruceAPI.PaymentMethod].self, #"[{"id":1,"name":"VISA","type":"APPLE_PAY","expiration":129,"default":true}]"#)

        // "Similar classes" for the full class 9008 (cards point at other demo classes).
        similarClasses[9008] = dec([BruceAPI.ClassCard].self, """
        [{"id":9005,"title":"Hatha Flow","photo":"mfrnofbzeqyucdflpasg","distance":2400,"start_time":"\(at(0, 22, 0))","end_time":"\(at(0, 23, 30))","studio":{"id":1489,"name":"Example Yoga Studio"}},
         {"id":9001,"title":"High Intensity","photo":"k5pxisc2ienijh72umlm","distance":2400,"start_time":"\(at(1, 11, 30))","end_time":"\(at(1, 12, 15))","studio":{"id":1489,"name":"Example Yoga Studio"}},
         {"id":9006,"title":"Morning Flow","photo":"xdz9eqgslqobguwuiqn8","distance":2400,"start_time":"\(at(1, 7, 0))","end_time":"\(at(1, 8, 0))","studio":{"id":1489,"name":"Example Yoga Studio"}}]
        """)

        loadDemoInsights()
        visitHistory = Self.demoVisits
        loadDemoRaces()   // after the history: Train for it adds this week's check-ins
        Task { await refreshRecommendations() }

        // BRUCE_SCREEN=<name> opens a screen directly (for screenshots).
        switch AppModel.setting("BRUCE_SCREEN") ?? "" {
        case "foryou": push(.forYou)
        case "places": sheets = [.settings, .places]
        case "editplace": sheets = [.settings, .places, .editPlace(recSettings.work?.id)]
        case "goals": tab = .myClasses; push(.goals)
        case "goalscard": tab = .myClasses
        case "newgoal": tab = .myClasses; push(.goals); present(.editGoal(nil))
        case "challenges": tab = .friends; demoFriendsTab = 1
        case "challenge": tab = .friends; demoFriendsTab = 1; push(.challenge("demoOct"))
        case "challengemember": tab = .friends; demoFriendsTab = 1; push(.challenge("demoOct")); demoChallengeMember = 7
        case "newchallenge": tab = .friends; demoFriendsTab = 1; present(.newChallenge)
        case "wrapped": wrappedOpen = true
        case "wrappedshare": wrappedOpen = true; demoWrappedCard = 99
        case "explore": tab = .explore
        case "races": tab = .explore; demoExploreTab = 2
        case "race": tab = .explore; demoExploreTab = 2; push(.race("vasaloppet-2027"))
        case "myraces", "thisweek": tab = .myClasses; showRacesInMyClasses = true
        case "myrace": tab = .myClasses; showRacesInMyClasses = true; push(.race("hyrox-stockholm-2026"))
        // Train for it (RacePlanner.swift): a race without a plan yet, the plan sheet before starting and in week 3 of 10.
        case "trainforit": tab = .myClasses; showRacesInMyClasses = true; push(.race("tough-viking-stadion-2027"))
        case "planstart": tab = .myClasses; showRacesInMyClasses = true; push(.race("tough-viking-stadion-2027")); present(.racePlan("tough-viking-stadion-2027"))
        case "raceplan": tab = .myClasses; showRacesInMyClasses = true; push(.race("hyrox-stockholm-2026")); present(.racePlan("hyrox-stockholm-2026"))
        case "addrace": tab = .myClasses; showRacesInMyClasses = true; present(.editRace(nil))
        case "classes": tab = .explore; demoExploreTab = 1
        case "classesfiltered": tab = .explore; demoExploreTab = 1; currentlyOpen = true
        case "detail": push(.classDetail(9001))
        case "parakey": push(.classDetail(9001)); present(.parakey(1489))
        case "studio": push(.studio(1724))
        case "studiohours": push(.studio(1724)); demoHoursOpen = true
        case "reviews": push(.studio(1724)); demoStudioTab = 1
        case "ticket": push(.studio(1724)); present(.ticket(5001))
        case "friends": tab = .friends
        case "myclasses": tab = .myClasses
        case "mybookings":
            bookings = [9001, 9006].compactMap { id in classDetails[id].map { BruceAPI.Booking(id: id, classId: id, studioId: $0.studioId, checkedInAt: nil, class: $0) } }
            tab = .myClasses
        case "notifications": present(.notifications)
        case "menu": present(.menu)
        case "account": present(.account)
        case "membership": sheets = [.account, .membership]
        case "wellness": present(.account); wellnessOverlay = true
        case "credits": sheets = [.account, .credits]
        case "strikes": sheets = [.account, .strikes]
        case "payment": sheets = [.account, .payment]
        case "settings": present(.settings)
        case "autobook": present(.autoBook)
        case "checkin": present(.checkIn)
        case "categories": push(.categories)
        case "category": push(.category(2)); demoCategoryTab = 1
        case "actions": push(.category(2)); demoCategoryTab = 1; classActions = 9006
        case "full": push(.classDetail(9008))
        case "similar": push(.classDetail(9008)); present(.similarClasses(9008))
        case "alerts": push(.classDetail(9008)); demoScrollBottom = true
        case "area": tab = .explore; if let a = areas.first { present(.area(a.id)) }
        case "waitlisted": standbys.append(BruceAPI.ClassHolder(id: 77, class: classDetails[9008])); push(.classDetail(9008))
        case "leave": standbys.append(BruceAPI.ClassHolder(id: 77, class: classDetails[9008])); push(.classDetail(9008)); askLeaveWaitlist(9008)
        case "joined": push(.classDetail(9008)); infoAlert = Copy.waitlistJoined
        case "limitreached", "visitlimit":
            // Example Yoga Studio with this month's BASE visits used up: "Buy for SEK 220" + limit notice.
            // Shapes as recorded [c7:125, 132]: price in user_attendance_info, dynamic_prices all 0, items EPIC..BASE.
            let cal = BruceDate.calendar
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            let resets = iso.string(from: cal.date(byAdding: .month, value: 1, to: monthStart)!)
            studioLimits[1489] = dec([BruceAPI.VisitLimit].self, """
            [{"id":"U1RVRElPOkdFTkVSQUw=","total":1,"used":1,"remaining":0,"within_limit":false,"resolvable_by_unbooking":false,"resets_at":"\(resets)","month":\(BruceDate.format(Date(), "yyyyMM")),"type":"STUDIO","visit_limit_type":"GENERAL",
              "items":[{"id":3,"label":"EPIC","limit":8,"period":"MONTHLY"},{"id":2,"label":"BLACK","limit":8,"period":"MONTHLY"},{"id":1,"label":"BASE","limit":1,"period":"MONTHLY"}]},
             {"id":"U0lNVUxUQU5FT1VT","total":3,"used":1,"remaining":2,"within_limit":true,"resets_at":"\(resets)","type":"SIMULTANEOUS","items":[]}]
            """)
            classDetails[9006]?.dynamicPrices = BruceAPI.TierPrices(["BASE": 0, "BLACK": 0, "EPIC": 0, "FREE": -1])
            classDetails[9006]?.currency = "sek"
            classDetails[9006]?.userAttendanceInfo = dec(BruceAPI.AttendanceInfo.self, """
            {"id":9006,"admission_access":false,"booking_credit_access":false,"booking_credit_amount":null,"price":22000,"booking_voucher_access":false,
             "booking_voucher_id":null,"trial":false,"user_tier_code":"BASE","booking_limit_reached":true,"visit_limit_reached":true,"visit_limit_reached_types":["STUDIO"]}
            """)
            push(.classDetail(9006))
            if AppModel.setting("BRUCE_SCREEN") == "visitlimit" { present(.visitLimit(1489)) }
        case "waitlistbooked":
            // One waitlist entry got a spot: the API drops it from /standby and lists a booking instead [c7:80, 64].
            // loadMine keeps such an entry as "Booked"; here that end state is set directly.
            promotedStandbys = [BruceAPI.ClassHolder(id: 78, class: classDetails[9006])]
            bookings = [BruceAPI.Booking(id: 9106, classId: 9006, studioId: 1489, checkedInAt: nil, class: classDetails[9006])]
            tab = .myClasses; demoMyClassesTab = 1
        case "editprofile": sheets = [.account, .editProfile]
        case "pause": sheets = [.account, .membership, .pause]
        case "pausepicker": demoPausePicker = true; sheets = [.account, .membership, .pause]
        case "plans": sheets = [.account, .membership, .plans]
        case "spa": push(.studio(9520))
        case "closed": push(.studio(9600))
        case "club": push(.studio(9700))
        case "clubclasses": push(.studio(9700)); demoStudioTab = 1
        case "closingsoon": push(.studio(9800))
        case "checkout": push(.studio(9520)); present(.checkout(9520))
        case "statistics": sheets = [.account, .statistics]
        case "receipts": sheets = [.account, .receipts]
        case "rules": push(.classDetail(9001)); present(.bookingRules(9001))
        case "checkedin", "review":
            // A checked-in class that ended: stays in My classes, and is reviewable (POST /v52/review [c8:467]).
            let b = BruceAPI.Booking(id: 2, classId: 9001, studioId: 1489, checkedInAt: iso.string(from: Date().addingTimeInterval(-3600)),
                                     class: classDetails[9001])
            bookings = [b]; reviewable = [b]
            if AppModel.setting("BRUCE_SCREEN") == "review" { present(.review(2)) } else { tab = .myClasses }
        case "booked": bookings = [BruceAPI.Booking(id: 1, classId: 9001, studioId: 1489, checkedInAt: nil, class: classDetails[9001])]; push(.classDetail(9001))
        case "cancelsheet": bookings = [BruceAPI.Booking(id: 1, classId: 9001, studioId: 1489, checkedInAt: nil, class: classDetails[9001])]; push(.classDetail(9001)); present(.bookingRules(9001))
        case "addtocalendar": bookings = [BruceAPI.Booking(id: 1, classId: 9001, studioId: 1489, checkedInAt: nil, class: classDetails[9001])]; push(.classDetail(9001)); present(.addToCalendar(9001))
        case "cancelchips":
            // Today 23:25 (cancelling costs a strike already), tomorrow 07:00 and 11:30 (still free).
            bookings = [9008, 9006, 9001].compactMap { id in classDetails[id].map { BruceAPI.Booking(id: id, classId: id, studioId: $0.studioId, checkedInAt: nil, class: $0) } }
            tab = .myClasses
        case "bookagain":
            // The Statistics visit row's Book again for a class like 9006 (Morning Flow, Example Yoga Studio).
            if let t = BookAgainTemplate(studioId: 1489, masterId: nil, title: "Morning Flow", start: classDetails[9006]?.start.flatMap { cal.date(byAdding: .day, value: -7, to: $0) }, instructor: "Instructor D") {
                sheets = [.statistics, .bookAgain(t)]
            }
        case "widgets":
            bookings = [9006, 9001].compactMap { id in classDetails[id].map { BruceAPI.Booking(id: id, classId: id, studioId: $0.studioId, checkedInAt: nil, class: $0) } }
            present(.widgets)
        case "milestones": tab = .home   // the newest milestone card and "New to you" on Home (demo history)
        case "bookwhenopens": push(.classDetail(9011))
        case "bookwhenopenswatching": if let w = classDetails[9011].flatMap(OpeningWatch.init) { openingWatches = [w] }; push(.classDetail(9011))
        case "firstvisit": push(.classDetail(9009))   // Example Salt Spa: no check-in in the demo history
        case "firstvisitstudio": push(.studio(9800))   // Example Climbing Hall: never visited in the demo
        case "detailmap": push(.classDetail(9001)); demoScrollBottom = true
        case "invite": present(.invite)
        case "howitworks": sheets = [.invite, .howItWorks]
        case "voucher": present(.voucher)
        case "support": present(.support)
        case "help": present(.help)
        case "push": sheets = [.settings, .push]
        case "pushinfo": sheets = [.settings, .push, .pushInfo]
        case "quickcheckin": present(.quickCheckIn)
        case "checkinall": present(.quickCheckIn)   // iOS opens "Other studios" on top
        case "checkinbooked":
            // A booked class at the demo gym starting in 15 min: its check-in window is open now.
            let c = dec(BruceAPI.BruceClass.self, """
            {"id":9950,"studio_id":1724,"title":"Strength Circuit","start_time":"\(iso.string(from: Date().addingTimeInterval(15 * 60)))","end_time":"\(iso.string(from: Date().addingTimeInterval(60 * 60)))","instructor":"Instructor G","available_spots":4,"early_check_in_minutes":30,"late_check_in_minutes":5}
            """)
            classDetails[c.id] = c
            bookings = [BruceAPI.Booking(id: 9951, classId: c.id, studioId: 1724, checkedInAt: nil, class: c)]
            present(.quickCheckIn)
        case "confirm": present(.quickCheckIn); if let t = checkInTargets.first { askCheckIn(t) }
        case "filter": tab = .explore; demoExploreTab = 1; filterOpen = true
        case "classfilters": tab = .explore; demoExploreTab = 1; filterOpen = true; classFilters.slots = [.lunch]; classFilters.durations = [.short]; classFilters.sort = .distance
        case "selectcity": tab = .explore; filterOpen = true; present(.selectCity)
        case "newarea", "drawarea": tab = .explore; present(.newArea)
        case "areas", "deletearea": tab = .explore; filterOpen = true; selectedAreaId = areas.first?.id
        case "search": tab = .explore; present(.search)
        case "map": tab = .explore; exploreMap = true
        case "welcome": demoLoggedOut = true
        case "createaccount": demoLoggedOut = true; present(.createAccount)
        case "login": demoLoggedOut = true; present(.login)
        case "reset": demoLoggedOut = true; present(.resetPassword)
        case "sneakpeek": demoLoggedOut = true; sneakPeek = true; tab = .explore
        default: break
        }
    }
}

extension BruceAPI.Category {
    /// The main categories as `GET /v52/category` lists them (demo mode, and the tests of the Train for it mapping).
    static let demo: [BruceAPI.Category] = (try? JSONDecoder().decode([BruceAPI.Category].self, from: Data(demoJSON.utf8))) ?? []
    private static let demoJSON = """
        [{"id":1,"title":"Gym","photo":"ulopoksuf88nlz90lmsz"},{"id":5,"title":"Meditation","photo":"dgl20t8p7zqpugxw9ron"},
         {"id":3,"title":"Ball sports"},{"id":4,"title":"Breathwork"},{"id":2,"title":"Yoga","photo":"mfrnofbzeqyucdflpasg"},
         {"id":6,"title":"Cardio"},{"id":7,"title":"Climbing"},{"id":8,"title":"CrossFit"},{"id":9,"title":"Cycling"},
         {"id":10,"title":"Dance"},{"id":11,"title":"Family Training"},{"id":12,"title":"High-intensity","photo":"k5pxisc2ienijh72umlm"},
         {"id":13,"title":"Hyrox"},{"id":14,"title":"Martial arts"},{"id":15,"title":"Massage & Naprapathy"},{"id":16,"title":"Mobility"},
         {"id":17,"title":"Other"},{"id":18,"title":"Outdoor"},{"id":19,"title":"Pilates","photo":"xdz9eqgslqobguwuiqn8"},
         {"id":20,"title":"Pregnancy & Postnatal"},{"id":21,"title":"Racket sports"},{"id":22,"title":"Reformer"},{"id":23,"title":"Running"},
         {"id":24,"title":"Sauna"},{"id":25,"title":"Spa"},{"id":26,"title":"Strength"},{"id":27,"title":"Swimming"}]
    """
}
