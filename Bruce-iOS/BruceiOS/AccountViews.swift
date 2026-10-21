import SwiftUI
import QuickLook

// MARK: - Menu

struct MenuSheet: View {
    @Environment(AppModel.self) var m
    let rows: [(String, String, SheetRoute)] = [
        ("person.crop.circle", "Account", .account),
        ("gearshape", "Settings", .settings),
        ("calendar.badge.clock", "Auto-book", .autoBook),
        ("target", "Monthly goals", .goals),
        ("person.2", "Invite friends", .invite),
        ("gift", "Redeem voucher", .voucher),
        ("bubble.left.and.bubble.right", "Support", .support),
    ]
    var body: some View {
        List {
            Section {
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    Button {
                        if (r.1 == "Account" || r.1 == "Monthly goals") && !m.isLoggedIn { m.sheets = [.login] } else { m.sheets = [r.2] }
                    } label: {
                        Label {
                            Text(r.1).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.ink)
                        } icon: {
                            Image(systemName: r.0).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) { if m.isLoggedIn { WrappedBanner().padding(.horizontal, Theme.gutter).padding(.top, 4) } }
        .scrollContentBackground(.hidden)
        .sheetChrome("Menu")
    }
}

// MARK: - Account

struct AccountSheet: View {
    @Environment(AppModel.self) var m
    var visits: BruceAPI.VisitLimit? { m.visitLimits.first { $0.type == "MONTHLY" } ?? m.visitLimits.first }
    var tier: String { m.membership?.membershipTier ?? m.membership?.admissionTier ?? "—" }

    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.user?.fullName ?? "Member").font(.system(size: 20, weight: .bold))
                        Text("Member #\(m.user.map { String($0.id) } ?? "—")").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        NavigationLink(value: SheetRoute.editProfile) { Text("Edit profile").font(.system(size: 14, weight: .semibold)) }
                            .buttonStyle(.glass).controlSize(.small)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink(value: SheetRoute.membership) {
                    InfoRow(title: "Membership", subtitle: m.membership?.paused == true ? "Paused" : (m.membership?.membership == true ? "Active" : "—"), chevron: false) {
                        Text(tier.uppercased()).font(.system(size: 12, weight: .heavy).width(.expanded)).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.baseTag))
                    }
                }
                if m.wellnessLimit != nil {
                    Button { m.wellnessOverlay = true } label: { InfoRow(title: "Wellness visits", subtitle: m.wellnessSummary) }
                }
                NavigationLink(value: SheetRoute.visits) {
                    InfoRow(title: "Total monthly visits", subtitle: visits.map { "\($0.used ?? 0) / \($0.total ?? 0)" } ?? "—",
                            footnote: Copy.unlimitedExcluded, chevron: false)
                }
                NavigationLink(value: SheetRoute.credits) { InfoRow(title: "Credits", subtitle: m.membership?.availableCredits.map { "\($0) credits" } ?? "—", chevron: false) }
                NavigationLink(value: SheetRoute.strikes) { InfoRow(title: "Strikes", subtitle: m.blockInfo?.strikeCount.map { "\($0) of \(Policy.strikesToBlock)" } ?? "—", chevron: false) }
            }
            Section {
                NavigationLink(value: SheetRoute.payment) { InfoRow(title: "Payment methods", subtitle: "Your payment methods", chevron: false) }
                NavigationLink(value: SheetRoute.statistics) { InfoRow(title: "Statistics", subtitle: "Training history", chevron: false) }
                NavigationLink(value: SheetRoute.receipts) { InfoRow(title: "Receipts", subtitle: "Your payments", chevron: false) }
            }
            Section {
                Button(role: .destructive) { Task { await m.logout() } } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .sheetChrome("Account")
        .sheet(isPresented: Binding(get: { m.wellnessOverlay }, set: { m.wellnessOverlay = $0 })) { WellnessSheet().presentationDetents([.medium, .large]) }
        .task { await m.loadAccount() }
        .refreshable { await m.loadAccount() }
        .overlay { if m.user == nil && m.membership == nil && m.isLoggedIn { ProgressView() } }
    }
}

