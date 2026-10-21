import SwiftUI
import EventKit
import EventKitUI

// Add to Calendar (CalendarExport.swift): one booked class through the system event editor, which needs no
// calendar permission on iOS 17+, plus "Subscribe to all bookings", which opens Bruce's webcal feed directly.

struct AddToCalendarSheet: View {
    @Environment(AppModel.self) var m
    @Environment(\.openURL) var openURL
    let classId: Int
    @State private var editing = false

    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }
    var event: CalendarEvent? { c.flatMap { CalendarEvent($0, studio: m.studio($0.studioId)) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let c, let event {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.title).bruceFont(20, weight: .bold)
                        Text("\(BruceDate.format(event.start, "EEE d MMM")) · \(BruceDate.time(event.start))–\(BruceDate.time(event.end))").bruceFont(16)
                        if let l = event.location { Text(l).bruceFont(15).foregroundStyle(Theme.secondary) }
                        Label(Copy.calendarAlert, systemImage: "bell").bruceFont(14).foregroundStyle(Theme.secondary).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    LimeButton(title: "Add to Calendar", systemImage: "calendar.badge.plus") { editing = true }
                    if let feed = m.calendarFeedURL {
                        Button { openURL(feed); m.dismissSheets() } label: {
                            Label(Copy.calendarSubscribe, systemImage: "calendar.badge.clock").bruceFont(17, weight: .semibold)
                                .frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    }
                    Text(Copy.calendarOneOff).bruceFont(14).foregroundStyle(Theme.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Add to Calendar")
        .sheet(isPresented: $editing) {
            if let event {
                EventEditor(event: event) { saved in
                    editing = false
                    if saved { m.flash(Copy.calendarAdded, icon: "calendar.badge.checkmark"); m.dismissSheets() }
                }
                .ignoresSafeArea()
            }
        }
        .task { if m.user?.secret == nil { await m.loadAccount() } }
    }
}

/// The system event editor (EKEventEditViewController) prefilled with the class; the user picks the calendar
/// and can change the alert. No calendar access request is needed for this controller on iOS 17+.
struct EventEditor: UIViewControllerRepresentable {
    let event: CalendarEvent
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let e = EKEvent(eventStore: store)
        e.title = event.title
        e.startDate = event.start
        e.endDate = event.end
        e.location = event.location
        e.notes = event.notes
        e.url = event.url
        e.addAlarm(EKAlarm(relativeOffset: -Double(CalendarEvent.alertMinutes) * 60))
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            done(action == .saved)
        }
    }
}
