import SwiftUI
import CoreLocation
import UserNotifications
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// Shared by Bruce-MacOS (via the Sources/BruceMacOS/Shared symlink) and Bruce-iOS (Xcode file reference).
// Platform-neutral: navigation state, data, API calls and demo mode. No views live here.

enum Tab: Int, CaseIterable { case home, explore, checkIn, friends, myClasses }

enum Route: Hashable {
    case classDetail(Int)
    case studio(Int)
    case categories
    case category(Int)
    /// Home "For you": all recommended classes (Recommendations.swift).
    case forYou
    /// Monthly goals (Goals.swift), from My classes.
    case goals
    /// A challenge with friends by server id (Challenges.swift).
    case challenge(String)
    /// A race page by catalog id, or "custom-<uuid>" for a race added by hand (Races.swift).
    case race(String)
}

enum SheetRoute: Hashable {
    case notifications, menu, account, membership, visits, credits, strikes, payment
    case settings, login, checkIn, info(String)
    case search, selectCity, newArea, createAccount, resetPassword
    case ticket(Int), checkout(Int), editProfile, pause, plans, statistics, receipts, visitLimit(Int)
    case bookingRules(Int), classInvite(Int), invite, howItWorks, voucher, support, help, push, pushInfo, quickCheckIn
    case similarClasses(Int), area(UUID), parakey(Int)
    /// Add one booked class to the calendar (CalendarExport.swift).
    case addToCalendar(Int)
    /// Book again: the next class of a series the user went to (BookAgain.swift).
    case bookAgain(BookAgainTemplate)
    /// iPhone: the widget faces, for demo screenshots (WidgetBridge.swift).
    case widgets
    /// Auto-book rules and the optional server (AutoBook.swift).
    case autoBook
    /// "Rate class" dialog for a booking id (POST /v52/review [c8:467]).
    case review(Int)
    /// Settings › Places & commute (Recommendations.swift), and editing one place (nil = add).
    case places, editPlace(UUID?)
    /// Monthly goals (from Statistics) and the goal editor (nil = new goal).
    case goals, editGoal(UUID?)
    /// New challenge with friends (Challenges.swift).
    case newChallenge
    /// Add a race by hand, or edit one (nil = new; Races.swift).
    case editRace(UUID?)
    /// Train for it: a race's plan by its My races key (RacePlanner.swift).
    case racePlan(String)
    /// Start a crew for a race by its My races key (RaceSocial.swift).
    case newCrew(String)
    /// The member's result for a race by its My races key (Races.swift RaceResult).
    case raceResult(String)
}

@MainActor
@Observable
final class AppModel {
    // Navigation
    var tab: Tab = .home
    var stacks: [Tab: [Route]] = [:]
    var sheets: [SheetRoute] = []
    var wellnessOverlay = false
    var exploreCategories: Set<Int> = []
    var filterOpen = false
    var exploreMap = false
    // Filter panel state
    var accessTiers: Set<String> = []
    var favoritesOnly = false
    var currentlyOpen = false
    var soloOnly = false
    var hideFull = false
    /// Classes tab: time of day, duration, sort, bookable now (ClassFilters.swift).
    var classFilters = ClassFilterState()
    /// Saved custom areas (Areas.swift) and the one used as the Explore "Area" filter.
    var areas: [SavedArea] = []
    var selectedAreaId: UUID?
    /// Local until the area API is captured; demo mode keeps them in memory only.
    @ObservationIgnored lazy var areaStore: any AreaStore = AppModel.demo ? MemoryAreaStore(AppModel.demoAreas) : LocalAreaStore()
    /// "My area" filter active (= an area is selected). Setting false clears the selection.
    var customArea: Bool {
        get { selectedAreaId != nil }
        set { if !newValue { selectedAreaId = nil } }
    }
    /// Logged out: browse public data without an account.
    var sneakPeek = false
    var demoLoggedOut = false
    var demoExploreTab = 0
    var demoScrollBottom = false
    /// Class id whose ⋮ action sheet is open.
    var classActions: Int?
    var demoHoursOpen = false
    var demoCategoryTab = 0
    var demoStudioTab = 0
    var demoMyClassesTab = 0
    var demoFriendsTab = 0
    /// Demo: participant detail to open on the challenge page / Wrapped card to start at (99 = the last).
    var demoChallengeMember: Int?
    var demoWrappedCard = 0

