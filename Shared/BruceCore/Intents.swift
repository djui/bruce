import AppIntents
import Foundation

// Siri and Shortcuts (App Intents). Shared by both apps; the AppModel instance is registered with
// `AppDependencyManager` in each app's `init`, so intents that run in the background (no window) still use the
// signed-in session. Every state-changing intent asks for confirmation first, like the in-app buttons.

// MARK: - Entities

/// An upcoming booking (not checked in, class not started yet).
struct BookingEntity: AppEntity {
    let id: Int
    let classId: Int?
    let title: String
    let studio: String
    let start: Date

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Booked class"
    static var defaultQuery = BookingQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(studio) · \(SiriData.when(start))")
    }
}

struct BookingQuery: EntityQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [Int]) async throws -> [BookingEntity] {
        try await SiriData.upcomingBookings(model).filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BookingEntity] {
        try await SiriData.upcomingBookings(model)
    }
}

/// A saved (bookmarked) class that starts later and is not booked yet: what "Book a class" offers.
struct SavedClassEntity: AppEntity {
    let id: Int
    let title: String
    let studio: String
    let start: Date

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Saved class"
    static var defaultQuery = SavedClassQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(studio) · \(SiriData.when(start))")
    }
}

struct SavedClassQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [Int]) async throws -> [SavedClassEntity] {
        try await SiriData.savedClasses(model).filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SavedClassEntity] {
        let q = string.trimmingCharacters(in: .whitespaces)
        return try await SiriData.savedClasses(model).filter {
            q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.studio.localizedCaseInsensitiveContains(q)
        }
    }

    func suggestedEntities() async throws -> [SavedClassEntity] {
        try await SiriData.savedClasses(model)
    }
}

// MARK: - Intents

struct UpcomingClassesIntent: AppIntent {
    static var title: LocalizedStringResource = "Upcoming classes"
    static var description = IntentDescription("Tells you your next booked class and how many classes you have booked.")

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[BookingEntity]> & ProvidesDialog {
        let list = try await SiriData.upcomingBookings(model)
        guard let next = list.first else {
            return .result(value: [], dialog: "You have no classes booked.")
        }
        let more = list.count == 1 ? "It's your only booked class." : "You have \(list.count) classes booked."
        return .result(value: list,
                       dialog: "Your next class is \(next.title) at \(next.studio), \(SiriData.when(next.start)). \(more)")
    }
}

struct CancelBookingIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel a booking"
    static var description = IntentDescription("Cancels one of your booked classes after you confirm.")

    @Parameter(title: "Class", requestValueDialog: "Which class do you want to cancel?")
    var booking: BookingEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary { Summary("Cancel \(\.$booking)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try SiriData.session(model)
        // Same late-cancel rule as the booking-rules sheet: past `unbookable_latest_time` a cancel can cost a strike.
        var late = false
        if let c = model.bookings.first(where: { $0.id == booking.id })?.class, let r = BookingRules(c) {
            late = Date() > r.lateCancel
        }
        let warning = late ? " The late cancellation window has passed, so this may count as a strike." : ""
        try await requestConfirmation(result: .result(dialog: "Cancel \(booking.title) at \(booking.studio), \(SiriData.when(booking.start))?\(warning)"),
                                      confirmationActionName: .go)
        try await SiriData.send(model, BruceAPI.cancelRequest(token: s.token, bookingId: booking.id))
        await model.loadMine()
        return .result(dialog: "Cancelled \(booking.title).")
    }
}

struct BookSavedClassIntent: AppIntent {
    static var title: LocalizedStringResource = "Book a saved class"
    static var description = IntentDescription("Books one of the classes you saved, after you confirm.")

    @Parameter(title: "Class", requestValueDialog: "Which saved class do you want to book?")
    var savedClass: SavedClassEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary { Summary("Book \(\.$savedClass)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try SiriData.session(model)
        try await requestConfirmation(result: .result(dialog: "Book \(savedClass.title) at \(savedClass.studio), \(SiriData.when(savedClass.start))?"),
                                      confirmationActionName: .go)
        try await SiriData.send(model, BruceAPI.bookRequest(token: s.token, classId: savedClass.id))
        await model.loadMine()
        return .result(dialog: "Booked \(savedClass.title).")
    }
}

struct VisitsLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Visits left"
    static var description = IntentDescription("Tells you how many visits you have used and have left this month.")

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try SiriData.session(model)
        let limits: [BruceAPI.VisitLimit]
        do { limits = try await BruceAPI.fetchVisitLimits(token: s.token, userId: s.userId) }
        catch { throw SiriData.mapped(error, model) }
        model.visitLimits = limits
        return .result(dialog: "\(SiriData.visitsSentence(limits))")
    }
}

/// Check-in needs the door QR or a confirmed suggestion, so this opens the app on the quick check-in sheet.
struct QuickCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check in"
    static var description = IntentDescription("Opens Brüce on the quick check-in suggestions.")
    static var openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        guard model.isLoggedIn else { throw SiriData.Failure.loggedOut }
        model.present(.quickCheckIn)
        return .result()
    }
}

// MARK: - Siri phrases

