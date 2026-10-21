import Foundation

// Train for it (race events, phase 2). A race in My races becomes a block of weeks that ends in race week: Base, Build,
// Peak, race week, then one recovery week (a race under six weeks away skips Base). Each week holds a class mix by Bruce
// category for the race type (HYROX: Hyrox, Strength, Running, High-intensity, Mobility; endurance races weight to the
// race's sport). Progress counts this week's check-ins and bookings; open slots get classes near the member from the
// city schedule (the For you scoring, visit limits, tiers and the selected area), to book once or every week.
//
// It is a class mix, not a training programme: the member picks the sessions per week and can change any week, and it
// does not plan long runs, rides or swims. The settings live on the My races entry (`MyRace.plan`), so they stay on the
// device; with reminders on and the server on they go along with `PUT /me/races` (server/README.md). The same logic is
// in docs/app/js/raceplan.js, tested with the same cases.

/// A Bruce class category in a class mix, matched by its id in the Bruce API (the ids of the demo data) and, when the
/// list has no such id or the id now names something else, by title.
enum PlanCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case hyrox, strength, running, highIntensity, crossfit, climbing, outdoor, cycling, swimming, cardio, mobility, yoga, massage, sauna
    var id: String { rawValue }

    /// The category id in the Bruce API (`GET /v52/category`, as in Demo.swift).
    var categoryId: Int {
        switch self {
        case .hyrox: 13
        case .strength: 26
        case .running: 23
        case .highIntensity: 12
        case .crossfit: 8
        case .climbing: 7
        case .outdoor: 18
        case .cycling: 9
        case .swimming: 27
        case .cardio: 6
        case .mobility: 16
        case .yoga: 2
        case .massage: 15
        case .sauna: 24
        }
    }
    var title: String {
        switch self {
        case .hyrox: "Hyrox"
        case .strength: "Strength"
        case .running: "Running"
        case .highIntensity: "High-intensity"
        case .crossfit: "CrossFit"
        case .climbing: "Climbing"
        case .outdoor: "Outdoor"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .cardio: "Cardio"
        case .mobility: "Mobility"
        case .yoga: "Yoga"
        case .massage: "Massage & Naprapathy"
        case .sauna: "Sauna"
        }
    }
    /// Grid rows and chips.
    var short: String {
        switch self {
        case .highIntensity: "HIIT"
        case .massage: "Massage"
        default: title
        }
    }
    /// Lower-case names a category title or a class title uses.
    var names: [String] {
        switch self {
        case .hyrox: ["hyrox"]
        case .strength: ["strength"]
        case .running: ["running", "run"]
        case .highIntensity: ["high-intensity", "high intensity", "hiit"]
        case .crossfit: ["crossfit"]
        case .climbing: ["climbing", "bouldering"]
        case .outdoor: ["outdoor"]
        case .cycling: ["cycling", "spinning", "indoor cycling"]
        case .swimming: ["swimming", "swim"]
        case .cardio: ["cardio"]
        case .mobility: ["mobility", "stretch", "stretching"]
        case .yoga: ["yoga"]
        case .massage: ["massage", "naprapathy"]
        case .sauna: ["sauna"]
        }
    }
    var symbol: String {
        switch self {
        case .hyrox, .highIntensity, .crossfit: "figure.highintensity.intervaltraining"
        case .strength: "dumbbell.fill"
        case .running: "figure.run"
        case .climbing: "figure.climbing"
        case .outdoor: "tree.fill"
        case .cycling: "figure.indoor.cycle"
        case .swimming: "figure.pool.swim"
        case .cardio: "heart.fill"
        case .mobility: "figure.flexibility"
        case .yoga: "figure.yoga"
        case .massage: "hand.raised.fill"
        case .sauna: "drop.fill"
        }
    }
    /// Hard sessions: weekly series of these are worth pausing for race week.
    var heavy: Bool { [.hyrox, .strength, .highIntensity, .crossfit].contains(self) }

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() }

    /// A category's title or code names this category ("Hyrox", "High-intensity", "Massage & Naprapathy", "HIGH_INTENSITY").
    func names(category text: String?) -> Bool {
        guard let text else { return false }
        let t = PlanCategory.fold(text).replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return names.contains { t == $0 || t.hasPrefix($0 + " ") || t.hasPrefix($0 + "-") }
    }

    /// The id of this category in the live list: the known id when its title still fits (or the list doesn't have it),
    /// else a category with a fitting title or code; nil when the known id now names something else and no title fits.
    func resolve(in categories: [BruceAPI.Category]) -> Int? {
        guard !categories.isEmpty else { return categoryId }
        if let c = categories.first(where: { $0.id == categoryId }), names(category: c.title) || names(category: c.code) { return c.id }
        if let c = categories.first(where: { names(category: $0.title) || names(category: $0.code) }) { return c.id }
        return categories.contains { $0.id == categoryId } ? nil : categoryId
    }

    /// The category a class title points to ("Hyrox Prep", "Strength Circuit", "Run Club"), for weekly rules whose
    /// class is not loaded.
    static func guess(title: String) -> PlanCategory? {
        let full = fold(title)
        let words = full.split { !$0.isLetter && $0 != "-" }.map(String.init)
        return allCases.first { c in c.names.contains { n in n.contains(" ") ? full.contains(n) : words.contains(n) } }
    }
}

