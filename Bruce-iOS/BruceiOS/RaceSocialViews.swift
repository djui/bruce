import SwiftUI

// Friends going, race crews and after the race on iPhone (RaceSocial.swift): faces of friends going on race cards, the
// race page and My races; "Show friends I'm going" (opt-in per race); the crew card on the race page and Start a crew;
// the crew's week on the challenge page; results and the recovery week after the race.

/// Faces and "2 friends going" (race cards on a gradient, the race page, My races rows).
struct GoingFaces: View {
    let users: [BruceAPI.UserLite]
    var size: CGFloat = 26
    var onDark = false
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -size * 0.18) {
                ForEach(users.prefix(3), id: \.id) { u in
                    Avatar(fileId: u.photo, initials: u.initials, size: size)
                        .overlay(Circle().stroke(onDark ? Color.white.opacity(0.85) : Theme.background, lineWidth: 2))
                }
                if users.count > 3 {
                    Text("+\(users.count - 3)").bruceFont(12, weight: .bold).foregroundStyle(onDark ? .white : Theme.ink)
                        .frame(width: size, height: size)
                        .background(Circle().fill(onDark ? Color.white.opacity(0.25) : Theme.chipGrey))
                        .overlay(Circle().stroke(onDark ? Color.white.opacity(0.85) : Theme.background, lineWidth: 2))
                }
            }
            Text(RaceSocialText.going(users.count)).bruceFont(14, weight: .semibold)
                .foregroundStyle(onDark ? .white : Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RaceSocialText.names(users.compactMap(\.firstName)))
    }
}

/// Race page: who of your friends is going, "Show friends I'm going", and the crew (or Start a crew).
struct RaceFriendsCard: View {
    @Environment(AppModel.self) var m
    let race: Race
    var body: some View {
        let mine = m.myRace(forKey: race.id)
        let friends = m.friendsGoing(race.id)
        VStack(alignment: .leading, spacing: 14) {
            Text("WITH FRIENDS").bruceHeading(16)
            Toggle(isOn: Binding(get: { mine?.going ?? false }, set: { m.setRaceGoing(race, $0) })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.goingToggle).bruceFont(16, weight: .semibold)
                        Text(m.canShareGoing ? Copy.goingHint : Copy.goingNeedsServer).bruceFont(13).foregroundStyle(Theme.secondary)
                    }
                } icon: { Image(systemName: "person.2") }
            }
            .disabled(!m.canShareGoing && mine?.going != true)
            if friends.isEmpty, m.canShareGoing, !m.raceGoing.sharing {
                Text(Copy.goingShareToSee).bruceFont(13).foregroundStyle(Theme.secondary)
            }
            Divider()
            RaceCrewBlock(race: race)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// The member's crew for a race (or an invite to one), else Start a crew.
