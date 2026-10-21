import Foundation
import UserNotifications

// Race events: a hand-curated catalog of Nordic races and "My races" on the device.
//
// The catalog is `docs/app/races.json` in this repository, published by GitHub Pages and read by all three apps
// (`RaceCatalog`); the last good copy is kept on disk. Brüce only links to each race's own page: it never signs
// anyone up, takes money or reads registration platforms, and race names are plain text (Brüce is not affiliated
// with any organiser). My races stay on the device like custom areas (`MyRaces`); reminders are local
// notifications (`RaceReminders`). Schema: README.md, section "Races".

enum RaceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case running, hyrox, obstacle, endurance, triathlon
    var id: String { rawValue }
    /// Chip and filter title.
    var title: String {
        switch self {
        case .running: "Running"
        case .hyrox: "HYROX"
        case .obstacle: "Obstacle"
        case .endurance: "Ski, bike, swim"
        case .triathlon: "Triathlon"
        }
    }
    /// Short label on cards ("HYROX · Solna"); endurance races use their sport instead.
    var shortTitle: String { self == .endurance ? "Endurance" : title }
    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .hyrox: "figure.highintensity.intervaltraining"
        case .obstacle: "figure.climbing"
        case .endurance: "figure.skiing.crosscountry"
        case .triathlon: "figure.open.water.swim"
        }
    }
}

/// The sport of an endurance race (ski, bike or swim legs such as the Klassiker).
enum RaceSport: String, Codable, CaseIterable, Hashable {
    case ski, bike, swim
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .ski: "figure.skiing.crosscountry"
        case .bike: "figure.outdoor.cycle"
        case .swim: "figure.open.water.swim"
        }
    }
}

/// Sign-up status as shown on the race's own page on `checkedOn`. `checkSite` when it was unclear.
enum RaceStatus: String, Codable, CaseIterable, Hashable {
    case open, opensSoon, soldOut, lottery, checkSite
}

/// One entry fee with the days it applies (both optional and inclusive). `lowest`: other entries cost more
/// ("From 799 SEK"); `per`: what the price is for ("per team").
struct PriceStep: Codable, Hashable {
    var from: String? = nil
    var until: String? = nil
    var amount: Int
    var currency: String
    var lowest: Bool? = nil
    var per: String? = nil

    /// "2,685 SEK", "From 799 SEK", "4,700 NOK per team".
    var priceText: String {
        (lowest == true ? "From " : "") + RaceMoney.text(amount, currency) + (per.map { " per \($0)" } ?? "")
    }
    func applies(on day: String) -> Bool { (from.map { $0 <= day } ?? true) && (until.map { day <= $0 } ?? true) }
}