/// The phases of a block.
enum PlanPhase: String, Codable, CaseIterable, Hashable {
    case base, build, peak, race, recovery
    var title: String {
        switch self {
        case .base: "Base"
        case .build: "Build"
        case .peak: "Peak"
        case .race: "Race week"
        case .recovery: "Recovery"
        }
    }
    /// The phase strip ("Base Build Peak Race").
    var short: String { self == .race ? "Race" : self == .recovery ? "Recover" : title }
}

/// The class mix for a race type: per phase, categories in priority order. A week with n sessions takes the first n
/// (round again past the end); race week and the recovery week are fixed.
struct PlanTemplate: Hashable {
    let base: [PlanCategory]
    let build: [PlanCategory]
    let peak: [PlanCategory]
    let raceWeek: [PlanCategory]
    let recovery: [PlanCategory]

    func list(_ p: PlanPhase) -> [PlanCategory] {
        switch p {
        case .base: base
        case .build: build
        case .peak: peak
        case .race: raceWeek
        case .recovery: recovery
        }
    }
    /// Grid rows: every category of the mix, in order of first use.
    var rows: [PlanCategory] {
        var out: [PlanCategory] = []
        for c in base + build + peak + raceWeek + recovery where !out.contains(c) { out.append(c) }
        return out
    }
    /// Sessions per category in a week of `phase` with `perWeek` sessions.
    func counts(_ phase: PlanPhase, perWeek: Int) -> [PlanCategory: Int] {
        let l = list(phase)
        guard !l.isEmpty else { return [:] }
        let n = phase == .race || phase == .recovery ? l.count : max(0, perWeek)
        var out: [PlanCategory: Int] = [:]
        for i in 0..<n { out[l[i % l.count], default: 0] += 1 }
        return out
    }

    /// The report's table "Train for it": a race type to Bruce categories. Endurance races weight to their sport.
    static func forRace(_ type: RaceType, sport: RaceSport? = nil) -> PlanTemplate {
        switch type {
        case .hyrox:
            // Typical build week: 2 Hyrox, 1 Strength, 1 Running, 1 High-intensity or Mobility. Race week: a light Hyrox, Mobility.
            return PlanTemplate(base: [.hyrox, .strength, .running, .mobility, .strength, .highIntensity],
                                build: [.hyrox, .strength, .running, .hyrox, .highIntensity, .mobility],
                                peak: [.hyrox, .hyrox, .running, .strength, .highIntensity, .mobility],
                                raceWeek: [.hyrox, .mobility], recovery: [.mobility, .sauna])
        case .running:
            // Around your own long runs: Running, Cycling as easy aerobic, Strength, Mobility. Massage after the race.
            return PlanTemplate(base: [.running, .strength, .cycling, .mobility, .yoga, .strength],
                                build: [.running, .cycling, .strength, .mobility, .running, .yoga],
                                peak: [.running, .running, .strength, .mobility, .cycling, .yoga],
                                raceWeek: [.mobility], recovery: [.massage, .mobility])
        case .obstacle:
            // Strength or CrossFit, Climbing for grip, Running or Outdoor. Race week: easy Climbing, Mobility.
            return PlanTemplate(base: [.strength, .climbing, .running, .crossfit, .mobility, .outdoor],
                                build: [.strength, .crossfit, .climbing, .running, .outdoor, .mobility],
                                peak: [.crossfit, .strength, .climbing, .running, .outdoor, .mobility],
                                raceWeek: [.climbing, .mobility], recovery: [.mobility, .sauna])
        case .triathlon:
            return PlanTemplate(base: [.swimming, .cycling, .running, .strength, .mobility, .swimming],
                                build: [.swimming, .cycling, .running, .strength, .cycling, .mobility],
                                peak: [.swimming, .cycling, .running, .strength, .running, .mobility],
                                raceWeek: [.swimming, .mobility], recovery: [.mobility, .sauna])
        case .endurance:
            switch sport {
            case .bike?:
                return PlanTemplate(base: [.cycling, .strength, .cycling, .mobility, .cardio, .yoga],
                                    build: [.cycling, .cycling, .strength, .cardio, .mobility, .cycling],
                                    peak: [.cycling, .cycling, .strength, .cardio, .mobility, .yoga],
                                    raceWeek: [.cycling, .mobility], recovery: [.mobility, .sauna])
            case .swim?:
                return PlanTemplate(base: [.swimming, .strength, .swimming, .mobility, .cardio, .yoga],
                                    build: [.swimming, .swimming, .strength, .cardio, .mobility, .swimming],
                                    peak: [.swimming, .swimming, .strength, .mobility, .cardio, .yoga],
                                    raceWeek: [.swimming, .mobility], recovery: [.mobility, .sauna])
            case .ski?:
                // No ski classes: Cardio and Strength before Vasaloppet.
                return PlanTemplate(base: [.cardio, .strength, .cycling, .mobility, .cardio, .yoga],
                                    build: [.cardio, .strength, .cardio, .cycling, .mobility, .strength],
                                    peak: [.cardio, .cardio, .strength, .cycling, .mobility, .yoga],
                                    raceWeek: [.cardio, .mobility], recovery: [.mobility, .sauna])
            case nil:
                // An endurance race added by hand has no sport: a mix of the three.
                return PlanTemplate(base: [.cardio, .strength, .cycling, .swimming, .mobility, .yoga],
                                    build: [.cycling, .cardio, .strength, .swimming, .mobility, .cycling],
                                    peak: [.cycling, .swimming, .cardio, .strength, .mobility, .yoga],
                                    raceWeek: [.cardio, .mobility], recovery: [.mobility, .sauna])
            }
        }
    }
}

