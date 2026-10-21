import Foundation

// Friends going, race crews and after the race (phase 3 of the race events; server/README.md "Friends going" and
// "Race crews").
//
// Going is opt-in per race and off by default: "Show friends I'm going" on a race page marks the My races entry, and
// `PUT /me/races` (Races.swift `syncRaceServer`) sends it with `going: true`, which the server stores as the row's
// visibility. `GET /races/going` returns, for a caller who shares a race themselves, the Bruce friends (as Bruce lists
// them for the caller) who marked an upcoming race going: nobody else, so it says nothing about who uses Brüce beyond
// the caller's own friends. Only catalog races can be shared; a race added by hand has no shared record.
//
// A crew is a challenge (Challenges.swift) with a race and a weekly target that ends on race day: same invites, share
// link, accept and leave, and the same "everything counts" visits, counted per week (Monday to Sunday). The server
// tells the crew on Sundays at 19:00 how many hit their sessions (opt-out: Auto-book › Weekly crew update).

/// A friend going to a race, as the server knows them (the name Bruce shows the caller).
struct RaceFriend: Codable, Hashable {
    let userId: Int
    var name: String? = nil
}

/// `GET /races/going`: friends going by race id; `sharing`: the caller shares a race (else nothing is shown).
struct RaceGoing: Codable, Hashable {
    var going: [String: [RaceFriend]] = [:]
    var sharing = false
    /// The races the server has as the caller's going.
    var mine: [String] = []
}

enum RaceGoingServer {
    static func fetch(session: Session) async throws -> RaceGoing {
        try JSONDecoder().decode(RaceGoing.self, from: try await BruceAPI.send(AutoBookServer.request("GET", "races/going", session: session)))
    }
}

/// Words for friends going and crews (the same in the web app's crews.js).
enum RaceSocialText {
    /// "1 friend going", "2 friends going".
    static func going(_ n: Int) -> String { n == 1 ? "1 friend going" : "\(n) friends going" }
    /// "Alex is going", "Alex and Maja are going", "Alex, Maja and Robin are going".
    static func names(_ names: [String]) -> String {
        let list = names.filter { !$0.isEmpty }
        guard let last = list.last else { return "" }
        if list.count == 1 { return "\(last) is going" }
        return list.dropLast().joined(separator: ", ") + " and \(last) are going"
    }
    /// "4 sessions a week".
    static func weekly(_ n: Int) -> String { n == 1 ? "1 session a week" : "\(n) sessions a week" }
    /// "2 of 4 this week", "4 of 4 this week".
    static func thisWeek(_ done: Int, _ weekly: Int) -> String { "\(done) of \(weekly) this week" }
    /// "Last week 4 of 5 hit their sessions"; nil in the crew's first week.
    static func lastWeek(_ c: CrewWeeks) -> String? {
        guard let hit = c.lastWeek?.hit, let size = c.size, size > 0 else { return nil }
        return "Last week \(hit) of \(size) hit their sessions"
    }
    /// "2 of 5 done this week".
    static func doneThisWeek(_ c: CrewWeeks) -> String {
        let w = c.weekly ?? 1
        return "\(c.members.filter { ($0.thisWeek ?? 0) >= w }.count) of \(c.members.count) done this week"
    }
    /// The name a new crew gets: "HYROX Stockholm crew".
    static func crewName(_ r: Race) -> String { "\(r.name) crew" }
}

/// Crews: sessions a week from the Train for it plan.
enum Crew {
    static let weeklyRange = 1...7
    /// The plan's sessions in a Base, Build or Peak week, else 3.
    static func defaultWeekly(_ plan: RacePlanSettings?) -> Int {
        min(max(plan?.perWeek ?? 3, weeklyRange.lowerBound), weeklyRange.upperBound)
    }
}

// MARK: - After the race