/// A catalog race (or a race added by hand, see `MyRace.resolved`). Dates are local race days, "2027-05-15".
struct Race: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: RaceType
    var sport: RaceSport? = nil
    var date: String
    var endDate: String? = nil
    var city: String
    var country: String
    var venue: String? = nil
    var distancesKm: [Double] = []
    /// "solo, duo, trio or team", "15-leg relay", "full distance".
    var format: String? = nil
    /// The race's own page (sign-up or the page with the facts).
    var signupUrl: String
    /// A named registration platform ("RaceID", "Haku"); nil when the race runs its own sign-up.
    var platform: String? = nil
    var priceNote: String? = nil
    var priceSteps: [PriceStep]? = nil
    var status: RaceStatus
    /// Sign-up opening day for `opensSoon`.
    var opensOn: String? = nil
    /// A leg of En Svensk Klassiker.
    var klassiker: Bool? = nil
    var resultsUrl: String? = nil
    /// The day the facts were read off the race's own page; empty for a race added by hand.
    var checkedOn: String

    static let customPrefix = "custom-"
    /// Added by hand (My races), not from the catalog.
    var isCustom: Bool { id.hasPrefix(Race.customPrefix) }
    var lastDay: String { endDate ?? date }
    var isMultiDay: Bool { endDate.map { $0 != date } ?? false }
    /// Every day of the event, first to last.
    var days: [String] {
        var out = [date]
        while let last = out.last, last < lastDay, out.count < 14, let next = RaceDay.adding(1, to: last) { out.append(next) }
        return out
    }
    var url: URL? {
        guard let u = URL(string: signupUrl), let s = u.scheme?.lowercased(), s == "https" || s == "http", u.host != nil else { return nil }
        return u
    }
    /// "toughviking.se" (the sign-up link's host without "www.").
    var host: String? {
        guard let h = url?.host?.lowercased() else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
    var symbol: String { sport?.symbol ?? type.symbol }
    /// "HYROX · Solna", "Ski · Klassiker", "Running · Gothenburg".
    var kindLabel: String {
        [sport?.title ?? type.shortTitle, klassiker == true ? "Klassiker" : (city.isEmpty ? nil : city)].compactMap { $0 }.joined(separator: " · ")
    }
    /// "Strawberry Arena | Solna", the city alone, or the venue alone when it names the city ("Sälen to Mora").
    var placeLine: String {
        if let v = venue, !city.isEmpty, v.localizedCaseInsensitiveContains(city) { return v }
        return [venue, city.isEmpty ? nil : city].compactMap { $0 }.joined(separator: " | ")
    }
    /// "8 km", "21.1 km", "42.2 / 21.1 / 5 km"; nil without distances.
    var distanceText: String? {
        guard !distancesKm.isEmpty else { return nil }
        let many = distancesKm.count > 1
        return distancesKm.map { RaceMoney.number($0, decimals: many ? 1 : 3) }.joined(separator: " / ") + " km"
    }
    /// Distances and format: "8 km · solo, duo, trio or team".
    var factsLine: String? {
        let parts = [distanceText, format].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Dates

    /// "Sat 15 May 2027", "Thu 10 – Sun 13 Dec 2026"; `day` narrows a multi-day event to the member's day.
    func dateText(day: String? = nil) -> String {
        let a = day ?? date, b = day ?? lastDay
        if a == b { return RaceDay.format(a, "EEE d MMM yyyy") }
        let sameMonth = a.prefix(7) == b.prefix(7)
        return RaceDay.format(a, sameMonth ? "EEE d" : "EEE d MMM") + " – " + RaceDay.format(b, "EEE d MMM yyyy")
    }
    /// "Saturday 15 May 2027", "Thursday 10 to Sunday 13 December 2026".
    func longDateText(day: String? = nil) -> String {
        let a = day ?? date, b = day ?? lastDay
        if a == b { return RaceDay.format(a, "EEEE d MMMM yyyy") }
        let sameMonth = a.prefix(7) == b.prefix(7)
        return RaceDay.format(a, sameMonth ? "EEEE d" : "EEEE d MMMM") + " to " + RaceDay.format(b, "EEEE d MMMM yyyy")
    }
    /// Days until the (member's) race day: 0 on the day, negative after.
    func daysToGo(day: String? = nil, now: Date = Date()) -> Int? { RaceDay.days(until: day ?? date, now: now) }
    /// The event (or the member's day of it) is over.
    func isPast(day: String? = nil, now: Date = Date()) -> Bool { (RaceDay.days(until: day ?? lastDay, now: now) ?? 0) < 0 }
    /// "206 days to go", "Tomorrow", "Race day", "Done".
    func countdownText(day: String? = nil, now: Date = Date()) -> String {
        guard let a = daysToGo(day: day, now: now) else { return "" }
        if isPast(day: day, now: now) { return "Done" }
        if a <= 0 { return "Race day" }
        return a == 1 ? "Tomorrow" : "\(a) days to go"
    }
    /// "52 days", "Tomorrow", "Race day", "Done" (cards).
    func countdownShort(day: String? = nil, now: Date = Date()) -> String {
        let t = countdownText(day: day, now: now)
        return t.hasSuffix(" to go") ? String(t.dropLast(6)) : t
    }

    // MARK: Prices and status

    var steps: [PriceStep] { (priceSteps ?? []).sorted { ($0.from ?? $0.until ?? "") < ($1.from ?? $1.until ?? "") } }
    /// The entry fee that applies today (the last matching step).
    func currentStep(now: Date = Date()) -> PriceStep? {
        let today = RaceDay.today(now)
        return steps.last { $0.applies(on: today) }
    }
    /// The next known step with a later start day.
    func nextStep(now: Date = Date()) -> PriceStep? {
        let today = RaceDay.today(now)
        return steps.first { ($0.from ?? "") > today }
    }
    /// The day the price changes next: the next step's first day, else the day after the current step's last day.
    func nextPriceChange(now: Date = Date()) -> String? {
        if let n = nextStep(now: now)?.from { return n }
        guard let u = currentStep(now: now)?.until else { return nil }
        return RaceDay.adding(1, to: u)
    }
    /// Days until sign-up opens (0 on the day), for `opensSoon` races.
    func daysToSignup(now: Date = Date()) -> Int? {
        guard status == .opensSoon, let o = opensOn else { return nil }
        return RaceDay.days(until: o, now: now)
    }
    /// Sign-up opens today or on a day still ahead.
    func opensLater(now: Date = Date()) -> Bool { (daysToSignup(now: now) ?? -1) >= 0 }
    /// "1 Nov", or "today" on the opening day.
    func opensText(now: Date = Date(), weekday: Bool = false) -> String {
        guard let o = opensOn else { return "" }
        return daysToSignup(now: now) == 0 ? "today" : RaceDay.format(o, weekday ? "EEE d MMM" : "d MMM")
    }
    /// The race page's status line; nil for races added by hand.
    func statusText(now: Date = Date()) -> String? {
        guard !isCustom, !checkedOn.isEmpty else { return nil }
        switch status {
        case .open: return "Sign-up open"
        case .opensSoon:
            guard let o = opensOn else { return "Sign-up opens soon" }
            return opensLater(now: now) ? "Sign-up opens \(opensText(now: now, weekday: true))" : "Sign-up was due to open on \(RaceDay.format(o, "d MMM")) · check the site"
        case .soldOut: return "Sold out"
        case .lottery: return "Places by lottery"
        case .checkSite: return "Check the race's page for sign-up"
        }
    }
    /// The list pill: the current price ("2,685 SEK until 5 Nov"), else the status ("Sold out", "Opens 1 Nov").
    func pillText(now: Date = Date()) -> String {
        if isCustom { return "" }
        if isPast(now: now) { return "Done" }
        switch status {
        case .soldOut: return "Sold out"
        case .lottery: return "Lottery"
        case .checkSite: return "Check site"
        case .opensSoon: return opensLater(now: now) ? "Opens \(opensText(now: now))" : "Check site"
        case .open:
            guard let s = currentStep(now: now) else { return "Sign-up open" }
            return s.priceText + (s.until.map { " until \(RaceDay.format($0, "d MMM"))" } ?? "")
        }
    }
    /// "checked 21 Oct" (or with the year when it is not this year's).
    func checkedText(now: Date = Date()) -> String? {
        guard !checkedOn.isEmpty else { return nil }
        let sameYear = checkedOn.prefix(4) == RaceDay.today(now).prefix(4)
        return "checked " + RaceDay.format(checkedOn, sameYear ? "d MMM" : "d MMM yyyy")
    }
    /// "Sign-up on RaceID · checked 21 Oct", "Sign-up on vasaloppet.se · checked 21 Oct".
    func signupLine(now: Date = Date()) -> String? {
        guard !isCustom, let where_ = platform ?? host else { return nil }
        return (["Sign-up on \(where_)", checkedText(now: now)].compactMap { $0 }).joined(separator: " · ")
    }
}

extension Race {
    enum CodingKeys: String, CodingKey {
        case id, name, type, sport, date, endDate, city, country, venue, distancesKm, format, signupUrl, platform, priceNote, priceSteps,
             status, opensOn, klassiker, resultsUrl, checkedOn
    }
    /// Required: id, name, type, date, signupUrl, status. Everything else may be missing (distances then empty).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  type: try c.decode(RaceType.self, forKey: .type), sport: try c.decodeIfPresent(RaceSport.self, forKey: .sport),
                  date: try c.decode(String.self, forKey: .date), endDate: try c.decodeIfPresent(String.self, forKey: .endDate),
                  city: try c.decodeIfPresent(String.self, forKey: .city) ?? "", country: try c.decodeIfPresent(String.self, forKey: .country) ?? "",
                  venue: try c.decodeIfPresent(String.self, forKey: .venue),
                  distancesKm: try c.decodeIfPresent([Double].self, forKey: .distancesKm) ?? [],
                  format: try c.decodeIfPresent(String.self, forKey: .format), signupUrl: try c.decode(String.self, forKey: .signupUrl),
                  platform: try c.decodeIfPresent(String.self, forKey: .platform), priceNote: try c.decodeIfPresent(String.self, forKey: .priceNote),
                  priceSteps: try c.decodeIfPresent([PriceStep].self, forKey: .priceSteps), status: try c.decode(RaceStatus.self, forKey: .status),
                  opensOn: try c.decodeIfPresent(String.self, forKey: .opensOn), klassiker: try c.decodeIfPresent(Bool.self, forKey: .klassiker),
                  resultsUrl: try c.decodeIfPresent(String.self, forKey: .resultsUrl),
                  checkedOn: try c.decodeIfPresent(String.self, forKey: .checkedOn) ?? "")
    }

    /// Every date in the entry is a real day (and the event doesn't end before it starts), so the apps can show it.
    var hasReadableDates: Bool {
        func ok(_ d: String?) -> Bool { d.map { RaceDay.date($0) != nil } ?? true }
        return RaceDay.date(date) != nil && ok(endDate) && (endDate ?? date) >= date && ok(opensOn)
            && (checkedOn.isEmpty || ok(checkedOn)) && (priceSteps ?? []).allSatisfy { ok($0.from) && ok($0.until) }
    }
}

