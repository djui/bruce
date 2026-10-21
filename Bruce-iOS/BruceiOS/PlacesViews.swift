import SwiftUI
import MapKit

// MARK: - Settings › Places & commute (device only; Recommendations.swift)

/// MapKit travel times for "For you". Few requests: the scorer prefilters by straight-line distance and asks only
/// for the closest studios; answers are cached in memory and on the device for a week. Transit falls back to the
/// distance estimate when MapKit has no ETA (nil).
@MainActor
enum CommuteETA {
    private static var cache: [String: (minutes: Int, at: Double)] = {
        guard let d = UserDefaults.standard.dictionary(forKey: "commuteETACache") as? [String: [Double]] else { return [:] }
        return d.compactMapValues { $0.count == 2 ? (Int($0[0]), $0[1]) : nil }
    }()

    static func minutes(_ q: TravelQuery) async -> Int? {
        let now = Date().timeIntervalSince1970
        if let c = cache[q.key], now - c.at < 7 * 86_400 { return c.minutes }
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: q.from.lat, longitude: q.from.lon), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: q.to.lat, longitude: q.to.lon), address: nil)
        switch q.mode {
        case .walk: req.transportType = .walking
        case .bike: req.transportType = .cycling
        case .transit: req.transportType = .transit
        case .car: req.transportType = .automobile
        }
        guard let eta = try? await MKDirections(request: req).calculateETA() else { return nil }
        let m = max(1, Int((eta.expectedTravelTime / 60).rounded()))
        cache[q.key] = (m, now)
        if cache.count > 400 { cache = cache.filter { now - $0.value.at < 3 * 86_400 } }
        UserDefaults.standard.set(cache.mapValues { [Double($0.minutes), $0.at] }, forKey: "commuteETACache")
        return m
    }
}

struct PlacesView: View {
    @Environment(AppModel.self) var m

    var body: some View {
        let s = m.recSettings
        Form {
            Section {
                PlacesMap(settings: s).frame(height: 196).clipShape(RoundedRectangle(cornerRadius: 24))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                ForEach(s.places) { p in
                    NavigationLink(value: SheetRoute.editPlace(p.id)) { PlaceRow(place: p) }
                }
                .onDelete { idx in var n = s; n.places.remove(atOffsets: idx); m.saveRecSettings(n) }
                NavigationLink(value: SheetRoute.editPlace(nil)) {
                    Label("Add place", systemImage: "plus").bruceFont(16, weight: .semibold).foregroundStyle(Theme.limeInk)
                }
            } header: { Text("Places") } footer: { Text("Saved on this iPhone only. Never sent to Bruce or our server.") }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(CommuteMode.allCases) { mode in
                                GlassChip(selected: s.mode == mode, action: { update { $0.mode = mode } }) {
                                    HStack(spacing: 5) { Image(systemName: mode.symbol); Text(mode.title) }.fixedSize()
                                }
                                .accessibilityAddTraits(s.mode == mode ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            } header: { Text("How you get around") }
            Section {
                Picker("Max detour", selection: Binding(get: { s.maxDetour }, set: { v in update { $0.maxDetour = v } })) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                .tint(Theme.secondary)
                HStack {
                    Text("Workdays near work")
                    Spacer()
                    timeMenu(s.workStart) { v in update { $0.workStart = v; $0.workEnd = max($0.workEnd, v + 30) } }
                    Text("–").foregroundStyle(Theme.secondary)
                    timeMenu(s.workEnd) { v in update { $0.workEnd = v; $0.workStart = min($0.workStart, v - 30) } }
                }
                Toggle("Use friends' bookings", isOn: Binding(get: { s.useFriends }, set: { v in update { $0.useFriends = v } }))
            } footer: {
                Text("On workdays, classes in this window are measured from work. After work, a class near your way home shows the extra minutes.")
            }
        }
        .tint(Theme.lime)
        .sheetChrome("Places & commute")
    }

    func update(_ change: (inout RecSettings) -> Void) {
        var n = m.recSettings
        change(&n)
        m.saveRecSettings(n)
    }

    func timeMenu(_ value: Int, set: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(Array(stride(from: 6 * 60, through: 22 * 60, by: 30)), id: \.self) { t in
                Button(RecSettings.clock(t)) { set(t) }
            }
        } label: {
            Text(RecSettings.clock(value)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
    }
}

struct PlaceRow: View {
    let place: SavedPlace
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.symbol).bruceFont(14, weight: .semibold).foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(place.kind == .home ? Theme.lime : Color.white, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.divider, lineWidth: place.kind == .home ? 0 : 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).bruceFont(16)
                Text(place.kind == .work ? "\(place.address) · \(place.workdaysLabel)" : place.address)
                    .bruceFont(14).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
    }
}

