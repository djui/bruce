import Foundation

// Additional read-only models and GET endpoints for the full app UI.
// Shapes follow the Charles captures in ../../../captures/*/.

enum BruceDate {
    static let tz = TimeZone(identifier: "Europe/Stockholm")!

    // Formatters are expensive to create; they are cached (Date(Formatter) use is thread-safe on Apple OSes).
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
    nonisolated(unsafe) private static var parsed: [String: Date] = [:]
    private static let parseLock = NSLock()
    /// Parses API timestamps; memoised because list rows parse the same start times on every render.
    static func parse(_ s: String) -> Date? {
        parseLock.lock(); defer { parseLock.unlock() }
        if let d = parsed[s] { return d }
        guard let d = iso.date(from: s) ?? Session.parseDate(s) else { return nil }
        if parsed.count > 20_000 { parsed.removeAll(keepingCapacity: true) }
        parsed[s] = d
        return d
    }

    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    private static let formatLock = NSLock()
    static func format(_ d: Date?, _ pattern: String) -> String {
        guard let d else { return "" }
        formatLock.lock(); defer { formatLock.unlock() }
        let f: DateFormatter
        if let cached = formatters[pattern] { f = cached } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = tz
            f.dateFormat = pattern
            formatters[pattern] = f
        }
        return f.string(from: d)
    }

    static let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = tz; c.firstWeekday = 2; return c }()

    /// "today, 11 October" / "Monday, 12 October".
    static func dayHeader(_ d: Date?, lowercaseToday: Bool = true) -> String {
        guard let d else { return "" }
        if calendar.isDateInToday(d) { return "today, " + format(d, "d MMMM") }
        return format(d, "EEEE, d MMMM")
    }

    static func time(_ d: Date?) -> String { format(d, "HH:mm") }

    /// "20261101" -> that day at 00:00 Stockholm time.
    static func parseDay(_ s: String) -> Date? {
        guard s.count == 8, let y = Int(s.prefix(4)), let mo = Int(s.dropFirst(4).prefix(2)), let d = Int(s.suffix(2)) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: mo, day: d))
    }
}

extension BruceAPI {
    static func imageURL(_ fileId: String?, w: Int = 402, h: Int = 252) -> URL? {
        // Demo mode is fully offline (no remote images) unless BRUCE_DEMO_ASSETS=1.
        guard AppModel.remoteAssets, let id = fileId, !id.isEmpty else { return nil }
        return URL(string: "https://res.cloudinary.com/dbo5hzaqa/image/upload/c_fill,dpr_3,h_\(h),q_60,w_\(w)/\(id).jpg")
    }

    // MARK: Nested shapes

    struct Rating: Codable, Hashable {
        let total: Int?
        let average: Int?   // x100, e.g. 482 = 4.82
        var distribution: [String: Int]? = nil
        var display: String? {
            guard let a = average, a > 0 else { return nil }
            return String(format: "%.1f", Double(a) / 100).replacingOccurrences(of: ".", with: ",")
        }
    }

    struct Category: Codable, Hashable, Identifiable {
        let id: Int
        let code: String?
        let title: String?
        let photo: String?
    }

    struct StudioCategory: Codable, Hashable {
        let categoryId: Int?
        let main: Bool?
        let order: Int?
        let category: Category?
        enum CodingKeys: String, CodingKey { case categoryId = "category_id", main, order, category }
    }

    struct Address: Codable, Hashable {
        let address: String?
        let city: String?
        let zipCode: String?
        let vicinity: String?
        let latitude: Double?
        let longitude: Double?
        enum CodingKeys: String, CodingKey { case address, city, vicinity, latitude, longitude, zipCode = "zip_code" }
    }

    struct StudioAddress: Codable, Hashable {
        let main: Bool?
        let address: Address?
    }

    struct Facility: Codable, Hashable { let code: String?; let title: String? }
    struct StudioFacility: Codable, Hashable { let facility: Facility? }

    struct ClassCategory: Codable, Hashable {
        let categoryId: Int?
        let main: Bool?
        enum CodingKeys: String, CodingKey { case categoryId = "category_id", main }
    }

    struct StudioLite: Codable, Hashable {
        let id: Int
        let name: String?
        let photo: String?
        let vicinity: String?
        let cityId: Int?
        /// Only on the class detail (`include_studio_alerts=true`) [c7:157].
        var alerts: [StudioAlert]? = nil
        enum CodingKeys: String, CodingKey { case id, name, photo, vicinity, alerts, cityId = "city_id" }
    }