/// Train for it settings on a My races entry. Decoded leniently, so files from other versions load.
struct RacePlanSettings: Codable, Hashable {
    static let perWeekRange = 2...6
    static let weeksRange = 4...16
    static let defaultWeeks = 10
    static let defaultPerWeek = 4
    static let maxPerCell = 3

    /// The day the member started the plan; the block never starts before its week.
    var startedOn: String
    /// Block length in weeks, race week included (fewer when the race is closer).
    var weeks = RacePlanSettings.defaultWeeks
    /// Sessions in a Base, Build or Peak week.
    var perWeek = RacePlanSettings.defaultPerWeek
    /// The member's own counts for single weeks: "<Monday>|<category>" -> sessions.
    var edits: [String: Int] = [:]
    /// Weekly auto-book rules paused for race week, put back after race day.
    var paused: [AutoBookRule] = []
    /// This month's planned classes are monthly goals (Goals.swift), made and kept in step by `refreshPlanGoals`.
    var goals = false
    /// Goal categories ("13") the member deleted from those goals: not made again.
    var goalsSkip: [String] = []

    init(startedOn: String, weeks: Int = RacePlanSettings.defaultWeeks, perWeek: Int = RacePlanSettings.defaultPerWeek) {
        self.startedOn = startedOn; self.weeks = weeks; self.perWeek = perWeek
    }

    enum CodingKeys: String, CodingKey { case startedOn, weeks, perWeek, edits, paused, goals, goalsSkip }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedOn = try c.decode(String.self, forKey: .startedOn)
        weeks = (try? c.decodeIfPresent(Int.self, forKey: .weeks)) ?? RacePlanSettings.defaultWeeks
        perWeek = (try? c.decodeIfPresent(Int.self, forKey: .perWeek)) ?? RacePlanSettings.defaultPerWeek
        edits = (try? c.decodeIfPresent([String: Int].self, forKey: .edits)) ?? [:]
        paused = (try? c.decodeIfPresent([AutoBookRule].self, forKey: .paused)) ?? []
        goals = (try? c.decodeIfPresent(Bool.self, forKey: .goals)) ?? false
        goalsSkip = (try? c.decodeIfPresent([String].self, forKey: .goalsSkip)) ?? []
    }

    static func editKey(_ monday: String, _ c: PlanCategory) -> String { "\(monday)|\(c.rawValue)" }
}

/// One week of a plan.
struct PlanWeek: Hashable, Identifiable {
    /// 0-based; the block weeks first, then the recovery week.
    let index: Int
    /// "2026-10-19"
    let monday: String
    let phase: PlanPhase
    /// Sessions per category, with the member's edits.
    let counts: [PlanCategory: Int]
    /// Categories the member changed this week.
    let edited: Set<PlanCategory>
    var id: String { monday }
    var sunday: String { RaceDay.adding(6, to: monday) ?? monday }
    var total: Int { counts.values.reduce(0, +) }
    func count(_ c: PlanCategory) -> Int { counts[c] ?? 0 }
    /// ISO week number (Europe/Stockholm).
    var isoWeek: Int { RacePlanner.isoWeek(monday) }
    /// "W43".
    var label: String { "W\(isoWeek)" }
    /// Monday 00:00 and the next Monday 00:00 in Stockholm.
    var start: Date { RaceDay.date(monday) ?? .distantPast }
    var end: Date { RaceDay.date(RaceDay.adding(7, to: monday) ?? monday) ?? .distantFuture }
    func contains(_ d: Date) -> Bool { d >= start && d < end }
}

/// A plan as it stands for a race day: the weeks with their phases and counts.
struct RacePlan: Hashable {
    let raceDay: String
    let settings: RacePlanSettings
    let template: PlanTemplate
    /// The block (Base ... race week), then the recovery week.
    let weeks: [PlanWeek]

    init?(raceDay: String, type: RaceType, sport: RaceSport? = nil, settings: RacePlanSettings) {
        guard RaceDay.date(raceDay) != nil, RaceDay.date(settings.startedOn) != nil else { return nil }
        self.raceDay = raceDay
        self.settings = settings
        let tpl = PlanTemplate.forRace(type, sport: sport)
        template = tpl
        let raceMonday = RacePlanner.monday(of: raceDay)
        let length = min(max(settings.weeks, 1), RacePlanSettings.weeksRange.upperBound)
        let earliest = RaceDay.adding(-7 * (length - 1), to: raceMonday) ?? raceMonday
        let first = min(max(RacePlanner.monday(of: settings.startedOn), earliest), raceMonday)
        let n = RacePlanner.days(from: first, to: raceMonday) / 7 + 1
        let phases = RacePlanner.phases(blockWeeks: n)
        let perWeek = min(max(settings.perWeek, RacePlanSettings.perWeekRange.lowerBound), RacePlanSettings.perWeekRange.upperBound)
        let rows = tpl.rows
        weeks = phases.enumerated().map { i, p in
            let monday = RaceDay.adding(7 * i, to: first) ?? first
            var counts = tpl.counts(p, perWeek: perWeek)
            var edited = Set<PlanCategory>()
            for c in rows {
                if let v = settings.edits[RacePlanSettings.editKey(monday, c)] {
                    counts[c] = min(max(v, 0), RacePlanSettings.maxPerCell); edited.insert(c)
                }
            }
            return PlanWeek(index: i, monday: monday, phase: p, counts: counts.filter { $0.value > 0 }, edited: edited)
        }
    }

