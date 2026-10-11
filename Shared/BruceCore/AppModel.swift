import SwiftUI
import CoreLocation
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
}

enum SheetRoute: Hashable {
    case notifications, menu, account, membership, visits, credits, strikes, payment
    case settings, login, checkIn, info(String)
    case search, selectCity, newArea, createAccount, resetPassword
    case ticket(Int), checkout(Int), editProfile, pause, plans, statistics, receipts
    case bookingRules(Int), invite, howItWorks, voucher, support, help, push, pushInfo, quickCheckIn
    case similarClasses(Int), area(UUID)
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
    var standbys: [BruceAPI.ClassHolder] = []
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
    var notificationSetting: BruceAPI.NotificationSetting?
    var social: Bool?
    var payments: [BruceAPI.Payment] = []
    var aggregate: [BruceAPI.DayCount] = []
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
    /// Strike-unblock price from the city (nil until loaded).
    var unblockPriceKr: Int? { (city?.unlockPrice).map { $0 / 100 } }

    var token: String { session?.accessToken ?? "" }
    var isLoggedIn: Bool { (AppModel.demo && !demoLoggedOut) || !token.isEmpty }
    var showWelcome: Bool { !isLoggedIn && !sneakPeek }
    var userId: Int? { session?.userId }
    var unreadNotifications: Bool { notifications.contains { isNew($0) } }
    func isNew(_ n: BruceAPI.BruceNotification) -> Bool { (n.date ?? .distantPast) > notificationsSeenAt }
    func markNotificationsSeen() {
        notificationsSeenAt = Date()
        if !AppModel.demo { UserDefaults.standard.set(notificationsSeenAt.timeIntervalSince1970, forKey: "notificationsSeenAt") }
    }
    var tier: String { (membership?.membershipTier ?? membership?.admissionTier ?? "BASE").uppercased() }

    func booking(forClass id: Int) -> BruceAPI.Booking? { bookings.first { $0.classId == id || $0.class?.id == id } }