/// The places and the trip between work and home with its travel time. Offline (demo) a drawn map.
struct PlacesMap: View {
    @Environment(AppModel.self) var m
    let settings: RecSettings

    var tripMinutes: Int? {
        guard let h = settings.home, let w = settings.work else { return nil }
        return m.travelOverrides[Recommender.travelKey(w.point, h.point, settings.mode)]
            ?? settings.mode.estimateMinutes(meters: Recommender.meters(w.point, h.point))
    }

    var body: some View {
        if AppModel.remoteAssets && !settings.places.isEmpty { live } else { drawn }
    }

    var live: some View {
        Map(initialPosition: region, interactionModes: [.zoom, .pan]) {
            if let h = settings.home, let w = settings.work {
                MapPolyline(coordinates: [w.point.coordinate, h.point.coordinate])
                    .stroke(.black.opacity(0.8), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [7, 6]))
                if let t = tripMinutes {
                    Annotation("", coordinate: GeoPoint(lat: (h.point.lat + w.point.lat) / 2, lon: (h.point.lon + w.point.lon) / 2).coordinate) {
                        tripPill(t)
                    }
                }
            }
            ForEach(settings.places) { p in
                Annotation(p.name, coordinate: p.point.coordinate) { pin(p) }
            }
            ForEach(nearbyStudios, id: \.0) { _, c in
                Annotation("", coordinate: c) { Circle().fill(.black.opacity(0.75)).frame(width: 10, height: 10) }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    /// A few studios near the places (dots), like the mockup.
    var nearbyStudios: [(Int, CLLocationCoordinate2D)] {
        guard !settings.places.isEmpty else { return [] }
        return m.cityStudios.compactMap { s -> (Int, CLLocationCoordinate2D, Double)? in
            guard let p = m.studioPoint(s.id) else { return nil }
            let d = settings.places.map { Recommender.meters($0.point, p) }.min() ?? .infinity
            return d < 1500 ? (s.id, p.coordinate, d) : nil
        }
        .sorted { $0.2 < $1.2 }.prefix(12).map { ($0.0, $0.1) }
    }

    var region: MapCameraPosition {
        let pts = settings.places.map(\.point)
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else { return .automatic }
        let span = MKCoordinateSpan(latitudeDelta: max(0.012, (maxLat - minLat) * 1.8), longitudeDelta: max(0.02, (maxLon - minLon) * 1.8))
        return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: span))
    }

    func pin(_ p: SavedPlace) -> some View {
        Image(systemName: p.symbol).bruceFont(12, weight: .bold).foregroundStyle(.black)
            .frame(width: 28, height: 28)
            .background(Circle().fill(p.kind == .home ? Theme.lime : .white))
            .overlay(Circle().stroke(.black, lineWidth: 2))
    }

