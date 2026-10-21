import XCTest
@testable import BruceMacOS

/// Shared/BruceCore logic compiled into the macOS target (the Shared symlink): run with `swift test` in Bruce-MacOS.
final class ClassFiltersTests: XCTestCase {
    /// A listed class at `iso` (UTC) of `minutes` length.
    func cls(_ id: Int, _ iso: String, minutes: Int = 60, studio: Int = 1, spots: Int? = 4, opens: String? = nil, closes: String? = nil) -> BruceAPI.BruceClass {
        let end = Date(timeIntervalSince1970: BruceDate.parse(iso)!.timeIntervalSince1970 + Double(minutes) * 60)
        let f = ISO8601DateFormatter()
        var json = #"{"id":\#(id),"studio_id":\#(studio),"title":"Class \#(id)","start_time":"\#(iso)","end_time":"\#(f.string(from: end))""#
        if let spots { json += #","available_spots":\#(spots)"# }
        if let opens { json += #","bookable_earliest_time":"\#(opens)""# }
        if let closes { json += #","bookable_latest_time":"\#(closes)""# }
        json += "}"
        return try! JSONDecoder().decode(BruceAPI.BruceClass.self, from: Data(json.utf8))
    }

    let now = BruceDate.parse("2026-10-21T10:00:00Z")!   // Wednesday 12:00 in Stockholm

    func testSlotsFollowStockholmTime() {
        // 06:00Z = 08:00 Stockholm (early), 09:30Z = 11:30 (lunch), 18:30Z = 20:30 (late).
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T06:00:00Z")), .early)
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T06:30:00Z")), .morning)
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T09:30:00Z")), .lunch)
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T13:00:00Z")), .afternoon)
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T16:00:00Z")), .evening)
        XCTAssertEqual(ClassFilters.slot(of: cls(1, "2026-10-22T18:30:00Z")), .late)
    }

    func testDurationBands() {
        XCTAssertTrue(DurationBand.short.contains(minutes: 45))
        XCTAssertFalse(DurationBand.short.contains(minutes: 46))
        XCTAssertTrue(DurationBand.medium.contains(minutes: 60))
        XCTAssertTrue(DurationBand.long.contains(minutes: 61))
    }

    func testBookableNow() {
        XCTAssertTrue(ClassFilters.isBookableNow(cls(1, "2026-10-22T16:00:00Z"), now: now))
        XCTAssertFalse(ClassFilters.isBookableNow(cls(1, "2026-10-22T16:00:00Z", spots: 0), now: now))
        XCTAssertFalse(ClassFilters.isBookableNow(cls(1, "2026-10-22T16:00:00Z", opens: "2026-10-21T16:00:00Z"), now: now))
        XCTAssertFalse(ClassFilters.isBookableNow(cls(1, "2026-10-22T16:00:00Z", closes: "2026-10-21T09:00:00Z"), now: now))
        XCTAssertFalse(ClassFilters.isBookableNow(cls(1, "2026-10-21T09:00:00Z"), now: now))
    }

    func testPassesAndCount() {
        var f = ClassFilterState()
        XCTAssertTrue(f.isEmpty)
        f.slots = [.lunch]; f.durations = [.medium]; f.bookableNow = true
        XCTAssertEqual(f.activeCount, 3)
        XCTAssertTrue(ClassFilters.passes(cls(1, "2026-10-22T10:00:00Z"), f, now: now))                 // 12:00, 60 min
        XCTAssertFalse(ClassFilters.passes(cls(1, "2026-10-22T07:00:00Z"), f, now: now))                // morning
        XCTAssertFalse(ClassFilters.passes(cls(1, "2026-10-22T10:00:00Z", minutes: 45), f, now: now))   // short
        XCTAssertFalse(ClassFilters.passes(cls(1, "2026-10-22T10:00:00Z", spots: 0), f, now: now))      // full
        f.sort = .distance
        XCTAssertEqual(f.activeCount, 4)
    }

    func testSorting() {
        let a = cls(1, "2026-10-22T16:00:00Z", studio: 1, spots: 2)
        let b = cls(2, "2026-10-22T15:00:00Z", studio: 2, spots: 0)
        let c = cls(3, "2026-10-22T17:00:00Z", studio: 3, spots: nil)
        let d = cls(4, "2026-10-22T14:00:00Z", studio: 4, spots: 9)
        let dist: [Int: Double] = [1: 500, 2: 100, 4: 2000]
        let travel: [Int: Int] = [1: 9, 2: 3, 3: 12]
        func ids(_ s: ClassSort) -> [Int] {
            var f = ClassFilterState(); f.sort = s
            return ClassFilters.sorted([a, b, c, d], f, distance: { dist[$0] }, travel: { travel[$0] }).map(\.id)
        }
        XCTAssertEqual(ids(.start), [4, 2, 1, 3])
        XCTAssertEqual(ids(.distance), [2, 1, 4, 3])
        XCTAssertEqual(ids(.travel), [2, 1, 3, 4])
        XCTAssertEqual(ids(.spots), [4, 1, 3, 2])
    }
}

final class BookingRulesTests: XCTestCase {
    func testCancelStrikesAndChip() {
        let json = #"{"id":1,"studio_id":1,"title":"Yoga","start_time":"2026-10-20T16:00:00Z","end_time":"2026-10-20T17:00:00Z"}"#
        let c = try! JSONDecoder().decode(BruceAPI.BruceClass.self, from: Data(json.utf8))
        let r = BookingRules(c)!
        let start = c.start!
        let h: TimeInterval = 3600
        XCTAssertEqual([13, 12, 8, 3, 2, 1, 0.5].map { r.cancelStrikes(at: start.addingTimeInterval(-$0 * h)) }, [0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(r.nextCancelStep(at: start.addingTimeInterval(-8 * h))?.strikes, 2)
        XCTAssertNil(r.nextCancelStep(at: start.addingTimeInterval(-0.5 * h)))
        let free = r.cancelChip(at: start.addingTimeInterval(-13 * h))!
        XCTAssertEqual(free.tone, .free)
        XCTAssertTrue(free.text.hasPrefix("Free cancel until "))
        let two = r.cancelChip(at: start.addingTimeInterval(-2 * h))!
        XCTAssertEqual(two.tone, .warn)
        XCTAssertTrue(two.text.hasPrefix("Cancel now: 2 strikes · 3 from "))
        XCTAssertEqual(r.cancelChip(at: start.addingTimeInterval(-0.5 * h))?.tone, .bad)
        XCTAssertNil(r.cancelChip(at: start))
    }
}

final class FirstVisitTests: XCTestCase {
    func review(_ rating: Int?, daysAgo: Int, now: Date) -> BruceAPI.Review {
        let f = ISO8601DateFormatter()
        let r = rating.map { "\($0)" } ?? "null"
        let json = #"{"id":\#(daysAgo),"rating":\#(r),"comment":"c","created_at":"\#(f.string(from: now.addingTimeInterval(-Double(daysAgo) * 86400)))"}"#
        return try! JSONDecoder().decode(BruceAPI.Review.self, from: Data(json.utf8))
    }

    func testRecentRatingAndTrend() {
        let now = BruceDate.parse("2026-10-21T10:00:00Z")!
        let list = [review(5, daysAgo: 1, now: now), review(3, daysAgo: 10, now: now), review(4, daysAgo: 89, now: now),
                    review(1, daysAgo: 91, now: now), review(nil, daysAgo: 2, now: now)]
        let r = RecentRating.recent(list, now: now)
        XCTAssertEqual(r?.count, 3)
        XCTAssertEqual(r?.average, 4)
        XCTAssertEqual(r?.text, "4.0")
        XCTAssertNil(RecentRating.recent([review(5, daysAgo: 100, now: now)], now: now))
        XCTAssertNil(RecentRating.trend(allTime: 470, recent: r))   // fewer than 5
        XCTAssertEqual(RecentRating.trend(allTime: 470, recent: .init(average: 4.1, count: 23, days: 90)), "Rated lower lately.")
        XCTAssertEqual(RecentRating.trend(allTime: 410, recent: .init(average: 4.6, count: 5, days: 90)), "Rated higher lately.")
        XCTAssertNil(RecentRating.trend(allTime: 450, recent: .init(average: 4.3, count: 9, days: 90)))
    }

    func testFirstVisitInfoUsesLiveFields() {
        let studio = try! JSONDecoder().decode(BruceAPI.Studio.self, from: Data(#"{"id":7,"name":"Hall","status":"LIVE","integration_door_type":"parakey","qr_code_id":"abc","studio_facilities":[{"facility":{"code":"shower","title":"Shower"}},{"facility":{"code":"locker","title":"Lockers"}}]}"#.utf8))
        let c = try! JSONDecoder().decode(BruceAPI.BruceClass.self, from: Data(#"{"id":1,"studio_id":7,"title":"Bouldering Intro","start_time":"2026-10-22T15:30:00Z","end_time":"2026-10-22T16:30:00Z","early_check_in_minutes":30,"late_check_in_minutes":5}"#.utf8))
        let info = FirstVisitInfo(studio: studio, class: c)
        XCTAssertEqual(info.checkIn, "Check in 17:00–17:25")   // Stockholm time
        XCTAssertEqual(info.checkInNote, "Opens 30 min before, closes 5 min before")
        XCTAssertTrue(info.door?.contains("Parakey") == true)
        XCTAssertEqual(info.facilities, ["Shower", "Lockers"])
        let plain = try! JSONDecoder().decode(BruceAPI.Studio.self, from: Data(#"{"id":8,"name":"Gym","status":"LIVE"}"#.utf8))
        XCTAssertNil(FirstVisitInfo(studio: plain, class: nil).door)
        XCTAssertTrue(FirstVisitInfo(studio: plain, class: nil).checkIn.contains("before the class starts"))
    }
}

final class MilestonesTests: XCTestCase {
    func visit(_ id: Int, _ day: String, studio: Int, cat: Int? = 19, solo: Bool = false) -> BruceAPI.Visit {
        let cls = solo ? "" : #","class":{"id":\#(id),"title":"Reformer","start_time":"\#(day)T10:00:00Z","end_time":"\#(day)T11:00:00Z","class_categories":[{"category_id":\#(cat ?? 19)}]}"#
        let json = #"{"id":\#(id),"studio_id":\#(studio),"checked_in_at":"\#(day)T09:55:00Z"\#(cls)}"#
        return try! JSONDecoder().decode(BruceAPI.Visit.self, from: Data(json.utf8))
    }

    func testClassStudioCategoryAndStreakMilestones() {
        var visits: [BruceAPI.Visit] = []
        for i in 0..<12 { visits.append(visit(i, String(format: "2026-%02d-%02d", 1 + i / 4, 1 + (i % 4) * 7), studio: 1 + i % 5, cat: i == 11 ? 2 : 19)) }
        visits.append(visit(99, "2026-04-01", studio: 6, solo: true))
        let now = BruceDate.parse("2026-10-21T10:00:00Z")!
        let list = Milestones.reached(visits: visits, now: now, categoryTitle: { [19: "Pilates", 2: "Yoga"][$0] }, studioName: { "Studio \($0)" })
        let keys = list.map(\.key)
        XCTAssertTrue(keys.contains("classes-10")); XCTAssertFalse(keys.contains("classes-25"))
        XCTAssertTrue(keys.contains("studios-5"))
        XCTAssertTrue(keys.contains("category-2")); XCTAssertFalse(keys.contains("category-19"))
        XCTAssertTrue(list.first { $0.key == "classes-10" }!.detail.hasPrefix("Number 10 was Reformer on "))
        XCTAssertTrue(list.first { $0.key == "studios-5" }!.detail.contains("Your 5th was Studio 5"))
        XCTAssertNil(Milestones.fresh(list, seen: [], now: now))
        XCTAssertEqual(Milestones.fresh(list, seen: [], now: BruceDate.parse("2026-03-30T10:00:00Z")!)?.key, "category-2")
        let weekly = ["2026-09-29", "2026-10-06", "2026-10-13", "2026-10-20"].enumerated().map { visit(100 + $0.offset, $0.element, studio: 1) }
        let s = Milestones.reached(visits: weekly, now: now)
        XCTAssertEqual(s.first { $0.kind == .streak }?.title, "4-week streak")
        XCTAssertTrue(s.contains { $0.key == "streak-4-2026-09-28" })
        XCTAssertEqual(Milestones.ordinal(22), "22nd"); XCTAssertEqual(Milestones.ordinal(12), "12th")
        XCTAssertEqual(Goals.newStudioVisits(visits + [visit(200, "2026-10-02", studio: 1), visit(201, "2026-10-05", studio: 7)], now: now).map(\.studioRef), [7])
    }

    func testNewToYouRespectsPlanAndHistory() {
        func studio(_ id: Int, _ name: String, cat: Int, base: Int?, lat: Double) -> BruceAPI.Studio {
            let limits = base.map { #","visit_limit":{"items":[{"id":1,"label":"BASE","limit":\#($0),"period":"MONTHLY"},{"id":3,"label":"EPIC","limit":0,"period":"MONTHLY"}]}"# } ?? ""
            let json = #"{"id":\#(id),"name":"\#(name)","status":"LIVE","has_classes":true,"studio_categories":[{"category_id":\#(cat),"main":true}],"studio_addresses":[{"main":true,"address":{"latitude":\#(lat),"longitude":18.0}}]\#(limits)}"#
            return try! JSONDecoder().decode(BruceAPI.Studio.self, from: Data(json.utf8))
        }
        let studios = [studio(1, "Visited", cat: 2, base: 0, lat: 59.3), studio(2, "Yoga far", cat: 2, base: 0, lat: 59.4),
                       studio(3, "Gym near", cat: 1, base: nil, lat: 59.301), studio(4, "Epic only", cat: 2, base: -1, lat: 59.3), studio(5, "Climb far", cat: 7, base: 0, lat: 59.5)]
        var profile = VisitProfile(visits: [])
        profile.categories = [2: 3]
        let here = GeoPoint(lat: 59.3, lon: 18.0)
        let dist: (BruceAPI.Studio) -> Double? = { s in
            let a = s.studioAddresses?.first?.address
            return a.flatMap { x in x.latitude.map { Recommender.meters(here, GeoPoint(lat: $0, lon: x.longitude ?? 18.0)) } }
        }
        let picks = NewToYou.picks(studios: studios, visited: [1], profile: profile, tier: "BASE", distance: dist, categoryTitle: { [2: "Yoga"][$0] })
        XCTAssertEqual(picks.map(\.studio.id), [2, 3])
        XCTAssertEqual(picks[0].reason, "Yoga, which you do")
        XCTAssertEqual(picks[1].reason, "near you")
        XCTAssertTrue(NewToYou.includedInPlan(studios[3], tier: "EPIC")); XCTAssertFalse(NewToYou.includedInPlan(studios[3], tier: "BASE"))
    }
}
