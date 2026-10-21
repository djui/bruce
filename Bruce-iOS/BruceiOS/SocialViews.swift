import SwiftUI

/// Friends' upcoming classes: GET /v52/booking?friends=true, joined with GET /v52/friend.
struct FriendsView: View {
    @Environment(AppModel.self) var m
    /// Classes · Challenges · Friends.
    @State private var segment = 0

    var items: [(BruceAPI.FriendBooking, BruceAPI.UserLite?, BruceAPI.BruceClass)] {
        m.friendsBookings.compactMap { b in
            guard let c = b.class, (c.start ?? .distantPast) > Date().addingTimeInterval(-3600) else { return nil }
            return (b, m.friends.first { $0.friendUser?.id == b.userId }?.friendUser, c)
        }
        .sorted { $0.2.startTime < $1.2.startTime }
    }

    var body: some View {
        ScrollView {
            if !m.isLoggedIn {
                EmptyState(system: "person.2", text: "Log in to see what your friends are training.")
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        switch segment {
                        case 1: ChallengesSegment()
                        case 2: friendList
                        default: classes
                        }
                    } header: {
                        UnderlineTabs(titles: ["Classes", "Challenges", "Friends"],
                                      badges: [items.isEmpty ? nil : String(items.count),
                                               m.pendingChallengeInvites.isEmpty ? nil : String(m.pendingChallengeInvites.count), nil],
                                      selection: $segment)
                        .padding(.top, 8)
                        .background(Theme.background)
                    }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .bruceTitle("Friends")
        .toolbar {
            // The tab's own action goes before the shared Notifications/Menu capsule (see MainToolbarButtons).
            if m.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { m.present(.newChallenge) } label: { Image(systemName: "plus") }.accessibilityLabel("New challenge")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            MainToolbarButtons()
        }
        .task { await m.loadSocial(); await m.loadChallenges() }
        .refreshable { await m.loadSocial(); await m.loadChallenges() }
        .onAppear { if m.demoFriendsTab != 0 { segment = m.demoFriendsTab; m.demoFriendsTab = 0 } }
    }

    @ViewBuilder var classes: some View {
        if items.isEmpty {
            EmptyState(system: "person.2", text: "Your friends' upcoming classes will show up here.")
        } else {
            friendStrip
            ForEach(groupedByDay(items, date: { $0.2.start }), id: \.0) { day, list in
                SectionHeaderBar(text: BruceDate.dayHeader(day))
                ForEach(list, id: \.0.id) { _, u, c in
                    NavigationLink(value: Route.classDetail(c.id)) {
                        ClassRow(c: c, showMenu: false, showFriends: false,
                                 trailing: AnyView(Avatar(fileId: u?.photo, initials: u?.initials ?? "?", size: 40)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Bruce friends; "Uses Brüce" when they have a row on our server (they can join challenges).
    @ViewBuilder var friendList: some View {
        if m.friends.isEmpty {
            EmptyState(system: "person.2", text: "Add friends in the Bruce app to see them here.")
        } else {
            VStack(spacing: 0) {
                ForEach(m.friends) { f in
                    HStack(spacing: 14) {
                        Avatar(fileId: f.friendUser?.photo, initials: f.friendUser?.initials ?? "", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.friendUser?.fullName ?? "").font(.system(size: 16, weight: .semibold))
                            if let id = f.friendUser?.id, m.usesBruce.contains(id) {
                                Text("Uses Brüce").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 10)
                }
            }
            .padding(.top, 8)
        }
    }

    var friendStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(m.friends) { f in
                    VStack(spacing: 6) {
                        Avatar(fileId: f.friendUser?.photo, initials: f.friendUser?.initials ?? "", size: 58)
                            .padding(3).glassEffect(.regular, in: .circle)
                        Text(f.friendUser?.firstName ?? "").font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
    }
}

struct MyClassesView: View {
    @Environment(AppModel.self) var m
    @State private var tab = 0

    var body: some View {
        ScrollView {
            if m.isLoggedIn { GoalsCompactCard() }
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    switch tab {
                    case 0:
                        if m.bookings.isEmpty { EmptyState(system: "calendar.badge.checkmark", text: "You have no bookings.") }
                        // Checked-in classes stay listed with a "Checked in" badge, as in the original [c8:404].
                        else { list(m.bookings.compactMap { b in b.class.map { (b.id, $0, b) } },
                                    badge: { c in m.booking(forClass: c.id)?.isCheckedIn == true ? Copy.checkedIn : nil }) }
                    case 1:
                        if m.waitlistRows.isEmpty { EmptyState(system: "bell", text: "You're not on any waitlists.") }
                        // A standby that got a spot shows "Booked" (and can be cancelled), as in the original.
                        else { list(m.waitlistRows.compactMap { s in s.class.map { (s.id, $0, m.booking(forClass: $0.id)) } },
                                    badge: { m.waitlistBadge($0.id) }) }
                    default:
                        if m.bookmarkedClasses.isEmpty { EmptyState(system: "bookmark", text: "No bookmarked classes yet.") }
                        else { list(m.bookmarkedClasses.map { ($0.id, $0, nil) }) }
                    }
                } header: {
                    UnderlineTabs(titles: ["Bookings", "Waitlist", "Bookmarks"],
                                  badges: [m.bookings.isEmpty ? nil : String(m.bookings.count), m.waitlistRows.isEmpty ? nil : String(m.waitlistRows.count), nil],
                                  selection: $tab)
                    .padding(.top, 8)
                    .background(Theme.background)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .bruceTitle("My classes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(m.simultaneousLimit.map { "\(m.upcomingBookings.count) / \($0)" } ?? "\(m.upcomingBookings.count)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            MainToolbarButtons()
        }
        .task { await m.loadMine() }
        .refreshable { await m.loadMine() }
        .onAppear { if m.demoMyClassesTab != 0 { tab = m.demoMyClassesTab; m.demoMyClassesTab = 0 } }
    }

    func list(_ items: [(Int, BruceAPI.BruceClass, BruceAPI.Booking?)],
              badge: @escaping (BruceAPI.BruceClass) -> String? = { _ in nil }) -> some View {
        ForEach(groupedByDay(items, date: { $0.1.start }), id: \.0) { day, list in
            SectionHeaderBar(text: BruceDate.dayHeader(day))
            ForEach(list.sorted { $0.1.startTime < $1.1.startTime }, id: \.0) { item in
                let c = item.1
                NavigationLink(value: Route.classDetail(c.id)) { ClassRow(c: c, badge: badge(c)) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let b = item.2, b.isCheckedIn {
                            Button("Show ticket", systemImage: "ticket") { m.present(.ticket(b.id)) }
                            if let r = m.reviewableBooking(forClass: c.id) {
                                Button("\(Copy.reviewTitle)…", systemImage: "star") { m.present(.review(r.id)) }
                            }
                        } else if item.2 != nil {
                            Button("Add to Calendar", systemImage: "calendar.badge.plus") { m.present(.addToCalendar(c.id)) }
                            Button("Cancel booking…", systemImage: "xmark.circle", role: .destructive) { m.present(.bookingRules(c.id)) }
                        }
                        ShareLink(item: ShareURL.forClass(c.id, title: c.title))
                    }
            }
        }
    }
}

// MARK: - Notifications

struct NotificationsSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ScrollView {
            if m.notifications.isEmpty {
                EmptyState(system: "bell", text: m.isLoggedIn ? "No notifications." : "Log in to see notifications.")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedByDay(m.notifications, date: \.date).reversed(), id: \.0) { day, list in
                        Text(BruceDate.dayHeader(day)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.top, 10)
                        ForEach(list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) { n in
                            // Opens the class the notification is about, else its studio.
                            Button { m.openNotification(n) } label: { card(n) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
            }
        }
        .sheetChrome("Notifications")
        .task { await m.loadSocial() }
        .refreshable { await m.loadSocial() }
        .onDisappear { m.markNotificationsSeen() }
    }

    func card(_ n: BruceAPI.BruceNotification) -> some View {
        HStack(alignment: .top, spacing: 14) {
            NotificationIcon(n: n, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(n.title ?? "").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(BruceDate.time(n.date)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    if m.isNew(n) { Circle().fill(Theme.red).frame(width: 8, height: 8) }
                }
                Text(n.message ?? "").font(.system(size: 15)).foregroundStyle(Theme.ink.opacity(0.85))
            }
        }
        .padding(16)
        .contentShape(.rect(cornerRadius: 24))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }
}

/// A notification's icon: the class or studio photo (black when there is none) with a glyph for what happened, and a
/// corner badge for what it is about (a class, a studio, or Bruce itself), tinted lime for good news and red for bad.
struct NotificationIcon: View {
    let n: BruceAPI.BruceNotification
    var size: CGFloat
    var body: some View {
        ZStack {
            if let photo = n.meta?.photo ?? n.meta?.userPhoto {
                Avatar(fileId: photo, size: size)
                Circle().fill(.black.opacity(0.35))
            } else {
                Circle().fill(.black)
            }
            Image(systemName: n.look.symbol).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { badge.offset(x: 3, y: 3) }
        .accessibilityElement().accessibilityLabel(n.iconAccessibilityLabel)
    }

    var badge: some View {
        let d = (size * 0.42).rounded()
        let (fill, ink): (Color, Color) = switch n.look.tone {
        case .good: (Theme.lime, .black)
        case .bad: (Theme.red, .white)
        case .neutral: (Color(.systemGray5), Theme.ink)
        }
        return ZStack {
            Circle().fill(fill)
            switch n.subject {
            case .bruce: Text("B").font(.system(size: d * 0.6, weight: .black).width(.expanded))
            case .classSession: Image(systemName: "figure.run").font(.system(size: d * 0.52, weight: .bold))
            case .studio: Image(systemName: "building.2").font(.system(size: d * 0.48, weight: .bold))
            }
        }
        .foregroundStyle(ink).frame(width: d, height: d)
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
    }
}
