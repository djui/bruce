import SwiftUI

extension Theme {
    static let darkBG = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255)
    static let darkCard = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    static let darkField = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    static let olive = Color(red: 0x84 / 255, green: 0x99 / 255, blue: 0x3E / 255)
    static let oliveRange = Color(red: 0x6E / 255, green: 0x7E / 255, blue: 0x38 / 255)
    static let neonLime = Color(red: 0xDA / 255, green: 0xFC / 255, blue: 0x55 / 255)
    static let tealPrice = Color(red: 0x1F / 255, green: 0xB5 / 255, blue: 0x8F / 255)
}

/// Dark nav bar used by the account sub-pages (Edit profile, Pause, Membership plans).
struct DarkNavBar<Trailing: View>: View {
    @Environment(AppModel.self) var m
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ZStack {
            Text(title).font(.system(size: 19, weight: .bold))
            HStack {
                IconButton(system: "chevron.left", size: 20) { m.sheets.count > 1 ? m.popSheet() : m.dismissSheets() }
                Spacer()
                trailing
            }
        }
        .frame(height: 56).padding(.horizontal, Theme.gutter)
    }
}

extension DarkNavBar where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Edit profile (display-only)


struct EditProfileView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    @State private var home = ""
    @State private var secondary = ""

    var body: some View {
        VStack(spacing: 0) {
            DarkNavBar(title: "Edit profile")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 10) {
                        Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 116)
                        Text(m.user?.photoValid == false ? "Photo pending" : "Photo approved").font(.system(size: 16, weight: .light))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 6)
                    Text("Personal Info").font(.system(size: 18, weight: .bold)).padding(.top, 50)
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(m.user?.fullName ?? "")
                            Text(maskedNationalID(m.user?.nationalIdentity))
                        }
                        .font(.system(size: 16, weight: .light))
                        Spacer()
                        Text("BankID").font(.system(size: 13, weight: .heavy)).italic()
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.8)))
                    }
                    .padding(.top, 14)
                    HStack(spacing: 8) {
                        Text("Email").font(.system(size: 18, weight: .bold))
                        if m.user?.emailConfirmed == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.green)
                        }
                    }
                    .padding(.top, 30)
                    darkField("Email", text: $email).padding(.top, 14)
                    Text("Home address").font(.system(size: 18, weight: .bold)).padding(.top, 30)
                    darkField("Home address", text: $home, clear: true).padding(.top, 14)
                    Text("Secondary address").font(.system(size: 18, weight: .bold)).padding(.top, 30)
                    darkField("Secondary address", text: $secondary).padding(.top, 14)
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "info.circle").font(.system(size: 22, weight: .ultraLight))
                        Text(Copy.locationUse)
                            .font(.system(size: 16, weight: .light)).foregroundStyle(Color.white.opacity(0.45))
                    }
                    .padding(.top, 26)
                    Button { m.flash("Saving the profile is not available here") } label: {
                        Text("Save").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Theme.neonLime))
                    }
                    .buttonStyle(.plain).padding(.top, 50).padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear { email = m.user?.email ?? "" }
    }

    func darkField(_ placeholder: String, text: Binding<String>, clear: Bool = false) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.35)))
                .textFieldStyle(.plain).font(.system(size: 17, weight: .light))
            if clear && !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.white.opacity(0.6)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.darkField))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.6)))
    }
}

// MARK: - Pause membership (display-only)

struct PauseMembershipView: View {
    @Environment(AppModel.self) var m
    @State private var picking = false

    var daysLeft: Int { m.membership?.remainingPauseDays ?? 0 }
    var periodsLeft: Int { m.membership?.remainingPausePeriods ?? 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                DarkNavBar(title: "Pause membership") {
                    IconButton(system: "info.circle", size: 22) { m.flash("Pauses apply from your next billing period") }
                }
                Text(Copy.pauseRules(m.membership))
                    .font(.system(size: 17, weight: .light)).lineSpacing(3).padding(.horizontal, 16).padding(.top, 20)
                HStack(spacing: 20) {
                    box("Pause days", daysLeft)
                    box("Pause periods", periodsLeft)
                }
                .frame(maxWidth: .infinity).padding(.top, 22)
                Spacer()
                Button { picking = true } label: {
                    Text("Add pause").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Theme.neonLime))
                }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 30)
            }
            if picking {
                Color.black.opacity(0.3).onTapGesture { picking = false }
                PauseRangePicker(daysLeft: daysLeft, done: { picking = false })
                    .padding(.horizontal, 2).padding(.bottom, 60).transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.2), value: picking)
        .onAppear { if m.demoPausePicker { picking = true; m.demoPausePicker = false } }
    }

    func box(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 20) {
            Text(title).font(.system(size: 15, weight: .light)).foregroundStyle(Color.white.opacity(0.75))
            Text("\(value)").font(.system(size: 30, weight: .heavy).width(.expanded))
        }
        .frame(width: 124, height: 124)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.9), lineWidth: 1))
    }
}