/// Wellness visits from the API (WELLNESS_MONTHLY limit). Plan changes are display-only.
struct WellnessSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let w = m.wellnessLimit
        VStack(alignment: .leading, spacing: 14) {
            Text("Wellness access").font(.system(size: 18, weight: .bold))
            switch w?.state ?? .unknown {
            case .limited(let total):
                Text("\(Text("\(w?.used ?? 0)").foregroundStyle(Theme.limeInk))\(Text("/\(total)").foregroundStyle(Theme.secondary))")
                    .font(.system(size: 52, weight: .black).width(.expanded))
                Text("VISITS USED THIS MONTH · \(m.tier) PLAN").font(.system(size: 12, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary)
                Text("\(max(0, w?.remaining ?? total - (w?.used ?? 0))) remaining").font(.system(size: 15))
            case .unlimited:
                Image(systemName: "infinity").font(.system(size: 48, weight: .black)).foregroundStyle(Theme.limeInk)
                Text("UNLIMITED VISITS · \(m.tier) PLAN").font(.system(size: 12, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary)
            case .notIncluded:
                Text("0/0").font(.system(size: 52, weight: .black).width(.expanded)).foregroundStyle(Theme.secondary)
                Text("NOT INCLUDED IN THE \(m.tier) PLAN").font(.system(size: 12, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary)
                Text("Wellness studios can still be booked as paid tickets.").font(.system(size: 15))
            case .unknown:
                ProgressView()
            }
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Membership (display-only)

struct MembershipView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let ms = m.membership
        List {
            Section(m.cityName) {
                kv("\((ms?.membershipTier ?? "—").capitalized) membership", price(ms))
                kv("Next payment", ms?.nextPayment.map { String($0.prefix(10)) } ?? "—")
                kv("Access until", ms?.admissionAccessUntil.map { String($0.prefix(10)) } ?? "—")
            }
            Section {
                NavigationLink(value: SheetRoute.plans) { InfoRow(title: "Change membership", subtitle: "Move to another level", chevron: false) }
                NavigationLink(value: SheetRoute.pause) { InfoRow(title: "Pause membership", subtitle: "\(ms?.remainingPauseDays ?? 0) unused days", chevron: false) }
                Button { m.flash("Membership changes are display-only in this client") } label: { InfoRow(title: "Cancel membership", subtitle: "Cancel your membership") }
                Button { m.flash("Membership changes are display-only in this client") } label: { InfoRow(title: "Withdraw from contract", subtitle: Copy.withdrawal) }
            } footer: {
                Text("Membership changes are display-only in this unofficial client.")
            }
        }
        .sheetChrome("Membership")
    }

    func price(_ ms: BruceAPI.MembershipInfo?) -> String {
        guard let p = ms?.currentMembershipPrice else { return "—" }
        return "\(p >= 10_000 ? p / 100 : p) kr/month"
    }
    func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).fontWeight(.semibold) }
    }
}

// MARK: - Visits

struct VisitsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text(Copy.unlimitedExcluded).italic().font(.system(size: 14)).foregroundStyle(Theme.secondary).padding(.vertical, 12)
                ForEach(groupedByDay(m.pastBookings, date: { $0.class?.start }).reversed(), id: \.0) { day, list in
                    SectionHeaderBar(text: BruceDate.dayHeader(day))
                    ForEach(list) { b in
                        if let c = b.class { ClassRow(c: c, showMenu: false) }
                    }
                }
                if m.pastBookings.isEmpty { EmptyState(system: "figure.walk", text: "No visits yet.") }
            }
        }
        .sheetChrome("Total monthly visits")
        .task { await m.loadVisits() }
    }
}

