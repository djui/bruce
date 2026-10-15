import Foundation
#if os(iOS)
import UserNotifications
#endif

// Auto-book: "book this class every week". A class becomes bookable a fixed time before it starts
// (`bookable_earliest`, 7 days for ~97% of classes, measured Oct 2026; see API.md "Booking windows"), and classes
// are listed about 14 days ahead. So each weekly rule resolves to concrete class ids well before they open, and the
// booking request goes out at the open moment:
// - the running app (macOS, or iOS in the foreground) books by itself,
// - iOS schedules a notification at the open moment with a Book button that books from the lock screen,
// - an optional server (server/ in the repo) books even when no device is awake. The app syncs its rules there.

/// A weekly slot: same studio, weekday and local start time (Europe/Stockholm), and the same class series
/// (`master_id`) or, without one, the same title.
struct AutoBookRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var studioId: Int
    var masterId: Int?
    var title: String
    /// Calendar weekday in Europe/Stockholm, 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    /// Local start time in minutes after midnight.
    var minuteOfDay: Int
    var createdAt = Date()

    init?(_ c: BruceAPI.BruceClass) {
        guard let s = c.start else { return nil }
        let d = BruceDate.calendar.dateComponents([.weekday, .hour, .minute], from: s)
        studioId = c.studioId
        masterId = c.masterId
        title = c.title
        weekday = d.weekday ?? 1
        minuteOfDay = (d.hour ?? 0) * 60 + (d.minute ?? 0)
    }

    func matches(_ c: BruceAPI.BruceClass) -> Bool {
        guard c.studioId == studioId, c.isListed, let s = c.start else { return false }
        let d = BruceDate.calendar.dateComponents([.weekday, .hour, .minute], from: s)
        guard d.weekday == weekday, (d.hour ?? 0) * 60 + (d.minute ?? 0) == minuteOfDay else { return false }
        if let masterId, let m = c.masterId { return m == masterId }
        return c.title.caseInsensitiveCompare(title) == .orderedSame
    }

    /// "Tuesdays 18:00".
    var label: String {
        let names = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
        return "\(names[(weekday - 1 + 7) % 7]) \(String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60))"
    }
}

/// One upcoming class of a rule.
struct AutoBookOccurrence: Codable, Identifiable, Hashable {
    let classId: Int
    let ruleId: UUID
    let title: String
    let studioId: Int
    let start: Date
    /// When booking opens (`bookable_earliest_time`); start - 7 days when the class did not say.
    let opens: Date
    var id: Int { classId }
}

enum AutoBook {
    /// Used when a class carries no booking window (seen on ~1% of classes).
    static let defaultWindow: TimeInterval = 7 * 24 * 3600
    /// Classes are listed about 14 days ahead; one extra day covers the edge.
    static let lookaheadDays = 15
    /// After the open moment, failed booking attempts are retried this long (the server clock may be a bit behind).
    static let retryWindow: TimeInterval = 20

    // MARK: Local storage (rules and which classes were already handled)

