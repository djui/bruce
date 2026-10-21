import Foundation

// MARK: - Monthly goals (device only)
//
// "20 gym visits, 2 swims in October". Progress counts the checked-in visits of the current month from the visit
// history the Statistics screen reads (`GET /v52/booking`); booked but not checked in does not count. Goals live on
// the device. With "Reminder when behind" and the auto-book server switched on, the reminding goals are also sent to
// the server (`PUT /me/goals`, server/README.md), which pushes a nudge when a goal falls behind pace.

/// One goal. Category keys as on the server: nil = any visit, "anyClass" = any class (device only),
/// "gym" = drop-in / solo training, else a Bruce category id ("27").
struct MonthlyGoal: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: String?
    var title: String
    var target: Int
    var studioId: Int? = nil
    var studioName: String? = nil
    var remind = false
    /// Made from a race's Train for it plan (its My races key): the target follows the plan each month, and the goal
    /// goes with the plan (RacePlanner.swift).
    var raceKey: String? = nil

    static let key = "monthlyGoals"
    static func load() -> [MonthlyGoal] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MonthlyGoal].self, from: d)) ?? []
    }
    static func save(_ goals: [MonthlyGoal]) {
        if let d = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(d, forKey: key) }
    }

    static let demo: [MonthlyGoal] = [
        MonthlyGoal(category: "gym", title: "Gym visits", target: 20, remind: true),
        MonthlyGoal(category: "27", title: "Swims", target: 2),
    ]
}

/// The "everything counts, deduped" visit rule (CONTRACT.md), applied to checked-in visits: the same class counts
/// once; a drop-in at the same studio on the same local day within 3 hours of a counted class visit there is the same
/// visit; two drop-ins at the same studio on the same day count once.
enum VisitDedupe {
    static func unique(_ visits: [BruceAPI.Visit]) -> [BruceAPI.Visit] {
        let cal = BruceDate.calendar
        let sorted = visits.filter { $0.deleted != true && $0.date != nil }.sorted { $0.date! < $1.date! }
        var classIds = Set<Int>()
        var classTimes: [String: [Date]] = [:]   // "studio|day" -> class starts
        var dropIns = Set<String>()
        var out: [BruceAPI.Visit] = []
        func dayKey(_ v: BruceAPI.Visit) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: v.date!)
            return "\(v.studioRef ?? -1)|\(c.year!)-\(c.month!)-\(c.day!)"
        }
        // Classes first, so a drop-in before the class at the same studio is matched too.
        for v in sorted where !v.isSolo {
            let cid = v.classId ?? v.visitClass?.id
            if let cid, !classIds.insert(cid).inserted { continue }
            classTimes[dayKey(v), default: []].append(v.date!)
            out.append(v)
        }
        for v in sorted where v.isSolo {
            let k = dayKey(v)
            if (classTimes[k] ?? []).contains(where: { abs($0.timeIntervalSince(v.date!)) <= 3 * 3600 }) { continue }
            guard dropIns.insert(k).inserted else { continue }
            out.append(v)
        }
        return out.sorted { $0.date! > $1.date! }
    }
}

enum GoalCategory {
    /// Whether a visit counts for a category key. Classes match by their class categories; a solo visit (drop-in)
    /// matches "gym", and a category by the studio's main category (a swim at a bath house is a drop-in there).
    static func matches(_ v: BruceAPI.Visit, key: String?, mainCategory: (Int) -> Int?) -> Bool {
        switch key {
        case nil: return true
        case "anyClass": return !v.isSolo
        case "gym": return v.isSolo
        case "newStudios": return false   // needs the whole history: Goals.month handles it
        case let k?:
            guard let id = Int(k) else { return false }
            if !v.isSolo { return v.categoryIds.contains(id) }
            return v.studioRef.flatMap(mainCategory) == id
        }
    }

    /// "Gym visits", "Swims", "Yoga classes", "Visits".
    static func title(_ key: String?, categoryTitle: String?) -> String {
        switch key {
        case nil: return "Visits"
        case "anyClass": return "Classes"
        case "gym": return "Gym visits"
        case "newStudios": return "New studios"
        default:
            let t = categoryTitle ?? "Category"
            switch t.lowercased() {
            case "swimming": return "Swims"
            case "running": return "Runs"
            case "climbing": return "Climbs"
            case "gym", "sauna", "spa", "outdoor": return "\(t) visits"
            default: return "\(t) classes"
            }
        }
    }

