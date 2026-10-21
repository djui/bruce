import WidgetKit
import SwiftUI
import AppIntents

// Home Screen widgets, Lock Screen accessories and a Control Center control for Brüce (unofficial Bruce Studios
// client). Everything renders from the App Group snapshot the app writes (Shared/BruceWidgetKit): the extension
// holds no login and makes no requests. Check-in is never performed here: the button and the Control only open
// the app's quick check-in sheet, where it stays confirmed and location-aware.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One timeline for all widgets: an entry now, one at each moment the next class's status changes, and a reload
/// once the class has ended (the app rewrites the snapshot whenever it refreshes and reloads the timelines).
struct SnapshotProvider: TimelineProvider {
    static let placeholder: WidgetSnapshot = {
        let start = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date().addingTimeInterval(86400)) ?? Date()
        let next = WidgetSnapshot.NextClass(classId: 0, title: "Hatha Flow", studio: "Example Yoga Studio", start: start, end: start.addingTimeInterval(3600),
                                            checkInFrom: start.addingTimeInterval(-1800), lateCheckIn: start.addingTimeInterval(-300), lateCancel: start.addingTimeInterval(-43200),
                                            shortNotice: start.addingTimeInterval(-10800), lastMinute: start.addingTimeInterval(-3600), checkedIn: false)
        return WidgetSnapshot(next: next, visitsUsed: 7, visitsTotal: 20, month: "October", loggedIn: true, updatedAt: Date())
    }()

    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: Self.placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? Self.placeholder : (WidgetSnapshot.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let s = WidgetSnapshot.load() ?? .empty
        var dates = [now]
        if let c = s.next { dates += c.steps(after: now).prefix(8) }
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: s) }
        let reload: Date = s.next.map { $0.end > now ? $0.end.addingTimeInterval(60) : now.addingTimeInterval(6 * 3600) } ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }
}

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "net.dauernheim.bruce.nextclass", provider: SnapshotProvider()) { entry in
            NextClassEntryView(entry: entry)
        }
        .configurationDisplayName("Next class")
        .description("Your next booked class and when you can still cancel it for free. Brüce (unofficial).")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextClassEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry
    var body: some View {
        NextClassView(snapshot: entry.snapshot, now: entry.date, family: family)
            .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

struct VisitsLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "net.dauernheim.bruce.visits", provider: SnapshotProvider()) { entry in
            VisitsLeftEntryView(entry: entry)
        }
        .configurationDisplayName("Visits left")
        .description("Visits left on your plan this month. Brüce (unofficial).")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct VisitsLeftEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry
    var body: some View {
        VisitsLeftView(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

/// Lock Screen button: opens the app's quick check-in sheet.
struct CheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "net.dauernheim.bruce.checkin", provider: SnapshotProvider()) { _ in
            CheckInButtonView().containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Check in")
        .description("Opens Brüce's quick check-in. The check-in itself happens in the app, at the studio.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Control Center / Lock Screen control: opens the app on the quick check-in sheet (it books or checks in nothing).
struct OpenCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Open check-in in Brüce"
    static let description = IntentDescription("Opens Brüce on the quick check-in suggestions. Unofficial client; the check-in stays in the app.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetSnapshot.checkInURL))
    }
}

struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.dauernheim.bruce.control.checkin") {
            ControlWidgetButton(action: OpenCheckInIntent()) {
                Label("Check in", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("Check in with Brüce")
        .description("Opens the quick check-in sheet in Brüce (unofficial).")
    }
}

@main
struct BruceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        VisitsLeftWidget()
        CheckInWidget()
        CheckInControl()
    }
}
