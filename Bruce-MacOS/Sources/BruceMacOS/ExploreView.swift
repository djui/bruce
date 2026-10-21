import SwiftUI
import CoreLocation
import MapKit

struct ExploreView: View {
    @Environment(AppModel.self) var m
    @State private var tabIndex = 0
    @State private var dayOffset = 0
    @State private var fromHour: Double = 0
    @State private var toHour: Double = 24

    var selectedDay: Date {
        BruceDate.calendar.date(byAdding: .day, value: dayOffset, to: BruceDate.calendar.startOfDay(for: Date()))!
    }

    // MARK: Data

    var studios: [BruceAPI.Studio] {
        var s = m.cityStudios
        let cats = m.exploreCategories
        if !cats.isEmpty { s = s.filter { $0.studioCategories?.contains { cats.contains($0.categoryId ?? -1) } ?? false } }
        if m.favoritesOnly { s = s.filter { m.favorites.contains($0.id) } }
        // Studio access: tier_level 1/2/3 = Base/Black/Epic (inferred from captures).
        // Studio access chips are applied client-side: the app's own /studio/filter request carries no tier
        // filter (c5:38). A tier "has access" when the studio's visit_limit item for it is not -1 (c4).
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
        if m.selectedArea != nil { s = s.filter { m.studioInSelectedArea($0.id) } }
        return s.sorted { (distance($0) ?? .greatestFiniteMagnitude) < (distance($1) ?? .greatestFiniteMagnitude) }
    }

    var classes: [BruceAPI.BruceClass] {
        let key = BruceDate.calendar.startOfDay(for: selectedDay)
        var c = (m.classesByDay[key] ?? []).filter { $0.canceled != true }
        c = c.filter {
            guard let d = $0.start else { return true }
            let h = Double(BruceDate.calendar.component(.hour, from: d)) + Double(BruceDate.calendar.component(.minute, from: d)) / 60
            return h >= fromHour && h <= toHour
        }
        if dayOffset == 0 { c = c.filter { ($0.start ?? .distantFuture) > Date() } }
        let cats = m.exploreCategories
        if !cats.isEmpty { c = c.filter { $0.classCategories?.contains { cats.contains($0.categoryId ?? -1) } ?? false } }
        if m.favoritesOnly { c = c.filter { m.favorites.contains($0.studioId) } }
        if m.hideFull { c = c.filter { ($0.availableSpots ?? 1) > 0 } }
        if m.selectedArea != nil { c = c.filter { m.studioInSelectedArea($0.studioId) } }
        let f = m.classFilters
        if !f.isEmpty { c = c.filter { ClassFilters.passes($0, f) } }
        return ClassFilters.sorted(c, f, distance: m.studioDistance, travel: m.studioTravelMinutes)
    }