/// The easy week after the race: the Train for it recovery week (the week after race week) and its class mix.
struct RaceRecovery: Hashable {
    let monday: String
    let sunday: String
    /// Categories in the mix's order, with their sessions.
    let categories: [PlanCategory]
    let counts: [PlanCategory: Int]
    /// "1 Mobility and 1 Sauna".
    var text: String {
        let parts = categories.compactMap { c in counts[c].map { "\($0) \(c.short)" } }
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

extension MyRaceEntry {
    /// Shared as going: switched on, a catalog race.
    var sharesGoing: Bool { mine.going && mine.raceId != nil && !race.isCustom }

    /// After the race until the end of the week after race week (the plan's recovery week): the recovery mix.
    func recovery(now: Date = Date()) -> RaceRecovery? {
        guard isPast(now: now) else { return nil }
        let raced = mine.day ?? race.lastDay
        guard let monday = RaceDay.adding(7, to: RacePlanner.monday(of: raced)), let sunday = RaceDay.adding(6, to: monday),
              RaceDay.today(now) <= sunday else { return nil }
        let tpl = PlanTemplate.forRace(race.type, sport: race.sport)
        let counts = tpl.counts(.recovery, perWeek: 0)
        var order: [PlanCategory] = []
        for c in tpl.recovery where !order.contains(c) { order.append(c) }
        return RaceRecovery(monday: monday, sunday: sunday, categories: order, counts: counts)
    }
}

// MARK: - App state

extension AppModel {
    /// Going needs our server on (it stores who may see the race) and a login; the demo pretends.
    var canShareGoing: Bool { AppModel.demo || (tokenUsable && AutoBookServer.isConfigured && AutoBookServer.booksForMe) }

    /// Friends going to a race, with their photos from the Friends list when Bruce has them.
    func friendsGoing(_ raceId: String) -> [BruceAPI.UserLite] {
        // With the server switched off nothing is shared any more, so nothing is shown either.
        guard canShareGoing else { return [] }
        return (raceGoing.going[raceId] ?? []).filter { !isMe($0.userId) }.map { f in
            friends.first { $0.friendUser?.id == f.userId }?.friendUser ?? BruceAPI.UserLite(id: f.userId, firstName: f.name, lastName: nil, photo: nil)
        }
    }

    /// `GET /races/going`, at most every 10 minutes unless `force`; a failure keeps what is shown.
    func loadRaceGoing(force: Bool = false) async {
        if AppModel.demo { if raceGoingAt == nil { loadDemoGoing() }; return }
        guard canShareGoing, let s = session else { return }
        if !force, let at = raceGoingAt, Date().timeIntervalSince(at) < 600 { return }
        if let t = raceGoingTask { await t.value; if !force { return } }
        let t = Task { [weak self] in
            guard let got = try? await RaceGoingServer.fetch(session: s) else { return }
            self?.raceGoing = got
            self?.raceGoingAt = Date()
            self?.adoptGoing(got)
        }
        raceGoingTask = t
        await t.value
        raceGoingTask = nil
    }

    /// Going is the member's on every device: a switch flipped on another device (the server's `mine`) is taken over
    /// here, unless this device flipped it after its last confirmed sync (then this device's switch is still on its way).
    func adoptGoing(_ got: RaceGoing, now: Date = Date()) {
        let syncedAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "raceSyncAt"))
        let server = Set(got.mine)
        var changed = false
        for e in upcomingMyRaces where e.mine.raceId != nil && !e.race.isCustom {
            guard let id = e.mine.raceId, e.mine.going != server.contains(id), (e.mine.goingAt ?? .distantPast) <= syncedAt else { continue }
            guard let i = myRaces.firstIndex(where: { $0.id == e.mine.id }) else { continue }
            myRaces[i].going = server.contains(id)
            changed = true
        }
        if changed { persistMyRaces() }
    }

    /// "Show friends I'm going" on a race page: adds the race to My races if needed. The first time, it says what the
    /// server keeps; without the server it says how to switch it on.
    func setRaceGoing(_ r: Race, _ on: Bool) {
        guard !r.isCustom else { return }
        guard !on || canShareGoing else { flash(Copy.goingNeedsServer, icon: "server.rack"); return }
        let apply = { [weak self] in
            guard let self else { return }
            let wasMine = self.isMyRace(r.id)
            var mine = self.myRace(forKey: r.id) ?? MyRace(race: r)
            mine.going = on
            mine.goingAt = Date()
            self.saveMyRace(mine)
            if AppModel.demo {
                self.raceGoing.mine.removeAll { $0 == r.id }
                if on { self.raceGoing.mine.append(r.id) }
                self.raceGoing.sharing = self.myRaceEntries.contains { $0.sharesGoing }
            }
            self.flash(on ? (wasMine ? Copy.goingOn : Copy.goingOnAdded) : Copy.goingOff, icon: on ? "person.2.fill" : "person.2.slash")
        }
        let key = "raceGoingConsent"
        if !on || AppModel.demo || UserDefaults.standard.bool(forKey: key) { apply(); return }
        confirm = PendingAction(title: Copy.goingConsentTitle, message: Copy.goingConsent, button: "Show friends") {
            UserDefaults.standard.set(true, forKey: key)
            apply()
        }
    }

    // MARK: Crews

    /// The crew the member is in (or invited to) for a race: an accepted one first.
    func crew(forRace raceId: String) -> ChallengeSummary? {
        let all = challenges.filter { $0.raceId == raceId && $0.isCrew }
        return all.first { !$0.isInvite } ?? all.first
    }

