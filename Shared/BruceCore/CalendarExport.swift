import Foundation

// Add to Calendar (one booking as an event) and the calendar subscription (Bruce's own webcal feed).
// One-off events are built from the class data already loaded; the feed URL contains the user's secret
// (API.md: treat it as a credential), so it is only opened or copied, never shown or logged.

/// A booked class as a calendar event: the system editor (iOS), EventKit (macOS) or an .ics file (web, fallback).
struct CalendarEvent: Hashable {
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let notes: String
    let url: URL
    /// All-day event (a race): `start` is the first day's midnight, `end` the midnight after the last day.
    var allDay = false
    /// Alert before the start, in minutes (editable in the system editor on iOS).
    var alarmMinutes = CalendarEvent.alertMinutes
    var uid: String?
    static let alertMinutes = 60
    /// A race's alert: 18:00 the evening before (6 h before its midnight start).
    static let raceAlertMinutes = 6 * 60

    /// A race as an all-day event: the member's day of the event if they picked one, else every day of it.
    init?(race r: Race, day: String? = nil) {
        guard let s = RaceDay.date(day ?? r.date), let last = RaceDay.adding(1, to: day ?? r.lastDay), let e = RaceDay.date(last) else { return nil }
        title = r.name
        start = s
        end = e
        allDay = true
        alarmMinutes = Self.raceAlertMinutes
        uid = "race-\(r.id)"
        location = [r.venue, r.city.isEmpty ? nil : r.city].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        var lines: [String] = []
        if let f = r.factsLine { lines.append(f) }
        if let u = r.url { lines.append("Race page: \(u.absoluteString)") }
        lines.append("")
        lines.append(Copy.raceEventFooter)
        notes = lines.joined(separator: "\n")
        url = r.url ?? URL(string: "https://djui.github.io/bruce/app/#/mine?tab=races")!
    }

    init?(_ c: BruceAPI.BruceClass, studio: BruceAPI.Studio?) {
        guard let r = BookingRules(c) else { return nil }
        title = c.title
        start = r.start
        end = r.end ?? r.start.addingTimeInterval(3600)
        let name = studio?.name ?? c.studio?.name
        let a = (studio?.studioAddresses?.first { $0.main == true } ?? studio?.studioAddresses?.first)?.address
        let street = [a?.address, [a?.zipCode, a?.city].compactMap { $0 }.joined(separator: " ")].compactMap { $0?.isEmpty == false ? $0 : nil }
        location = ([name] + street).compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        var lines: [String] = []
        if let i = c.instructor, !i.isEmpty { lines.append("Instructor: \(i)") }
        lines.append("Check-in \(BruceDate.time(r.checkInFrom))–\(BruceDate.time(r.lateCheckIn)) in the Bruce app at the studio.")
        lines.append("Free cancel until \(BookingRules.long(r.lateCancel)); after that a cancellation costs strikes, a no-show \(Policy.noShowStrikes).")
        lines.append("")
        lines.append(Copy.calendarEventFooter)
        notes = lines.joined(separator: "\n")
        url = ShareURL.forClass(c.id, title: c.title)
    }

    /// The event as an iCalendar file (RFC 5545), UTC times.
    var ics: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        // All-day events carry plain dates (DTEND is the day after the last day, RFC 5545 3.6.1).
        let when = allDay ? ["DTSTART;VALUE=DATE:\(Self.icsDay(start))", "DTEND;VALUE=DATE:\(Self.icsDay(end))"]
            : ["DTSTART:\(f.string(from: start))", "DTEND:\(f.string(from: end))"]
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Brüce (unofficial)//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
                     "BEGIN:VEVENT", "UID:\(uid ?? String(url.absoluteString.hashValue.magnitude))@bruce.unofficial", "DTSTAMP:\(f.string(from: Date()))"]
            + when + ["SUMMARY:\(esc(title))"]
        if allDay { lines.append("TRANSP:TRANSPARENT") }
        if let location { lines.append("LOCATION:\(esc(location))") }
        lines += ["DESCRIPTION:\(esc(notes))", "URL:\(url.absoluteString)",
                  "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(esc(title))", "TRIGGER:-PT\(alarmMinutes)M", "END:VALARM",
                  "END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// EventKit reads an all-day event in the device's time zone: the same calendar days there, ending on the last day
    /// (an end at the next midnight would add a day).
    var deviceAllDayRange: (start: Date, end: Date) {
        func local(_ d: Date) -> Date { Calendar.current.date(from: BruceDate.calendar.dateComponents([.year, .month, .day], from: d)) ?? d }
        return (local(start), local(end).addingTimeInterval(-1))
    }

    /// "20270515" for an all-day event's date (the Bruce time zone's calendar day).
    static func icsDay(_ d: Date) -> String { RaceDay.iso(d).replacingOccurrences(of: "-", with: "") }

    /// File name for the exported .ics ("hot-yoga-2026-10-27.ics").
    var fileName: String { "\(ShareURL.slug(title))-\(BruceDate.format(start, "yyyy-MM-dd")).ics" }
}

/// Bruce's calendar feed of all bookings (API.md: `GET /v52/user/<id>/calendar/<secret>.ics`).
enum CalendarFeed {
    /// The `webcal://` URL opens the system's subscribe dialog directly. Nil until the user record (with its
    /// secret) is loaded. Never log, show or send it anywhere but the system handler or the pasteboard.
    static func url(userId: Int?, secret: String?) -> URL? {
        guard let userId, let secret, !secret.isEmpty else { return nil }
        return URL(string: "webcal://api.bruce.app/v52/user/\(userId)/calendar/\(secret).ics")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
