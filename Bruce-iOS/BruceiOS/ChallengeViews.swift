import SwiftUI

// MARK: - Challenges with friends (Challenges.swift): Friends tab segment, challenge page, new challenge

extension AppModel {
    /// "Gym" for drop-ins, else the category title.
    func challengeCategoryTitle(_ key: String?) -> String {
        guard let key else { return "Everything" }
        if key == "gym" { return "Gym / drop-in" }
        return categoryTitle(forKey: key) ?? "Category \(key)"
    }
    /// A studio name from a leaderboard (the server may not know drop-in studio names).
    func studioLabel(id: Int?, name: String?) -> String {
        if let name, !name.isEmpty { return name }
        return id.map { studioName($0) } ?? "a studio"
    }
}

/// The Friends tab's "Challenges" segment.
struct ChallengesSegment: View {
    @Environment(AppModel.self) var m

    var body: some View {
        let invites = m.pendingChallengeInvites
        let running = m.challenges.filter { !$0.isInvite }
        VStack(alignment: .leading, spacing: 14) {
            if !AutoBookServer.isConfigured {
                EmptyState(system: "server.rack", text: "Challenges need our server. Set its address in Menu › Auto-book.")
            } else if let e = m.challengesError, m.challenges.isEmpty {
                EmptyState(system: "wifi.exclamationmark", text: e)
            }
            ForEach(invites) { c in ChallengeInviteCard(c: c) }
            ForEach(Array(running.enumerated()), id: \.1.id) { i, c in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink(value: Route.challenge(c.id)) { ChallengeHeaderCard(c: c) }.buttonStyle(.plain)
                    if let d = m.challengeDetails[c.id] {
                        Leaderboard(detail: d, limit: 5) { _ in m.push(.challenge(c.id)) }
                        if i == 0, let me = d.leaderboard?.first(where: { m.isMe($0.userId) }) {
                            YourDays(entry: me, challenge: c)
                        }
                    }
                }
                .task { await m.loadChallenge(c.id) }
            }
            if m.challengesLoaded && m.challenges.isEmpty && m.challengesError == nil && AutoBookServer.isConfigured {
                VStack(spacing: 14) {
                    Image(systemName: "trophy").bruceFont(48, weight: .light).foregroundStyle(Theme.limeInk)
                    Text("Challenge your friends: most classes this month, or everyone hits 12.")
                        .bruceFont(16).multilineTextAlignment(.center)
                    LimeButton(title: "New challenge", systemImage: "plus") { m.present(.newChallenge) }
                }
                .padding(.top, 50)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 30)
        .task { await m.loadChallenges() }
    }
}

/// Gradient card: month chip, days left, title, "4 friends · everything counts · started 1 Oct".
struct ChallengeHeaderCard: View {
    let c: ChallengeSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(chip, systemImage: "trophy.fill")
                    .bruceFont(12.5, weight: .semibold).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.lime, in: .capsule)
                Spacer()
                if let left = c.period?.daysLeft { Text(left == 0 ? "Last day" : "\(left) day\(left == 1 ? "" : "s") left").bruceFont(13).opacity(0.8) }
            }
            Text(c.displayTitle).bruceFont(22, weight: .heavy, width: .expanded).padding(.top, 12).padding(.bottom, 2)
            Text(line).bruceFont(14).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.17, green: 0.20, blue: 0.07), Color(red: 0.33, green: 0.42, blue: 0.11)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    /// "October" for a month, else "3 Nov – 16 Nov".
    var chip: String {
        let s = (c.period?.start).flatMap(Challenge.day), e = (c.period?.end).flatMap(Challenge.day)
        guard let s, let e else { return c.period?.label ?? "" }
        let cal = BruceDate.calendar
        if cal.component(.day, from: s) == 1, cal.isDate(s, equalTo: e, toGranularity: .month) { return BruceDate.format(s, "MMMM") }
        return "\(BruceDate.format(s, "d MMM")) – \(BruceDate.format(e, "d MMM"))"
    }

    var line: String {
        let n = c.accepted.count
        var parts = ["\(n) friend\(n == 1 ? "" : "s")", c.countsLabel]
        if let s = c.startDate {
            parts.append(s > Date() ? "starts \(BruceDate.format(s, "d MMM"))" : "started \(BruceDate.format(s, "d MMM"))")
        }
        return parts.joined(separator: " · ")
    }
}