    /// SF Symbol for a category title.
    static func symbol(_ key: String?, categoryTitle: String?) -> String {
        switch key {
        case nil: return "figure.walk"
        case "anyClass": return "figure.mixed.cardio"
        case "gym": return "dumbbell.fill"
        case "newStudios": return "sparkles"
        default:
            let t = (categoryTitle ?? "").lowercased()
            if t.contains("swim") { return "figure.pool.swim" }
            if t.contains("yoga") || t.contains("meditation") { return "figure.yoga" }
            if t.contains("pilates") || t.contains("reformer") { return "figure.pilates" }
            if t.contains("cycl") { return "figure.indoor.cycle" }
            if t.contains("run") { return "figure.run" }
            if t.contains("climb") { return "figure.climbing" }
            if t.contains("dance") { return "figure.dance" }
            if t.contains("martial") || t.contains("box") { return "figure.boxing" }
            if t.contains("sauna") || t.contains("spa") { return "drop.fill" }
            if t.contains("strength") || t.contains("gym") { return "dumbbell.fill" }
            if t.contains("hyrox") || t.contains("high") || t.contains("crossfit") { return "figure.highintensity.intervaltraining" }
            return "figure.mixed.cardio"
        }
    }

    /// Accent per goal (index into the app's goal palette): 0 = lime (any visit, gym, classes), else a colour.
    static func tone(_ key: String?, categoryTitle: String?) -> Int {
        guard let k = key, k != "gym", k != "anyClass" else { return 0 }
        if k == "newStudios" { return 3 }
        let t = (categoryTitle ?? "").lowercased()
        if t.contains("swim") { return 1 }
        if t.contains("yoga") || t.contains("meditation") || t.contains("pilates") || t.contains("reformer") { return 2 }
        return 3
    }
}

struct GoalProgress: Identifiable, Hashable {
    let goal: MonthlyGoal
    let done: Int
    /// Visits expected by today at an even pace (target * day / days in month).
    let expected: Double
    let lastVisit: BruceAPI.Visit?
    var id: UUID { goal.id }
    var isDone: Bool { done >= goal.target }
    var toGo: Int { max(0, goal.target - done) }
    var fraction: Double { goal.target > 0 ? min(1, Double(done) / Double(goal.target)) : 0 }

    /// "Exactly on pace", "2 ahead of pace", "3 behind pace", "Done".
    var paceText: String {
        if isDone { return "Done" }
        let diff = Double(done) - expected
        if abs(diff) < 0.5 { return "Exactly on pace" }
        let n = Int(abs(diff).rounded())
        return diff > 0 ? "\(n) ahead of pace" : "\(n) behind pace"
    }
    var behind: Bool { !isDone && Double(done) < expected - 0.5 }
}

struct GoalsMonth {
    let month: Date
    let day: Int
    let daysInMonth: Int
    let progress: [GoalProgress]
    var daysLeft: Int { daysInMonth - day }
    var done: Int { progress.map { min($0.done, $0.goal.target) }.reduce(0, +) }
    var target: Int { progress.map(\.goal.target).reduce(0, +) }
    var allDone: Bool { !progress.isEmpty && progress.allSatisfy(\.isDone) }

    /// "On pace" / "Behind" / "Done".
    var status: String {
        if allDone { return "Done" }
        let expected = progress.map { min(Double($0.goal.target), $0.expected) }.reduce(0, +)
        return Double(done) >= expected - 0.5 ? "On pace" : "Behind"
    }
    /// "Day 14 of 31. Keep 1 visit every 1.4 days to hit everything."
    var hint: String {
        let head = "Day \(day) of \(daysInMonth)."
        if allDone { return "\(head) Every goal is done. Anything more is a bonus." }
        let remaining = target - done
        guard daysLeft > 0 else { return "\(head) Last day: \(remaining) to go." }
        if remaining > daysLeft { return "\(head) \(remaining) to go in \(daysLeft) days: some double days needed." }
        let every = Double(daysLeft) / Double(remaining)
        let s = every < 1.05 ? "every day" : "every \(String(format: "%.1f", every).replacingOccurrences(of: ".0", with: "")) days"
        return "\(head) Keep 1 visit \(s) to hit everything."
    }
}