    var rows: [PlanCategory] { template.rows }
    /// Weeks of the block (race week included), not the recovery week: "Week 3 of 10".
    var blockWeeks: Int { weeks.filter { $0.phase != .recovery }.count }
    var raceWeek: PlanWeek? { weeks.first { $0.phase == .race } }
    var firstDay: String { weeks.first?.monday ?? raceDay }
    var lastDay: String { weeks.last?.sunday ?? raceDay }
    func week(containing day: String) -> PlanWeek? { weeks.first { $0.monday <= day && day <= $0.sunday } }
    func week(at d: Date) -> PlanWeek? { week(containing: RaceDay.iso(d)) }

    enum Status: Hashable { case upcoming, active(PlanWeek), done }
    func status(now: Date = Date()) -> Status {
        let today = RaceDay.today(now)
        if today < firstDay { return .upcoming }
        if let w = week(containing: today) { return .active(w) }
        return .done
    }
    /// The plan still has a week to show: not over yet.
    func isRunning(now: Date = Date()) -> Bool { status(now: now) != .done }

    /// "Week 3 of 10 · Base", "Week 10 of 10 · Race week", "Recovery week", "Starts Mon 5 Oct", "Plan done".
    func headline(now: Date = Date()) -> String {
        switch status(now: now) {
        case .upcoming: return "Starts \(RaceDay.format(firstDay, "EEE d MMM"))"
        case .done: return "Plan done"
        case .active(let w):
            if w.phase == .recovery { return "Recovery week" }
            return "Week \(w.index + 1) of \(blockWeeks) · \(w.phase.title)"
        }
    }

    /// The phase strip: each phase of the block with its number of weeks.
    var segments: [(phase: PlanPhase, weeks: Int)] {
        var out: [(phase: PlanPhase, weeks: Int)] = []
        for w in weeks where w.phase != .recovery {
            if out.last?.phase == w.phase { out[out.count - 1].weeks += 1 } else { out.append((w.phase, 1)) }
        }
        return out
    }

    /// Sessions per category in a month (a week counts for the month its Thursday is in, as ISO weeks do).
    func monthTargets(month: Date) -> [(category: PlanCategory, count: Int)] {
        let cal = BruceDate.calendar
        var sums: [PlanCategory: Int] = [:]
        for w in weeks {
            guard let thu = RaceDay.adding(3, to: w.monday).flatMap(RaceDay.date), cal.isDate(thu, equalTo: month, toGranularity: .month) else { continue }
            for (c, n) in w.counts { sums[c, default: 0] += n }
        }
        return rows.compactMap { c in sums[c].flatMap { $0 > 0 ? (c, $0) : nil } }
    }
}

// MARK: - Progress and suggestions

/// What fills a slot: a check-in, a booking, or the class a weekly auto-book rule books this week.
struct PlanItem: Hashable {
    enum Kind: Int, Hashable { case done, booked, autoBook }
    let kind: Kind
    let classId: Int?
    let title: String
    let studioId: Int?
    let start: Date
    let categories: Set<PlanCategory>
}

/// A class picked for an open slot.
struct PlanSuggestion: Hashable, Identifiable {
    let category: PlanCategory
    let c: BruceAPI.BruceClass
    /// The For you reasons ("12 min from home").
    let reasons: [RecReason]
    /// Booked now, cancelling would already cost a strike (the free cancellation has passed).
    let strike: Bool
    /// Booking opens later; nil when it is open.
    let opens: Date?
    var id: Int { c.id }
    var fewSpots: Int? { c.availableSpots.flatMap { (1...9).contains($0) ? $0 : nil } }
}

/// One planned session this week.
struct PlanSlot: Identifiable, Hashable {
    enum State: Hashable { case done, booked, autoBook, suggested, open }
    let category: PlanCategory
    /// 0-based among the slots of its category.
    let n: Int
    var item: PlanItem? = nil
    var suggestion: PlanSuggestion? = nil
    var id: String { "\(category.rawValue)-\(n)" }
    var state: State {
        switch item?.kind {
        case .done?: .done
        case .booked?: .booked
        case .autoBook?: .autoBook
        case nil: suggestion == nil ? .open : .suggested
        }
    }
    var isFilled: Bool { item != nil }
}

/// A week's slots and what filled them.
struct PlanWeekStatus: Hashable {
    let week: PlanWeek
    var slots: [PlanSlot]
    /// Sessions of the mix's categories that found no open slot (a bonus class).
    var extra: [PlanItem]
    var done: Int { slots.filter { $0.state == .done }.count }
    var planned: Int { slots.count }
    /// "2 of 4 this week".
    var progressText: String { "\(done) of \(planned) this week" }
    /// The first open slot with a class to book (Home's "next class to book").
    var nextToBook: PlanSuggestion? { slots.lazy.compactMap { $0.state == .suggested ? $0.suggestion : nil }.first }
}

