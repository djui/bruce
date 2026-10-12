import SwiftUI
import MapKit

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 14
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
        return CGSize(width: width, height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

struct PanelChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 13).frame(height: 42)
                .background(Capsule().fill(selected ? Theme.lime : Color(red: 0.92, green: 0.91, blue: 0.93)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter side panel

struct FilterPanel: View {
    @Environment(AppModel.self) var m
    @State private var showAllCategories = false
    @State private var pendingDelete: SavedArea?
    @State private var renaming: SavedArea?
    @State private var newName = ""

    var allCategories: [BruceAPI.Category] { m.sortedCategories }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                IconButton(system: "xmark", size: 20) { m.filterOpen = false }
                Text("Filter").font(.system(size: 20, weight: .bold))
                Spacer()
                if m.activeFilterCount > 0 {
                    Button("Clear") { m.clearFilters() }.buttonStyle(.plain).font(.system(size: 15)).underline()
                }
            }
            .padding(.horizontal, 22).frame(height: 76)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Studio access") {
                        FlowLayout {
                            ForEach(["Base", "Black", "Epic", "Wellness", "Free"], id: \.self) { t in
                                PanelChip(title: t, selected: m.accessTiers.contains(t)) {
                                    if m.accessTiers.contains(t) { m.accessTiers.remove(t) } else { m.accessTiers.insert(t) }
                                }
                            }
                        }
                    }
                    section("Display options") {
                        FlowLayout {
                            PanelChip(title: "Favorite studios", selected: m.favoritesOnly) { m.favoritesOnly.toggle() }
                            PanelChip(title: "Currently open", selected: m.currentlyOpen) { m.currentlyOpen.toggle() }
                            PanelChip(title: "Solo training only", selected: m.soloOnly) { m.soloOnly.toggle() }
                            PanelChip(title: "Hide full classes", selected: m.hideFull) { m.hideFull.toggle() }
                        }
                    }
                    section("Area", link: ("Change city", { m.present(.selectCity) })) {
                        FlowLayout {
                            PanelChip(title: "Entire \(m.cityName)", selected: m.selectedAreaId == nil) { m.selectedAreaId = nil }
                            // Saved areas (local, see Shared/BruceCore/Areas.swift); right-click → Show on map, Rename, Delete (confirmed).
                            ForEach(m.cityAreas) { a in
                                PanelChip(title: a.name, selected: m.selectedAreaId == a.id) { m.selectedAreaId = m.selectedAreaId == a.id ? nil : a.id }
                                    .contextMenu {
                                        Button("Show on map") { m.present(.area(a.id)) }
                                        Button("Rename…") { newName = a.name; renaming = a }
                                        Divider()
                                        Button("Delete area…", role: .destructive) { pendingDelete = a }
                                    }
                            }
                            PanelChip(title: "+", selected: false) { m.present(.newArea) }
                        }
                    }
                    section("Categories", link: (showAllCategories ? "Show less" : "Show all", { showAllCategories.toggle() })) {
                        FlowLayout {
                            ForEach(showAllCategories ? allCategories : Array(allCategories.prefix(9))) { c in
                                PanelChip(title: c.title ?? "", selected: m.exploreCategories.contains(c.id)) { m.toggleCategory(c.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { a in
            Button("Delete", role: .destructive) { Task { await m.deleteArea(a.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("The area is removed from your saved areas.") }
        .alert("Rename area", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { a in
            TextField("Name", text: $newName)
            Button("Save") { Task { await m.renameArea(a.id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    func section<C: View>(_ title: String, link: (String, () -> Void)? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                if let link { Button(action: link.1) { Text(link.0).underline().font(.system(size: 17, weight: .light)) }.buttonStyle(.plain) }
            }
            content()
        }
        .padding(.top, 20).padding(.bottom, 26)
    }
}

// MARK: - Search sheet (local filtering over loaded data)

struct SearchSheet: View {
    @Environment(AppModel.self) var m
    @State private var query = ""
    /// Server hits from GET /v52/search (c5:423); merged with local matches.
    @State private var remote: [BruceAPI.SearchHit] = []
    @FocusState private var focused: Bool

    var studioHits: [BruceAPI.Studio] {
        guard !query.isEmpty else { return [] }
        var local = m.cityStudios.filter { s in
            s.name.localizedCaseInsensitiveContains(query) || (s.vicinity ?? "").localizedCaseInsensitiveContains(query)
                || (s.studioCategories ?? []).contains { ($0.category?.title ?? "").localizedCaseInsensitiveContains(query) }
        }
        let ids = Set(local.map(\.id))
        for h in remote where h.type == "STUDIO" {
            if let id = h.fields?.id, !ids.contains(id), let st = m.studio(id) { local.append(st) }
        }
        return Array(local.prefix(30))
    }
    var classHits: [BruceAPI.BruceClass] {
        guard !query.isEmpty else { return [] }
        let catIds = Set(m.categories.filter { ($0.title ?? "").localizedCaseInsensitiveContains(query) }.map(\.id))
        return m.classesByDay.values.joined().filter { c in
            c.title.localizedCaseInsensitiveContains(query) || (c.instructor ?? "").localizedCaseInsensitiveContains(query)
                || m.studioName(c.studioId).localizedCaseInsensitiveContains(query)
                || (c.classCategories ?? []).contains { catIds.contains($0.categoryId ?? -1) }
        }
        .filter { ($0.start ?? .distantPast) > Date() }
        .sorted { $0.startTime < $1.startTime }.prefix(50).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("", text: $query, prompt: Text("Studios, classes, instructors, etc.").foregroundColor(Theme.tertiary))
                        .textFieldStyle(.plain).font(.system(size: 17, weight: .light)).focused($focused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.89)))
                Button("Cancel") { m.dismissSheets() }.buttonStyle(.plain).font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
            if query.isEmpty {
                EmptyState(system: "magnifyingglass", text: Copy.searchHint)
            } else if studioHits.isEmpty && classHits.isEmpty {
                EmptyState(system: "magnifyingglass", text: "No results for \u{201C}\(query)\u{201D}.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !studioHits.isEmpty {
                            SectionHeaderBar(text: "Studios")
                            ForEach(studioHits) { s in
                                Button { m.dismissSheets(); m.push(.studio(s.id)) } label: { InfoRow(title: s.name, subtitle: s.vicinity) }.buttonStyle(.plain)
                            }
                        }
                        if !classHits.isEmpty {
                            SectionHeaderBar(text: "Classes")
                            ForEach(classHits) { c in
                                Button { m.dismissSheets(); m.push(.classDetail(c.id)) } label: {
                                    ClassRow(time: BruceDate.time(c.start), duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                             title: c.title, studio: m.studioName(c.studioId),
                                             meta: [BruceDate.dayHeader(c.start), c.instructor].compactMap { $0 }.joined(separator: " | "), showMenu: false)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
        .task(id: query) {
            remote = []
            guard !AppModel.demo, m.isLoggedIn, query.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)   // debounce
            if let r = try? await BruceAPI.search(token: m.token, query: query, lat: m.refLat, lon: m.refLon, cityCode: m.city?.code ?? "STO") {
                remote = r
            }
        }
    }
}

// MARK: - Select city

struct SelectCitySheet: View {
    @Environment(AppModel.self) var m

    /// Fallback when /location/city was not loaded (logged out / demo); public city list from the captures.
    static let fallback: [(Int, String, String, String)] = [
        (2, "Göteborg", "Sweden", "SE"), (5, "Malmö", "Sweden", "SE"), (1, "Stockholm", "Sweden", "SE"),
        (8, "København", "Denmark", "DK"), (7, "Bergen", "Norway", "NO"), (6, "Oslo", "Norway", "NO"),
    ]

    var groups: [(country: String, code: String, cities: [(Int, String)])] {
        let rows: [(Int, String, String, String)] = m.cities.isEmpty ? Self.fallback
            : m.cities.map { ($0.id, $0.name, $0.country?.name ?? "", $0.country?.code ?? "") }
        let order = ["SE", "DK", "NO", "FI"]
        let byCountry = Dictionary(grouping: rows) { $0.3 }
        return byCountry.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }.map { code in
            let list = byCountry[code]!
            return (list.first!.2, code, list.map { ($0.0, $0.1) }.sorted { $0.1 < $1.1 })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Select city", leading: .close) { m.dismissSheets() }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.code) { i, g in
                        HStack(spacing: 10) {
                            Text(flag(g.code)).font(.system(size: 18))
                            Text(g.country).font(.system(size: 17, weight: .semibold))
                            Spacer()
                            if i == 0 { Image(systemName: "location").font(.system(size: 18, weight: .light)) }
                        }
                        .padding(.horizontal, Theme.gutter).frame(height: 62).background(Theme.sectionGrey)
                        ForEach(Array(g.cities.enumerated()), id: \.element.0) { j, c in
                            Button { m.selectCity(c.0) } label: {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(c.1).font(.system(size: 18, weight: .light))
                                        Spacer()
                                        if c.0 == m.cityId { Image(systemName: "checkmark").font(.system(size: 17, weight: .medium)) }
                                    }
                                    .padding(.trailing, Theme.gutter).frame(height: 76)
                                    if j < g.cities.count - 1 { Rectangle().fill(Theme.divider).frame(height: 0.5) }
                                }
                                .padding(.leading, Theme.gutter).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
}

// MARK: - New area (Save = visible region, Draw = freehand polygon with mouse drag)

struct NewAreaSheet: View {
    @Environment(AppModel.self) var m
    @State private var position: MapCameraPosition = .automatic
    @State private var visible: MKCoordinateRegion?
    @State private var drawing = false
    @State private var stroke: [CGPoint] = []
    @State private var polygon: [GeoPoint] = []
    @State private var naming = false
    @State private var name = ""

    var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: m.cityLat, longitude: m.cityLon) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "New area", leading: .close, action: { m.dismissSheets() }) {
                Button { name = m.nextAreaName; naming = true } label: {
                    Text("Save").underline().font(.system(size: 18, weight: .semibold))
                }.buttonStyle(.plain)
            }
            OnlineOnly {
                MapReader { proxy in
                    ZStack {
                        Map(position: $position, interactionModes: drawing ? [] : .all) {
                            UserAnnotation()
                            if polygon.count >= 3 {
                                MapPolygon(coordinates: polygon.map(\.coordinate))
                                    .foregroundStyle(Theme.lime.opacity(0.4)).stroke(Theme.lime, lineWidth: 2)
                            }
                        }
                        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                        .onMapCameraChange(frequency: .onEnd) { ctx in visible = ctx.region }
                        if drawing {
                            Color.white.opacity(0.001)
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { v in stroke.append(v.location) }
                                    .onEnded { _ in finish(proxy) })
                            Path { p in
                                guard let f = stroke.first else { return }
                                p.move(to: f); for q in stroke.dropFirst() { p.addLine(to: q) }
                            }
                            .stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                Text(drawing ? "Drag with the mouse to draw the outline of your area." :
                        Copy.areaHint)
                    .font(.system(size: 16)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 22).padding(.vertical, 14).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.25).opacity(0.95)))
                    .padding(.horizontal, Theme.gutter).padding(.top, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 10) {
                    if !polygon.isEmpty {
                        Button { polygon = [] } label: {
                            Text("Clear").font(.system(size: 16)).foregroundStyle(.black)
                                .frame(width: 84, height: 50).background(Capsule().fill(Color.white))
                        }.buttonStyle(.plain)
                    }
                    Button { stroke = []; drawing.toggle() } label: {
                        Text(drawing ? "Cancel" : "Draw").font(.system(size: 18)).foregroundStyle(.black)
                            .frame(width: 84, height: 60).background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.gutter)
            }
            .onAppear { position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 6000, longitudinalMeters: 6000)) }
        }
        .alert("Name this area", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Save") { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(polygon.count >= 3 ? "Your drawn area is saved." : "The visible map area is saved.") }
    }

    func finish(_ proxy: MapProxy) {
        let coords = stroke.compactMap { proxy.convert($0, from: .local) }.map(GeoPoint.init)
        stroke = []; drawing = false
        guard coords.count >= 3 else { return }
        polygon = PolygonMath.simplify(coords, maxPoints: 50)
    }

    func save() async {
        var pts = polygon
        if pts.count < 3 {
            let r = visible ?? MKCoordinateRegion(center: center, latitudinalMeters: 6000, longitudinalMeters: 6000)
            pts = PolygonMath.rectangle(centerLat: r.center.latitude, centerLon: r.center.longitude,
                                        latDelta: r.span.latitudeDelta, lonDelta: r.span.longitudeDelta)
        }
        let n = name.trimmingCharacters(in: .whitespaces)
        if await m.saveArea(name: n.isEmpty ? m.nextAreaName : n, points: pts) != nil { m.dismissSheets() }
    }
}

// MARK: - Popular categories grid

struct CategoriesGridView: View {
    @Environment(AppModel.self) var m

    var items: [(Int, String, String?)] {
        let home = m.home.first { $0.type == "CATEGORIES" }?.items.compactMap { i in i.categoryId.map { ($0, i.title ?? "", i.photo) } } ?? []
        let seen = Set(home.map(\.0))
        let rest = m.categories.filter { !seen.contains($0.id) && $0.photo != nil }.map { ($0.id, $0.title ?? "", $0.photo) }
        return home + rest
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Popular categories") { m.pop() }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                    ForEach(items, id: \.0) { c in
                        Button { m.push(.category(c.0)) } label: {
                            ZStack {
                                RemotePhoto(fileId: c.2, w: 240, h: 240)
                                Color.black.opacity(0.3)
                                Text(c.1).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 22)
            }
        }
    }
}