/// One square of the "This month" calendar.
struct GoalCalendarDay: Hashable, Identifiable {
    let day: Int
    /// nil = no visit, 0 = a visit (lime), > 0 = a visit for a coloured goal (GoalCategory.tone).
    let tone: Int?
    let isToday: Bool
    let isFuture: Bool
    var id: Int { day }
}

enum Goals {
    static func month(goals: [MonthlyGoal], visits: [BruceAPI.Visit], now: Date = Date(), mainCategory: (Int) -> Int?) -> GoalsMonth {
        let cal = BruceDate.calendar
        let interval = cal.dateInterval(of: .month, for: now)!
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let day = cal.component(.day, from: now)
        let mine = thisMonth(visits, now: now)
        let progress = goals.map { g -> GoalProgress in
            let hits = g.category == "newStudios" ? newStudioVisits(visits, now: now) : mine.filter { v in
                GoalCategory.matches(v, key: g.category, mainCategory: mainCategory) && (g.studioId == nil || v.studioRef == g.studioId)
            }
            return GoalProgress(goal: g, done: hits.count, expected: Double(g.target) * Double(day) / Double(days), lastVisit: hits.first)
        }
        return GoalsMonth(month: interval.start, day: day, daysInMonth: days, progress: progress)
    }

    /// "Try new studios": this month's first-ever visits at studios never visited before this month, one per studio,
    /// newest first.
    static func newStudioVisits(_ visits: [BruceAPI.Visit], now: Date = Date()) -> [BruceAPI.Visit] {
        let cal = BruceDate.calendar
        guard let monthStart = cal.dateInterval(of: .month, for: now)?.start else { return [] }
        let all = VisitDedupe.unique(visits).filter { v in v.date.map { $0 <= now } ?? false }.sorted { $0.date! < $1.date! }
        var firstAt: [Int: BruceAPI.Visit] = [:]
        for v in all { if let s = v.studioRef, firstAt[s] == nil { firstAt[s] = v } }
        return firstAt.values.filter { $0.date! >= monthStart }.sorted { $0.date! > $1.date! }
    }

    /// This month's counted visits, newest first.
    static func thisMonth(_ visits: [BruceAPI.Visit], now: Date = Date()) -> [BruceAPI.Visit] {
        let cal = BruceDate.calendar
        return VisitDedupe.unique(visits).filter { v in
            guard let d = v.date else { return false }
            return cal.isDate(d, equalTo: now, toGranularity: .month) && d <= now
        }
    }

    /// Weeks in a row (Monday to Sunday) with at least one visit, up to this week (or last week while this week
    /// has none yet).
    static func streakWeeks(_ visits: [BruceAPI.Visit], now: Date = Date()) -> Int {
        let cal = BruceDate.calendar
        let weeks = Set(visits.compactMap { v in v.date.flatMap { cal.dateInterval(of: .weekOfYear, for: $0)?.start } })
        guard var w = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(w) { w = cal.date(byAdding: .weekOfYear, value: -1, to: w)! }
        var n = 0
        while weeks.contains(w) { n += 1; w = cal.date(byAdding: .weekOfYear, value: -1, to: w)! }
        return n
    }

    /// The month's calendar squares: lime for a visit, a goal's colour when a visit counted for a coloured goal.
    static func calendar(goals: [MonthlyGoal], visits: [BruceAPI.Visit], now: Date = Date(),
                         categoryTitle: (String?) -> String?, mainCategory: (Int) -> Int?) -> [GoalCalendarDay] {
        let cal = BruceDate.calendar
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let today = cal.component(.day, from: now)
        var tones: [Int: Int] = [:]
        for v in thisMonth(visits, now: now) {
            guard let d = v.date else { continue }
            let day = cal.component(.day, from: d)
            var tone = 0
            for g in goals {
                let t = GoalCategory.tone(g.category, categoryTitle: categoryTitle(g.category))
                if t > 0, GoalCategory.matches(v, key: g.category, mainCategory: mainCategory) { tone = t; break }
            }
            tones[day] = max(tones[day] ?? 0, tone)
        }
        return (1...days).map { GoalCalendarDay(day: $0, tone: tones[$0], isToday: $0 == today, isFuture: $0 > today) }
    }

    /// Weekday of the 1st (Monday = 0), for the calendar's leading blanks.
    static func leadingBlanks(now: Date = Date()) -> Int {
        let cal = BruceDate.calendar
        guard let first = cal.dateInterval(of: .month, for: now)?.start else { return 0 }
        return (cal.component(.weekday, from: first) + 5) % 7
    }

