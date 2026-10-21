import Foundation

// Classes-tab filters beyond the shared Explore ones (ExploreView.swift FilterSheet, web filters.js): time of day,
// duration, sort order and "Bookable now". All client-side over the class days already loaded.

/// Length of a class.
enum DurationBand: String, CaseIterable, Codable, Hashable {
    case short, medium, long
    var title: String {
        switch self { case .short: "≤ 45 min"; case .medium: "45–60 min"; case .long: "60+ min" }
    }
    func contains(minutes: Int) -> Bool {
        switch self {
        case .short: return minutes <= 45
        case .medium: return minutes > 45 && minutes <= 60
        case .long: return minutes > 60
        }
    }
}

/// Order of the Classes list.
enum ClassSort: String, CaseIterable, Codable, Hashable {
    case start, distance, travel, spots
    var title: String {
        switch self { case .start: "Start"; case .distance: "Distance"; case .travel: "Travel time"; case .spots: "Spots left" }
    }
}

struct ClassFilterState: Codable, Equatable {
    var slots: Set<DaySlot> = []
    var durations: Set<DurationBand> = []
    var sort: ClassSort = .start
    var bookableNow = false

    var isEmpty: Bool { self == ClassFilterState() }
    /// Counts for the Filter badge: one each for time of day, duration, a sort other than start, bookable now.
    var activeCount: Int {
        (slots.isEmpty ? 0 : 1) + (durations.isEmpty ? 0 : 1) + (sort == .start ? 0 : 1) + (bookableNow ? 1 : 0)
    }
}

enum ClassFilters {
    /// The class's time-of-day slot (DaySlot, Recommendations.swift) in the city's time zone.
    static func slot(of c: BruceAPI.BruceClass) -> DaySlot? {
        guard let s = c.start else { return nil }
        let d = BruceDate.calendar.dateComponents([.hour, .minute], from: s)
        return DaySlot(minuteOfDay: (d.hour ?? 0) * 60 + (d.minute ?? 0))
    }

    /// Open for booking right now: the window has opened and not closed, there is a spot, and it hasn't started.
    static func isBookableNow(_ c: BruceAPI.BruceClass, now: Date = Date()) -> Bool {
        guard let s = c.start, s > now, c.isListed else { return false }
        if let a = c.availableSpots, a <= 0 { return false }
        if let o = c.bookingOpens, o > now { return false }
        if let u = c.bookableLatestTime.flatMap(BruceDate.parse), u < now { return false }
        return true
    }

    static func passes(_ c: BruceAPI.BruceClass, _ f: ClassFilterState, now: Date = Date()) -> Bool {
        if !f.slots.isEmpty { guard let s = slot(of: c), f.slots.contains(s) else { return false } }
        if !f.durations.isEmpty { guard let d = c.durationMinutes, f.durations.contains(where: { $0.contains(minutes: d) }) else { return false } }
        if f.bookableNow, !isBookableNow(c, now: now) { return false }
        return true
    }

    /// `distance` and `travel` give metres and minutes to a studio (nil = unknown, sorted last); ties fall back to start.
    static func sorted(_ classes: [BruceAPI.BruceClass], _ f: ClassFilterState,
                       distance: (Int) -> Double? = { _ in nil }, travel: (Int) -> Int? = { _ in nil }) -> [BruceAPI.BruceClass] {
        func byStart(_ a: BruceAPI.BruceClass, _ b: BruceAPI.BruceClass) -> Bool { a.startTime < b.startTime }
        switch f.sort {
        case .start:
            return classes.sorted(by: byStart)
        case .distance:
            let d = Dictionary(uniqueKeysWithValues: Set(classes.map(\.studioId)).map { ($0, distance($0) ?? .greatestFiniteMagnitude) })
            return classes.sorted { (d[$0.studioId]!, $0.startTime) < (d[$1.studioId]!, $1.startTime) }
        case .travel:
            let t = Dictionary(uniqueKeysWithValues: Set(classes.map(\.studioId)).map { ($0, travel($0) ?? Int.max) })
            return classes.sorted { (t[$0.studioId]!, $0.startTime) < (t[$1.studioId]!, $1.startTime) }
        case .spots:
            // Most spots first; unknown counts after them, full classes at the very end.
            func key(_ c: BruceAPI.BruceClass) -> Int { c.availableSpots.map { $0 <= 0 ? -2 : $0 } ?? -1 }
            return classes.sorted { key($0) != key($1) ? key($0) > key($1) : $0.startTime < $1.startTime }
        }
    }
}

extension AppModel {
    /// Straight-line distance in metres from the user's location (else the city centre) to a studio.
    func studioDistance(_ id: Int) -> Double? {
        guard let p = studioPoint(id) else { return nil }
        return Recommender.meters(GeoPoint(lat: refLat, lon: refLon), p)
    }

    /// Minutes to a studio the way For you measures them: from your location (else home, else the city centre),
    /// by your commute mode; a MapKit ETA already fetched for For you is used when one exists.
    func studioTravelMinutes(_ id: Int) -> Int? {
        guard let p = studioPoint(id) else { return nil }
        let from = userLocation.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
            ?? recSettings.home?.point ?? GeoPoint(lat: refLat, lon: refLon)
        let mode = recSettings.mode
        return travelOverrides[Recommender.travelKey(from, p, mode)] ?? mode.estimateMinutes(meters: Recommender.meters(from, p))
    }
}