/// Local race days ("2027-05-15") in the Bruce time zone (Stockholm; Oslo and Copenhagen share it).
enum RaceDay {
    /// Midnight at the start of the day, or nil for anything but a real calendar date.
    static func date(_ iso: String?) -> Date? {
        guard let iso, iso.count == 10 else { return nil }
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        let c = DateComponents(year: p[0], month: p[1], day: p[2])
        guard let d = BruceDate.calendar.date(from: c) else { return nil }
        let back = BruceDate.calendar.dateComponents([.year, .month, .day], from: d)
        guard back.year == p[0], back.month == p[1], back.day == p[2] else { return nil }
        return d
    }
    static func iso(_ d: Date) -> String {
        let c = BruceDate.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func today(_ now: Date = Date()) -> String { iso(now) }
    static func adding(_ n: Int, to iso: String) -> String? {
        date(iso).flatMap { BruceDate.calendar.date(byAdding: .day, value: n, to: $0) }.map(Self.iso)
    }
    /// Whole days from today to `iso` (0 = today, negative = past).
    static func days(until iso: String, now: Date = Date()) -> Int? {
        guard let d = date(iso) else { return nil }
        return BruceDate.calendar.dateComponents([.day], from: BruceDate.calendar.startOfDay(for: now), to: d).day
    }
    static func format(_ iso: String, _ pattern: String) -> String { BruceDate.format(date(iso), pattern) }
    /// 09:00 on that day: when race reminders fire.
    static func morning(_ iso: String) -> Date? { date(iso).flatMap { BruceDate.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) } }
}