    // Session & safety
    var session: Session? = AppModel.demo ? nil : TokenStore.resolve()
    /// `BRUCE_DEMO=1` (environment) or `-BRUCE_DEMO 1` (launch argument): offline UI preview with
    /// placeholder data; no API calls at all. The iOS app can also enter it from the welcome screen.
    nonisolated(unsafe) static var demo = AppModel.flag("BRUCE_DEMO")
    /// Public Cloudinary images and Apple map tiles. Off in demo mode unless BRUCE_DEMO_ASSETS=1.
    nonisolated static var remoteAssets: Bool { !demo || AppModel.flag("BRUCE_DEMO_ASSETS") }
    /// Environment variable, or a `-KEY 1` launch argument (lands in the UserDefaults argument domain).
    nonisolated static func flag(_ key: String) -> Bool {
        ProcessInfo.processInfo.environment[key] == "1" || UserDefaults.standard.string(forKey: key) == "1"
    }
    /// Environment variable or `-KEY value` launch argument.
    nonisolated static func setting(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key] ?? UserDefaults.standard.string(forKey: key)
    }
    /// Switch to the offline demo at runtime (iOS welcome screen "Try the offline demo").
    /// True when demo mode was switched on in the UI (not by flag); logging out then leaves demo mode.
    nonisolated(unsafe) static var demoAtRuntime = false
    func enterDemo() {
        AppModel.demo = true
        AppModel.demoAtRuntime = true
        session = nil
        demoLoggedOut = false
        sneakPeek = false
        loadDemo()
    }
    var status = ""
    /// Last failed load (shown as a retry banner); nil when the last refresh succeeded.
    var loadError: String?
    /// Device location when the user allowed it (iOS); distances and "Nearby" fall back to the city centre.
    var userLocation: CLLocation? { didSet { recomputeDistances() } }
    /// Studios pinned in the quick check-in list (local only).
    var checkInPins: Set<Int> = AppModel.demo ? [] : Set((UserDefaults.standard.array(forKey: "checkInPins") as? [Int]) ?? [])
    var toast: String?
    /// SF Symbol shown in front of the toast text (iOS), and the action behind its Undo button.
    var toastIcon: String?
    var toastUndo: (() -> Void)?
    var loading = false

    // Data
    var studios: [BruceAPI.Studio] = [] { didSet { studioIndex = Dictionary(studios.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }); recomputeDistances() } }
    private(set) var studioIndex: [Int: BruceAPI.Studio] = [:]
    /// Metres from `refLat/refLon` (user location or city centre) per studio id; recomputed when either changes.
    private(set) var studioDistances: [Int: Double] = [:]
    private func recomputeDistances() {
        let ref = CLLocation(latitude: refLat, longitude: refLon)
        var d: [Int: Double] = [:]
        for s in studios {
            guard let a = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
                  let lat = a.latitude, let lon = a.longitude else { continue }
            d[s.id] = CLLocation(latitude: lat, longitude: lon).distance(from: ref)
        }
        studioDistances = d
    }
    @ObservationIgnored private var studiosTask: Task<Void, Never>?
    @ObservationIgnored private var classDayTasks: [Date: Task<Void, Never>] = [:]
    /// Days (from today) already requested for a studio's Classes tab (loaded lazily, 14 days max).
    var studioClassDays: [Int: Int] = [:]
    @ObservationIgnored private var studioClassTasks: [Int: Task<Void, Never>] = [:]
    var categories: [BruceAPI.Category] = []
    var home: [BruceAPI.HomeSection] = []
    var classesByDay: [Date: [BruceAPI.BruceClass]] = [:]
    var classesLoadingDay: Date?
    var bookings: [BruceAPI.Booking] = []
    /// Auto-book (AutoBook.swift): weekly rules, their upcoming classes, and the last server sync problem.
    var autoBookRules: [AutoBookRule] = AppModel.demo ? [] : AutoBook.loadRules()
    var autoBookUpcoming: [AutoBookOccurrence] = []
    var autoBookServerNote: String?
    /// Waitlisted classes the server books as soon as a spot frees up (see AutoBook.swift).
    var watchedWaitlists: Set<Int> = AppModel.demo ? [] : AutoBook.watchedWaitlists
    /// Milestones already shown on Home (Milestones.swift).
    var milestonesSeen: Set<String> = AppModel.demo ? [] : Milestones.seen
    func markMilestoneSeen(_ key: String) { milestonesSeen.insert(key); if !AppModel.demo { Milestones.seen = milestonesSeen } }
    /// One-off classes to book the moment their window opens (AutoBook.swift `OpeningWatch`).
    var openingWatches: [OpeningWatch] = AppModel.demo ? [] : AutoBook.openingWatches
    @ObservationIgnored var autoBookTask: Task<Void, Never>?
    var standbys: [BruceAPI.ClassHolder] = []
    /// Waitlist entries that turned into bookings. The API drops a promoted entry from `GET /v52/standby` (its
    /// `booking_id` stays null) and the booking appears in `GET /v52/booking` [c7:80, 64]; the original keeps
    /// showing it in the Waitlist tab as "Booked". Kept only while a booking for that class exists.
    var promotedStandbys: [BruceAPI.ClassHolder] = []
    /// Rows of the Waitlist tab: current entries plus promoted ones, by class start.
    var waitlistRows: [BruceAPI.ClassHolder] {
        (standbys + promotedStandbys).sorted { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }
    }
    var bookmarks: [BruceAPI.ClassHolder] = []
    var notifications: [BruceAPI.BruceNotification] = []
    var friends: [BruceAPI.Friend] = []
    var user: BruceAPI.UserLite?
    var membership: BruceAPI.MembershipInfo?
    var visitLimits: [BruceAPI.VisitLimit] = []
    var blockInfo: BruceAPI.BlockInfo?
    var paymentMethods: [BruceAPI.PaymentMethod] = []
    var pastBookings: [BruceAPI.Booking] = []
    var classDetails: [Int: BruceAPI.BruceClass] = [:]
    var studioDetails: [Int: BruceAPI.Studio] = [:]

    var invites: [BruceAPI.Voucher] = []
    /// iOS: downloaded receipt PDF to preview (macOS opens it in Preview instead).
    var receiptURL: URL?
    /// Notifications created after this moment get the red "new" dot (the API's `read` flag is always false).
    var notificationsSeenAt: Date = {
        let t = UserDefaults.standard.double(forKey: "notificationsSeenAt")
        return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }()
    /// Pending confirmation for a state-changing action (book / cancel / check-in).
    var confirm: PendingAction?
    /// Simple OK alert (e.g. after joining a waitlist).
    var infoAlert: String?
    var reviews: [Int: [BruceAPI.Review]] = [:]
    var friendsBookings: [BruceAPI.FriendBooking] = []
    var classAttendees: [Int: [BruceAPI.ClassAttendee]] = [:]
    var notificationSetting: BruceAPI.NotificationSetting?
    var social: Bool?
    var payments: [BruceAPI.Payment] = []
    var aggregate: [BruceAPI.DayCount] = []
    /// Checked-in visit history (Statistics.swift `fetchVisitHistory`), shared by Statistics, goals,
    /// recommendations and Wrapped. nil until first read.
    var visitHistory: [BruceAPI.Visit]?
    @ObservationIgnored var visitHistoryLoadedAt = Date.distantPast
    @ObservationIgnored var visitHistoryTask: Task<[BruceAPI.Visit], Never>?
    /// Home "For you" (Recommendations.swift): saved places and commute settings (device only) and the ranked picks.
    var recSettings: RecSettings = AppModel.demo ? .demo : RecSettings.load()
    var recommendations: [Recommendation] = []
    var recommendationsLoading = false
    @ObservationIgnored var recommendTask: Task<Void, Never>?
    /// MapKit travel minutes by `Recommender.travelKey` (iOS), kept for the app's lifetime.
    @ObservationIgnored var travelOverrides: [String: Int] = [:]
    /// Monthly goals (Goals.swift), device only.
    var goals: [MonthlyGoal] = AppModel.demo ? MonthlyGoal.demo : MonthlyGoal.load()
    /// Race catalog (Races.swift): the published races.json, its last good copy on disk, demo races in demo mode.
    var races: [Race] = []
    /// Studios with an organiser's training status (the catalog's `trainingClubs`; Races.swift).
    var trainingClubs: [TrainingClub] = []
    var racesLoading = false
    var racesError: String?
    @ObservationIgnored var racesFetchedAt: Date?
    @ObservationIgnored var raceReminderTask: Task<Void, Never>?
    /// `PUT /me/races` one after the other (Races.swift `syncRaceServer`), so a quick on and off reaches the server in order.
    @ObservationIgnored var raceSyncTask: Task<Void, Never>?
    /// Train for it (RacePlanner.swift): this week's slots per race key, kept while the data they come from is the same.
    @ObservationIgnored var planWeekCache: [String: (sig: String, value: PlanWeekStatus)] = [:]
    /// My races (Races.swift), device only; demo mode keeps them in memory.
    var myRaces: [MyRace] = AppModel.demo ? [] : MyRaces.load()
    /// My classes shows its Races segment (Home's "My races", a race reminder).
    var showRacesInMyClasses = false
    /// Friends going (RaceSocial.swift): the caller's Bruce friends who share a race, by race id, from our server.
    var raceGoing = RaceGoing()
    @ObservationIgnored var raceGoingAt: Date?
    @ObservationIgnored var raceGoingTask: Task<Void, Never>?
    /// Explore switches to this segment when set (0 Studios, 1 Classes, 2 Races), then clears it.
    var exploreTabRequest: Int?
    /// Challenges with friends (Challenges.swift), from the auto-book server.
    var challenges: [ChallengeSummary] = []
    var challengeDetails: [String: ChallengeDetail] = [:]
    /// Bruce friends who have a row on our server ("Uses Brüce").
    var usesBruce: Set<Int> = []
    var challengesError: String?
    var challengesLoaded = false
    /// Brüce Wrapped full-screen story (Wrapped.swift).
    var wrappedOpen = false
    /// tier code -> (annual, monthly) SEK/month from GET /v52/membership/info (öre / 100).
    var planPrices: [String: (annual: Int, monthly: Int)] = [:]
    var membershipCommitmentMonths: Int? = nil
    var demoPausePicker = false
    func loadPlanPrices() async {
        guard tokenUsable, let uid = userId, planPrices.isEmpty else { return }
        for t in ["BASE", "BLACK", "EPIC"] {
            if let p = try? await BruceAPI.fetchPlanPrice(token: token, userId: uid, cityCode: city?.code ?? "STO", tier: t),
               let a = p.originalPrice, let f = p.originalFlexPrice { planPrices[t] = (a / 100, f / 100) }
        }
    }
    // Local-only preferences (no endpoint is called)
    var prefs: [String: Bool] = [:]
    /// Favourite studios (studio id -> favorite id), loaded from GET /v52/favorite (c5:39).
    var favoriteIds: [Int: Int] = [:]
    var favorites: Set<Int> { Set(favoriteIds.keys) }
    func loadAllFavorites() async {
        guard tokenUsable, let all = try? await BruceAPI.fetchAllFavorites(token: token) else { return }
        favoriteIds = Dictionary(all.compactMap { f in f.studioId.map { ($0, f.id) } }, uniquingKeysWith: { a, _ in a })
    }
    func loadFavorite(_ studioId: Int) async {
        guard tokenUsable else { return }
        if let f = try? await BruceAPI.fetchFavorite(token: token, studioId: studioId) { favoriteIds[studioId] = f.id }
    }
    func toggleFavorite(_ id: Int) {
        if let fid = favoriteIds[id] {
            favoriteIds[id] = nil
            guard !AppModel.demo else { return }
            Task { do { try await BruceAPI.removeFavorite(token: token, favoriteId: fid) } catch { favoriteIds[id] = fid; flash("Could not update favourite") } }
        } else {
            favoriteIds[id] = -1
            guard !AppModel.demo else { return }
            Task {
                do { favoriteIds[id] = try await BruceAPI.addFavorite(token: token, studioId: id).id }
                catch { favoriteIds[id] = nil; flash("Could not update favourite") }
            }
        }
    }
    func pref(_ k: String) -> Binding<Bool> {
        Binding(get: { self.prefs[k] ?? true }, set: { self.prefs[k] = $0 })
    }

    func askCheckIn(_ t: CheckInTarget) {
        confirm = PendingAction(title: "Check in at \(t.name)?", message: "\(t.subtitle)\nThis sends a real check-in to Bruce Studios.",
                                button: "Check in") { [weak self] in await self?.checkIn(t) }
    }

    var cities: [BruceAPI.City] = []
    var cityId = 1
    var city: BruceAPI.City? { cities.first { $0.id == cityId } }
    var cityName: String { city?.name ?? (cityId == 1 ? "Stockholm" : "City #\(cityId)") }
    /// Selected city's centre (map framing, "Entire city").
    var cityLat: Double { city?.coordinates?.latitude ?? 59.3293 }
    var cityLon: Double { city?.coordinates?.longitude ?? 18.0686 }
    /// Reference point for distances / home screen: the user's location when known, else the city centre.
    var refLat: Double { userLocation?.coordinate.latitude ?? cityLat }
    var refLon: Double { userLocation?.coordinate.longitude ?? cityLon }
    /// Wellness visits this month from GET /v52/studio/user_visit_limit (type WELLNESS_MONTHLY).
    var wellnessLimit: BruceAPI.VisitLimit? { visitLimits.first { $0.type == "WELLNESS_MONTHLY" } }
    /// "Wellness visits" row text: "used / total this month", "Unlimited", or "Not included" (BASE gets total -1 [c4]).
    var wellnessSummary: String {
        guard let w = wellnessLimit else { return "—" }
        switch w.state {
        case .limited(let t): return "\(w.used ?? 0) / \(t) this month"
        case .unlimited: return "Unlimited"
        case .notIncluded: return "Not included in your plan"
        case .unknown: return "—"
        }
    }
    /// Strike-unblock price from the city (nil until loaded).
    var unblockPriceKr: Int? { (city?.unlockPrice).map { $0 / 100 } }

    var token: String { session?.accessToken ?? "" }
    var isLoggedIn: Bool { (AppModel.demo && !demoLoggedOut) || !token.isEmpty }
    var showWelcome: Bool { !isLoggedIn && !sneakPeek }
    var userId: Int? { session?.userId }
    /// Set by the iPhone app: rewrites the widget snapshot after bookings or limits load (WidgetBridge.swift).
    @MainActor static var onDataChanged: ((AppModel) -> Void)?
    /// Bruce's webcal feed of all bookings (CalendarExport.swift); nil until the user record is loaded. A credential.
    var calendarFeedURL: URL? { CalendarFeed.url(userId: userId ?? user?.id, secret: user?.secret) }
    var unreadNotifications: Bool { notifications.contains { isNew($0) } }
    func isNew(_ n: BruceAPI.BruceNotification) -> Bool { (n.date ?? .distantPast) > notificationsSeenAt }
    func markNotificationsSeen() {
        notificationsSeenAt = Date()
        if !AppModel.demo { UserDefaults.standard.set(notificationsSeenAt.timeIntervalSince1970, forKey: "notificationsSeenAt") }
    }
    var tier: String { (membership?.membershipTier ?? membership?.admissionTier ?? "BASE").uppercased() }

    func booking(forClass id: Int) -> BruceAPI.Booking? { bookings.first { $0.classId == id || $0.class?.id == id } }
    /// Bookings not yet checked in: these count against "bookings at a time" (SIMULTANEOUS) and can be cancelled.
    var upcomingBookings: [BruceAPI.Booking] { bookings.filter { !$0.isCheckedIn } }

    // MARK: Post-class review ("Rate class") [c8:415, 467]

    /// From `GET /v52/booking?reviewable=true` (checked-in, ended, not yet rated).
    var reviewable: [BruceAPI.Booking] = []
    /// Booking ids the user skipped in the rating dialog. Local only, like the original's `skippedReview` flag;
    /// a skipped class can still be rated later from My classes / the class page.
    var skippedReviews: Set<Int> = AppModel.demo ? [] : Set((UserDefaults.standard.array(forKey: "skippedReviews") as? [Int]) ?? [])
    /// Booking ids already offered automatically in this run (the dialog opens at most once per booking per launch).
    @ObservationIgnored private var reviewPrompted: Set<Int> = []

    func reviewableBooking(forClass id: Int) -> BruceAPI.Booking? {
        reviewable.first { $0.classId == id || $0.class?.id == id }
    }
    func reviewBooking(_ bookingId: Int) -> BruceAPI.Booking? {
        reviewable.first { $0.id == bookingId } ?? bookings.first { $0.id == bookingId } ?? pastBookings.first { $0.id == bookingId }
    }

    /// Like the original: read the reviewable bookings at start (and with My classes) and open the rating dialog
    /// for the newest one that was not skipped, when nothing else is on screen.
    func loadReviewable() async {
        guard tokenUsable, let uid = userId else { return }
        guard let r = try? await BruceAPI.fetchReviewableBookings(token: token, userId: uid) else { return }
        reviewable = r.filter { $0.reviewId == nil }
        promptReviewIfNeeded()
    }

    func promptReviewIfNeeded() {
        guard sheets.isEmpty, confirm == nil, infoAlert == nil else { return }
        let next = reviewable
            .filter { !skippedReviews.contains($0.id) && !reviewPrompted.contains($0.id) }
            .max { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }
        guard let b = next else { return }
        reviewPrompted.insert(b.id)
        present(.review(b.id))
    }

    func skipReview(_ bookingId: Int) {
        skippedReviews.insert(bookingId)
        if !AppModel.demo { UserDefaults.standard.set(Array(skippedReviews), forKey: "skippedReviews") }
        dismissSheets()
    }

    /// `POST /v52/review` [c8:467]. `isPublic` false = the original's "Send (anonymous)".
    @discardableResult
    func submitReview(bookingId: Int, rating: Int, comment: String?, isPublic: Bool) async -> Bool {
        guard (1...5).contains(rating) else { return false }
        if AppModel.demo {
            reviewable.removeAll { $0.id == bookingId }
            flash("Demo: rating not sent (offline)"); return true
        }
        guard let req = try? BruceAPI.submitReviewRequest(token: token, bookingId: bookingId, rating: rating,
                                                         comment: comment, isPublic: isPublic) else { return false }
        guard await send(req, label: "Rating") else { return false }
        reviewable.removeAll { $0.id == bookingId }
        flash("Thanks for rating the class")
        return true
    }

    enum LimitState { case limited(Int), unlimited, notIncluded, unknown }
    var studioLimits: [Int: [BruceAPI.VisitLimit]] = [:]
    /// Per-studio limits; `force` re-reads them (the original re-reads `user_visit_limit` after book/cancel [c2:93-129]).
    func loadStudioLimits(_ studioId: Int, force: Bool = false) async {
        guard tokenUsable, let uid = userId, force || studioLimits[studioId] == nil else { return }
        if let l = try? await BruceAPI.fetchStudioLimits(token: token, userId: uid, studioId: studioId) { studioLimits[studioId] = l }
    }

    // MARK: Visit limit per studio (pill sheet, "Buy for SEK n")

    /// The `STUDIO` entry of `user_visit_limit?studio_id=` (total/used/remaining/resets_at, per-tier items).
    func studioVisitLimit(_ studioId: Int) -> BruceAPI.VisitLimit? {
        studioLimits[studioId]?.first { $0.type == "STUDIO" }
    }
    /// Monthly visit limit for every tier at a studio, in plan order (BASE, BLACK, EPIC, then any others).
    /// Source: the `STUDIO` limit's `items`, else the studio's own `visit_limit.items` from the studio list.
    /// `limit` 0 = unlimited, -1 = not included. FREE is left out (not a plan the user can pick).
    func tierLimits(_ studioId: Int) -> [(tier: String, limit: Int)] {
        func clean(_ items: [BruceAPI.VisitLimitItem]?) -> [(tier: String, limit: Int)] {
            (items ?? []).compactMap { i in
                guard let l = i.label?.uppercased(), !l.isEmpty, l != "FREE", let v = i.limit else { return nil }
                return (l, v)
            }
        }
        var out = clean(studioVisitLimit(studioId)?.items)
        if out.isEmpty { out = clean(studioDetails[studioId]?.visitLimit?.items) }
        if out.isEmpty { out = clean(studioIndex[studioId]?.visitLimit?.items) }
        let order = ["BASE": 0, "BLACK": 1, "EPIC": 2]
        return out.sorted { (order[$0.tier] ?? 9, $0.tier) < (order[$1.tier] ?? 9, $1.tier) }
    }
    /// When the studio's monthly visits reset: `resets_at`, else the first day of next month.
    func visitLimitReset(_ studioId: Int) -> Date {
        if let d = studioVisitLimit(studioId)?.resetDate { return d }
        let cal = BruceDate.calendar
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: 1, to: start) ?? Date()
    }
    /// True when the user's plan has no visits left at this class's studio this month. Uses the class's
    /// `visit_limit_reached` [c4:96] when present, else the studio's `STUDIO` limit (used >= total, or
    /// `within_limit == false`).
    func visitLimitReached(_ c: BruceAPI.BruceClass) -> Bool {
        if let r = c.attendance?.visitLimitReached { return r }
        guard let s = studioVisitLimit(c.studioId), let t = s.total, t > 0 else { return false }
        if s.withinLimit == false { return true }
        if let rem = s.remaining { return rem <= 0 }
        return (s.used ?? 0) >= t
    }
    /// Drop-in price in whole currency units: `user_attendance_info.price` (öre) / 100, e.g. 22000 -> SEK 220
    /// [c7:125]. `dynamic_prices` is not a price (all 0 there). Currency from the class (`"sek"`).
    func dropInPrice(_ c: BruceAPI.BruceClass) -> (amount: Int, currency: String)? {
        guard let ore = c.attendance?.price, ore > 0 else { return nil }
        return (ore / 100, (c.attendance?.currency ?? c.currency ?? "SEK").uppercased())
    }
    /// Studios in the selected city a tier can visit, counted from each studio's `visit_limit` items
    /// (-1 = not included). nil until studios with limits have loaded.
    func planStudioCount(_ tier: String) -> Int? {
        let l = cityStudios.compactMap { $0.visitLimit?.items?.first { $0.label?.uppercased() == tier.uppercased() }?.limit }
        return l.isEmpty ? nil : l.filter { $0 != -1 }.count
    }
    /// Studios in the selected city with unlimited visits (limit 0) for a tier.
    func planUnlimitedCount(_ tier: String) -> Int? {
        let l = cityStudios.compactMap { $0.visitLimit?.items?.first { $0.label?.uppercased() == tier.uppercased() }?.limit }
        return l.isEmpty ? nil : l.filter { $0 == 0 }.count
    }
    /// Unused invite codes from GET /v52/booking/voucher (nil when logged out).
    var openInvites: Int? { isLoggedIn ? invites.filter { !$0.accepted }.count : nil }
    /// SIMULTANEOUS limit ("bookings at a time", My classes pill) from user_visit_limit [c3:56].
    var simultaneousLimit: Int? { studioLimits.values.joined().first { $0.type == "SIMULTANEOUS" }?.total
        ?? visitLimits.first { $0.type == "SIMULTANEOUS" }?.total }
    func studioLimitState(_ studioId: Int) -> LimitState {
        if let s = studioLimits[studioId]?.first(where: { $0.type == "STUDIO" }), s.total != nil { return s.state }
        guard let items = studio(studioId)?.visitLimit?.items,
              let l = items.first(where: { $0.label?.uppercased() == tier })?.limit else { return .unknown }
        return l > 0 ? .limited(l) : l == 0 ? .unlimited : .notIncluded
    }
    var schedules: [Int: [BruceAPI.ScheduleEntry]] = [:]
    /// Upcoming classes per studio (next 14 days) for the studio page's Classes tab / "Show classes" row.
    var studioClasses: [Int: [BruceAPI.BruceClass]] = [:]
    /// A studio's upcoming classes, loaded lazily: the first 3 days, then 4 more per `loadMoreStudioClasses`
    /// (called when the list's end appears) up to 14 days. Days of a batch load concurrently.
    func loadStudioClasses(_ studioId: Int) async {
        guard studioClasses[studioId] == nil else { return }
        await loadStudioClassDays(studioId, upTo: 3)
    }
    func studioClassesComplete(_ id: Int) -> Bool { (studioClassDays[id] ?? 0) >= 14 }
    func loadMoreStudioClasses(_ studioId: Int) async {
        await loadStudioClassDays(studioId, upTo: min(14, (studioClassDays[studioId] ?? 0) + 4))
    }
    private func loadStudioClassDays(_ studioId: Int, upTo end: Int) async {
        guard !AppModel.demo else { return }
        if let t = studioClassTasks[studioId] { await t.value; return }
        let from = studioClassDays[studioId] ?? 0
        guard end > from else { return }
        let t = Task {
            let start = Date()
            let cal = BruceDate.calendar
            let today = cal.startOfDay(for: Date())
            let s = cal.date(byAdding: .day, value: from, to: today)!, e = cal.date(byAdding: .day, value: end, to: today)!
            do {
                let got = try await BruceAPI.fetchClassRange(token: tokenUsable ? token : nil, from: max(s, Date()), to: e, studioId: studioId, maxPages: 10)
                let merged = Dictionary(((studioClasses[studioId] ?? []) + got).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                studioClasses[studioId] = merged.values.filter { $0.canceled != true }.sorted { $0.startTime < $1.startTime }
                studioClassDays[studioId] = end
                debugTiming("studio \(studioId) classes days \(from)-\(end)", since: start, "\(got.count) classes")
            } catch {
                if studioClasses[studioId] == nil { studioClasses[studioId] = [] }
                handleLoadError(error, "Classes")
            }
        }
        studioClassTasks[studioId] = t
        await t.value
        studioClassTasks[studioId] = nil
    }

    func loadSchedule(_ studioId: Int) async {
        guard tokenUsable, schedules[studioId] == nil else { return }
        let from = BruceDate.calendar.startOfDay(for: Date())
        let to = BruceDate.calendar.date(byAdding: .day, value: 7, to: from)!.addingTimeInterval(-1)
        if let s = try? await BruceAPI.fetchOpeningSchedule(token: token, studioId: studioId, from: from, to: to) { schedules[studioId] = s }
    }
    /// Today's checked-in booking at a studio (ticket).
    func todaysCheckIn(studioId: Int) -> BruceAPI.Booking? {
        (pastBookings + bookings).first { b in
            (b.studioId ?? b.class?.studioId) == studioId &&
            b.checkedInAt.flatMap(BruceDate.parse).map { BruceDate.calendar.isDateInToday($0) } == true
        }
    }
    /// Studio visit limit for the user's tier ("0 / 2" pill). nil = unlimited / unknown.
    func studioLimit(_ studioId: Int) -> Int? {
        guard let items = studio(studioId)?.visitLimit?.items,
              let l = items.first(where: { $0.label?.uppercased() == tier })?.limit, l > 0 else { return nil }
        return l
    }
    /// Visits counted against the studio limit this month: checked-in + active bookings at that studio.
    func studioVisitsThisMonth(_ studioId: Int) -> Int {
        if let used = studioLimits[studioId]?.first(where: { $0.type == "STUDIO" })?.used { return used }
        let cal = BruceDate.calendar
        let all = pastBookings + bookings
        var ids = Set<Int>()
        for b in all where (b.studioId ?? b.class?.studioId) == studioId {
            if let d = b.class?.start, cal.isDate(d, equalTo: Date(), toGranularity: .month) { ids.insert(b.id) }
        }
        return ids.count
    }
    /// From /location/city `user_strike_block_un_lock_price` (öre/øre), 14000 = 140 kr in Stockholm.
    var unblockPrice: Int { (city?.unlockPrice).map { $0 / 100 } ?? 140 }

    /// Categories in API/alphabetical order (filter panel).
    var sortedCategories: [BruceAPI.Category] {
        categories.sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
    }
    /// Explore chip row: the first Home category (e.g. Gym) pinned, then alphabetical (as in the original).
    var chipCategories: [BruceAPI.Category] {
        let pinned = home.first { $0.type == "CATEGORIES" }?.items.first?.categoryId
        let s = sortedCategories
        guard let pinned, let first = s.first(where: { $0.id == pinned }) else { return s }
        return [first] + s.filter { $0.id != pinned }
    }

    var cityStudios: [BruceAPI.Studio] { studios.filter { $0.cityId == nil || $0.cityId == cityId } }
    /// O(1): rows call this for every visible class (was a linear scan over ~700 studios).
    func studio(_ id: Int) -> BruceAPI.Studio? { studioDetails[id] ?? studioIndex[id] }
    func studioName(_ id: Int) -> String { studio(id)?.name ?? "Studio #\(id)" }

    // MARK: Navigation

    var stack: [Route] { stacks[tab] ?? [] }
    func push(_ r: Route) { stacks[tab, default: []].append(r) }
    func pop() { _ = stacks[tab]?.popLast() }
    func select(_ t: Tab) {
        if t == .checkIn { present(.checkIn); return }
        if t == tab { stacks[t] = [] }
        tab = t
    }
    func present(_ s: SheetRoute) { sheets = [s] }
    func pushSheet(_ s: SheetRoute) { sheets.append(s) }
    func popSheet() { _ = sheets.popLast() }
    func dismissSheets() { sheets = []; wellnessOverlay = false }

    var activeFilterCount: Int {
        accessTiers.count + exploreCategories.count + [favoritesOnly, currentlyOpen, soloOnly, hideFull, customArea].filter { $0 }.count
            + classFilters.activeCount
    }
    func clearFilters() {
        accessTiers = []; exploreCategories = []
        favoritesOnly = false; currentlyOpen = false; soloOnly = false; hideFull = false; customArea = false
        classFilters = ClassFilterState()
    }
    func selectCity(_ id: Int) {
        guard id != cityId else { dismissSheets(); return }
        cityId = id; customArea = false; classesByDay = [:]
        dismissSheets()
        Task { await loadHome() }
    }
    func isBookmarked(_ classId: Int) -> Bool { bookmarks.contains { $0.class?.id == classId } }
    /// POST /v52/bookmark, DELETE /v52/bookmark/<bookmark id> [c3:73, 77]. Demo: local only.
    func toggleBookmark(_ classId: Int) {
        if let b = bookmarks.first(where: { $0.class?.id == classId }) {
            bookmarks.removeAll { $0.id == b.id }
            let undo: () -> Void = { [weak self] in self?.toggleBookmark(classId) }
            guard !AppModel.demo else { flash("Bookmark removed", icon: "bookmark.slash", undo: undo); return }
            Task {
                do { try await BruceAPI.removeBookmark(token: token, bookmarkId: b.id); flash("Bookmark removed", icon: "bookmark.slash", undo: undo) }
                catch { bookmarks.append(b); flash("Could not remove bookmark") }
            }
        } else {
            let c = findClass(classId)
            guard !AppModel.demo else { bookmarks.append(BruceAPI.ClassHolder(id: -classId, class: c)); flash("Bookmark added", icon: "bookmark.fill"); return }
            Task {
                do {
                    let ref = try await BruceAPI.addBookmark(token: token, classId: classId)
                    bookmarks.append(BruceAPI.ClassHolder(id: ref.id, class: c)); flash("Bookmark added", icon: "bookmark.fill")
                } catch { flash("Could not add bookmark") }
            }
        }
    }
    var bookmarkedClasses: [BruceAPI.BruceClass] { bookmarks.compactMap(\.class).sorted { $0.startTime < $1.startTime } }
    func findClass(_ id: Int) -> BruceAPI.BruceClass? {
        if let c = classDetails[id] ?? classesByDay.values.joined().first(where: { $0.id == id }) { return c }
        if let c = bookings.first(where: { $0.class?.id == id })?.class ?? bookmarks.first(where: { $0.class?.id == id })?.class { return c }
        return standbys.first { $0.class?.id == id }?.class ?? studioClasses.values.joined().first { $0.id == id }
    }

    func toggleCategory(_ id: Int) {
        if exploreCategories.contains(id) { exploreCategories.remove(id) } else { exploreCategories.insert(id) }
    }

    func startSneakPeek() async {
        sneakPeek = true
        tab = .explore   // the public studio list is what a sneak peek can show
        if AppModel.demo { return }
        async let cats: Void = loadCategoriesIfNeeded()   // GET /v52/category is public too (chip row)
        await loadStudios()   // GET /v52/studio/filter works without a token
        await cats
    }

    func flash(_ s: String, icon: String? = nil, undo: (() -> Void)? = nil) {
        toast = s; toastIcon = icon; toastUndo = undo
        Task { try? await Task.sleep(nanoseconds: (undo == nil ? 3_500 : 5_000) * 1_000_000); if toast == s { dismissToast() } }
    }
    func dismissToast() { toast = nil; toastIcon = nil; toastUndo = nil }

    // MARK: Auth

    func login(email: String, password: String) async {
        if AppModel.demo { flash("Demo mode: login is disabled (offline)"); return }
        loading = true; status = "Logging in…"
        defer { loading = false }
        do {
            let r = try await BruceAPI.authenticate(email: email, password: password)
            let s = Session(accessToken: r.accessToken, refreshToken: r.refreshToken,
                            accessTokenExpiresAt: r.accessTokenExpiresAt,
                            refreshTokenExpiresAt: r.refreshTokenExpiresAt, userId: r.userId)
            TokenStore.save(s)
            session = s
            RaceReminders.forgetServer()   // a new login sends the race reminders again (Races.swift)
            status = "Logged in."
            dismissSheets()
            await bootstrap()
        } catch {
            status = "Login failed: \(error.localizedDescription)"
        }
    }

    func logout() async {
        if !AppModel.demo, !token.isEmpty, let req = try? BruceAPI.logoutRequest(token: token) {
            _ = try? await BruceAPI.perform(req)
        }
        TokenStore.clear()
        session = nil
        sneakPeek = false
        if AppModel.demo && AppModel.demoAtRuntime {
            // Leave the runtime demo completely so a later real login loads real data and real images.
            AppModel.demo = false; AppModel.demoAtRuntime = false
            resetLoadedData()
        } else if AppModel.demo { demoLoggedOut = true }
        bookings = []; standbys = []; promotedStandbys = []; bookmarks = []; notifications = []; friends = []; reviewable = []
        user = nil; membership = nil; visitLimits = []; blockInfo = nil; paymentMethods = []
        visitHistory = nil; recommendations = []; challenges = []; challengeDetails = [:]; usesBruce = []; challengesLoaded = false
        raceGoing = RaceGoing(); raceGoingAt = nil
        Task { await refreshAutoBook() }   // logged out: stops the booker and clears its notifications
        dismissSheets()
    }

    func handleLoadError(_ error: Error, _ label: String) {
        if case BruceAPI.APIError.http(401, _) = error { expireSession(); return }
        if (error as? URLError)?.code == .cancelled { return }
        status = "\(label): \(error.localizedDescription)"
        loadError = (error as? URLError) != nil ? "You're offline or the server can't be reached." : "Couldn't load \(label.lowercased())."
    }

    /// Access token rejected by the server (HTTP 401): forget it and ask for a fresh login. There is no refresh
    /// call: the original app never sends `refresh_token` (captures 1-8) and only stores the access token. The
    /// server keeps accepting an access token long after its `access_token_expires_at` (the token from the c2
    /// login, "expiring" 3 h later, still got 211 x 200 in c8 about 27 h after that), so only a 401 ends a session.
    func expireSession() {
        guard session != nil else { return }
        TokenStore.clear()
        session = nil
        sneakPeek = false
        bookings = []; standbys = []; promotedStandbys = []; bookmarks = []; notifications = []; friends = []; reviewable = []
        user = nil; membership = nil; visitLimits = []; blockInfo = nil; paymentMethods = []
        visitHistory = nil; recommendations = []; challenges = []; challengeDetails = [:]; usesBruce = []; challengesLoaded = false
        raceGoing = RaceGoing(); raceGoingAt = nil
        Task { await refreshAutoBook() }   // logged out: stops the booker and clears its notifications
        resetLoadedData()
        status = "Your session expired. Please log in again."
        sheets = [.login]
    }

    /// Drop every cached collection (used when leaving the runtime demo).
    func resetLoadedData() {
        studios = []; categories = []; home = []; classesByDay = [:]; classDetails = [:]; studioDetails = [:]
        schedules = [:]; studioClasses = [:]; studioLimits = [:]; reviews = [:]; pastBookings = []
        friendsBookings = []; classAttendees = [:]; invites = []; payments = []; aggregate = []; favoriteIds = [:]
        notificationSetting = nil; social = nil; stacks = [:]; tab = .home
    }

    /// Logged in with a token. `access_token_expires_at` is deliberately ignored (see `expireSession`).
    var tokenUsable: Bool { !AppModel.demo && !token.isEmpty }

    // MARK: Loading (read-only GETs)

    func bootstrap() async {
        await loadAreas()   // local store: no network
        if AppModel.demo { loadDemo(); return }
        Task { await loadRaces() }   // public catalog file (Races.swift), also logged out
        guard tokenUsable else { return }   // logged out: welcome screen; sneak peek loads public data
        if let c = try? await BruceAPI.fetchCities(token: token), !c.isEmpty { cities = c }
        async let a: Void = loadStudios()
        async let b: Void = loadHome()
        async let c: Void = loadMine()
        async let d: Void = loadSocial()
        async let e: Void = loadAccount()
        async let f: Void = loadVisits()
        async let g: Void = loadAllFavorites()
        _ = await (a, b, c, d, e, f, g)
        await refreshAutoBook()   // after loadMine: booked classes are skipped
        await syncAutoBookServer()   // hands a new login and push token to the server
    }

    /// Studio list: cached copy instantly, then a fast streamed refresh (see FastLoading.swift).
    /// Concurrent callers share one in-flight load. Logged out it uses the same public endpoint.
    func loadStudios(force: Bool = false) async {
        if AppModel.demo { return }
        if let t = studiosTask { await t.value; return }
        let t = Task { await self.refreshStudios(force: force) }
        studiosTask = t
        await t.value
        studiosTask = nil
    }

    private func refreshStudios(force: Bool) async {
        let start = Date()
        if studios.isEmpty, let cached = await Task.detached(priority: .userInitiated, operation: { StudioCache.load() }).value {
            studios = cached.studios
            debugTiming("studios from disk cache", since: start, "\(cached.studios.count) studios")
            if !force && StudioCache.isFresh(cached) { return }
        }
        var byId = Dictionary(studios.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var firstPage = true
        var expire: Int?
        do {
            var lastPublish = Date.distantPast
            let all = try await BruceAPI.fetchStudiosFast(token: tokenUsable ? token : nil, knownIds: Array(byId.keys)) { page, light, exp in
                expire = exp
                for s in page where !light || byId[s.id] == nil { byId[s.id] = s }
                // Coalesce: at most ~3 UI updates per second while pages stream in (each update re-sorts lists).
                if firstPage || Date().timeIntervalSince(lastPublish) > 0.33 {
                    lastPublish = Date()
                    self.studios = Array(byId.values)
                }
                if firstPage { firstPage = false; debugTiming("studios first page", since: start, light ? "(light)" : "(full)") }
            }
            studios = all   // exact current set (drops studios that went offline)
            let toSave = all, exp = expire
            Task.detached(priority: .utility) { StudioCache.save(toSave, expire: exp) }   // JSON encode off the main actor
            loadError = nil
            debugTiming("studios all", since: start, "\(all.count) studios")
        } catch { handleLoadError(error, "Studios") }
    }

    func loadCategoriesIfNeeded() async {
        guard !AppModel.demo, categories.isEmpty else { return }
        if let c = try? await BruceAPI.fetchCategories(token: tokenUsable ? token : nil) { categories = c }
    }

    func loadHome() async {
        guard tokenUsable else { return }
        do { home = try await BruceAPI.fetchHomeScreen(token: token, lat: refLat, lon: refLon) } catch { handleLoadError(error, "Home") }
        do { categories = try await BruceAPI.fetchCategories(token: token) } catch {}
    }

    func loadMine() async {
        guard tokenUsable, let uid = userId else { return }
        mineLoadedAt = Date()
        do {
            // Keep checked-in classes: the original lists them in My classes (with the ticket) for the whole
            // 24 h window of the request [c8:404, 410]. Unchecked past classes still drop an hour after start.
            bookings = try await BruceAPI.fetchBookings(token: token, userId: uid)
                .filter { b in b.class != nil && (b.isCheckedIn || (b.class?.start ?? .distantPast) > Date().addingTimeInterval(-3600)) }
        } catch { handleLoadError(error, "Bookings") }
        if let fresh = try? await BruceAPI.fetchStandbys(token: token, userId: uid) {
            // Replace the list (no stale rows); an entry that vanished and now has a booking moved to "Booked".
            let freshIds = Set(fresh.compactMap { $0.class?.id })
            var seen = Set<Int>()
            promotedStandbys = (standbys + promotedStandbys).filter { s in
                guard let cid = s.class?.id, !freshIds.contains(cid), booking(forClass: cid) != nil else { return false }
                return seen.insert(cid).inserted
            }
            standbys = fresh
            // The standby list carries the class's current `available_spots`; keep an open class page in step.
            for s in fresh { if let c = s.class, let d = classDetails[c.id], d.availableSpots != c.availableSpots { classDetails[c.id]?.availableSpots = c.availableSpots } }
            pruneWaitlistWatches()
        }
        bookmarks = (try? await BruceAPI.fetchBookmarks(token: token, userId: uid)) ?? []
        await loadReviewable()
        pruneOpeningWatches()
        AppModel.onDataChanged?(self)
        if !AppModel.demo { await CancelReminders.sync(bookings: bookings, studioName: studioName) }
    }

    /// Settings › "Last free cancel reminder" (CancelReminders.swift): asks for notification permission when turned on.
    func setCancelReminders(_ on: Bool) {
        CancelReminders.enabled = on
        cancelRemindersOn = on
        Task {
            if on { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            await CancelReminders.sync(bookings: bookings, studioName: studioName)
        }
    }
    var cancelRemindersOn = CancelReminders.enabled

    func loadSocial() async {
        guard tokenUsable, let uid = userId else { return }
        notifications = (try? await BruceAPI.fetchNotifications(token: token, userId: uid)) ?? []
        // A "Free spot" or cancellation newer than the last bookings/waitlist read means those lists are stale.
        if notifications.contains(where: { $0.kind != .other && ($0.date ?? .distantPast) > (mineLoadedAt ?? .distantPast) }) {
            await loadMine()
        }
        friends = (try? await BruceAPI.fetchFriends(token: token, userId: uid)) ?? []
        friendsBookings = (try? await BruceAPI.fetchFriendsBookings(token: token, userId: uid)) ?? []
    }

    func loadReviews(_ studioId: Int) async {
        guard tokenUsable, reviews[studioId] == nil else { return }
        if let r = try? await BruceAPI.fetchReviews(token: token, studioId: studioId) { reviews[studioId] = r }
    }

    func loadSettings() async {
        guard tokenUsable, let uid = userId else { return }
        notificationSetting = try? await BruceAPI.fetchNotificationSetting(token: token, userId: uid)
        if let u = try? await BruceAPI.fetchUser(token: token, userId: uid) { user = u; social = u.social }
    }

    /// PUT /v52/user/<id>/notification_setting/<id> [c3:319-332]. Sent when the user flips a toggle.
    func setMarketing(_ field: String, _ on: Bool) {
        guard var s = notificationSetting else { return }
        switch field { case "marketing_email": s.marketingEmail = on; case "marketing_push": s.marketingPush = on; default: s.marketingSms = on }
        notificationSetting = s
        guard !AppModel.demo, let uid = userId else { return }
        Task { try? await BruceAPI.updateNotificationSetting(token: token, userId: uid, settingId: s.id, body: [field: on]) }
    }
    func setPushType(_ key: String, _ on: Bool) {
        guard var s = notificationSetting, var types = s.types, let i = types.firstIndex(where: { $0.key == key }) else { return }
        types[i].enabled = on; s.types = types; notificationSetting = s
        guard !AppModel.demo, let uid = userId else { return }
        let body: [String: Any] = ["types": types.map { ["key": $0.key, "enabled": $0.enabled] }]
        Task { try? await BruceAPI.updateNotificationSetting(token: token, userId: uid, settingId: s.id, body: body) }
    }
    /// PUT /v52/user/<id> {"social": bool} [c3:280, 287].
    func setSocial(_ on: Bool) {
        social = on
        guard !AppModel.demo, let uid = userId else { return }
        Task { try? await BruceAPI.setSocial(token: token, userId: uid, social: on) }
    }

    func loadPayments() async {
        guard tokenUsable, let uid = userId else { return }
        payments = (try? await BruceAPI.fetchPayments(token: token, userId: uid)) ?? []
    }
    func loadAggregate() async {
        guard tokenUsable, let uid = userId else { return }
        aggregate = (try? await BruceAPI.fetchBookingAggregate(token: token, userId: uid)) ?? []
    }
    func openReceipt(_ p: BruceAPI.Payment) {
        guard !AppModel.demo else { flash("Demo: no receipt"); return }
        Task {
            do {
                let data = try await BruceAPI.fetchReceiptPDF(token: token, paymentId: p.id)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("bruce-receipt-\(p.id).pdf")
                try data.write(to: url)
                #if canImport(AppKit)
                NSWorkspace.shared.open(url)
                #else
                receiptURL = url
                #endif
            } catch { flash("Could not load receipt") }
        }
    }

    // MARK: Waitlist (POST/DELETE /v52/standby [c3:65, 69])
    func standby(forClass id: Int) -> BruceAPI.ClassHolder? { standbys.first { $0.class?.id == id } }
    /// Row badge for a class the user is (or was) on the waitlist for: "Booked" once the user has a booking for
    /// it (matched by class id), "Spot open" while the class has a free spot, else "Waitlist".
    func waitlistBadge(_ classId: Int) -> String? {
        if booking(forClass: classId) != nil,
           standby(forClass: classId) != nil || promotedStandbys.contains(where: { $0.class?.id == classId }) { return "Booked" }
        if waitlistSpotOpen(classId) { return Copy.spotOpen }
        return standby(forClass: classId) != nil ? "Waitlist" : nil
    }
    /// On the waitlist, not booked, and the class has a free spot again. A "Free spot" notification goes to the
    /// waitlist but does not book: the entry stays in `GET /v52/standby` until the user books the spot (or someone
    /// else takes it), so the class's `available_spots` is the only sign. Uses the freshest copy of the class.
    func waitlistSpotOpen(_ classId: Int) -> Bool {
        guard let s = standby(forClass: classId), booking(forClass: classId) == nil else { return false }
        return ((classDetails[classId] ?? s.class)?.availableSpots ?? 0) > 0
    }
    /// The user is on this class's waitlist (from GET /v52/standby; the class payload has no such flag).
    func isOnWaitlist(_ classId: Int) -> Bool { standby(forClass: classId) != nil }
    /// Friends booked on a class (GET /v52/booking?friends=true joined with GET /v52/friend), once per friend.
    func friendsBooked(_ classId: Int) -> [BruceAPI.UserLite] {
        var seen = Set<Int>()
        return friendsBookings.filter { $0.classId == classId || $0.class?.id == classId }
            .compactMap { b in friends.first { $0.friendUser?.id == b.userId }?.friendUser }
            .filter { seen.insert($0.id).inserted }
    }
    /// Wellness class = class at a studio labelled `WELLNESS` (the class payload carries no wellness flag;
    /// the same label drives the Wellness filter and the WELLNESS_MONTHLY visit limit).
    func isWellness(studioId: Int) -> Bool { studio(studioId)?.label?.uppercased() == "WELLNESS" }
    func joinWaitlist(_ classId: Int) async {
        if AppModel.demo {
            standbys.append(BruceAPI.ClassHolder(id: -classId, class: findClass(classId)))
            infoAlert = Copy.waitlistJoined; return
        }
        guard let req = try? BruceAPI.joinWaitlistRequest(token: token, classId: classId) else { return }
        if await send(req, label: "Join waitlist") { infoAlert = Copy.waitlistJoined }
        await loadMine()
    }
    func askLeaveWaitlist(_ classId: Int) {
        guard let s = standby(forClass: classId) else { return }
        confirm = PendingAction(title: Copy.leaveWaitlist, message: "", button: "Leave waitlist") { [weak self] in
            guard let self else { return }
            if AppModel.demo { self.standbys.removeAll { $0.id == s.id }; self.pruneWaitlistWatches(); return }
            if self.isWatchingWaitlist(s.class?.id ?? 0) { await self.setWatchWaitlist(false, classId: s.class?.id ?? 0) }
            guard let req = try? BruceAPI.leaveWaitlistRequest(token: self.token, standbyId: s.id) else { return }
            await self.send(req, label: "Leave waitlist")
            await self.loadMine()
        }
    }

    func loadAccount() async {
        guard tokenUsable, let uid = userId else { return }
        user = try? await BruceAPI.fetchUser(token: token, userId: uid)
        membership = try? await BruceAPI.fetchMembership(token: token, userId: uid)
        visitLimits = (try? await BruceAPI.fetchVisitLimits(token: token, userId: uid)) ?? []
        blockInfo = try? await BruceAPI.fetchBlockInfo(token: token, userId: uid)
        paymentMethods = (try? await BruceAPI.fetchPaymentMethods(token: token, userId: uid)) ?? []
        invites = (try? await BruceAPI.fetchVouchers(token: token, userId: uid)) ?? []
        AppModel.onDataChanged?(self)
    }

    func loadVisits() async {
        guard tokenUsable, let uid = userId else { return }
        pastBookings = ((try? await BruceAPI.fetchPastBookings(token: token, userId: uid)) ?? [])
            .filter { $0.checkedInAt != nil }
            .sorted { ($0.class?.startTime ?? "") > ($1.class?.startTime ?? "") }
    }

    /// One city day: time windows in parallel, results shown page by page; shared in-flight task per day.
    func loadClasses(day: Date) async {
        let key = BruceDate.calendar.startOfDay(for: day)
        guard !AppModel.demo, classesByDay[key] == nil else { return }
        if let t = classDayTasks[key] { await t.value; return }
        let t = Task {
            let start = Date()
            classesLoadingDay = key
            defer { if classesLoadingDay == key { classesLoadingDay = nil } }
            var acc: [Int: BruceAPI.BruceClass] = [:]
            do {
                var lastPublish = Date.distantPast
                let all = try await BruceAPI.fetchClassDayFast(token: tokenUsable ? token : nil, day: key, cityId: cityId) { page in
                    for c in page { acc[c.id] = c }
                    if Date().timeIntervalSince(lastPublish) > 0.33 {
                        lastPublish = Date()
                        self.classesByDay[key] = acc.values.sorted { $0.startTime < $1.startTime }
                    }
                }
                classesByDay[key] = all
                debugTiming("classes day \(BruceDate.format(key, "d MMM"))", since: start, "\(all.count) classes")
            } catch {
                if acc.isEmpty { classesByDay[key] = nil }
                handleLoadError(error, "Classes")
            }
        }
        classDayTasks[key] = t
        await t.value
        classDayTasks[key] = nil
    }

    /// Several days with bounded concurrency (each day is itself split into parallel windows).
    func loadClassDays(_ days: [Date], concurrency: Int = 2) async {
        var it = days.makeIterator()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<concurrency { if let d = it.next() { g.addTask { await self.loadClasses(day: d) } } }
            while await g.next() != nil { if let d = it.next() { g.addTask { await self.loadClasses(day: d) } } }
        }
    }

    func loadClassDetail(_ id: Int) async {
        guard tokenUsable else { return }
        if var c = try? await BruceAPI.fetchClass(token: token, id: id) {
            if c.classCategories == nil {
                c.classCategories = classesByDay.values.joined().first { $0.id == id }?.classCategories
            }
            classDetails[id] = c
            await loadStudioDetail(c.studioId)
        }
    }

    /// "Similar classes" for a class (GET /v52/studio/class/alternative_recommendation [c7:24, 41]).
    var similarClasses: [Int: [BruceAPI.ClassCard]] = [:]
    func loadSimilarClasses(_ classId: Int) async {
        guard tokenUsable, similarClasses[classId] == nil else { return }
        do { similarClasses[classId] = try await BruceAPI.fetchSimilarClasses(token: token, classId: classId) }
        catch { similarClasses[classId] = []; handleLoadError(error, "Similar classes") }
    }

    func loadClassAttendees(_ id: Int) async {
        guard tokenUsable else { return }
        if let a = try? await BruceAPI.fetchClassAttendees(token: token, classId: id) { classAttendees[id] = a }
    }

    /// "Who's booked" row, as in the original app: me first, then friends, then other members with a
    /// public profile, then everyone else as "Hidden". Falls back to the friends feed for friends the
    /// attendee list doesn't name.
    func attendees(forClass id: Int) -> [ClassAttendeeEntry] {
        var me: [ClassAttendeeEntry] = [], friendsIn: [ClassAttendeeEntry] = [], others: [ClassAttendeeEntry] = [], hidden: [ClassAttendeeEntry] = []
        var seen = Set<Int>()
        let mine = booking(forClass: id)
        if mine != nil, let u = user {
            me.append(ClassAttendeeEntry(key: "u\(u.id)", name: u.firstName, photo: u.photo, initials: u.initials, hidden: false))
            seen.insert(u.id)
        }
        func friendUser(_ uid: Int?) -> BruceAPI.UserLite? { uid.flatMap { uid in friends.first { $0.friendUser?.id == uid }?.friendUser } }
        for a in classAttendees[id] ?? [] {
            if !me.isEmpty, a.id == mine?.id { continue }
            let uid = a.user?.id ?? a.userId
            if let uid, seen.contains(uid) { continue }
            if let uid { seen.insert(uid) }
            if let f = friendUser(uid) {
                friendsIn.append(ClassAttendeeEntry(key: "u\(f.id)", name: f.firstName, photo: f.photo ?? a.user?.photo, initials: f.initials, hidden: false))
            } else if let u = a.user, u.social != false, let name = u.displayName ?? u.firstName, !name.isEmpty {
                let initials = [u.firstName, u.lastName].compactMap { $0?.first.map(String.init) }.joined()
                others.append(ClassAttendeeEntry(key: "u\(u.id)", name: name, photo: u.photo, initials: initials, hidden: false))
            } else {
                hidden.append(ClassAttendeeEntry(key: "b\(a.id)", name: nil, photo: nil, initials: "", hidden: true))
            }
        }
        for b in friendsBookings where b.classId == id || b.class?.id == id {
            guard let f = friendUser(b.userId), !seen.contains(f.id) else { continue }
            seen.insert(f.id)
            friendsIn.append(ClassAttendeeEntry(key: "u\(f.id)", name: f.firstName, photo: f.photo, initials: f.initials, hidden: false))
            // That friend's booking is already in the list as an anonymous one; don't count them twice.
            if !hidden.isEmpty { hidden.removeLast() }
        }
        return me + friendsIn + others + hidden
    }

    func loadStudioDetail(_ id: Int) async {
        guard tokenUsable, studioDetails[id] == nil else { return }
        if let s = try? await BruceAPI.fetchStudio(token: token, id: id) { studioDetails[id] = s }
    }

    // MARK: State-changing (sent for real; every one is user-initiated)

    func book(classId: Int, title: String) async {
        if AppModel.demo {
            let c = classDetails[classId]
            bookings.append(BruceAPI.Booking(id: 90_000 + classId, classId: classId, studioId: c?.studioId, checkedInAt: nil, class: c))
            flash("Demo: booked \(title) (offline, nothing sent)"); return
        }
        guard let req = try? BruceAPI.bookRequest(token: token, classId: classId) else { return }
        if await send(req, label: "Booking") { flash("Booked \(title)") }
        await loadMine()
        await loadClassAttendees(classId)
        await refreshLimits(forClass: classId)
    }

    /// Invites friends (by user id) to a class; they get it in their Bruce app.
    func inviteToClass(_ classId: Int, userIds: [Int]) async -> Bool {
        guard !userIds.isEmpty else { return false }
        let who = userIds.count == 1 ? "1 friend" : "\(userIds.count) friends"
        if AppModel.demo { flash("Demo: invited \(who) (offline, nothing sent)"); return true }
        guard let req = try? BruceAPI.classInviteRequest(token: token, classId: classId, userIds: userIds) else { return false }
        let ok = await send(req, label: "Invite")
        if ok { flash("Invited \(who)") }
        return ok
    }

    func cancel(_ b: BruceAPI.Booking) async {
        if AppModel.demo {
            bookings.removeAll { $0.id == b.id }
            flash("Demo: booking cancelled (offline, nothing sent)"); return
        }
        guard let req = try? BruceAPI.cancelRequest(token: token, bookingId: b.id) else { return }
        if await send(req, label: "Cancel booking") { flash("Booking cancelled") }
        await loadMine()
        if let cid = b.classId ?? b.class?.id {
            await loadClassAttendees(cid)
            await refreshLimits(forClass: cid)
        }
    }

    /// After book/cancel the original re-reads the class and `user_visit_limit` [c2:93-129].
    private func refreshLimits(forClass classId: Int) async {
        guard let sid = findClass(classId)?.studioId else { return }
        await loadStudioLimits(sid, force: true)
        if classDetails[classId] != nil { await loadClassDetail(classId) }
    }

    /// Re-read bookings and waitlist when the app comes back to the foreground: a waitlist spot can turn into a
    /// booking while the app is in the background.
    func refreshOnForeground() async {
        guard tokenUsable, !loading, Date().timeIntervalSince(mineLoadedAt ?? .distantPast) > 30 else { return }
        await loadMine()
        await refreshAutoBook()
    }
    @ObservationIgnored private var mineLoadedAt: Date?

    /// `POST /v52/studio/check_in`, exactly one request per confirmed tap (a second tap while one is in flight is
    /// ignored). An error status does not prove the check-in failed: a remote check-in without door `meta` at an
    /// STC/BRP gym answered HTTP 400 although the booking was checked in (the official app showed the ticket,
    /// Oct 12). So on any non-2xx answer the bookings are re-read, and a booking at that studio with
    /// `checked_in_at` today counts as success: the ticket opens and no error is shown.
    func checkIn(_ t: CheckInTarget) async {
        if AppModel.demo { flash("Demo: check-in to \(t.name) not sent (offline)"); return }
        guard !checkInInFlight else { return }
        guard tokenUsable else { flash("Please log in again."); return }
        guard let req = try? BruceAPI.checkInRequest(token: token, target: t) else { return }
        checkInInFlight = true
        loading = true
        defer { checkInInFlight = false; loading = false }
        let code: Int, body: String
        do { (code, body) = try await BruceAPI.perform(req) }
        catch { flash("Check-in failed: \(error.localizedDescription)"); return }
        if code == 401 { expireSession(); return }
        let ok = (200..<300).contains(code)
        if ok, let d = t.door { LearnedDoors.remember(d, studioId: t.studioId) }   // optional: reuse a scanned door
        await loadMine()
        await loadVisits()
        if let b = todaysCheckIn(studioId: t.studioId) {
            if !ok { status = "Check-in: HTTP \(code), but the booking is checked in\n\(body.prefix(500))" }
            flash("Checked in at \(t.name)")
            present(.ticket(b.id))
            return
        }
        if ok { flash("Checked in at \(t.name)"); return }
        status = "Check-in: HTTP \(code)\n\(body.prefix(500))"
        if let msg = BruceAPI.errorMessage(body) { flash("Check-in failed: \(msg)") } else { flash("Check-in failed (HTTP \(code))") }
    }
    @ObservationIgnored private var checkInInFlight = false

    /// Candidates for the Home check-in control: today's booked classes plus studios with a
    /// known door QR (current/recent bookings and previously visited drop-in gyms).
    var checkInTargets: [CheckInTarget] {
        var out: [CheckInTarget] = []
        var seen = Set<Int>()
        let cal = BruceDate.calendar
        for b in bookings.sorted(by: { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }) {
            guard let c = b.class, let d = c.start, cal.isDateInToday(d) || abs(d.timeIntervalSinceNow) < 3 * 3600 else { continue }
            let sid = c.studioId
            guard !b.isCheckedIn else { continue }
            if let t = CheckInTarget.make(studio: studio(sid), studioId: sid, name: studioName(sid),
                                          subtitle: "\(c.title) · \(BruceDate.time(d))") { out.append(t); seen.insert(sid) }
        }
        for b in pastBookings + bookings {
            guard let sid = b.studioId ?? b.class?.studioId, !seen.contains(sid) else { continue }
            if let t = CheckInTarget.make(studio: studio(sid), studioId: sid, name: studioName(sid), subtitle: "Visited before"),
               t.door != nil { out.append(t); seen.insert(sid) }
        }
        for (sid, door) in KnownDoors.byStudio.sorted(by: { $0.key < $1.key }) where !seen.contains(sid) {
            out.append(CheckInTarget(studioId: sid, name: studio(sid)?.name ?? door.name, subtitle: "Drop-in gym",
                                     qrCodeId: "stc:\(door.major)", door: door))
        }
        return out
    }

    /// Scanned QR (door "stc://open-door?major=..&minor=.." or a studio QR id) -> target.
    func target(forScanned code: String) -> CheckInTarget? {
        var cfg = CheckInConfig()
        if cfg.apply(qr: code) {
            let sid = KnownDoors.byStudio.first { $0.value.major == cfg.major }?.key
                ?? studios.first { $0.stcMajor == cfg.major }?.id ?? 0
            return CheckInTarget(studioId: sid, name: sid > 0 ? studioName(sid) : "door \(cfg.major)", subtitle: "Door \(cfg.doorId)",
                                 qrCodeId: "stc:\(cfg.major)", door: KnownDoors.Door(name: "", major: cfg.major, doorId: cfg.doorId))
        }
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = studios.first(where: { $0.qrCodeId == c }) {
            return CheckInTarget.make(studio: s, studioId: s.id, name: s.name, subtitle: "Studio QR")
        }
        return nil
    }

    @discardableResult
    private func send(_ req: URLRequest, label: String) async -> Bool {
        guard tokenUsable else { flash("Please log in again."); return false }
        loading = true
        defer { loading = false }
        do {
            let (code, body) = try await BruceAPI.perform(req)
            if code == 401 { expireSession(); return false }
            guard (200..<300).contains(code) else {
                status = "\(label): HTTP \(code)\n\(body.prefix(500))"
                // Show the server's reason (`errors[0].message`) when there is one, not just the status code.
                if let msg = BruceAPI.errorMessage(body) { flash("\(label) failed: \(msg)") }
                else { flash("\(label) failed (HTTP \(code))") }
                return false
            }
            return true
        } catch {
            flash("\(label) failed: \(error.localizedDescription)"); return false
        }
    }
}

struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let run: () async -> Void
}