    static func loadRules() -> [AutoBookRule] {
        guard let d = UserDefaults.standard.data(forKey: "autoBookRules") else { return [] }
        return (try? JSONDecoder().decode([AutoBookRule].self, from: d)) ?? []
    }
    static func saveRules(_ rules: [AutoBookRule]) {
        if let d = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(d, forKey: "autoBookRules") }
    }
    /// Class ids already booked or tried. A class is tried once: cancelling an auto-booked class does not rebook it.
    static var handled: Set<Int> {
        get { Set((UserDefaults.standard.array(forKey: "autoBookHandled") as? [Int]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.sorted().suffix(500)), forKey: "autoBookHandled") }
    }

    /// Full classes the user asked the server to book as soon as a spot on the waitlist frees up.
    static var watchedWaitlists: Set<Int> {
        get { Set((UserDefaults.standard.array(forKey: "autoBookWaitlistWatches") as? [Int]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.sorted().suffix(50)), forKey: "autoBookWaitlistWatches") }
    }

    // MARK: Finding the classes

    /// Upcoming classes for the rules (start in the future, not yet handled), soonest opening first.
    /// Reads each rule's studio only on the matching weekdays of the next `lookaheadDays` days.
    static func occurrences(token: String, rules: [AutoBookRule], now: Date = Date()) async -> [AutoBookOccurrence] {
        guard !rules.isEmpty else { return [] }
        let cal = BruceDate.calendar
        let today = cal.startOfDay(for: now)
        var wanted: Set<String> = []
        var fetches: [(studioId: Int, day: Date)] = []
        for r in rules {
            for i in 0..<lookaheadDays {
                guard let day = cal.date(byAdding: .day, value: i, to: today),
                      cal.component(.weekday, from: day) == r.weekday else { continue }
                if wanted.insert("\(r.studioId)-\(i)").inserted { fetches.append((r.studioId, day)) }
            }
        }
        var classes: [BruceAPI.BruceClass] = []
        await withTaskGroup(of: [BruceAPI.BruceClass].self) { g in
            for f in fetches {
                g.addTask { (try? await BruceAPI.fetchClasses(token: token, day: f.day, studioId: f.studioId, maxPages: 5)) ?? [] }
            }
            for await list in g { classes += list }
        }
        let done = handled
        var out: [Int: AutoBookOccurrence] = [:]
        for c in classes {
            guard let s = c.start, s > now, !done.contains(c.id), let r = rules.first(where: { $0.matches(c) }) else { continue }
            out[c.id] = AutoBookOccurrence(classId: c.id, ruleId: r.id, title: c.title, studioId: c.studioId, start: s,
                                           opens: c.bookingOpens ?? s.addingTimeInterval(-defaultWindow))
        }
        return out.values.sorted { $0.opens < $1.opens }
    }

    // MARK: Booking

    enum Outcome: Equatable {
        case booked, alreadyBooked, loggedOut
        case failed(String)
        var message: String {
            switch self {
            case .booked: return "Booked"
            case .alreadyBooked: return "Already booked"
            case .loggedOut: return "Not booked: please log in again"
            case .failed(let why): return "Not booked: \(why)"
            }
        }
    }

    /// `POST /v52/booking` at the open moment. A failure is retried every second until `retryWindow` after
    /// `opens` (a request a moment too early is refused); then the bookings are re-read, because a booking made
    /// elsewhere (the server, the other app) also counts.
    static func book(token: String, userId: Int?, classId: Int, opens: Date = .distantPast) async -> Outcome {
        guard !token.isEmpty, let req = try? BruceAPI.bookRequest(token: token, classId: classId) else { return .loggedOut }
        var last = "no answer"
        while true {
            if let r = try? await BruceAPI.perform(req) {
                let (code, body) = r
                if (200..<300).contains(code) { return .booked }
                if code == 401 { return .loggedOut }
                last = BruceAPI.errorMessage(body) ?? "HTTP \(code)"
            }
            guard Date() < opens.addingTimeInterval(retryWindow) else { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if let userId, let mine = try? await BruceAPI.fetchBookings(token: token, userId: userId),
           mine.contains(where: { ($0.classId ?? $0.class?.id) == classId }) { return .alreadyBooked }
        return .failed(last)
    }

    // MARK: iOS: a notification at the open moment with a Book button

    #if os(iOS)
    static let category = "AUTOBOOK"
    static let bookAction = "AUTOBOOK_BOOK"

    static func registerCategory() {
        let book = UNNotificationAction(identifier: bookAction, title: "Book", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [book], intentIdentifiers: [], options: []),
        ])
    }

    /// Asks for notification permission and registers for remote push (the token arrives in the app delegate).
    static func requestPermission() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { await MainActor.run { registerForPush?() } }
    }
    /// Set by the iOS app (UIApplication lives in the app target).
    @MainActor static var registerForPush: (@MainActor () -> Void)?

    /// Replaces the pending auto-book notifications with one per upcoming class (iOS keeps at most 64 pending).
    static func schedule(_ upcoming: [AutoBookOccurrence], studioNames: [Int: String] = [:]) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("autobook-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for o in upcoming.prefix(30) where o.opens > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Booking opens: \(o.title)"
            content.body = "\(BruceDate.format(o.start, "EEEE d MMMM, HH:mm")) at \(studioNames[o.studioId] ?? "the studio"). Tap Book to take a spot."
            content.sound = .default
            content.categoryIdentifier = category
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["classId": o.classId, "opens": o.opens.timeIntervalSince1970]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, o.opens.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "autobook-\(o.classId)", content: content, trigger: trigger))
        }
    }

    /// Handles a tap on the notification or its Book button: books with the stored session and reports the outcome
    /// as a follow-up notification. Works while the app is in the background.
    static func handle(_ response: UNNotificationResponse) async -> Int? {
        let info = response.notification.request.content.userInfo
        // A server push ("Booked: …") only opens the class.
        if response.notification.request.content.categoryIdentifier == "AUTOBOOK_RESULT" { return info["classId"] as? Int }
        guard response.notification.request.content.categoryIdentifier == category,
              let classId = info["classId"] as? Int else { return nil }
        let opens = (info["opens"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        let s = TokenStore.resolve()
        let outcome = await book(token: s?.accessToken ?? "", userId: s?.userId, classId: classId, opens: opens)
        handled.insert(classId)
        let content = UNMutableNotificationContent()
        content.title = outcome.message
        content.body = response.notification.request.content.title.replacingOccurrences(of: "Booking opens: ", with: "")
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "autobook-result-\(classId)", content: content, trigger: nil))
        return classId
    }
    #endif
}

