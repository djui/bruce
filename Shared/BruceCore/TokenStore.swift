import Foundation
import Security

/// Session tokens from `POST /v52/access/authenticate`. Never hardcoded.
struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var accessTokenExpiresAt: String?
    var refreshTokenExpiresAt: String?
    var userId: Int?

    var accessExpiry: Date? { accessTokenExpiresAt.flatMap(Session.parseDate) }
    var isAccessExpired: Bool { accessExpiry.map { $0 <= Date() } ?? false }

    static func parseDate(_ s: String) -> Date? {
        // Server sends nanosecond precision, e.g. 2026-01-01T00:00:00.123456789Z.
        let f = ISO8601DateFormatter()   // rare: only for nanosecond timestamps BruceDate.parse could not read
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z") {
            let trimmed = String(s[..<dot]) + "." + String(s[s.index(after: dot)..<z].prefix(3)) + "Z"
            if let d = f.date(from: trimmed) { return d }
        }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Keychain storage for the session.
/// Resolution order: env `BRUCE_ACCESS_TOKEN` (access token only), then the Keychain
/// session, then the legacy single-token Keychain item.
enum TokenStore {
    #if os(iOS)
    static let service = "net.dauernheim.bruce"
    #else
    static let service = "net.dauernheim.BruceMacOS"
    #endif
    /// Pre-rename service name; its session is migrated on first read.
    static let oldService = "net.dauernheim.BruceCheckIn"
    static let legacyAccount = "bruce-access-token"
    static let sessionAccount = "bruce-session"

    static func resolve() -> Session? {
        if let env = ProcessInfo.processInfo.environment["BRUCE_ACCESS_TOKEN"], !env.isEmpty {
            return Session(accessToken: env)
        }
        migrateOldService()
        if let d = read(sessionAccount), let s = try? JSONDecoder().decode(Session.self, from: d) { return s }
        if let d = read(legacyAccount), let t = String(data: d, encoding: .utf8), !t.isEmpty {
            return Session(accessToken: t)
        }
        return nil
    }

    static func save(_ s: Session) {
        if let d = try? JSONEncoder().encode(s) { write(sessionAccount, d) }
    }

    /// Save a manually entered access token (keeps any stored refresh token).
    static func save(accessToken: String) {
        var s = resolve() ?? Session(accessToken: accessToken)
        s.accessToken = accessToken
        save(s)
    }

    static func clear() {
        delete(sessionAccount); delete(legacyAccount)
    }

    private static func migrateOldService() {
        guard read(sessionAccount) == nil, read(legacyAccount) == nil else { return }
        for account in [sessionAccount, legacyAccount] {
            if let d = read(account, service: oldService) { write(account, d) }
            delete(account, service: oldService)
        }
    }

    private static func base(_ account: String, service: String = service) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func write(_ account: String, _ data: Data) {
        delete(account)
        var add = base(account)
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func delete(_ account: String, service: String = service) {
        SecItemDelete(base(account, service: service) as CFDictionary)
    }

    private static func read(_ account: String, service: String = service) -> Data? {
        var q = base(account, service: service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
