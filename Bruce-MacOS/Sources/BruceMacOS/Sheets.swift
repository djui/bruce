import SwiftUI

// MARK: - Notifications

struct NotificationsSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Notifications", leading: .close) { m.dismissSheets() }
            let groups = Dictionary(grouping: m.notifications) { BruceDate.calendar.startOfDay(for: $0.date ?? .distantPast) }
            if m.notifications.isEmpty {
                EmptyState(system: "bell", text: m.isLoggedIn ? "No notifications." : "Log in to see notifications.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                            Text(BruceDate.dayHeader(day)).font(.system(size: 17, weight: .light)).padding(.top, 14)
                            ForEach(groups[day]!.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) { n in
                                // Opens the class the notification is about, else its studio.
                                Button { Task { await m.openNotification(n) } } label: { card(n) }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
                }
            }
        }
        .task { await m.loadSocial() }
        .onDisappear { m.markNotificationsSeen() }
    }

    func card(_ n: BruceAPI.BruceNotification) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if let photo = n.meta?.photo ?? n.meta?.userPhoto {
                Avatar(fileId: photo, size: 64)
            } else {
                Circle().fill(Color.black).frame(width: 64, height: 64)
                    .overlay(Text("B").font(.system(size: 40, weight: .black).width(.expanded)).foregroundStyle(.white))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(n.title ?? "").font(.system(size: 17, weight: .bold))
                Text(n.message ?? "").font(.system(size: 17, weight: .light)).lineSpacing(6).padding(.leading, 10)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 10) {
                Text(BruceDate.time(n.date)).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary)
                if m.isNew(n) { Circle().fill(Color.red).frame(width: 6, height: 6).padding(.trailing, 20) }
            }
        }
        .padding(20).frame(minHeight: 200, alignment: .top)
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

// MARK: - Hamburger menu

struct MenuSheet: View {
    @Environment(AppModel.self) var m
    let rows: [(String, String, SheetRoute?)] = [
        ("person.crop.circle", "Account", .account),
        ("gearshape", "Settings", .settings),
        ("person.2", "Invite friends", .invite),
        ("gift", "Redeem voucher", .voucher),
        ("bubble.left.and.bubble.right", "Chat with support", .support),
        ("questionmark.circle", "FAQ", .help),
        ("camera", "Community", .info("Community")),
        ("square.on.square", "Gift cards", .info("Gift cards")),
    ]
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.85)).frame(width: 92, height: 8).padding(.top, 12).padding(.bottom, 18)
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                Button {
                    if r.1 == "Account" && !m.isLoggedIn { m.sheets = [.login] }
                    else if let s = r.2 { m.sheets = [s] }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 30) {
                            Image(systemName: r.0).font(.system(size: 22, weight: .light)).frame(width: 30)
                                .overlay(alignment: .topTrailing) {
                                    if r.1 == "Settings" && m.prefs["pushSetupDone"] != true { Circle().fill(.red).frame(width: 9, height: 9).offset(x: 2, y: -2) }
                                }
                            Text(r.1).font(.system(size: 18, weight: .medium))
                            Spacer()
                        }
                        .frame(height: 76)
                        if i < rows.count - 1 { Rectangle().fill(Theme.divider).frame(height: 0.5) }
                    }
                    .padding(.leading, Theme.gutter).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .background(Color.white)
        .clipShape(UnevenRoundedCorners(radius: 14))
    }
}

// MARK: - Account

struct AccountSheet: View {
    @Environment(AppModel.self) var m
    var visits: BruceAPI.VisitLimit? { m.visitLimits.first { $0.type == "MONTHLY" } ?? m.visitLimits.first }
    var tier: String { m.membership?.membershipTier ?? m.membership?.admissionTier ?? "—" }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Account", leading: .close, action: { m.dismissSheets() }) {
                IconButton(system: "rectangle.portrait.and.arrow.right", size: 20) { Task { await m.logout() } }
            }
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 130)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(m.user?.fullName ?? "Member").font(.system(size: 20, weight: .medium))
                            Text("Member #\(m.user.map { String($0.id) } ?? "—")").font(.system(size: 17, weight: .light)).foregroundStyle(Theme.tertiary)
                            Button { m.pushSheet(.editProfile) } label: { Text("Edit profile").underline() }.buttonStyle(.plain).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                    }
                    .padding(Theme.gutter).padding(.bottom, 10)
                    Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
                    Button { m.pushSheet(.membership) } label: {
                        InfoRow(title: "Membership", subtitle: m.membership?.paused == true ? "Paused" : (m.membership?.membership == true ? "Active" : "—"), chevron: false) {
                            Text(tier.uppercased()).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.baseTag))
                        }
                    }.buttonStyle(.plain)
                    if let w = m.wellnessLimit {
                        Button { m.wellnessOverlay = true } label: {
                            InfoRow(title: "Wellness visits", subtitle: "\(w.used ?? 0) / \(w.total ?? 0)")
                        }.buttonStyle(.plain)
                    }
                    Button { m.pushSheet(.visits) } label: {
                        InfoRow(title: "Total monthly visits", subtitle: "\(visits?.used ?? 0) / \(visits?.total ?? 0)",
                                footnote: Copy.unlimitedExcluded)
                    }.buttonStyle(.plain)
                    Button { m.pushSheet(.credits) } label: {
                        InfoRow(title: "Credits", subtitle: "\(m.membership?.availableCredits ?? 0) credits")
                    }.buttonStyle(.plain)
                    Button { m.pushSheet(.strikes) } label: { InfoRow(title: "Strikes", subtitle: "View your strikes") }.buttonStyle(.plain)
                    Button { m.pushSheet(.payment) } label: { InfoRow(title: "Payment methods", subtitle: "Your payment methods") }.buttonStyle(.plain)
                    Button { m.pushSheet(.statistics) } label: { InfoRow(title: "Statistics", subtitle: "Training history") }.buttonStyle(.plain)
                    Button { m.pushSheet(.receipts) } label: { InfoRow(title: "Receipts", subtitle: "Your payments") }.buttonStyle(.plain)
                }
            }
        }
        .task { await m.loadAccount() }
    }
}