    struct Suggestion: Hashable, Identifiable {
        let key: String?
        let average: Double
        let target: Int
        var id: String { key ?? "any" }
    }

    /// Goals worth suggesting from the last three full months: gym visits and the user's main categories.
    static func suggestions(visits: [BruceAPI.Visit], existing: [MonthlyGoal], now: Date = Date(), mainCategory: (Int) -> Int?) -> [Suggestion] {
        let cal = BruceDate.calendar
        guard let thisMonth = cal.dateInterval(of: .month, for: now)?.start,
              let from = cal.date(byAdding: .month, value: -3, to: thisMonth) else { return [] }
        let recent = VisitDedupe.unique(visits).filter { ($0.date ?? .distantPast) >= from && ($0.date ?? .distantFuture) < thisMonth }
        guard !recent.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for v in recent {
            if v.isSolo {
                counts["gym", default: 0] += 1
                if let c = v.studioRef.flatMap(mainCategory), c != 1 { counts[String(c), default: 0] += 1 }
            } else {
                for c in Set(v.categoryIds) { counts[String(c), default: 0] += 1 }
            }
        }
        let taken = Set(existing.map { $0.category ?? "any" })
        return counts.filter { !taken.contains($0.key) }
            .map { k, n in
                let avg = Double(n) / 3
                return Suggestion(key: k, average: avg, target: max(1, Int((avg * 1.1).rounded(.up))))
            }
            .filter { $0.average >= 1 }
            .sorted { $0.average > $1.average }
            .prefix(3).map { $0 }
    }
}

// MARK: - App state

extension AppModel {
    /// The main category of a studio (a drop-in's category), from the studio list.
    func mainCategory(ofStudio id: Int) -> Int? {
        let cats = studio(id)?.studioCategories ?? []
        return (cats.first { $0.main == true } ?? cats.min { ($0.order ?? 99) < ($1.order ?? 99) })?.categoryId
    }

    func categoryTitle(forKey key: String?) -> String? {
        guard let k = key, let id = Int(k) else { return nil }
        return categories.first { $0.id == id }?.title
    }

    func goalTitle(_ key: String?) -> String { GoalCategory.title(key, categoryTitle: categoryTitle(forKey: key)) }

    func goalsMonth(now: Date = Date()) -> GoalsMonth {
        Goals.month(goals: goals, visits: visitHistory ?? [], now: now, mainCategory: { self.mainCategory(ofStudio: $0) })
    }

    func saveGoal(_ g: MonthlyGoal) {
        if let i = goals.firstIndex(where: { $0.id == g.id }) { goals[i] = g } else { goals.append(g) }
        goalsChanged()
    }

    func deleteGoal(_ id: UUID) {
        // A goal made from a Train for it plan stays deleted (RacePlanner.swift `refreshPlanGoals`).
        if let g = goals.first(where: { $0.id == id }), let key = g.raceKey, let cat = g.category {
            updatePlan(key) { if !$0.goalsSkip.contains(cat) { $0.goalsSkip.append(cat) } }
        }
        goals.removeAll { $0.id == id }
        goalsChanged()
    }

    func goalsChanged() {
        guard !AppModel.demo else { return }
        MonthlyGoal.save(goals)
        Task { await syncGoalReminders() }
    }

    /// `PUT /me/goals` with the goals that remind (at most 10), only while the auto-book server is switched on.
    /// Cheap and silent: failures are ignored, the device keeps the goals either way.
    func syncGoalReminders() async {
        guard !AppModel.demo, tokenUsable, let s = session, AutoBookServer.isConfigured, AutoBookServer.booksForMe else { return }
        let body: [String: Any] = ["goals": goals.filter(\.remind).prefix(10).map { g -> [String: Any] in
            ["id": g.id.uuidString, "title": g.title, "category": g.category ?? NSNull(), "target": g.target, "remind": true]
        }]
        let signature = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
        guard signature != UserDefaults.standard.string(forKey: "goalReminderSync") else { return }
        if (try? await BruceAPI.send(AutoBookServer.request("PUT", "me/goals", session: s, body: body))) != nil {
            UserDefaults.standard.set(signature, forKey: "goalReminderSync")
        }
    }
}
