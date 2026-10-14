import Foundation

// MARK: - Challenges with friends (our server, server/README.md)
//
// Bruce does not expose friends' past visits, so challenges run on the auto-book server: each participant's row
// there holds their Bruce login, a daily job reads their `GET /v52/booking` history, and the leaderboard comes back
// from `GET /challenges/:id`. Friends in a challenge see each other's visits (totals, class types, studios). Joining
// stores the Bruce login on the server even with "Let the server book for me" switched off; the app says so first.

struct ChallengeParticipant: Codable, Hashable {
    let userId: Int
    var name: String? = nil
    var status: String? = nil
}

struct ChallengePeriod: Codable, Hashable {
    var start: String? = nil
    var end: String? = nil
    var label: String? = nil
    var day: Int? = nil
    var days: Int? = nil
    var daysLeft: Int? = nil
}

/// A challenge as listed (`GET /challenges`), or the preview a non-participant gets for a share link.
struct ChallengeSummary: Codable, Identifiable, Hashable {
    let id: String
    var title: String? = nil
    var metric: String = "classes"
    var target: Int? = nil
    var category: String? = nil
    var categoryTitle: String? = nil
    var start: String? = nil
    var end: String? = nil
    var repeatMonthly: Bool? = nil
    var ownerId: Int? = nil
    var ownerName: String? = nil
    /// "accepted" | "invited"; nil in a preview.
    var myStatus: String? = nil
    var participants: [ChallengeParticipant]? = nil
    var period: ChallengePeriod? = nil
    var shareUrl: String? = nil
    var createdAt: String? = nil
    /// Preview only.
    var participantCount: Int? = nil

    var isInvite: Bool { myStatus == "invited" }
    var accepted: [ChallengeParticipant] { (participants ?? []).filter { $0.status == "accepted" } }
    var displayTitle: String { title?.isEmpty == false ? title! : Challenge.metricTitle(metric, target: target) }
    /// "everything counts" / "Yoga counts".
    var countsLabel: String { category == nil ? "everything counts" : "\(categoryTitle ?? "one category") counts" }
    var link: URL { URL(string: shareUrl ?? "") ?? Challenge.shareURL(id) }
    var startDate: Date? { (period?.start ?? start).flatMap(Challenge.day) }
}

struct ChallengeEntry: Decodable, Hashable, Identifiable {
    struct TopStudio: Decodable, Hashable { var id: Int? = nil; var name: String? = nil; var count: Int? = nil }
    struct TopClass: Decodable, Hashable { var title: String? = nil; var count: Int? = nil }
    struct CategoryCount: Decodable, Hashable { var key: String? = nil; var count: Int? = nil }
    struct Recent: Decodable, Hashable {
        var at: String? = nil
        var kind: String? = nil
        var title: String? = nil
        var studioId: Int? = nil
        var studio: String? = nil
        var date: Date? { at.flatMap(BruceDate.parse) }
    }
    let userId: Int
    var name: String? = nil
    var status: String? = nil
    var rank: Int? = nil
    var score: Int? = nil
    var visits: Int? = nil
    var classes: Int? = nil
    var dropins: Int? = nil
    var minutes: Int? = nil
    var studios: Int? = nil
    var topStudio: TopStudio? = nil
    var topClass: TopClass? = nil
    var categories: [CategoryCount]? = nil
    var together: Int? = nil
    var lastVisit: String? = nil
    var done: Bool? = nil
    var daily: [Int]? = nil
    var recent: [Recent]? = nil
    var id: Int { userId }
    var isInvited: Bool { status == "invited" }
    var lastVisitDate: Date? { lastVisit.flatMap(BruceDate.parse) }
}

struct ChallengeMonth: Decodable, Hashable, Identifiable {
    struct Entry: Decodable, Hashable {
        let userId: Int
        var name: String? = nil
        var score: Int? = nil
        var visits: Int? = nil
        var classes: Int? = nil
        var dropins: Int? = nil
        var minutes: Int? = nil
    }
    let month: String
    var label: String? = nil
    var entries: [Entry] = []
    var id: String { month }
}