    func distance(_ s: BruceAPI.Studio) -> Double? {
        guard let a = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
              let lat = a.latitude, let lon = a.longitude else { return nil }
        return CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: m.refLat, longitude: m.refLon))
    }

    func mainCategory(_ s: BruceAPI.Studio) -> String? {
        let cats = (s.studioCategories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        return (cats.first { $0.main == true } ?? cats.first)?.category?.title
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Explore") {
                if tabIndex == 0 {
                    IconButton(system: m.exploreMap ? "list.bullet" : "map", size: 22) { m.exploreMap.toggle() }
                        .help(m.exploreMap ? "List" : "Map")
                }
                IconButton(system: "magnifyingglass", size: 22) { m.present(.search) }.help("Search")
            }
            UnderlineTabs(titles: ["Studios", "Classes"],
                          badges: [String(studios.count), m.classesLoadingDay != nil && tabIndex == 1 ? "…" : String(classes.count)],
                          selection: $tabIndex)
            chips.padding(.top, 14).padding(.bottom, 8)
            if tabIndex == 0 { if m.exploreMap { StudiosMap(studios: studios) } else { studioList } } else { classList }
        }
        .onAppear { if m.demoExploreTab != 0 { tabIndex = m.demoExploreTab; m.demoExploreTab = 0 } }
        .task(id: "\(tabIndex)-\(dayOffset)") { if tabIndex == 1 { await m.loadClasses(day: selectedDay) } }
    }

    var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { m.filterOpen = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .light)).padding(.trailing, 6)
                        .overlay(alignment: .topTrailing) {
                            if m.activeFilterCount > 0 { Circle().fill(Theme.lime).frame(width: 9, height: 9).offset(x: -2, y: -4) }
                        }
                }.buttonStyle(.plain)
                chip(selected: m.favoritesOnly) { Image(systemName: "heart.fill").font(.system(size: 18)) } action: { m.favoritesOnly.toggle() }
                ForEach(m.chipCategories) { c in
                    chip(selected: m.exploreCategories.contains(c.id)) { Text(c.title ?? "") } action: { m.toggleCategory(c.id) }
                }
                // "···" at the end of the row opens the filter panel (all categories and filters).
                chip(selected: false) { Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)) } action: { m.filterOpen = true }
                    .help("More filters")
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    static func chipView<L: View>(selected: Bool, @ViewBuilder label: () -> L, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label().font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(selected ? Theme.ink : Theme.chipGrey))
        }
        .buttonStyle(.plain)
    }

    func chip<L: View>(selected: Bool, @ViewBuilder label: () -> L, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label().font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(selected ? Theme.ink : Theme.chipGrey))
        }
        .buttonStyle(.plain)
    }

    var studioList: some View {
        ScrollView {
            LazyVStack(spacing: 30) {
                ForEach(studios) { s in
                    Button { m.push(.studio(s.id)) } label: {
                        ZStack {
                            RemotePhoto(fileId: s.photo)
                            Color.black.opacity(0.3)
                            VStack(spacing: 4) {
                                Text(s.name).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                                Text(([s.vicinity] + [distance(s).map { formatDistance(Int($0)) }]).compactMap { $0 }.joined(separator: " | "))
                                    .font(.system(size: 17))
                            }
                            .padding(.horizontal, 12)
                            VStack {
                                HStack {
                                    if let r = s.rating?.display { Label(r, systemImage: "star.fill").font(.system(size: 16)) }
                                    Spacer()
                                }
                                Spacer()
                                HStack { Text(mainCategory(s) ?? "").font(.system(size: 16)); Spacer() }
                            }
                            .padding(14)
                        }
                        .foregroundStyle(.white)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                if !studios.isEmpty && m.activeFilterCount > 0 { FilterActiveFooter() }
                if studios.isEmpty {
                    Text(m.studios.isEmpty ? "Loading studios…" : "No studios match.").foregroundStyle(Theme.secondary).padding(.top, 40)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
        }
    }

    var classList: some View {
        VStack(spacing: 0) {
            TimeRangeSlider(from: $fromHour, to: $toHour).padding(.horizontal, Theme.gutter).padding(.vertical, 6)
            dayTabs
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: SectionHeaderBar(text: BruceDate.dayHeader(selectedDay))) {
                        ForEach(classes) { c in
                            Button { m.push(.classDetail(c.id)) } label: {
                                let st = m.studio(c.studioId)
                                ClassRow(time: BruceDate.time(c.start),
                                         duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                         title: c.title, studio: st?.name ?? "",
                                         meta: [st?.vicinity, c.instructor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | "),
                                         badge: m.waitlistBadge(c.id), full: (c.availableSpots ?? 1) <= 0,
                                         wellness: m.isWellness(studioId: c.studioId), classId: c.id)
                            }
                            .buttonStyle(.plain)
                        }
                        if !classes.isEmpty && (m.activeFilterCount > 0 || fromHour > 0 || toHour < 24) { FilterActiveFooter() }
                        if classes.isEmpty {
                            Text(!m.isLoggedIn ? "Log in to see classes." : m.classesLoadingDay != nil ? "Loading classes…" : "No classes.")
                                .foregroundStyle(Theme.secondary).padding(.top, 40)
                        }
                    }
                }
            }
        }
    }

    var dayTabs: some View {
        HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                let d = BruceDate.calendar.date(byAdding: .day, value: i, to: Date())!
                Button { dayOffset = i } label: {
                    VStack(spacing: 8) {
                        Text(i == 0 ? "today" : BruceDate.format(d, "EEE").lowercased())
                            .font(.system(size: 17, weight: dayOffset == i ? .semibold : .medium))
                            .foregroundStyle(dayOffset == i ? Theme.ink : Theme.tertiary)
                        Rectangle().fill(dayOffset == i ? Theme.ink : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.top, 4)
    }
}

/// Two-thumb "00:00 —— 24:00" slider.
struct TimeRangeSlider: View {
    @Binding var from: Double
    @Binding var to: Double
    var body: some View {
        HStack(spacing: 12) {
            Text(label(from)).font(.system(size: 15, weight: .light)).frame(width: 46, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width - 20
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.ink).frame(height: 1.5).padding(.horizontal, 10)
                    thumb.offset(x: CGFloat(from / 24) * w)
                        .gesture(DragGesture().onChanged { v in from = min(to - 1, max(0, (v.location.x / w * 24).rounded())) })
                    thumb.offset(x: CGFloat(to / 24) * w)
                        .gesture(DragGesture().onChanged { v in to = max(from + 1, min(24, (v.location.x / w * 24).rounded())) })
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 24)
            Text(label(to)).font(.system(size: 15, weight: .light)).frame(width: 46, alignment: .trailing)
        }
    }
    var thumb: some View { Circle().fill(Theme.ink).frame(width: 20, height: 20) }
    func label(_ h: Double) -> String { String(format: "%02d:00", Int(h)) }
}


/// Explore map mode: black pins for every studio with coordinates, locate button.
struct StudiosMap: View {
    @Environment(AppModel.self) var m
    let studios: [BruceAPI.Studio]
    @State private var position: MapCameraPosition = .automatic

    struct Pin: Identifiable { let id: Int; let c: CLLocationCoordinate2D }
    var pins: [Pin] {
        studios.compactMap { s in
            guard let a = s.studioAddresses?.first(where: { $0.main == true })?.address ?? s.studioAddresses?.first?.address,
                  let lat = a.latitude, let lon = a.longitude else { return nil }
            return Pin(id: s.id, c: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
    var cityRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: m.refLat, longitude: m.refLon), latitudinalMeters: 9000, longitudinalMeters: 9000)
    }

    var body: some View {
        if !AppModel.remoteAssets { OfflineMap() } else {
        Map(position: $position) {
            ForEach(pins) { p in
                Annotation("", coordinate: p.c, anchor: .bottom) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 24))
                        .foregroundStyle(.black, .white)
                        .onTapGesture { m.push(.studio(p.id)) }
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))

        .overlay(alignment: .bottomTrailing) {
            Button { withAnimation { position = .region(cityRegion) } } label: {
                Circle().fill(Color(white: 0.94)).frame(width: 64, height: 64)
                    .overlay(Image(systemName: "location.fill").rotationEffect(.degrees(-90)).font(.system(size: 24)).foregroundStyle(Theme.ink))
                    .shadow(color: .black.opacity(0.15), radius: 4)
            }
            .buttonStyle(.plain).padding(Theme.gutter)
        }
        .onAppear { position = .region(cityRegion) }
        }
    }
}
