import Foundation

// What the Home Screen and Lock Screen widgets show (Bruce-iOS/BruceWidgets), written by the app into the App Group
// container after it loads the bookings and visit limits. The widget extension reads only this file: no Bruce
// login, no token and no network ever enter the extension. Compiled into the app and the extension.

struct WidgetSnapshot: Codable, Equatable {
    struct NextClass: Codable, Equatable {
        let classId: Int
        let title: String
        let studio: String
        let start: Date
        let end: Date
        let checkInFrom: Date
        let lateCheckIn: Date
        /// The strike steps (Copy.swift): free until `lateCancel`, 1 strike until `shortNotice`, 2 until `lastMinute`, then 3.
        let lateCancel: Date
        let shortNotice: Date
        let lastMinute: Date
        var checkedIn: Bool
    }
    var next: NextClass?
    /// Visits this month on the plan (`MONTHLY` limit); `visitsTotal` nil = unlimited, both nil = unknown.
    var visitsUsed: Int?
    var visitsTotal: Int?
    /// "October".
    var month: String
    var loggedIn: Bool
    var updatedAt: Date

    static let appGroup = "group.net.dauernheim.bruce"
    static let fileName = "widget-snapshot.json"
    /// Deep links the widgets and the Control open; the app handles the `bruece` scheme (Info.plist).
    static let scheme = "bruece"
    static let checkInURL = URL(string: "bruece://checkin")!
    static let visitsURL = URL(string: "bruece://visits")!
    static func classURL(_ id: Int) -> URL { URL(string: "bruece://class/\(id)")! }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(self) { try? d.write(to: url, options: .atomic) }
    }

    static let empty = WidgetSnapshot(next: nil, visitsUsed: nil, visitsTotal: nil, month: "", loggedIn: false, updatedAt: .distantPast)
}

extension WidgetSnapshot.NextClass {
    enum Tone { case free, warn, bad, checkIn, started }
    /// The line under the class on the widget at `now`, with its colour (the same tiers as the My classes chip).
    func status(at now: Date) -> (text: String, tone: Tone) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"
        if checkedIn { return ("Checked in", .checkIn) }
        if now >= start { return (now < end ? "Started · check-in closed" : "Ended", .started) }
        if now >= checkInFrom { return (now < lateCheckIn ? "Check-in open until \(f.string(from: lateCheckIn))" : "Check-in closed · 1 strike if late", .checkIn) }
        if now < lateCancel { return ("Free cancel until \(f.string(from: lateCancel))", .free) }
        if now < shortNotice { return ("Cancel now: 1 strike · 2 from \(f.string(from: shortNotice))", .warn) }
        if now < lastMinute { return ("Cancel now: 2 strikes · 3 from \(f.string(from: lastMinute))", .warn) }
        return ("Cancel now: 3 strikes", .bad)
    }
    /// Moments at which the status line changes (timeline entries), after `now`.
    func steps(after now: Date) -> [Date] {
        [lateCancel, shortNotice, lastMinute, checkInFrom, lateCheckIn, start, end].filter { $0 > now }.sorted()
    }
}
