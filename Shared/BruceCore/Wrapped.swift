import Foundation

// MARK: - Brüce Wrapped: the year so far, computed on the device (iOS and macOS compile this; the UI is iOS only)
//
// Numbers come from the visit history the Statistics screen loads (`GET /v52/booking`, checked-in visits), deduped
// with the contract's visit rule (`VisitDedupe`), from January 1 to now. "You and Robin" matches friends' bookings
// this year (`GET /v52/booking?friends=true&class_day_after=<Jan 1>`) with the user's classes by class id. The
// percentiles come from our server (`GET /wrapped/percentiles`, CONTRACT.md) and are skipped when it is off.
// The rules mirror docs/app/js/wrapped-stats.js so both apps tell the same story.

/// The user's class personality, chosen by rules on time of day, weekdays, categories and studio variety.
struct WrappedPersona: Hashable {
    enum Kind: String, Hashable {
        case earlyBird, nightOwl, lunchBreaker, weekendWarrior, zenMaster, ironRegular, explorer, loyalist, allRounder, newcomer
    }
    let kind: Kind
    let title: String
    let blurb: String
    /// SF Symbol for the share card tag and the persona card.
    var symbol: String {
        switch kind {
        case .earlyBird: "sunrise.fill"
        case .nightOwl: "moon.stars.fill"
        case .lunchBreaker: "fork.knife"
        case .weekendWarrior: "flag.checkered"
        case .zenMaster: "leaf.fill"
        case .ironRegular: "dumbbell.fill"
        case .explorer: "map.fill"
        case .loyalist: "heart.fill"
        case .allRounder, .newcomer: "sparkles"
        }
    }
}

struct WrappedStats: Hashable {
    var year: Int
    var firstName: String?
    var visits = 0
    var classes = 0
    var dropins: Int { visits - classes }
    var minutes = 0
    var hours: Int { Int((Double(minutes) / 60).rounded()) }
    /// Days per visit so far this year ("One visit every 1.5 days"), nil without visits.
    var every: Double?
    /// Visits per month, January first; `monthNow` is the current month's index (later months are the future).
    var months: [Int] = Array(repeating: 0, count: 12)
    var monthNow = 0
    var bestMonth: Int? { visits > 0 ? months.indices.max { months[$0] < months[$1] || (months[$0] == months[$1] && $0 > $1) } : nil }
    var persona = WrappedPersona(kind: .newcomer, title: "The Newcomer", blurb: "")
    /// Favourite studio by visits, and how many different studios.
    var topStudio: (id: Int, name: String, count: Int)?
    var studios = 0
    var topClass: (title: String, count: Int)?
    /// Most common hour of the day (0-23) and how many visits started in it.
    var topHour: (hour: Int, count: Int)?
    /// Longest run of weeks in a row (Monday to Sunday) with a visit, with the first and last visit day of the run.
    var streak: (weeks: Int, from: Date?, to: Date?) = (0, nil, nil)
    /// The friend the user did most classes with this year.
    var friend: (userId: Int, name: String, initials: String, count: Int)?
    /// "Top N%" figures from our server; nil when the server is off, not reachable or the cohort is too small.
    var percentiles: WrappedPercentiles?

    static func == (a: WrappedStats, b: WrappedStats) -> Bool { a.hashKey == b.hashKey }
    func hash(into h: inout Hasher) { h.combine(hashKey) }
    private var hashKey: String {
        "\(year)|\(visits)|\(classes)|\(minutes)|\(months)|\(persona.kind)|\(topStudio?.id ?? 0)|\(topClass?.title ?? "")|\(streak.weeks)|\(friend?.userId ?? 0)|\(friend?.count ?? 0)|\(percentiles?.visits ?? -1)"
    }

    var topHourLabel: String? { topHour.map { String(format: "%02d:00", $0.hour) } }

    /// "3 Aug to 20 Sep" (or "3 to 20 Sep" within a month).
    var streakRange: String {
        guard let f = streak.from, let t = streak.to else { return "" }
        let cal = BruceDate.calendar
        if cal.isDate(f, inSameDayAs: t) { return BruceDate.format(f, "d MMM") }
        if cal.isDate(f, equalTo: t, toGranularity: .month) { return "\(BruceDate.format(f, "d")) to \(BruceDate.format(t, "d MMM"))" }
        return "\(BruceDate.format(f, "d MMM")) to \(BruceDate.format(t, "d MMM"))"
    }