enum RacePlanner {
    static let isoCalendar: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = BruceDate.tz; return c }()

    /// The Monday of the week that holds `day`.
    static func monday(of day: String) -> String {
        guard let d = RaceDay.date(day) else { return day }
        let wd = BruceDate.calendar.component(.weekday, from: d)   // 1 = Sunday
        return RaceDay.adding(-((wd + 5) % 7), to: day) ?? day
    }
    static func isoWeek(_ day: String) -> Int { RaceDay.date(day).map { isoCalendar.component(.weekOfYear, from: $0) } ?? 0 }
    static func days(from a: String, to b: String) -> Int {
        guard let x = RaceDay.date(a), let y = RaceDay.date(b) else { return 0 }
        return BruceDate.calendar.dateComponents([.day], from: x, to: y).day ?? 0
    }

    /// Phases for a block of `n` weeks (race week included), plus the recovery week. Peak is the last two weeks before
    /// race week, Build about a third of the rest; a block of six weeks or fewer (a race under six weeks away) skips
    /// Base, and very short ones keep what fits: Peak, then Build.
    static func phases(blockWeeks n: Int) -> [PlanPhase] {
        let t = max(0, n - 1)
        let peak = t >= 4 ? 2 : min(t, 1)
        let build: Int, base: Int
        if n <= 6 { build = t - peak; base = 0 }
        else { build = max(2, Int((Double(t) / 3).rounded())); base = t - peak - build }
        return Array(repeating: .base, count: base) + Array(repeating: .build, count: build) + Array(repeating: .peak, count: peak) + [.race, .recovery]
    }

    /// "1 Hyrox and 1 Mobility", "2 Hyrox, 1 Strength and 1 Running".
    static func mixText(_ w: PlanWeek, rows: [PlanCategory]) -> String {
        let parts = rows.compactMap { c in w.count(c) > 0 ? "\(w.count(c)) \(c.short)" : nil }
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    /// Fills the week's slots: check-ins first, then bookings, then the classes weekly rules will book, oldest first.
    /// Each item takes a slot of one of its categories, the one with the most open slots left.
    static func assign(week: PlanWeek, rows: [PlanCategory], items: [PlanItem]) -> PlanWeekStatus {
        var slots = rows.flatMap { c in (0..<week.count(c)).map { PlanSlot(category: c, n: $0) } }
        var extra: [PlanItem] = []
        // Visits outside the mix (a gym drop-in, a sauna in a HYROX plan) don't fill anything and aren't listed.
        for item in items.sorted(by: { ($0.kind.rawValue, $0.start) < ($1.kind.rawValue, $1.start) }) where !item.categories.isDisjoint(with: rows) {
            var best: (cat: PlanCategory, open: Int, order: Int)?
            for (order, c) in rows.enumerated() where item.categories.contains(c) {
                let open = slots.filter { $0.category == c && $0.item == nil }.count
                if open > 0, best == nil || open > best!.open { best = (c, open, order) }
            }
            if let b = best, let i = slots.firstIndex(where: { $0.category == b.cat && $0.item == nil }) { slots[i].item = item }
            else { extra.append(item) }
        }
        return PlanWeekStatus(week: week, slots: slots, extra: extra)
    }

    /// A plan whose goals are on: its race key, this month's targets and the categories the member deleted.
    struct GoalPlan {
        let key: String
        let targets: [(category: PlanCategory, count: Int)]
        var skip: [String] = []
    }

    /// The monthly goals with those of plans in step: per plan this month's four biggest categories (goal keys are
    /// category ids, "13"), not those the member deleted or already has a goal for (their own, or an earlier race's);
    /// goals of plans not listed go.
    static func planGoals(_ goals: [MonthlyGoal], plans: [GoalPlan], ids: [PlanCategory: Int], title: (String) -> String) -> [MonthlyGoal] {
        var next = goals.filter { g in g.raceKey.map { k in plans.contains { $0.key == k } } ?? true }
        for p in plans {
            var keep = Set<String>()
            for t in p.targets.sorted(by: { $0.count > $1.count }).prefix(4) {
                guard t.count > 0, let id = ids[t.category] else { continue }
                let k = String(id)
                if p.skip.contains(k) || next.contains(where: { $0.category == k && $0.raceKey != p.key && $0.studioId == nil }) { continue }
                keep.insert(k)
                if let i = next.firstIndex(where: { $0.raceKey == p.key && $0.category == k }) { next[i].target = t.count }
                else { next.append(MonthlyGoal(category: k, title: title(k), target: t.count, remind: true, raceKey: p.key)) }
            }
            next.removeAll { $0.raceKey == p.key && !keep.contains($0.category ?? "") }
        }
        return next
    }

    /// What the suggestions need from the app.
    struct SuggestInput {
        var now = Date()
        /// No class before this (now), and none from this moment (the end of the week, or race day).
        var notAfter: Date
        var notBefore: Date? = nil
        /// Every known class, studio points, history and places: the For you input.
        var rec: RecInput
        var categoryIds: [PlanCategory: Int]
        /// Visit limits, tier access and the selected area.
        var allowed: (BruceAPI.BruceClass) -> Bool = { _ in true }
        /// Days ("2026-10-22") with a session already.
        var busyDays: Set<String> = []
    }

    /// A class for each open slot: the best match of its category this week by the For you scoring, one per class,
    /// preferring days without another session and classes still free to cancel.
    static func suggest(_ status: PlanWeekStatus, input: SuggestInput) -> PlanWeekStatus {
        var out = status
        var busy = input.busyDays
        var used = Set(status.slots.compactMap { $0.item?.classId })
        let earliest = max(input.now, input.notBefore ?? input.now)
        let horizon = input.notAfter.timeIntervalSince(input.now)
        guard horizon > 0 else { return out }
        for i in out.slots.indices where out.slots[i].item == nil {
            let cat = out.slots[i].category
            guard let catId = input.categoryIds[cat] else { continue }
            let pool = input.rec.classes.filter { c in
                guard let s = c.start, s >= earliest, s < input.notAfter, !used.contains(c.id) else { return false }
                return (c.classCategories ?? []).contains { $0.categoryId == catId } && input.allowed(c)
            }
            guard !pool.isEmpty else { continue }
            var rec = input.rec
            rec.classes = pool
            rec.now = input.now
            rec.horizon = horizon
            let ranked = Recommender.rank(rec)
            func free(_ r: Recommendation) -> Bool { (BookingRules(r.c)?.cancelStrikes(at: input.now) ?? 0) == 0 }
            func day(_ r: Recommendation) -> String { r.c.start.map(RaceDay.iso) ?? "" }
            guard let pick = ranked.first(where: { free($0) && !busy.contains(day($0)) }) ?? ranked.first(where: free)
                    ?? ranked.first else { continue }
            used.insert(pick.c.id)
            busy.insert(day(pick))
            let opens = pick.c.bookingOpens.flatMap { $0 > input.now ? $0 : nil }
            out.slots[i].suggestion = PlanSuggestion(category: cat, c: pick.c, reasons: pick.reasons,
                                                     strike: !free(pick), opens: opens)
        }
        return out
    }
}

