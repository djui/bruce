import SwiftUI
import EventKit
import AppKit

// Add to Calendar (CalendarExport.swift): one booked class written with EventKit (write-only access, macOS 14+);
// when that access is refused or unavailable, the event is opened as an .ics file in the default calendar app
// instead. "Subscribe to all bookings" opens Bruce's webcal feed directly.

struct AddToCalendarSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    @State private var working = false

    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.classesByDay.values.joined().first { $0.id == classId } }
    var event: CalendarEvent? { c.flatMap { CalendarEvent($0, studio: m.studio($0.studioId)) } }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Add to Calendar", leading: .close) { m.dismissSheets() }
            if let c, let event {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.title).font(.system(size: 20, weight: .bold))
                        Text("\(BruceDate.format(event.start, "EEE d MMM")) · \(BruceDate.time(event.start))–\(BruceDate.time(event.end))").font(.system(size: 16))
                        if let l = event.location { Text(l).font(.system(size: 15)).foregroundStyle(Theme.secondary) }
                        Label(Copy.calendarAlert, systemImage: "bell").font(.system(size: 14)).foregroundStyle(Theme.secondary).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.sectionGrey))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                    LimeButton(title: working ? "Adding…" : "Add to Calendar") {
                        guard !working else { return }
                        working = true
                        Task {
                            let how = await CalendarWriter.add(event)
                            working = false
                            m.flash(how == .saved ? Copy.calendarAdded : "Opened in Calendar: confirm the event there", icon: "calendar.badge.checkmark")
                            m.dismissSheets()
                        }
                    }
                    if let feed = m.calendarFeedURL {
                        Button { NSWorkspace.shared.open(feed); m.dismissSheets() } label: {
                            Text(Copy.calendarSubscribe).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(Copy.calendarOneOff).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if m.user?.secret == nil { await m.loadAccount() } }
    }
}

enum CalendarWriter {
    enum Outcome { case saved, openedFile }

    /// Writes the event to the default calendar; without write access it opens an .ics file in the calendar app.
    static func add(_ event: CalendarEvent) async -> Outcome {
        let store = EKEventStore()
        if (try? await store.requestWriteOnlyAccessToEvents()) == true, let cal = store.defaultCalendarForNewEvents {
            let e = EKEvent(eventStore: store)
            e.title = event.title
            e.startDate = event.start
            e.endDate = event.end
            e.location = event.location
            e.notes = event.notes
            e.url = event.url
            e.addAlarm(EKAlarm(relativeOffset: -Double(CalendarEvent.alertMinutes) * 60))
            e.calendar = cal
            if (try? store.save(e, span: .thisEvent, commit: true)) != nil { return .saved }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(event.fileName)
        try? event.ics.write(to: file, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(file)
        return .openedFile
    }
}
