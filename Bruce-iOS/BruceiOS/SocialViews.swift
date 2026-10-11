import SwiftUI

/// Friends' upcoming classes: GET /v52/booking?friends=true, joined with GET /v52/friend.
struct FriendsView: View {
    @Environment(AppModel.self) var m

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
            } else if items.isEmpty {
                EmptyState(system: "person.2", text: "Your friends' upcoming classes will show up here.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    friendStrip
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedByDay(items, date: { $0.2.start }), id: \.0) { day, list in
                            Section(header: SectionHeaderBar(text: BruceDate.dayHeader(day))) {
                                ForEach(list, id: \.0.id) { _, u, c in
                                    NavigationLink(value: Route.classDetail(c.id)) {
                                        ClassRow(c: c, showMenu: false,
                                                 trailing: AnyView(Avatar(fileId: u?.photo, initials: u?.initials ?? "?", size: 40)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .bruceTitle("Friends")
        .task { await m.loadSocial() }
        .refreshable { await m.loadSocial() }
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
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    switch tab {
                    case 0:
                        if m.bookings.isEmpty { EmptyState(system: "calendar.badge.checkmark", text: "You have no bookings.") }
                        else { list(m.bookings.compactMap { b in b.class.map { (b.id, $0, b) } }) }
                    case 1:
                        if m.standbys.isEmpty { EmptyState(system: "bell", text: "You're not on any waitlists.") }
                        else { list(m.standbys.compactMap { s in s.class.map { (s.id, $0, nil) } }, badge: "On waitlist") }
                    default:
                        if m.bookmarkedClasses.isEmpty { EmptyState(system: "bookmark", text: "No bookmarked classes yet.") }
                        else { list(m.bookmarkedClasses.map { ($0.id, $0, nil) }) }
                    }
                } header: {
                    UnderlineTabs(titles: ["Bookings", "Waitlist", "Bookmarks"],
                                  badges: [m.bookings.isEmpty ? nil : String(m.bookings.count), m.standbys.isEmpty ? nil : String(m.standbys.count), nil],
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
                Text(m.simultaneousLimit.map { "\(m.bookings.count) / \($0)" } ?? "\(m.bookings.count)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6)
            }
        }
        .task { await m.loadMine() }
        .refreshable { await m.loadMine() }
    }

    func list(_ items: [(Int, BruceAPI.BruceClass, BruceAPI.Booking?)], badge: String? = nil) -> some View {
        ForEach(groupedByDay(items, date: { $0.1.start }), id: \.0) { day, list in
            SectionHeaderBar(text: BruceDate.dayHeader(day))
            ForEach(list.sorted { $0.1.startTime < $1.1.startTime }, id: \.0) { item in
                let c = item.1
                NavigationLink(value: Route.classDetail(c.id)) { ClassRow(c: c, badge: badge) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if item.2 != nil {
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
                        ForEach(list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) { n in card(n) }
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
            if let photo = n.meta?.photo ?? n.meta?.userPhoto {
                Avatar(fileId: photo, size: 48)
            } else {
                Image(systemName: icon(n)).font(.system(size: 20, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 48, height: 48).background(Circle().fill(Theme.lime))
            }
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
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    func icon(_ n: BruceAPI.BruceNotification) -> String {
        let t = (n.title ?? "").lowercased()
        if t.contains("cancel") { return "calendar.badge.minus" }
        if t.contains("reminder") { return "alarm" }
        return "bell.fill"
    }
}