// MARK: - App state

extension AppModel {
    /// Live ids of the plan categories (by id, with the title fallback when the API's list has moved).
    var planCategoryIds: [PlanCategory: Int] {
        Dictionary(PlanCategory.allCases.compactMap { c in c.resolve(in: categories).map { (c, $0) } }, uniquingKeysWith: { a, _ in a })
    }
    func planCategories(of categoryIds: [Int], in map: [PlanCategory: Int]) -> Set<PlanCategory> {
        Set(map.compactMap { categoryIds.contains($0.value) ? $0.key : nil })
    }

    func racePlan(for e: MyRaceEntry) -> RacePlan? {
        e.mine.plan.flatMap { RacePlan(raceDay: e.day, type: e.race.type, sport: e.race.sport, settings: $0) }
    }
    func racePlan(forKey key: String) -> (entry: MyRaceEntry, plan: RacePlan)? {
        guard let e = myRaceEntries.first(where: { $0.mine.key == key }), let p = racePlan(for: e) else { return nil }
        return (e, p)
    }
    /// The soonest race whose plan is still running (My classes › Races "This week", Home).
    var activePlan: (entry: MyRaceEntry, plan: RacePlan)? {
        let running = myRaceEntries.sorted { $0.day < $1.day }.compactMap { e in racePlan(for: e).flatMap { $0.isRunning() ? (e, $0) : nil } }
        // A plan in its block before one in its recovery week.
        return running.first { if case .active(let w) = $0.1.status() { return w.phase != .recovery } else { return true } } ?? running.first
    }

    /// The plan's week now, with its check-ins, bookings, auto-book classes and suggestions. Memoised: rows call it on
    /// every render.
    func planWeekStatus(_ e: MyRaceEntry, _ plan: RacePlan, now: Date = Date()) -> PlanWeekStatus? {
        guard case .active(let week) = plan.status(now: now) else { return nil }
        // Everything the week is computed from; suggestions also move on with the minute (a class soon to start drops out).
        let sig = [e.mine.key, "\(plan.hashValue)", week.monday, "\(Int(now.timeIntervalSince1970 / 60))",
                   "\(classesByDay.values.map(\.count).reduce(0, +))", "\(studioClasses.values.map(\.count).reduce(0, +))", "\(classDetails.count)",
                   "\(bookings.map { "\($0.id)\($0.isCheckedIn ? "c" : "")" }.hashValue)", "\(visitHistory?.count ?? -1)-\(visitHistory?.first?.id ?? 0)",
                   "\(autoBookRules.hashValue)", "\(autoBookUpcoming.map(\.classId).hashValue)", "\(standbys.map(\.id).hashValue)",
                   "\(selectedAreaId?.uuidString ?? "")", "\(studioLimits.count)", "\(categories.count)", "\(recSettings.hashValue)",
                   "\(travelOverrides.count)", "\(friendsBookings.count)"].joined(separator: "|")
        if let c = planWeekCache[e.mine.key], c.sig == sig { return c.value }
        let value = computePlanWeek(e, plan, week: week, now: now)
        planWeekCache[e.mine.key] = (sig, value)
        return value
    }