    func tripPill(_ t: Int) -> some View {
        Label("\(t) min", systemImage: settings.mode.symbol).bruceFont(11, weight: .bold).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4).background(.white, in: .capsule)
    }

    /// Offline stand-in: water, streets, the route and the pins (no map tiles in demo mode).
    var drawn: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let home = CGPoint(x: w * 0.30, y: h * 0.84), work = CGPoint(x: w * 0.68, y: h * 0.23)
            ZStack {
                Color(light: Color(red: 0.87, green: 0.90, blue: 0.85), dark: Color(red: 0.11, green: 0.14, blue: 0.13))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.61))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.54), control1: CGPoint(x: w * 0.3, y: h * 0.70), control2: CGPoint(x: w * 0.6, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w, y: h * 0.69))
                    p.addCurve(to: CGPoint(x: 0, y: h * 0.77), control1: CGPoint(x: w * 0.6, y: h * 0.62), control2: CGPoint(x: w * 0.3, y: h * 0.84))
                }
                .fill(Color(red: 0.62, green: 0.78, blue: 0.90).opacity(0.55))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.31)); p.addLine(to: CGPoint(x: w, y: h * 0.2))
                    p.move(to: CGPoint(x: w * 0.11, y: 0)); p.addLine(to: CGPoint(x: w * 0.22, y: h))
                    p.move(to: CGPoint(x: w * 0.54, y: 0)); p.addLine(to: CGPoint(x: w * 0.49, y: h))
                    p.move(to: CGPoint(x: w * 0.82, y: 0)); p.addLine(to: CGPoint(x: w * 0.9, y: h))
                    p.move(to: CGPoint(x: 0, y: h * 0.9)); p.addLine(to: CGPoint(x: w, y: h * 0.85))
                }
                .stroke(.white.opacity(0.55), lineWidth: 5)
                if settings.home != nil && settings.work != nil {
                    Path { p in
                        p.move(to: home)
                        p.addCurve(to: work, control1: CGPoint(x: w * 0.36, y: h * 0.62), control2: CGPoint(x: w * 0.55, y: h * 0.35))
                    }
                    .stroke(Color(red: 0.17, green: 0.17, blue: 0.18), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [7, 6]))
                    if let t = tripMinutes { tripPill(t).position(x: w * 0.56, y: h * 0.54) }
                }
                ForEach([CGPoint(x: 0.35, y: 0.77), CGPoint(x: 0.72, y: 0.36), CGPoint(x: 0.49, y: 0.43), CGPoint(x: 0.16, y: 0.48)], id: \.x) { d in
                    Circle().fill(.black.opacity(0.8)).frame(width: 10, height: 10).position(x: w * d.x, y: h * d.y)
                }
                if let p = settings.home { pin(p).position(home) }
                if let p = settings.work { pin(p).position(work) }
                if settings.places.isEmpty {
                    Text("Add home and work to see your trips").bruceFont(13, weight: .semibold).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 8).glassEffect(.regular, in: .capsule)
                }
            }
        }
        .accessibilityLabel(tripMinutes.map { "Map of your places. Work to home takes about \($0) minutes." } ?? "Map of your places")
    }
}

// MARK: - Add / edit a place

