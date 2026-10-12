import Foundation
import CoreLocation

// Custom areas ("New area" / saved areas in the Explore filter).
//
// Local-only, like the original app: capture 6 (creating and using areas) shows no area/zone/polygon
// request, and /v52/class and /v52/studio/filter carry no bounds parameter, so the original stores areas on
// the device and filters client-side. `LocalAreaStore` (JSON file) is the real implementation; the
// `AreaStore` protocol only keeps the door open should a server API ever appear.

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
}

struct SavedArea: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var cityId: Int
    /// Closed polygon (first point not repeated at the end).
    var points: [GeoPoint]
    var createdAt = Date()

    /// Ray casting in lat/lon (fine at city scale).
    func contains(lat: Double, lon: Double) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            if (a.lat > lat) != (b.lat > lat),
               lon < (b.lon - a.lon) * (lat - a.lat) / (b.lat - a.lat) + a.lon { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// Persistence for saved areas. Async + throwing so an API implementation fits the same shape.
protocol AreaStore: Sendable {
    func list() async throws -> [SavedArea]
    func create(_ area: SavedArea) async throws -> SavedArea
    func update(_ area: SavedArea) async throws -> SavedArea
    func delete(_ id: UUID) async throws
}

/// JSON file in Application Support (per device). Used until the API endpoints are known.
actor LocalAreaStore: AreaStore {
    private let url: URL
    init(filename: String = "bruce-areas-v1.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
    }
    func list() async throws -> [SavedArea] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return try JSONDecoder().decode([SavedArea].self, from: d)
    }
    func create(_ area: SavedArea) async throws -> SavedArea {
        var all = try await list()
        all.append(area)
        try JSONEncoder().encode(all).write(to: url, options: .atomic)
        return area
    }
    func update(_ area: SavedArea) async throws -> SavedArea {
        let all = try await list().map { $0.id == area.id ? area : $0 }
        try JSONEncoder().encode(all).write(to: url, options: .atomic)
        return area
    }
    func delete(_ id: UUID) async throws {
        let all = try await list().filter { $0.id != id }
        try JSONEncoder().encode(all).write(to: url, options: .atomic)
    }
}

/// In-memory store (demo mode: nothing written to disk).
actor MemoryAreaStore: AreaStore {
    private var areas: [SavedArea]
    init(_ initial: [SavedArea] = []) { areas = initial }
    func list() async throws -> [SavedArea] { areas }
    func create(_ area: SavedArea) async throws -> SavedArea { areas.append(area); return area }
    func update(_ area: SavedArea) async throws -> SavedArea {
        if let i = areas.firstIndex(where: { $0.id == area.id }) { areas[i] = area }
        return area
    }
    func delete(_ id: UUID) async throws { areas.removeAll { $0.id == id } }
}

enum PolygonMath {
    /// Douglas–Peucker on a local equirectangular projection (metres), auto-tuned to ≤ `maxPoints`.
    static func simplify(_ pts: [GeoPoint], maxPoints: Int = 50) -> [GeoPoint] {
        guard pts.count > maxPoints, let ref = pts.first else { return pts }
        let k = cos(ref.lat * .pi / 180)
        let xy = pts.map { (($0.lon - ref.lon) * 111_320 * k, ($0.lat - ref.lat) * 110_540) }
        var tolerance = 5.0
        var keep = dp(xy, tolerance)
        while keep.count > maxPoints && tolerance < 5_000 { tolerance *= 1.5; keep = dp(xy, tolerance) }
        return keep.map { pts[$0] }
    }