// MARK: - Credits (display-only)

struct CreditsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text("CREDITS").font(Theme.screenTitle(36))
                    Text("Pay as you go.\nNo monthly fee.").font(.system(size: 17)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).frame(height: 200)
                .background(RoundedRectangle(cornerRadius: 26).fill(Theme.creditsBeige))
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                InfoRow(title: "Remaining credits", subtitle: "\(m.membership?.availableCredits ?? 0)", chevron: false)
                Button { m.flash("Purchases are disabled in this app") } label: { InfoRow(title: "Buy credits", subtitle: "Choose amount") }
            }
            Section("Credits") {
                ForEach(["No membership needed", "Use them like single tickets", "Expire after 12 months"], id: \.self) { t in
                    Label(t, systemImage: "checkmark.seal.fill")
                }
            }
        }
        .sheetChrome("Credits")
    }
}

// MARK: - Strikes

struct StrikesView: View {
    @Environment(AppModel.self) var m
    var count: Int { m.blockInfo?.strikeCount ?? 0 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 0) {
                        ForEach(0..<Policy.strikesToBlock, id: \.self) { i in
                            if i > 0 { Rectangle().fill(Theme.tertiary).frame(width: 24, height: 2) }
                            Image(systemName: "xmark").font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(i < count ? .white : .clear)
                                .frame(width: 66, height: 66)
                                .background(Circle().fill(i < count ? Theme.strikeRed : .clear))
                                .glassEffect(.regular, in: .circle)
                        }
                    }
                    Text("\(count) strike\(count == 1 ? "" : "s")").font(.system(size: 38, weight: .black).width(.expanded))
                        .foregroundStyle(count > 0 ? Theme.strikeRed : Theme.teal)
                    Text(Copy.strikeSummary(m.blockInfo, unlockPrice: m.unblockPriceKr))
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                Text("STRIKE POLICY").font(Theme.heading(20)).padding(.top, 6)
                policy("No strikes", Theme.teal, Copy.strikeFree.map { (nil, $0) })
                policy("1 strike", Theme.secondary, Copy.strikeOne)
                policy("2 strikes", Theme.hoursOrange, Copy.strikeTwo)
                policy("3 strikes", Theme.strikeRed, Copy.strikeThree)
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Strikes")
        .task { if m.blockInfo == nil { await m.loadAccount() } }
    }

    func policy(_ title: String, _ color: Color, _ items: [(String?, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(color)
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text("•")
                    Text("\(Text(items[i].0 ?? "").fontWeight(.semibold))\(items[i].1)").font(.system(size: 15))
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

// MARK: - Payment methods (display-only)

struct PaymentMethodsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(m.paymentMethods) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.type == "APPLE_PAY" ? "Apple Pay" : (p.type ?? "Card").capitalized).font(.system(size: 18, weight: .semibold))
                            if let e = p.expiryDisplay { Text("Expiry date: \(e)").font(.system(size: 14)).foregroundStyle(Theme.secondary) }
                        }
                        Spacer()
                        Text(p.name ?? "").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.background)
                            .frame(width: 54, height: 30).background(RoundedRectangle(cornerRadius: 6).fill(Theme.ink))
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }
                if m.paymentMethods.isEmpty { EmptyState(system: "creditcard", text: "No payment methods.") }
                Button("Change card") { m.flash("Payment changes are disabled in this app") }.buttonStyle(.glass)
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Payment methods")
    }
}

// MARK: - Statistics & receipts

struct StatisticsView: View {
    @Environment(AppModel.self) var m
    @State private var visits: [BruceAPI.Visit]?
    @State private var month = BruceDate.calendar.dateInterval(of: .month, for: Date())?.start ?? Date()

