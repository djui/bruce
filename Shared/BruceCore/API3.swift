import Foundation

// Endpoints confirmed by capture 3 (`captures/3`, see API.md "Capture 3 additions").
extension BruceAPI {
    // MARK: Bookmarks [c3:73, 77]
    struct BookmarkRef: Decodable { let id: Int; let classId: Int?
        enum CodingKeys: String, CodingKey { case id, classId = "class_id" } }

    static func addBookmark(token: String, classId: Int) async throws -> BookmarkRef {
        struct R: Decodable { let bookmark: BookmarkRef }
        return try decode(R.self, try await send(makeRequest("POST", "v52/bookmark", token: token,
                                                             body: ["class_id": classId, "locale": "en"]))).bookmark
    }
    static func removeBookmark(token: String, bookmarkId: Int) async throws {
        try await send(makeRequest("DELETE", "v52/bookmark/\(bookmarkId)", token: token, body: ["locale": "en"]))
    }

    // MARK: Favourites [c3:88, 93, 96]
    struct FavoriteRef: Decodable { let id: Int; let studioId: Int?
        enum CodingKeys: String, CodingKey { case id, studioId = "studio_id" } }

    static func fetchFavorite(token: String, studioId: Int) async throws -> FavoriteRef? {
        struct R: Decodable { let favorites: [FavoriteRef] }
        let q = [("studio_id", String(studioId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/favorite", query: q, token: token))).favorites.first
    }
    static func addFavorite(token: String, studioId: Int) async throws -> FavoriteRef {
        struct R: Decodable { let favorite: FavoriteRef }
        return try decode(R.self, try await send(makeRequest("POST", "v52/favorite", token: token,
                                                             body: ["studio_id": studioId, "locale": "en"]))).favorite
    }
    static func removeFavorite(token: String, favoriteId: Int) async throws {
        try await send(makeRequest("DELETE", "v52/favorite/\(favoriteId)", token: token, body: ["locale": "en"]))
    }

    // MARK: Waitlist / standby [c3:65, 69]
    static func joinWaitlistRequest(token: String, classId: Int) throws -> URLRequest {
        try makeRequest("POST", "v52/standby", token: token, body: ["class_id": classId, "locale": "en"])
    }
    static func leaveWaitlistRequest(token: String, standbyId: Int) throws -> URLRequest {
        try makeRequest("DELETE", "v52/standby/\(standbyId)", token: token, body: ["locale": "en"])
    }

    // MARK: Reviews [c3:101, 121]
    struct ReviewUser: Decodable, Hashable { let firstName: String?; let photo: String?
        enum CodingKeys: String, CodingKey { case firstName = "first_name", photo } }
    struct ReviewClass: Decodable, Hashable { let title: String?; let opening: Bool? }
    struct ReviewBooking: Decodable, Hashable { let `class`: ReviewClass?; let user: ReviewUser? }
    struct Review: Decodable, Identifiable, Hashable {
        let id: Int
        let rating: Int?
        let comment: String?
        let createdAt: String?
        let booking: ReviewBooking?
        enum CodingKeys: String, CodingKey { case id, rating, comment, booking, createdAt = "created_at" }
        var activity: String {
            if booking?.class?.opening == true { return "Solo training" }
            return booking?.class?.title ?? "Class"
        }
    }
    static func fetchReviews(token: String, studioId: Int) async throws -> [Review] {
        struct R: Decodable { let reviews: [Review] }
        let q = [("studio_id", String(studioId)), ("comment", "true"), ("hidden", "false"), ("order_by", "-id"),
                 ("limit", "50"), ("include_booking", "true"), ("include_booking_class", "true"),
                 ("include_booking_user", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/review", query: q, token: token))).reviews
    }

    // MARK: Friends' bookings feed [c3:106]
    struct FriendBooking: Decodable, Identifiable, Hashable {
        let id: Int
        let userId: Int?
        let classId: Int?
        let `class`: BruceClass?
        enum CodingKeys: String, CodingKey { case id, `class`, userId = "user_id", classId = "class_id" }
    }
    static func fetchFriendsBookings(token: String, userId: Int) async throws -> [FriendBooking] {
        struct R: Decodable { let bookings: [FriendBooking] }
        let q = [("user_id", String(userId)), ("friends", "true"), ("class_day_after", BruceDate.format(Date(), "yyyyMMdd")),
                 ("deleted", "false"), ("limit", "30"), ("include_class", "true"), ("include_class_studio", "true"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token))).bookings
    }

    // MARK: Notification settings [c3:279, 319-332] and social flag [c3:280]
    struct PushType: Decodable, Hashable { let key: String; let name: String?; let description: String?; var enabled: Bool }
    struct NotificationSetting: Decodable {
        let id: Int
        var marketingEmail: Bool?
        var marketingPush: Bool?
        var marketingSms: Bool?
        var types: [PushType]?
        enum CodingKeys: String, CodingKey {
            case id, types, marketingEmail = "marketing_email", marketingPush = "marketing_push", marketingSms = "marketing_sms"
        }
    }
    static func fetchNotificationSetting(token: String, userId: Int) async throws -> NotificationSetting? {
        struct R: Decodable { let notificationSettings: [NotificationSetting]
            enum CodingKeys: String, CodingKey { case notificationSettings = "notification_settings" } }
        return try decode(R.self, try await send(makeRequest("GET", "v52/user/\(userId)/notification_setting",
                                                             query: [("locale", "en")], token: token))).notificationSettings.first
    }
    static func updateNotificationSetting(token: String, userId: Int, settingId: Int, body: [String: Any]) async throws {
        var b = body; b["locale"] = "en"
        try await send(makeRequest("PUT", "v52/user/\(userId)/notification_setting/\(settingId)", token: token, body: b))
    }
    static func setSocial(token: String, userId: Int, social: Bool) async throws {
        try await send(makeRequest("PUT", "v52/user/\(userId)", token: token, body: ["social": social, "locale": "en"]))
    }

    // MARK: Payments / receipts [c3:454, 536]
    struct Payment: Decodable, Identifiable, Hashable {
        let id: Int
        let createdAt: String?
        let amount: Int?
        let currency: String?
        let type: String?
        let status: String?
        enum CodingKeys: String, CodingKey { case id, amount, currency, type, status, createdAt = "created_at" }
        var title: String {
            switch type ?? "" {
            case "MEMBERSHIP_RENEWAL": return "Membership"
            case "MEMBERSHIP_UPGRADE": return "Membership upgrade"
            case "USER_BLOCK_UNLOCK": return "Strike unblock"
            case "BOOKING": return "Booking"
            case "FREE": return "Free"
            default: return (type ?? "Payment").capitalized
            }
        }
    }
    static func fetchPayments(token: String, userId: Int) async throws -> [Payment] {
        struct R: Decodable { let payments: [Payment] }
        let q = [("user_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/payment", query: q, token: token))).payments
    }
    static func fetchReceiptPDF(token: String, paymentId: Int) async throws -> Data {
        try await send(makeRequest("GET", "v52/payment/\(paymentId)/receipt.pdf", token: token))
    }

    // MARK: Statistics [c3:396]
    struct DayCount: Decodable, Hashable { let day: Int; let count: Int }
    static func fetchBookingAggregate(token: String, userId: Int) async throws -> [DayCount] {
        struct R: Decodable { let bookingAggregates: [DayCount]
            enum CodingKeys: String, CodingKey { case bookingAggregates = "booking_aggregates" } }
        let q = [("user_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/booking/aggregate", query: q, token: token))).bookingAggregates
    }

    // MARK: Plan prices [c2:426] GET /v52/membership/info?city_code=&tier_code=&commitment_months=12
    struct PlanPrice: Decodable { let originalPrice: Int?; let originalFlexPrice: Int?
        enum CodingKeys: String, CodingKey { case originalPrice = "original_price", originalFlexPrice = "original_flex_price" } }
    static func fetchPlanPrice(token: String, userId: Int, cityCode: String, tier: String) async throws -> PlanPrice {
        struct R: Decodable { let membershipInfo: PlanPrice
            enum CodingKeys: String, CodingKey { case membershipInfo = "membership_info" } }
        let q = [("city_code", cityCode), ("tier_code", tier), ("commitment_months", "12"), ("user_id", String(userId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/membership/info", query: q, token: token))).membershipInfo
    }

    // MARK: Per-studio limits [c3:56, c4:34, c4:85]
    /// GET /v52/studio/user_visit_limit?user_id=&studio_id=&month=YYYYMM -> limits of type STUDIO (pill:
    /// total>0 "used/total", 0 unlimited "∞", -1 not included "0 / 0"), MONTHLY, WELLNESS_MONTHLY, SIMULTANEOUS.
    static func fetchStudioLimits(token: String, userId: Int, studioId: Int) async throws -> [VisitLimit] {
        struct R: Decodable { let limits: [VisitLimit] }
        let q = [("user_id", String(userId)), ("studio_id", String(studioId)), ("month", BruceDate.format(Date(), "yyyyMM")), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/studio/user_visit_limit", query: q, token: token))).limits
    }

    // MARK: Opening schedule with attendance info (price for paid tickets) [c4:31]
    struct AttendanceInfo: Decodable, Hashable {
        let admissionAccess: Bool?
        let price: Int?            // öre, e.g. 28000 = SEK 280
        let currency: String?
        enum CodingKeys: String, CodingKey { case price, currency, admissionAccess = "admission_access" }
    }
}

extension BruceAPI {
    /// Studio alert: `alerts[]` (include_alerts=true / include_studio_alerts=true) [c2:212, c7:30]. Each alert has a
    /// `start_date` and an optional `end_date` (null = open-ended). The `exclude_*expired_alerts` flags are not
    /// reliable (c7:30 still returned an alert that ended in 2023), so `isActive` filters on the client.
    struct StudioAlert: Codable, Hashable {
        let message: String?
        let type: String?
        let order: Int?
        var id: Int? = nil
        var startDate: String? = nil
        var endDate: String? = nil
        enum CodingKeys: String, CodingKey { case message, type, order, id, startDate = "start_date", endDate = "end_date" }
        var start: Date? { startDate.flatMap(BruceDate.parse) }
        var end: Date? { endDate.flatMap(BruceDate.parse) }
        /// Started (or no start given) and not yet ended (or no end given).
        func isActive(at now: Date = Date()) -> Bool {
            if let s = start, s > now { return false }
            if let e = end, e <= now { return false }
            return true
        }
    }

    // MARK: Similar classes [c7:24, 41] GET /v52/studio/class/alternative_recommendation?class_id=
    /// A "Similar classes" card: nearby classes around the same time (the official app offers them for a full class).
    struct ClassCard: Decodable, Identifiable, Hashable {
        struct StudioRef: Decodable, Hashable { let id: Int; let name: String? }
        let id: Int
        let title: String?
        let photo: String?
        let distance: Int?          // metres from the original class's studio
        let startTime: String
        let endTime: String?
        let studio: StudioRef?
        enum CodingKeys: String, CodingKey { case id, title, photo, distance, studio, startTime = "start_time", endTime = "end_time" }
        var start: Date? { BruceDate.parse(startTime) }
        var end: Date? { endTime.flatMap(BruceDate.parse) }
    }
    static func fetchSimilarClasses(token: String, classId: Int) async throws -> [ClassCard] {
        struct R: Decodable { let classCards: [ClassCard]
            enum CodingKeys: String, CodingKey { case classCards = "class_cards" } }
        let q = [("class_id", String(classId)), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/studio/class/alternative_recommendation", query: q, token: token))).classCards
    }
    struct StudioPhotoFile: Codable, Hashable { let fileId: String?
        enum CodingKeys: String, CodingKey { case fileId = "file_id" } }
    struct StudioPhoto: Codable, Hashable { let order: Int?; let main: Bool?; let photo: StudioPhotoFile? }


    // MARK: All favourites [c5:39] GET /v52/favorite?locale=en (no studio_id)
    static func fetchAllFavorites(token: String) async throws -> [FavoriteRef] {
        struct R: Decodable { let favorites: [FavoriteRef] }
        return try decode(R.self, try await send(makeRequest("GET", "v52/favorite", query: [("locale", "en")], token: token))).favorites
    }

    // MARK: Indexed search [c5:423] GET /v52/search
    struct SearchFields: Decodable, Hashable { let id: Int?; let name: String?; let city: String?; let distance: Int?; let photo: String? }
    struct SearchHit: Decodable, Hashable, Identifiable { let id: String; let type: String?; let fields: SearchFields? }
    static func search(token: String, query: String, lat: Double, lon: Double, cityCode: String) async throws -> [SearchHit] {
        struct R: Decodable { let result: [SearchHit] }
        let q = [("query", query), ("type", "studio,class"), ("latitude", String(lat)), ("longitude", String(lon)),
                 ("city_code", cityCode), ("search_mode", "indexed"), ("locale", "en")]
        return try decode(R.self, try await send(makeRequest("GET", "v52/search", query: q, token: token))).result
    }
}
