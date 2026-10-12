import SwiftUI
import CoreLocation

/// iOS-style action sheet for a class row's ⋮ button.
struct ClassActionSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    var c: BruceAPI.BruceClass? { m.findClass(classId) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { m.classActions = nil }
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    action(m.isBookmarked(classId) ? "Remove bookmark" : "Add bookmark") { m.toggleBookmark(classId) }
                    Divider()
                    action("Invite friends") { m.present(.invite) }
                    Divider()
                    ShareLink(item: ShareURL.forClass(classId, title: c?.title ?? "")) { label("Share") }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { m.classActions = nil } })
                    Divider()
                    action("Show studio") { if let sid = c?.studioId { m.push(.studio(sid)) } }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.95)))
                Button { m.classActions = nil } label: {
                    Text("Close").font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.iosBlue)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.bottom, 10)
            .transition(.move(edge: .bottom))
        }
    }

    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 19)).foregroundStyle(Theme.iosBlue)
            .frame(maxWidth: .infinity).frame(height: 56).contentShape(Rectangle())
    }

    func action(_ t: String, _ run: @escaping () -> Void) -> some View {
        Button { m.classActions = nil; run() } label: { label(t) }.buttonStyle(.plain)
    }
}

extension Theme {
    static let iosBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
}

/// Category page: "<Category>" with Studios / Classes tabs (classes for the next 7 days).
struct CategoryView: View {
    @Environment(AppModel.self) var m
    let categoryId: Int
    @State private var tab = 0

    var title: String { m.categories.first { $0.id == categoryId }?.title ?? "Category" }

    var studios: [BruceAPI.Studio] {
        m.cityStudios.filter { $0.studioCategories?.contains { $0.categoryId == categoryId } ?? false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var classes: [BruceAPI.BruceClass] {
        m.classesByDay.values.joined()
            .filter { $0.canceled != true && ($0.start ?? .distantPast) > Date() }
            .filter { $0.classCategories?.contains { $0.categoryId == categoryId } ?? false }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: title) { m.pop() }
            UnderlineTabs(titles: ["Studios", "Classes"], badges: [String(studios.count), String(classes.count)], selection: $tab)
            ScrollView {
                if tab == 0 { studioList } else { classList }
            }
        }
        .onAppear { if m.demoCategoryTab != 0 { tab = m.demoCategoryTab; m.demoCategoryTab = 0 } }
        .task {
            let cal = BruceDate.calendar
            await m.loadClassDays((0..<7).map { cal.date(byAdding: .day, value: $0, to: Date())! })
        }
    }

    var studioList: some View {
        LazyVStack(spacing: 24) {
            ForEach(studios) { s in
                Button { m.push(.studio(s.id)) } label: {
                    ZStack {
                        RemotePhoto(fileId: s.photo)
                        Color.black.opacity(0.3)
                        VStack(spacing: 4) {
                            Text(s.name).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                            Text(s.vicinity ?? "").font(.system(size: 16))
                        }
                        .padding(.horizontal, 12)
                    }
                    .foregroundStyle(.white).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            if studios.isEmpty { Text("No studios.").foregroundStyle(Theme.secondary).padding(.top, 40) }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
    }

    var classList: some View {
        let groups = Dictionary(grouping: classes) { BruceDate.calendar.startOfDay(for: $0.start ?? Date()) }
        return LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(groups.keys.sorted(), id: \.self) { day in
                Section(header: SectionHeaderBar(text: BruceDate.format(day, "EEEE, MMMM d"))) {
                    ForEach(groups[day]!) { c in
                        let st = m.studio(c.studioId)
                        Button { m.push(.classDetail(c.id)) } label: {
                            ClassRow(time: BruceDate.time(c.start), duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                     title: c.title, studio: st?.name ?? "",
                                     meta: [st?.vicinity, c.instructor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | "),
                                     badge: m.isOnWaitlist(c.id) ? "On waitlist" : nil, full: (c.availableSpots ?? 1) <= 0,
                                     wellness: m.isWellness(studioId: c.studioId), classId: c.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if classes.isEmpty {
                Text(m.classesLoadingDay != nil ? "Loading classes…" : "No upcoming classes.").foregroundStyle(Theme.secondary).padding(.top, 40)
            }
        }
    }
}
