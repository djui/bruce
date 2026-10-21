import Foundation

// Milestones (Home card, Statistics) and "New to you" studios (Home), from the visit history and the studio list
// the apps already load. Artwork is SF Symbols in our palette; nothing is fetched for this.

struct Milestone: Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case classes, studios, category, streak }
    let kind: Kind
    let value: Int
    let title: String
    let detail: String
    let symbol: String
    let reachedAt: Date
    /// Stable key, so a milestone is shown once ("classes-50", "category-27", "streak-4-2026-09-28").
    let key: String
    var id: String { key }
    var shareText: String { "\(title) with Bruce Studios. \(detail)" }
}

enum Milestones {
    static let classSteps = [10, 25, 50, 100, 250, 500, 1000]
    static let studioSteps = [5, 10, 25, 50]
    static let streakSteps = [4, 8, 12, 26, 52]
    /// A milestone older than this is not announced on Home any more (it still lists under Statistics).
    static let freshDays = 30

    /// Every milestone reached so far, newest first.
    /// - `visits`: the whole history (any order; deduplicated here, check-ins only count).
    static func reached(visits all: [BruceAPI.Visit], now: Date = Date(),
                        categoryTitle: (Int) -> String? = { _ in nil }, studioName: (Int) -> String? = { _ in nil }) -> [Milestone] {
        let cal = BruceDate.calendar
        let vs = VisitDedupe.unique(all).filter { ($0.date ?? .distantFuture) <= now }.sorted { $0.date! < $1.date! }
        var out: [Milestone] = []
        let f = { (d: Date) in BruceDate.format(d, "EEE d MMM") }

        // Classes: the nth class (solo visits don't count).
        let classes = vs.filter { !$0.isSolo }
        for n in classSteps where classes.count >= n {
            let v = classes[n - 1]
            let studios = Set(classes.prefix(n).compactMap(\.studioRef)).count
            out.append(Milestone(kind: .classes, value: n, title: "\(n) classes",
                                 detail: "Number \(n) was \(v.title) on \(f(v.date!)). \(studios) studio\(studios == 1 ? "" : "s") so far.",
                                 symbol: "figure.run", reachedAt: v.date!, key: "classes-\(n)"))
        }
        // Studios: the nth distinct studio.
        var seen: [Int] = []
        var firstAt: [Int: BruceAPI.Visit] = [:]
        for v in vs { if let s = v.studioRef, !seen.contains(s) { seen.append(s); firstAt[s] = v } }
        for n in studioSteps where seen.count >= n {
            let s = seen[n - 1], v = firstAt[s]!
            let name = studioName(s) ?? v.visitClass?.studio?.name ?? "a new studio"
            out.append(Milestone(kind: .studios, value: n, title: "\(n) studios",
                                 detail: "Your \(ordinal(n)) was \(name) on \(f(v.date!)).", symbol: "building.2", reachedAt: v.date!, key: "studios-\(n)"))
        }
        // A new category: the first class in a category the user never did before (after at least 5 classes).
        var catFirst: [Int: BruceAPI.Visit] = [:]
        var doneBefore = 0
        for v in classes {
            for c in Set(v.categoryIds) where catFirst[c] == nil { catFirst[c] = v }
            doneBefore += 1
            _ = doneBefore
        }
        let firstFive = classes.prefix(5).compactMap(\.date).last ?? .distantPast
        for (c, v) in catFirst where v.date! > firstFive {
            let t = categoryTitle(c) ?? "a new category"
            out.append(Milestone(kind: .category, value: c, title: "New: \(t)",
                                 detail: "Your first \(t) class was \(v.title) on \(f(v.date!)).", symbol: "sparkles", reachedAt: v.date!, key: "category-\(c)"))
        }
        // Weekly streak, counted up to now.
        let streak = Goals.streakWeeks(vs, now: now)
        if let w = cal.dateInterval(of: .weekOfYear, for: now)?.start, streak > 0 {
            let from = cal.date(byAdding: .weekOfYear, value: -(streak - 1), to: vs.last.flatMap { cal.dateInterval(of: .weekOfYear, for: $0.date!)?.start }.map { min($0, w) } ?? w)!
            for n in streakSteps where streak >= n {
                let at = cal.date(byAdding: .weekOfYear, value: n - 1, to: from)!
                out.append(Milestone(kind: .streak, value: n, title: "\(n)-week streak",
                                     detail: "A visit every week since \(BruceDate.format(from, "d MMM")).", symbol: "flame.fill", reachedAt: at,
                                     key: "streak-\(n)-\(BruceDate.format(from, "yyyy-MM-dd"))"))
            }
        }
        return out.sorted { $0.reachedAt > $1.reachedAt }
    }

    /// The newest milestone reached in the last `freshDays` days that was not shown yet.
    static func fresh(_ reached: [Milestone], seen: Set<String>, now: Date = Date()) -> Milestone? {
        reached.first { !seen.contains($0.key) && now.timeIntervalSince($0.reachedAt) < Double(freshDays) * 86400 }
    }

    static func ordinal(_ n: Int) -> String {
        let s = n % 100
        let suffix = (11...13).contains(s) ? "th" : n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th"
        return "\(n)\(suffix)"
    }

    private static let seenKey = "milestonesSeen"
    static var seen: Set<String> {
        get { Set((UserDefaults.standard.array(forKey: seenKey) as? [String]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: seenKey) }
    }
}

// MARK: - New to you

struct NewStudioPick: Hashable, Identifiable {
    let studio: BruceAPI.Studio
    let distance: Double?
    let reason: String
    var id: Int { studio.id }
}

enum NewToYou {
    /// Live studios the user never checked in at, included in the plan (`visit_limit.items` for the tier, as the
    /// Explore access filter reads it), in categories the user does (`VisitProfile.categories`) or near; nearest first.
    static func picks(studios: [BruceAPI.Studio], visited: Set<Int>, profile: VisitProfile, tier: String,
                      distance: (BruceAPI.Studio) -> Double?, categoryTitle: (Int) -> String?, limit: Int = 8) -> [NewStudioPick] {
        let liked = Set(profile.categories.filter { $0.value >= 2 }.map(\.key))
        var out: [(NewStudioPick, Double)] = []
        for s in studios where s.isLive && !visited.contains(s.id) && includedInPlan(s, tier: tier) {
            guard s.hasClasses == true || s.hasOpenings == true else { continue }
            let cats = (s.studioCategories ?? []).compactMap(\.categoryId)
            let shared = cats.first { liked.contains($0) }
            let d = distance(s)
            guard shared != nil || (d ?? .infinity) <= 3000 else { continue }
            let reason = shared.flatMap(categoryTitle).map { "\($0), which you do" } ?? "near you"
            out.append((NewStudioPick(studio: s, distance: d, reason: reason), (shared == nil ? 1.0 : 0.0) * 1e6 + (d ?? 1e5)))
        }
        return out.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    static func includedInPlan(_ s: BruceAPI.Studio, tier: String) -> Bool {
        guard let items = s.visitLimit?.items else { return true }
        guard let mine = items.first(where: { $0.label?.uppercased() == tier.uppercased() }) else { return true }
        return (mine.limit ?? -1) != -1
    }
}
