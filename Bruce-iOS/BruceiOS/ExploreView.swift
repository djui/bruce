import SwiftUI
import CoreLocation
import MapKit

extension AppModel {
    /// Precomputed in AppModel (user location, else city centre).
    func distance(_ s: BruceAPI.Studio) -> Double? { studioDistances[s.id] }
    func mainCategory(_ s: BruceAPI.Studio) -> String? {
        let cats = (s.studioCategories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        return (cats.first { $0.main == true } ?? cats.first)?.category?.title
    }
    func isOpenNow(_ id: Int) -> Bool {
        let now = Date()
        return (schedules[id] ?? []).contains { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }
    }
}

struct ExploreView: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var ui: UIState
    @State private var tabIndex = 0
    @State private var dayOffset = 0
    @State private var fromHour: Double = 0
    @State private var toHour: Double = 24
    @Namespace private var glass

    var selectedDay: Date {
        BruceDate.calendar.date(byAdding: .day, value: dayOffset, to: BruceDate.calendar.startOfDay(for: Date()))!
    }

    // MARK: Data (same filtering as the macOS Explore view)

    var studios: [BruceAPI.Studio] {
        var s = m.cityStudios
        let cats = m.exploreCategories
        if !cats.isEmpty { s = s.filter { $0.studioCategories?.contains { cats.contains($0.categoryId ?? -1) } ?? false } }
        if m.favoritesOnly { s = s.filter { m.favorites.contains($0.id) } }
        if !m.accessTiers.isEmpty {
            s = s.filter { st in
                m.accessTiers.contains { t in
                    switch t {
                    case "Wellness": return st.label?.uppercased() == "WELLNESS"
                    case "Free": return st.visitLimit?.items?.contains { $0.label == "FREE" && ($0.limit ?? -1) != -1 } ?? false
                    default:
                        guard let l = st.visitLimit?.items?.first(where: { $0.label?.uppercased() == t.uppercased() })?.limit else { return false }
                        return l != -1
                    }
                }
            }
        }
        if m.soloOnly { s = s.filter { $0.hasOpenings == true } }
        if m.currentlyOpen { s = s.filter { m.schedules[$0.id] == nil || m.isOpenNow($0.id) } }
        if m.selectedArea != nil { s = s.filter { m.studioInSelectedArea($0.id) } }
        return s.sorted { (m.distance($0) ?? .greatestFiniteMagnitude) < (m.distance($1) ?? .greatestFiniteMagnitude) }
    }

    var classes: [BruceAPI.BruceClass] {
        let key = BruceDate.calendar.startOfDay(for: selectedDay)
        var c = (m.classesByDay[key] ?? []).filter { $0.canceled != true }
        c = c.filter {
            guard let d = $0.start else { return true }
            let h = Double(BruceDate.calendar.component(.hour, from: d)) + Double(BruceDate.calendar.component(.minute, from: d)) / 60
            return h >= fromHour && h <= toHour
        }
        let cats = m.exploreCategories
        if !cats.isEmpty { c = c.filter { $0.classCategories?.contains { cats.contains($0.categoryId ?? -1) } ?? false } }
        if m.favoritesOnly { c = c.filter { m.favorites.contains($0.studioId) } }
        if m.hideFull { c = c.filter { ($0.availableSpots ?? 1) > 0 } }
        if m.selectedArea != nil { c = c.filter { m.studioInSelectedArea($0.studioId) } }
        return c
    }

    /// What the list shows: for today only classes that haven't started yet (the badge counts the whole day).
    var upcomingClasses: [BruceAPI.BruceClass] {
        dayOffset == 0 ? classes.filter { ($0.start ?? .distantFuture) > Date() } : classes
    }

    // MARK: Body