    private func computePlanWeek(_ e: MyRaceEntry, _ plan: RacePlan, week: PlanWeek, now: Date) -> PlanWeekStatus {
        let ids = planCategoryIds
        let cats = { (list: [Int]) in self.planCategories(of: list, in: ids) }
        var items: [PlanItem] = []
        var seen = Set<Int>()
        // Check-ins (the visit history goals and Statistics count).
        for v in VisitDedupe.unique(visitHistory ?? []) {
            guard let d = v.date, week.contains(d), d <= now else { continue }
            let c = v.isSolo ? cats(v.studioRef.flatMap { mainCategory(ofStudio: $0) }.map { [$0] } ?? []) : cats(v.categoryIds)
            if let cid = v.classId ?? v.visitClass?.id { seen.insert(cid) }
            items.append(PlanItem(kind: .done, classId: v.classId ?? v.visitClass?.id, title: v.title, studioId: v.studioRef, start: d, categories: c))
        }
        // Bookings this week (checked in ones the history doesn't have yet count as done).
        for b in bookings {
            guard let c = b.class, let s = c.start, week.contains(s), !seen.contains(c.id) else { continue }
            seen.insert(c.id)
            let full = findClass(c.id) ?? c
            items.append(PlanItem(kind: b.isCheckedIn ? .done : .booked, classId: c.id, title: c.title, studioId: c.studioId, start: s,
                                  categories: cats((full.classCategories ?? c.classCategories ?? []).compactMap(\.categoryId))))
        }
        // Classes weekly rules book this week (found by the booker, or in the loaded lists).
        var ruleClasses: [BruceAPI.BruceClass] = []
        for o in autoBookUpcoming where week.contains(o.start) && o.start > now && !seen.contains(o.classId) {
            seen.insert(o.classId)
            let c = findClass(o.classId)
            let set = c.map { cats(($0.classCategories ?? []).compactMap(\.categoryId)) } ?? Set([PlanCategory.guess(title: o.title)].compactMap { $0 })
            items.append(PlanItem(kind: .autoBook, classId: o.classId, title: o.title, studioId: o.studioId, start: o.start, categories: set))
        }
        if !autoBookRules.isEmpty {
            ruleClasses = (Array(classesByDay.values.joined()) + Array(studioClasses.values.joined())).filter { c in
                guard let s = c.start, week.contains(s), s > now, !seen.contains(c.id) else { return false }
                return autoBookRules.contains { $0.matches(c) }
            }
            for c in ruleClasses where !seen.contains(c.id) {
                seen.insert(c.id)
                var set = cats((c.classCategories ?? []).compactMap(\.categoryId))
                if set.isEmpty, let g = PlanCategory.guess(title: c.title) { set = [g] }
                items.append(PlanItem(kind: .autoBook, classId: c.id, title: c.title, studioId: c.studioId, start: c.start!, categories: set))
            }
        }
        let status = RacePlanner.assign(week: week, rows: plan.rows, items: items)
        // Suggestions: this week up to its end; in race week only until the day before race day, in the recovery week
        // only after it.
        let raceStart = RaceDay.date(plan.raceDay) ?? week.end
        var notAfter = week.end, notBefore: Date? = nil
        if week.phase == .race { notAfter = min(week.end, raceStart) }
        if week.phase == .recovery { notBefore = BruceDate.calendar.date(byAdding: .day, value: 1, to: raceStart) }
        var rec = recInput(visits: visitHistory ?? [])
        rec.excluded.formUnion(seen)
        let input = RacePlanner.SuggestInput(
            now: now, notAfter: notAfter, notBefore: notBefore, rec: rec, categoryIds: ids,
            allowed: { [self] c in
                if visitLimitReached(c) { return false }
                if case .notIncluded = studioLimitState(c.studioId) { return false }
                if !studioInSelectedArea(c.studioId) { return false }
                if let l = studioLimit(c.studioId), studioVisitsThisMonth(c.studioId) >= l { return false }
                return true
            },
            busyDays: Set(status.slots.compactMap { $0.item.map { RaceDay.iso($0.start) } }))
        return RacePlanner.suggest(status, input: input)
    }

