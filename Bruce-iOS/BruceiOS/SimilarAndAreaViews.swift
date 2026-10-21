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
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Similar classes to").bruceFont(16).foregroundStyle(Theme.secondary)
                    Text([c?.title, c.map { BruceDate.time($0.start) }].compactMap { $0 }.joined(separator: ", "))
                        .bruceFont(18, weight: .bold)
                    if let sid = c?.studioId {
                        Text("nearby \(m.studioName(sid))").bruceFont(16).foregroundStyle(Theme.secondary)
                    }
                }
                .multilineTextAlignment(.center).padding(.horizontal, Theme.gutter)
                if let cards {
                    if cards.isEmpty {
                        EmptyState(system: "calendar.badge.exclamationmark", text: "No similar classes nearby.")
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(cards) { card in
                                    Button { open(card) } label: { SimilarClassCard(card: card) }.buttonStyle(.plain)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, Theme.gutter)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.hidden)
                    }
                } else {
                    ProgressView().frame(height: 220)
                }
            }
            .padding(.top, 8).padding(.bottom, 24)
        }
        .sheetChrome("Similar classes")
        .task { await m.loadSimilarClasses(classId) }
    }

    func open(_ card: BruceAPI.ClassCard) {
        m.dismissSheets()
        m.push(.classDetail(card.id))
    }
}

struct SimilarClassCard: View {
    let card: BruceAPI.ClassCard
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePhoto(fileId: card.photo, w: 300, h: 220, symbol: "figure.strengthtraining.traditional")
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(BruceDate.time(card.start)) - \(BruceDate.time(card.end))").bruceFont(16, weight: .semibold).monospacedDigit()
                Text(card.title ?? "Class").bruceFont(22, weight: .heavy).lineLimit(2)
                HStack(spacing: 6) {
                    Text(card.studio?.name ?? "").lineLimit(1)
                    if let d = card.distance, d > 0 { Text("· \(formatDistance(d))").layoutPriority(1) }
                }
                .bruceFont(14, weight: .medium)
            }
            .foregroundStyle(.white).padding(16)
        }
        .frame(width: 300, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Show / rename a saved area

/// A saved custom area on the map (long-press an area chip → Show on map), with Rename and "Filter by this area".
struct AreaMapSheet: View {
    @Environment(AppModel.self) var m
    @Environment(\.sheetIsRoot) var isRoot
    let areaId: UUID
    @State private var position: MapCameraPosition = .automatic
    @State private var renaming = false
    @State private var name = ""

    var area: SavedArea? { m.area(areaId) }

    var body: some View {
        Group {
            if let a = area {
                Map(position: $position) {
                    UserAnnotation()
                    MapPolygon(coordinates: a.points.map(\.coordinate))
                        .foregroundStyle(Theme.lime.opacity(0.35)).stroke(Theme.lime, lineWidth: 3)
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) { footer(a) }
                .onAppear { fit(a) }
            } else {
                EmptyState(system: "skew", text: "This area no longer exists.")
            }
        }
        .navigationTitle(area?.name ?? "Area").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot { ToolbarItem(placement: .topBarLeading) { CloseButton() } }
            if area != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rename") { name = area?.name ?? ""; renaming = true }.fontWeight(.semibold)
                }
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
                .bruceFont(15, weight: .medium)
            if selected {
                Button { m.selectedAreaId = nil } label: {
                    Label("Filtering by this area", systemImage: "checkmark").bruceFont(17, weight: .bold)
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.glass).controlSize(.large)
            } else {
                LimeButton(title: "Filter by this area") { m.selectedAreaId = a.id }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
    }

    func fit(_ a: SavedArea) {
        guard let b = PolygonMath.bounds(a.points) else { return }
        // Shifted south a little so the area sits above the footer card.
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: b.centerLat - b.latDelta * 0.2, longitude: b.centerLon),
                                              span: MKCoordinateSpan(latitudeDelta: b.latDelta * 1.4, longitudeDelta: b.lonDelta)))
    }
}
