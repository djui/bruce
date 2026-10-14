import Foundation
import CoreLocation

// MARK: - Recommendations ("For you" on Home), computed on the device only
//
// Upcoming classes (the next ~2 days) from the class lists the app already loads (per studio and per day) are
// scored against the user's own visit history (`GET /v52/booking`, Statistics.swift), friends' bookings
// (`GET /v52/booking?friends=true`) and travel time from the places saved in Settings › Places & commute.
// Places never leave the device. The scoring (`Recommender`) is pure: the app feeds it data and, on iOS,
// MapKit ETAs (`AppModel.travelTimeProvider`) for the few studios worth asking about.

/// How the user gets around.
enum CommuteMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case walk, bike, transit, car
    var id: String { rawValue }
    var title: String {
        switch self { case .walk: "Walk"; case .bike: "Bike"; case .transit: "Transit"; case .car: "Car" }
    }
    var symbol: String {
        switch self { case .walk: "figure.walk"; case .bike: "bicycle"; case .transit: "tram.fill"; case .car: "car.fill" }
    }
    /// Average speed on the street network, km/h (transit includes walking to and waiting at the stop).
    var kmh: Double {
        switch self { case .walk: 4.8; case .bike: 15; case .transit: 17; case .car: 24 }
    }
    /// Fixed minutes per trip: unlocking the bike, waiting for transit, parking.
    var overhead: Double {
        switch self { case .walk: 0; case .bike: 1; case .transit: 6; case .car: 4 }
    }
    /// Straight line -> street distance.
    static let detourFactor = 1.3

    /// Cheap estimate from the straight-line distance (prefilter, and the fallback when MapKit has no ETA).
    func estimateMinutes(meters: Double) -> Int {
        guard meters > 30 else { return 0 }
        let km = meters * Self.detourFactor / 1000
        return max(1, Int((km / kmh * 60 + overhead).rounded()))
    }
}

/// A place saved in Places & commute (device only).
struct SavedPlace: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case home, work, other }
    var id = UUID()
    var kind: Kind
    var name: String
    /// "Rosenlundsgatan, Södermalm".
    var address: String
    var point: GeoPoint
    /// Days the user is at this place (work), Calendar weekdays 1 = Sunday ... 7 = Saturday.
    var workdays: [Int] = [2, 3, 4, 5, 6]

    var symbol: String {
        switch kind { case .home: "house.fill"; case .work: "briefcase.fill"; case .other: "mappin" }
    }
    /// "Mon–Fri", "Mon, Wed, Thu", "Every day".
    var workdaysLabel: String { SavedPlace.daysLabel(workdays) }

    static func daysLabel(_ days: [Int]) -> String {
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        let sorted = order.filter(days.contains)
        if sorted.count == 7 { return "Every day" }
        if sorted.isEmpty { return "No days" }
        if sorted.count >= 3, let a = order.firstIndex(of: sorted[0]), order[a..<(a + sorted.count)].elementsEqual(sorted) {
            return "\(names[sorted.first!]!)–\(names[sorted.last!]!)"
        }
        return sorted.compactMap { names[$0] }.joined(separator: ", ")
    }
}

/// Places & commute settings. Stored in UserDefaults on this device only; never sent anywhere.
struct RecSettings: Codable, Hashable {
    var places: [SavedPlace] = []
    var mode: CommuteMode = .bike
    /// Max extra minutes for "On your way home".
    var maxDetour: Int = 15
    /// Workdays near work: classes starting in this window are measured from work (minutes after midnight).
    var workStart: Int = 11 * 60 + 30
    var workEnd: Int = 13 * 60 + 30
    var useFriends = true

    var home: SavedPlace? { places.first { $0.kind == .home } }
    var work: SavedPlace? { places.first { $0.kind == .work } }