enum RaceMoney {
    /// "2,685 SEK" (thousands with commas, as on the race pages in English).
    static func text(_ amount: Int, _ currency: String) -> String { grouped(amount) + " " + currency.uppercased() }
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }
    /// 42.195 -> "42.195" (or "42.2" with one decimal), 8 -> "8".
    static func number(_ v: Double, decimals: Int) -> String {
        if v == v.rounded(), abs(v) < 1e9 { return String(Int(v)) }
        var s = String(format: "%.\(decimals)f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s
    }
}

enum Races {
    static let countries: [(code: String, name: String)] = [("SE", "Sweden"), ("NO", "Norway"), ("DK", "Denmark")]
    static func countryName(_ code: String) -> String { countries.first { $0.code == code }?.name ?? code }

    struct MonthGroup: Identifiable, Hashable {
        /// "2026-12"
        let key: String
        /// "December 2026"
        let title: String
        let races: [Race]
        var id: String { key }
    }

    static func sorted(_ races: [Race]) -> [Race] { races.sorted { ($0.date, $0.name) < ($1.date, $1.name) } }

    /// Races under month headers, in date order.
    static func byMonth(_ races: [Race]) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        for r in sorted(races) {
            let key = String(r.date.prefix(7))
            if groups.last?.key == key {
                let g = groups.removeLast()
                groups.append(MonthGroup(key: key, title: g.title, races: g.races + [r]))
            } else {
                groups.append(MonthGroup(key: key, title: RaceDay.format(key + "-01", "MMMM yyyy"), races: [r]))
            }
        }
        return groups
    }

    /// Explore › Races: by type and country (empty = all), a search text, and upcoming only unless `includePast`.
    static func filter(_ races: [Race], types: Set<RaceType> = [], countries: Set<String> = [], query: String = "",
                       includePast: Bool = false, now: Date = Date()) -> [Race] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return sorted(races.filter { r in
            (types.isEmpty || types.contains(r.type)) && (countries.isEmpty || countries.contains(r.country))
                && (includePast || !r.isPast(now: now)) && (q.isEmpty || matches(r, q))
        })
    }

    static func matches(_ r: Race, _ folded: String) -> Bool {
        // An endurance race is found by its sport ("ski"), not by the "Ski, bike, swim" chip title.
        let hay = [r.name, r.city, r.venue, countryName(r.country), r.sport?.title ?? r.type.title, r.distanceText, r.format,
                   r.klassiker == true ? "Klassiker" : nil].compactMap { $0 }.map(fold)
        return folded.split(separator: " ").allSatisfy { w in hay.contains { $0.contains(w) } }
    }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// A link typed for a race added by hand: "toughviking.se" -> https://toughviking.se; nil without a host.
    static func webURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let lower = t.lowercased()
        let full = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? t : "https://" + t
        guard let u = URL(string: full), let h = u.host, h.contains("."), !h.hasPrefix("."), !h.hasSuffix(".") else { return nil }
        return u
    }
}

