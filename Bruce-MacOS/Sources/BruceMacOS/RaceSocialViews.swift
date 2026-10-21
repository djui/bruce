import SwiftUI
import AppKit

// Friends going, race crews and after the race on the Mac (RaceSocial.swift), on the race page: who is going and
// "Show friends I'm going", the crew card (this week per member, invite, leave) and Start a crew, results and the
// recovery week. Challenges are iPhone-only on the Mac, so a crew lives on its race page here.

/// "2 friends going" with faces (race cards, race page, My races).
struct GoingFaces: View {
    let users: [BruceAPI.UserLite]
    var size: CGFloat = 24
    var onDark = false
    var body: some View {
        HStack(spacing: 8) {
            FriendFaces(users: users, size: size)
            Text(RaceSocialText.going(users.count)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(onDark ? .white : Theme.secondary)
        }
        .help(RaceSocialText.names(users.compactMap(\.firstName)))
    }
}

/// Race page: friends going and the opt-in toggle.
struct RaceGoingCard: View {
    @Environment(AppModel.self) var m
    let race: Race
    var body: some View {
        let friends = m.friendsGoing(race.id)
        let mine = m.myRace(forKey: race.id)
        VStack(alignment: .leading, spacing: 10) {
            if !friends.isEmpty { GoingFaces(users: friends, size: 28) }
            Toggle(isOn: Binding(get: { mine?.going ?? false }, set: { m.setRaceGoing(race, $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.goingToggle).font(.system(size: 15, weight: .semibold))
                    Text(m.canShareGoing ? Copy.goingHint : Copy.goingNeedsServer).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                }
            }
            .toggleStyle(.switch).tint(Theme.lime)
            .disabled(!m.canShareGoing && mine?.going != true)
            if friends.isEmpty, m.canShareGoing, !m.raceGoing.sharing {
                Text(Copy.goingShareToSee).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
    }
}

/// Race page: the member's crew for this race (this week per member), an invite to one, or Start a crew.
struct RaceCrewCard: View {
    @Environment(AppModel.self) var m
    let race: Race
    @State private var confirmLeave = false
    var body: some View {
        let crew = m.crew(forRace: race.id)
        VStack(alignment: .leading, spacing: 10) {
            if let crew {
                HStack {
                    Label(crew.displayTitle, systemImage: "person.3.fill").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(RaceSocialText.weekly(crew.weekly ?? 1)).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
                }
                if crew.isInvite {
                    Text("\(crew.ownerName ?? "A friend") invited you to this crew.").font(.system(size: 14))
                    HStack {
                        Button("Accept") { m.withChallengeServerConsent { await m.joinChallenge(crew.id) } }
                        Button("Decline") { Task { await m.leaveChallenge(crew.id) } }
                    }
                    Text(ChallengeCopy.crewPrivacy).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                } else if let w = m.challengeDetails[crew.id]?.crew {
                    ForEach(w.members) { mem in
                        HStack(spacing: 10) {
                            Avatar(fileId: nil, initials: String((m.isMe(mem.userId) ? "You" : mem.name ?? "?").prefix(1)), size: 26)
                            Text(m.isMe(mem.userId) ? "You" : mem.name ?? "Friend").font(.system(size: 14, weight: m.isMe(mem.userId) ? .bold : .regular))
                            Spacer()
                            CrewBar(done: mem.thisWeek ?? 0, weekly: w.weekly ?? 1).frame(width: 120)
                            Text(RaceSocialText.thisWeek(mem.thisWeek ?? 0, w.weekly ?? 1)).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                                .frame(width: 96, alignment: .trailing)
                        }
                    }
                    if let l = RaceSocialText.lastWeek(w) { Text(l).font(.system(size: 13, weight: .semibold)) }
                    HStack {
                        ShareLink(item: crew.link, message: Text("Train with me for \(race.name) on Brüce: \(crew.displayTitle)")) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button("Leave crew") { confirmLeave = true }.foregroundStyle(.red)
                    }
                    .font(.system(size: 13))
                    Text(ChallengeCopy.crewPrivacy).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else {
                Text("Train with friends").font(.system(size: 16, weight: .bold))
                Text(Copy.crewIntro).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Button { m.present(.newCrew(race.id)) } label: { Label("Start a crew", systemImage: "person.3") }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
        .task(id: crew?.id) { if let id = crew?.id, !(crew?.isInvite ?? true) { await m.loadChallenge(id) } }
        .confirmationDialog("Leave this crew?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive) { if let id = crew?.id { Task { await m.leaveChallenge(id) } } }
        } message: { Text("Your numbers in it are deleted from our server.") }
    }
}

/// Sessions this week against the crew's target.
struct CrewBar: View {
    let done: Int
    let weekly: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(weekly, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: 3).fill(i < done ? Theme.lime : Theme.chipGrey).frame(height: 8)
            }
        }
    }
}

/// Race page after the race: results on the race's own site, and the recovery week.
struct RaceAfterCard: View {
    @Environment(AppModel.self) var m
    let race: Race
    let entry: MyRaceEntry?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.raceOver(race)).font(.system(size: 15, weight: .semibold))
            // Your result (RaceViews.swift RaceResultEditor), typed by hand.
            if let e = entry {
                if let res = e.mine.result {
                    HStack(alignment: .firstTextBaseline) {
                        Text(res.dnf ? Copy.raceResultDNF : res.timeText).font(.system(size: 24, weight: .black).width(.expanded)).monospacedDigit()
                        Spacer()
                        if let p = res.placeText { Text(p).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary) }
                    }
                    ForEach(res.splits) { s in
                        HStack { Text(s.title).font(.system(size: 13)); Spacer(); Text(RaceResult.timeText(s.seconds)).font(.system(size: 13, weight: .semibold)).monospacedDigit() }
                    }
                }
                Button(e.mine.result == nil ? Copy.raceResultAdd : "Edit result…") { m.present(.raceResult(e.mine.key)) }.font(.system(size: 14, weight: .semibold))
            }
            if let u = race.results {
                Button { NSWorkspace.shared.open(u) } label: {
                    Label("\(Copy.raceResults) on \(u.host?.replacingOccurrences(of: "www.", with: "") ?? "the race's site")", systemImage: "list.number")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            if let e = entry, let rec = e.recovery(), m.racePlan(for: e).map({ !$0.isRunning() }) ?? true {
                Divider()
                Text("\(Copy.raceRecoveryTitle): \(rec.text)").font(.system(size: 14, weight: .semibold))
                Text(Copy.raceRecoveryHint).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                HStack {
                    ForEach(rec.categories, id: \.self) { c in Button("Find \(c.short)") { m.showPlanCategory(c) } }
                }
                .font(.system(size: 13))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
    }
}

/// Start a crew: name, sessions a week (from the plan) and friends to invite.
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
        m.friends.compactMap(\.friendUser).filter { m.usesBruce.contains($0.id) }.sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Start a crew", leading: .close, action: { m.dismissSheets() })
            if let r = race {
                Form {
                    TextField("Crew name", text: $name)
                    Stepper("\(RaceSocialText.weekly(weekly))", value: $weekly, in: Crew.weeklyRange)
                    Text(Copy.crewWeeklyHint).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                    Section("Invite friends who use Brüce") {
                        if friends.isEmpty { Text("Friends on Brüce show up here. Others can join with the share link.").foregroundStyle(Theme.secondary) }
                        ForEach(friends, id: \.id) { u in
                            Toggle(u.firstName ?? u.fullName, isOn: Binding(get: { invited.contains(u.id) }, set: { on in
                                if on { invited.insert(u.id) } else { invited.remove(u.id) }
                            }))
                        }
                    }
                    Text(ChallengeCopy.crewPrivacy).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary)
                    if !AutoBookServer.booksForMe { Text(ChallengeCopy.serverConsent).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary) }
                }
                .padding(Theme.gutter)
                Spacer()
                LimeButton(title: working ? "Starting…" : "Start crew · \(invited.count + 1) people") { start(r) }
                    .disabled(working).padding(Theme.gutter)
            } else {
                EmptyState(system: "flag.checkered", text: Copy.raceGone)
            }
        }
        .task { if m.friends.isEmpty { await m.loadSocial() }; await m.loadChallenges() }
        .onAppear {
            guard !loaded, let r = race else { return }
            loaded = true
            name = RaceSocialText.crewName(r)
            weekly = Crew.defaultWeekly(m.myRace(forKey: raceKey)?.plan)
            if AppModel.demo { invited = [11, 9] }
        }
    }

    func start(_ r: Race) {
        m.withChallengeServerConsent {
            working = true
            defer { working = false }
            guard await m.startCrew(r, name: name, weekly: weekly, invite: Array(invited)) != nil else { return }
            m.dismissSheets()
        }
    }
}