    static let key = "recSettings"
    static func load() -> RecSettings {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(RecSettings.self, from: d) else { return RecSettings() }
        return s
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    /// "11:30–13:30".
    var workWindowLabel: String { "\(Self.clock(workStart))–\(Self.clock(workEnd))" }
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// Fictional places for demo mode (a home on Södermalm, work in Norrmalm).
    static let demo = RecSettings(places: [
        SavedPlace(kind: .home, name: "Home", address: "Rosenlundsgatan, Södermalm", point: GeoPoint(lat: 59.3158, lon: 18.0612)),
        SavedPlace(kind: .work, name: "Work", address: "Kungsgatan, Norrmalm", point: GeoPoint(lat: 59.3355, lon: 18.0655)),
    ])
}

/// Why a class is recommended, shown as a chip.
struct RecReason: Hashable {
    enum Kind: Hashable { case travel, history, category, slot, friends }
    let kind: Kind
    let text: String
    var symbol: String? = nil
    /// Friends' user ids (faces on the chip).
    var friendIds: [Int] = []
}

struct Recommendation: Identifiable, Hashable {
    let c: BruceAPI.BruceClass
    /// 0-99, "96% match".
    let match: Int
    let reasons: [RecReason]
    /// Free spots when only a few are left ("2 spots left").
    let fewSpots: Int?
    var id: Int { c.id }
}

/// Time of day the user tends to train ("Lunch slot you use").
enum DaySlot: Int, CaseIterable, Hashable {
    case early, morning, lunch, afternoon, evening, late
    init(minuteOfDay m: Int) {
        switch m {
        case ..<(8 * 60 + 30): self = .early
        case ..<(11 * 60): self = .morning
        case ..<(14 * 60): self = .lunch
        case ..<(17 * 60): self = .afternoon
        case ..<(20 * 60): self = .evening
        default: self = .late
        }
    }
    var name: String {
        switch self {
        case .early: "Early"; case .morning: "Morning"; case .lunch: "Lunch"
        case .afternoon: "Afternoon"; case .evening: "Evening"; case .late: "Late"
        }
    }
}

/// What the user did in the last 180 days: favourite titles, categories, studios and time slots.
struct VisitProfile {
    var total = 0
    var classTotal = 0
    var titles: [String: Int] = [:]
    var titleAtStudio: [String: Int] = [:]
    var categories: [Int: Int] = [:]
    var studios: [Int: Int] = [:]
    /// Weekend flag + slot.
    var slots: [String: Int] = [:]

    init(visits: [BruceAPI.Visit], now: Date = Date(), days: Int = 180) {
        let cal = BruceDate.calendar
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        for v in VisitDedupe.unique(visits) {
            guard let d = v.date, d >= since, d <= now else { continue }
            total += 1
            if let s = v.studioRef { studios[s, default: 0] += 1 }
            let c = cal.dateComponents([.hour, .minute, .weekday], from: d)
            slots[Self.slotKey(weekday: c.weekday ?? 2, minute: (c.hour ?? 0) * 60 + (c.minute ?? 0)), default: 0] += 1
            guard !v.isSolo else { continue }
            classTotal += 1
            let t = Self.norm(v.title)
            titles[t, default: 0] += 1
            if let s = v.studioRef { titleAtStudio["\(t)|\(s)", default: 0] += 1 }
            for cat in Set(v.categoryIds) { categories[cat, default: 0] += 1 }
        }
    }

    static func norm(_ title: String) -> String { title.lowercased().trimmingCharacters(in: .whitespaces) }
    static func slotKey(weekday: Int, minute: Int) -> String {
        "\(weekday == 1 || weekday == 7 ? "we" : "wd")-\(DaySlot(minuteOfDay: minute).rawValue)"
    }
}

/// Everything the scorer needs, gathered by `AppModel.refreshRecommendations()`.
struct RecInput {
    var now = Date()
    var classes: [BruceAPI.BruceClass]
    /// Studio coordinates and names by id.
    var studioPoints: [Int: GeoPoint]
    var visits: [BruceAPI.Visit]
    var friendsByClass: [Int: [BruceAPI.UserLite]]
    /// Classes the user booked or is waitlisted for.
    var excluded: Set<Int>
    var settings: RecSettings
    var categoryTitles: [Int: String]
    /// Refined minutes (MapKit ETA), keyed by `Recommender.travelKey`.
    var travelOverrides: [String: Int] = [:]
}

/// A travel question worth asking MapKit.
struct TravelQuery: Hashable {
    let key: String
    let from: GeoPoint
    let to: GeoPoint
    let mode: CommuteMode
}

enum Recommender {
    static let horizon: TimeInterval = 48 * 3600
    static let maxPicks = 12

    static func travelKey(_ from: GeoPoint, _ to: GeoPoint, _ mode: CommuteMode) -> String {
        String(format: "%.4f,%.4f>%.4f,%.4f|%@", from.lat, from.lon, to.lat, to.lon, mode.rawValue)
    }

