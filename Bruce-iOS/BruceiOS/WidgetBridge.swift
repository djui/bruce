import SwiftUI
import WidgetKit

// The app side of the widgets (Bruce-iOS/BruceWidgets): writes the App Group snapshot after the bookings and visit
// limits load, reloads the timelines, and handles the bruece:// links the widgets and the Control open.

extension AppModel {
    /// Rewrites the widget snapshot from what is loaded. Cheap; called after loadMine/loadAccount and at logout.
    func updateWidgetSnapshot() {
        let now = Date()
        let upcoming = bookings.compactMap { b -> (BruceAPI.Booking, BruceAPI.BruceClass, BookingRules)? in
            guard let c = b.class, let r = BookingRules(c), (r.end ?? r.start.addingTimeInterval(3600)) > now else { return nil }
            return (b, c, r)
        }.sorted { $0.2.start < $1.2.start }
        let next = upcoming.first.map { b, c, r in
            WidgetSnapshot.NextClass(classId: c.id, title: c.title, studio: studioName(c.studioId), start: r.start, end: r.end ?? r.start.addingTimeInterval(3600),
                                     checkInFrom: r.checkInFrom, lateCheckIn: r.lateCheckIn, lateCancel: r.lateCancel, shortNotice: r.shortNotice,
                                     lastMinute: r.lastMinute, checkedIn: b.isCheckedIn)
        }
        let monthly = visitLimits.first { $0.type == "MONTHLY" }
        let total = monthly?.total.flatMap { $0 > 0 ? $0 : nil }
        let snap = WidgetSnapshot(next: next, visitsUsed: monthly?.used, visitsTotal: total, month: BruceDate.format(now, "MMMM"),
                                  loggedIn: isLoggedIn, updatedAt: now)
        Task { await ClassLiveActivity.sync(self) }
        guard snap != WidgetSnapshot.load() else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// bruece://checkin, bruece://visits, bruece://class/<id> (WidgetSnapshot.swift).
    func open(widgetURL url: URL) {
        guard url.scheme == WidgetSnapshot.scheme else { return }
        let parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "checkin": dismissSheets(); if isLoggedIn { present(.quickCheckIn) } else { present(.login) }
        case "visits": dismissSheets(); present(isLoggedIn ? .visits : .login)
        case "class": if parts.count > 1, let id = Int(parts[1]) { dismissSheets(); push(.classDetail(id)) }
        case "ticket": if parts.count > 1, let id = Int(parts[1]) { dismissSheets(); present(.ticket(id)) }
        default: break
        }
    }
}

/// Demo screen "widgets": the widget faces at their sizes, so they can be checked without a Home Screen.
struct WidgetsPreviewSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let s = WidgetSnapshot.load() ?? .empty
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add them from the Home Screen or Lock Screen widget gallery; the check-in Control is in Control Center. They only open the app: nothing is booked or checked in from a widget.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                HStack(spacing: 14) {
                    face(NextClassView(snapshot: s, now: Date(), family: .systemSmall), w: 158, h: 158)
                    face(VisitsLeftView(snapshot: s, family: .systemSmall), w: 158, h: 158)
                }
                face(NextClassView(snapshot: s, now: Date(), family: .systemMedium), w: 338, h: 158)
                HStack(spacing: 14) {
                    face(NextClassView(snapshot: s, now: Date(), family: .accessoryRectangular), w: 172, h: 76, lock: true)
                    face(VisitsLeftView(snapshot: s, family: .accessoryCircular), w: 76, h: 76, lock: true)
                    face(CheckInButtonView(), w: 76, h: 76, lock: true)
                }
                Text("Live Activity for today's class").font(.system(size: 16, weight: .bold)).padding(.top, 8)
                let a = ClassLiveActivity.demoAttributes
                ForEach(Array([ClassActivityAttributes.ContentState(phase: .leave, leaveBy: a.start.addingTimeInterval(-33 * 60), travelMinutes: 12, mode: "bike", checkedInAt: nil),
                               .init(phase: .checkIn, leaveBy: nil, travelMinutes: nil, mode: nil, checkedInAt: nil),
                               .init(phase: .checkedIn, leaveBy: nil, travelMinutes: nil, mode: nil, checkedInAt: a.start.addingTimeInterval(-19 * 60))].enumerated()), id: \.offset) { _, st in
                    ClassActivityLockView(attributes: a, state: st).frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .environment(\.colorScheme, .dark)
                }
                Text(WidgetTheme.brand).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Widgets")
        .task { m.updateWidgetSnapshot() }
    }

    func face<V: View>(_ v: V, w: CGFloat, h: CGFloat, lock: Bool = false) -> some View {
        v.padding(lock ? 6 : 14).frame(width: w, height: h)
            .background(lock ? Color.black.opacity(0.85) : Theme.sectionGrey, in: RoundedRectangle(cornerRadius: lock ? 18 : 24, style: .continuous))
            .environment(\.colorScheme, lock ? .dark : .light)
    }
}
