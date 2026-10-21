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
