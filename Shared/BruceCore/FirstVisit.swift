import Foundation

// "First visit here?" (class and studio pages, until the first check-in at that studio) and the recent rating on the
// Reviews tab. Everything comes from fields the apps already load (class check-in minutes, studio facilities and door
// type, the studio page's review list) plus our own policy wording; nothing is crawled.

/// What a first-timer wants to know: when to check in, how the door works, what the studio has.
struct FirstVisitInfo: Hashable {
    /// "Check in 17:00–17:25" for a class, else the general rule.
    let checkIn: String
    let checkInNote: String
    /// How to get in, from `integration_door_type` / check-in support; nil when the studio says nothing.
    let door: String?
    let facilities: [String]
    static let lateCheckIn = "Late check-in costs 1 strike"

    init(studio: BruceAPI.Studio?, class c: BruceAPI.BruceClass?) {
        if let c, let r = BookingRules(c) {
            checkIn = "Check in \(BruceDate.time(r.checkInFrom))–\(BruceDate.time(r.lateCheckIn))"
            checkInNote = "Opens \(c.earlyCheckInMinutes ?? 30) min before, closes \(c.lateCheckInMinutes ?? 5) min before"
        } else {
            checkIn = "Check in before the class starts"
            checkInNote = "Usually opens 30 min before and closes 5–15 min before; each class page shows its window"
        }
        if studio?.usesParakey == true {
            door = "Door opens from the Parakey app, linked to your account at check-in"
        } else if studio?.supportsCheckIn == true {
            door = "Scan the studio's QR code in the app to check in"
        } else {
            door = nil
        }
        facilities = (studio?.studioFacilities ?? []).compactMap { $0.facility?.title }.filter { !$0.isEmpty }
    }
}

/// The last 90 days of the review list, next to the all-time average.
enum RecentRating {
    struct Summary: Hashable {
        let average: Double
        let count: Int
        let days: Int
        var text: String { String(format: "%.1f", average) }
    }
    static let window = 90
    /// Reviews with a rating created in the last `days` days. The studio page's review query returns commented
    /// reviews only (`comment=true`, 50 newest), so callers label it "with comments".
    static func recent(_ reviews: [BruceAPI.Review], days: Int = window, now: Date = Date()) -> Summary? {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        let rated = reviews.compactMap { r -> Int? in
            guard let d = r.createdAt.flatMap(BruceDate.parse), d >= since, let n = r.rating, n > 0 else { return nil }
            return n
        }
        guard !rated.isEmpty else { return nil }
        return Summary(average: Double(rated.reduce(0, +)) / Double(rated.count), count: rated.count, days: days)
    }
    /// "Rated lower lately" / "Rated higher lately" once at least 5 recent ratings differ from the all-time average
    /// (`rating.average`, x100) by 0.3 stars or more.
    static func trend(allTime: Int?, recent: Summary?) -> String? {
        guard let a = allTime, a > 0, let r = recent, r.count >= 5 else { return nil }
        let diff = r.average - Double(a) / 100
        if diff <= -0.3 { return "Rated lower lately." }
        if diff >= 0.3 { return "Rated higher lately." }
        return nil
    }
}

extension AppModel {
    /// Studios the user has checked in at, from the visit history and today's checked-in bookings; nil until the
    /// history has loaded (then nothing is called a first visit).
    var visitedStudioIds: Set<Int>? {
        guard let history = visitHistory else { return nil }
        var ids = Set(history.compactMap { $0.studioId ?? $0.visitClass?.studio?.id })
        for b in bookings where b.isCheckedIn { if let s = b.studioId ?? b.class?.studioId { ids.insert(s) } }
        return ids
    }
    /// True while the user is logged in, the history is known and has no check-in at this studio.
    func isFirstVisit(_ studioId: Int) -> Bool {
        guard isLoggedIn, let ids = visitedStudioIds else { return false }
        return !ids.contains(studioId)
    }
}