struct BruceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UpcomingClassesIntent(), phrases: [
            "What's my next class in \(.applicationName)",
            "When is my next \(.applicationName) class",
            "Show my \(.applicationName) classes",
            "My classes in \(.applicationName)",
        ], shortTitle: "Next class", systemImageName: "calendar.badge.checkmark")
        AppShortcut(intent: BookSavedClassIntent(), phrases: [
            "Book a class in \(.applicationName)",
            "Book a saved class in \(.applicationName)",
        ], shortTitle: "Book saved class", systemImageName: "bookmark")
        AppShortcut(intent: CancelBookingIntent(), phrases: [
            "Cancel a class in \(.applicationName)",
            "Cancel my \(.applicationName) booking",
        ], shortTitle: "Cancel booking", systemImageName: "calendar.badge.minus")
        AppShortcut(intent: VisitsLeftIntent(), phrases: [
            "How many visits do I have left in \(.applicationName)",
            "\(.applicationName) visits left",
        ], shortTitle: "Visits left", systemImageName: "figure.walk")
        AppShortcut(intent: QuickCheckInIntent(), phrases: [
            "Check in with \(.applicationName)",
            "Check in at the gym with \(.applicationName)",
        ], shortTitle: "Check in", systemImageName: "qrcode.viewfinder")
    }
}

// MARK: - Data

@MainActor
enum SiriData {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case loggedOut, demo, server(String)
        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .loggedOut: return "Open Brüce and log in first."
            case .demo: return "Siri doesn't work in demo mode."
            case .server(let m): return "\(m)"
            }
        }
    }

    static func session(_ m: AppModel) throws -> (token: String, userId: Int) {
        if AppModel.demo { throw Failure.demo }
        guard !m.token.isEmpty, let uid = m.userId else { throw Failure.loggedOut }
        return (m.token, uid)
    }

    /// 401 ends the session like everywhere else in the app; other errors become a sentence Siri can say.
    static func mapped(_ error: Error, _ m: AppModel) -> Error {
        if case BruceAPI.APIError.http(401, _) = error { m.expireSession(); return Failure.loggedOut }
        if error is URLError { return Failure.server("Brüce can't reach the server right now.") }
        return error
    }

    /// Sends a state-changing request; a non-2xx answer throws the server's reason.
    static func send(_ m: AppModel, _ req: URLRequest) async throws {
        let code: Int, body: String
        do { (code, body) = try await BruceAPI.perform(req) } catch { throw mapped(error, m) }
        if code == 401 { m.expireSession(); throw Failure.loggedOut }
        guard (200..<300).contains(code) else {
            throw Failure.server(BruceAPI.errorMessage(body) ?? "The server said no (HTTP \(code)).")
        }
    }

    static func upcomingBookings(_ m: AppModel) async throws -> [BookingEntity] {
        let s = try session(m)
        let all: [BruceAPI.Booking]
        do { all = try await BruceAPI.fetchBookings(token: s.token, userId: s.userId) } catch { throw mapped(error, m) }
        let names = studioNames(m)
        return all.compactMap { b -> BookingEntity? in
            guard !b.isCheckedIn, let c = b.class, c.canceled != true, let start = c.start, start > Date() else { return nil }
            return BookingEntity(id: b.id, classId: c.id, title: c.title,
                                 studio: c.studio?.name ?? names[c.studioId] ?? "the studio", start: start)
        }
        .sorted { $0.start < $1.start }
    }

    static func savedClasses(_ m: AppModel) async throws -> [SavedClassEntity] {
        let s = try session(m)
        let saved: [BruceAPI.ClassHolder], booked: [BruceAPI.Booking]
        do {
            async let a = BruceAPI.fetchBookmarks(token: s.token, userId: s.userId)
            async let b = BruceAPI.fetchBookings(token: s.token, userId: s.userId)
            (saved, booked) = try await (a, b)
        } catch { throw mapped(error, m) }
        let bookedIds = Set(booked.compactMap { $0.classId ?? $0.class?.id })
        let names = studioNames(m)
        return saved.compactMap(\.class).compactMap { c -> SavedClassEntity? in
            guard c.canceled != true, c.deleted != true, !bookedIds.contains(c.id), let start = c.start, start > Date() else { return nil }
            return SavedClassEntity(id: c.id, title: c.title, studio: c.studio?.name ?? names[c.studioId] ?? "the studio", start: start)
        }
        .sorted { $0.start < $1.start }
    }

    /// Studio names from the loaded list, else the disk cache (an intent can run before the app loaded studios).
    private static func studioNames(_ m: AppModel) -> [Int: String] {
        let list = m.studios.isEmpty ? (StudioCache.load()?.studios ?? []) : m.studios
        return Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// "today at 18:00", "tomorrow at 07:30", "Friday 17 October at 12:00".
    nonisolated static func when(_ d: Date) -> String {
        let cal = BruceDate.calendar
        let day = cal.isDateInToday(d) ? "today" : cal.isDateInTomorrow(d) ? "tomorrow" : BruceDate.format(d, "EEEE d MMMM")
        return "\(day) at \(BruceDate.time(d))"
    }

    /// Monthly visits (`MONTHLY`) plus Wellness visits when the plan includes them [API.md "Visit limits"].
    static func visitsSentence(_ limits: [BruceAPI.VisitLimit]) -> String {
        var parts: [String] = []
        if let v = limits.first(where: { $0.type == "MONTHLY" }) {
            switch v.state {
            case .limited(let t):
                let used = v.used ?? 0, left = v.remaining ?? max(t - used, 0)
                parts.append("You've used \(used) of \(t) visits this month, so \(left) \(left == 1 ? "is" : "are") left.")
            case .unlimited: parts.append("Your monthly visits are unlimited.")
            case .notIncluded, .unknown: break
            }
            if let r = v.resetDate { parts.append("They reset on \(BruceDate.format(r, "d MMMM")).") }
        }
        if let w = limits.first(where: { $0.type == "WELLNESS_MONTHLY" }), case .limited(let t) = w.state {
            let left = w.remaining ?? max(t - (w.used ?? 0), 0)
            parts.append("You have \(left) of \(t) Wellness visits left.")
        }
        return parts.isEmpty ? "Brüce didn't get your visit limits from the server." : parts.joined(separator: " ")
    }
}