struct ChallengeDetail: Decodable, Hashable {
    let challenge: ChallengeSummary
    var leaderboard: [ChallengeEntry]? = nil
    var months: [ChallengeMonth]? = nil
    var updatedAt: String? = nil
    /// Preview of a challenge the caller is not in (share link): whether they may join.
    var joinable: Bool? = nil
    var isPreview: Bool { leaderboard == nil }
}

/// A new challenge from the sheet.
struct ChallengeDraft: Hashable {
    var metric = "classes"
    var target = 12
    /// nil = all categories.
    var category: String?
    var categoryTitle: String?
    var start: Date
    var end: Date
    var repeatMonthly = true
    var invite: [Int] = []

    var title: String { Challenge.metricTitle(metric, target: metric == "target" ? target : nil) }
    var body: [String: Any] {
        var b: [String: Any] = ["title": title, "metric": metric, "start": Challenge.dayString(start), "end": Challenge.dayString(end),
                                "repeatMonthly": repeatMonthly, "invite": invite]
        if metric == "target" { b["target"] = target }
        if let category { b["category"] = category; b["categoryTitle"] = categoryTitle ?? "" }
        return b
    }
}

enum Challenge {
    static func metricTitle(_ metric: String, target: Int?) -> String {
        switch metric {
        case "visits": return "Most visits"
        case "minutes": return "Most minutes"
        case "target": return "Everyone hits \(target ?? 12)"
        default: return "Most classes"
        }
    }
    /// What the score counts ("11 classes in 14 days").
    static func unit(_ metric: String, _ n: Int) -> String {
        switch metric {
        case "minutes": return n == 1 ? "minute" : "minutes"
        case "classes": return n == 1 ? "class" : "classes"
        default: return n == 1 ? "visit" : "visits"
        }
    }
    static func shareURL(_ id: String) -> URL { URL(string: "https://djui.github.io/bruce/app/#challenge/\(id)")! }

    /// "2026-10-01" (Stockholm day).
    static func day(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return BruceDate.calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    static func dayString(_ d: Date) -> String { BruceDate.format(d, "yyyy-MM-dd") }

    /// Server errors are `{ "error": "<message>" }`.
    static func message(_ error: Error) -> String {
        if case BruceAPI.APIError.http(let code, let data) = error {
            struct E: Decodable { let error: String? }
            if let e = try? JSONDecoder().decode(E.self, from: data), let m = e.error, !m.isEmpty { return m }
            return "Server error (HTTP \(code))"
        }
        if (error as? URLError) != nil { return "Our server can't be reached right now." }
        return error.localizedDescription
    }
}

/// Challenge endpoints on the auto-book server (same auth as auto-book).
enum ChallengeServer {
    static func list(session: Session) async throws -> (challenges: [ChallengeSummary], usesBruce: [Int]) {
        struct R: Decodable { let challenges: [ChallengeSummary]; let usesBruce: [Int]? }
        let r = try JSONDecoder().decode(R.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "challenges", session: session)))
        return (r.challenges, r.usesBruce ?? [])
    }
    static func detail(_ id: String, session: Session) async throws -> ChallengeDetail {
        try JSONDecoder().decode(ChallengeDetail.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "challenges/\(id)", session: session)))
    }
    static func create(_ d: ChallengeDraft, session: Session) async throws -> ChallengeSummary {
        struct R: Decodable { let challenge: ChallengeSummary }
        return try JSONDecoder().decode(R.self, from: try await BruceAPI.send(AutoBookServer.request("POST", "challenges", session: session, body: d.body))).challenge
    }
    /// "accept" (invited), "join" (share link) or "leave".
    static func act(_ action: String, _ id: String, session: Session) async throws {
        try await BruceAPI.send(AutoBookServer.request("POST", "challenges/\(id)/\(action)", session: session, body: [String: Any]()))
    }
}

// MARK: - App state

extension AppModel {
    var pendingChallengeInvites: [ChallengeSummary] { challenges.filter(\.isInvite) }