// MARK: - My races (device only)

/// A race the member follows: from the catalog by `raceId`, or added by hand (name, date, city, link, type).
/// Name, dates, city and link are also saved for catalog races, so My races shows them before the catalog loads.
struct MyRace: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Catalog race id; nil for a race added by hand.
    var raceId: String?
    var name: String
    var date: String
    var endDate: String?
    var city: String?
    var url: String?
    var type: RaceType = .running
    /// The member's day of a multi-day event (their HYROX heat), else nil.
    var day: String?
    /// Their start, "Doubles Open" or "10 km".
    var note: String?
    var remindSignup = false
    var remindPrice = false
    var addedAt = Date()

    init(race: Race, day: String? = nil, note: String? = nil, remindSignup: Bool = false, remindPrice: Bool = false) {
        raceId = race.isCustom ? nil : race.id
        name = race.name; date = race.date; endDate = race.endDate; city = race.city; url = race.signupUrl; type = race.type
        self.day = day; self.note = note; self.remindSignup = remindSignup; self.remindPrice = remindPrice
    }
    init(name: String, date: String, city: String? = nil, url: String? = nil, type: RaceType = .running, note: String? = nil) {
        raceId = nil; self.name = name; self.date = date; self.city = city; self.url = url; self.type = type; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, raceId, name, date, endDate, city, url, type, day, note, remindSignup, remindPrice, addedAt }
    /// Missing fields get their defaults, so files written by older and newer versions both load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        raceId = try c.decodeIfPresent(String.self, forKey: .raceId)
        name = try c.decode(String.self, forKey: .name)
        date = try c.decode(String.self, forKey: .date)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        type = (try? c.decodeIfPresent(RaceType.self, forKey: .type)) ?? .running
        day = try c.decodeIfPresent(String.self, forKey: .day)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        remindSignup = try c.decodeIfPresent(Bool.self, forKey: .remindSignup) ?? false
        remindPrice = try c.decodeIfPresent(Bool.self, forKey: .remindPrice) ?? false
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    /// The race page and route key: the catalog id, or "custom-<uuid>".
    var key: String { raceId ?? Race.customPrefix + id.uuidString.lowercased() }

    /// The catalog race (fresh facts) when the catalog has it, else a race built from what was saved.
    func resolved(in catalog: [Race]) -> Race {
        if let raceId, let r = catalog.first(where: { $0.id == raceId }) { return r }
        return Race(id: key, name: name, type: type, date: date, endDate: endDate, city: city ?? "", country: "",
                    signupUrl: url ?? "", status: .checkSite, checkedOn: "")
    }
}

