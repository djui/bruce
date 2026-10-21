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

/// One way to enter a race ("Doubles", "15 km", "Team of 4+"), with its own distance, team size and fees when the
/// race prices them apart. The member picks one in "Your race"; its code is saved with the race in My races.
struct RaceFormat: Codable, Hashable, Identifiable {
    var code: String
    var title: String
    var distanceKm: Double? = nil
    /// People per entry: 1 solo, 2 doubles, 4 a relay; nil when the race doesn't say.
    var teamSize: Int? = nil
    /// Fees for this format, as `Race.priceSteps`; nil when the race's own steps apply.
    var priceSteps: [PriceStep]? = nil
    /// "Open or Pro", "Also as a corporate team".
    var note: String? = nil
    var id: String { code }

    var steps: [PriceStep] { (priceSteps ?? []).sorted { ($0.from ?? $0.until ?? "") < ($1.from ?? $1.until ?? "") } }
    /// "Doubles · 2 people" / "15 km".
    var detail: String? {
        [distanceKm.map { RaceMoney.number($0, decimals: 1) + " km" }, teamSize.flatMap { $0 > 1 ? "\($0) people" : nil }, note].compactMap { $0 }
            .joined(separator: " · ").nilIfEmpty
    }
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
    /// Ways to enter, when the race prices or sizes them apart (HYROX singles, doubles, relay).
    var formats: [RaceFormat]? = nil
    /// The organiser's rule for changes, refunds and transfers, as its page words it.
    var changeRule: String? = nil
    /// How the start works: "Start wave by email a few days before. Be there 90 minutes early."
    var startInfo: String? = nil
    /// How long before the start wave the organiser wants you there (HYROX: 90).
    var arriveMinutesBefore: Int? = nil

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
    /// The race's own results page (https only), linked after the race.
    var results: URL? {
        guard let s = resultsUrl, let u = URL(string: s), u.scheme?.lowercased() == "https", u.host != nil else { return nil }
        return u
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

    // MARK: Formats

    var hasFormats: Bool { !(formats ?? []).isEmpty }
    /// A format by its code; nil for an unknown code (a format the catalog dropped).
    func format(_ code: String?) -> RaceFormat? { code.flatMap { c in formats?.first { $0.code == c } } }
    /// The fees of a format: its own steps, else the race's.
    func steps(for format: RaceFormat?) -> [PriceStep] { format?.priceSteps == nil ? steps : (format?.steps ?? []) }
    /// Today's fee for a format (the race's when the format has none of its own).
    func currentStep(for format: RaceFormat?, now: Date = Date()) -> PriceStep? {
        let today = RaceDay.today(now)
        return steps(for: format).last { $0.applies(on: today) }
    }
    /// "Be there by 12:50" needs the start wave; HYROX wants 90 minutes, others an hour by default.
    var arriveMinutes: Int { arriveMinutesBefore ?? 60 }
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
             status, opensOn, klassiker, resultsUrl, checkedOn, formats, changeRule, startInfo, arriveMinutesBefore
    }
    /// Required: id, name, type, date, signupUrl, status. Everything else may be missing (distances then empty).
    /// Formats this version can't read are dropped one by one, not the race.
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
                  checkedOn: try c.decodeIfPresent(String.self, forKey: .checkedOn) ?? "",
                  formats: (try? c.decodeIfPresent([Lossy<RaceFormat>].self, forKey: .formats))?.compactMap(\.value).filter { !$0.code.isEmpty && !$0.title.isEmpty },
                  changeRule: try? c.decodeIfPresent(String.self, forKey: .changeRule),
                  startInfo: try? c.decodeIfPresent(String.self, forKey: .startInfo),
                  arriveMinutesBefore: (try? c.decodeIfPresent(Int.self, forKey: .arriveMinutesBefore)).flatMap { $0 > 0 ? $0 : nil })
        if formats?.isEmpty == true { formats = nil }
    }

    /// Every date in the entry is a real day (and the event doesn't end before it starts), so the apps can show it.
    var hasReadableDates: Bool {
        func ok(_ d: String?) -> Bool { d.map { RaceDay.date($0) != nil } ?? true }
        return RaceDay.date(date) != nil && ok(endDate) && (endDate ?? date) >= date && ok(opensOn)
            && (checkedOn.isEmpty || ok(checkedOn)) && (priceSteps ?? []).allSatisfy { ok($0.from) && ok($0.until) }
            && (formats ?? []).allSatisfy { $0.steps.allSatisfy { ok($0.from) && ok($0.until) } }
    }
}