    /// The caller's name in a leaderboard ("You").
    func isMe(_ id: Int) -> Bool { id == (myUserId ?? -1) }
    /// The logged-in user's id (0 in demo mode).
    var myUserId: Int? { AppModel.demo ? 0 : (userId ?? user?.id) }

    func loadChallenges() async {
        if AppModel.demo { if !challengesLoaded { loadDemoChallenges() }; return }
        guard tokenUsable, let s = session, AutoBookServer.isConfigured else { return }
        do {
            let r = try await ChallengeServer.list(session: s)
            challenges = r.challenges
            usesBruce = Set(r.usesBruce)
            challengesError = nil
        } catch { challengesError = Challenge.message(error) }
        challengesLoaded = true
    }

    func loadChallenge(_ id: String) async {
        if AppModel.demo { if !challengesLoaded { loadDemoChallenges() }; return }
        guard tokenUsable, let s = session else { return }
        do {
            let d = try await ChallengeServer.detail(id, session: s)
            challengeDetails[id] = d
            challengesError = nil
        } catch { challengesError = Challenge.message(error) }
    }

    /// Challenges store the Bruce login on our server. With the auto-book server switched off, explain that once
    /// before the first challenge action, then go ahead.
    func withChallengeServerConsent(_ action: @escaping () async -> Void) {
        let key = "challengeServerConsent"
        if AppModel.demo || AutoBookServer.booksForMe || UserDefaults.standard.bool(forKey: key) { Task { await action() }; return }
        confirm = PendingAction(title: "Challenges use our server", message: ChallengeCopy.serverConsent, button: "Continue") {
            UserDefaults.standard.set(true, forKey: key)
            await action()
        }
    }

    /// `POST /challenges`; returns the new challenge's id.
    func createChallenge(_ d: ChallengeDraft) async -> String? {
        if AppModel.demo {
            let c = demoChallenge(id: "demo\(challenges.count + 1)", title: d.title, metric: d.metric, target: d.metric == "target" ? d.target : nil,
                                  owner: (0, "Demo"), mine: "accepted", people: [(0, "Demo", "accepted")] + d.invite.map { ($0, friendName($0), "invited") })
            challenges.insert(c, at: 0)
            challengeDetails[c.id] = ChallengeDetail(challenge: c, leaderboard: [ChallengeEntry(userId: 0, name: "Demo", status: "accepted", rank: 1, score: 0, daily: [])]
                                                     + d.invite.map { ChallengeEntry(userId: $0, name: friendName($0), status: "invited") }, months: [])
            flash("Demo: challenge started (offline, nothing sent)")
            return c.id
        }
        guard let s = session else { return nil }
        do {
            let c = try await ChallengeServer.create(d, session: s)
            challenges.insert(c, at: 0)
            await loadChallenge(c.id)
            flash("Challenge started")
            return c.id
        } catch { flash(Challenge.message(error)); return nil }
    }

    /// Accept an invite (`accept`) or join from a share link (`join`).
    func joinChallenge(_ id: String, viaLink: Bool = false) async {
        if AppModel.demo {
            if let i = challenges.firstIndex(where: { $0.id == id }) {
                challenges[i].myStatus = "accepted"
                if var d = challengeDetails[id] { d = ChallengeDetail(challenge: challenges[i], leaderboard: d.leaderboard?.map { e in
                    var e = e; if e.userId == 0 { e.status = "accepted" }; return e }, months: d.months); challengeDetails[id] = d }
            }
            flash("Demo: joined (offline, nothing sent)"); return
        }
        guard let s = session else { return }
        do {
            try await ChallengeServer.act(viaLink ? "join" : "accept", id, session: s)
            flash("You're in")
            await loadChallenges()
            await loadChallenge(id)
        } catch { flash(Challenge.message(error)) }
    }