/// Wellness visits from GET /v52/studio/user_visit_limit (WELLNESS_MONTHLY). Plan changes are display-only.
struct WellnessSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let w = m.wellnessLimit
        VStack(alignment: .leading, spacing: 6) {
            Text("Wellness access").font(.system(size: 20, weight: .bold))
            (Text("\(w?.used ?? 0)").foregroundColor(Theme.lime) + Text("/\(w?.total ?? 0)").foregroundColor(Color(white: 0.6)))
                .font(.system(size: 52, weight: .light))
            Text("VISITS USED THIS MONTH").font(.system(size: 13, weight: .semibold)).kerning(1).foregroundStyle(Color(white: 0.6))
        }
        .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkPanel)
        .clipShape(UnevenRoundedCorners(radius: 18))
    }
}

// MARK: - Membership (display-only)

struct MembershipView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let ms = m.membership
        VStack(spacing: 0) {
            NavBar(title: "Membership") { m.popSheet() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Stockholm").font(.system(size: 18, weight: .semibold)).padding(.top, 30).padding(.bottom, 4)
                        kv("\((ms?.membershipTier ?? "—").capitalized) membership", price(ms))
                        kv("Next payment", ms?.nextPayment.map { String($0.prefix(10)) } ?? "—")
                        kv("Access until", ms?.admissionAccessUntil.map { String($0.prefix(10)) } ?? "—")
                    }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 18)
                    Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Renew annual subscription").font(.system(size: 18, weight: .medium))
                            Text(Copy.renewal(ms))
                                .font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: .constant(ms?.prolongCommitment ?? true)).toggleStyle(.switch).tint(Theme.ink).disabled(true).labelsHidden()
                    }
                    .padding(Theme.gutter)
                    Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
                    Button { m.pushSheet(.plans) } label: { InfoRow(title: "Change membership", subtitle: "Move to another level") }.buttonStyle(.plain)
                    Button { m.pushSheet(.pause) } label: { InfoRow(title: "Pause membership", subtitle: "\(ms?.remainingPauseDays ?? 0) unused days") }.buttonStyle(.plain)
                    readOnly("Cancel membership", "Cancel your membership")
                    readOnly("Withdraw from contract", Copy.withdrawal)
                    Text("Membership changes are display-only in this unofficial client.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiary).padding(Theme.gutter)
                }
            }
        }
    }

    func price(_ ms: BruceAPI.MembershipInfo?) -> String {
        guard let p = ms?.currentMembershipPrice else { return "—" }
        let kr = p >= 10_000 ? p / 100 : p
        return "\(kr) kr/month"
    }
    func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.system(size: 17, weight: .light)); Spacer(); Text(v).font(.system(size: 17, weight: .semibold)) }
    }
    func readOnly(_ t: String, _ s: String) -> some View {
        Button { m.flash("Not available here") } label: { InfoRow(title: t, subtitle: s) }.buttonStyle(.plain)
    }
}

// MARK: - Visits

struct VisitsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Total monthly visits") { m.popSheet() }
            Text(Copy.unlimitedExcluded).italic().font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.secondary).padding(.vertical, 18)
            let groups = Dictionary(grouping: m.pastBookings) { BruceDate.calendar.startOfDay(for: $0.class?.start ?? .distantPast) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        SectionHeaderBar(text: BruceDate.dayHeader(day))
                        ForEach(groups[day]!) { b in
                            if let c = b.class {
                                let st = m.studio(c.studioId)
                                ClassRow(time: BruceDate.time(c.start), duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                         title: c.title, studio: st?.name ?? "",
                                         meta: [st?.vicinity, c.instructor].compactMap { $0 }.joined(separator: "  |  "), showMenu: false)
                            }
                        }
                    }
                    if m.pastBookings.isEmpty { Text("No visits yet.").foregroundStyle(Theme.secondary).padding(.top, 40) }
                }
            }
        }
        .task { await m.loadVisits() }
    }
}