/// Start waves and arrival times as "HH:mm" on the race day (local time), typed by the member.
enum RaceClock {
    /// "14:20" (also "14.20", "1420", "9:05") as minutes after midnight; nil when it isn't a time of day.
    static func minutes(_ s: String?) -> Int? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let digits = s.filter(\.isNumber)
        guard digits.count == s.filter { $0 != ":" && $0 != "." && $0 != " " }.count, (3...4).contains(digits.count) else { return nil }
        guard let h = Int(digits.dropLast(2)), let m = Int(digits.suffix(2)), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
    /// "09:05".
    static func text(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
    /// The typed time, tidied ("1420" → "14:20"); nil when it isn't one.
    static func normalized(_ s: String?) -> String? { minutes(s).map(text) }
    /// "12:50": the start wave less the minutes the organiser wants you there before it.
    static func arriveBy(wave: String?, minutesBefore: Int) -> String? {
        guard let w = minutes(wave) else { return nil }
        return text(max(0, w - minutesBefore))
    }
    /// The moment on the race day, for calendar events and workouts; nil without a readable time.
    static func date(_ day: String, _ time: String?) -> Date? {
        guard let m = minutes(time), let d = RaceDay.date(day) else { return nil }
        return BruceDate.calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: d)
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

    /// Home's "Upcoming races": the next catalog races by date that aren't in My races, open or opening (sold-out
    /// and lottery races stay in Explore), at most `limit`. Races in the member's country first when they have one.
    static func upcomingOnHome(_ races: [Race], mine: [MyRace], country: String? = nil, now: Date = Date(), limit: Int = 8) -> [Race] {
        let have = Set(mine.compactMap(\.raceId))
        let list = sorted(races).filter { !$0.isPast(now: now) && !have.contains($0.id) && ($0.status == .open || $0.status == .opensSoon) }
        guard let country, list.contains(where: { $0.country == country }) else { return Array(list.prefix(limit)) }
        return Array((list.filter { $0.country == country } + list.filter { $0.country != country }).prefix(limit))
    }
    /// The carousel pill: the next price step ("750 → 775 SEK on 1 Nov"), else the list pill ("From 1,295 SEK", "Opens 1 Nov").
    static func homePill(_ r: Race, now: Date = Date()) -> String {
        if r.status == .open, let c = r.currentStep(now: now), let n = r.nextStep(now: now), let f = n.from, c.currency == n.currency {
            return "\(RaceMoney.grouped(c.amount)) → \(RaceMoney.grouped(n.amount)) \(n.currency.uppercased()) on \(RaceDay.format(f, "d MMM"))"
        }
        return r.pillText(now: now)
    }

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
    /// An endurance race's sport, saved so Train for it has the right class mix before the catalog loads.
    var sport: RaceSport?
    /// The member's day of a multi-day event (their HYROX heat), else nil.
    var day: String?
    /// Their start, "Doubles Open" or "10 km"; with a catalog format, the rest of it ("Open").
    var note: String?
    /// The catalog format they enter (`Race.formats` code), else nil.
    var format: String?
    /// Their start wave or start time on the race day, "14:20", added by hand when the organiser sends it.
    var wave: String?
    /// Their bib number, as the organiser gives it.
    var bib: String?
    /// "Remind me to add my start wave": a notification three days before race day while `wave` is empty.
    var remindWave = false
    var remindSignup = false
    var remindPrice = false
    /// "Race week" (08:00 on the Monday of race week) and "the day before" (18:00) reminders (RaceReminders).
    var remindWeek = false
    var remindEve = false
    /// Train for it (RacePlanner.swift); nil without a plan.
    var plan: RacePlanSettings?
    /// "Show friends I'm going" (RaceSocial.swift): shared with Bruce friends who share a race too, through our server.
    /// Catalog races only; off by default.
    var going = false
    /// When going was last switched on or off here: the switch flipped last wins on every device (server/README.md).
    var goingAt: Date?
    var addedAt = Date()

    init(race: Race, day: String? = nil, note: String? = nil, remindSignup: Bool = false, remindPrice: Bool = false) {
        raceId = race.isCustom ? nil : race.id
        name = race.name; date = race.date; endDate = race.endDate; city = race.city; url = race.signupUrl; type = race.type; sport = race.sport
        self.day = day; self.note = note; self.remindSignup = remindSignup; self.remindPrice = remindPrice
    }
    init(name: String, date: String, city: String? = nil, url: String? = nil, type: RaceType = .running, note: String? = nil) {
        raceId = nil; self.name = name; self.date = date; self.city = city; self.url = url; self.type = type; self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, raceId, name, date, endDate, city, url, type, sport, day, note, format, wave, bib, remindWave, remindSignup, remindPrice, remindWeek, remindEve,
             plan, going, goingAt, addedAt
    }
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
        sport = try? c.decodeIfPresent(RaceSport.self, forKey: .sport)
        day = try c.decodeIfPresent(String.self, forKey: .day)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        wave = try? c.decodeIfPresent(String.self, forKey: .wave)
        bib = try? c.decodeIfPresent(String.self, forKey: .bib)
        remindWave = (try? c.decodeIfPresent(Bool.self, forKey: .remindWave)) ?? false
        remindSignup = try c.decodeIfPresent(Bool.self, forKey: .remindSignup) ?? false
        remindPrice = try c.decodeIfPresent(Bool.self, forKey: .remindPrice) ?? false
        remindWeek = (try? c.decodeIfPresent(Bool.self, forKey: .remindWeek)) ?? false
        remindEve = (try? c.decodeIfPresent(Bool.self, forKey: .remindEve)) ?? false
        // A plan this version can't read is dropped, not the race.
        plan = try? c.decodeIfPresent(RacePlanSettings.self, forKey: .plan)
        going = (try? c.decodeIfPresent(Bool.self, forKey: .going)) ?? false
        goingAt = try? c.decodeIfPresent(Date.self, forKey: .goingAt)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    /// The race page and route key: the catalog id, or "custom-<uuid>".
    var key: String { raceId ?? Race.customPrefix + id.uuidString.lowercased() }

    /// The catalog race (fresh facts) when the catalog has it, else a race built from what was saved.
    func resolved(in catalog: [Race]) -> Race {
        if let raceId, let r = catalog.first(where: { $0.id == raceId }) { return r }
        return Race(id: key, name: name, type: type, sport: sport, date: date, endDate: endDate, city: city ?? "", country: "",
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
    /// The catalog format the member picked, when the catalog still has it.
    var format: RaceFormat? { race.format(mine.format) }
    /// "Doubles · Open" (format and note), "10 km" (note alone), nil without either.
    var startText: String? {
        [format?.title, mine.note].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ").nilIfEmpty
    }
    /// "Sat 12 Dec · Doubles · Open".
    var whenLine: String {
        ([RaceDay.format(day, "EEE d MMM")] + [startText].compactMap { $0 }).joined(separator: " · ")
    }
    /// The member's start wave, tidied; nil until they add one.
    var wave: String? { RaceClock.normalized(mine.wave) }
    /// "12:50": when the organiser wants them there (the wave less `Race.arriveMinutes`).
    var arriveBy: String? { RaceClock.arriveBy(wave: mine.wave, minutesBefore: race.arriveMinutes) }
    /// Race day is today (the member's day of the event).
    func isRaceDay(now: Date = Date()) -> Bool { daysToGo(now: now) == 0 }
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

/// "Sign-up opens" (09:00 on the opening day) and "price goes up" (09:00 the day before the next step) for catalog races,
/// and for any race "race week" (08:00 on the Monday of race week) and "the day before" (18:00), each opt-in per race in
/// My races. They only remind: nothing is signed up or paid for. While the server has the race-day reminders
/// (`PUT /me/races` answered that it can push), it sends those two by push and email and the device leaves them out.
enum RaceReminders {
    static let category = "RACE_REMINDER"
    static let idPrefix = "race-reminder-"
    /// The races (My races keys) whose race-week and day-before reminders the server pushes: the ones this device sent
    /// in its last `PUT /me/races` that the server can push to (set by `syncRaceServer`).
    static var serverIds: Set<String> {
        guard AutoBookServer.isConfigured, AutoBookServer.booksForMe else { return [] }
        return Set(UserDefaults.standard.stringArray(forKey: "raceServerIds") ?? [])
    }
    /// This device in `PUT /me/races`: each device's My races replace only the races it sent.
    static var deviceId: String {
        if let d = UserDefaults.standard.string(forKey: "raceSyncDevice") { return d }
        let d = UUID().uuidString.lowercased()
        UserDefaults.standard.set(d, forKey: "raceSyncDevice")
        return d
    }
    /// After a new login or with the server off: send again, and remind on the device until then.
    static func forgetServer() {
        UserDefaults.standard.removeObject(forKey: "raceReminderSync")
        UserDefaults.standard.removeObject(forKey: "raceServerIds")
    }

    /// 08:00 on the Monday of race week; nil for a race on a Monday (the evening before covers it).
    static func weekTime(_ day: String) -> Date? {
        let monday = RacePlanner.monday(of: day)
        guard monday != day, let d = RaceDay.date(monday) else { return nil }
        return BruceDate.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: d)
    }
    /// 18:00 the day before race day.
    static func eveTime(_ day: String) -> Date? {
        RaceDay.adding(-1, to: day).flatMap(RaceDay.date).flatMap { BruceDate.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
    }
    /// 18:00 three days before race day: start waves come by email or SMS a few days before (HYROX: about three).
    static func waveTime(_ day: String) -> Date? {
        RaceDay.adding(-3, to: day).flatMap(RaceDay.date).flatMap { BruceDate.calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
    }
    static func waveBody(_ r: Race, day: String) -> String {
        "\(RaceDay.format(day, "EEEE")) is race day. When your start wave or start time arrives, add it in My races: the race-day card then says when to be there."
    }
    /// "Saturday is race day. Your class mix this week: 1 Hyrox and 1 Mobility."
    static func weekBody(_ r: Race, day: String, plan: RacePlan?) -> String {
        var s = "\(RaceDay.format(day, "EEEE")) is race day."
        if let p = plan, let w = p.raceWeek, w.total > 0 { s += " Your class mix this week: \(RacePlanner.mixText(w, rows: p.rows))." }
        return s
    }
    static func eveBody(_ r: Race) -> String {
        guard let h = r.host else { return "Race day tomorrow." }
        return "Race day tomorrow. Start times and what to bring are on \(h)."
    }

    struct Planned: Hashable {
        let id: String
        let raceId: String
        let fire: Date
        let title: String
        let body: String
    }

    /// The reminders the member asked for that are still ahead, soonest first.
    /// `serverIds`: races whose race-week and day-before reminders the server sends instead.
    static func plan(_ mine: [MyRace], catalog: [Race], now: Date = Date(), serverIds: Set<String> = []) -> [Planned] {
        var out: [Planned] = []
        for m in mine {
            let r = m.resolved(in: catalog)
            let day = m.day ?? r.date
            guard !r.isPast(day: m.day, now: now) else { continue }
            let local = !serverIds.contains(m.key)
            if local, m.remindWeek, let fire = weekTime(day), fire > now {
                let plan = m.plan.flatMap { RacePlan(raceDay: day, type: r.type, sport: r.sport, settings: $0) }
                out.append(Planned(id: "\(idPrefix)week-\(m.key)", raceId: m.key, fire: fire, title: "Race week: \(r.name)",
                                   body: weekBody(r, day: day, plan: plan)))
            }
            // A Monday race has no race week before it: either switch is the evening before.
            let eve = m.remindEve || (m.remindWeek && weekTime(day) == nil)
            if local, eve, let fire = eveTime(day), fire > now {
                out.append(Planned(id: "\(idPrefix)eve-\(m.key)", raceId: m.key, fire: fire, title: "Tomorrow: \(r.name)", body: eveBody(r)))
            }
            // Always local: only this device knows whether the wave was added.
            if m.remindWave, RaceClock.minutes(m.wave) == nil, let fire = waveTime(day), fire > now {
                out.append(Planned(id: "\(idPrefix)wave-\(m.key)", raceId: m.key, fire: fire, title: "Add your start wave: \(r.name)", body: waveBody(r, day: day)))
            }
            guard m.raceId != nil, !r.isCustom, !r.isPast(now: now) else { continue }
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
        for p in plan(mine, catalog: catalog, now: now, serverIds: serverIds).prefix(20) {
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
        // Train for it (RacePlanner.swift): rules paused for a race that is over come back; plan goals follow the month.
        restorePausedRules()
        refreshPlanGoals()
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

    /// The country of the member's Bruce city ("SE"), for Home's Upcoming races; Stockholm when the API hasn't said.
    var homeCountry: String? {
        if let c = city?.country?.code?.uppercased(), c.count == 2 { return c }
        return cityId == 1 ? "SE" : nil
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
        var removed = myRaces.remove(at: i)
        // A race added by hand has no page without it; a catalog race's page stays (with Add to My races).
        if removed.raceId == nil { stacks = stacks.mapValues { $0.filter { $0 != .race(key) } } }
        // Its Train for it plan goes too: weekly bookings paused for race week come back, its goals go (Undo brings
        // the plan back, its goals with the next refresh).
        if let p = removed.plan, !p.paused.isEmpty { restoreAutoBookRules(p.paused); removed.plan?.paused = [] }
        planWeekCache[key] = nil
        refreshPlanGoals()
        persistMyRaces()
        flash(Copy.raceRemoved, icon: "flag.slash", undo: { [weak self] in
            guard let self, !self.isMyRace(removed.key) else { return }
            self.myRaces.insert(removed, at: min(i, self.myRaces.count)); self.persistMyRaces(); self.refreshPlanGoals()
        })
    }

    /// Adds or replaces a member's race (the editor for races added by hand, the day and start on a race page).
    func saveMyRace(_ r: MyRace) {
        if let i = myRaces.firstIndex(where: { $0.id == r.id }) { myRaces[i] = r } else { myRaces.append(r) }
        persistMyRaces()
    }
    /// Picks a format on a race page; adds the race to My races when it isn't there yet.
    func setRaceFormat(_ r: Race, code: String?) {
        var mine = myRace(forKey: r.id) ?? MyRace(race: r)
        let wasMine = isMyRace(r.id)
        mine.format = code
        saveMyRace(mine)
        if !wasMine { flash(Copy.raceAdded, icon: "flag.checkered") }
    }
    /// The member's start wave and bib, typed on the race page (empty strings clear them).
    func setRaceStart(_ r: Race, wave: String? = nil, bib: String? = nil, note: String? = nil) {
        guard var mine = myRace(forKey: r.id) else { return }
        if let wave { mine.wave = RaceClock.normalized(wave) ?? wave.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        if let bib { mine.bib = bib.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        if let note { mine.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        guard mine != myRace(forKey: r.id) else { return }
        saveMyRace(mine)
    }

    /// Turns a reminder on or off; switching one on adds the race to My races and asks for notification permission.
    func setRaceReminder(_ r: Race, signup: Bool? = nil, price: Bool? = nil, week: Bool? = nil, eve: Bool? = nil, wave: Bool? = nil) {
        var mine = myRace(forKey: r.id) ?? MyRace(race: r)
        let wasMine = isMyRace(r.id)
        if let signup { mine.remindSignup = signup }
        if let price { mine.remindPrice = price }
        if let week { mine.remindWeek = week }
        if let eve { mine.remindEve = eve }
        if let wave { mine.remindWave = wave }
        saveMyRace(mine)
        if signup == true || price == true || week == true || eve == true || wave == true {
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
        Task { await syncRaceServer() }
    }

    /// The races `PUT /me/races` sends: race-day reminders or going on, and going switched off here (so the server
    /// hears it even without a reminder). Going carries the moment it was flipped.
    static func raceSyncBody(_ upcoming: [MyRaceEntry], plan: (MyRaceEntry) -> RacePlan?) -> [[String: Any]] {
        let switched = { (e: MyRaceEntry) in e.mine.goingAt != nil && e.mine.raceId != nil && !e.race.isCustom }
        let list = upcoming.filter { $0.mine.remindWeek || $0.mine.remindEve || $0.sharesGoing || switched($0) }.prefix(20)
        return list.map { e in
            var o: [String: Any] = ["id": e.mine.key, "name": e.race.name, "date": e.day, "remindWeek": e.mine.remindWeek, "remindEve": e.mine.remindEve]
            if switched(e), let at = e.mine.goingAt { o["going"] = e.mine.going; o["goingAt"] = Int(at.timeIntervalSince1970 * 1000) }
            if let u = e.race.url { o["url"] = u.absoluteString }
            if let p = plan(e) {
                var plan: [String: Any] = ["perWeek": p.settings.perWeek, "weeks": p.blockWeeks, "startedOn": p.settings.startedOn]
                if let w = p.raceWeek {
                    plan["raceWeek"] = p.rows.compactMap { c in w.count(c) > 0 ? ["key": c.rawValue, "title": c.short, "count": w.count(c)] : nil }
                }
                o["plan"] = plan
            }
            return o
        }
    }

    /// `PUT /me/races` with this device's races that have race-week or day-before reminders or are shared as going (at
    /// most 20), only while the server is on: the server sends the reminders by push and email (server/README.md), and
    /// the device leaves out the ones the server confirmed; going races are shown to friends (RaceSocial.swift). Skipped
    /// when nothing changed; failures are silent and the device keeps its notifications.
    func syncRaceServer() async {
        // One after the other: each one reads My races when it runs, so the last change is the one sent last.
        let previous = raceSyncTask
        let t = Task { await previous?.value; await self.sendRaceServer() }
        raceSyncTask = t
        await t.value
    }

    private func sendRaceServer() async {
        guard !AppModel.demo, tokenUsable, let s = session, AutoBookServer.isConfigured, AutoBookServer.booksForMe else { return }
        let races = AppModel.raceSyncBody(upcomingMyRaces) { self.racePlan(for: $0) }
        let body: [String: Any] = ["device": RaceReminders.deviceId, "races": races]
        let signature = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
        let last = UserDefaults.standard.string(forKey: "raceReminderSync")
        guard signature != last, !(last == nil && races.isEmpty) else { return }
        struct R: Decodable { let push: Bool?; let ids: [String]? }
        // A failed PUT keeps the last confirmed races: the others stay local notifications.
        guard let data = try? await BruceAPI.send(AutoBookServer.request("PUT", "me/races", session: s, body: body)) else { return }
        let r = try? JSONDecoder().decode(R.self, from: data)
        UserDefaults.standard.set(signature, forKey: "raceReminderSync")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "raceSyncAt")
        UserDefaults.standard.set(r?.push == true ? (r?.ids ?? []) : [], forKey: "raceServerIds")
        syncRaceReminders()
        // Sharing a race (or not any more) changes what the server shows of friends going.
        await loadRaceGoing(force: true)
    }

    /// Re-plans the race reminders, one sync after the other. Not before the catalog is there: without it no reminder
    /// could be planned, and the sync would clear the pending ones.
    func syncRaceReminders() {
        guard !AppModel.demo, !races.isEmpty else { return }
        let mine = myRaces, catalog = races, previous = raceReminderTask
        raceReminderTask = Task { await previous?.value; await RaceReminders.sync(mine, catalog: catalog) }
    }
}
