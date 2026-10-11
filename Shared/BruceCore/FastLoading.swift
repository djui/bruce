import Foundation

// Fast list loading (measured against the public endpoints, see Bruce-iOS/README.md "Performance"):
//
// * Studios: `GET /v52/studio/filter` caps `limit` at 30 and pages by `next_cursor` = base64("id::<last id>")
//   with ids descending. Pages with the heavy includes (addresses, categories, visit limits) take ~0.85 s,
//   pages with plain fields ~0.15 s. So: (1) a light pass streams names/photos page by page, (2) the full
//   pages are fetched in parallel by splitting the id space into balanced ranges (cursor "id::<upper>"),
//   (3) the result is cached on disk and shown instantly on the next launch (stale-while-revalidate).
// * Classes: `GET /v52/class` for a day is split into time windows fetched concurrently, each paged.

func debugTiming(_ label: String, since start: Date, _ extra: String = "") {
    #if DEBUG
    print(String(format: "[timing] %@ %.2fs %@", label, Date().timeIntervalSince(start), extra))
    #endif
}

extension BruceAPI {
    static let studioListFields = "checkin_studio_id,city_id,deleted,has_address,has_classes,has_openings,id,integration_door_type,keyword,label,name,photo,qr_code_id,rating,remote,requires_additional_cost,status,tier_level,time_zone,vicinity,visit_limit_id"
    static let studioLightFields = "id,name,photo,city_id,vicinity,status,qr_code_id,rating,label,has_openings,has_classes,tier_level,time_zone"

    struct StudioPage { let studios: [Studio]; let next: String?; let cacheExpire: Int? }

    static func idCursor(_ id: Int) -> String { Data("id::\(id)".utf8).base64EncodedString() }

    /// One page of the studio list. `light` = plain fields only (no includes): ~5x faster.
    static func fetchStudioPage(token: String?, cursor: String?, light: Bool, countryCode: String = "SE") async throws -> StudioPage {
        struct R: Decodable { let studios: [Studio]; let metadata: Metadata? }
        var q: [(String, String)] = [("filter[status][in]", "live"), ("filter[country_code][eq]", countryCode),
                                     ("fields", light ? studioLightFields : studioListFields), ("limit", "30"), ("locale", "en")]
        if !light { q.append(("include", "addresses,addresses_address,categories,categories_category,visit_limit")) }
        if let cursor { q.append(("next_cursor", cursor)) }
        let r = try decode(R.self, try await send(makeRequest("GET", "v52/studio/filter", query: q, token: token)))
        let next = r.metadata?.pagination?.nextCursor
        return StudioPage(studios: r.studios, next: (next?.isEmpty ?? true) || r.studios.isEmpty ? nil : next,
                          cacheExpire: r.metadata?.cacheExpireSeconds)
    }

    /// Full studio list. Light pass first (only when no ids are known yet), then full pages in parallel over
    /// balanced id ranges. `onPage(studios, light, cacheExpireSeconds)` is called on the main actor for every page as it arrives.
    static func fetchStudiosFast(token: String?, knownIds: [Int], ranges: Int = 6,
                                 onPage: @escaping @MainActor ([Studio], Bool, Int?) -> Void) async throws -> [Studio] {
        var ids = knownIds
        if ids.isEmpty {
            var cursor: String?
            for _ in 0..<200 {
                let p = try await fetchStudioPage(token: token, cursor: cursor, light: true)
                ids += p.studios.map(\.id)
                await onPage(p.studios, true, p.cacheExpire)
                guard let n = p.next else { break }
                cursor = n
            }
        }
        // Balanced descending boundaries: range i covers ids < bounds[i] (nil = from the top) and >= bounds[i+1].
        let sorted = ids.sorted(by: >)
        let k = max(1, min(ranges, sorted.count / 30))
        var bounds: [Int?] = [nil]
        for i in 1..<max(k, 1) { bounds.append(sorted[sorted.count * i / k]) }
        bounds.append(0)
        return try await withThrowingTaskGroup(of: [Studio].self) { group in
            for i in 0..<(bounds.count - 1) {
                let hi = bounds[i], lo = bounds[i + 1] ?? 0
                group.addTask {
                    var out: [Studio] = []
                    var cursor = hi.map(idCursor)
                    for _ in 0..<200 {
                        let p = try await fetchStudioPage(token: token, cursor: cursor, light: false)
                        let mine = p.studios.filter { $0.id >= lo }
                        out += mine
                        await onPage(mine, false, p.cacheExpire)
                        guard let n = p.next, (p.studios.map(\.id).min() ?? 0) >= lo else { break }
                        cursor = n
                    }
                    return out
                }
            }
            var all: [Int: Studio] = [:]
            for try await part in group { for s in part { all[s.id] = s } }
            return Array(all.values)
        }
    }

