import SwiftUI

/// Big-title text sheet with X on the right ("How it works", "Push settings").
struct TextInfoSheet: View {
    @Environment(AppModel.self) var m
    let title: String
    let paragraphs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title).font(.system(size: 34, weight: .bold))
                Spacer()
                IconButton(system: "xmark", size: 22) { m.sheets.count > 1 ? m.popSheet() : m.dismissSheets() }
            }
            .padding(.top, 36).padding(.bottom, 40)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs, id: \.self) { Text($0).font(.system(size: 17, weight: .light)).lineSpacing(12) }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - Invite friends to a class

/// Class page "Invite": pick friends and send them this class (POST /v52/class/<id>/invite).
struct ClassInviteSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    @State private var picked: Set<Int> = []
    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }
    var friends: [BruceAPI.UserLite] {
        m.friends.compactMap(\.friendUser).sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: c?.title ?? "Invite friends", leading: .close, action: { m.dismissSheets() }) {
                if let c {
                    ShareButton(url: ShareURL.forClass(classId, title: c.title))
                }
            }
            SectionHeaderBar(text: "Friends")
            ScrollView {
                VStack(spacing: 0) {
                    if friends.isEmpty {
                        Text(m.isLoggedIn ? "Add friends in Bruce to invite them to classes." : "Log in to invite friends.")
                            .font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary).padding(24)
                    }
                    ForEach(friends, id: \.id) { u in
                        Button {
                            if picked.contains(u.id) { picked.remove(u.id) } else { picked.insert(u.id) }
                        } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 22) {
                                    Avatar(fileId: u.photo, initials: u.initials, size: 64)
                                    Text(u.firstName ?? u.fullName).font(.system(size: 18, weight: .medium))
                                    Spacer()
                                    Image(systemName: picked.contains(u.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                        .font(.system(size: 26, weight: .light))
                                        .foregroundStyle(picked.contains(u.id) ? .black : Theme.secondary)
                                }
                                .padding(.vertical, 14).padding(.trailing, Theme.gutter)
                                Rectangle().fill(Theme.divider).frame(height: 0.5)
                            }
                            .padding(.leading, Theme.gutter).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            LimeButton(title: m.loading ? "Inviting…" : "Invite friends") {
                Task { if await m.inviteToClass(classId, userIds: Array(picked)) { m.dismissSheets() } }
            }
            .disabled(picked.isEmpty || m.loading).opacity(picked.isEmpty ? 0.5 : 1)
            .padding(Theme.gutter)
        }
        .task { if m.friends.isEmpty { await m.loadSocial() } }
    }
}

// MARK: - Invite friends

struct InviteSheet: View {
    @Environment(AppModel.self) var m
    var open: [BruceAPI.Voucher] { m.invites.filter { !$0.accepted } }
    var accepted: [BruceAPI.Voucher] { m.invites.filter { $0.accepted } }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Invite friends", leading: .close, action: { m.dismissSheets() }) {
                IconButton(system: "info.circle", size: 22) { m.pushSheet(.howItWorks) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    Text("Invite a friend").font(.system(size: 36, weight: .bold)).multilineTextAlignment(.center)
                        .padding(.top, 30).padding(.horizontal, 30)
                    Text(Copy.inviteIntro(open: m.openInvites))
                        .font(.system(size: 16, weight: .light)).multilineTextAlignment(.center).lineSpacing(3)
                        .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 40)
                    SectionHeaderBar(text: "Invites")
                    if open.isEmpty {
                        Text(m.isLoggedIn ? "No invite codes left." : "Log in to see your invite codes.")
                            .font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary).padding(24)
                    }
                    ForEach(open) { v in
                        VStack(spacing: 0) {
                            HStack(spacing: 26) {
                                Image(systemName: "gift").font(.system(size: 20, weight: .light))
                                Text(v.code).font(.system(size: 17, weight: .semibold))
                                Spacer()
                                ShareLink(item: Copy.shareInvite(v.code)) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.up").font(.system(size: 17))
                                        Text("Share").font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundStyle(.black).padding(.horizontal, 22).frame(height: 46)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.lime))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 22).padding(.trailing, Theme.gutter)
                            Rectangle().fill(Theme.divider).frame(height: 0.5)
                        }
                        .padding(.leading, Theme.gutter)
                    }
                    if !accepted.isEmpty {
                        SectionHeaderBar(text: "Accepted invites")
                        ForEach(accepted) { v in
                            HStack(spacing: 26) {
                                Circle().fill(Theme.chipGrey).frame(width: 80, height: 80)
                                    .overlay(Image(systemName: "person").font(.system(size: 26, weight: .light)).foregroundStyle(.white))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(friendName(v)).font(.system(size: 18, weight: .semibold))
                                    Text(v.code.uppercased()).font(.system(size: 17, weight: .semibold))
                                }
                                Spacer()
                                Text("Pending").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.secondary)
                            }
                            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task { await m.loadAccount() }
    }

    /// The voucher payload only carries the user id; the name comes from the friend list when possible.
    func friendName(_ v: BruceAPI.Voucher) -> String {
        m.friends.first { $0.friendUser?.id == v.userId }?.friendUser?.firstName ?? "Invited friend"
    }
}