    static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lon).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
    }

    /// Classes worth ranking: start 20 min to 48 h from now, listed, not full, not booked or waitlisted.
    static func candidates(_ input: RecInput) -> [BruceAPI.BruceClass] {
        var seen = Set<Int>()
        return input.classes.filter { c in
            guard seen.insert(c.id).inserted, c.isListed, !input.excluded.contains(c.id), let s = c.start else { return false }
            guard s > input.now.addingTimeInterval(20 * 60), s < input.now.addingTimeInterval(horizon) else { return false }
            if let a = c.availableSpots, a <= 0 { return false }
            // Bookable now, or opens before the class starts (soon bookable).
            if let o = c.bookingOpens, o > s { return false }
            return true
        }
    }

    /// The place a class is measured from, and how.
    enum Leg { case fromHome(Int), fromWork(Int), wayHome(Int) }

    static func minutes(_ from: GeoPoint, _ to: GeoPoint, _ input: RecInput) -> Int {
        let mode = input.settings.mode
        return input.travelOverrides[travelKey(from, to, mode)] ?? mode.estimateMinutes(meters: meters(from, to))
    }

    static func leg(for c: BruceAPI.BruceClass, input: RecInput) -> Leg? {
        guard let s = c.start, let p = input.studioPoints[c.studioId] else { return nil }
        let st = input.settings
        let comps = BruceDate.calendar.dateComponents([.weekday, .hour, .minute], from: s)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if let w = st.work, w.workdays.contains(comps.weekday ?? 0) {
            if minute >= st.workStart && minute <= st.workEnd { return .fromWork(minutes(w.point, p, input)) }
            // After work: a class near the line from work to home costs only the detour.
            if let h = st.home, minute > st.workEnd, minute < 21 * 60 {
                let detour = minutes(w.point, p, input) + minutes(p, h.point, input) - minutes(w.point, h.point, input)
                if detour <= st.maxDetour { return .wayHome(max(0, detour)) }
            }
        }
        if let h = st.home { return .fromHome(minutes(h.point, p, input)) }
        return nil
    }

    /// The few (place, studio) pairs worth a real ETA: the closest candidate studios by straight-line estimate.
    static func travelQueries(_ input: RecInput, limit: Int = 12) -> [TravelQuery] {
        let mode = input.settings.mode
        var out: [TravelQuery: Int] = [:]
        for c in candidates(input) {
            guard let p = input.studioPoints[c.studioId] else { continue }
            for place in input.settings.places where place.kind != .other {
                let est = mode.estimateMinutes(meters: meters(place.point, p))
                guard est <= 40 else { continue }
                out[TravelQuery(key: travelKey(place.point, p, mode), from: place.point, to: p, mode: mode)] = est
            }
        }
        var list = out.sorted { $0.value < $1.value }.map(\.key)
        list = Array(list.filter { input.travelOverrides[$0.key] == nil }.prefix(limit))
        if let h = input.settings.home, let w = input.settings.work {
            let q = TravelQuery(key: travelKey(w.point, h.point, mode), from: w.point, to: h.point, mode: mode)
            if input.travelOverrides[q.key] == nil { list.insert(q, at: 0) }
        }
        return list
    }

    /// Ranks the candidates, best first, at most `maxPicks`, one per title and studio.
    static func rank(_ input: RecInput) -> [Recommendation] {
        let profile = VisitProfile(visits: input.visits, now: input.now)
        let cal = BruceDate.calendar
        let mode = input.settings.mode
        let hasPlaces = input.settings.home != nil || input.settings.work != nil
        var scored: [(Double, Recommendation)] = []
        for c in candidates(input) {
            guard let s = c.start else { continue }
            var parts: [(weight: Double, value: Double, reason: RecReason?)] = []

            // Travel
            if hasPlaces {
                var value = 0.0, reason: RecReason?
                switch leg(for: c, input: input) {
                case .fromWork(let m)?:
                    value = max(0, 1 - Double(m) / 35)
                    if m <= 25 { reason = RecReason(kind: .travel, text: mode == .walk ? "\(m) min walk from work" : "\(m) min from work", symbol: "briefcase.fill") }
                case .wayHome(let d)?:
                    value = max(0.55, 1 - Double(d) / 30)
                    reason = RecReason(kind: .travel, text: "On your way home · +\(d) min", symbol: mode.symbol)
                case .fromHome(let m)?:
                    value = max(0, 1 - Double(m) / 35)
                    if m <= 25 { reason = RecReason(kind: .travel, text: "\(m) min from home", symbol: mode.symbol) }
                case nil: break
                }
                parts.append((0.18, value, reason))
            }

            // History: this class here, this class anywhere, or its category
            let t = VisitProfile.norm(c.title)
            let here = profile.titleAtStudio["\(t)|\(c.studioId)"] ?? 0
            let anywhere = profile.titles[t] ?? 0
            let titleValue = max(min(1, Double(here) / 6), min(1, Double(anywhere) / 8) * 0.8)
            var titleReason: RecReason?
            if here >= 2 { titleReason = RecReason(kind: .history, text: "You did \(here) \(plural(c.title)) here", symbol: "clock.arrow.circlepath") }
            else if anywhere >= 3 { titleReason = RecReason(kind: .history, text: "You did \(anywhere) \(plural(c.title))", symbol: "clock.arrow.circlepath") }
            parts.append((0.28, titleValue, titleReason))

            let cats = (c.classCategories ?? []).compactMap(\.categoryId)
            let best = cats.map { ($0, profile.categories[$0] ?? 0) }.max { $0.1 < $1.1 }
            let catValue = min(1, Double(best?.1 ?? 0) / 6)
            var catReason: RecReason?
            if titleReason == nil, let b = best, b.1 >= 4, let name = input.categoryTitles[b.0] {
                catReason = RecReason(kind: .category, text: "You do \(name) often", symbol: "heart.fill")
            }
            parts.append((0.12, catValue, catReason))

            parts.append((0.12, min(1, Double(profile.studios[c.studioId] ?? 0) / 8), nil))

            // Time slot
            let comps = cal.dateComponents([.weekday, .hour, .minute], from: s)
            let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let slotCount = profile.slots[VisitProfile.slotKey(weekday: comps.weekday ?? 2, minute: minute)] ?? 0
            let share = profile.total > 0 ? Double(slotCount) / Double(profile.total) : 0
            let slotReason = share >= 0.2 && slotCount >= 3
                ? RecReason(kind: .slot, text: "\(DaySlot(minuteOfDay: minute).name) slot you use") : nil
            parts.append((0.14, min(1, share * 3), slotReason))

            // Friends
            if input.settings.useFriends {
                let fs = input.friendsByClass[c.id] ?? []
                var reason: RecReason?
                if !fs.isEmpty {
                    let names = fs.compactMap(\.firstName)
                    let text = fs.count == 1 ? "\(names.first ?? "A friend") booked"
                        : fs.count == 2 && names.count == 2 ? names.joined(separator: ", ") : "\(fs.count) friends going"
                    reason = RecReason(kind: .friends, text: text, friendIds: fs.map(\.id))
                }
                parts.append((0.16, min(1, Double(fs.count) / 2), reason))
            }

            let weight = parts.map(\.weight).reduce(0, +)
            let raw = weight > 0 ? parts.map { $0.weight * $0.value }.reduce(0, +) / weight : 0
            let match = min(99, Int((100 * (0.42 + 0.6 * raw)).rounded()))
            // Chips in a fixed order: travel, history, time slot, friends.
            let order: [RecReason.Kind: Int] = [.travel: 0, .history: 1, .category: 1, .slot: 2, .friends: 3]
            let reasons = parts.compactMap(\.reason).sorted { order[$0.kind]! < order[$1.kind]! }
            let few = c.availableSpots.flatMap { (1...3).contains($0) ? $0 : nil }
            scored.append((raw + (few != nil ? 0.001 : 0), Recommendation(c: c, match: match, reasons: reasons, fewSpots: few)))
        }
        // Best first; a weekly class shows once (its best occurrence).
        var seen = Set<String>()
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : ($0.1.c.startTime < $1.1.c.startTime) }
            .map(\.1)
            .filter { seen.insert("\(VisitProfile.norm($0.c.title))|\($0.c.studioId)").inserted }
            .prefix(maxPicks).map { $0 }
    }

    /// "Reformer" -> "Reformers", "Hatha Flow" -> "Hatha Flows", "Yoga Class" -> "Yoga Classes".
    static func plural(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("s") || t.hasSuffix("x") || t.hasSuffix("ch") { return t + "es" }
        return t + "s"
    }
}