/// A member's race with its resolved facts.
struct MyRaceEntry: Identifiable, Hashable {
    let mine: MyRace
    let race: Race
    var id: UUID { mine.id }
    /// The day the countdown counts to: the member's day of the event, else its first day.
    var day: String { mine.day ?? race.date }
    func daysToGo(now: Date = Date()) -> Int? { RaceDay.days(until: day, now: now) }
    func isPast(now: Date = Date()) -> Bool { race.isPast(day: mine.day, now: now) }
    /// "Sat 12 Dec · Doubles Open".
    var whenLine: String {
        ([RaceDay.format(day, "EEE d MMM")] + [mine.note].compactMap { $0?.isEmpty == false ? $0 : nil }).joined(separator: " · ")
    }
    /// What happens next for this race: "Sign-up opens 1 Nov · reminder on", "775 SEK from 1 Nov", or the status.
    func hint(now: Date = Date()) -> String? {
        let r = race
        if r.isCustom || isPast(now: now) { return nil }
        if r.opensLater(now: now) {
            return "Sign-up opens \(r.opensText(now: now))" + (mine.remindSignup ? " · reminder on" : "")
        }
        if r.status == .open, let n = r.nextStep(now: now), let f = n.from {
            return "\(n.priceText) from \(RaceDay.format(f, "d MMM"))" + (mine.remindPrice ? " · reminder on" : "")
        }
        if r.status == .open, let c = r.currentStep(now: now), let u = c.until {
            return "\(c.priceText) until \(RaceDay.format(u, "d MMM"))" + (mine.remindPrice ? " · reminder on" : "")
        }
        switch r.status {
        case .soldOut: return "Sold out"
        case .lottery: return "Places by lottery"
        default: return nil
        }
    }
}

enum MyRaces {
    static func entries(_ mine: [MyRace], catalog: [Race]) -> [MyRaceEntry] {
        mine.map { MyRaceEntry(mine: $0, race: $0.resolved(in: catalog)) }
    }
    /// Not over yet, soonest first.
    static func upcoming(_ entries: [MyRaceEntry], now: Date = Date()) -> [MyRaceEntry] {
        entries.filter { !$0.isPast(now: now) }.sorted { ($0.day, $0.race.name) < ($1.day, $1.race.name) }
    }
    /// Over, newest first.
    static func past(_ entries: [MyRaceEntry], now: Date = Date()) -> [MyRaceEntry] {
        entries.filter { $0.isPast(now: now) }.sorted { $0.day > $1.day }
    }

    // Persistence: a JSON file in Application Support, like custom areas (LocalAreaStore). Demo mode keeps them in memory.
    static let fileName = "bruce-my-races-v1.json"
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    /// Entries that can't be read are skipped; a file that can't be read at all is moved aside (".unreadable") so the
    /// next save doesn't overwrite it.
    static func load(from url: URL = defaultURL) -> [MyRace] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        if let list = try? JSONDecoder().decode([Lossy<MyRace>].self, from: d) { return list.compactMap(\.value) }
        let aside = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return []
    }
    static func save(_ list: [MyRace], to url: URL = defaultURL) {
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: url, options: .atomic) }
    }
}

// MARK: - Catalog

/// Skips an entry this version can't read (a new race type, say) instead of failing the whole file.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Reads the catalog from GitHub Pages (the same races.json the web app serves) and keeps the last good copy on disk.
enum RaceCatalog {
    static let url = URL(string: "https://djui.github.io/bruce/app/races.json")!
    /// A cached copy younger than this is used without asking again.
    static let refreshAfter: TimeInterval = 6 * 3600

    private struct File: Decodable { let races: [Lossy<Race>] }