// MARK: - Redeem voucher (display-only)

struct VoucherSheet: View {
    @Environment(AppModel.self) var m
    @State private var code = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Redeem voucher", leading: .close) { m.dismissSheets() }
            VStack(alignment: .leading, spacing: 24) {
                FormField(label: "Voucher code", placeholder: "XXXXXX", text: $code, focused: $focused)
                LimeButton(title: "Activate") { m.flash("Redeeming vouchers is not available here") }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 190)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}

// MARK: - Support (Intercom-style messenger home)


struct SupportSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button { m.dismissSheets() } label: {
                        Image(systemName: "xmark").font(.system(size: 22, weight: .light)).foregroundStyle(.white)
                            .frame(width: 50, height: 50).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)))
                    }.buttonStyle(.plain)
                }
                .padding(.top, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hi \(m.user?.firstName ?? "there") 👋").foregroundStyle(Color.white.opacity(0.6))
                    Text("How can we help?").foregroundStyle(.white)
                }
                .font(.system(size: 30, weight: .bold)).padding(.top, 50).padding(.bottom, 26)
                card {
                    VStack(spacing: 0) {
                        row("Messages", icon: "message.fill") { m.flash("Messages are not available here") }
                        Divider()
                        row("Help", icon: "questionmark.circle.fill") { m.pushSheet(.help) }
                    }
                }
                card {
                    Button { m.flash("Sending messages is not available here") } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Contact Bruce Studios").font(.system(size: 17, weight: .semibold))
                                Text("Through brucestudios.com or the official app").font(.system(size: 16)).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            Image(systemName: "paperplane.fill").font(.system(size: 18))
                        }
                        .padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                card {
                    VStack(spacing: 4) {
                        Button { m.pushSheet(.help) } label: {
                            HStack {
                                Text("Search for help").font(.system(size: 17, weight: .semibold))
                                Spacer()
                                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 14).frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.96)))
                        }.buttonStyle(.plain)
                        ForEach(Copy.helpTopics.prefix(4), id: \.self) { a in
                            row(a, icon: "chevron.right", weight: .regular) { m.pushSheet(.help) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        }
        .background(
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(white: 0.06), Color(red: 0.40, green: 0.43, blue: 0.39), Color(red: 0.70, green: 0.74, blue: 0.68)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 520)
                LinearGradient(colors: [Color(red: 0.86, green: 0.88, blue: 0.85), .white], startPoint: .top, endPoint: .bottom).frame(height: 140)
                Color.white
            }
        )
    }

    func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    func row(_ t: String, icon: String, weight: Font.Weight = .semibold, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(t).font(.system(size: 17, weight: weight))
                Spacer()
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
            }
            .frame(height: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct HelpSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Help and support", leading: m.sheets.count > 1 ? .back : .close,
                   action: { m.sheets.count > 1 ? m.popSheet() : m.dismissSheets() }) {
                IconButton(system: "magnifyingglass", size: 22) { m.flash("Help search is not available here") }
            }
            ScrollView {
                VStack(spacing: 0) {
                    Button { m.flash("Sending messages is not available here") } label: {
                        HStack {
                            Text("Can't find what you need?\nContact Bruce Studios support.").font(.system(size: 16, weight: .light))
                                .lineSpacing(4)
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 22, weight: .light))
                        }
                        .padding(.vertical, 18).padding(.leading, 6).padding(.trailing, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    ForEach(Copy.helpTopics, id: \.self) { t in
                        Divider()
                        Button { m.flash("Help articles are not available here") } label: {
                            HStack {
                                Text(t).font(.system(size: 18, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 16, weight: .medium))
                            }
                            .frame(height: 66).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Divider()
                }
                .padding(.leading, Theme.gutter).padding(.trailing, Theme.gutter)
            }
        }
    }
}