    var body: some View {
        let shown = (visits ?? []).filter { $0.date.map { BruceDate.calendar.isDate($0, equalTo: month, toGranularity: .month) } == true }
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                WrappedBanner().padding(.horizontal, Theme.gutter).padding(.top, 8)
                NavigationLink(value: SheetRoute.goals) {
                    InfoRow(title: "\(BruceDate.format(Date(), "MMMM")) goals", subtitle: goalsSubtitle)
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                VisitBarChart(months: m.monthlyVisits, selection: $month).padding(.top, 12).padding(.bottom, 28)
                ForEach(groupedByDay(shown, date: \.date).reversed(), id: \.0) { day, list in
                    Section {
                        ForEach(Array(list.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }.enumerated()), id: \.1.id) { i, v in
                            if i > 0 { Divider().padding(.leading, Theme.gutter + 72) }
                            VisitRow(v: v)
                        }
                    } header: {
                        SectionHeaderBar(text: BruceDate.dayHeader(day))
                    }
                }
                if visits == nil {
                    ProgressView().padding(.top, 30)
                } else if shown.isEmpty {
                    EmptyState(system: "figure.walk", text: "No visits in \(BruceDate.format(month, "MMMM")).")
                }
            }
        }
        .sheetChrome("Statistics")
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    var goalsSubtitle: String {
        guard !m.goals.isEmpty else { return "Set a monthly goal" }
        let g = m.goalsMonth()
        return "\(g.done) of \(g.target) · \(g.status)"
    }

    func load(force: Bool = false) async {
        async let a: Void = m.loadAggregate()
        visits = await m.fetchVisitHistory(force: force)
        await a
    }
}

/// A past visit as the original lists it: time (and length for a class), title, studio, area | instructor.
struct VisitRow: View {
    @Environment(AppModel.self) var m
    let v: BruceAPI.Visit
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(BruceDate.time(v.date)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                if let d = v.durationMinutes { Text("\(d) min").font(.system(size: 15)).foregroundStyle(Theme.secondary) }
            }
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(v.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(m.studioName(for: v)).font(.system(size: 15)).lineLimit(1)
                let meta = m.visitMeta(v)
                if !meta.isEmpty { Text(meta).font(.system(size: 15)).foregroundStyle(Theme.secondary).lineLimit(1) }
            }
            .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14).padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
    }
}

struct ReceiptsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        List {
            ForEach(m.payments.filter { ($0.amount ?? 0) > 0 }) { p in
                Button { m.openReceipt(p) } label: {
                    InfoRow(title: p.title, subtitle: BruceDate.format(p.createdAt.flatMap(BruceDate.parse), "d MMM yyyy")) {
                        Text("\((p.amount ?? 0) / 100) \(p.currency ?? "SEK")").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                }
            }
            if m.payments.isEmpty { Text("No payments.").foregroundStyle(Theme.secondary) }
        }
        .sheetChrome("Receipts")
        .quickLookPreview(Binding(get: { m.receiptURL }, set: { m.receiptURL = $0 }))
        .task { await m.loadPayments() }
    }
}

// MARK: - Dark account sub-pages (display-only)

struct EditProfileView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    @State private var home = ""
    @State private var secondary = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 10) {
                    Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 110)
                    Text(m.user?.photoValid == false ? "Photo pending" : "Photo approved").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                Text("Personal info").font(.system(size: 18, weight: .bold)).padding(.top, 20)
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.user?.fullName ?? "")
                    Text(maskedNationalID(m.user?.nationalIdentity)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                HStack(spacing: 8) {
                    Text("Email").font(.system(size: 18, weight: .bold))
                    if m.user?.emailConfirmed == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(.black, Theme.lime) }
                }
                .padding(.top, 10)
                field("Email", $email)
                Text("Home address").font(.system(size: 18, weight: .bold)).padding(.top, 10)
                field("Home address", $home)
                Text("Secondary address").font(.system(size: 18, weight: .bold)).padding(.top, 10)
                field("Secondary address", $secondary)
                Label(Copy.locationUse, systemImage: "info.circle")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).padding(.top, 6)
            }
            .padding(Theme.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            Button { m.flash("Saving the profile is not available here") } label: {
                Text("Save").font(.system(size: 17, weight: .bold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent).tint(Theme.neonLime).controlSize(.large).padding(Theme.gutter)
        }
        .sheetChrome("Edit profile")
        .onAppear { email = m.user?.email ?? "" }
    }

    func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 17)).padding(.horizontal, 16).frame(height: 52)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