struct ChallengeInviteCard: View {
    @Environment(AppModel.self) var m
    let c: ChallengeSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: Route.challenge(c.id)) {
                HStack(spacing: 12) {
                    LetterFace(name: c.ownerName ?? "?", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(c.ownerName ?? "A friend") challenged you").bruceFont(16, weight: .bold)
                        Text("\(c.displayTitle) · \(c.period?.label ?? "")").bruceFont(14).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Button { m.withChallengeServerConsent { await m.joinChallenge(c.id) } } label: {
                    Text("Accept").bruceFont(15, weight: .bold).foregroundStyle(.black).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(Theme.lime)
                Button { Task { await m.leaveChallenge(c.id) } } label: {
                    Text("Decline").bruceFont(15, weight: .semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            Text(ChallengeCopy.privacy).bruceFont(12).foregroundStyle(Theme.secondary)
        }
        .padding(16)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.lime, lineWidth: 2))
    }
}

struct Leaderboard: View {
    @Environment(AppModel.self) var m
    let detail: ChallengeDetail
    var limit = 50
    var onTap: (ChallengeEntry) -> Void

    var body: some View {
        let rows = Array((detail.leaderboard ?? []).prefix(limit))
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.1.id) { i, e in
                if i > 0 { Divider().padding(.leading, 82) }
                Button { onTap(e) } label: { row(e, above: i > 0 ? rows[i - 1] : nil) }.buttonStyle(.plain)
            }
        }
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    func row(_ e: ChallengeEntry, above: ChallengeEntry?) -> some View {
        let me = m.isMe(e.userId)
        return HStack(spacing: 10) {
            Text(e.rank.map(String.init) ?? "–").bruceFont(15, weight: .heavy).foregroundStyle(Theme.secondary).frame(width: 24)
            LetterFace(name: me ? "You" : (e.name ?? "?"), color: me ? Theme.lime : nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(me ? "You" : (e.name ?? "Friend")).bruceFont(16, weight: .semibold)
                Text(detailLine(e, above: above, me: me)).bruceFont(13).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if detail.challenge.metric == "target", e.done == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.limeInk)
            }
            Text(e.isInvited ? "" : score(e)).bruceFont(20, weight: .heavy, width: .expanded).monospacedDigit()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(me ? Theme.lime.opacity(0.22) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    func score(_ e: ChallengeEntry) -> String {
        let s = e.score ?? 0
        return detail.challenge.metric == "minutes" ? "\(Int((Double(s) / 60).rounded()))h" : "\(s)"
    }

    /// "Reformer ×5 · 3 studios", "2 behind Robin · 8 together", "Last visit 6 days ago", "Invited".
    func detailLine(_ e: ChallengeEntry, above: ChallengeEntry?, me: Bool) -> String {
        if e.isInvited { return "Invited" }
        let c = detail.challenge
        if me {
            if let a = above, !a.isInvited {
                let diff = (a.score ?? 0) - (e.score ?? 0)
                var s = diff == 0 ? "Tied with \(a.name ?? "them")" : "\(c.metric == "minutes" ? "\(diff) min" : "\(diff)") behind \(a.name ?? "them")"
                if let t = a.together, t > 0 { s += " · \(t) together" }
                return s
            }
            if c.metric == "target", let t = c.target { return e.done == true ? "Target reached" : "\(max(0, t - (e.score ?? 0))) to go" }
            let next = (detail.leaderboard ?? []).first { !m.isMe($0.userId) && !$0.isInvited }
            let lead = (e.score ?? 0) - (next?.score ?? 0)
            return lead > 0 ? "Leading by \(lead)" : "\(e.visits ?? 0) visits so far"
        }
        if let d = e.lastVisitDate, Date().timeIntervalSince(d) > 4 * 86_400 {
            return "Last visit \(Int(Date().timeIntervalSince(d) / 86_400)) days ago"
        }
        if let t = e.topClass, let title = t.title, (t.count ?? 0) >= 2 {
            return "\(title) ×\(t.count ?? 0)" + ((e.studios ?? 0) > 1 ? " · \(e.studios ?? 0) studios" : "")
        }
        if let t = e.together, t > 0 { return "\(t) together" }
        return "\(e.visits ?? 0) visit\(e.visits == 1 ? "" : "s")"
    }
}

/// "Your days": one bar per day of the period, up to today.
struct YourDays: View {
    let entry: ChallengeEntry
    let challenge: ChallengeSummary
    var body: some View {
        let daily = entry.daily ?? []
        let top = max(daily.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR DAYS").bruceHeading(18)
                Spacer()
                let n = entry.score ?? 0
                Text("\(n) \(Challenge.unit(challenge.metric, n)) in \(daily.count) day\(daily.count == 1 ? "" : "s")")
                    .bruceFont(14, weight: .semibold).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(daily.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 3).fill(v > 0 ? Theme.lime : Color(.systemFill))
                            .frame(height: v > 0 ? max(8, 54 * CGFloat(v) / CGFloat(top) * 0.6 + 8) : 4)
                    }
                }
                .frame(height: 54, alignment: .bottom)
                HStack {
                    Text(challenge.startDate.map { BruceDate.format($0, "d MMM") } ?? "")
                    Spacer()
                    Text("Today")
                }
                .bruceFont(12).foregroundStyle(Theme.secondary)
            }
            .padding(14)
            .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Challenge page

struct ChallengeView: View {
    @Environment(AppModel.self) var m
    let challengeId: String
    @State private var member: ChallengeEntry?
    @State private var confirmLeave = false

    var summary: ChallengeSummary? { m.challengeDetails[challengeId]?.challenge ?? m.challenges.first { $0.id == challengeId } }

    var body: some View {
        let d = m.challengeDetails[challengeId]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeading(text: "Challenge")
                if let c = summary {
                    ChallengeHeaderCard(c: c)
                    if c.isInvite || d?.isPreview == true { joinBar(c, preview: d?.isPreview == true, joinable: d?.joinable ?? true) }
                    if let d, !d.isPreview {
                        Leaderboard(detail: d) { member = $0 }
                        if let me = d.leaderboard?.first(where: { m.isMe($0.userId) }), !me.isInvited { YourDays(entry: me, challenge: c) }
                        months(d)
                        sendLink(c)
                        if let u = d.updatedAt.flatMap(BruceDate.parse) {
                            Text("Updated daily. Last update \(BruceDate.format(u, "d MMM HH:mm")).").bruceFont(12).foregroundStyle(Theme.secondary)
                        }
                        Text(ChallengeCopy.privacy).bruceFont(13).foregroundStyle(Theme.secondary)
                        if !c.isInvite {
                            Button("Leave challenge", role: .destructive) { confirmLeave = true }.buttonStyle(.glass).padding(.top, 6)
                        }
                    }
                } else if let e = m.challengesError {
                    EmptyState(system: "wifi.exclamationmark", text: e)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 30)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .pushedPage("Challenge")
        .toolbar {
            if let c = summary {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: c.link, message: Text("Join my challenge on Brüce: \(c.displayTitle)")) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task { await m.loadChallenge(challengeId) }
        .refreshable { await m.loadChallenge(challengeId) }
        .sheet(item: $member) { e in
            ParticipantSheet(entry: e, metric: summary?.metric ?? "classes").presentationDetents([.medium, .large])
        }
        .confirmationDialog("Leave this challenge?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await m.leaveChallenge(challengeId) } }
        } message: { Text("Your numbers in it are deleted from our server.") }
        .onAppear {
            if let id = m.demoChallengeMember, let e = m.challengeDetails[challengeId]?.leaderboard?.first(where: { $0.userId == id }) {
                m.demoChallengeMember = nil; member = e
            }
        }
    }

    func joinBar(_ c: ChallengeSummary, preview: Bool, joinable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview ? "\(c.ownerName ?? "A friend") started this challenge." : "\(c.ownerName ?? "A friend") challenged you.")
                .bruceFont(16, weight: .semibold)
            if preview && !joinable {
                Text("Only Bruce friends of \(c.ownerName ?? "the owner") can join.").bruceFont(14).foregroundStyle(Theme.secondary)
            } else {
                LimeButton(title: preview ? "Join" : "Accept") { m.withChallengeServerConsent { await m.joinChallenge(c.id, viaLink: preview) } }
                if !preview {
                    Button("Decline") { Task { await m.leaveChallenge(c.id) } }.buttonStyle(.glass).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder func months(_ d: ChallengeDetail) -> some View {
        let list = d.months ?? []
        if !list.isEmpty {
            Text("BY MONTH").bruceHeading(18).padding(.top, 10)
            ForEach(list) { mo in
                VStack(alignment: .leading, spacing: 8) {
                    Text(mo.label ?? mo.month).bruceFont(15, weight: .bold)
                    ForEach(Array(mo.entries.enumerated()), id: \.offset) { i, e in
                        HStack {
                            Text("\(i + 1)").bruceFont(13, weight: .heavy).foregroundStyle(Theme.secondary).frame(width: 18)
                            Text(m.isMe(e.userId) ? "You" : (e.name ?? "Friend")).bruceFont(15, weight: m.isMe(e.userId) ? .bold : .regular)
                            Spacer()
                            Text("\(e.visits ?? 0) visits · \(Int((Double(e.minutes ?? 0) / 60).rounded())) h").bruceFont(13).foregroundStyle(Theme.secondary)
                            Text("\(e.score ?? 0)").bruceFont(15, weight: .bold).monospacedDigit().frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                }
                .padding(14)
                .background(Theme.sectionGrey, in: .rect(cornerRadius: 20))
            }
        }
    }

    /// Friends not on Brüce yet get the link through the share sheet.
    @ViewBuilder func sendLink(_ c: ChallengeSummary) -> some View {
        let inIt = Set((c.participants ?? []).map(\.userId))
        let others = m.friends.compactMap(\.friendUser).filter { !inIt.contains($0.id) && !m.usesBruce.contains($0.id) }
        if !others.isEmpty {
            Text("INVITE MORE").bruceHeading(18).padding(.top, 10)
            VStack(spacing: 0) {
                ForEach(Array(others.prefix(8).enumerated()), id: \.1.id) { i, u in
                    if i > 0 { Divider().padding(.leading, 58) }
                    ShareLink(item: c.link, message: Text("\(u.firstName ?? "Hi"), join my challenge on Brüce: \(c.displayTitle)")) {
                        HStack(spacing: 12) {
                            LetterFace(name: u.firstName ?? "?", size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.firstName ?? u.fullName).bruceFont(16).foregroundStyle(Theme.ink)
                                Text("Not on Brüce yet · send link").bruceFont(13).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.limeInk)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
            }
            .background(Theme.sectionGrey, in: .rect(cornerRadius: 22))
        }
    }
}

/// Everything a participant did in the challenge: totals, top class and studio, categories, recent visits.
struct ParticipantSheet: View {
    @Environment(AppModel.self) var m
    @Environment(\.dismiss) var dismiss
    let entry: ChallengeEntry
    let metric: String

    var body: some View {
        let me = m.isMe(entry.userId)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        LetterFace(name: me ? "You" : (entry.name ?? "?"), color: me ? Theme.lime : nil, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(me ? "You" : (entry.name ?? "Friend")).bruceFont(22, weight: .heavy, width: .expanded)
                            Text(entry.rank.map { "Rank \($0) · \(entry.score ?? 0) \(Challenge.unit(metric, entry.score ?? 0))" } ?? "Invited")
                                .bruceFont(14).foregroundStyle(Theme.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow { stat("\(entry.visits ?? 0)", "visits"); stat("\(entry.classes ?? 0)", "classes") }
                        GridRow { stat("\(entry.dropins ?? 0)", "drop-ins"); stat(String(format: "%.0f h", Double(entry.minutes ?? 0) / 60), "trained") }
                    }
                    .padding(.vertical, 6)
                }
                Section("Favourites") {
                    if let t = entry.topClass, let title = t.title { LabeledContent("Top class", value: "\(title) ×\(t.count ?? 0)") }
                    if let s = entry.topStudio { LabeledContent("Top studio", value: "\(m.studioLabel(id: s.id, name: s.name)) ×\(s.count ?? 0)") }
                    LabeledContent("Studios", value: "\(entry.studios ?? 0)")
                    if !me, let t = entry.together, t > 0 { LabeledContent("Together with you", value: "\(t) class\(t == 1 ? "" : "es")") }
                }
                if let cats = entry.categories, !cats.isEmpty {
                    Section("Class types") {
                        ForEach(cats, id: \.self) { c in LabeledContent(m.challengeCategoryTitle(c.key), value: "\(c.count ?? 0)") }
                    }
                }
                if let recent = entry.recent, !recent.isEmpty {
                    Section("Recent visits") {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.kind == "dropin" ? "Drop-in" : (r.title ?? "Class")).bruceFont(16, weight: .medium)
                                Text("\(m.studioLabel(id: r.studioId, name: r.studio)) · \(BruceDate.format(r.date, "EEE d MMM, HH:mm"))")
                                    .bruceFont(13).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(role: .close) { dismiss() } } }
        }
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).bruceFont(26, weight: .black, width: .expanded).monospacedDigit()
            Text(l).bruceFont(13, weight: .semibold).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - New challenge

struct NewChallengeSheet: View {
    @Environment(AppModel.self) var m
    enum Period: String, CaseIterable { case thisMonth, nextMonth, custom }
    @State private var metric = "classes"
    @State private var target = 12
    @State private var period = Period.nextMonth
    @State private var customStart = Date()
    @State private var customEnd = Date().addingTimeInterval(13 * 86_400)
    @State private var category: Int?
    @State private var repeatMonthly = true
    @State private var invited: Set<Int> = []
    @State private var working = false

    var friends: [BruceAPI.UserLite] {
        m.friends.compactMap(\.friendUser).sorted { (m.usesBruce.contains($0.id) ? 0 : 1, $0.firstName ?? "") < (m.usesBruce.contains($1.id) ? 0 : 1, $1.firstName ?? "") }
    }

    var range: (Date, Date) {
        let cal = BruceDate.calendar
        let thisStart = cal.dateInterval(of: .month, for: Date())!.start
        switch period {
        case .thisMonth: return (thisStart, cal.date(byAdding: DateComponents(month: 1, day: -1), to: thisStart)!)
        case .nextMonth:
            let s = cal.date(byAdding: .month, value: 1, to: thisStart)!
            return (s, cal.date(byAdding: DateComponents(month: 1, day: -1), to: s)!)
        case .custom: return (cal.startOfDay(for: customStart), cal.startOfDay(for: max(customEnd, customStart)))
        }
    }

    func periodLabel(_ p: Period) -> String {
        let cal = BruceDate.calendar
        let thisStart = cal.dateInterval(of: .month, for: Date())!.start
        switch p {
        case .thisMonth: return BruceDate.format(thisStart, "MMMM yyyy")
        case .nextMonth: return BruceDate.format(cal.date(byAdding: .month, value: 1, to: thisStart), "MMMM yyyy")
        case .custom: return "Custom range"
        }
    }

    var body: some View {
        Form {
            Section("Who wins") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(["classes", "visits", "minutes", "target"], id: \.self) { k in
                        GlassChip(Challenge.metricTitle(k, target: k == "target" ? target : nil), selected: metric == k) { metric = k }
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if metric == "target" {
                    Stepper("Everyone hits \(target)", value: $target, in: 1...60)
                }
            }
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text(periodLabel($0)).tag($0) }
                }
                .pickerStyle(.menu).tint(Theme.secondary)
                if period == .custom {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart...customStart.addingTimeInterval(365 * 86_400), displayedComponents: .date)
                }
                Picker("Counts", selection: $category) {
                    Text("All categories").tag(Int?.none)
                    ForEach(m.sortedCategories) { c in Text(c.title ?? "").tag(Int?.some(c.id)) }
                }
                .pickerStyle(.menu).tint(Theme.secondary)
                if period != .custom { Toggle("Repeat monthly", isOn: $repeatMonthly) }
            }
            Section {
                if friends.isEmpty {
                    Text(m.isLoggedIn ? "Add friends in Bruce to challenge them." : "Log in to challenge friends.").foregroundStyle(Theme.secondary)
                }
                ForEach(friends, id: \.id) { u in
                    if m.usesBruce.contains(u.id) {
                        Button {
                            if invited.contains(u.id) { invited.remove(u.id) } else { invited.insert(u.id) }
                        } label: {
                            friendRow(u, sub: "Uses Brüce") {
                                Image(systemName: invited.contains(u.id) ? "checkmark.circle.fill" : "circle").bruceFont(26)
                                    .foregroundStyle(invited.contains(u.id) ? Theme.limeInk : Theme.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(invited.contains(u.id) ? .isSelected : [])
                    } else {
                        ShareLink(item: URL(string: "https://djui.github.io/bruce/app/")!,
                                  message: Text("\(u.firstName ?? "Hi"), I'm starting a challenge on Brüce. Get the app and I'll add you.")) {
                            friendRow(u, sub: "Not on Brüce yet · send link") { Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.limeInk) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { Text("Invite friends") } footer: {
                Label(ChallengeCopy.privacy, systemImage: "lock").bruceFont(13)
            }
            Section {
                LimeButton(title: working ? "Starting…" : "Start challenge · \(invited.count + 1) people") { start() }
                    .disabled(working).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            } footer: {
                if !AutoBookServer.booksForMe { Text(ChallengeCopy.serverConsent) }
            }
        }
        .tint(Theme.lime)
        .sheetChrome("New challenge")
        .task { if m.friends.isEmpty { await m.loadSocial() }; await m.loadChallenges() }
        .onAppear {
            if AppModel.demo && invited.isEmpty { invited = [7, 12] }
        }
    }

    func friendRow<A: View>(_ u: BruceAPI.UserLite, sub: String, @ViewBuilder accessory: () -> A) -> some View {
        HStack(spacing: 12) {
            LetterFace(name: u.firstName ?? "?", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(u.firstName ?? u.fullName).bruceFont(16).foregroundStyle(Theme.ink)
                Text(sub).bruceFont(13).foregroundStyle(Theme.secondary)
            }
            Spacer()
            accessory()
        }
        .contentShape(Rectangle())
    }

    func start() {
        let (s, e) = range
        let draft = ChallengeDraft(metric: metric, target: target, category: category.map(String.init),
                                   categoryTitle: category.flatMap { id in m.categories.first { $0.id == id }?.title },
                                   start: s, end: e, repeatMonthly: period != .custom && repeatMonthly, invite: Array(invited))
        m.withChallengeServerConsent {
            working = true
            defer { working = false }
            guard let id = await m.createChallenge(draft) else { return }
            m.dismissSheets()
            m.tab = .friends
            m.stacks[.friends] = [.challenge(id)]
        }
    }
}