/// Dark date-range sheet ("Pick dates" → start/end, olive range, lime end day). Never sends anything.
struct PauseRangePicker: View {
    @Environment(AppModel.self) var m
    let daysLeft: Int
    var done: () -> Void
    @State private var month: Date = BruceDate.calendar.date(byAdding: .month, value: 1, to: Date())!
    @State private var start: Date?
    @State private var end: Date?

    var cal: Calendar { BruceDate.calendar }
    /// Earliest selectable day: the next billing period (pauses can't start in the current one).
    var earliest: Date { m.membership?.nextPayment.flatMap(BruceDate.parse).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Date()) }
    var selectedDays: Int { guard let s = start else { return 0 }; return (cal.dateComponents([.day], from: s, to: end ?? s).day ?? 0) + 1 }
    var latestEnd: Date? { start.flatMap { cal.date(byAdding: .day, value: daysLeft - 1, to: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Pause membership").font(.system(size: 19, weight: .bold))
                HStack { Spacer(); Button { start = nil; end = nil } label: { Text("Clear").underline().foregroundStyle(Color.red) }.buttonStyle(.plain) }
            }
            .padding(.top, 26).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 12) {
                dateLine("Start date", start)
                dateLine("End date", end)
                Text("Pause days left: \(max(0, daysLeft - selectedDays))").font(.system(size: 16, weight: .light))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 22)
            HStack(spacing: 20) {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "arrowshape.left.fill") }.buttonStyle(.plain)
                Text(BruceDate.format(month, "MMMM")).font(.system(size: 26, weight: .bold)).frame(minWidth: 150)
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "arrowshape.right.fill") }.buttonStyle(.plain)
            }
            .font(.system(size: 18)).padding(.top, 18)
            Text(BruceDate.format(month, "yyyy")).font(.system(size: 15, weight: .semibold)).padding(.top, 4)
            grid.padding(.top, 14)
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1).padding(.top, 12)
            HStack(spacing: 0) {
                Button(action: done) { Text("Cancel").frame(maxWidth: .infinity, minHeight: 50) }.buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 50)
                Button { m.flash("Pausing is not available here"); done() } label: {
                    Text("Done").frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(end == nil ? Color.white.opacity(0.35) : .white)
                }
                .buttonStyle(.plain).disabled(end == nil)
            }
            .font(.system(size: 17))
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.11, green: 0.12, blue: 0.12)))
    }

    func dateLine(_ label: String, _ d: Date?) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 17, weight: .semibold))
            if let d { Text(BruceDate.format(d, "MMMM d, yyyy")).underline().font(.system(size: 16, weight: .light)).foregroundStyle(Color.white.opacity(0.8)) }
            else { Text("Pick dates").font(.system(size: 16, weight: .light)).foregroundStyle(Color.white.opacity(0.6)) }
        }
    }

    var days: [Date?] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first)! }
    }

    var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(["mon", "tue", "wed", "thu", "fri", "sat", "sun"], id: \.self) {
                Text($0).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(0.6)).frame(height: 28)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                if let d { dayCell(d) } else { Color.clear.frame(height: 40) }
            }
        }
        .padding(.horizontal, 6)
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
                if isEnd { Circle().fill(Theme.neonLime).overlay(Circle().stroke(Color.black.opacity(0.5))).padding(-2) }
                Text("\(cal.component(.day, from: d))").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnd ? .black : enabled ? .white : Color.white.opacity(0.3))
            }
            .frame(height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - Membership plans (display-only)


struct MembershipPlansView: View {
    @Environment(AppModel.self) var m
    @State private var annual = true
    @State private var tierIndex = 0

    var plan: PlanInfo { PlanInfo.all[tierIndex] }
    var price: (annual: Int, monthly: Int) {
        if let p = m.planPrices[plan.code] { return p }
        return (plan.annual, plan.monthly)
    }
    var isCurrent: Bool { m.tier == plan.code && annual == ((m.membershipCommitmentMonths ?? 12) >= 12) }

    var body: some View {
        VStack(spacing: 0) {
            DarkNavBar(title: "Membership")
            ScrollView {
                VStack(spacing: 22) {
                    segmented(["Monthly", "Annual"], selected: annual ? 1 : 0, big: true) { annual = $0 == 1 }
                    segmented(["Base", "Black", "Epic"], selected: tierIndex, big: false) { tierIndex = $0 }
                    card
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .onAppear { tierIndex = PlanInfo.all.firstIndex { $0.code == m.tier } ?? 0 }
        .task { await m.loadPlanPrices() }
    }

    func segmented(_ items: [String], selected: Int, big: Bool, _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(items[i]).font(.system(size: big ? 22 : 17, weight: big ? .bold : .medium))
                        .foregroundStyle(big && selected == i ? Color.black : .white)
                        .frame(maxWidth: .infinity).frame(height: big ? 44 : 42)
                        .background(Capsule().fill(selected == i ? (big ? Color.white : Theme.darkBG) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(big ? Color.clear : Theme.darkCard))
        .overlay(Capsule().stroke(big ? Color.white.opacity(0.6) : .clear))
    }

    var card: some View {
        let p = price
        let shown = annual ? p.annual : p.monthly
        let save = (p.monthly - p.annual) * 12
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(plan.code).font(.system(size: 34, weight: .heavy).width(.expanded))
                Spacer()
                if annual && save > 0 {
                    Text("Save SEK \(save.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))))")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.tealPrice)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.tealPrice.opacity(0.15)))
                }
            }
            Text(plan.blurb).font(.system(size: 16, weight: .light))
            if annual && p.monthly > p.annual {
                Text("SEK \(p.monthly.formatted(.number.locale(Locale(identifier: "en_US"))))").strikethrough()
                    .font(.system(size: 26, weight: .light)).foregroundStyle(Color.white.opacity(0.75))
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(shown.formatted(.number.locale(Locale(identifier: "en_US")))).font(.system(size: 64, weight: .heavy))
                Text("SEK / mo").font(.system(size: 17, weight: .light))
            }
            .foregroundStyle(Theme.tealPrice)
            Button { if !isCurrent { m.flash("Changing plans is not available here") } } label: {
                Text(isCurrent ? "Current plan" : "Upgrade to \(plan.code.capitalized) \(annual ? "Annual" : "Monthly")")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(isCurrent ? Color.black.opacity(0.55) : .black)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Capsule().fill(isCurrent ? Theme.olive : Theme.neonLime))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 22) {
                feature("\(m.planStudioCount(plan.code) ?? plan.studios) studios in \(m.cityName)", m.studios.isEmpty ? nil : "\(m.studios.count) studios in the country", info: true)
                feature("Unlimited visits at STC gyms", m.planUnlimitedCount(plan.code).map { "\($0) studios with unlimited visits in \(m.cityName)" })
                feature("\(isCurrent ? (m.simultaneousLimit ?? plan.bookings) : plan.bookings) bookings at a time", nil)
                if plan.wellness > 0 { feature("Access to Wellness studios", "Up to \(isCurrent ? (m.wellnessLimit?.total.flatMap { $0 > 0 ? $0 : nil } ?? plan.wellness) : plan.wellness) Wellness visits / month", info: true) }
            }
            .padding(.top, 10)
            Text("No joining fee").font(.system(size: 15, weight: .light)).padding(.top, 14)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.darkCard))
    }

    func feature(_ title: String, _ sub: String?, info: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.black, .white)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    if info { Image(systemName: "info.circle").font(.system(size: 15, weight: .light)).foregroundStyle(Color.white.opacity(0.7)) }
                }
                if let sub { Text(sub).font(.system(size: 14, weight: .light)) }
            }
        }
    }
}