/// A place to check in: studio QR id ("stc:<major>" or the studio's own qr_code_id) plus a door if known.
struct CheckInTarget: Identifiable, Hashable {
    let studioId: Int
    let name: String
    let subtitle: String
    let qrCodeId: String
    let door: KnownDoors.Door?
    var id: String { "\(studioId)-\(qrCodeId)" }

    static func make(studio: BruceAPI.Studio?, studioId: Int, name: String, subtitle: String) -> CheckInTarget? {
        if let d = KnownDoors.door(for: studioId) {
            return CheckInTarget(studioId: studioId, name: name, subtitle: subtitle, qrCodeId: "stc:\(d.major)", door: d)
        }
        guard let q = studio?.qrCodeId, !q.isEmpty else { return nil }
        return CheckInTarget(studioId: studioId, name: name, subtitle: subtitle, qrCodeId: q, door: nil)
    }
}

extension BruceAPI.VisitLimit {
    /// `total` > 0 caps the visits, 0 means unlimited, -1 means not included in the user's tier
    /// (e.g. `WELLNESS_MONTHLY` and Wellness studios on BASE) [c4].
    var state: AppModel.LimitState {
        guard let t = total else { return .unknown }
        return t > 0 ? .limited(t) : t == 0 ? .unlimited : .notIncluded
    }
}