    /// The story cards to show, in order; a card without data is skipped. The share card is always last.
    enum Card: String, Hashable, CaseIterable { case intro, visits, persona, place, streak, top, share }
    var cards: [Card] {
        var c: [Card] = [.intro]
        if visits > 0 { c.append(.visits) }
        if visits >= 3 { c.append(.persona) }
        if topStudio != nil { c.append(.place) }
        if streak.weeks >= 2 || friend != nil { c.append(.streak) }
        if visits > 0, percentiles?.visits != nil { c.append(.top) }
        c.append(.share)
        return c
    }

    /// The share card's stat tiles, up to six: (value, label).
    var shareTiles: [(value: String, label: String)] {
        var out: [(String, String)] = [("\(visits)", visits == 1 ? "visit" : "visits")]
        if hours > 0 { out.append(("\(hours) h", "trained")) }
        if let c = topClass { out.append(("\(c.count)×", "\(c.title), top class")) }
        if let s = topStudio { out.append(("\(s.count)", "at \(s.name)")) }
        if streak.weeks >= 2 { out.append(("\(streak.weeks) wk", "longest streak")) }
        if let f = friend { out.append(("\(f.count)", "\(f.count == 1 ? "class" : "classes") with \(f.name)")) }
        if out.count < 6, studios > 1 { out.append(("\(studios)", "studios tried")) }
        if out.count < 6, let b = bestMonth { out.append(("\(months[b])", "in \(Wrapped.monthNames[b]), best month")) }
        return Array(out.prefix(6))
    }
}

/// `GET /wrapped/percentiles` answer: share (0-100) of other Brüce users below the user, per metric.
struct WrappedPercentiles: Decodable, Hashable {
    var visits: Int?
    var minutes: Int?
    var studios: Int?
    var streak: Int?
    var cohort: Int?
    /// "Top N%" from a percentile.
    static func top(_ p: Int) -> Int { max(1, 100 - p) }
}