// MARK: - Server (server/README.md)

/// The auto-book server. Its address is built in; the app signs in with the user's own Bruce login
/// (`X-Access-Token` + `X-User-Id`, checked by the server with Bruce), so there is no shared key and each user only
/// sees their own classes. The server keeps the login to book with it.
enum AutoBookServer {
    static let defaultURL = "https://bruce-autobook.uwe-af1.workers.dev"
    static var url: String {
        get { UserDefaults.standard.string(forKey: "autoBookServerURL").flatMap { $0.isEmpty ? nil : $0 } ?? defaultURL }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(v.isEmpty || v == defaultURL ? nil : v, forKey: "autoBookServerURL")
        }
    }
    static var isConfigured: Bool { URL(string: url)?.host != nil }
    /// "Let the server book for me": on by default; off removes everything from the server.
    static var booksForMe: Bool {
        get { UserDefaults.standard.object(forKey: "autoBookServerBooks") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoBookServerBooks") }
    }
    /// "Suggest classes when I skip a habit": the server pushes picks when a weekly class done 3+ weeks in a row is
    /// skipped and nothing is booked for 4 days (server/README.md). On by default; sent with the rules.
    static var habitNudges: Bool {
        get { UserDefaults.standard.object(forKey: "habitNudges") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "habitNudges") }
    }
    /// This device's APNs token (hex) once iOS registered for push; sent with the rules.
    static var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: "autoBookDeviceToken") }
        set { UserDefaults.standard.set(newValue, forKey: "autoBookDeviceToken") }
    }
    /// Debug builds run against Apple's sandbox push service, TestFlight/App Store builds against production.
    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    struct Status: Decodable {
        struct Entry: Decodable, Hashable { let classId: Int; let title: String?; let at: String?; let outcome: String? }
        let hasSession: Bool?
        let lastScan: String?
        let upcoming: [Entry]?
        let log: [Entry]?
        let devices: Int?
        struct Watch: Decodable, Hashable { let classId: Int; let title: String?; let start: String? }
        /// Full classes the server watches for a free waitlist spot.
        let waitlist: [Watch]?
    }

    static func request(_ method: String, _ path: String, session: Session, body: Any? = nil) throws -> URLRequest {
        guard let base = URL(string: url), base.host != nil, let uid = session.userId else { throw BruceAPI.APIError.notLoggedIn }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(session.accessToken, forHTTPHeaderField: "X-Access-Token")
        req.setValue(String(uid), forHTTPHeaderField: "X-User-Id")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    /// `PUT /me`: the rules (same JSON as stored locally), this device's push token, the skipped-habit setting, and
    /// with them the login.
    static func sync(_ rules: [AutoBookRule], session: Session) async throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        var body: [String: Any] = ["rules": try JSONSerialization.jsonObject(with: enc.encode(rules)), "nudges": habitNudges]
        if let t = deviceToken { body["device"] = ["token": t, "env": pushEnvironment] }
        try await BruceAPI.send(request("PUT", "me", session: session, body: body))
    }

    /// `DELETE /me`: the server forgets the login, rules and devices.
    static func remove(session: Session) async throws { try await BruceAPI.send(request("DELETE", "me", session: session)) }

    static func status(session: Session) async throws -> Status {
        try JSONDecoder().decode(Status.self, from: try await BruceAPI.send(request("GET", "me", session: session)))
    }

    /// `PUT|DELETE /me/waitlist/<classId>`: the server polls the full class and books it for the user as soon as a
    /// spot is free (Bruce itself only sends a "Free spot" notification), then sends a push. Also stores the login.
    static func watchWaitlist(_ on: Bool, classId: Int, session: Session) async throws {
        try await BruceAPI.send(request(on ? "PUT" : "DELETE", "me/waitlist/\(classId)", session: session))
    }

    /// `POST /me/test-push`: a test notification to this user's devices.
    static func testPush(session: Session) async throws { try await BruceAPI.send(request("POST", "me/test-push", session: session)) }
}

