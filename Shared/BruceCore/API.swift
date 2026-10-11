import Foundation

/// Client for the Bruce Studios REST API (`https://api.bruce.app/v52`).
///
/// All routes, parameters and body shapes below were taken from Charles captures
/// of the official iOS app 14.4.2 (build 538); see ../../../API.md for evidence
/// file numbers. Auth is a single `X-Access-Token` header (no Bearer header).
enum BruceAPI {
    static let baseURL = URL(string: "https://api.bruce.app")!
    static let userAgent = "Bruce/14.4.2_538 (iOS27.0.0; Apple)"

    enum APIError: LocalizedError {
        case badURL
        case notLoggedIn
        case http(Int, Data)
        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid URL."
            case .notLoggedIn: return "Not logged in (no access token)."
            case .http(let code, let data):
                return "HTTP \(code): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")"
            }
        }
    }

    struct Pagination: Decodable {
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
    }
    struct Metadata: Decodable {
        let pagination: Pagination?
        /// Server cache hint (seconds); null/0 = always revalidate.
        let cacheExpireSeconds: Int?
        enum CodingKeys: String, CodingKey { case pagination, cacheExpireSeconds = "cache_expire_seconds" }
    }

    // MARK: - Request plumbing

    static func makeRequest(_ method: String, _ path: String, query: [(String, String)] = [],
                            token: String?, body: [String: Any]? = nil) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw APIError.badURL }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = comps.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "X-Access-Token") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return req
    }

    @discardableResult
    static func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw APIError.http(code, data) }
        return data
    }

    static func decode<T: Decodable>(_ t: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Auth  [capture 2: 461, 442]

    struct AuthResponse: Decodable {
        let userId: Int
        let accessToken: String
        let refreshToken: String?
        let accessTokenExpiresAt: String?
        let refreshTokenExpiresAt: String?
        enum CodingKeys: String, CodingKey {
            case userId = "user_id", accessToken = "access_token", refreshToken = "refresh_token"
            case accessTokenExpiresAt = "access_token_expires_at", refreshTokenExpiresAt = "refresh_token_expires_at"
        }
    }

    /// `POST /v52/access/authenticate` (no token) body
    /// `{"authenticator":"PASSWORD","email":..,"password":..,"locale":"en"}`.
    static func authenticate(email: String, password: String) async throws -> AuthResponse {
        let req = try makeRequest("POST", "v52/access/authenticate", token: nil, body: [
            "authenticator": "PASSWORD", "email": email, "password": password, "locale": "en",
        ])
        return try decode(AuthResponse.self, try await send(req))
    }

    /// `DELETE /v52/access/logout` body `{"locale":"en"}`.
    static func logoutRequest(token: String) throws -> URLRequest {
        try makeRequest("DELETE", "v52/access/logout", token: token, body: ["locale": "en"])
    }

    // MARK: - Studios

    struct Studio: Codable, Identifiable, Hashable {
        let id: Int
        let name: String
        let status: String?
        let integrationType: String?
        let integrationDoorType: String?
        let qrCodeId: String?
        let cityId: Int?
        let timeZone: String?
        let vicinity: String?
        let hasClasses: Bool?
        var photo: String? = nil
        var rating: Rating? = nil
        var studioCategories: [StudioCategory]? = nil
        var studioAddresses: [StudioAddress]? = nil
        var studioFacilities: [StudioFacility]? = nil
        var description: String? = nil
        var website: String? = nil
        var tierLevel: Int? = nil
        var hasOpenings: Bool? = nil
        var visitLimit: VisitLimitDef? = nil
        var label: String? = nil
        var studioPhotos: [StudioPhoto]? = nil
        var alerts: [StudioAlert]? = nil

        enum CodingKeys: String, CodingKey {
            case tierLevel = "tier_level", hasOpenings = "has_openings", visitLimit = "visit_limit"
            case label, alerts, studioPhotos = "studio_photos"
            case id, name, status, vicinity, photo, rating, description, website
            case studioCategories = "studio_categories", studioAddresses = "studio_addresses"
            case studioFacilities = "studio_facilities"
            case integrationType = "integration_type"
            case integrationDoorType = "integration_door_type"
            case qrCodeId = "qr_code_id"
            case cityId = "city_id"
            case timeZone = "time_zone"
            case hasClasses = "has_classes"
        }

        var isLive: Bool { status?.lowercased() == "live" }
        /// Door QR major if the studio's `qr_code_id` is "stc:<major>".
        var stcMajor: String? {
            guard let q = qrCodeId, q.hasPrefix("stc:") else { return nil }
            return String(q.dropFirst(4))
        }
        /// Live and either a STC door QR or a booking/door integration.
        var supportsCheckIn: Bool { isLive && (stcMajor != nil || integrationType != nil) }
    }

    /// Legacy unauthenticated list (only ~100 studios). Used when not logged in.
    static func fetchPublicStudios() async throws -> [Studio] {
        struct R: Decodable { let studios: [Studio] }
        let req = try makeRequest("GET", "v1/studios", token: nil)
        return try decode(R.self, try await send(req)).studios
    }

    /// Full Explore list: `GET /v52/studio/filter` paged by `next_cursor` [153..1133].
    static func fetchAllStudios(token: String, countryCode: String = "SE",
                                progress: (Int) -> Void = { _ in }) async throws -> [Studio] {
        struct R: Decodable { let studios: [Studio]; let metadata: Metadata? }
        var all: [Int: Studio] = [:]
        var cursor: String?
        for _ in 0..<200 {
            var q: [(String, String)] = [
                ("filter[status][in]", "live"),
                ("filter[country_code][eq]", countryCode),
                ("fields", "checkin_studio_id,city_id,deleted,has_address,has_classes,has_openings,id,integration_door_type,keyword,label,name,photo,qr_code_id,rating,remote,requires_additional_cost,status,tier_level,time_zone,vicinity,visit_limit_id"),
                ("include", "addresses,addresses_address,categories,categories_category,visit_limit"),
                ("limit", "30"),
                ("locale", "en"),
            ]
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/studio/filter", query: q, token: token)))
            let before = all.count
            for s in r.studios { all[s.id] = s }
            progress(all.count)
            guard let next = r.metadata?.pagination?.nextCursor, !next.isEmpty,
                  !r.studios.isEmpty, all.count > before else { break }
            cursor = next
        }
        return Array(all.values)
    }

    // MARK: - Classes  [20..1144, 214, 216, 1017, 1019]

    struct BruceClass: Decodable, Identifiable, Hashable {
        let id: Int
        let studioId: Int
        let title: String
        let startTime: String
        let endTime: String?
        let spots: Int?
        let availableSpots: Int?
        let instructor: String?
        let canceled: Bool?
        var description: String? = nil
        var photo: String? = nil
        var bookableLatestTime: String? = nil
        var unbookableLatestTime: String? = nil
        var unbookableLatest: Int? = nil
        var earlyCheckInMinutes: Int? = nil
        var lateCheckInMinutes: Int? = nil
        var classCategories: [ClassCategory]? = nil
        var studio: StudioLite? = nil
        enum CodingKeys: String, CodingKey {
            case id, title, spots, instructor, canceled, description, photo, studio
            case studioId = "studio_id", startTime = "start_time", endTime = "end_time"
            case availableSpots = "available_spots"
            case bookableLatestTime = "bookable_latest_time", unbookableLatestTime = "unbookable_latest_time"
            case unbookableLatest = "unbookable_latest"
            case earlyCheckInMinutes = "early_check_in_minutes", lateCheckInMinutes = "late_check_in_minutes"
            case classCategories = "class_categories"
        }
        var start: Date? { BruceDate.parse(startTime) }
        var end: Date? { endTime.flatMap(BruceDate.parse) }
        var durationMinutes: Int? {
            guard let s = start, let e = end else { return nil }
            return Int(e.timeIntervalSince(s) / 60)
        }
    }

    /// `GET /v52/class` for one day (city-wide) or for one studio, paged by `next_cursor`.
    static func fetchClasses(token: String, day: Date, studioId: Int? = nil, cityId: Int = 1,
                             maxPages: Int = 60) async throws -> [BruceClass] {
        struct R: Decodable { let classes: [BruceClass]; let metadata: Metadata? }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'00:00:00"
        let cal = Calendar.current
        let from = cal.startOfDay(for: day)
        let to = cal.date(byAdding: .day, value: 1, to: from)!
        var out: [BruceClass] = []
        var cursor: String?
        for _ in 0..<maxPages {
            var q: [(String, String)] = [
                ("start_time_after", f.string(from: from)),
                ("start_time_before", f.string(from: to)),
                ("limit", "30"), ("locale", "en"),
                ("is_recurring_base", "false"), ("is_master", "false"),
                ("dedicated", "false"), ("opening", "false"),
                ("studio_status", "live"), ("include_absolute_times", "true"),
                ("include_class_categories", "true"), ("include_booking_credit_costs", "true"),
                ("include_dynamic_prices", "true"),
            ]
            if let studioId {
                q.append(("studio_id", String(studioId)))
                q.append(("presentation_studio_id", String(studioId)))
            } else {
                q.append(("studio_city_id", String(cityId)))
            }
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/class", query: q, token: token)))
            out += r.classes
            guard let next = r.metadata?.pagination?.nextCursor, !next.isEmpty, !r.classes.isEmpty else { break }
            cursor = next
        }
        return out.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Bookings  [84, 120, and capture 1: 75, 86]

    struct Booking: Decodable, Identifiable, Hashable {
        let id: Int
        let classId: Int?
        let studioId: Int?
        let checkedInAt: String?
        let `class`: BruceClass?
        enum CodingKeys: String, CodingKey {
            case id, `class`
            case classId = "class_id", studioId = "studio_id", checkedInAt = "checked_in_at"
        }
    }

    static func fetchBookings(token: String, userId: Int) async throws -> [Booking] {
        struct R: Decodable { let bookings: [Booking] }
        let q: [(String, String)] = [
            ("user_id", String(userId)), ("limit", "30"), ("deleted", "false"),
            ("include_class", "true"), ("locale", "en"),
        ]
        return try decode(R.self, try await send(makeRequest("GET", "v52/booking", query: q, token: token))).bookings
    }

    /// `POST /v52/booking` body `{"class_id":..,"booked_via":..,"include_user":false,"locale":"en"}`
    /// -> `{"booking":{id,class_id,studio_id,...}}`.
    static func bookRequest(token: String, classId: Int) throws -> URLRequest {
        try makeRequest("POST", "v52/booking", token: token, body: [
            "class_id": classId, "booked_via": "HOMESCREEN_SPOTLIGHT", "include_user": false, "locale": "en",
        ])
    }

    /// `DELETE /v52/booking/<id>` body `{"locale":"en","include_user":false}` -> `{"booking":{deleted_at,...}}`.
    static func cancelRequest(token: String, bookingId: Int) throws -> URLRequest {
        try makeRequest("DELETE", "v52/booking/\(bookingId)", token: token,
                        body: ["locale": "en", "include_user": false])
    }

    // MARK: - Check-in (capture 1: 163)

    static func perform(_ req: URLRequest) async throws -> (Int, String) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        return (code, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Door identifiers for the check-in call, as encoded in the studio's door QR
/// code / beacon ("stc:<major>", door id = minor). Not secret.
struct CheckInConfig: Codable, Equatable {
    var major: String = ""
    var doorId: String = ""

    /// Parse a scanned door QR like "stc://open-door?major=13816&minor=118551".
    @discardableResult
    mutating func apply(qr: String) -> Bool {
        guard let c = URLComponents(string: qr.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "stc", c.host == "open-door",
              let ma = c.queryItems?.first(where: { $0.name == "major" })?.value,
              let mi = c.queryItems?.first(where: { $0.name == "minor" })?.value
        else { return false }
        major = ma; doorId = mi
        return true
    }


}