// MARK: - Credits (display-only)

struct CreditsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "") { m.popSheet() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        Text("Credits").font(.system(size: 44, weight: .bold))
                        Text("Pay as you go.\nNo monthly fee.").font(.system(size: 19, weight: .light)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).frame(height: 300)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.creditsBeige))
                    .padding(.horizontal, Theme.gutter)
                    InfoRow(title: "Remaining credits", subtitle: "\(m.membership?.availableCredits ?? 0)", chevron: false)
                    Button { m.flash("Not available here") } label: { InfoRow(title: "History", subtitle: "See previous purchases") }.buttonStyle(.plain)
                    Button { m.flash("Purchases are disabled in this app") } label: { InfoRow(title: "Buy credits", subtitle: "Choose amount") }.buttonStyle(.plain)
                    Text("Credits").font(.system(size: 26, weight: .bold)).padding(.horizontal, Theme.gutter).padding(.top, 30).padding(.bottom, 14)
                    ForEach(["No membership needed", "Use them like single tickets", "Expire after 12 months"], id: \.self) { t in
                        HStack(spacing: 18) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 24))
                            Text(t).font(.system(size: 18, weight: .medium))
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Strikes

struct StrikesView: View {
    @Environment(AppModel.self) var m
    var count: Int { m.blockInfo?.strikeCount ?? 0 }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        NavBar(title: "Strikes", leading: .back) { m.popSheet() }.padding(.horizontal, -Theme.gutter)
                        HStack(spacing: 0) {
                            ForEach(0..<Policy.strikesToBlock, id: \.self) { i in
                                if i > 0 { Rectangle().fill(Color(white: 0.6)).frame(width: 26, height: 2) }
                                Circle().fill(i < count ? Theme.ink : Color.white)
                                    .overlay(Circle().stroke(Color(white: 0.65), lineWidth: i < count ? 0 : 2))
                                    .overlay(Image(systemName: "xmark").font(.system(size: 24, weight: .light)).foregroundStyle(.white).opacity(i < count ? 1 : 0))
                                    .frame(width: 74, height: 74)
                            }
                        }
                        .padding(.top, 30)
                        Text("\(count) strike\(count == 1 ? "" : "s")").font(.system(size: 42, weight: .bold))
                            .foregroundStyle(count > 0 ? Theme.strikeRed : Color(red: 0.05, green: 0.5, blue: 0.2)).padding(.top, 28)
                        Text(Copy.strikeSummary(m.blockInfo, unlockPrice: m.unblockPriceKr))
                            .font(.system(size: 18, weight: .semibold)).lineSpacing(5).padding(.top, 14).padding(.bottom, 36)
                    }
                    .padding(.horizontal, Theme.gutter + 12)
                    .background(Color(white: 0.91))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Strike policy").font(.system(size: 30, weight: .bold)).padding(.top, 36)
                        policy("No strikes", Color(red: 0.05, green: 0.5, blue: 0.2), Copy.strikeFree.map { (nil, $0) })
                        Divider()
                        policy("1 strike", Color(white: 0.45), Copy.strikeOne)
                        Divider()
                        policy("2 strikes", Color(red: 0.62, green: 0.45, blue: 0.0), Copy.strikeTwo)
                    }
                    .padding(.horizontal, Theme.gutter + 12).padding(.bottom, 30)
                }
            }
        }
        .task { if m.blockInfo == nil { await m.loadAccount() } }
    }

    func policy(_ title: String, _ color: Color, _ items: [(String?, String)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(color)
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Text("•")
                    (Text(items[i].0 ?? "").fontWeight(.semibold) + Text(items[i].1).fontWeight(.light)).font(.system(size: 17))
                }
            }
        }
        .padding(.vertical, 26)
    }
}

// MARK: - Payment methods (display-only)

struct PaymentMethodsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Payment methods") { m.popSheet() }
            VStack(spacing: 22) {
                ForEach(m.paymentMethods) { p in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.type == "APPLE_PAY" ? "Apple Pay" : (p.type ?? "Card").capitalized).font(.system(size: 19, weight: .medium))
                            if let e = p.expiryDisplay { Text("Expiry date: \(e)").font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary) }
                        }
                        Spacer()
                        if p.type == "APPLE_PAY" {
                            Text(" Pay").font(.system(size: 12, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 4)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.ink, lineWidth: 0.8))
                        }
                        Text(p.name ?? "").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 54, height: 28).background(RoundedRectangle(cornerRadius: 3).fill(Theme.ink))
                    }
                    .padding(.horizontal, 26).padding(.vertical, 18)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 2))
                }
                if m.paymentMethods.isEmpty { Text("No payment methods.").foregroundStyle(Theme.secondary) }
                Text("Change card").underline().font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.tertiary)
                    .help("Payment changes are disabled in this app")
                Spacer()
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 30)
        }
    }
}
