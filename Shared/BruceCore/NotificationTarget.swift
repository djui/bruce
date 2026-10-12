import Foundation

// Where a notification leads. `GET /v52/notification` carries only title, message, type and a photo, so the
// class is found by matching the message text against classes the app already knows (waitlist, bookings,
// bookmarks, loaded days), falling back to the studio named in the message.

extension BruceAPI.BruceNotification {
    enum Kind { case freeSpot, cancellation, reminder, other }
    var kind: Kind {
        let t = "\(type ?? "") \(title ?? "")".lowercased(), msg = (message ?? "").lowercased()
        if t.contains("free spot") || t.contains("standby") || msg.hasPrefix("available spot") { return .freeSpot }
        if t.contains("cancel") || msg.hasPrefix("cancellation") { return .cancellation }
        if t.contains("reminder") { return .reminder }
        return .other
    }
}

enum NotificationMatch {
    /// The day the message refers to: an explicit "2026-10-12", else "today" / "tomorrow" / a weekday name
    /// counted from the notification's own date.
    static func day(_ message: String, sentAt: Date?) -> Date? {
        let cal = BruceDate.calendar, lower = message.lowercased()
        if let r = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
           let d = BruceDate.parseDay(lower[r].replacingOccurrences(of: "-", with: "")) { return d }
        let base = cal.startOfDay(for: sentAt ?? Date())
        if lower.range(of: #"\btoday\b"#, options: .regularExpression) != nil { return base }
        if lower.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil { return cal.date(byAdding: .day, value: 1, to: base) }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (i, name) in names.enumerated() where lower.range(of: "\\b\(name)\\b", options: .regularExpression) != nil {
            let ahead = (i + 1 - cal.component(.weekday, from: base) + 7) % 7
            return cal.date(byAdding: .day, value: ahead, to: base)
        }
        return nil
    }

    /// "17:00" in the message (the last time given, which is the class start).
    static func time(_ message: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\b(\d{1,2}):(\d{2})\b"#),
              let m = re.matches(in: message, range: NSRange(message.startIndex..., in: message)).last,
              let hr = Range(m.range(at: 1), in: message), let mr = Range(m.range(at: 2), in: message),
              let h = Int(message[hr]) else { return nil }
        return String(format: "%02d:", h) + message[mr]
    }

    /// Best class for the message: title in the text, same start time, and on the day the message names (or
    /// within a week of it being sent). The longest matching title wins ("Yin Yoga" over "Yoga").
    static func bestClass(_ message: String, sentAt: Date?, in classes: [BruceAPI.BruceClass]) -> BruceAPI.BruceClass? {
        let lower = message.lowercased(), hhmm = time(message), day = day(message, sentAt: sentAt)
        let cal = BruceDate.calendar
        let from = cal.startOfDay(for: sentAt ?? Date()).addingTimeInterval(-86_400)
        return classes.filter { c in
            guard let start = c.start, lower.contains(c.title.lowercased()) else { return false }
            if let hhmm, BruceDate.time(start) != hhmm { return false }
            if let day { return cal.isDate(start, inSameDayAs: day) }
            return start >= from && start < from.addingTimeInterval(8 * 86_400)
        }
        .max { a, b in
            a.title.count != b.title.count ? a.title.count < b.title.count : (a.start ?? .distantPast) > (b.start ?? .distantPast)
        }
    }

    /// Studio named in the message (after the last comma in "…, CrossFit Södermalm"), else anywhere in it; the
    /// notification's photo is the studio's photo, so it breaks ties.
    static func bestStudio(_ message: String, photo: String?, in studios: [BruceAPI.Studio]) -> BruceAPI.Studio? {
        let lower = message.lowercased()
        let tail = lower.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if let s = studios.first(where: { $0.name.lowercased() == tail }) { return s }
        let named = studios.filter { lower.contains($0.name.lowercased()) }
        if let photo, let s = named.first(where: { $0.photo == photo }) ?? studios.first(where: { $0.photo == photo }) { return s }
        return named.max { $0.name.count < $1.name.count }
    }
}

extension AppModel {
    /// Classes the app already holds, the user's own lists first.
    private var knownClasses: [BruceAPI.BruceClass] {
        (standbys + promotedStandbys + bookmarks).compactMap(\.class) + bookings.compactMap(\.class)
            + pastBookings.compactMap(\.class) + Array(classDetails.values) + classesByDay.values.joined()
    }

    /// Route a notification opens without loading anything, if any.
    func notificationRoute(_ n: BruceAPI.BruceNotification) -> Route? {
        guard let msg = n.message, !msg.isEmpty else { return nil }
        if let c = NotificationMatch.bestClass(msg, sentAt: n.date, in: knownClasses) { return .classDetail(c.id) }
        return nil
    }

    /// Opens the class a notification is about (loading that day's classes if needed), else its studio.
    func openNotification(_ n: BruceAPI.BruceNotification) async {
        guard let msg = n.message, !msg.isEmpty else { return }
        var route = notificationRoute(n)
        if route == nil, let day = NotificationMatch.day(msg, sentAt: n.date) {
            await loadClasses(day: day)
            route = notificationRoute(n)
        }
        if route == nil, let s = NotificationMatch.bestStudio(msg, photo: n.meta?.photo, in: studios) { route = .studio(s.id) }
        guard let route else { flash("Couldn't find the class for this notification"); return }
        dismissSheets()
        push(route)
    }
}