// MARK: - Statistics & receipts

struct StatisticsView: View {
    @Environment(AppModel.self) var m
    @State private var visits: [BruceAPI.Visit]?
    @State private var month = BruceDate.calendar.dateInterval(of: .month, for: Date())?.start ?? Date()

    var body: some View {
        let shown = (visits ?? []).filter { $0.date.map { BruceDate.calendar.isDate($0, equalTo: month, toGranularity: .month) } == true }
        let groups = Dictionary(grouping: shown) { BruceDate.calendar.startOfDay(for: $0.date ?? .distantPast) }
        VStack(spacing: 0) {
            NavBar(title: "Statistics") { m.popSheet() }
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    VisitBarChart(months: m.monthlyVisits, selection: $month).padding(.top, 12).padding(.bottom, 28)
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        Section {
                            ForEach(groups[day]!.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) { v in
                                ClassRow(time: BruceDate.time(v.date), duration: v.durationMinutes.map { "\($0) min" } ?? "",
                                         title: v.title, studio: m.studioName(for: v), meta: m.visitMeta(v), showMenu: false)
                            }
                        } header: {
                            SectionHeaderBar(text: BruceDate.dayHeader(day))
                        }
                    }
                    if visits == nil {
                        ProgressView().padding(.top, 30)
                    } else if shown.isEmpty {
                        Text("No visits in \(BruceDate.format(month, "MMMM")).").foregroundStyle(Theme.secondary).padding(.top, 30)
                    }
                }
            }
        }
        .task {
            async let a: Void = m.loadAggregate()
            visits = await m.fetchVisitHistory()
            await a
        }
    }
}

struct ReceiptsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Receipts") { m.popSheet() }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(m.payments.filter { ($0.amount ?? 0) > 0 }) { p in
                        Button { m.openReceipt(p) } label: {
                            InfoRow(title: p.title, subtitle: BruceDate.format(p.createdAt.flatMap(BruceDate.parse), "d MMM yyyy")) {
                                Text("\((p.amount ?? 0) / 100) \(p.currency ?? "SEK")").font(.system(size: 16, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if m.payments.isEmpty { Text("No payments.").foregroundStyle(Theme.secondary).padding(.top, 30) }
                }
            }
        }
        .task { await m.loadPayments() }
    }
}