    /// Decline an invite or leave a challenge (`leave`: the server deletes the caller's numbers).
    func leaveChallenge(_ id: String) async {
        if !AppModel.demo {
            guard let s = session else { return }
            do { try await ChallengeServer.act("leave", id, session: s) } catch { flash(Challenge.message(error)); return }
        }
        challenges.removeAll { $0.id == id }
        challengeDetails[id] = nil
        for t in Tab.allCases { stacks[t]?.removeAll { $0 == .challenge(id) } }
    }

    func friendName(_ userId: Int) -> String {
        friends.first { $0.friendUser?.id == userId }?.friendUser?.firstName ?? "Friend"
    }

    // MARK: Demo (offline): a running "Most classes" challenge and an invite

    func loadDemoChallenges() {
        challengesLoaded = true
        usesBruce = [7, 11, 12]
        let a = demoChallenge(id: "demoOct", title: "Most classes", metric: "classes", target: nil, owner: (7, "Robin"), mine: "accepted",
                              people: [(7, "Robin", "accepted"), (0, "Demo", "accepted"), (12, "Sam", "accepted"), (11, "Alex", "accepted")])
        let b = demoChallenge(id: "demoHits", title: "Everyone hits 12", metric: "target", target: 12, owner: (12, "Sam"), mine: "invited",
                              people: [(12, "Sam", "accepted"), (11, "Alex", "accepted"), (0, "Demo", "invited")])
        challenges = [b, a]
        let day = a.period?.day ?? 14
        func daily(_ pattern: [Int]) -> [Int] { (0..<day).map { pattern[$0 % pattern.count] } }
        let iso = ISO8601DateFormatter()
        func ago(_ days: Double) -> String { iso.string(from: Date().addingTimeInterval(-days * 86_400)) }
        func recent(_ items: [(Double, String?, Int)]) -> [ChallengeEntry.Recent] {
            items.map { ChallengeEntry.Recent(at: ago($0.0), kind: $0.1 == nil ? "dropin" : "class", title: $0.1, studioId: $0.2) }
        }
        challengeDetails[a.id] = ChallengeDetail(challenge: a, leaderboard: [
            ChallengeEntry(userId: 7, name: "Robin", status: "accepted", rank: 1, score: 13, visits: 15, classes: 13, dropins: 2, minutes: 690, studios: 3,
                           topStudio: .init(id: 1724, count: 6), topClass: .init(title: "Reformer", count: 5),
                           categories: [.init(key: "22", count: 5), .init(key: "2", count: 4), .init(key: "gym", count: 2)], together: 8,
                           lastVisit: ago(0.3), daily: daily([1, 1, 0, 1, 2, 1, 0]),
                           recent: recent([(0.3, "Reformer", 1724), (1.3, "Strength Circuit", 12388), (2.4, nil, 1724), (3.3, "Hatha Flow", 1491)])),
            ChallengeEntry(userId: 0, name: "Demo", status: "accepted", rank: 2, score: 11, visits: 14, classes: 11, dropins: 3, minutes: 560, studios: 4,
                           topStudio: .init(id: 1724, count: 7), topClass: .init(title: "Reformer", count: 4),
                           categories: [.init(key: "22", count: 4), .init(key: "2", count: 3)], together: 0,
                           lastVisit: ago(0.2), daily: daily([1, 0, 1, 0, 1, 0, 1, 2, 1, 0, 1, 1, 1, 1]),
                           recent: recent([(0.2, "Hyrox", 12388), (1.2, nil, 1724), (2.2, "Reformer", 1724)])),
            ChallengeEntry(userId: 12, name: "Sam", status: "accepted", rank: 3, score: 9, visits: 9, classes: 9, dropins: 0, minutes: 540, studios: 2,
                           topStudio: .init(id: 1491, count: 6), topClass: .init(title: "Hatha Flow", count: 4),
                           categories: [.init(key: "2", count: 7)], together: 3, lastVisit: ago(1.1), daily: daily([1, 0, 0, 1, 1, 0, 1]),
                           recent: recent([(1.1, "Hatha Flow", 1491), (3.1, "Morning Flow", 1489)])),
            ChallengeEntry(userId: 11, name: "Alex", status: "accepted", rank: 4, score: 6, visits: 7, classes: 6, dropins: 1, minutes: 330, studios: 2,
                           topStudio: .init(id: 1489, count: 4), topClass: .init(title: "High Intensity", count: 3),
                           categories: [.init(key: "12", count: 3)], together: 2, lastVisit: ago(6.2), daily: daily([1, 0, 1, 0, 0, 0, 0]),
                           recent: recent([(6.2, "High Intensity", 1489), (8.2, nil, 9700)])),
        ], months: [
            ChallengeMonth(month: BruceDate.format(Date(), "yyyy-MM"), label: BruceDate.format(Date(), "MMMM yyyy"), entries: [
                .init(userId: 7, name: "Robin", score: 13, visits: 15, classes: 13, dropins: 2, minutes: 690),
                .init(userId: 0, name: "Demo", score: 11, visits: 14, classes: 11, dropins: 3, minutes: 560),
                .init(userId: 12, name: "Sam", score: 9, visits: 9, classes: 9, dropins: 0, minutes: 540),
                .init(userId: 11, name: "Alex", score: 6, visits: 7, classes: 6, dropins: 1, minutes: 330)]),
            ChallengeMonth(month: "prev", label: BruceDate.format(BruceDate.calendar.date(byAdding: .month, value: -1, to: Date()), "MMMM yyyy"), entries: [
                .init(userId: 0, name: "Demo", score: 21, visits: 26, classes: 21, dropins: 5, minutes: 1080),
                .init(userId: 7, name: "Robin", score: 19, visits: 20, classes: 19, dropins: 1, minutes: 990),
                .init(userId: 12, name: "Sam", score: 12, visits: 12, classes: 12, dropins: 0, minutes: 720),
                .init(userId: 11, name: "Alex", score: 10, visits: 12, classes: 10, dropins: 2, minutes: 520)]),
        ], updatedAt: ago(0.4))
        challengeDetails[b.id] = ChallengeDetail(challenge: b, leaderboard: [
            ChallengeEntry(userId: 12, name: "Sam", status: "accepted", rank: 1, score: 9, visits: 9, classes: 9, topClass: .init(title: "Hatha Flow", count: 4), lastVisit: ago(1.1), daily: daily([1, 0, 0, 1])),
            ChallengeEntry(userId: 11, name: "Alex", status: "accepted", rank: 2, score: 6, visits: 7, classes: 6, lastVisit: ago(6.2), daily: daily([1, 0, 0, 0, 1])),
            ChallengeEntry(userId: 0, name: "Demo", status: "invited"),
        ], months: [])
    }