/// Address search with MapKit (MKLocalSearchCompleter + MKLocalSearch).
@MainActor
final class AddressSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    init(center: CLLocationCoordinate2D) {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(center: center, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    func search(_ q: String) {
        if q.trimmingCharacters(in: .whitespaces).count < 3 { results = []; completer.cancel(); return }
        completer.queryFragment = q
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ c: MKLocalSearchCompletion) async -> (GeoPoint, String)? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else { return nil }
        let label = [c.title, c.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return (GeoPoint(item.location.coordinate), label)
    }
}

struct EditPlaceView: View {
    @Environment(AppModel.self) var m
    @Environment(\.dismiss) var dismiss
    let placeId: UUID?
    @State private var place = SavedPlace(kind: .home, name: "Home", address: "", point: GeoPoint(lat: 0, lon: 0))
    @State private var query = ""
    @State private var hasPoint = false
    @State private var loaded = false
    @StateObject private var search = AddressSearch(center: CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686))
    @EnvironmentObject var loc: LocationProvider

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $place.kind) {
                    Text("Home").tag(SavedPlace.Kind.home)
                    Text("Work").tag(SavedPlace.Kind.work)
                    Text("Other").tag(SavedPlace.Kind.other)
                }
                .pickerStyle(.segmented)
                .onChange(of: place.kind) { _, k in if place.name.isEmpty || ["Home", "Work", "Place"].contains(place.name) { place.name = k == .home ? "Home" : k == .work ? "Work" : "Place" } }
                TextField("Name", text: $place.name)
            }
            Section {
                if hasPoint {
                    Label(place.address.isEmpty ? "Pinned location" : place.address, systemImage: "mappin.circle.fill").foregroundStyle(Theme.ink)
                }
                TextField("Search for an address", text: $query)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .onChange(of: query) { _, q in if !AppModel.demo { search.search(q) } }
                ForEach(search.results, id: \.self) { r in
                    Button {
                        Task {
                            if let (p, label) = await search.resolve(r) { place.point = p; place.address = label; hasPoint = true; query = ""; search.results = [] }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(Theme.ink)
                            if !r.subtitle.isEmpty { Text(r.subtitle).bruceFont(13).foregroundStyle(Theme.secondary) }
                        }
                    }
                }
                Button { useCurrentLocation() } label: { Label("Use my current location", systemImage: "location.fill") }
            } header: { Text("Address") } footer: {
                Text(AppModel.demo ? "Address search is off in the offline demo." : "Found with Apple Maps. Saved on this iPhone only.")
            }
            if place.kind == .work {
                Section {
                    HStack(spacing: 6) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                            let on = place.workdays.contains(d)
                            Button {
                                if on { place.workdays.removeAll { $0 == d } } else { place.workdays.append(d) }
                            } label: {
                                Text(["", "S", "M", "T", "W", "T", "F", "S"][d]).bruceFont(15, weight: .semibold)
                                    .foregroundStyle(on ? Color.black : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(on ? Theme.lime : Theme.chipGrey, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar(identifier: .gregorian).weekdaySymbols[d - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } header: { Text("Workdays") } footer: { Text(place.workdaysLabel) }
            }
            if placeId != nil {
                Section {
                    Button("Delete place", role: .destructive) {
                        var s = m.recSettings; s.places.removeAll { $0.id == place.id }; m.saveRecSettings(s); dismiss()
                    }
                }
            }
        }
        .tint(Theme.lime)
        .sheetChrome(placeId == nil ? "Add place" : place.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.glassProminent).tint(Theme.lime).foregroundStyle(.black)
                    .disabled(!hasPoint || place.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = placeId, let p = m.recSettings.places.first(where: { $0.id == id }) { place = p; hasPoint = true }
            else if m.recSettings.home != nil { place.kind = m.recSettings.work == nil ? .work : .other; place.name = m.recSettings.work == nil ? "Work" : "Place" }
        }
    }

    func save() {
        var s = m.recSettings
        // One home and one work: saving a new one replaces the old.
        if place.kind != .other { s.places.removeAll { $0.kind == place.kind && $0.id != place.id } }
        if let i = s.places.firstIndex(where: { $0.id == place.id }) { s.places[i] = place } else { s.places.append(place) }
        s.places.sort { ($0.kind == .home ? 0 : $0.kind == .work ? 1 : 2) < ($1.kind == .home ? 0 : $1.kind == .work ? 1 : 2) }
        m.saveRecSettings(s)
        dismiss()
    }

    func useCurrentLocation() {
        guard let l = m.userLocation else { loc.request(); m.flash("Allow location first, then try again"); return }
        place.point = GeoPoint(l.coordinate)
        hasPoint = true
        place.address = "Current location"
        guard !AppModel.demo, let req = MKReverseGeocodingRequest(location: l) else { return }
        Task {
            if let item = try? await req.mapItems.first {
                place.address = item.address?.shortAddress ?? item.name ?? "Current location"
            }
        }
    }
}