    private static func dp(_ p: [(Double, Double)], _ eps: Double) -> [Int] {
        var keep = [Bool](repeating: false, count: p.count)
        keep[0] = true; keep[p.count - 1] = true
        var stack = [(0, p.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var maxD = 0.0, idx = a
            for i in (a + 1)..<b {
                let d = perpendicular(p[i], p[a], p[b])
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > eps { keep[idx] = true; stack.append((a, idx)); stack.append((idx, b)) }
        }
        return keep.indices.filter { keep[$0] }
    }

    private static func perpendicular(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let len = (dx * dx + dy * dy).squareRoot()
        if len == 0 { return ((p.0 - a.0) * (p.0 - a.0) + (p.1 - a.1) * (p.1 - a.1)).squareRoot() }
        return abs(dy * p.0 - dx * p.1 + b.0 * a.1 - b.1 * a.0) / len
    }

    /// Rectangle polygon for a visible map region (Save without drawing).
    /// Bounding box (centre and span in degrees) with some padding, for fitting a map camera to an area.
    static func bounds(_ pts: [GeoPoint], padding: Double = 1.3) -> (centerLat: Double, centerLon: Double, latDelta: Double, lonDelta: Double)? {
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else { return nil }
        return ((minLat + maxLat) / 2, (minLon + maxLon) / 2, max((maxLat - minLat) * padding, 0.005), max((maxLon - minLon) * padding, 0.005))
    }

    static func rectangle(centerLat: Double, centerLon: Double, latDelta: Double, lonDelta: Double) -> [GeoPoint] {
        let n = centerLat + latDelta / 2, s = centerLat - latDelta / 2
        let w = centerLon - lonDelta / 2, e = centerLon + lonDelta / 2
        return [GeoPoint(lat: n, lon: w), GeoPoint(lat: n, lon: e), GeoPoint(lat: s, lon: e), GeoPoint(lat: s, lon: w)]
    }
}

extension AppModel {
    var selectedArea: SavedArea? { areas.first { $0.id == selectedAreaId } }
    var cityAreas: [SavedArea] { areas.filter { $0.cityId == cityId } }

    /// Studio inside the selected area (main address). Studios without coordinates are excluded.
    func studioInSelectedArea(_ studioId: Int) -> Bool {
        guard let a = selectedArea else { return true }
        guard let s = studio(studioId),
              let addr = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
              let lat = addr.latitude, let lon = addr.longitude else { return false }
        return a.contains(lat: lat, lon: lon)
    }

    /// Studios of the area's city whose main address lies inside the area.
    func studios(in area: SavedArea) -> [BruceAPI.Studio] {
        studios.filter { s in
            guard s.cityId == nil || s.cityId == area.cityId,
                  let addr = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
                  let lat = addr.latitude, let lon = addr.longitude else { return false }
            return area.contains(lat: lat, lon: lon)
        }
    }

    func loadAreas() async {
        if let list = try? await areaStore.list() { areas = list }
    }

    @discardableResult
    func saveArea(name: String, points: [GeoPoint]) async -> SavedArea? {
        let area = SavedArea(name: name, cityId: cityId, points: points)
        do {
            let saved = try await areaStore.create(area)
            areas.append(saved)
            selectedAreaId = saved.id
            flash("Area \u{201C}\(saved.name)\u{201D} saved")
            return saved
        } catch { flash("Could not save the area"); return nil }
    }

    func deleteArea(_ id: UUID) async {
        do {
            try await areaStore.delete(id)
            areas.removeAll { $0.id == id }
            if selectedAreaId == id { selectedAreaId = nil }
        } catch { flash("Could not delete the area") }
    }

    func renameArea(_ id: UUID, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, var a = areas.first(where: { $0.id == id }), a.name != n else { return }
        a.name = n
        do {
            let saved = try await areaStore.update(a)
            if let i = areas.firstIndex(where: { $0.id == id }) { areas[i] = saved }
            flash("Area renamed to \u{201C}\(n)\u{201D}")
        } catch { flash("Could not rename the area") }
    }

    func area(_ id: UUID) -> SavedArea? { areas.first { $0.id == id } }

    var nextAreaName: String { "My area \(cityAreas.count + 1)" }
}