// MARK: - App state

extension AppModel {
    /// iOS sets this to a MapKit ETA lookup (cached); nil (macOS, demo) uses the distance estimate only.
    @MainActor static var travelTimeProvider: ((TravelQuery) async -> Int?)?

    func studioPoint(_ id: Int) -> GeoPoint? {
        guard let s = studio(id),
              let a = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
              let lat = a.latitude, let lon = a.longitude else { return nil }
        return GeoPoint(lat: lat, lon: lon)
    }

    func saveRecSettings(_ s: RecSettings) {
        recSettings = s
        if !AppModel.demo { s.save() }
        Task { await refreshRecommendations(force: true) }
    }

    /// Studios whose next days of classes are worth loading: the ones the user visits most and the ones near
    /// their places (at most 14, so only a few requests).
    func recommendationStudios(visits: [BruceAPI.Visit]) -> [Int] {
        var counts: [Int: Int] = [:]
        for v in visits.prefix(300) { if let s = v.studioRef { counts[s, default: 0] += 1 } }
        var out = counts.sorted { $0.value > $1.value }.prefix(8).map(\.key)
        let mode = recSettings.mode
        var near: [(Int, Int)] = []
        for s in cityStudios where s.hasClasses != false {
            guard let p = studioPoint(s.id) else { continue }
            let best = recSettings.places.map { mode.estimateMinutes(meters: Recommender.meters($0.point, p)) }.min() ?? 99
            if best <= 15 { near.append((s.id, best)) }
        }
        for (id, _) in near.sorted(by: { $0.1 < $1.1 }).prefix(6) where !out.contains(id) { out.append(id) }
        return Array(out.prefix(14))
    }

