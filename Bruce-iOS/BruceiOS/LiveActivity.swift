import SwiftUI
import ActivityKit

// Starts, updates and ends the Live Activity for today's class (Shared/BruceWidgetKit/ClassActivity.swift) while the
// app runs: on launch, when it comes to the foreground, after bookings load and after a check-in. There is no
// push-to-start; the activity's own timers keep the countdowns moving between updates.

@MainActor
enum ClassLiveActivity {
    /// How long before the class the activity appears.
    static let leadTime: TimeInterval = 90 * 60
    /// Arrive this long before the start when computing "Leave by".
    static let arriveBefore: TimeInterval = 15 * 60

    static func sync(_ m: AppModel) async {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled, !AppModel.demo else { return }
        let now = Date()
        let candidate = m.bookings.compactMap { b -> (BruceAPI.Booking, BruceAPI.BruceClass, BookingRules)? in
            guard let c = b.class, let r = BookingRules(c) else { return nil }
            let end = r.end ?? r.start.addingTimeInterval(3600)
            guard r.start.timeIntervalSince(now) <= leadTime, end.addingTimeInterval(15 * 60) > now else { return nil }
            return (b, c, r)
        }.sorted { $0.2.start < $1.2.start }.first
        let running = Activity<ClassActivityAttributes>.activities
        guard let (b, c, r) = candidate else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        for a in running where a.attributes.bookingId != b.id { await a.end(nil, dismissalPolicy: .immediate) }
        let end = r.end ?? r.start.addingTimeInterval(3600)
        var state = ClassActivityAttributes.ContentState(
            phase: ClassActivityAttributes.ContentState.phase(now: now, start: r.start, checkInFrom: r.checkInFrom, checkedIn: b.isCheckedIn),
            leaveBy: nil, travelMinutes: nil, mode: m.recSettings.mode.rawValue, checkedInAt: b.checkedInAt.flatMap(BruceDate.parse))
        if state.phase == .leave {
            let minutes = await travelMinutes(m, to: c.studioId)
            state.travelMinutes = minutes
            state.leaveBy = minutes.map { r.start.addingTimeInterval(-arriveBefore - Double($0) * 60) }
        }
        let stale: Date? = switch state.phase {
        case .leave: r.checkInFrom
        case .checkIn: r.start
        case .checkedIn, .started: end
        }
        let content = ActivityContent(state: state, staleDate: stale)
        if let a = running.first(where: { $0.attributes.bookingId == b.id }) {
            if a.content.state != state { await a.update(content) }
            if now > end.addingTimeInterval(15 * 60) { await a.end(content, dismissalPolicy: .immediate) }
            return
        }
        let attrs = ClassActivityAttributes(bookingId: b.id, classId: c.id, title: c.title, studio: m.studioName(c.studioId), vicinity: m.studio(c.studioId)?.vicinity,
                                            start: r.start, end: end, checkInFrom: r.checkInFrom, lateCheckIn: r.lateCheckIn, memberName: m.user?.fullName ?? "")
        _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
    }

    /// Minutes to the studio by the user's commute mode: MapKit from the current location (else home); the
    /// straight-line estimate when MapKit has no answer.
    static func travelMinutes(_ m: AppModel, to studioId: Int) async -> Int? {
        guard let to = m.studioPoint(studioId) else { return nil }
        let from = m.userLocation.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } ?? m.recSettings.home?.point
        guard let from else { return nil }
        let mode = m.recSettings.mode
        let q = TravelQuery(key: Recommender.travelKey(from, to, mode), from: from, to: to, mode: mode)
        return await CommuteETA.minutes(q) ?? mode.estimateMinutes(meters: Recommender.meters(from, to))
    }

    /// The Lock Screen face for the demo screen "widgets".
    static var demoAttributes: ClassActivityAttributes {
        let start = BruceDate.calendar.date(bySettingHour: 18, minute: 15, second: 0, of: Date()) ?? Date()
        return ClassActivityAttributes(bookingId: 0, classId: 0, title: "Body Pump", studio: "Example City Club", vicinity: "Kungsholmen", start: start,
                                       end: start.addingTimeInterval(2700), checkInFrom: start.addingTimeInterval(-1800), lateCheckIn: start.addingTimeInterval(-300), memberName: "Demo Member")
    }
}
