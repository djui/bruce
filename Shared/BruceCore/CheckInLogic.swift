import Foundation
import CoreLocation

// Quick check-in: one suggested place + sectioned, searchable list of everything else.
// Shared by the iOS Home "Check in" sheet and the macOS quick check-in sheet.

struct CheckInSuggestion: Identifiable {
    enum Kind { case booking, nearby, lastVisited }
    let target: CheckInTarget
    let kind: Kind
    /// "Booked 18:30 · window open", "Nearby · 120 m", "Last visited".
    let reason: String
    var id: String { target.id }
}

extension AppModel {
    /// Booked classes (incl. openings) whose check-in window is open now: from
    /// start − early_check_in_minutes until the class ends (start + 1 h if no end time).
    var openWindowTargets: [(CheckInTarget, BruceAPI.BruceClass)] {
        let now = Date()
        return bookings.compactMap { b -> (CheckInTarget, BruceAPI.BruceClass)? in
            guard let c = b.class, let r = BookingRules(c) else { return nil }
            guard r.checkInFrom <= now, now <= (r.end ?? r.start.addingTimeInterval(3600)) else { return nil }
            let sid = c.studioId
            guard let t = CheckInTarget.make(studio: studio(sid), studioId: sid, name: studioName(sid),
                                             subtitle: "\(c.title) · \(BruceDate.time(c.start))") else { return nil }
            return (t, c)
        }
        .sorted { $0.1.startTime < $1.1.startTime }
    }

    /// Order: (a) booking with an open check-in window, (b) nearest check-in-capable studio within
    /// `radius` metres when a location is known, (c) the most recently checked-in studio.
    func suggestedCheckIn(location: CLLocation?, radius: Double = 300) -> CheckInSuggestion? {
        if let (t, c) = openWindowTargets.first {
            return CheckInSuggestion(target: t, kind: .booking, reason: "Booked \(BruceDate.time(c.start)) · window open")
        }
        if let loc = location {
            let near = allCheckInTargets.compactMap { t -> (CheckInTarget, Double)? in
                guard let a = studio(t.studioId)?.studioAddresses?.first(where: { $0.main == true })?.address
                        ?? studio(t.studioId)?.studioAddresses?.first?.address,
                      let lat = a.latitude, let lon = a.longitude else { return nil }
                let d = CLLocation(latitude: lat, longitude: lon).distance(from: loc)
                return d <= radius ? (t, d) : nil
            }
            .min { $0.1 < $1.1 }
            if let (t, d) = near {
                return CheckInSuggestion(target: t, kind: .nearby, reason: "Nearby · \(Int(d / 10) * 10) m")
            }
        }
        if let t = recentCheckInTargets.first {
            return CheckInSuggestion(target: t, kind: .lastVisited, reason: "Last visited")
        }
        return nil
    }

    /// Today's booked classes at studios with a door / QR code.
    var todaysBookingTargets: [CheckInTarget] {
        let cal = BruceDate.calendar
        var seen = Set<String>()
        return bookings.sorted { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }.compactMap { b in
            guard let c = b.class, let d = c.start, cal.isDateInToday(d) else { return nil }
            let sid = c.studioId
            guard let t = CheckInTarget.make(studio: studio(sid), studioId: sid, name: studioName(sid),
                                             subtitle: "\(c.title) · \(BruceDate.time(d))"),
                  seen.insert(t.id).inserted else { return nil }
            return t
        }
    }

    /// Last 5 studios by last check-in.
    var recentCheckInTargets: [CheckInTarget] {
        let visits = (pastBookings + bookings)
            .compactMap { b -> (Int, Date)? in
                guard let sid = b.studioId ?? b.class?.studioId, let d = b.checkedInAt.flatMap(BruceDate.parse) else { return nil }
                return (sid, d)
            }
            .sorted { $0.1 > $1.1 }
        var seen = Set<Int>(), out: [CheckInTarget] = []
        for (sid, d) in visits where seen.insert(sid).inserted {
            let when = BruceDate.calendar.isDateInToday(d) ? "Today \(BruceDate.time(d))" : BruceDate.format(d, "d MMM")
            if let t = CheckInTarget.make(studio: studio(sid), studioId: sid, name: studioName(sid), subtitle: "Checked in \(when)") {
                out.append(t)
            }
            if out.count == 5 { break }
        }
        return out
    }

    /// Every studio with a known door or a `qr_code_id`, alphabetical.
    var allCheckInTargets: [CheckInTarget] {
        var out: [Int: CheckInTarget] = [:]
        for s in studios where s.isLive || s.status == nil {
            if let t = CheckInTarget.make(studio: s, studioId: s.id, name: s.name, subtitle: s.vicinity ?? "") { out[s.id] = t }
        }
        for (sid, door) in KnownDoors.byStudio where out[sid] == nil {
            out[sid] = CheckInTarget(studioId: sid, name: studio(sid)?.name ?? door.name, subtitle: "Drop-in gym",
                                     qrCodeId: "stc:\(door.major)", door: door)
        }
        return out.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isCheckInPinned(_ studioId: Int) -> Bool { checkInPins.contains(studioId) }
    /// Local only (UserDefaults); never sent to the API.
    func toggleCheckInPin(_ studioId: Int) {
        if checkInPins.contains(studioId) { checkInPins.remove(studioId) } else { checkInPins.insert(studioId) }
        if !AppModel.demo { UserDefaults.standard.set(Array(checkInPins), forKey: "checkInPins") }
    }
    var pinnedCheckInTargets: [CheckInTarget] { allCheckInTargets.filter { checkInPins.contains($0.studioId) } }
}
