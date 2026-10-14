import Foundation

/// Offline demo data for For you, goals, challenges and Wrapped (`BRUCE_DEMO=1`). Fictional, no personal data.
extension AppModel {
    /// Extra demo studios, classes and friends for the recommendations (called from `loadDemo`).
    func loadDemoInsights() {
        let cal = BruceDate.calendar
        let iso = ISO8601DateFormatter()
        func at(_ dayOffset: Int, _ h: Int, _ min: Int) -> String {
            iso.string(from: cal.date(bySettingHour: h, minute: min, second: 0, of: cal.date(byAdding: .day, value: dayOffset, to: Date())!)!)
        }
        func dec<T: Decodable>(_ t: T.Type, _ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        studios += dec([BruceAPI.Studio].self, """
        [{"id":12388,"name":"STC Sturegatan Park","status":"LIVE","vicinity":"Östermalm","city_id":1,"has_classes":true,
          "studio_categories":[{"category_id":1,"main":true,"order":0,"category":{"id":1,"title":"Gym"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example street 9","city":"Stockholm","latitude":59.3372,"longitude":18.0702}}]},
         {"id":1491,"name":"Example Yoga Södermalm","status":"LIVE","vicinity":"Södermalm","city_id":1,"has_classes":true,
          "studio_categories":[{"category_id":2,"main":true,"order":0,"category":{"id":2,"title":"Yoga"}}],
          "studio_addresses":[{"main":true,"address":{"address":"Example lane 2","city":"Stockholm","latitude":59.3238,"longitude":18.0668}}]}]
        """)
        // The bath house gets an address (demo swims), the yoga studio keeps its northern one.
        if let i = studios.firstIndex(where: { $0.id == 9600 }) {
            studios[i].studioAddresses = dec([BruceAPI.StudioAddress].self, #"[{"main":true,"address":{"latitude":59.3110,"longitude":18.0590}}]"#)
        }
        let picks = dec([BruceAPI.BruceClass].self, """
        [{"id":9101,"studio_id":1724,"title":"Reformer","start_time":"\(at(1, 7, 0))","end_time":"\(at(1, 7, 50))","instructor":"Instructor R","available_spots":5,"class_categories":[{"category_id":22,"main":true}]},
         {"id":9102,"studio_id":12388,"title":"Strength Circuit","start_time":"\(at(1, 12, 5))","end_time":"\(at(1, 12, 50))","instructor":"Sina Ramezani","available_spots":9,"class_categories":[{"category_id":26,"main":true}]},
         {"id":9103,"studio_id":1491,"title":"Hatha Flow","start_time":"\(at(1, 17, 45))","end_time":"\(at(1, 18, 45))","instructor":"Instructor D","available_spots":2,"class_categories":[{"category_id":2,"main":true}]},
         {"id":9104,"studio_id":12388,"title":"Hyrox","start_time":"\(at(2, 17, 30))","end_time":"\(at(2, 18, 30))","instructor":"Instructor H","available_spots":7,"class_categories":[{"category_id":13,"main":true}]}]
        """)
        for c in picks {
            classDetails[c.id] = c
            classesByDay[cal.startOfDay(for: c.start!), default: []].append(c)
        }
        for k in classesByDay.keys { classesByDay[k]?.sort { $0.startTime < $1.startTime } }
        friends += dec([BruceAPI.Friend].self, """
        [{"id":7,"friend_user":{"id":7,"first_name":"Robin","last_name":"Example"}},{"id":12,"friend_user":{"id":12,"first_name":"Sam","last_name":"Example"}},
         {"id":11,"friend_user":{"id":11,"first_name":"Alex","last_name":"Example"}},{"id":9,"friend_user":{"id":9,"first_name":"Maja","last_name":"Example"}}]
        """)
        friendsBookings += [(30, 7, 9102), (31, 12, 9103), (32, 11, 9103)].map { id, uid, cid in
            BruceAPI.FriendBooking(id: id, userId: uid, classId: cid, class: classDetails[cid])
        }
    }

    /// A year of fictional visits for Statistics, goals, recommendations and Wrapped: weekday gym drop-ins, Tuesday
    /// Reformer, lunch Strength Circuit, weekend yoga, swims every week or two; quieter in summer.
    static var demoYearVisits: [BruceAPI.Visit] {
        let cal = BruceDate.calendar
        let iso = ISO8601DateFormatter()
        var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        let stc = BruceAPI.StudioLite(id: 1724, name: "STC Rosenlundsparken", photo: nil, vicinity: "Södermalm", cityId: 1)
        let sture = BruceAPI.StudioLite(id: 12388, name: "STC Sturegatan Park", photo: nil, vicinity: "Östermalm", cityId: 1)
        let yoga = BruceAPI.StudioLite(id: 1491, name: "Example Yoga Södermalm", photo: nil, vicinity: "Södermalm", cityId: 1)
        let north = BruceAPI.StudioLite(id: 1489, name: "Example Yoga Studio", photo: nil, vicinity: "Stockholm", cityId: 1)
        let club = BruceAPI.StudioLite(id: 9700, name: "Example City Club", photo: nil, vicinity: "Norrmalm", cityId: 1)
        var out: [BruceAPI.Visit] = []
        var id = 100, classId = 50_000
        let today = cal.startOfDay(for: Date())
        let yearStart = cal.dateInterval(of: .year, for: Date())!.start
        var day = cal.date(byAdding: .day, value: -3, to: today)!
        func time(_ d: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: d)!.addingTimeInterval(Double(m) * 60) }
        func add(_ d: Date, studio: BruceAPI.StudioLite, title: String?, h: Int, m: Int, minutes: Int, category: Int?, instructor: String? = nil) {
            id += 1
            let start = time(d, h, m)
            if let title {
                classId += 1
                out.append(BruceAPI.Visit(id: id, studioId: studio.id, checkedInAt: iso.string(from: start.addingTimeInterval(-600)), classId: classId,
                                          visitClass: .init(id: classId, title: title, startTime: iso.string(from: start),
                                                            endTime: iso.string(from: start.addingTimeInterval(Double(minutes) * 60)),
                                                            instructor: instructor, studio: studio,
                                                            classCategories: category.map { [BruceAPI.ClassCategory(categoryId: $0, main: true)] })))
            } else {
                out.append(BruceAPI.Visit(id: id, studioId: studio.id, checkedInAt: iso.string(from: start)))
            }
        }
        while day >= yearStart {
            let wd = cal.component(.weekday, from: day)
            let month = cal.component(.month, from: day)
            let k = month == 7 ? 0.35 : month == 6 || month == 8 ? 0.7 : month == 9 ? 1.15 : 1.0
            switch wd {
            case 2, 4, 6: if rnd() < 0.72 * k { add(day, studio: stc, title: nil, h: 6, m: 15 + Int(rnd() * 80), minutes: 60, category: nil) }
            case 3: if rnd() < 0.85 * k { add(day, studio: stc, title: "Reformer", h: 7, m: 0, minutes: 50, category: 22, instructor: "Instructor R") }
            case 5: if rnd() < 0.6 * k { add(day, studio: sture, title: "Strength Circuit", h: 12, m: 5, minutes: 45, category: 26, instructor: "Sina Ramezani") }
            case 7: if rnd() < 0.55 * k { add(day, studio: yoga, title: "Hatha Flow", h: 10, m: 0, minutes: 60, category: 2) }
            default:
                if rnd() < 0.3 * k { add(day, studio: rnd() < 0.5 ? north : club, title: rnd() < 0.5 ? "Morning Flow" : "High Intensity", h: 9, m: 0, minutes: 45, category: 12) }
            }
            if wd == 1 && rnd() < 0.6 * k {
                id += 1
                out.append(BruceAPI.Visit(id: id, studioId: 9600, checkedInAt: iso.string(from: time(day, 16, 20))))
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return out
    }

    /// Friends' past bookings for Wrapped "you and Robin did 14 classes together": Robin joins most demo Reformers.
    static func demoYearFriendBookings(_ visits: [BruceAPI.Visit]) -> [BruceAPI.FriendBooking] {
        visits.enumerated().compactMap { i, v in
            guard let cid = v.classId else { return nil }
            if v.title == "Reformer", i % 3 != 0 { return BruceAPI.FriendBooking(id: 70_000 + i, userId: 7, classId: cid, class: nil) }
            if v.title == "Hatha Flow", i % 2 == 0 { return BruceAPI.FriendBooking(id: 70_000 + i, userId: 12, classId: cid, class: nil) }
            return nil
        }
    }
}