// MARK: - App state

extension AppModel {
    func autoBookRule(for c: BruceAPI.BruceClass) -> AutoBookRule? { autoBookRules.first { $0.matches(c) } }

    /// Class page toggle "Book every week".
    func setAutoBook(_ on: Bool, for c: BruceAPI.BruceClass) {
        if on {
            guard autoBookRule(for: c) == nil, let r = AutoBookRule(c) else { return }
            autoBookRules.append(r)
            flash("Booking \(c.title) every week when it opens")
        } else {
            autoBookRules.removeAll { $0.matches(c) }
        }
        rulesChanged()
    }

    func removeAutoBook(_ r: AutoBookRule) {
        autoBookRules.removeAll { $0.id == r.id }
        rulesChanged()
    }

    private func rulesChanged() {
        if !AppModel.demo { AutoBook.saveRules(autoBookRules) }
        Task {
            #if os(iOS)
            if !autoBookRules.isEmpty { await AutoBook.requestPermission() }   // also registers for remote push
            #endif
            await refreshAutoBook()
            await syncAutoBookServer()
        }
    }

    // MARK: Waitlist: book as soon as a spot frees up

    /// Whether the server is asked to book this (full, waitlisted) class when a spot opens up.
    func isWatchingWaitlist(_ classId: Int) -> Bool { watchedWaitlists.contains(classId) }

    /// Class page toggle "Book when a spot opens". Needs the server (the app cannot book while it is closed).
    func setWatchWaitlist(_ on: Bool, classId: Int) async {
        if AppModel.demo { if on { watchedWaitlists.insert(classId) } else { watchedWaitlists.remove(classId) }; return }
        guard tokenUsable, let s = session else { return }
        guard AutoBookServer.isConfigured, AutoBookServer.booksForMe else {
            flash("Switch on \"Let the server book for me\" in Auto-book first"); return
        }
        do {
            try await AutoBookServer.watchWaitlist(on, classId: classId, session: s)
            if on { watchedWaitlists.insert(classId) } else { watchedWaitlists.remove(classId) }
            AutoBook.watchedWaitlists = watchedWaitlists
            if on {
                #if os(iOS)
                await AutoBook.requestPermission()   // the booking result arrives as a push; also registers for it
                #endif
                await syncAutoBookServer()           // sends this device's push token
                flash("Will book it for you as soon as a spot opens up")
            }
        } catch { flash("Server: \(error.localizedDescription)") }
    }

    /// Whether the class page offers "Book when a spot opens": a class the user could not book (full or already
    /// waitlisted), not yet started and not booked.
    func offersWaitlistAutoBook(_ c: BruceAPI.BruceClass) -> Bool {
        guard isLoggedIn, let start = c.start, start > Date(), booking(forClass: c.id) == nil else { return false }
        return (c.availableSpots ?? 1) <= 0 || (standby(forClass: c.id) != nil && !isWatchingWaitlist(c.id))
            || isWatchingWaitlist(c.id)
    }

    /// The toggle: joins the waitlist first when needed, then asks the server to book when a spot is free.
    func setBookWhenSpotOpens(_ on: Bool, classId: Int) async {
        if on, !isOnWaitlist(classId) {
            await joinWaitlist(classId)
            guard isOnWaitlist(classId) else { return }
        }
        await setWatchWaitlist(on, classId: classId)
    }

    /// After the waitlist was re-read: a watched class the user is no longer waitlisted for was booked (by the
    /// server or by hand) or left, so the server stops watching it.
    func pruneWaitlistWatches() {
        let gone = watchedWaitlists.filter { standby(forClass: $0) == nil }
        guard !gone.isEmpty else { return }
        watchedWaitlists.subtract(gone)
        AutoBook.watchedWaitlists = watchedWaitlists
        guard !AppModel.demo, let s = session else { return }
        Task { for id in gone { try? await AutoBookServer.watchWaitlist(false, classId: id, session: s) } }
    }