enum Wrapped {
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                             "October", "November", "December"]
    /// Calm classes for the Zen Master, matched against class titles and category titles.
    static let zenWords = ["yoga", "meditat", "pilates", "stretch", "mobility", "breath", "yin", "barre", "spa", "sauna"]

    /// Year-to-date numbers from the visit history (any order, may span years).
    /// - `studioName`: a studio's name by id (drop-ins carry no studio name).
    /// - `categoryTitle`: a Bruce category's title by id (Zen Master).
    /// - `friendBookings`/`friendName`: friends' bookings this year, and a friend's first name by user id.
    static func stats(visits all: [BruceAPI.Visit], now: Date = Date(), firstName: String? = nil,
                      studioName: (Int) -> String? = { _ in nil }, categoryTitle: (Int) -> String? = { _ in nil },
                      friendBookings: [BruceAPI.FriendBooking] = [], friendName: (Int) -> String? = { _ in nil }) -> WrappedStats {
        let cal = BruceDate.calendar
        let year = cal.component(.year, from: now)
        let vs = VisitDedupe.unique(all.filter { v in
            guard let d = v.date else { return false }
            return d <= now && cal.component(.year, from: d) == year
        }).sorted { $0.date! < $1.date! }
        var s = WrappedStats(year: year, firstName: firstName)
        s.monthNow = cal.component(.month, from: now) - 1
        s.visits = vs.count
        s.classes = vs.filter { !$0.isSolo }.count
        s.minutes = vs.reduce(0) { $0 + ($1.durationMinutes ?? 60) }
        for v in vs { s.months[cal.component(.month, from: v.date!) - 1] += 1 }
        if s.visits > 0, let jan1 = cal.dateInterval(of: .year, for: now)?.start {
            let days = (cal.dateComponents([.day], from: jan1, to: cal.startOfDay(for: now)).day ?? 0) + 1
            s.every = (Double(days) / Double(s.visits) * 10).rounded() / 10
        }

        let byStudio = tally(vs.compactMap(\.studioRef))
        s.studios = byStudio.count
        if let top = byStudio.first {
            let name = studioName(top.key) ?? vs.first { $0.studioRef == top.key }?.visitClass?.studio?.name ?? "Your top studio"
            s.topStudio = (top.key, name, top.count)
        }
        s.topClass = tally(vs.filter { !$0.isSolo }.map(\.title).filter { !$0.isEmpty }).first.map { ($0.key, $0.count) }
        s.topHour = tally(vs.map { cal.component(.hour, from: $0.date!) }).first.map { ($0.key, $0.count) }
        s.streak = longestStreak(vs.compactMap(\.date))
        s.persona = persona(vs, categoryTitle: categoryTitle)

        // Friends: classes both attended, matched by class id.
        let mine = Set(vs.filter { !$0.isSolo }.compactMap { $0.classId ?? $0.visitClass?.id })
        var per: [Int: Set<Int>] = [:]
        for b in friendBookings {
            guard let uid = b.userId, let cid = b.classId ?? b.class?.id, mine.contains(cid) else { continue }
            per[uid, default: []].insert(cid)
        }
        if let best = per.max(by: { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) }),
           let name = friendName(best.key), !name.isEmpty {
            s.friend = (best.key, name, String(name.prefix(1)).uppercased(), best.value.count)
        }
        return s
    }

    /// Counts per key, most first (ties: the smaller key first, so the result is stable).
    static func tally<K: Hashable & Comparable>(_ keys: [K]) -> [(key: K, count: Int)] {
        var m: [K: Int] = [:]
        for k in keys { m[k, default: 0] += 1 }
        return m.map { (key: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
    }

    /// Longest run of consecutive weeks (Monday to Sunday) with a visit, with the first and last visit of the run.
    static func longestStreak(_ dates: [Date]) -> (weeks: Int, from: Date?, to: Date?) {
        let cal = BruceDate.calendar
        let sorted = dates.sorted()
        let weeks = Array(Set(sorted.compactMap { cal.dateInterval(of: .weekOfYear, for: $0)?.start })).sorted()
        var best = (n: 0, start: Date?.none, end: Date?.none)
        var run = 0, start: Date?, prev: Date?
        for w in weeks {
            if let p = prev, let next = cal.date(byAdding: .weekOfYear, value: 1, to: p), cal.isDate(next, inSameDayAs: w) { run += 1 }
            else { run = 1; start = w }
            if run > best.n { best = (run, start, w) }
            prev = w
        }
        guard best.n > 0, let a = best.start, let b = best.end, let bEnd = cal.date(byAdding: .day, value: 7, to: b) else { return (0, nil, nil) }
        let inRun = sorted.filter { $0 >= a && $0 < bEnd }
        return (best.n, inRun.first, inRun.last)
    }

    /// Class personality by rules (same order and thresholds as the web app).
    static func persona(_ vs: [BruceAPI.Visit], categoryTitle: (Int) -> String?) -> WrappedPersona {
        let n = vs.count
        guard n > 0 else {
            return WrappedPersona(kind: .newcomer, title: "The Newcomer", blurb: "Your first visit is the hardest. The rest of the year is yours.")
        }
        let cal = BruceDate.calendar
        func hour(_ v: BruceAPI.Visit) -> Int { cal.component(.hour, from: v.date!) }
        /// 0 = Monday.
        func weekday(_ v: BruceAPI.Visit) -> Int { (cal.component(.weekday, from: v.date!) + 5) % 7 }
        func count(_ f: (BruceAPI.Visit) -> Bool) -> Int { vs.filter(f).count }
        func share(_ f: (BruceAPI.Visit) -> Bool) -> Double { Double(count(f)) / Double(n) }
        let early = { (v: BruceAPI.Visit) in hour(v) < 8 }
        let night = { (v: BruceAPI.Visit) in hour(v) >= 19 }
        let lunch = { (v: BruceAPI.Visit) in weekday(v) < 5 && (11..<14).contains(hour(v)) }
        let weekend = { (v: BruceAPI.Visit) in weekday(v) >= 5 }
        let zen = { (v: BruceAPI.Visit) -> Bool in
            let texts = [v.isSolo ? "" : v.title] + v.categoryIds.compactMap(categoryTitle)
            return texts.contains { t in zenWords.contains { t.lowercased().contains($0) } }
        }
        let dropin = { (v: BruceAPI.Visit) in v.isSolo }
        let studios = tally(vs.compactMap(\.studioRef))
        if n >= 3, share(early) >= 0.35 {
            return .init(kind: .earlyBird, title: "The Early Bird", blurb: "\(count(early)) visits before 08:00. The morning crew knows you by name.")
        }
        if n >= 3, share(night) >= 0.35 {
            return .init(kind: .nightOwl, title: "The Night Owl", blurb: "\(count(night)) visits after 19:00. You own the late slots.")
        }
        if n >= 3, share(lunch) >= 0.3 {
            return .init(kind: .lunchBreaker, title: "The Lunch Breaker", blurb: "\(count(lunch)) lunch-break visits. Who needs a sandwich anyway?")
        }
        if n >= 3, share(weekend) >= 0.4 {
            return .init(kind: .weekendWarrior, title: "The Weekend Warrior", blurb: "\(count(weekend)) visits on Saturdays and Sundays. Weekends are for training.")
        }
        if n >= 3, share(zen) >= 0.4 {
            return .init(kind: .zenMaster, title: "The Zen Master", blurb: "\(count(zen)) calm sessions: yoga, stretch and breath. Namaste.")
        }
        if n >= 3, share(dropin) >= 0.6 {
            return .init(kind: .ironRegular, title: "The Iron Regular", blurb: "\(count(dropin)) solo sessions. No class needed, just you and the weights.")
        }
        if studios.count >= 8 || (n >= 6 && Double(studios.count) / Double(n) >= 0.3) {
            return .init(kind: .explorer, title: "The Explorer", blurb: "\(studios.count) different studios. Always looking for the next one.")
        }
        if let top = studios.first, n >= 5, Double(top.count) / Double(n) >= 0.6 {
            return .init(kind: .loyalist, title: "The Loyalist", blurb: "\(Int((100 * Double(top.count) / Double(n)).rounded()))% of your visits at one place. Loyal to the core.")
        }
        return .init(kind: .allRounder, title: "The All-Rounder", blurb: "A bit of everything, at all hours. Hard to pin down.")
    }
}

// MARK: - Loading

extension BruceAPI {
    /// Friends' bookings since `since` (`GET /v52/booking?friends=true&class_day_after=yyyyMMdd`), paged by `next_cursor`.
    static func fetchFriendsBookings(token: String, userId: Int, since: Date, maxPages: Int = 40) async throws -> [FriendBooking] {
        struct R: Decodable { let bookings: [FriendBooking]; let metadata: Metadata? }
        var all: [Int: FriendBooking] = [:]
        var cursor: String?
        for _ in 0..<maxPages {
            var q = [("user_id", String(userId)), ("friends", "true"), ("class_day_after", BruceDate.format(since, "yyyyMMdd")),
                     ("deleted", "false"), ("limit", "30"), ("locale", "en")]
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token)))
            let before = all.count
            for b in r.bookings { all[b.id] = b }
            guard let next = r.metadata?.pagination?.nextCursor, !next.isEmpty, !r.bookings.isEmpty, all.count > before else { break }
            cursor = next
        }
        return Array(all.values)
    }
}