    /// The races in a catalog file, by date; entries with an unknown type, status or a bad date are left out.
    static func decode(_ data: Data) throws -> [Race] {
        let f = try JSONDecoder().decode(File.self, from: data)
        return Races.sorted(f.races.compactMap(\.value).filter { $0.hasReadableDates && $0.url != nil })
    }

    static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bruce-races-catalog-v1.json")
    }
    /// The last good copy and when it was fetched.
    static func loadCached(from url: URL = cacheURL) -> (races: [Race], at: Date)? {
        guard let d = try? Data(contentsOf: url), let races = try? decode(d), !races.isEmpty else { return nil }
        let at = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        return (races, at)
    }
    static func saveCache(_ data: Data, to url: URL = cacheURL) { try? data.write(to: url, options: .atomic) }

    /// One GET of the published file. Throws on HTTP errors or a file without readable races.
    static func fetch() async throws -> (races: [Race], data: Data) {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let races = try decode(data)
        guard !races.isEmpty else { throw URLError(.cannotParseResponse) }
        return (races, data)
    }
}

// MARK: - Reminders (local notifications, opt-in per race)

/// "Sign-up opens" (09:00 on the opening day) and "price goes up" (09:00 the day before the next step), per race in
/// My races. They only remind: nothing is signed up or paid for.
enum RaceReminders {
    static let category = "RACE_REMINDER"
    static let idPrefix = "race-reminder-"

    struct Planned: Hashable {
        let id: String
        let raceId: String
        let fire: Date
        let title: String
        let body: String
    }

    /// The reminders the member asked for that are still ahead, soonest first.
    static func plan(_ mine: [MyRace], catalog: [Race], now: Date = Date()) -> [Planned] {
        var out: [Planned] = []
        for m in mine {
            guard m.raceId != nil else { continue }
            let r = m.resolved(in: catalog)
            guard !r.isCustom, !r.isPast(now: now) else { continue }
            let site = r.host ?? "the race's page"
            // Planned until the moment itself, so a sync early on the opening day keeps it.
            if m.remindSignup, r.status == .opensSoon, let o = r.opensOn, let fire = RaceDay.morning(o), fire > now {
                out.append(Planned(id: "\(idPrefix)signup-\(r.id)", raceId: r.id, fire: fire, title: "Sign-up opens today",
                                   body: "\(r.name): sign-up opens today on \(site). Brüce only reminds you; places can go fast."))
            }
            if m.remindPrice, r.status == .open, let change = r.nextPriceChange(now: now),
               let eve = RaceDay.adding(-1, to: change), let fire = RaceDay.morning(eve), fire > now {
                let current = r.currentStep(now: now)
                let next = r.steps.first { $0.from == change }
                let body: String
                if let current, let next {
                    body = "\(r.name): \(current.priceText) until today, \(next.priceText) from tomorrow. Sign up on \(site)."
                } else if let current {
                    body = "\(r.name): today is the last day for \(current.priceText). Sign up on \(site)."
                } else {
                    body = "\(r.name): the entry fee changes tomorrow. Check \(site)."
                }
                out.append(Planned(id: "\(idPrefix)price-\(r.id)", raceId: r.id, fire: fire, title: "Price goes up tomorrow", body: body))
            }
        }
        return out.sorted { $0.fire < $1.fire }
    }