// MARK: - Settings (local toggles only)

struct SettingsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Settings", leading: .close) { m.dismissSheets() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { m.pushSheet(.selectCity) } label: { InfoRow(title: "Change city", subtitle: m.cityName) }.buttonStyle(.plain)
                    toggleRow("Social", (m.social ?? true) ? "Everyone can see your profile" : "Only friends can see your profile",
                              isOn: Binding(get: { m.social ?? true }, set: { m.setSocial($0) }), help: true)
                    toggleRow("Location services", "Used for distances and check-in suggestions", isOn: m.pref("location"))
                    Button { copyCalendarURL() } label: {
                        InfoRow(title: "Calendar Subscription", subtitle: "Subscribe to your bookings in Calendar")
                    }.buttonStyle(.plain)
                    Button { m.prefs["pushSetupDone"] = true; m.pushSheet(.push) } label: {
                        InfoRow(title: "Push notifications", subtitle: m.prefs["pushSetupDone"] == true ? "On" : "Setup needed") {
                            EmptyView()
                        }
                        .overlay(alignment: .topLeading) {
                            if m.prefs["pushSetupDone"] != true {
                                Circle().fill(.red).frame(width: 6, height: 6).offset(x: 220, y: 24)
                            }
                        }
                    }.buttonStyle(.plain)
                    Button { m.pushSheet(.info("Terms and conditions")) } label: {
                        InfoRow(title: "Terms and conditions", subtitle: "Bruce Studios' terms")
                    }.buttonStyle(.plain)
                    Button { m.pushSheet(.info("Privacy policy")) } label: {
                        InfoRow(title: "Privacy policy", subtitle: "How Bruce Studios handles your data")
                    }.buttonStyle(.plain)
                    Button { m.pushSheet(.info("Open source licenses")) } label: {
                        InfoRow(title: "Open source licenses", subtitle: "Third-party notices")
                    }.buttonStyle(.plain)
                    Button { m.flash("Clear data is not available here") } label: {
                        InfoRow(title: "Clear data", subtitle: "Reset locally cached data")
                    }.buttonStyle(.plain)
                    Text("MARKETING").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, Theme.gutter).padding(.top, 34)
                    Text(Copy.marketing)
                        .font(.system(size: 16, weight: .light)).padding(.horizontal, Theme.gutter).padding(.top, 14).padding(.bottom, 8)
                    simpleToggle("Push", isOn: marketing("marketing_push", \.marketingPush))
                    simpleToggle("Email", isOn: marketing("marketing_email", \.marketingEmail))
                    simpleToggle("SMS", isOn: marketing("marketing_sms", \.marketingSms))
                    VStack(spacing: 6) {
                        Text("BruceMacOS · unofficial client, not affiliated with Bruce Studios").foregroundStyle(Theme.tertiary)
                        Link("djui.github.io/bruce", destination: URL(string: "https://djui.github.io/bruce/")!)
                            .foregroundStyle(Theme.secondary).underline()
                    }
                    .font(.system(size: 14, weight: .light))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
        .task { await m.loadSettings() }
    }

    func marketing(_ field: String, _ kp: KeyPath<BruceAPI.NotificationSetting, Bool?>) -> Binding<Bool> {
        Binding(get: { m.notificationSetting?[keyPath: kp] ?? true }, set: { m.setMarketing(field, $0) })
    }

    /// The calendar feed URL contains the user's secret (c3:341); it is only copied, never shown or logged.
    func copyCalendarURL() {
        guard let uid = m.userId, let secret = m.user?.secret, !secret.isEmpty else {
            m.flash("Calendar link not available"); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("webcal://api.bruce.app/v52/user/\(uid)/calendar/\(secret).ics", forType: .string)
        m.flash("Calendar link copied. Add it in Calendar › New Calendar Subscription")
    }

    func toggleRow(_ t: String, _ sub: String, isOn: Binding<Bool>, help: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(t).font(.system(size: 17, weight: .medium))
                        if help { Image(systemName: "questionmark.circle.fill").foregroundStyle(Color(white: 0.35)) }
                    }
                    Text(sub).font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                BlackToggle(isOn: isOn)
            }
            .padding(.vertical, 16).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter)
    }

    func simpleToggle(_ t: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack { Text(t).font(.system(size: 17, weight: .medium)); Spacer(); BlackToggle(isOn: isOn) }
                .padding(.vertical, 12).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter)
    }

}

