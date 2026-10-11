import SwiftUI
import MapKit

// MARK: - Similar classes

/// "Similar classes" sheet for a fully booked class: nearby classes around the same time, as horizontally
/// scrolling cards (GET /v52/studio/class/alternative_recommendation).
struct SimilarClassesSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int

    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }
    var cards: [BruceAPI.ClassCard]? { m.similarClasses[classId] }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Similar classes", leading: .close, action: { m.dismissSheets() }) { EmptyView() }
            VStack(spacing: 4) {
                Text("Similar classes to").font(.system(size: 17, weight: .light))
                Text([c?.title, c.map { BruceDate.time($0.start) }].compactMap { $0 }.joined(separator: ", "))
                    .font(.system(size: 18, weight: .bold))
                if let sid = c?.studioId {
                    Text("nearby \(m.studioName(sid))").font(.system(size: 17, weight: .light)).foregroundStyle(Theme.secondary)
                }
            }
            .multilineTextAlignment(.center).padding(.horizontal, Theme.gutter).padding(.vertical, 18)
            if let cards {
                if cards.isEmpty {
                    EmptyState(system: "calendar.badge.exclamationmark", text: "No similar classes nearby.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cards) { card in
                                Button { m.dismissSheets(); m.push(.classDetail(card.id)) } label: { cardView(card) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                    Spacer()
                }
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .task { await m.loadSimilarClasses(classId) }
    }

    func cardView(_ card: BruceAPI.ClassCard) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemotePhoto(fileId: card.photo, w: 300, h: 220)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(BruceDate.time(card.start)) - \(BruceDate.time(card.end))").font(.system(size: 16, weight: .semibold)).monospacedDigit()
                Text(card.title ?? "Class").font(.system(size: 22, weight: .bold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(card.studio?.name ?? "").lineLimit(1)
                    if let d = card.distance, d > 0 { Text("· \(formatDistance(d))").layoutPriority(1) }
                }
                .font(.system(size: 14, weight: .light))
            }
            .foregroundStyle(.white).padding(16)
        }
        .frame(width: 300, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Show / rename a saved area

/// A saved custom area on the map (right-click an area chip → Show on map), with Rename and "Filter by this area".
struct AreaMapSheet: View {
    @Environment(AppModel.self) var m
    let areaId: UUID
    @State private var position: MapCameraPosition = .automatic
    @State private var renaming = false
    @State private var name = ""

    var area: SavedArea? { m.area(areaId) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: area?.name ?? "Area", leading: .close, action: { m.dismissSheets() }) {
                if area != nil {
                    Button { name = area?.name ?? ""; renaming = true } label: {
                        Text("Rename").underline().font(.system(size: 18, weight: .semibold))
                    }.buttonStyle(.plain)
                }
            }
            if let a = area {
                Map(position: $position) {
                    UserAnnotation()
                    MapPolygon(coordinates: a.points.map(\.coordinate))
                        .foregroundStyle(Theme.lime.opacity(0.4)).stroke(Theme.lime, lineWidth: 2)
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .overlay(alignment: .bottom) { footer(a) }
                .onAppear { fit(a) }
            } else {
                EmptyState(system: "skew", text: "This area no longer exists.")
            }
        }
        .alert("Rename area", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") { Task { await m.renameArea(areaId, to: name) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    func footer(_ a: SavedArea) -> some View {
        let count = m.studios(in: a).count
        let selected = m.selectedAreaId == a.id
        return VStack(spacing: 12) {
            Text(m.studios.isEmpty ? "Studios are still loading" : "\(count) studio\(count == 1 ? "" : "s") in this area")
                .font(.system(size: 16))
            LimeButton(title: selected ? "Filtering by this area" : "Filter by this area") {
                m.selectedAreaId = selected ? nil : a.id
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .padding(Theme.gutter)
    }

    func fit(_ a: SavedArea) {
        guard let b = PolygonMath.bounds(a.points) else { return }
        // Shifted south a little so the area sits above the footer card.
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: b.centerLat - b.latDelta * 0.2, longitude: b.centerLon),
                                              span: MKCoordinateSpan(latitudeDelta: b.latDelta * 1.4, longitudeDelta: b.lonDelta)))
    }
}
