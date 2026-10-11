import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) var m
    @State private var page = 0
    @State private var query = ""

    var spotlight: [BruceAPI.HomeItem] { m.home.first { $0.type == "SPOTLIGHT" }?.items ?? [] }
    var categoryItems: [BruceAPI.HomeItem] { m.home.first { $0.type == "CATEGORIES" }?.items ?? [] }
    var studioSections: [BruceAPI.HomeSection] { m.home.filter { $0.items.first?.type == "STUDIO" } }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Home") {
                HStack(spacing: 18) {
                    IconButton(system: "viewfinder", size: 22, badge: !m.openWindowTargets.isEmpty) {
                        m.present(.quickCheckIn)
                    }
                    IconButton(system: "bell", size: 22) { m.present(.notifications) }
                    IconButton(system: "line.3.horizontal", size: 22, badge: true) { m.present(.menu) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField.padding(.horizontal, Theme.gutter).padding(.top, 8)
                    if !query.isEmpty {
                        searchResults
                    } else if !m.isLoggedIn {
                        loggedOut
                    } else {
                        if !spotlight.isEmpty { spotlightSection }
                        if !categoryItems.isEmpty { categoriesSection }
                        ForEach(studioSections, id: \.self) { s in studioRow(s) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.secondary)
            Text("Search studios, classes, instructors").font(.system(size: 17, weight: .light)).foregroundStyle(Theme.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.searchGrey))
        .contentShape(Rectangle())
        .onTapGesture { m.present(.search) }
    }

    var searchResults: some View {
        let hits = m.cityStudios.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.vicinity ?? "").localizedCaseInsensitiveContains(query) }.prefix(40)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hits)) { s in
                Button { m.push(.studio(s.id)) } label: {
                    InfoRow(title: s.name, subtitle: s.vicinity)
                }.buttonStyle(.plain)
            }
            if hits.isEmpty { Text("No results").foregroundStyle(Theme.secondary).padding(Theme.gutter) }
        }
        .padding(.top, 12)
    }

    var loggedOut: some View {
        VStack(spacing: 18) {
            Text("Log in to see your spotlight, categories and classes.")
                .font(.system(size: 16, weight: .light)).multilineTextAlignment(.center).padding(.top, 60)
            LimeButton(title: "Log in") { m.present(.login) }
        }
        .padding(.horizontal, Theme.gutter)
    }

    var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spotlight").font(.system(size: 24, weight: .bold)).padding(.horizontal, Theme.gutter)
            TabViewLike(count: spotlight.count, page: $page) { i in
                let it = spotlight[i]
                Button { if let id = it.classId { m.push(.classDetail(id)) } } label: {
                    ZStack(alignment: .bottomLeading) {
                        RemotePhoto(fileId: it.photo)
                        Color.black.opacity(0.35)
                        VStack(spacing: 6) {
                            Text(it.className ?? "").font(.system(size: 30, weight: .bold))
                            Text(BruceDate.format(it.startTime.flatMap(BruceDate.parse), "EEEE | d MMMM | HH:mm"))
                                .font(.system(size: 18, weight: .regular))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(it.studioName ?? "").font(.system(size: 17)).padding(20)
                    }
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, Theme.gutter)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 220)
            HStack(spacing: 10) {
                ForEach(0..<spotlight.count, id: \.self) { i in
                    Circle().fill(i == page ? Theme.ink : Color(white: 0.85)).frame(width: 8, height: 8)
                        .onTapGesture { page = i }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 26)
    }

    var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Categories").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { m.push(.categories) } label: { Text("Show all").underline().font(.system(size: 17, weight: .medium)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categoryItems, id: \.self) { c in
                        Button { if let id = c.categoryId { m.push(.category(id)) } } label: {
                            ZStack {
                                RemotePhoto(fileId: c.photo, w: 240, h: 240)
                                Color.black.opacity(0.3)
                                Text(c.title ?? "").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            }
                            .frame(width: 182, height: 182)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 22)
    }

    func studioRow(_ s: BruceAPI.HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(s.title?.isEmpty == false ? s.title! : "Nearby gyms").font(.system(size: 24, weight: .bold))
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(s.items, id: \.self) { it in
                        Button { if let id = it.studioId { m.push(.studio(id)) } } label: {
                            ZStack(alignment: .bottomLeading) {
                                RemotePhoto(fileId: it.photo)
                                Color.black.opacity(0.35)
                                VStack(spacing: 4) {
                                    Text(it.studioName ?? "").font(.system(size: 21, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(it.categories?.first ?? "").font(.system(size: 16))
                                }
                                .padding(.horizontal, 10).frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(([it.vicinities?.first].compactMap { $0 } + [it.distance.map(formatDistance)].compactMap { $0 }).joined(separator: " | "))
                                    .font(.system(size: 13)).padding(.horizontal, 16).padding(.bottom, 14)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 262, height: 164)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 26)
    }
}


/// Horizontally paged carousel (TabView page style is iOS-only).
struct TabViewLike<Content: View>: View {
    let count: Int
    @Binding var page: Int
    @ViewBuilder var content: (Int) -> Content
    @State private var drag: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in content(i).frame(width: geo.size.width) }
            }
            .offset(x: -CGFloat(page) * geo.size.width + drag)
            .animation(.easeOut(duration: 0.25), value: page)
            .gesture(DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.width }
                .onEnded { v in
                    if v.translation.width < -60 { page = min(count - 1, page + 1) }
                    if v.translation.width > 60 { page = max(0, page - 1) }
                    drag = 0
                })
        }
        .clipped()
    }
}