    enum LimitState { case limited(Int), unlimited, notIncluded, unknown }
    var studioLimits: [Int: [BruceAPI.VisitLimit]] = [:]
    func loadStudioLimits(_ studioId: Int) async {
        guard tokenUsable, let uid = userId, studioLimits[studioId] == nil else { return }
        if let l = try? await BruceAPI.fetchStudioLimits(token: token, userId: uid, studioId: studioId) { studioLimits[studioId] = l }
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
        if let s = studioLimits[studioId]?.first(where: { $0.type == "STUDIO" }), let t = s.total {
            return t > 0 ? .limited(t) : t == 0 ? .unlimited : .notIncluded
        }
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
    }
    func clearFilters() {
        accessTiers = []; exploreCategories = []
        favoritesOnly = false; currentlyOpen = false; soloOnly = false; hideFull = false; customArea = false
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
            guard !AppModel.demo else { flash("Bookmark removed"); return }
            Task {
                do { try await BruceAPI.removeBookmark(token: token, bookmarkId: b.id); flash("Bookmark removed") }
                catch { bookmarks.append(b); flash("Could not remove bookmark") }
            }
        } else {
            let c = findClass(classId)
            guard !AppModel.demo else { bookmarks.append(BruceAPI.ClassHolder(id: -classId, class: c)); flash("Bookmark added"); return }
            Task {
                do {
                    let ref = try await BruceAPI.addBookmark(token: token, classId: classId)
                    bookmarks.append(BruceAPI.ClassHolder(id: ref.id, class: c)); flash("Bookmark added")
                } catch { flash("Could not add bookmark") }
            }
        }
    }
    var bookmarkedClasses: [BruceAPI.BruceClass] { bookmarks.compactMap(\.class).sorted { $0.startTime < $1.startTime } }
    func findClass(_ id: Int) -> BruceAPI.BruceClass? {
        classDetails[id] ?? classesByDay.values.joined().first { $0.id == id }
            ?? bookings.first { $0.class?.id == id }?.class ?? bookmarks.first { $0.class?.id == id }?.class
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

    func flash(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if toast == s { toast = nil } }
    }

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
        bookings = []; standbys = []; bookmarks = []; notifications = []; friends = []
        user = nil; membership = nil; visitLimits = []; blockInfo = nil; paymentMethods = []
        dismissSheets()
    }

    func handleLoadError(_ error: Error, _ label: String) {
        if case BruceAPI.APIError.http(401, _) = error { expireSession(); return }
        if (error as? URLError)?.code == .cancelled { return }
        status = "\(label): \(error.localizedDescription)"
        loadError = (error as? URLError) != nil ? "You're offline or the server can't be reached." : "Couldn't load \(label.lowercased())."
    }

    /// Access token expired or rejected: forget it and ask for a fresh login (no refresh endpoint is known).
    func expireSession() {
        guard session != nil else { return }
        TokenStore.clear()
        session = nil
        sneakPeek = false
        bookings = []; standbys = []; bookmarks = []; notifications = []; friends = []
        user = nil; membership = nil; visitLimits = []; blockInfo = nil; paymentMethods = []
        resetLoadedData()
        status = "Your session expired. Please log in again."
        sheets = [.login]
    }

    /// Drop every cached collection (used when leaving the runtime demo).
    func resetLoadedData() {
        studios = []; categories = []; home = []; classesByDay = [:]; classDetails = [:]; studioDetails = [:]
        schedules = [:]; studioClasses = [:]; studioLimits = [:]; reviews = [:]; pastBookings = []
        friendsBookings = []; invites = []; payments = []; aggregate = []; favoriteIds = [:]
        notificationSetting = nil; social = nil; stacks = [:]; tab = .home
    }

    private var tokenUsable: Bool { !AppModel.demo && !token.isEmpty && session?.isAccessExpired != true }

    // MARK: Loading (read-only GETs)

    func bootstrap() async {
        await loadAreas()   // local store: no network
        if AppModel.demo { loadDemo(); return }
        if session != nil, session?.isAccessExpired == true { expireSession(); return }
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
        do {
            bookings = try await BruceAPI.fetchBookings(token: token, userId: uid)
                .filter { ($0.class?.start ?? .distantPast) > Date().addingTimeInterval(-3600) && $0.checkedInAt == nil }
        } catch { handleLoadError(error, "Bookings") }
        standbys = (try? await BruceAPI.fetchStandbys(token: token, userId: uid)) ?? []
        bookmarks = (try? await BruceAPI.fetchBookmarks(token: token, userId: uid)) ?? []
    }

    func loadSocial() async {
        guard tokenUsable, let uid = userId else { return }
        notifications = (try? await BruceAPI.fetchNotifications(token: token, userId: uid)) ?? []
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
            if AppModel.demo { self.standbys.removeAll { $0.id == s.id }; return }
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
    }

    func cancel(_ b: BruceAPI.Booking) async {
        if AppModel.demo {
            bookings.removeAll { $0.id == b.id }
            flash("Demo: booking cancelled (offline, nothing sent)"); return
        }
        guard let req = try? BruceAPI.cancelRequest(token: token, bookingId: b.id) else { return }
        if await send(req, label: "Cancel booking") { flash("Booking cancelled") }
        await loadMine()
    }

    func checkIn(_ t: CheckInTarget) async {
        if AppModel.demo { flash("Demo: check-in to \(t.name) not sent (offline)"); return }
        guard let req = try? BruceAPI.checkInRequest(token: token, target: t) else { return }
        if await send(req, label: "Check-in") { flash("Checked in at \(t.name)") }
        await loadMine()
    }

    /// Candidates for the Home check-in control: today's booked classes plus studios with a
    /// known door QR (current/recent bookings and previously visited drop-in gyms).
    var checkInTargets: [CheckInTarget] {
        var out: [CheckInTarget] = []
        var seen = Set<Int>()
        let cal = BruceDate.calendar
        for b in bookings.sorted(by: { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }) {
            guard let c = b.class, let d = c.start, cal.isDateInToday(d) || abs(d.timeIntervalSinceNow) < 3 * 3600 else { continue }
            let sid = c.studioId
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
                flash("\(label) failed (HTTP \(code))"); return false
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
        if let d = KnownDoors.byStudio[studioId] {
            return CheckInTarget(studioId: studioId, name: name, subtitle: subtitle, qrCodeId: "stc:\(d.major)", door: d)
        }
        guard let q = studio?.qrCodeId, !q.isEmpty else { return nil }
        return CheckInTarget(studioId: studioId, name: name, subtitle: subtitle, qrCodeId: q, door: nil)
    }
}