enum WrappedServer {
    /// `GET /wrapped/percentiles?year=&visits=&minutes=&studios=&streak=` -> the percentiles, nil when the cohort is
    /// too small (`percentiles: null`).
    static func percentiles(_ s: WrappedStats, session: Session) async throws -> WrappedPercentiles? {
        struct R: Decodable { let cohort: Int?; let percentiles: WrappedPercentiles? }
        var req = try AutoBookServer.request("GET", "wrapped/percentiles", session: session)
        guard let url = req.url, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [("year", s.year), ("visits", s.visits), ("minutes", s.minutes), ("studios", s.studios), ("streak", s.streak.weeks)]
            .map { URLQueryItem(name: $0.0, value: String($0.1)) }
        req.url = comps.url
        let r = try JSONDecoder().decode(R.self, from: try await BruceAPI.send(req))
        guard var p = r.percentiles else { return nil }
        p.cohort = r.cohort
        return p
    }
}

extension AppModel {
    /// Everything Wrapped shows: the visit history (shared with Statistics), friends' bookings this year and, when
    /// our server is on, the percentiles. Failures of the extras only hide their cards.
    func loadWrapped(now: Date = Date()) async -> WrappedStats {
        let cal = BruceDate.calendar
        let jan1 = cal.dateInterval(of: .year, for: now)?.start ?? now
        let visits = await fetchVisitHistory()
        var friendBookings: [BruceAPI.FriendBooking] = []
        if AppModel.demo {
            friendBookings = Self.demoYearFriendBookings(visits)
        } else if tokenUsable, let uid = userId {
            friendBookings = (try? await BruceAPI.fetchFriendsBookings(token: token, userId: uid, since: jan1)) ?? []
        }
        var names: [Int: String] = [:]
        for f in friends { if let u = f.friendUser, let n = u.firstName { names[u.id] = n } }
        var studioNames: [Int: String] = [:]
        for st in studios { studioNames[st.id] = st.name }
        for v in visits { if let id = v.studioRef, studioNames[id] == nil { studioNames[id] = studio(id)?.name } }
        let categoryTitles = Dictionary(categories.compactMap { c in c.title.map { (c.id, $0) } }, uniquingKeysWith: { a, _ in a })
        var s = Wrapped.stats(visits: visits, now: now, firstName: user?.firstName ?? (AppModel.demo ? "Uwe" : nil),
                              studioName: { studioNames[$0] }, categoryTitle: { categoryTitles[$0] },
                              friendBookings: friendBookings, friendName: { names[$0] })
        if AppModel.demo {
            s.percentiles = WrappedPercentiles(visits: 92, minutes: 88, studios: 70, streak: 79, cohort: 23)
        } else if s.visits > 0, tokenUsable, let session, AutoBookServer.isConfigured, AutoBookServer.booksForMe {
            s.percentiles = try? await WrappedServer.percentiles(s, session: session)
        }
        return s
    }
}