    var body: some View {
        Group {
            if tabIndex == 0 && m.exploreMap {
                StudiosMap(studios: studios).ignoresSafeArea(edges: .bottom)
            } else {
                ScrollView {
                    if tabIndex == 0 { studioList } else { classList }
                }
                // Header bar below: content scrolling under it is blurred/dimmed (hard edge), never shows through sharply.
                .scrollEdgeEffectStyle(.hard, for: .top)
                .refreshable {
                    if tabIndex == 1 { m.classesByDay[BruceDate.calendar.startOfDay(for: selectedDay)] = nil; await m.loadClasses(day: selectedDay) }
                    else { await m.loadStudios(force: true) }
                }
            }
        }
        // Pinned header: underline tabs with counts + chip row (+ time range and day picker for classes).
        .safeAreaBar(edge: .top) { controls.padding(.bottom, 8) }
        .bruceTitle("Explore")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if tabIndex == 0 {
                    Button { withAnimation { m.exploreMap.toggle() } } label: {
                        Image(systemName: m.exploreMap ? "list.bullet" : "map")
                    }
                }
            }
        }
        // Results cover the page only while searching with a non-empty query; the page underneath (tab, filters,
        // scroll position, map/list) stays mounted, so cancelling returns to exactly where the search started.
        .overlay { ExploreSearchOverlay() }
        .sheet(isPresented: Binding(get: { m.filterOpen }, set: { m.filterOpen = $0 })) { FilterSheet() }
        .onAppear { if m.demoExploreTab != 0 { tabIndex = m.demoExploreTab; m.demoExploreTab = 0 } }
        .task(id: "\(tabIndex)-\(dayOffset)") {
            // Load the selected day even on the Studios tab so the Classes count badge is real, not stale.
            await m.loadClasses(day: selectedDay)
            guard tabIndex == 1 else { return }
            // Prefetch the neighbouring day once the visible one is in.
            await m.loadClasses(day: BruceDate.calendar.date(byAdding: .day, value: 1, to: selectedDay)!)
        }
    }

    var controls: some View {
        VStack(spacing: 10) {
            UnderlineTabs(titles: ["Studios", "Classes"],
                          badges: [m.studios.isEmpty ? "…" : String(studios.count),
                                   m.classesByDay[BruceDate.calendar.startOfDay(for: selectedDay)] == nil ? "…" : String(classes.count)],
                          selection: $tabIndex)
            chips
            if tabIndex == 1 {
                // Original order: time range directly under the chips, then the day tabs.
                TimeRangeSlider(from: $fromHour, to: $toHour).padding(.horizontal, Theme.gutter + 4)
                dayTabs
            }
        }
        .padding(.top, 4)
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    // Filter first, left of the heart chip (as in the original).
                    GlassChip(selected: m.activeFilterCount > 0, action: { m.filterOpen = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                            if m.activeFilterCount > 0 { Text("\(m.activeFilterCount)").monospacedDigit() }
                        }
                    }
                    .accessibilityLabel("Filter")
                    GlassChip(selected: m.favoritesOnly, action: { withAnimation { m.favoritesOnly.toggle() } }) {
                        Image(systemName: m.favoritesOnly ? "heart.fill" : "heart")
                    }
                    ForEach(m.chipCategories) { c in
                        GlassChip(c.title ?? "", selected: m.exploreCategories.contains(c.id)) { withAnimation { m.toggleCategory(c.id) } }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    var dayTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        let d = BruceDate.calendar.date(byAdding: .day, value: i, to: Date())!
                        Button { withAnimation(.spring(duration: 0.3)) { dayOffset = i } } label: {
                            VStack(spacing: 1) {
                                Text(i == 0 ? "today" : BruceDate.format(d, "EEE").lowercased()).font(.system(size: 12, weight: .semibold))
                                Text(BruceDate.format(d, "d")).font(.system(size: 17, weight: .bold))
                            }
                            .foregroundStyle(dayOffset == i ? Color.black : Theme.ink)
                            .frame(width: 50, height: 50)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(dayOffset == i ? .regular.tint(Theme.lime).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    var studioList: some View {
        LazyVStack(spacing: 18) {
            ForEach(studios) { s in
                NavigationLink(value: Route.studio(s.id)) {
                    StudioCard(studio: s, distance: m.distance(s), category: m.mainCategory(s), isFavorite: m.favorites.contains(s.id)).equatable()
                }
                    .buttonStyle(.plain)
            }
            if m.studios.isEmpty {
                ProgressView("Loading studios…").frame(maxWidth: .infinity, minHeight: 300)
            } else if studios.isEmpty {
                EmptyState(system: "building.2", text: "No studios match these filters.")
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
    }

    var classList: some View {
        LazyVStack(spacing: 0) {
            SectionHeaderBar(text: BruceDate.dayHeader(selectedDay))
            ForEach(upcomingClasses) { c in
                NavigationLink(value: Route.classDetail(c.id)) {
                    ClassRow(c: c, badge: m.standby(forClass: c.id) != nil ? "Waitlist" : nil)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 86)
            }
            if classes.count > upcomingClasses.count {
                Text("\(classes.count - upcomingClasses.count) earlier classes today are not shown")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.vertical, 16)
            }
            if upcomingClasses.isEmpty && classes.isEmpty {
                if m.classesLoadingDay != nil || m.classesByDay[BruceDate.calendar.startOfDay(for: selectedDay)] == nil {
                    ProgressView("Loading classes…").frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    EmptyState(system: "calendar", text: "No classes match.")
                }
            }
        }
    }
}

/// Search results over the Explore page while the bottom search accessory is active with a non-empty query.
/// The page underneath stays mounted (tab, filters, scroll position, map/list), so cancelling restores it.
struct ExploreSearchOverlay: View {
    @EnvironmentObject var ui: UIState
    var body: some View {
        if ui.searchActive && !ui.query.isEmpty {
            SearchResults(query: $ui.query).background(Theme.background)
        }
    }
}

/// Big photo card. Value-only inputs + Equatable, so streaming updates and scrolling skip unchanged cards.
/// Capsules use a thin material (not a glass layer per card: glass in long lists is expensive).
struct StudioCard: View, Equatable {
    let studio: BruceAPI.Studio
    var distance: Double? = nil
    var category: String? = nil
    var isFavorite = false
    var height: CGFloat = 210

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePhoto(fileId: studio.photo, symbol: symbol)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(studio.name).font(.system(size: 24, weight: .heavy).width(.expanded)).lineLimit(2)
                Text(([studio.vicinity] + [distance.map { formatDistance(Int($0)) }]).compactMap { $0 }.joined(separator: " | "))
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(.white).padding(16)
            HStack(spacing: 8) {
                if let r = studio.rating?.display {
                    Label(r, systemImage: "star.fill").font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(.thinMaterial, in: Capsule())
                }
                Spacer()
                if let category {
                    Text(category).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(.thinMaterial, in: Capsule())
                }
                if isFavorite {
                    Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        .frame(width: 30, height: 30).background(.thinMaterial, in: Circle())
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    var symbol: String {
        switch (category ?? "").lowercased() {
        case "yoga", "pilates": return "figure.yoga"
        case "spa", "sauna": return "drop"
        case "swimming": return "figure.pool.swim"
        case "climbing": return "figure.climbing"
        default: return "dumbbell"
        }
    }
}

/// Two-thumb "00:00 —— 24:00" hour range.
struct TimeRangeSlider: View {
    @Binding var from: Double
    @Binding var to: Double
    var body: some View {
        HStack(spacing: 12) {
            Text(label(from)).font(.system(size: 14, weight: .semibold)).monospacedDigit().frame(width: 46, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width - 24
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chipGrey).frame(height: 4).padding(.horizontal, 12)
                    Capsule().fill(Theme.lime).frame(width: CGFloat((to - from) / 24) * w, height: 4).offset(x: 12 + CGFloat(from / 24) * w)
                    thumb.offset(x: CGFloat(from / 24) * w)
                        .gesture(DragGesture().onChanged { v in from = min(to - 1, max(0, (v.location.x / w * 24).rounded())) })
                    thumb.offset(x: CGFloat(to / 24) * w)
                        .gesture(DragGesture().onChanged { v in to = max(from + 1, min(24, (v.location.x / w * 24).rounded())) })
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 28)
            Text(label(to)).font(.system(size: 14, weight: .semibold)).monospacedDigit().frame(width: 46, alignment: .trailing)
        }
    }
    var thumb: some View { Circle().fill(.white).frame(width: 24, height: 24).glassEffect(.regular.interactive(), in: .circle).shadow(color: .black.opacity(0.15), radius: 3) }
    func label(_ h: Double) -> String { String(format: "%02d:00", Int(h)) }
}

/// Explore map: pins for every studio with coordinates; glass recentre button.
struct StudiosMap: View {
    @Environment(AppModel.self) var m
    @Environment(\.pushRoute) var pushRoute
    let studios: [BruceAPI.Studio]
    @State private var position: MapCameraPosition = .automatic

    struct Pin: Identifiable { let id: Int; let name: String; let c: CLLocationCoordinate2D }
    var pins: [Pin] {
        studios.compactMap { s in
            guard let a = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
                  let lat = a.latitude, let lon = a.longitude else { return nil }
            return Pin(id: s.id, name: s.name, c: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
    var cityRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: m.refLat, longitude: m.refLon), latitudinalMeters: 9000, longitudinalMeters: 9000)
    }

    var body: some View {
        if !AppModel.remoteAssets {
            OfflineMap()
        } else {
            Map(position: $position) {
                ForEach(pins) { p in
                    Annotation(p.name, coordinate: p.c, anchor: .bottom) {
                        Button { (pushRoute ?? m.push)(.studio(p.id)) } label: {
                            Image(systemName: "dumbbell.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 32, height: 32).background(Circle().fill(Theme.lime))
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .bottomTrailing) {
                Button { withAnimation { position = .region(cityRegion) } } label: {
                    Image(systemName: "location.fill").font(.system(size: 20)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .padding(Theme.gutter).padding(.bottom, 90)
            }
            .onAppear { position = .region(cityRegion) }
        }
    }
}

// MARK: - Filter

struct FilterSheet: View {
    @Environment(AppModel.self) var m
    @State private var showAllCategories = false
    @State private var detent: PresentationDetent =
        AppModel.demo && ["areas", "deletearea"].contains(AppModel.setting("BRUCE_SCREEN") ?? "") ? .large : .medium

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Studio access") {
                        ForEach(["Base", "Black", "Epic", "Wellness", "Free"], id: \.self) { t in
                            GlassChip(t, selected: m.accessTiers.contains(t)) {
                                if m.accessTiers.contains(t) { m.accessTiers.remove(t) } else { m.accessTiers.insert(t) }
                            }
                        }
                    }
                    section("Display options") {
                        GlassChip("Favorite studios", selected: m.favoritesOnly) { m.favoritesOnly.toggle() }
                        GlassChip("Currently open", selected: m.currentlyOpen) { m.currentlyOpen.toggle() }
                        GlassChip("Solo training only", selected: m.soloOnly) { m.soloOnly.toggle() }
                        GlassChip("Hide full classes", selected: m.hideFull) { m.hideFull.toggle() }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Area").font(.system(size: 18, weight: .bold))
                            Spacer()
                            NavigationLink("Change city") { SelectCitySheet() }.font(.system(size: 15, weight: .semibold))
                        }
                        AreaChips()
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Categories").font(.system(size: 18, weight: .bold))
                            Spacer()
                            Button(showAllCategories ? "Show less" : "Show all") { withAnimation { showAllCategories.toggle() } }
                                .font(.system(size: 15, weight: .semibold))
                        }
                        GlassEffectContainer(spacing: 8) {
                            FlowLayout {
                                ForEach(showAllCategories ? m.sortedCategories : Array(m.sortedCategories.prefix(9))) { c in
                                    GlassChip(c.title ?? "", selected: m.exploreCategories.contains(c.id)) { m.toggleCategory(c.id) }
                                }
                            }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .navigationTitle("Filter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(role: .close) { m.filterOpen = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { withAnimation { m.clearFilters() } }.disabled(m.activeFilterCount == 0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                LimeButton(title: "Show results") { m.filterOpen = false }.padding(.horizontal, Theme.gutter).padding(.vertical, 8)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 18, weight: .bold))
            GlassEffectContainer(spacing: 8) { FlowLayout { content() } }
        }
    }
}

/// Simple wrapping layout for chips (copied from Bruce-MacOS/ExploreExtras.swift).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10
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

// MARK: - Search (local filtering + GET /v52/search when logged in)

struct SearchResults: View {
    @Environment(AppModel.self) var m
    @Binding var query: String
    @State private var remote: [BruceAPI.SearchHit] = []

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
        ScrollView {
            if query.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("POPULAR").font(Theme.heading(16)).foregroundStyle(Theme.secondary)
                    GlassEffectContainer(spacing: 8) {
                        FlowLayout {
                            ForEach(m.chipCategories.prefix(12)) { c in
                                GlassChip(c.title ?? "", selected: false) { query = c.title ?? "" }
                            }
                        }
                    }
                }
                .padding(Theme.gutter)
            } else if studioHits.isEmpty && classHits.isEmpty {
                EmptyState(system: "magnifyingglass", text: "No results for \u{201C}\(query)\u{201D}.")
            } else {
                LazyVStack(spacing: 0) {
                    if !studioHits.isEmpty {
                        SectionHeaderBar(text: "Studios")
                        ForEach(studioHits) { s in
                            NavigationLink(value: Route.studio(s.id)) {
                                HStack(spacing: 14) {
                                    RemotePhoto(fileId: s.photo, w: 120, h: 120).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                                    InfoRow(title: s.name, subtitle: [s.vicinity, m.mainCategory(s)].compactMap { $0 }.joined(separator: " | "))
                                }
                                .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !classHits.isEmpty {
                        SectionHeaderBar(text: "Classes")
                        ForEach(classHits) { c in
                            NavigationLink(value: Route.classDetail(c.id)) {
                                ClassRow(c: c, meta: [BruceDate.dayHeader(c.start), c.instructor].compactMap { $0 }.joined(separator: " | "), showMenu: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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
        List {
            ForEach(groups, id: \.code) { g in
                Section("\(flag(g.code))  \(g.country)") {
                    ForEach(g.cities, id: \.0) { c in
                        Button { m.selectCity(c.0) } label: {
                            HStack {
                                Text(c.1).foregroundStyle(Theme.ink)
                                Spacer()
                                if c.0 == m.cityId { Image(systemName: "checkmark").fontWeight(.semibold) }
                            }
                        }
                    }
                }
            }
        }
        .sheetChrome("Select city")
    }

    func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
}

// MARK: - Areas

/// "Entire <city>" + saved areas (long-press → delete confirmation) + "New area".
struct AreaChips: View {
    @Environment(AppModel.self) var m
    @State private var pendingDelete: SavedArea?
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            FlowLayout {
                GlassChip("Entire \(m.cityName)", selected: m.selectedAreaId == nil) { m.selectedAreaId = nil }
                ForEach(m.cityAreas) { a in
                    GlassChip(selected: m.selectedAreaId == a.id, action: { m.selectedAreaId = m.selectedAreaId == a.id ? nil : a.id }) {
                        Label(a.name, systemImage: "skew")
                    }
                    // Like the original app: long-press goes straight to the delete confirmation.
                    .contentShape(.capsule)
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        pendingDelete = a
                    })
                }
                NavigationLink { NewAreaSheet() } label: {
                    Label("New area", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .alert("Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { a in
            Button("Delete", role: .destructive) { Task { await m.deleteArea(a.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("The area is removed from your saved areas.") }
        .onAppear {
            if AppModel.demo, AppModel.setting("BRUCE_SCREEN") == "deletearea", let a = m.cityAreas.first { pendingDelete = a }
        }
    }
}

/// New area: Save without drawing stores the visible map rectangle; Draw captures a freehand polygon
/// (simplified with Douglas–Peucker to ≤ 50 points) shown as a lime translucent overlay, then Save stores it.
struct NewAreaSheet: View {
    @Environment(AppModel.self) var m
    @Environment(\.dismiss) var dismiss
    @Environment(\.sheetIsRoot) var isRoot
    @State private var position: MapCameraPosition = .automatic
    @State private var visible: MKCoordinateRegion?
    @State private var drawing = false
    @State private var stroke: [CGPoint] = []
    @State private var polygon: [GeoPoint] = []
    @State private var naming = false
    @State private var name = ""

    var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: m.cityLat, longitude: m.cityLon) }

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $position, interactionModes: drawing ? [] : .all) {
                    UserAnnotation()
                    if polygon.count >= 3 {
                        MapPolygon(coordinates: polygon.map(\.coordinate))
                            .foregroundStyle(Theme.lime.opacity(0.35)).stroke(Theme.lime, lineWidth: 3)
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { ctx in visible = ctx.region }
                if drawing {
                    // Finger path capture layer (map gestures are disabled while drawing).
                    Color.white.opacity(0.001)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in stroke.append(v.location) }
                            .onEnded { _ in finishStroke(proxy) })
                    Path { p in
                        guard let f = stroke.first else { return }
                        p.move(to: f); for q in stroke.dropFirst() { p.addLine(to: q) }
                    }
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            Text(drawing ? "Draw the outline of your area with one finger." :
                    Copy.areaHint)
                .font(.system(size: 15, weight: .medium)).multilineTextAlignment(.center).foregroundStyle(.white)
                .padding(14).frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
                .padding(Theme.gutter)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                if !polygon.isEmpty {
                    Button { polygon = []; stroke = [] } label: { Label("Clear", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.glass).controlSize(.large)
                }
                Button { stroke = []; drawing.toggle() } label: {
                    Label(drawing ? "Cancel" : "Draw", systemImage: drawing ? "xmark" : "pencil.tip")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                }
                .buttonStyle(.glassProminent).tint(Theme.lime).controlSize(.large)
            }
            .padding(Theme.gutter).padding(.bottom, 24)
        }
        .navigationTitle("New area").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot { ToolbarItem(placement: .topBarLeading) { CloseButton() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { name = m.nextAreaName; naming = true }.fontWeight(.semibold)
            }
        }
        .alert("Name this area", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Save") { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(polygon.count >= 3 ? "Your drawn area is saved." : "The visible map area is saved.") }
        .onAppear {
            position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 6000, longitudinalMeters: 6000))
            if AppModel.demo, AppModel.setting("BRUCE_SCREEN") == "drawarea" { polygon = AppModel.demoAreas[0].points }
        }
    }

    func finishStroke(_ proxy: MapProxy) {
        let coords = stroke.compactMap { proxy.convert($0, from: .local) }.map(GeoPoint.init)
        stroke = []
        drawing = false
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
        if await m.saveArea(name: n.isEmpty ? m.nextAreaName : n, points: pts) != nil { isRoot ? m.dismissSheets() : dismiss() }
    }
}

// MARK: - Categories

struct CategoriesGridView: View {
    @Environment(AppModel.self) var m

    var items: [(Int, String, String?)] {
        let home = m.home.first { $0.type == "CATEGORIES" }?.items.compactMap { i in i.categoryId.map { ($0, i.title ?? "", i.photo) } } ?? []
        let seen = Set(home.map(\.0))
        let rest = m.categories.filter { !seen.contains($0.id) && $0.photo != nil }.map { ($0.id, $0.title ?? "", $0.photo) }
        return home + rest
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(items, id: \.0) { c in
                    NavigationLink(value: Route.category(c.0)) {
                        ZStack(alignment: .bottomLeading) {
                            RemotePhoto(fileId: c.2, w: 240, h: 240, symbol: "figure.mind.and.body")
                            Text(c.1).font(.system(size: 16, weight: .bold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 7).glassEffect(.regular, in: .capsule).padding(10)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.gutter)
        }
        .navigationTitle("Popular categories").navigationBarTitleDisplayMode(.inline)
    }
}

struct CategoryView: View {
    @Environment(AppModel.self) var m
    let categoryId: Int
    @State private var tab = 0

    var title: String { m.categories.first { $0.id == categoryId }?.title ?? "Category" }
    var studios: [BruceAPI.Studio] {
        m.cityStudios.filter { $0.studioCategories?.contains { $0.categoryId == categoryId } ?? false }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var classes: [BruceAPI.BruceClass] {
        m.classesByDay.values.joined()
            .filter { $0.canceled != true && ($0.start ?? .distantPast) > Date() }
            .filter { $0.classCategories?.contains { $0.categoryId == categoryId } ?? false }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tab == 0 {
                    LazyVStack(spacing: 16) {
                        ForEach(studios) { s in
                            NavigationLink(value: Route.studio(s.id)) { StudioCard(studio: s, category: title, isFavorite: m.favorites.contains(s.id), height: 190).equatable() }.buttonStyle(.plain)
                        }
                        if studios.isEmpty { EmptyState(system: "building.2", text: "No studios.") }
                    }
                    .padding(Theme.gutter)
                } else {
                    ForEach(groupedByDay(classes, date: \.start), id: \.0) { day, list in
                        SectionHeaderBar(text: BruceDate.dayHeader(day))
                        ForEach(list) { c in
                            NavigationLink(value: Route.classDetail(c.id)) {
                                ClassRow(c: c, badge: m.standby(forClass: c.id) != nil ? "Waitlist" : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if classes.isEmpty { EmptyState(system: "calendar", text: m.classesLoadingDay != nil ? "Loading classes…" : "No upcoming classes.") }
                }
            }
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .safeAreaBar(edge: .top) {
            UnderlineTabs(titles: ["Studios", "Classes"], badges: [String(studios.count), String(classes.count)], selection: $tab)
                .padding(.vertical, 8)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .onAppear { if m.demoCategoryTab != 0 { tab = m.demoCategoryTab; m.demoCategoryTab = 0 } }
        .task {
            let cal = BruceDate.calendar
            await m.loadClassDays((0..<7).map { cal.date(byAdding: .day, value: $0, to: Date())! })
        }
    }
}