    private static let windowFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()

    /// Classes in [from, to), paged; list fields only (no credit costs / dynamic prices, which only the detail needs).
    static func fetchClassRange(token: String?, from: Date, to: Date, studioId: Int? = nil, cityId: Int = 1,
                                maxPages: Int = 40, onPage: (@MainActor ([BruceClass]) -> Void)? = nil) async throws -> [BruceClass] {
        struct R: Decodable { let classes: [BruceClass]; let metadata: Metadata? }
        var out: [BruceClass] = []
        var cursor: String?
        for _ in 0..<maxPages {
            var q: [(String, String)] = [
                ("start_time_after", windowFormatter.string(from: from)), ("start_time_before", windowFormatter.string(from: to)),
                ("limit", "30"), ("locale", "en"), ("is_recurring_base", "false"), ("is_master", "false"),
                ("dedicated", "false"), ("opening", "false"), ("studio_status", "live"),
                ("include_absolute_times", "true"), ("include_class_categories", "true"),
            ]
            if let studioId { q += [("studio_id", String(studioId)), ("presentation_studio_id", String(studioId))] }
            else { q.append(("studio_city_id", String(cityId))) }
            if let cursor { q.append(("next_cursor", cursor)) }
            let r = try decode(R.self, try await send(makeRequest("GET", "v52/class", query: q, token: token)))
            out += r.classes
            if let onPage { await onPage(r.classes) }
            guard let n = r.metadata?.pagination?.nextCursor, !n.isEmpty, !r.classes.isEmpty else { break }
            cursor = n
        }
        return out
    }

    /// A whole city day, split into time windows fetched concurrently (each window paged).
    static func fetchClassDayFast(token: String?, day: Date, cityId: Int,
                                  onPage: @escaping @MainActor ([BruceClass]) -> Void) async throws -> [BruceClass] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let hours = [0, 7, 9, 11, 13, 16, 18, 20, 24]
        return try await withThrowingTaskGroup(of: [BruceClass].self) { group in
            for i in 0..<(hours.count - 1) {
                let a = start.addingTimeInterval(Double(hours[i]) * 3600), b = start.addingTimeInterval(Double(hours[i + 1]) * 3600)
                group.addTask { try await fetchClassRange(token: token, from: a, to: b, cityId: cityId, onPage: onPage) }
            }
            var all: [Int: BruceClass] = [:]
            for try await part in group { for c in part { all[c.id] = c } }
            return all.values.sorted { $0.startTime < $1.startTime }
        }
    }
}

/// Disk cache for the studio list (stale-while-revalidate).
enum StudioCache {
    struct Payload: Codable { let savedAt: Date; let expireSeconds: Int?; let studios: [BruceAPI.Studio] }
    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("bruce-studios-SE-v1.json")
    }
    static func load() -> Payload? {
        guard !AppModel.demo, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: d)
    }
    static func save(_ studios: [BruceAPI.Studio], expire: Int?) {
        guard !AppModel.demo, !studios.isEmpty,
              let d = try? JSONEncoder().encode(Payload(savedAt: Date(), expireSeconds: expire, studios: studios)) else { return }
        try? d.write(to: url, options: .atomic)
    }
    /// Fresh per the server's `cache_expire_seconds` hint (null/0 = always revalidate).
    static func isFresh(_ p: Payload) -> Bool {
        guard let e = p.expireSeconds, e > 0 else { return false }
        return Date().timeIntervalSince(p.savedAt) < Double(e)
    }
}