    /// Recomputes Home "For you". Loads what it needs once (history, the next days of classes at the user's studios),
    /// ranks with the distance estimate, then refines the closest studios with real ETAs and ranks again.
    func refreshRecommendations(force: Bool = false) async {
        guard isLoggedIn else { recommendations = []; return }
        if let t = recommendTask, !force { await t.value; return }
        recommendTask?.cancel()
        let t = Task { await self.computeRecommendations() }
        recommendTask = t
        await t.value
        if recommendTask == t { recommendTask = nil }
    }

    private func computeRecommendations() async {
        recommendationsLoading = recommendations.isEmpty
        defer { recommendationsLoading = false }
        let visits = await fetchVisitHistory()
        if !AppModel.demo {
            let ids = recommendationStudios(visits: visits)
            await withTaskGroup(of: Void.self) { g in
                var it = ids.makeIterator()
                for _ in 0..<4 { if let id = it.next() { g.addTask { await self.loadStudioClasses(id) } } }
                while await g.next() != nil { if let id = it.next() { g.addTask { await self.loadStudioClasses(id) } } }
            }
        }
        guard !Task.isCancelled else { return }
        var input = recInput(visits: visits)
        recommendations = Recommender.rank(input)
        guard let eta = AppModel.travelTimeProvider, !AppModel.demo else { return }
        let queries = Recommender.travelQueries(input)
        guard !queries.isEmpty else { return }
        for q in queries {
            guard !Task.isCancelled else { return }
            if let m = await eta(q) { travelOverrides[q.key] = m }
        }
        input.travelOverrides = travelOverrides
        recommendations = Recommender.rank(input)
    }

    func recInput(visits: [BruceAPI.Visit]) -> RecInput {
        var classes = classesByDay.values.joined().map { $0 } + studioClasses.values.joined()
        classes += friendsBookings.compactMap(\.class)
        var friendsBy: [Int: [BruceAPI.UserLite]] = [:]
        for c in classes where friendsBy[c.id] == nil {
            let f = friendsBooked(c.id)
            if !f.isEmpty { friendsBy[c.id] = f }
        }
        var points: [Int: GeoPoint] = [:]
        for id in Set(classes.map(\.studioId)) { points[id] = studioPoint(id) }
        let excluded = Set(bookings.compactMap { $0.classId ?? $0.class?.id } + standbys.compactMap { $0.class?.id })
        return RecInput(classes: classes, studioPoints: points, visits: visits, friendsByClass: friendsBy, excluded: excluded,
                        settings: recSettings, categoryTitles: Dictionary(categories.map { ($0.id, $0.title ?? "") }, uniquingKeysWith: { a, _ in a }),
                        travelOverrides: travelOverrides)
    }
}
