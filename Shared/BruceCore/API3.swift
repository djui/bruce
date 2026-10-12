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
    // MARK: Class attendees [c3:58, 573; c2:55]
    /// Public profile on an attendee booking. Same shape as `booking.user` on reviews [c3:101]; only
    /// filled for members with "Bruce Studios Social" on. Everyone else comes back without `user`.
    struct AttendeeUser: Decodable, Hashable {
        let id: Int
        let firstName: String?
        let lastName: String?
        let displayName: String?
        let photo: String?
        let social: Bool?
        enum CodingKeys: String, CodingKey {
            case id, photo, social, firstName = "first_name", lastName = "last_name", displayName = "display_name"
        }
    }
    struct ClassAttendee: Decodable, Identifiable, Hashable {
        let id: Int
        let userId: Int?
        let user: AttendeeUser?
        enum CodingKeys: String, CodingKey { case id, user, userId = "user_id" }
    }
    /// Everyone booked on a class: `GET /v52/booking?class_id=<id>&include_user=true&include_message=true&deleted=false`,
    /// paged by `next_cursor` (a class rarely needs more than one page of 30).
    static func fetchClassAttendees(token: String, classId: Int, maxPages: Int = 4) async throws -> [ClassAttendee] {
        struct R: Decodable { let bookings: [ClassAttendee]; let metadata: Metadata? }
        var out: [ClassAttendee] = []
        var cursor: String?
        for _ in 0..<maxPages {
            var q = [("class_id", String(classId)), ("include_user", "true"), ("include_message", "true"),
                     ("deleted", "false"), ("limit", "30"), ("locale", "en")]
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token)))
            out += r.bookings
            guard let next = r.metadata?.pagination?.nextCursor, !next.isEmpty, !r.bookings.isEmpty else { break }
            cursor = next
        }
        return out
    }

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
    /// Studio notice banner: `alerts[]` (include_alerts=true, exclude_expired_alerts=true) [c2:212].
    struct StudioAlert: Codable, Hashable { let message: String?; let type: String?; let order: Int? }
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

extension BruceAPI.Studio {
    /// First notice banner text by `order`; shown on the studio page and on its class pages.
    var notice: String? {
        (alerts ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap(\.message).first { !$0.isEmpty }
    }
}