    // MARK: Home

    struct HomeItem: Decodable, Hashable {
        let type: String?
        let categoryId: Int?
        let title: String?
        let code: String?
        let photo: String?
        let className: String?
        let classId: Int?
        let studioName: String?
        let studioId: Int?
        let vicinities: [String]?
        let categories: [String]?
        let distance: Int?
        let startTime: String?
        enum CodingKeys: String, CodingKey {
            case type, title, code, photo, vicinities, categories, distance
            case categoryId = "category_id", className = "class_name", classId = "class_id"
            case studioName = "studio_name", studioId = "studio_id", startTime = "start_time"
        }
    }

    struct HomeSection: Decodable, Hashable {
        let title: String?
        let type: String
        let items: [HomeItem]
    }

    static func fetchHomeScreen(token: String, lat: Double, lon: Double) async throws -> [HomeSection] {
        struct R: Decodable { let sections: [HomeSection] }
        let q = [("coordinates", "\(lat),\(lon)"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/home_screen", query: q, token: token))).sections
    }

    static func fetchCategories(token: String?) async throws -> [Category] {
        struct R: Decodable { let categories: [Category] }
        let q = [("filter[main][eq]", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/category", query: q, token: token))).categories
    }

    // MARK: Class / studio detail

    static func fetchClass(token: String, id: Int) async throws -> BruceClass {
        struct R: Decodable { let `class`: BruceClass }
        // Same includes as the original's class detail call [c2:50, 58, 93, 100]: dynamic prices and the
        // user's attendance info carry the drop-in price and `visit_limit_reached` [c4:96].
        let q = [("include_studio", "true"), ("include_info", "true"), ("include_class_categories", "true"), ("include_absolute_times", "true"),
                 ("include_booking_credit_costs", "true"), ("include_studio_alerts", "true"), ("exclude_studio_expired_alerts", "true"),
                 ("include_dynamic_prices", "true"), ("include_studio_user_attendance_info", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/class/\(id)", query: q, token: token))).class
    }

    static func fetchStudio(token: String, id: Int) async throws -> Studio {
        struct R: Decodable { let studio: Studio }
        let q = [("include_addresses", "true"), ("include_addresses_address", "true"), ("include_studio_photos", "true"), ("include_studio_photos_photo", "true"),
                 ("include_facilities", "true"), ("include_categories", "true"),
                 ("include_alerts", "true"), ("exclude_expired_alerts", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/studio/\(id)", query: q, token: token))).studio
    }

    // MARK: Notifications, friends

    struct NotificationMeta: Decodable, Hashable { let photo: String?; let userPhoto: String?
        enum CodingKeys: String, CodingKey { case photo, userPhoto = "user_photo" } }
    struct BruceNotification: Decodable, Identifiable, Hashable {
        let id: Int
        let createdAt: String?
        let type: String?
        let title: String?
        let message: String?
        let read: Bool?
        let meta: NotificationMeta?
        enum CodingKeys: String, CodingKey { case id, type, title, message, read, meta, createdAt = "created_at" }
        var date: Date? { createdAt.flatMap(BruceDate.parse) }
    }

    static func fetchNotifications(token: String, userId: Int) async throws -> [BruceNotification] {
        struct R: Decodable { let notifications: [BruceNotification] }
        let q = [("user_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/notification", query: q, token: token))).notifications
    }

    struct UserLite: Decodable, Hashable {
        let id: Int
        let firstName: String?
        let lastName: String?
        let photo: String?
        var social: Bool? = nil
        var email: String? = nil
        var emailConfirmed: Bool? = nil
        var nationalIdentity: String? = nil
        var photoValid: Bool? = nil
        var secret: String? = nil
        enum CodingKeys: String, CodingKey {
            case id, photo, social, email, secret, firstName = "first_name", lastName = "last_name"
            case emailConfirmed = "email_confirmed", nationalIdentity = "national_identity", photoValid = "photo_valid"
        }
        var initials: String { [firstName, lastName].compactMap { $0?.first.map(String.init) }.joined() }
        var fullName: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ") }
    }

    struct Friend: Decodable, Identifiable, Hashable {
        let id: Int
        let friendUser: UserLite?
        enum CodingKeys: String, CodingKey { case id, friendUser = "friend_user" }
    }

    static func fetchFriends(token: String, userId: Int) async throws -> [Friend] {
        struct R: Decodable { let friends: [Friend] }
        let q = [("user_id", String(userId)), ("locale", "en"), ("include_friend_user", "true")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/friend", query: q, token: token))).friends
    }

    // MARK: Account (read-only)

    static func fetchUser(token: String, userId: Int) async throws -> UserLite {
        struct R: Decodable { let user: UserLite }
        let data = try await send(makeRequest("GET", "v52/user/\(userId)", query: [("locale", "en")], token: token))
        if let r = try? decode(R.self, data) { return r.user }
        return try decode(UserLite.self, data)
    }

    struct MembershipInfo: Decodable {
        let membership: Bool?
        let paused: Bool?
        let membershipTier: String?
        let admissionTier: String?
        let currentMembershipPrice: Int?
        let currency: String?
        let availableCredits: Int?
        let nextPayment: String?
        let admissionAccessUntil: String?
        let remainingPauseDays: Int?
        var remainingPausePeriods: Int? = nil
        /// Yearly pause allowance (`pause_days_total`, `total_pause_periods`).
        var pauseDaysTotal: Int? = nil
        var totalPausePeriods: Int? = nil
        /// Cancellation terms (`has_notice_period`, `cancel_without_notice_until`).
        var hasNoticePeriod: Bool? = nil
        var cancelWithoutNoticeUntil: String? = nil
        /// Commitment (`commitment_months`, `committed_until`, `prolong_commitment`).
        var commitmentMonths: Int? = nil
        var committedUntil: String? = nil
        var prolongCommitment: Bool? = nil
        enum CodingKeys: String, CodingKey {
            case membership, paused, currency
            case pauseDaysTotal = "pause_days_total", totalPausePeriods = "total_pause_periods"
            case hasNoticePeriod = "has_notice_period", cancelWithoutNoticeUntil = "cancel_without_notice_until"
            case commitmentMonths = "commitment_months", committedUntil = "committed_until", prolongCommitment = "prolong_commitment"
            case membershipTier = "membership_tier", admissionTier = "admission_tier"
            case currentMembershipPrice = "current_membership_price"
            case availableCredits = "available_credits", nextPayment = "next_payment"
            case admissionAccessUntil = "admission_access_until", remainingPauseDays = "remaining_pause_days"
            case remainingPausePeriods = "remaining_pause_periods"
        }
    }

    static func fetchMembership(token: String, userId: Int) async throws -> MembershipInfo {
        struct R: Decodable { let userMembershipInfo: MembershipInfo
            enum CodingKeys: String, CodingKey { case userMembershipInfo = "user_membership_info" } }
        let q = [("user_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/membership/user_info", query: q, token: token))).userMembershipInfo
    }

    struct VisitLimitItem: Codable, Hashable { let label: String?; let limit: Int? }
    /// One entry of `GET /v52/studio/user_visit_limit` `limits[]`: `{total,used,remaining,within_limit,resets_at,type,items}`.
    /// For `type == "STUDIO"`, `items` lists the studio's limit per tier (`[{label:"EPIC",limit:8,period:"MONTHLY"},...]`,
    /// in API order EPIC, BLACK, BASE; total 0 = unlimited) [c7:132, 76, 91]. Unused fields (id, month, ...) are ignored.
    struct VisitLimit: Decodable, Hashable {
        let total: Int?
        let used: Int?
        let remaining: Int?
        let type: String?
        let items: [VisitLimitItem]?
        var withinLimit: Bool? = nil
        /// `resets_at`, UTC ISO 8601, e.g. "2026-10-31T23:00:00Z" = 1 November 00:00 in Stockholm [c7:132].
        var resetsAt: String? = nil
        enum CodingKeys: String, CodingKey {
            case total, used, remaining, type, items, withinLimit = "within_limit", resetsAt = "resets_at"
        }
        var resetDate: Date? {
            guard let r = resetsAt else { return nil }
            if let d = BruceDate.parse(r) { return d }
            if r.count == 8, let d = BruceDate.parseDay(r) { return d }   // YYYYMMDD
            if let t = Double(r), t > 1_000_000_000 { return Date(timeIntervalSince1970: t) }
            return nil
        }
    }
}

extension BruceAPI.VisitLimit {
    /// Lenient: `resets_at` may be a string or a number; an odd field never drops the whole limits list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try? c.decodeIfPresent(Int.self, forKey: .total)
        used = try? c.decodeIfPresent(Int.self, forKey: .used)
        remaining = try? c.decodeIfPresent(Int.self, forKey: .remaining)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        items = try? c.decodeIfPresent([BruceAPI.VisitLimitItem].self, forKey: .items)
        withinLimit = try? c.decodeIfPresent(Bool.self, forKey: .withinLimit)
        if let s = try? c.decodeIfPresent(String.self, forKey: .resetsAt) { resetsAt = s }
        else if let n = try? c.decodeIfPresent(Double.self, forKey: .resetsAt) { resetsAt = String(format: "%.0f", n) }
    }
}

extension BruceAPI {
    static func fetchVisitLimits(token: String, userId: Int) async throws -> [VisitLimit] {
        struct R: Decodable { let limits: [VisitLimit] }
        let q = [("locale", "en"), ("user_id", String(userId))]
        return try decode(R.self, try await send(makeRequest("GET", "v52/studio/user_visit_limit", query: q, token: token))).limits
    }

    struct BlockInfo: Decodable {
        let strikeCount: Int?
        let blocked: Bool?
        let freeUnlocksRemaining: Int?
        var totalFreeUnlocks: Int? = nil
        var blockEndDate: String? = nil
        enum CodingKeys: String, CodingKey {
            case blocked, strikeCount = "strike_count", freeUnlocksRemaining = "free_unlocks_remaining"
            case totalFreeUnlocks = "total_free_unlocks", blockEndDate = "block_end_date"
        }
    }

    static func fetchBlockInfo(token: String, userId: Int) async throws -> BlockInfo {
        struct R: Decodable { let userBlockInfo: BlockInfo
            enum CodingKeys: String, CodingKey { case userBlockInfo = "user_block_info" } }
        let q = [("locale", "en"), ("user_id", String(userId))]
        return try decode(R.self, try await send(makeRequest("GET", "v52/user_block/info", query: q, token: token))).userBlockInfo
    }

    struct PaymentMethod: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let type: String?
        let expiration: Int?
        let isDefault: Bool?
        enum CodingKeys: String, CodingKey { case id, name, type, expiration, isDefault = "default" }
        /// Expiration arrives as MMYY or YYYYMM integers; render MM/YY.
        var expiryDisplay: String? {
            guard let e = expiration else { return nil }
            let s = String(e)
            if s.count == 6 { return "\(s.suffix(2))/\(s.dropFirst(2).prefix(2))" }
            if s.count == 4 { return "\(s.prefix(2))/\(s.suffix(2))" }
            if s.count == 3 { return "0\(s.prefix(1))/\(s.suffix(2))" }
            return s
        }
    }

    static func fetchPaymentMethods(token: String, userId: Int) async throws -> [PaymentMethod] {
        struct R: Decodable { let paymentMethods: [PaymentMethod]
            enum CodingKeys: String, CodingKey { case paymentMethods = "payment_methods" } }
        let q = [("locale", "en"), ("user_id", String(userId))]
        return try decode(R.self, try await send(makeRequest("GET", "v52/payment/method", query: q, token: token))).paymentMethods
    }

    // MARK: My classes

    /// Bookmark or standby (waitlist entry) with its class. Standby `booking_id` is always null, even after the
    /// user got a spot: a promoted entry simply disappears from `GET /v52/standby` [c7:80, 64].
    struct ClassHolder: Decodable, Identifiable, Hashable {
        let id: Int
        let `class`: BruceClass?
    }

    static func fetchBookmarks(token: String, userId: Int) async throws -> [ClassHolder] {
        struct R: Decodable { let bookmarks: [ClassHolder] }
        let q = [("user_id", String(userId)), ("include_class", "true"), ("include_class_studio", "true"),
                 ("deleted", "false"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/bookmark", query: q, token: token))).bookmarks
    }

    static func fetchStandbys(token: String, userId: Int) async throws -> [ClassHolder] {
        struct R: Decodable { let standbys: [ClassHolder] }
        let after = ISO8601DateFormatter().string(from: Date())
        let q = [("user_id", String(userId)), ("include_class", "true"), ("deleted", "false"),
                 ("class_start_time_after", after), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/standby", query: q, token: token))).standbys
    }

    /// Past checked-in bookings (for "Total monthly visits").
    static func fetchPastBookings(token: String, userId: Int) async throws -> [Booking] {
        struct R: Decodable { let bookings: [Booking] }
        let q: [(String, String)] = [("user_id", String(userId)), ("limit", "30"), ("deleted", "false"),
                                     ("include_class", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token))).bookings
    }

    // MARK: Cities  [GET /v52/location/city?include_country=true]

    struct Country: Decodable, Hashable { let id: Int; let name: String?; let code: String? }
    struct CityCoordinates: Decodable, Hashable {
        let latitude: Double
        let longitude: Double
        let swLatitude: Double?
        let swLongitude: Double?
        let neLatitude: Double?
        let neLongitude: Double?
        enum CodingKeys: String, CodingKey {
            case latitude, longitude
            case swLatitude = "sw_latitude", swLongitude = "sw_longitude"
            case neLatitude = "ne_latitude", neLongitude = "ne_longitude"
        }
    }
    struct City: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let code: String?
        let hidden: Bool?
        let countryId: Int?
        let coordinates: CityCoordinates?
        let country: Country?
        let unlockPrice: Int?
        enum CodingKeys: String, CodingKey {
            case id, name, code, hidden, coordinates, country, countryId = "country_id"
            case unlockPrice = "user_strike_block_un_lock_price"
        }
    }

    static func fetchCities(token: String?) async throws -> [City] {
        struct R: Decodable { let cities: [City] }
        let q = [("include_country", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/location/city", query: q, token: token))).cities
            .filter { $0.hidden != true }
    }

    // MARK: Invite codes  [GET /v52/booking/voucher?owner_id=<uid>]

    struct Voucher: Decodable, Identifiable, Hashable {
        let id: Int
        let code: String
        let userId: Int?
        let consumedAt: String?
        enum CodingKeys: String, CodingKey { case id, code, userId = "user_id", consumedAt = "consumed_at" }
        var accepted: Bool { userId != nil }
    }

    static func fetchVouchers(token: String, userId: Int) async throws -> [Voucher] {
        struct R: Decodable { let bookingVouchers: [Voucher]
            enum CodingKeys: String, CodingKey { case bookingVouchers = "booking_vouchers" } }
        let q = [("owner_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/booking/voucher", query: q, token: token))).bookingVouchers
    }

    struct VisitLimitDef: Codable, Hashable { let items: [VisitLimitItem]? }

    /// `POST /v52/studio/check_in`. With a door: `{"qr_code_id":"stc:<major>","meta":{major,minor,door_id}}`
    /// (captured). Without a door the studio's own `qr_code_id` is sent alone (not captured; best effort).
    static func checkInRequest(token: String, target: CheckInTarget) throws -> URLRequest {
        var body: [String: Any] = ["locale": "en", "qr_code_id": target.qrCodeId, "include_class": true]
        if let d = target.door { body["meta"] = ["major": d.major, "minor": d.doorId, "door_id": d.doorId] }
        return try makeRequest("POST", "v52/studio/check_in", token: token, body: body)
    }

    // MARK: Opening hours  [GET /v52/studio/<id>/opening_hour/schedule?start=..&end=..]

    struct ScheduleEntry: Decodable, Hashable {
        let start: String
        let end: String
        let isAllDay: Bool?
        var attendance: AttendanceInfo? = nil
        enum CodingKeys: String, CodingKey { case start, end, isAllDay = "is_all_day", attendance = "studio_user_attendance_info" }
        var startDate: Date? { BruceDate.parse(start) }
        var endDate: Date? { BruceDate.parse(end) }
    }

    static func fetchOpeningSchedule(token: String, studioId: Int, from: Date, to: Date) async throws -> [ScheduleEntry] {
        struct R: Decodable { let schedule: [ScheduleEntry] }
        let f = ISO8601DateFormatter()
        let q = [("start", f.string(from: from)), ("end", f.string(from: to)), ("include_studio_user_attendance_info", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/studio/\(studioId)/opening_hour/schedule", query: q, token: token))).schedule
    }
}

enum ShareURL {
    /// "STC Södermalm Timmermansgatan" -> "stc-sodermalm-timmermansgatan".
    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) && ch.isASCII { out.unicodeScalars.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    /// Confirmed format: https://www.brucestudios.com/studios/<id>/<slug> (two examples from the app's share sheet).
    static func forStudio(_ id: Int, name: String) -> URL {
        URL(string: "https://www.brucestudios.com/studios/\(id)/\(slug(name))")!
    }
    /// Confirmed format: https://app.brucestudios.com/classes/<id>/<slug>; diacritics folded (mittsträning -> mittstraning).
    static func forClass(_ id: Int, title: String) -> URL {
        URL(string: "https://app.brucestudios.com/classes/\(id)/\(slug(title))")!
    }
}
