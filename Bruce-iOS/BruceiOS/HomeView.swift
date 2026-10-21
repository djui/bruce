import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var loc: LocationProvider
    @State private var page: Int? = 0

    var spotlight: [BruceAPI.HomeItem] { m.home.first { $0.type == "SPOTLIGHT" }?.items ?? [] }
    var categoryItems: [BruceAPI.HomeItem] { m.home.first { $0.type == "CATEGORIES" }?.items ?? [] }
    var studioSections: [BruceAPI.HomeSection] { m.home.filter { $0.items.first?.type == "STUDIO" } }
    var nextBooking: BruceAPI.Booking? {
        m.bookings.filter { ($0.class?.start ?? .distantPast) > Date().addingTimeInterval(-3600) }
            .min { ($0.class?.startTime ?? "") < ($1.class?.startTime ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !m.isLoggedIn {
                    loggedOut
                } else {
                    if let b = nextBooking, let c = b.class { nextUp(c) }
                    NextRaceCard()
                    MilestoneCard()
                    ForYouSection()
                    NewToYouSection()
                    if m.home.isEmpty {
                        loadingSkeleton
                    } else {
                        UpcomingRacesRow()
                        if !spotlight.isEmpty { spotlightSection }
                        if !categoryItems.isEmpty { categoriesSection }
                        ForEach(studioSections, id: \.self) { s in studioRow(s) }
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .bruceTitle("Home")
        .toolbar { MainToolbarButtons() }
        .refreshable { await m.bootstrap() }
        // Like the original: ask for location the first time Home appears after login (system prompt explains why).
        .task(id: m.isLoggedIn) { if m.isLoggedIn { loc.requestIfNeeded() } }
    }

    var searchField: some View {
        Button { m.present(.search) } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").bruceFont(18, weight: .medium)
                Text("Search studios, classes, instructors").bruceFont(16)
                Spacer()
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).frame(height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    var loggedOut: some View {
        VStack(spacing: 18) {
            Image(systemName: "figure.run.circle").bruceFont(64, weight: .light).foregroundStyle(Theme.limeInk)
            Text("Log in to see your spotlight, categories and classes.")
                .bruceFont(16).multilineTextAlignment(.center)
            LimeButton(title: "Log in") { m.present(.login) }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 70)
    }

    /// Glass "next up" card for the next booking, with a direct check-in.
    func nextUp(_ c: BruceAPI.BruceClass) -> some View {
        NavigationLink(value: Route.classDetail(c.id)) {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(BruceDate.format(c.start, "EEE").uppercased()).bruceFont(12, weight: .heavy, width: .expanded)
                    Text(BruceDate.time(c.start)).bruceFont(18, weight: .bold).monospacedDigit()
                }
                .foregroundStyle(.black)
                .frame(width: 70, height: 58)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime))
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT UP").bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
                    Text(c.title).bruceFont(17, weight: .bold).lineLimit(1)
                    Text(m.studioName(c.studioId)).bruceFont(14).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter).padding(.top, 18)
    }

    func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).bruceHeading(19).padding(.horizontal, Theme.gutter)
    }

    var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Spotlight")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(spotlight.enumerated()), id: \.offset) { i, it in
                        NavigationLink(value: it.classId.map { Route.classDetail($0) } ?? Route.categories) {
                            ZStack(alignment: .bottomLeading) {
                                RemotePhoto(fileId: it.photo, symbol: "figure.highintensity.intervaltraining")
                                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(it.className ?? "").bruceFont(26, weight: .heavy, width: .expanded).lineLimit(2)
                                    Text(BruceDate.format(it.startTime.flatMap(BruceDate.parse), "EEEE | d MMMM | HH:mm"))
                                        .bruceFont(15, weight: .medium)
                                }
                                .foregroundStyle(.white)
                                .padding(18)
                                Text(it.studioName ?? "").bruceFont(13, weight: .semibold)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .glassEffect(.regular, in: .capsule)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(14)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                            .containerRelativeFrame(.horizontal)
                            .frame(height: 230)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.gutter)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            HStack(spacing: 8) {
                ForEach(0..<spotlight.count, id: \.self) { i in
                    Capsule().fill(i == (page ?? 0) ? Theme.ink : Theme.tertiary)
                        .frame(width: i == (page ?? 0) ? 18 : 7, height: 7)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.3), value: page)
        }
        .padding(.top, 26)
    }

    var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Categories")
                Spacer()
                NavigationLink(value: Route.categories) { Text("Show all").bruceFont(15, weight: .semibold) }
                    .buttonStyle(.glass).padding(.trailing, Theme.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categoryItems, id: \.self) { c in
                        NavigationLink(value: c.categoryId.map { Route.category($0) } ?? Route.categories) {
                            ZStack(alignment: .bottomLeading) {
                                RemotePhoto(fileId: c.photo, w: 240, h: 240, symbol: "figure.mind.and.body")
                                Text(c.title ?? "").bruceFont(17, weight: .bold)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .glassEffect(.regular, in: .capsule)
                                    .padding(10)
                            }
                            .frame(width: 168, height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 28)
    }

    /// Neutral placeholder while the home screen loads.
    var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(Theme.chipGrey).frame(width: 160, height: 22)
            RoundedRectangle(cornerRadius: 28).fill(Theme.chipGrey).frame(height: 230)
            RoundedRectangle(cornerRadius: 8).fill(Theme.chipGrey).frame(width: 190, height: 22).padding(.top, 14)
            HStack(spacing: 12) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 26).fill(Theme.chipGrey).frame(height: 168) } }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 26)
        .overlay { ProgressView() }
        .accessibilityLabel("Loading")
    }

    func studioRow(_ s: BruceAPI.HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(s.title?.isEmpty == false ? s.title! : "Nearby gyms")
                Spacer()
                // Nearby is computed from the coordinates we send: offer the real location (asked only on tap).
                if s.type == "NEARBY_GYMS" && !loc.authorized { UseLocationButton(text: "Near me").padding(.trailing, Theme.gutter) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(s.items, id: \.self) { it in
                        NavigationLink(value: it.studioId.map { Route.studio($0) } ?? Route.categories) {
                            ZStack(alignment: .bottomLeading) {
                                RemotePhoto(fileId: it.photo)
                                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(it.studioName ?? "").bruceFont(19, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(([it.categories?.first, it.vicinities?.first].compactMap { $0 } + [it.distance.map(formatDistance)].compactMap { $0 })
                                        .joined(separator: " | ")).bruceFont(13, weight: .medium)
                                }
                                .foregroundStyle(.white).padding(14)
                            }
                            .frame(width: 262, height: 164)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 28)
    }
}