struct PauseMembershipView: View {
    @Environment(AppModel.self) var m
    @State private var picking = false
    var daysLeft: Int { m.membership?.remainingPauseDays ?? 0 }
    var periodsLeft: Int { m.membership?.remainingPausePeriods ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(Copy.pauseRules(m.membership))
                .font(.system(size: 16))
            GlassEffectContainer {
                HStack(spacing: 16) {
                    box("Pause days", daysLeft)
                    box("Pause periods", periodsLeft)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(Theme.gutter)
        .safeAreaInset(edge: .bottom) {
            Button { picking = true } label: {
                Text("Add pause").font(.system(size: 17, weight: .bold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent).tint(Theme.neonLime).controlSize(.large).padding(Theme.gutter)
        }
        .sheetChrome("Pause membership")
        .sheet(isPresented: $picking) {
            PauseRangePicker(daysLeft: daysLeft) { picking = false }
                .presentationDetents([.large]).environment(\.colorScheme, .dark)
        }
        .onAppear { if m.demoPausePicker { picking = true; m.demoPausePicker = false } }
    }

    func box(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 14) {
            Text(title).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            Text("\(value)").font(.system(size: 34, weight: .black).width(.expanded))
        }
        .frame(width: 140, height: 124)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

/// Date-range picker with olive range and lime end day (copied layout from macOS). Never sends anything.
struct PauseRangePicker: View {
    @Environment(AppModel.self) var m
    let daysLeft: Int
    var done: () -> Void
    @State private var month: Date = BruceDate.calendar.date(byAdding: .month, value: 1, to: Date())!
    @State private var start: Date?
    @State private var end: Date?

    var cal: Calendar { BruceDate.calendar }
    var earliest: Date { m.membership?.nextPayment.flatMap(BruceDate.parse).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Date()) }
    var selectedDays: Int { guard let s = start else { return 0 }; return (cal.dateComponents([.day], from: s, to: end ?? s).day ?? 0) + 1 }
    var latestEnd: Date? { start.flatMap { cal.date(byAdding: .day, value: daysLeft - 1, to: $0) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    dateLine("Start date", start)
                    dateLine("End date", end)
                    Text("Pause days left: \(max(0, daysLeft - selectedDays))").font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 16) {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
                    VStack(spacing: 0) {
                        Text(BruceDate.format(month, "MMMM").uppercased()).font(Theme.heading(22))
                        Text(BruceDate.format(month, "yyyy")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(minWidth: 170)
                    Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass)
                }
                grid
                Spacer()
            }
            .padding(Theme.gutter)
            .foregroundStyle(.white)
            .navigationTitle("Pause membership").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(role: .cancel, action: done) }
                ToolbarItem(placement: .topBarTrailing) { Button("Clear") { start = nil; end = nil }.tint(Theme.red) }
                ToolbarItem(placement: .bottomBar) {
                    Button { m.flash("Pausing is not available here"); done() } label: { Text("Done").fontWeight(.bold).foregroundStyle(.black).frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).tint(Theme.neonLime).disabled(end == nil)
                }
            }
        }
    }

    func dateLine(_ label: String, _ d: Date?) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 16, weight: .semibold))
            Text(d.map { BruceDate.format($0, "MMMM d, yyyy") } ?? "Pick dates").font(.system(size: 15)).foregroundStyle(.white.opacity(d == nil ? 0.5 : 0.85))
        }
    }

    var days: [Date?] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first)! }
    }

    var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(["mon", "tue", "wed", "thu", "fri", "sat", "sun"], id: \.self) {
                Text($0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).frame(height: 26)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                if let d { dayCell(d) } else { Color.clear.frame(height: 40) }
            }
        }
    }

    func dayCell(_ d: Date) -> some View {
        let enabled = d >= earliest && (start == nil || end != nil || (d >= start! && d <= (latestEnd ?? d)))
        let inRange = start.map { s in d >= s && d <= (end ?? s) } ?? false
        let isEnd = end.map { cal.isDate($0, inSameDayAs: d) } ?? (start.map { cal.isDate($0, inSameDayAs: d) } ?? false)
        return Button {
            if start == nil || end != nil { start = d; end = nil }
            else if d < start! { start = d }
            else { end = d }
        } label: {
            ZStack {
                if inRange { Rectangle().fill(Theme.oliveRange) }
                if isEnd { Circle().fill(Theme.neonLime).padding(-2) }
                Text("\(cal.component(.day, from: d))").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnd ? .black : enabled ? .white : .white.opacity(0.3))
            }
            .frame(height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

/// Plans with live prices from GET /v52/membership/info (per tier, 12-month commitment). Display-only:
/// upgrading is an account change. No hard-coded prices or feature counts.
struct MembershipPlansView: View {
    @Environment(AppModel.self) var m
    @State private var annual = true
    @State private var tierIndex = 0
    @State private var loaded = false

    var plan: PlanInfo { PlanInfo.all[tierIndex] }
    var price: (annual: Int, monthly: Int)? { m.planPrices[plan.code] }
    var isCurrent: Bool { m.tier == plan.code }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("", selection: $annual) { Text("Monthly").tag(false); Text("Annual").tag(true) }.pickerStyle(.segmented)
                Picker("", selection: $tierIndex) { ForEach(PlanInfo.all.indices, id: \.self) { Text(PlanInfo.all[$0].code.capitalized).tag($0) } }
                    .pickerStyle(.segmented)
                card
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Membership")
        .onAppear { tierIndex = PlanInfo.all.firstIndex { $0.code == m.tier } ?? 0 }
        .task { await m.loadPlanPrices(); loaded = true }
    }

    var card: some View {
        let en = Locale(identifier: "en_US")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(plan.code).font(.system(size: 34, weight: .black).width(.expanded))
                Spacer()
                if let p = price, annual, p.monthly > p.annual {
                    Text("Save SEK \(((p.monthly - p.annual) * 12).formatted(.number.locale(en)))").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.tealPrice)
                        .padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.tint(Theme.tealPrice.opacity(0.25)), in: .capsule)
                }
            }
            Text(plan.blurb).font(.system(size: 15))
            if let p = price {
                if annual && p.monthly > p.annual {
                    Text("SEK \(p.monthly.formatted(.number.locale(en)))").strikethrough().font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text((annual ? p.annual : p.monthly).formatted(.number.locale(en))).font(.system(size: 60, weight: .black))
                    Text("SEK / mo").font(.system(size: 16))
                }
                .foregroundStyle(Theme.tealPrice)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text("Price not available").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            Button { if !isCurrent { m.flash("Changing plans is display-only in this client") } } label: {
                Text(isCurrent ? "Current plan" : "Upgrade to \(plan.code.capitalized) \(annual ? "Annual" : "Monthly")")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent).tint(isCurrent ? Theme.olive : Theme.neonLime).controlSize(.large)
            if let n = m.planStudioCount(plan.code) {
                Label("\(n) studios in \(m.cityName)", systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold))
            }
            if isCurrent, let s = m.simultaneousLimit {
                Label("\(s) bookings at a time", systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold))
            }
            if isCurrent, let w = m.wellnessLimit?.total, w > 0 {
                Label("Up to \(w) Wellness visits / month", systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }
}