struct RaceCrewBlock: View {
    @Environment(AppModel.self) var m
    let race: Race
    var body: some View {
        let crew = m.crew(forRace: race.id)
        Group {
            if let crew, crew.isInvite {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(crew.ownerName ?? "A friend") invited you to a crew", systemImage: "person.3.fill").bruceFont(16, weight: .semibold)
                    Text("\(crew.displayTitle) · \(RaceSocialText.weekly(crew.weekly ?? 1))").bruceFont(14).foregroundStyle(Theme.secondary)
                    HStack(spacing: 10) {
                        Button { m.withChallengeServerConsent { await m.joinChallenge(crew.id) } } label: {
                            Text("Accept").bruceFont(15, weight: .bold).foregroundStyle(.black).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(Theme.lime)
                        Button { Task { await m.leaveChallenge(crew.id) } } label: { Text("Decline").bruceFont(15, weight: .semibold).frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                    }
                    Text(ChallengeCopy.crewPrivacy).bruceFont(12).foregroundStyle(Theme.secondary)
                }
            } else if let crew {
                NavigationLink(value: Route.challenge(crew.id)) { CrewSummaryRow(crew: crew, detail: m.challengeDetails[crew.id]) }
                    .buttonStyle(.plain)
                    .task { await m.loadChallenge(crew.id) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Train with friends", systemImage: "person.3").bruceFont(16, weight: .semibold)
                    Text(Copy.crewIntro).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { m.present(.newCrew(race.id)) } label: {
                        Label("Start a crew", systemImage: "plus").bruceFont(15, weight: .semibold).padding(.horizontal, 12).frame(height: 34)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

/// Crew on the race page: name, sessions a week, members, your week.
struct CrewSummaryRow: View {
    @Environment(AppModel.self) var m
    let crew: ChallengeSummary
    let detail: ChallengeDetail?
    var body: some View {
        let w = detail?.crew
        let me = w?.members.first { m.isMe($0.userId) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(crew.displayTitle, systemImage: "person.3.fill").bruceFont(16, weight: .semibold).lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(crew.accepted.prefix(6), id: \.userId) { p in
                        LetterFace(name: m.isMe(p.userId) ? "You" : (p.name ?? "?"), color: m.isMe(p.userId) ? Theme.lime : nil, size: 28)
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                    }
                }
                Text("\(crew.accepted.count) in the crew · \(RaceSocialText.weekly(crew.weekly ?? 1))").bruceFont(14).foregroundStyle(Theme.secondary)
            }
            if let w, let me {
                HStack {
                    CrewBar(done: me.thisWeek ?? 0, weekly: w.weekly ?? 1).frame(maxWidth: 160)
                    Text("You: \(RaceSocialText.thisWeek(me.thisWeek ?? 0, w.weekly ?? 1))").bruceFont(14, weight: .semibold)
                }
                if let l = RaceSocialText.lastWeek(w) { Text(l).bruceFont(13).foregroundStyle(Theme.secondary) }
            }
        }
        .foregroundStyle(Theme.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Sessions this week against the crew's target, one bar per session.
struct CrewBar: View {
    let done: Int
    let weekly: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(weekly, 1), id: \.self) { i in
                Capsule().fill(i < done ? Theme.lime : Theme.chipGrey).frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The challenge page of a crew: everyone's week, last week, the race.
struct CrewWeekSection: View {
    @Environment(AppModel.self) var m
    let crew: ChallengeSummary
    let weeks: CrewWeeks
    var onTap: (Int) -> Void = { _ in }
    var body: some View {
        let weekly = weeks.weekly ?? 1
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THIS WEEK").bruceHeading(18)
                Spacer()
                Text(RaceSocialText.doneThisWeek(weeks)).bruceFont(14, weight: .semibold).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(weeks.members.enumerated()), id: \.1.id) { i, mem in
                    if i > 0 { Divider().padding(.leading, 62) }
                    let me = m.isMe(mem.userId)
                    Button { onTap(mem.userId) } label: {
                        HStack(spacing: 12) {
                            LetterFace(name: me ? "You" : (mem.name ?? "?"), color: me ? Theme.lime : nil, size: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(me ? "You" : (mem.name ?? "Friend")).bruceFont(16, weight: .semibold)
                                    Spacer()
                                    Text(RaceSocialText.thisWeek(mem.thisWeek ?? 0, weekly)).bruceFont(14, weight: .semibold).monospacedDigit()
                                    if (mem.thisWeek ?? 0) >= weekly { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.limeInk) }
                                }
                                CrewBar(done: mem.thisWeek ?? 0, weekly: weekly)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(me ? Theme.lime.opacity(0.18) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(me ? "You" : (mem.name ?? "Friend")): \(RaceSocialText.thisWeek(mem.thisWeek ?? 0, weekly))")
                }
            }
            .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            if let l = RaceSocialText.lastWeek(weeks) { Label(l, systemImage: "flag.checkered").bruceFont(15, weight: .semibold).padding(.top, 2) }
            if let raceId = crew.raceId, let r = m.race(raceId) {
                NavigationLink(value: Route.race(raceId)) {
                    HStack {
                        Label(r.name, systemImage: r.symbol).bruceFont(15, weight: .semibold)
                        Spacer()
                        Text(r.countdownShort(day: m.myRace(forKey: raceId)?.day)).bruceFont(14).foregroundStyle(Theme.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(14)
                    .background(Theme.sectionGrey, in: .rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
            Text(Copy.crewUpdatesHint + (AutoBookServer.crewUpdates ? "" : " Switched off in Menu › Auto-book."))
                .bruceFont(12).foregroundStyle(Theme.secondary)
        }
    }
}

/// Race page after the race: results on the race's own site, and the recovery week.
struct RaceAfterCard: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) private var openURL
    let race: Race
    let entry: MyRaceEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Copy.raceOver(race), systemImage: "flag.checkered").bruceFont(16, weight: .semibold)
            // Your result (RaceViews.swift RaceResultEditor): typed by hand, into Wrapped and Apple Health.
            if let e = entry {
                if let res = e.mine.result { RaceResultBlock(result: res) }
                Button { m.present(.raceResult(e.mine.key)) } label: {
                    Label(e.mine.result == nil ? Copy.raceResultAdd : "Edit result", systemImage: "stopwatch").bruceFont(15, weight: .semibold)
                        .padding(.horizontal, 12).frame(height: 34)
                }
                .buttonStyle(.glass)
            }
            if let u = race.results {
                Button { openURL(u) } label: {
                    Label("\(Copy.raceResults) on \(Self.host(u))", systemImage: "list.number").bruceFont(16, weight: .semibold)
                        .foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.glassProminent).tint(Theme.lime)
                .accessibilityHint("Opens the race's results page in Safari")
            }
            if let e = entry, let rec = e.recovery(), m.racePlan(for: e).map({ !$0.isRunning() }) ?? true {
                RecoveryBlock(recovery: rec)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
    static func host(_ u: URL) -> String {
        let h = u.host?.lowercased() ?? "the race's site"
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

/// The recovery week's class mix with a Find button per category.
struct RecoveryBlock: View {
    @Environment(AppModel.self) var m
    let recovery: RaceRecovery
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("\(Copy.raceRecoveryTitle): \(recovery.text)").bruceFont(15, weight: .semibold)
            Text(Copy.raceRecoveryHint).bruceFont(13).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                ForEach(recovery.categories, id: \.self) { c in
                    Button { m.showPlanCategory(c) } label: {
                        Label("Find \(c.short)", systemImage: c.symbol).bruceFont(14, weight: .semibold).padding(.horizontal, 10).frame(height: 32)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

/// My classes › Races, just after a race: results and the easy week (when no plan shows it already).
struct JustRacedCard: View {
    @Environment(\.openURL) private var openURL
    let entry: MyRaceEntry
    let recovery: RaceRecovery
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("After \(entry.race.name)").bruceFont(17, weight: .bold).lineLimit(2)
                Spacer()
                if let u = entry.race.results {
                    Button { openURL(u) } label: { Text(Copy.raceResults).bruceFont(14, weight: .semibold) }.buttonStyle(.glass)
                }
            }
            RecoveryBlock(recovery: recovery)
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 24))
    }
}

// MARK: - Start a crew

struct NewCrewSheet: View {
    @Environment(AppModel.self) var m
    let raceKey: String
    @State private var name = ""
    @State private var weekly = 3
    @State private var invited: Set<Int> = []
    @State private var working = false
    @State private var loaded = false

    var race: Race? { m.race(raceKey) }
    var friends: [BruceAPI.UserLite] {
        m.friends.compactMap(\.friendUser).sorted { (m.usesBruce.contains($0.id) ? 0 : 1, $0.firstName ?? "") < (m.usesBruce.contains($1.id) ? 0 : 1, $1.firstName ?? "") }
    }

    var body: some View {
        Form {
            if let r = race {
                Section {
                    HStack(spacing: 12) {
                        BibDate(race: r, day: m.myRace(forKey: raceKey)?.day, scale: 0.7).shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).bruceFont(17, weight: .bold)
                            Text("Until race day · \(r.countdownShort(day: m.myRace(forKey: raceKey)?.day))").bruceFont(14).foregroundStyle(Theme.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                } footer: { Text(Copy.crewIntro) }
                Section {
                    TextField("Crew name", text: $name).textInputAutocapitalization(.words)
                    Stepper(RaceSocialText.weekly(weekly), value: $weekly, in: Crew.weeklyRange)
                } header: { Text("Crew") } footer: { Text(Copy.crewWeeklyHint) }
                Section {
                    if friends.isEmpty {
                        Text(m.isLoggedIn ? "Add friends in Bruce to train with them." : "Log in to start a crew.").foregroundStyle(Theme.secondary)
                    }
                    ForEach(friends, id: \.id) { u in
                        if m.usesBruce.contains(u.id) {
                            Button {
                                if invited.contains(u.id) { invited.remove(u.id) } else { invited.insert(u.id) }
                            } label: {
                                friendRow(u, sub: m.friendsGoing(raceKey).contains { $0.id == u.id } ? "Going · uses Brüce" : "Uses Brüce") {
                                    Image(systemName: invited.contains(u.id) ? "checkmark.circle.fill" : "circle").bruceFont(26)
                                        .foregroundStyle(invited.contains(u.id) ? Theme.limeInk : Theme.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(invited.contains(u.id) ? .isSelected : [])
                        } else {
                            ShareLink(item: URL(string: "https://djui.github.io/bruce/app/")!,
                                      message: Text("\(u.firstName ?? "Hi"), I'm starting a crew for \(r.name) on Brüce. Get the app and I'll add you.")) {
                                friendRow(u, sub: "Not on Brüce yet · send link") { Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.limeInk) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("Invite friends") } footer: {
                    Label(ChallengeCopy.crewPrivacy, systemImage: "lock").bruceFont(13)
                }
                Section {
                    LimeButton(title: working ? "Starting…" : "Start crew · \(invited.count + 1) \(invited.isEmpty ? "person" : "people")") { start(r) }
                        .disabled(working || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } footer: {
                    if !AutoBookServer.booksForMe { Text(ChallengeCopy.serverConsent) }
                }
            } else {
                Text(Copy.raceGone)
            }
        }
        .tint(Theme.lime)
        .sheetChrome("Start a crew")
        .task { if m.friends.isEmpty { await m.loadSocial() }; await m.loadChallenges() }
        .onAppear {
            guard !loaded, let r = race else { return }
            loaded = true
            name = RaceSocialText.crewName(r)
            weekly = Crew.defaultWeekly(m.myRace(forKey: raceKey)?.plan)
            if AppModel.demo { invited = [11, 9] }
        }
    }

    func friendRow<A: View>(_ u: BruceAPI.UserLite, sub: String, @ViewBuilder accessory: () -> A) -> some View {
        HStack(spacing: 12) {
            Avatar(fileId: u.photo, initials: u.initials, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(u.firstName ?? u.fullName).bruceFont(16).foregroundStyle(Theme.ink)
                Text(sub).bruceFont(13).foregroundStyle(Theme.secondary)
            }
            Spacer()
            accessory()
        }
        .contentShape(Rectangle())
    }

    func start(_ r: Race) {
        m.withChallengeServerConsent {
            working = true
            defer { working = false }
            guard let id = await m.startCrew(r, name: name, weekly: weekly, invite: Array(invited)) else { return }
            m.dismissSheets()
            m.push(.challenge(id))
        }
    }
}
