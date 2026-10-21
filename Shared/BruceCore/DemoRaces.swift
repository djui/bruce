import Foundation

// Demo mode's races (Races.swift): a slice of the real catalog in docs/app/races.json, as checked on 21 Oct 2026, and
// four of them in My races (HYROX Stockholm on the Saturday in doubles with a Train for it plan in week 3 of 10, shared
// as going and with a crew; a price reminder; a sign-up reminder; Midnattsloppet 2026, run in August, with results).
// Friends going and the crew are fictional (RaceSocial.swift `loadDemoGoing`, `demoCrewChallenge`).
// RacesTests checks that every demo race matches the catalog file.

extension Race {
    static let demo: [Race] = (try? RaceCatalog.decode(Data(demoJSON.utf8))) ?? []

    private static let demoJSON = #"""
{"races": [
  {"id":"goteborgsvarvet-2026","name":"Göteborgsvarvet","type":"running","date":"2026-05-23","city":"Gothenburg","country":"SE","distancesKm":[21.1],"signupUrl":"https://www.goteborgsvarvet.se/nyheter/24-varv-runt-jorden-och-64-nationer-arets-goteborgsvarvet-i-siffror","status":"checkSite","resultsUrl":"https://www.goteborgsvarvet.se/startlista-resultat","checkedOn":"2026-10-21"},
  {"id":"midnattsloppet-stockholm-2026","name":"Midnattsloppet Stockholm","type":"running","date":"2026-08-15","city":"Stockholm","country":"SE","distancesKm":[5,10,21],"format":"evening run","signupUrl":"https://midnattsloppet.com/en/all-you-need-to-know-stockholm/","status":"checkSite","resultsUrl":"https://midnattsloppet.com/en/startlist-results/","checkedOn":"2026-10-21"},
  {"id":"hyrox-stockholm-2026","name":"HYROX Stockholm","type":"hyrox","date":"2026-12-10","endDate":"2026-12-13","city":"Solna","country":"SE","venue":"Strawberry Arena","distancesKm":[],"signupUrl":"https://hyrox.com/find-my-race/","platform":"vivenu","priceNote":"Singles 1,530 SEK, doubles 1,470 SEK per person, relay 870 SEK per person. Prices rise as spots fill. Spectators 220 SEK.","priceSteps":[{"amount":1470,"currency":"SEK","lowest":true}],"status":"open","resultsUrl":"https://results.hyrox.com/","checkedOn":"2026-10-21","formats":[{"code":"singles","title":"Singles","teamSize":1,"priceSteps":[{"amount":1530,"currency":"SEK"}],"note":"Open or Pro"},{"code":"doubles","title":"Doubles","teamSize":2,"priceSteps":[{"amount":1470,"currency":"SEK","per":"person"}],"note":"Open or Pro"},{"code":"relay","title":"Relay","teamSize":4,"priceSteps":[{"amount":870,"currency":"SEK","per":"person"}],"note":"2 runs and 2 stations each"},{"code":"adaptive","title":"Adaptive","teamSize":1}],"changeRule":"Changes only with the Flex add-on, bought at checkout: refunds up to 7 days before, plus one name change for doubles and relay. Without Flex, no changes.","startInfo":"Start wave by email a few days before. Be there 90 minutes early.","arriveMinutesBefore":90},
  {"id":"vasaloppet-2027","name":"Vasaloppet","type":"endurance","sport":"ski","date":"2027-03-07","city":"Mora","country":"SE","venue":"Sälen to Mora","distancesKm":[90],"signupUrl":"https://www.vasaloppet.se/en/ski/vasaloppet/","priceNote":"2,685 SEK until 5 Nov, then 2,985 SEK as a late entry","priceSteps":[{"until":"2026-11-05","amount":2685,"currency":"SEK"},{"from":"2026-11-06","amount":2985,"currency":"SEK"}],"status":"open","klassiker":true,"resultsUrl":"https://results.vasaloppet.se/?lang=EN_CAP","checkedOn":"2026-10-21"},
  {"id":"hyrox-copenhagen-2027","name":"HYROX Copenhagen","type":"hyrox","date":"2027-03-25","endDate":"2027-03-28","city":"Copenhagen","country":"DK","venue":"Bella Center","distancesKm":[],"signupUrl":"https://hyrox.com/find-my-race/","platform":"vivenu","priceNote":"Single 1,045 DKK","priceSteps":[{"amount":1045,"currency":"DKK","lowest":true}],"status":"open","resultsUrl":"https://results.hyrox.com/","checkedOn":"2026-10-21","formats":[{"code":"singles","title":"Singles","teamSize":1,"priceSteps":[{"amount":1045,"currency":"DKK"}],"note":"Open or Pro"},{"code":"doubles","title":"Doubles","teamSize":2,"note":"Open or Pro"},{"code":"relay","title":"Relay","teamSize":4}],"changeRule":"Changes only with the Flex add-on, bought at checkout: refunds up to 7 days before, plus one name change for doubles and relay. Without Flex, no changes.","startInfo":"Start wave by email a few days before. Be there 90 minutes early.","arriveMinutesBefore":90},
  {"id":"tough-viking-goteborg-2027","name":"Tough Viking Göteborg","type":"obstacle","date":"2027-04-24","city":"Gothenburg","country":"SE","venue":"Slottsskogen","distancesKm":[8],"signupUrl":"https://www.toughviking.se/","platform":"RaceID","priceNote":"750 SEK now","priceSteps":[{"amount":750,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"tough-viking-stadion-2027","name":"Tough Viking Stockholms Stadion","type":"obstacle","date":"2027-05-15","city":"Stockholm","country":"SE","venue":"Stockholms Stadion","distancesKm":[8],"format":"solo, duo, trio or team","signupUrl":"https://www.toughviking.se/","platform":"RaceID","priceNote":"750 SEK until 31 Oct, then 775 SEK. The 2027 main races step up by date: 699, 750, 775, 799, 899, then 999 SEK. The Stadion race also hosts the Swedish OCR Championships.","priceSteps":[{"until":"2026-10-31","amount":750,"currency":"SEK"},{"from":"2026-11-01","amount":775,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21","formats":[{"code":"open","title":"Open","teamSize":1,"note":"Female or male"},{"code":"duo","title":"Duo","teamSize":2},{"code":"trio","title":"Trio","teamSize":3},{"code":"team","title":"Team","teamSize":4,"note":"4 or more; corporate teams of 10+ can pay by invoice"}],"startInfo":"Personal start time, picked at registration and sent by SMS. Teammates register with the same team name and start group."},
  {"id":"goteborgsvarvet-2027","name":"Göteborgsvarvet","type":"running","date":"2027-05-22","city":"Gothenburg","country":"SE","distancesKm":[21.1],"signupUrl":"https://www.goteborgsvarvet.se/en/news/goteborgsvarvet-2027-is-sold-out","platform":"njuko","priceNote":"Sold out. There is a waitlist with entry transfers.","status":"soldOut","resultsUrl":"https://www.goteborgsvarvet.se/startlista-resultat","checkedOn":"2026-10-21"},
  {"id":"stockholm-marathon-2027","name":"Stockholm Marathon","type":"running","date":"2027-05-29","city":"Stockholm","country":"SE","distancesKm":[42.195],"signupUrl":"https://stockholmmarathon.se/eng/eng-lopare/","platform":"Haku","priceNote":"1,295, then 1,495, 1,795 and 1,995 SEK in four steps by date. The 2026 race sold out.","status":"checkSite","checkedOn":"2026-10-21","changeRule":"The entry is binding and personal, with no refund. Transfers weren't allowed under the 2025 terms.","startInfo":"Start groups A to G, seeded by earlier race times; pacers from 3:00 to 5:45. The bib is collected at the Expo, Thursday to Saturday before the race."},
  {"id":"vatternrundan-2027","name":"Vätternrundan","type":"endurance","sport":"bike","date":"2027-06-18","endDate":"2027-06-19","city":"Motala","country":"SE","distancesKm":[315],"signupUrl":"https://vatternrundan.se/en/races/vatternrundan-315km","priceNote":"2,100 SEK. Entries open at 19:00 on 25 Nov.","priceSteps":[{"amount":2100,"currency":"SEK"}],"status":"opensSoon","opensOn":"2026-11-25","klassiker":true,"resultsUrl":"https://result.vatternrundan.se/","checkedOn":"2026-10-21"},
  {"id":"vansbrosimningen-2027","name":"Vansbrosimningen","type":"endurance","sport":"swim","date":"2027-07-10","city":"Vansbro","country":"SE","distancesKm":[3],"signupUrl":"https://www.vansbrosimningen.se/","priceNote":"1,345–1,545 SEK","priceSteps":[{"amount":1345,"currency":"SEK","lowest":true}],"status":"open","klassiker":true,"resultsUrl":"https://vansbrosimningen.se/resultat/","checkedOn":"2026-10-21"},
  {"id":"ironman-703-jonkoping-2027","name":"IRONMAN 70.3 Jönköping","type":"triathlon","date":"2027-07-11","city":"Jönköping","country":"SE","distancesKm":[],"signupUrl":"https://www.ironman.com/races/im703-jonkoping","priceNote":"Sold out","status":"soldOut","checkedOn":"2026-10-21"},
  {"id":"midnattsloppet-stockholm-2027","name":"Midnattsloppet Stockholm","type":"running","date":"2027-08-14","city":"Stockholm","country":"SE","distancesKm":[5,10],"format":"evening run","signupUrl":"https://midnattsloppet.com/en/start-fee/","priceNote":"2027 prices come with the sign-up. In 2026 there were six price steps from 499 to 799 SEK, teams of 4 got 50 SEK off each, and entries could be paid with Epassi and other wellness allowances.","status":"opensSoon","opensOn":"2026-11-01","resultsUrl":"https://midnattsloppet.com/en/startlist-results/","checkedOn":"2026-10-21","changeRule":"Name change through the organiser before a deadline (10 Aug in 2025).","startInfo":"A start group every 5 minutes from 21:10 to 23:20, grouped by expected finish time. The race kit is picked up at a Stadium store."},
  {"id":"stockholm-half-marathon-2027","name":"Stockholm Half Marathon","type":"running","date":"2027-08-21","city":"Stockholm","country":"SE","distancesKm":[21.1],"signupUrl":"https://www.stockholmhalfmarathon.se/","platform":"Haku","priceNote":"1,045 SEK until 14 Feb","priceSteps":[{"until":"2027-02-14","amount":1045,"currency":"SEK"}],"status":"open","checkedOn":"2026-10-21"},
  {"id":"oslo-maraton-2027","name":"Oslo Maraton","type":"running","date":"2027-09-18","city":"Oslo","country":"NO","distancesKm":[42.195,21.1,10],"signupUrl":"https://www.oslomaraton.no/","platform":"Haku","priceNote":"1,350 NOK for the marathon","status":"open","resultsUrl":"https://oslomaraton.no/resultater-og-historie/","checkedOn":"2026-10-21"},
  {"id":"cph-half-2027","name":"CPH Half","type":"running","date":"2027-09-19","city":"Copenhagen","country":"DK","distancesKm":[21.1],"signupUrl":"https://cphhalf.dk/en/lottery/","priceNote":"795 DKK. The lottery is done; about 188,000 entered the draw.","priceSteps":[{"amount":795,"currency":"DKK"}],"status":"lottery","resultsUrl":"https://cphhalf.dk/en/results-archive/","checkedOn":"2026-10-21"},
  {"id":"lidingoloppet-2027","name":"Lidingöloppet","type":"running","date":"2027-09-25","city":"Lidingö","country":"SE","distancesKm":[30],"format":"cross-country","signupUrl":"https://lidingoloppet.se/en/tcs-lidingoloppet/faq/registration-fees","priceNote":"2027 prices are not out yet. Entries cost 796–1,395 SEK in 2026.","status":"checkSite","klassiker":true,"resultsUrl":"https://lidingoloppet.se/en/tcs-lidingoloppet/results-and-statistics","checkedOn":"2026-10-21"}
]}
"""#
}

extension AppModel {
    func loadDemoRaces() {
        races = Race.demo
        func pick(_ id: String) -> Race? { races.first { $0.id == id } }
        myRaces = [
            pick("hyrox-stockholm-2026").map { r -> MyRace in
                var m = MyRace(race: r, day: "2026-12-12", note: "Open")
                m.format = "doubles"; m.wave = "14:20"; m.bib = "1427"
                // Train for it, started nine weeks before race week: on 21 October 2026 it is week 3 of 10, Base.
                m.plan = RacePlanSettings(startedOn: RaceDay.adding(-63, to: RacePlanner.monday(of: "2026-12-12")) ?? "2026-10-05")
                m.remindWeek = true; m.remindEve = true
                m.going = true
                return m
            },
            pick("tough-viking-stadion-2027").map { MyRace(race: $0, remindPrice: true) },
            pick("midnattsloppet-stockholm-2027").map { MyRace(race: $0, note: "10 km", remindSignup: true) },
            pick("midnattsloppet-stockholm-2026").map { MyRace(race: $0, note: "10 km") },
        ].compactMap { $0 }
        loadDemoGoing()
        loadDemoPlanWeek()
    }

    /// This week of the demo plan, on this week's days so the cards look alike any day: Strength on Monday and a run
    /// on Tuesday checked in, a Hyrox class to book on Thursday (Hyrox there on the Thursdays before), and Mobility on
    /// Sunday that a weekly rule books. Fictional studios and classes.
    func loadDemoPlanWeek() {
        let cal = BruceDate.calendar
        let iso = ISO8601DateFormatter()
        guard let monday = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return }
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: monday)!)! }
        func s(_ d: Date) -> String { iso.string(from: d) }
        func dec<T: Decodable>(_ t: T.Type, _ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        studios += dec([BruceAPI.Studio].self, """
        [{"id":9810,"name":"Example Box Hornstull","status":"LIVE","vicinity":"Hornstull","city_id":1,"has_classes":true,
          "studio_categories":[{"category_id":13,"main":true,"order":0,"category":{"id":13,"title":"Hyrox"}},{"category_id":26,"order":1,"category":{"id":26,"title":"Strength"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example street 40","city":"Stockholm","latitude":59.3157,"longitude":18.0335}}],
          "visit_limit":{"items":[{"label":"BASE","limit":0},{"label":"BLACK","limit":0},{"label":"EPIC","limit":0}]}},
         {"id":9820,"name":"Example Run Club","status":"LIVE","vicinity":"Djurgården","city_id":1,"has_classes":true,
          "studio_categories":[{"category_id":23,"main":true,"order":0,"category":{"id":23,"title":"Running"}},{"category_id":18,"order":1,"category":{"id":18,"title":"Outdoor"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example path 1","city":"Stockholm","latitude":59.3260,"longitude":18.1060}}],
          "visit_limit":{"items":[{"label":"BASE","limit":0},{"label":"BLACK","limit":0},{"label":"EPIC","limit":0}]}}]
        """)
        // Thursday's Hyrox, or the next day of this week that is still ahead; Sunday's Mobility.
        let thursday = (3...6).map { at($0, 18, 0) }.first { $0 > Date().addingTimeInterval(3600) }
        var week: [BruceAPI.BruceClass] = []
        if let t = thursday {
            week.append(dec(BruceAPI.BruceClass.self, """
            {"id":9811,"studio_id":9810,"title":"Hyrox","start_time":"\(s(t))","end_time":"\(s(t.addingTimeInterval(3600)))","instructor":"Instructor H","spots":20,"available_spots":7,
             "unbookable_latest_time":"\(s(t.addingTimeInterval(-43_200)))","bookable_latest_time":"\(s(t.addingTimeInterval(-600)))","class_categories":[{"category_id":13,"main":true}]}
            """))
        }
        let sunday = at(6, 17, 0)
        week.append(dec(BruceAPI.BruceClass.self, """
        {"id":9812,"studio_id":1489,"title":"Mobility","start_time":"\(s(sunday))","end_time":"\(s(sunday.addingTimeInterval(2700)))","instructor":"Instructor E","spots":14,"available_spots":9,
         "unbookable_latest_time":"\(s(sunday.addingTimeInterval(-43_200)))","class_categories":[{"category_id":16,"main":true}]}
        """))
        for c in week where c.start! > Date() {
            classDetails[c.id] = c
            classesByDay[cal.startOfDay(for: c.start!), default: []].append(c)
        }
        for k in classesByDay.keys { classesByDay[k]?.sort { $0.startTime < $1.startTime } }
        autoBookRules = [AutoBookRule(studioId: 1489, masterId: nil, title: "Mobility", weekday: 1, minuteOfDay: 17 * 60)]
        friendsBookings.append(BruceAPI.FriendBooking(id: 40, userId: 7, classId: 9811, class: classDetails[9811]))
        // Check-ins: this week's Strength and run, and Hyrox at the box on the four Thursdays before.
        let gym = BruceAPI.StudioLite(id: 1724, name: "STC Rosenlundsparken", photo: nil, vicinity: "Södermalm", cityId: 1)
        let run = BruceAPI.StudioLite(id: 9820, name: "Example Run Club", photo: nil, vicinity: "Djurgården", cityId: 1)
        let box = BruceAPI.StudioLite(id: 9810, name: "Example Box Hornstull", photo: nil, vicinity: "Hornstull", cityId: 1)
        func visit(_ id: Int, _ start: Date, _ title: String, _ studio: BruceAPI.StudioLite, _ category: Int, minutes: Int = 60) -> BruceAPI.Visit {
            BruceAPI.Visit(id: id, studioId: studio.id, checkedInAt: s(start.addingTimeInterval(-480)), classId: 80_000 + id,
                           visitClass: .init(id: 80_000 + id, title: title, startTime: s(start), endTime: s(start.addingTimeInterval(Double(minutes) * 60)),
                                             instructor: "Instructor H", studio: studio, classCategories: [BruceAPI.ClassCategory(categoryId: category, main: true)]))
        }
        var plan = [visit(9001, at(0, 7, 30), "Full Body Strength", gym, 26, minutes: 45), visit(9002, at(1, 18, 0), "Run Club", run, 23)]
        plan += (1...4).map { visit(9002 + $0, at(3 - 7 * $0, 18, 0), "Hyrox", box, 13) }
        // Both studios and categories go back a few months, so Home doesn't announce them as milestones.
        plan += [visit(9010, at(-88, 18, 0), "Hyrox", box, 13), visit(9011, at(-90, 18, 0), "Run Club", run, 23)]
        visitHistory = ((visitHistory ?? []) + plan.filter { ($0.date ?? .distantFuture) < Date() })
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