    func demoChallenge(id: String, title: String, metric: String, target: Int?, owner: (Int, String), mine: String,
                       people: [(Int, String, String)]) -> ChallengeSummary {
        let cal = BruceDate.calendar
        let start = cal.dateInterval(of: .month, for: Date())!.start
        let days = cal.range(of: .day, in: .month, for: Date())!.count
        let day = cal.component(.day, from: Date())
        let end = cal.date(byAdding: .day, value: days - 1, to: start)!
        return ChallengeSummary(id: id, title: title, metric: metric, target: target, start: Challenge.dayString(start), end: Challenge.dayString(end),
                                repeatMonthly: true, ownerId: owner.0, ownerName: owner.1, myStatus: mine,
                                participants: people.map { ChallengeParticipant(userId: $0.0, name: $0.1, status: $0.2) },
                                period: ChallengePeriod(start: Challenge.dayString(start), end: Challenge.dayString(end), label: BruceDate.format(start, "MMMM yyyy"),
                                                        day: day, days: days, daysLeft: days - day),
                                shareUrl: Challenge.shareURL(id).absoluteString)
    }
}

enum ChallengeCopy {
    static let privacy = "Friends in this challenge see your visits: totals, class types and studios. Each friend accepts separately. Leave anytime; your numbers are deleted."
    static let serverConsent = "Challenges run on our server (the one that can auto-book for you). Joining stores your Bruce login there so it can read your visits once a day for the leaderboard. Leaving a challenge deletes your numbers."
}