    /// Starts a crew for a race: a challenge from today to the member's race day with the weekly target; adds the race to
    /// My races. Returns the crew's id.
    func startCrew(_ r: Race, name: String, weekly: Int, invite: [Int]) async -> String? {
        if !isMyRace(r.id) { myRaces.append(MyRace(race: r)); persistMyRaces() }
        let day = myRace(forKey: r.id)?.day ?? r.date
        guard let end = RaceDay.date(day) else { return nil }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = ChallengeDraft(metric: "visits", start: BruceDate.calendar.startOfDay(for: Date()), end: end, repeatMonthly: false, invite: invite,
                                   raceId: r.id, weekly: min(max(weekly, Crew.weeklyRange.lowerBound), Crew.weeklyRange.upperBound),
                                   name: n.isEmpty ? RaceSocialText.crewName(r) : String(n.prefix(80)))
        return await createChallenge(draft)
    }

    // MARK: After the race

    /// The race just run (its recovery week), when no Train for it plan already shows that week.
    var justRaced: (entry: MyRaceEntry, recovery: RaceRecovery)? {
        for e in pastMyRaces {
            guard let rec = e.recovery() else { continue }
            if let p = racePlan(for: e), p.isRunning() { continue }
            return (e, rec)
        }
        return nil
    }

    // MARK: Demo (offline): fictional friends going and a crew

    func loadDemoGoing() {
        raceGoingAt = Date()
        raceGoing = RaceGoing(going: [
            "hyrox-stockholm-2026": [RaceFriend(userId: 7, name: "Robin"), RaceFriend(userId: 12, name: "Sam")],
            "vasaloppet-2027": [RaceFriend(userId: 7, name: "Robin"), RaceFriend(userId: 11, name: "Alex"), RaceFriend(userId: 9, name: "Maja")],
            "tough-viking-stadion-2027": [RaceFriend(userId: 11, name: "Alex"), RaceFriend(userId: 9, name: "Maja")],
            "goteborgsvarvet-2027": [RaceFriend(userId: 12, name: "Sam")],
        ], sharing: true, mine: myRaces.filter(\.going).compactMap(\.raceId))
    }

    /// "HYROX Sthlm Doubles": five friends, 4 sessions a week until race day. This week the demo member has done the
    /// plan's Strength and run; last week 4 of 5 hit their sessions.
    func demoCrewChallenge() -> (ChallengeSummary, ChallengeDetail) {
        let cal = BruceDate.calendar
        let monday = RacePlanner.monday(of: RaceDay.today())
        let start = RaceDay.adding(-14, to: monday) ?? monday
        let end = "2026-12-12"
        let people: [(Int, String)] = [(7, "Robin"), (0, "Demo"), (12, "Sam"), (11, "Alex"), (9, "Maja")]
        let days = RacePlanner.days(from: start, to: RaceDay.today()) + 1
        let total = RacePlanner.days(from: start, to: end) + 1
        let c = ChallengeSummary(id: "demoCrew", title: "HYROX Sthlm Doubles", metric: "visits", start: start, end: end, repeatMonthly: false,
                                 ownerId: 7, ownerName: "Robin", myStatus: "accepted",
                                 participants: people.map { ChallengeParticipant(userId: $0.0, name: $0.1, status: "accepted") },
                                 period: ChallengePeriod(start: start, end: end, label: "\(RaceDay.format(start, "d MMM")) – \(RaceDay.format(end, "d MMM yyyy"))",
                                                         day: days, days: total, daysLeft: max(0, total - days)),
                                 shareUrl: Challenge.shareURL("demoCrew").absoluteString, raceId: "hyrox-stockholm-2026", weekly: 4)
        let week: [(Int, Int, Int)] = [(12, 4, 4), (7, 3, 4), (0, 2, 4), (9, 2, 5), (11, 1, 2)]
        let crew = CrewWeeks(raceId: "hyrox-stockholm-2026", weekly: 4, size: 5,
                             week: .init(start: monday, end: RaceDay.adding(6, to: monday)),
                             lastWeek: .init(start: RaceDay.adding(-7, to: monday), end: RaceDay.adding(-1, to: monday), hit: 4),
                             weeksLeft: max(0, Int((Double(RacePlanner.days(from: RaceDay.today(), to: end)) / 7).rounded(.up))),
                             members: week.map { id, now, last in
                                 CrewWeeks.Member(userId: id, name: people.first { $0.0 == id }?.1, thisWeek: now, lastWeek: last) })
        let iso = ISO8601DateFormatter()
        let board = week.enumerated().map { i, w in
            let n = w.1 + w.2 + 4 - i
            return ChallengeEntry(userId: w.0, name: people.first { $0.0 == w.0 }?.1, status: "accepted", rank: i + 1, score: n, visits: n, classes: n - 1,
                                  dropins: 1, minutes: n * 55, studios: 2, topClass: .init(title: "Hyrox", count: max(1, n / 2)),
                                  lastVisit: iso.string(from: cal.date(byAdding: .day, value: -(i % 3), to: Date()) ?? Date()), daily: [])
        }
        return (c, ChallengeDetail(challenge: c, leaderboard: board, months: [], crew: crew, updatedAt: iso.string(from: Date().addingTimeInterval(-5 * 3600))))
    }
}