    /// While "Let the server book for me" is on: sends the rules, the push token and the current login.
    func syncAutoBookServer() async {
        guard !AppModel.demo, tokenUsable, let s = session, AutoBookServer.isConfigured, AutoBookServer.booksForMe else { return }
        guard !autoBookRules.isEmpty || AutoBookServer.deviceToken != nil else { return }
        do { try await AutoBookServer.sync(autoBookRules, session: s); autoBookServerNote = nil }
        catch { autoBookServerNote = "Server sync failed: \(error.localizedDescription)" }
        await syncGoalReminders()   // goals that remind when behind (Goals.swift); skipped when unchanged
    }

    /// The "Let the server book for me" switch.
    func setServerBooksForMe(_ on: Bool) async {
        AutoBookServer.booksForMe = on
        if on { await syncAutoBookServer(); await refreshAutoBook(); return }
        UserDefaults.standard.removeObject(forKey: "goalReminderSync")   // DELETE /me clears the server's goals too
        guard let s = session else { return }
        do { try await AutoBookServer.remove(session: s); autoBookServerNote = nil }
        catch { autoBookServerNote = "Server: \(error.localizedDescription)" }
        await refreshAutoBook()
    }

    /// Next opening for a rule, if one of its classes is known.
    func nextAutoBook(_ r: AutoBookRule) -> AutoBookOccurrence? { autoBookUpcoming.first { $0.ruleId == r.id } }

    /// Resolves the rules to upcoming classes, schedules the iOS notifications and (re)starts the in-app booker.
    /// Called at start, when the app returns to the foreground and when the rules change.
    func refreshAutoBook() async {
        guard !AppModel.demo, tokenUsable, !autoBookRules.isEmpty else {
            autoBookUpcoming = []
            autoBookTask?.cancel(); autoBookTask = nil
            #if os(iOS)
            if !AppModel.demo { await AutoBook.schedule([]) }
            #endif
            return
        }
        let found = await AutoBook.occurrences(token: token, rules: autoBookRules)
        // A class that is already booked or waitlisted needs nothing.
        autoBookUpcoming = found.filter { booking(forClass: $0.classId) == nil && standby(forClass: $0.classId) == nil }
        #if os(iOS)
        // While the server books, its push reports the result; the local "Book" prompt is only the fallback.
        let names = Dictionary(autoBookUpcoming.map { ($0.studioId, studioName($0.studioId)) }, uniquingKeysWith: { a, _ in a })
        await AutoBook.schedule(AutoBookServer.booksForMe && AutoBookServer.isConfigured ? [] : autoBookUpcoming, studioNames: names)
        #endif
        startAutoBooker()
    }

    /// Books each upcoming class at its open moment while the app runs. A class whose window opened while the app
    /// was not running is booked as soon as the app runs again (if spots are left, the server takes it).
    private func startAutoBooker() {
        autoBookTask?.cancel()
        autoBookTask = Task { [weak self] in
            #if os(macOS)
            // Keep timers precise: without this, App Nap can delay a background app's wake-up by minutes.
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Auto-book")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            #endif
            while !Task.isCancelled {
                guard let self, let next = self.autoBookUpcoming.first else { return }
                let wait = next.opens.timeIntervalSinceNow - 0.5
                if wait > 0 {
                    // Sleep in steps of at most a minute so a changed system clock or a wake from sleep is noticed.
                    try? await Task.sleep(nanoseconds: UInt64(min(wait, 60) * 1_000_000_000))
                    continue
                }
                await self.autoBookNow(next)
            }
        }
    }

    private func autoBookNow(_ o: AutoBookOccurrence) async {
        autoBookUpcoming.removeAll { $0.classId == o.classId }
        AutoBook.handled.insert(o.classId)
        guard booking(forClass: o.classId) == nil else { return }
        let outcome = await AutoBook.book(token: token, userId: userId, classId: o.classId, opens: o.opens)
        if outcome == .loggedOut { expireSession() }
        flash("\(outcome.message): \(o.title), \(BruceDate.format(o.start, "EEE HH:mm"))")
        if outcome == .booked || outcome == .alreadyBooked { await loadMine() }
    }
}
