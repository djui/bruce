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
    /// Alert before the start, in minutes (editable in the system editor on iOS).
    static let alertMinutes = 60

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
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Brüce (unofficial)//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
                     "BEGIN:VEVENT", "UID:\(url.absoluteString.hashValue.magnitude)@bruce.unofficial", "DTSTAMP:\(f.string(from: Date()))",
                     "DTSTART:\(f.string(from: start))", "DTEND:\(f.string(from: end))", "SUMMARY:\(esc(title))"]
        if let location { lines.append("LOCATION:\(esc(location))") }
        lines += ["DESCRIPTION:\(esc(notes))", "URL:\(url.absoluteString)",
                  "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(esc(title))", "TRIGGER:-PT\(Self.alertMinutes)M", "END:VALARM",
                  "END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

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
