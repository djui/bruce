import SwiftUI

/// Friends' upcoming classes: GET /v52/booking?friends=true (c3:106), joined with GET /v52/friend.
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
        VStack(spacing: 0) {
            ScreenHeader(title: "Friends")
            if !m.isLoggedIn {
                EmptyState(system: "person.2", text: "Log in to see what your friends are training.")
            } else if items.isEmpty {
                EmptyState(system: "person.2", text: "Your friends' upcoming classes will show up here.")
            } else {
                let groups = Dictionary(grouping: items) { BruceDate.calendar.startOfDay(for: $0.2.start ?? Date()) }
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups.keys.sorted(), id: \.self) { day in
                            Section(header: SectionHeaderBar(text: BruceDate.dayHeader(day))) {
                                ForEach(groups[day]!, id: \.0.id) { b, u, c in
                                    Button { m.push(.classDetail(c.id)) } label: { row(u, c) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { await m.loadSocial() }
    }

    func row(_ u: BruceAPI.UserLite?, _ c: BruceAPI.BruceClass) -> some View {
        let st = m.studio(c.studioId)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(BruceDate.time(c.start)).font(.system(size: 17, weight: .semibold))
                    Text(c.durationMinutes.map { "\($0) min" } ?? "").font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                }
                .frame(width: 62, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text(st?.name ?? c.studio?.name ?? "").font(.system(size: 16, weight: .light)).lineLimit(1)
                    Text([st?.vicinity ?? c.studio?.vicinity, c.instructor].compactMap { $0 }.joined(separator: " | "))
                        .font(.system(size: 16, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Avatar(fileId: u?.photo, initials: u?.initials ?? "?", size: 40)
            }
            .padding(.vertical, 18).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter - 4)
        .contentShape(Rectangle())
    }
}

struct MyClassesView: View {
    @Environment(AppModel.self) var m
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "My classes") { CountPill(used: m.upcomingBookings.count, total: m.simultaneousLimit ?? 3) }
            UnderlineTabs(titles: ["Bookings", "Waitlist", "Bookmarks"], selection: $tab)
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
        }
        .task { await m.loadMine() }
        .onAppear { if m.demoMyClassesTab != 0 { tab = m.demoMyClassesTab; m.demoMyClassesTab = 0 } }
    }

    func list(_ items: [(Int, BruceAPI.BruceClass, BruceAPI.Booking?)],
              badge: @escaping (BruceAPI.BruceClass) -> String? = { _ in nil }) -> some View {
        let groups = Dictionary(grouping: items) { BruceDate.calendar.startOfDay(for: $0.1.start ?? Date()) }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups.keys.sorted(), id: \.self) { day in
                    SectionHeaderBar(text: BruceDate.dayHeader(day))
                    ForEach(groups[day]!.sorted { $0.1.startTime < $1.1.startTime }, id: \.0) { item in
                        let c = item.1
                        let st = m.studio(c.studioId)
                        Button { m.push(.classDetail(c.id)) } label: {
                            ClassRow(time: BruceDate.time(c.start), duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                     title: c.title, studio: st?.name ?? c.studio?.name ?? "",
                                     meta: [st?.vicinity, c.instructor].compactMap { $0 }.joined(separator: " | "),
                                     badge: badge(c), wellness: m.isWellness(studioId: c.studioId), classId: c.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let b = item.2, b.isCheckedIn {
                                Button("Show ticket") { m.present(.ticket(b.id)) }
                                if let r = m.reviewableBooking(forClass: c.id) {
                                    Button("\(Copy.reviewTitle)…") { m.present(.review(r.id)) }
                                }
                            } else if item.2 != nil {
                                Button("Add to Calendar") { m.present(.addToCalendar(c.id)) }
                                Button("Cancel booking…") { m.present(.bookingRules(c.id)) }
                            }
                        }
                    }
                }
            }
        }
    }
}