/// iOS-style black switch (local state only).
struct BlackToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Capsule().fill(isOn ? Color(white: 0.17) : Color(white: 0.88)).frame(width: 66, height: 40)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 34, height: 34).padding(3).shadow(color: .black.opacity(0.15), radius: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct PushSettingsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Push notifications", leading: .back, action: { m.popSheet() }) {
                IconButton(system: "info.circle", size: 22) { m.pushSheet(.pushInfo) }
            }
            row("Booking reminders", "booking_reminder")
            row("Check in", "check_in_reminder")
            row("New studios", "new_studio")
            Spacer()
        }
        .task { if m.notificationSetting == nil { await m.loadSettings() } }
    }
    /// Push types from GET notification_setting; flipping one PUTs the whole `types` array (c3:327).
    /// Subtitle from the API's notification type description, else our own fallback.
    func row(_ t: String, _ k: String) -> some View {
        let s = m.notificationSetting?.types?.first { $0.key == k }?.description ?? Copy.pushSubtitle(k)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(t).font(.system(size: 17, weight: .medium))
                    Text(s).font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                BlackToggle(isOn: Binding(get: { m.notificationSetting?.types?.first { $0.key == k }?.enabled ?? true },
                                          set: { m.setPushType(k, $0) }))
            }
            .padding(.vertical, 14).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter)
    }
}


// MARK: - Quick check-in (Home top bar): one suggestion + searchable "Other studios"

/// Same logic as iOS (Shared/BruceCore/CheckInLogic.swift), without location: (a) booking with an open
/// check-in window, else (c) last visited. Every check-in still asks for confirmation.
struct QuickCheckInSheet: View {
    @Environment(AppModel.self) var m
    @State private var query = ""

    func matches(_ t: CheckInTarget) -> Bool {
        query.isEmpty || t.name.localizedCaseInsensitiveContains(query) || t.subtitle.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Check in", leading: .close, action: { m.dismissSheets() }) {
                IconButton(system: "qrcode.viewfinder", size: 22) { m.present(.checkIn) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    if query.isEmpty, let sug = m.suggestedCheckIn(location: nil) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sug.reason.uppercased()).font(.system(size: 12, weight: .heavy).width(.expanded))
                                .foregroundStyle(sug.kind == .booking ? Color.black : Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(sug.kind == .booking ? Theme.lime : Theme.chipGrey))
                            Text(sug.target.name).font(.system(size: 24, weight: .heavy).width(.expanded)).lineLimit(2)
                            if sug.kind == .booking { Text(sug.target.subtitle).font(.system(size: 15, weight: .light)).foregroundStyle(Theme.secondary) }
                            LimeButton(title: "Check in") { m.askCheckIn(sug.target) }.padding(.top, 6)
                        }
                        .padding(18)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                        .padding(Theme.gutter)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                        TextField("", text: $query, prompt: Text("Other studios").foregroundColor(Theme.tertiary)).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.searchGrey))
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                    group("Pinned", m.pinnedCheckInTargets.filter(matches))
                    group("Today's bookings", m.todaysBookingTargets.filter(matches))
                    group("Recent", m.recentCheckInTargets.filter(matches))
                    group("All", m.allCheckInTargets.filter(matches))
                }
            }
        }
    }

    @ViewBuilder func group(_ title: String, _ list: [CheckInTarget]) -> some View {
        if !list.isEmpty {
            SectionHeaderBar(text: title)
            ForEach(list) { t in
                HStack(spacing: 14) {
                    Image(systemName: t.door != nil ? "door.left.hand.open" : "qrcode").font(.system(size: 18, weight: .light)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if !t.subtitle.isEmpty { Text(t.subtitle).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Button { m.toggleCheckInPin(t.studioId) } label: {
                        Image(systemName: m.isCheckInPinned(t.studioId) ? "pin.fill" : "pin").foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain).help(m.isCheckInPinned(t.studioId) ? "Unpin" : "Pin")
                    Button { m.askCheckIn(t) } label: {
                        Text("Check in").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
            }
        }
    }
}
