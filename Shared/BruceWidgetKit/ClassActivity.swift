import SwiftUI
import ActivityKit
import WidgetKit

// Live Activity for today's class (Bruce-iOS/BruceWidgets + Bruce-iOS/BruceiOS/LiveActivity.swift): "Leave by 17:42",
// then the check-in window with a button that opens the app, then the ticket once checked in. Started and updated
// by the app while it runs (no push-to-start); the views use timers so the countdowns move between updates.
// Compiled into the app and the widget extension. Nothing here checks anyone in.

struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case leave, checkIn, checkedIn, started }
        var phase: Phase
        /// When to set off, and the travel time it is based on (nil without a route).
        var leaveBy: Date?
        var travelMinutes: Int?
        var mode: String?
        var checkedInAt: Date?

        /// The phase at `now` for a class with these times.
        static func phase(now: Date, start: Date, checkInFrom: Date, checkedIn: Bool) -> Phase {
            if checkedIn { return .checkedIn }
            if now >= start { return .started }
            if now >= checkInFrom { return .checkIn }
            return .leave
        }
    }
    let bookingId: Int
    let classId: Int
    let title: String
    let studio: String
    let vicinity: String?
    let start: Date
    let end: Date
    let checkInFrom: Date
    let lateCheckIn: Date
    let memberName: String
}

enum ClassActivityCopy {
    static let brand = "Brüce (unofficial)"
    static func modeWord(_ m: String?) -> String {
        switch m { case "walk": "on foot"; case "transit": "by transit"; case "car": "by car"; default: "by bike" }
    }
}

/// Lock Screen / banner face.
struct ClassActivityLockView: View {
    let attributes: ClassActivityAttributes
    let state: ClassActivityAttributes.ContentState
    static let time: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(attributes.title) · \(Self.time.string(from: attributes.start))").font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text([attributes.studio, attributes.vicinity].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                WidgetMark(size: 22)
            }
            phaseLine
            HStack(spacing: 0) {
                step("Leave", state.leaveBy.map { Self.time.string(from: $0) } ?? "–", on: state.phase == .leave)
                step("Check in", "\(Self.time.string(from: attributes.checkInFrom))–\(Self.time.string(from: attributes.lateCheckIn))", on: state.phase == .checkIn)
                step("Class", Self.time.string(from: attributes.start), on: state.phase == .started || state.phase == .checkedIn)
            }
            Text(ClassActivityCopy.brand).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    @ViewBuilder var phaseLine: some View {
        switch state.phase {
        case .leave:
            HStack(spacing: 8) {
                Image(systemName: "figure.walk.departure").font(.system(size: 15, weight: .semibold))
                if let l = state.leaveBy {
                    Text("Leave by \(Self.time.string(from: l))").font(.system(size: 17, weight: .bold))
                    if let t = state.travelMinutes { Text("· \(t) min \(ClassActivityCopy.modeWord(state.mode))").font(.system(size: 13)).foregroundStyle(.secondary) }
                    Spacer()
                    Text(timerInterval: Date()...max(Date(), l), countsDown: true).font(.system(size: 15, weight: .semibold)).monospacedDigit().frame(width: 60, alignment: .trailing)
                } else {
                    Text("Check-in opens \(Self.time.string(from: attributes.checkInFrom))").font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundStyle(WidgetTheme.teal)
        case .checkIn:
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder").font(.system(size: 15, weight: .semibold))
                Text("Check-in open until \(Self.time.string(from: attributes.lateCheckIn))").font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Link(destination: WidgetSnapshot.checkInURL) {
                    Text("Check in").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(WidgetTheme.lime, in: Capsule())
                }
            }
            .foregroundStyle(WidgetTheme.lime)
        case .checkedIn:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 17)).foregroundStyle(.black, WidgetTheme.lime)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Checked in\(state.checkedInAt.map { " \(Self.time.string(from: $0))" } ?? "")").font(.system(size: 16, weight: .bold))
                    Text(attributes.memberName).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: WidgetSnapshot.ticketURL(attributes.bookingId)) {
                    Text("Ticket").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(WidgetTheme.lime, in: Capsule())
                }
            }
        case .started:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .semibold))
                Text("Started · check-in closed").font(.system(size: 16, weight: .bold))
                Spacer()
            }
            .foregroundStyle(WidgetTheme.orange)
        }
    }

    func step(_ title: String, _ value: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy).width(.expanded)).foregroundStyle(on ? WidgetTheme.lime : .secondary)
            Text(value).font(.system(size: 12, weight: on ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact / minimal Dynamic Island pieces.
struct ClassActivityCompactLeading: View {
    let state: ClassActivityAttributes.ContentState
    var body: some View {
        Image(systemName: state.phase == .checkedIn ? "checkmark.seal.fill" : state.phase == .checkIn ? "qrcode.viewfinder" : "figure.walk.departure")
            .foregroundStyle(WidgetTheme.lime)
    }
}
struct ClassActivityCompactTrailing: View {
    let attributes: ClassActivityAttributes
    let state: ClassActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .leave:
            if let l = state.leaveBy { Text(timerInterval: Date()...max(Date(), l), countsDown: true).monospacedDigit().frame(width: 44) }
            else { Text(ClassActivityLockView.time.string(from: attributes.checkInFrom)) }
        case .checkIn: Text(timerInterval: Date()...max(Date(), attributes.lateCheckIn), countsDown: true).monospacedDigit().frame(width: 44)
        case .checkedIn: Text("In").foregroundStyle(WidgetTheme.lime)
        case .started: Text(ClassActivityLockView.time.string(from: attributes.start))
        }
    }
}

extension WidgetSnapshot {
    static func ticketURL(_ bookingId: Int) -> URL { URL(string: "bruece://ticket/\(bookingId)")! }
}