    /// Replaces the pending race reminders with the planned ones (with none asked for it only clears).
    static func sync(_ mine: [MyRace], catalog: [Race], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for p in plan(mine, catalog: catalog, now: now).prefix(20) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["raceId": p.raceId]
            let comps = BruceDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - App state

extension AppModel {
    /// Loads the catalog: demo races in demo mode; else the cached copy at once, then the published file when the copy
    /// is older than `RaceCatalog.refreshAfter` (or `force`). A failed fetch keeps whatever is shown.
    func loadRaces(force: Bool = false) async {
        if AppModel.demo { if races.isEmpty { races = Race.demo }; return }
        if races.isEmpty, let cached = await Task.detached(priority: .userInitiated, operation: { RaceCatalog.loadCached() }).value {
            races = cached.races; racesFetchedAt = cached.at
        }
        if !force, let at = racesFetchedAt, Date().timeIntervalSince(at) < RaceCatalog.refreshAfter { return }
        guard !racesLoading else { return }
        racesLoading = true
        defer { racesLoading = false }
        do {
            let got = try await RaceCatalog.fetch()
            races = got.races; racesFetchedAt = Date(); racesError = nil
            let data = got.data
            Task.detached(priority: .utility) { RaceCatalog.saveCache(data) }
            syncRaceReminders()
        } catch {
            if races.isEmpty { racesError = Copy.racesLoadFailed }
        }
    }

    var myRaceEntries: [MyRaceEntry] { MyRaces.entries(myRaces, catalog: races) }
    var upcomingMyRaces: [MyRaceEntry] { MyRaces.upcoming(myRaceEntries) }
    var pastMyRaces: [MyRaceEntry] { MyRaces.past(myRaceEntries) }
    /// Home's "Next race".
    var nextMyRace: MyRaceEntry? { upcomingMyRaces.first }

    /// A catalog race, or a race added by hand by its "custom-<uuid>" key.
    func race(_ id: String) -> Race? {
        races.first { $0.id == id } ?? myRaces.first { $0.key == id }?.resolved(in: races)
    }
    func myRace(forKey key: String) -> MyRace? { myRaces.first { $0.key == key } }
    func isMyRace(_ key: String) -> Bool { myRace(forKey: key) != nil }

    func addToMyRaces(_ r: Race) {
        guard !isMyRace(r.id) else { return }
        myRaces.append(MyRace(race: r))
        persistMyRaces()
        flash(Copy.raceAdded, icon: "flag.checkered")
    }

    func removeFromMyRaces(_ key: String) {
        guard let i = myRaces.firstIndex(where: { $0.key == key }) else { return }
        let removed = myRaces.remove(at: i)
        // A race added by hand has no page without it; a catalog race's page stays (with Add to My races).
        if removed.raceId == nil { stacks = stacks.mapValues { $0.filter { $0 != .race(key) } } }
        persistMyRaces()
        flash(Copy.raceRemoved, icon: "flag.slash", undo: { [weak self] in
            guard let self, !self.isMyRace(removed.key) else { return }
            self.myRaces.insert(removed, at: min(i, self.myRaces.count)); self.persistMyRaces()
        })
    }

    /// Adds or replaces a member's race (the editor for races added by hand, the day and start on a race page).
    func saveMyRace(_ r: MyRace) {
        if let i = myRaces.firstIndex(where: { $0.id == r.id }) { myRaces[i] = r } else { myRaces.append(r) }
        persistMyRaces()
    }

    /// Turns a reminder on or off; switching one on adds the race to My races and asks for notification permission.
    func setRaceReminder(_ r: Race, signup: Bool? = nil, price: Bool? = nil) {
        var mine = myRace(forKey: r.id) ?? MyRace(race: r)
        let wasMine = isMyRace(r.id)
        if let signup { mine.remindSignup = signup }
        if let price { mine.remindPrice = price }
        saveMyRace(mine)
        if signup == true || price == true {
            if !wasMine { flash(Copy.raceAdded, icon: "flag.checkered") }
            if !AppModel.demo { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
        }
    }

    /// Opens My classes › Races (Home's "My races" button, the race reminder notification).
    func showMyRaces() {
        dismissSheets()
        showRacesInMyClasses = true
        stacks[.myClasses] = []
        tab = .myClasses
    }
    /// Opens Explore › Races.
    func showRaceCatalog() {
        dismissSheets()
        exploreTabRequest = 2
        stacks[.explore] = []
        tab = .explore
    }

    func persistMyRaces() {
        guard !AppModel.demo else { return }
        MyRaces.save(myRaces)
        syncRaceReminders()
    }

    /// Re-plans the race reminders, one sync after the other. Not before the catalog is there: without it no reminder
    /// could be planned, and the sync would clear the pending ones.
    func syncRaceReminders() {
        guard !AppModel.demo, !races.isEmpty else { return }
        let mine = myRaces, catalog = races, previous = raceReminderTask
        raceReminderTask = Task { await previous?.value; await RaceReminders.sync(mine, catalog: catalog) }
    }
}