    /// Loads the city schedule for the rest of the plan's week (Explore's day lists), so open slots get suggestions.
    func loadPlanWeekClasses() async {
        guard !AppModel.demo, tokenUsable, let (_, plan) = activePlan, case .active(let week) = plan.status() else { return }
        let cal = BruceDate.calendar
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }.filter { week.contains($0) }
        await loadClassDays(days)
    }

    // MARK: Starting, changing and stopping a plan

    /// "Train for it": adds the race to My races if needed and starts its plan today.
    @discardableResult
    func startPlan(_ r: Race, perWeek: Int = RacePlanSettings.defaultPerWeek, weeks: Int = RacePlanSettings.defaultWeeks) -> String {
        var mine = myRace(forKey: r.id) ?? MyRace(race: r)
        let wasMine = isMyRace(r.id)
        mine.plan = RacePlanSettings(startedOn: RaceDay.today(), weeks: weeks, perWeek: perWeek)
        saveMyRace(mine)
        planWeekCache = [:]
        flash(wasMine ? Copy.planStarted : Copy.planStartedAdded, icon: "figure.run")
        return mine.key
    }

    func updatePlan(_ key: String, _ change: (inout RacePlanSettings) -> Void) {
        guard var mine = myRace(forKey: key), var p = mine.plan else { return }
        change(&p)
        mine.plan = p
        saveMyRace(mine)
        planWeekCache[key] = nil
        if p.goals { refreshPlanGoals() }
    }

    /// Changes one week's count of a category (the grid); back to the mix's own count clears the edit.
    func setPlanCount(_ key: String, week: PlanWeek, category c: PlanCategory, to n: Int, template: PlanTemplate, perWeek: Int) {
        let own = template.counts(week.phase, perWeek: perWeek)[c] ?? 0
        let v = min(max(n, 0), RacePlanSettings.maxPerCell)
        updatePlan(key) { $0.edits[RacePlanSettings.editKey(week.monday, c)] = v == own ? nil : v }
    }

    /// Stops the plan: its settings, its monthly goals and paused rules (put back now) go; the race stays in My races.
    func stopPlan(_ key: String) {
        guard var mine = myRace(forKey: key), let p = mine.plan else { return }
        mine.plan = nil
        saveMyRace(mine)
        planWeekCache[key] = nil
        if !p.paused.isEmpty { restoreAutoBookRules(p.paused) }
        refreshPlanGoals()
        flash(Copy.planStopped, icon: "stop.circle")
    }

    // MARK: Monthly goals from the plan (Goals.swift)

    /// "Make monthly goals": this month's planned sessions per category become monthly goals with "Reminder when
    /// behind" (the server's behind-pace push). A category the member already has a goal for keeps that goal.
    func createPlanGoals(_ key: String, now: Date = Date()) { setPlanGoals(key, true, now: now) }

    /// Monthly goals from the plan on or off (off removes them).
    func setPlanGoals(_ key: String, _ on: Bool, now: Date = Date()) {
        updatePlan(key) { $0.goals = on; $0.goalsSkip = [] }
        refreshPlanGoals(now: now)
        if on { flash(goals.contains { $0.raceKey == key } ? Copy.planGoalsMade : Copy.planGoalsNone, icon: "target") }
    }

    /// Keeps the goals made from plans in step with them (`RacePlanner.planGoals`), and gone when a plan stops or ends.
    func refreshPlanGoals(now: Date = Date()) {
        var wanted: [RacePlanner.GoalPlan] = []
        for e in myRaceEntries.sorted(by: { $0.day < $1.day }) {
            guard let p = e.mine.plan, p.goals, let plan = racePlan(for: e), plan.isRunning(now: now) else { continue }
            wanted.append(.init(key: e.mine.key, targets: plan.monthTargets(month: now), skip: p.goalsSkip))
        }
        guard !wanted.isEmpty || goals.contains(where: { $0.raceKey != nil }) else { return }
        let next = RacePlanner.planGoals(goals, plans: wanted, ids: planCategoryIds, title: { self.goalTitle($0) })
        guard next != goals else { return }
        goals = next
        goalsChanged()
    }

    // MARK: Race week: pause heavy weekly classes

    /// Weekly rules of hard classes (Hyrox, Strength, HIIT, CrossFit) to offer pausing from the week before race week
    /// (their race-week class opens then) until race day.
    func raceWeekRules(_ plan: RacePlan, now: Date = Date()) -> [AutoBookRule] {
        guard let rw = plan.raceWeek else { return [] }
        let today = RaceDay.today(now)
        guard let from = RaceDay.adding(-7, to: rw.monday), today >= from, today <= plan.raceDay else { return [] }
        let ids = planCategoryIds
        let known = Array(classesByDay.values.joined()) + Array(studioClasses.values.joined()) + bookings.compactMap(\.class)
        return autoBookRules.filter { r in
            if let c = known.first(where: { r.matches($0) }) {
                let set = planCategories(of: (c.classCategories ?? []).compactMap(\.categoryId), in: ids)
                if !set.isEmpty { return set.contains { $0.heavy } }
            }
            return PlanCategory.guess(title: r.title)?.heavy == true
        }
    }

    /// Takes a weekly rule out until race day is over; `restorePausedRules` puts it back.
    func pauseForRaceWeek(_ rule: AutoBookRule, key: String) {
        updatePlan(key) { p in if !p.paused.contains(where: { $0.id == rule.id }) { p.paused.append(rule) } }
        removeAutoBook(rule)
        flash(Copy.planPaused(rule.title, rule.label), icon: "pause.circle")
    }

    /// Puts back the rules paused for a race whose race day is over (and those of a plan that was stopped).
    func restorePausedRules(now: Date = Date()) {
        let today = RaceDay.today(now)
        for e in myRaceEntries {
            guard let p = e.mine.plan, !p.paused.isEmpty, e.day < today else { continue }
            restoreAutoBookRules(p.paused)
            updatePlan(e.mine.key) { $0.paused = [] }
            flash(Copy.planRulesBack(p.paused.count), icon: "arrow.clockwise.circle")
        }
    }

    // MARK: Booking from the plan

    /// "Find" on an open slot: Explore › Classes with that category.
    func showPlanCategory(_ c: PlanCategory) {
        dismissSheets()
        if let id = planCategoryIds[c] { exploreCategories = [id] }
        exploreTabRequest = 1
        stacks[.explore] = []
        tab = .explore
    }

    /// Book: the booking rules sheet (it shows what cancelling costs, and books on confirm), as on a class page.
    func bookPlanned(_ s: PlanSuggestion) {
        if classDetails[s.c.id] == nil && findClass(s.c.id) == nil { classDetails[s.c.id] = s.c }
        if sheets.isEmpty { present(.bookingRules(s.c.id)) } else { pushSheet(.bookingRules(s.c.id)) }
    }
}
