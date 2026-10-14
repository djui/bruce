import SwiftUI

// MARK: - Home "For you" (Recommendations.swift): a hero pick and more picks with the reasons as chips

struct ForYouSection: View {
    @Environment(AppModel.self) var m

    var body: some View {
        let recs = m.recommendations
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("FOR YOU").font(Theme.heading(19))
                Spacer()
                if let first = recs.first { Text(ForYou.dayLabel(first.c.start)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary) }
                Button { m.present(.places) } label: { Image(systemName: "mappin.and.ellipse").font(.system(size: 15, weight: .semibold)) }
                    .buttonStyle(.glass).accessibilityLabel("Places & commute")
            }
            .padding(.horizontal, Theme.gutter)
            if let hero = recs.first {
                NavigationLink(value: Route.classDetail(hero.c.id)) { RecHeroCard(rec: hero) }
                    .buttonStyle(.plain).padding(.horizontal, Theme.gutter)
                if recs.count > 1 {
                    HStack {
                        Text("MORE PICKS").font(Theme.heading(19))
                        Spacer()
                        NavigationLink(value: Route.forYou) { Text("Show all").font(.system(size: 15, weight: .semibold)) }.buttonStyle(.glass)
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 14)
                    ForEach(recs.dropFirst().prefix(3)) { r in
                        NavigationLink(value: Route.classDetail(r.c.id)) { RecCard(rec: r) }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            } else if m.recommendationsLoading {
                RoundedRectangle(cornerRadius: 26).fill(Theme.chipGrey).frame(height: 210).overlay { ProgressView() }
                    .padding(.horizontal, Theme.gutter)
            } else {
                Button { m.present(.places) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Theme.limeInk)
                        Text(m.recSettings.places.isEmpty ? "Add home and work to get picks that fit your day."
                                                          : "No picks for the next two days yet. Check back later.")
                            .font(.system(size: 15)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(16).background(Theme.sectionGrey, in: .rect(cornerRadius: 24))
                }
                .buttonStyle(.plain).padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 22)
        .task(id: m.isLoggedIn) { await m.refreshRecommendations() }
    }
}

enum ForYou {
    /// "Tomorrow, Thu 15 Oct", "Today, Wed 14 Oct", "Fri 16 Oct".
    static func dayLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        let cal = BruceDate.calendar
        let rest = BruceDate.format(d, "EEE d MMM")
        if cal.isDateInToday(d) { return "Today, \(rest)" }
        if cal.isDateInTomorrow(d) { return "Tomorrow, \(rest)" }
        return rest
    }
    /// Friend faces: one pastel per person (the mockup's palette).
    static let faces: [Color] = [Color(red: 0.95, green: 0.86, blue: 0.56), Color(red: 0.78, green: 0.71, blue: 0.95),
                                 Color(red: 0.96, green: 0.72, blue: 0.63), Color(red: 0.65, green: 0.83, blue: 0.95)]
    /// By first letter, so a friend keeps their colour everywhere.
    static func face(_ name: String) -> Color { faces[Int(name.unicodeScalars.first?.value ?? 0) % faces.count] }
}

/// The big lime-green pick: match, studio, title, when, and two reasons.
struct RecHeroCard: View {
    @Environment(AppModel.self) var m
    let rec: Recommendation
    var body: some View {
        let c = rec.c
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.31, green: 0.37, blue: 0.16), Color(red: 0.50, green: 0.60, blue: 0.23), Color(red: 0.64, green: 0.75, blue: 0.29)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: GoalCategory.symbol(c.classCategories?.first?.categoryId.map(String.init), categoryTitle: m.categories.first { $0.id == c.classCategories?.first?.categoryId }?.title))
                .font(.system(size: 130, weight: .ultraLight)).foregroundStyle(.white.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 20, y: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.title).font(.system(size: 25, weight: .heavy).width(.expanded)).lineLimit(2)
                Text("\(BruceDate.format(c.start, "EEEE | d MMMM | HH:mm"))\(c.durationMinutes.map { " · \($0) min" } ?? "")")
                    .font(.system(size: 14, weight: .medium)).opacity(0.9)
                ReasonChips(rec: rec, limit: 2, onDark: true).padding(.top, 8)
            }
            .foregroundStyle(.white).padding(18)
            HStack(alignment: .top) {
                Text("\(rec.match)% match").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.lime, in: .capsule)
                Spacer()
                Text(m.studioName(c.studioId)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: .capsule).overlay(Capsule().stroke(.white.opacity(0.3)))
            }
            .padding(14).frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 226)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }
}

/// A smaller pick: time, length, title, studio, area | instructor, reasons.
struct RecCard: View {
    @Environment(AppModel.self) var m
    let rec: Recommendation
    var showDay = false
    var body: some View {
        let c = rec.c
        let st = m.studio(c.studioId)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if showDay { Text(BruceDate.format(c.start, "EEE").uppercased()).font(.system(size: 11, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary) }
                    Text(BruceDate.time(c.start)).font(.system(size: 17, weight: .bold)).monospacedDigit()
                    Text(durationText(c)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                .frame(width: 54, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    Text(st?.name ?? c.studio?.name ?? "").font(.system(size: 15)).lineLimit(1)
                    let line = [st?.vicinity ?? c.studio?.vicinity, c.instructor].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " | ")
                    if !line.isEmpty { Text(line).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Text("\(rec.match)%").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.limeInk).monospacedDigit()
            }
            ReasonChips(rec: rec, limit: 3)
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sectionGrey, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

/// Reasons as chips ("8 min from work", "Robin booked" with faces, "2 spots left" in lime).
struct ReasonChips: View {
    @Environment(AppModel.self) var m
    let rec: Recommendation
    var limit = 3
    var onDark = false
    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(rec.reasons.prefix(limit).enumerated()), id: \.offset) { _, r in
                InsightChip(text: r.text, symbol: r.symbol, friendIds: r.friendIds, onDark: onDark)
            }
            if let n = rec.fewSpots {
                Text("\(n) spot\(n == 1 ? "" : "s") left").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.lime, in: .capsule)
            }
        }
    }
}

struct InsightChip: View {
    @Environment(AppModel.self) var m
    let text: String
    var symbol: String? = nil
    var friendIds: [Int] = []
    var onDark = false
    var body: some View {
        HStack(spacing: 5) {
            if !friendIds.isEmpty {
                HStack(spacing: -6) {
                    ForEach(friendIds.prefix(3), id: \.self) { id in
                        LetterFace(name: m.friendName(id), size: 20)
                            .overlay(Circle().stroke(onDark ? Color.clear : Theme.sectionGrey, lineWidth: 2))
                    }
                }
            } else if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
        .foregroundStyle(onDark ? Color.white : Theme.ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(onDark ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Theme.chipGrey), in: .capsule)
    }
}

/// A coloured circle with an initial (friends without a photo in challenges and chips).
struct LetterFace: View {
    let name: String
    var color: Color? = nil
    var size: CGFloat = 38
    var body: some View {
        Circle().fill(color ?? ForYou.face(name))
            .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.black))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "Show all": every pick for the next two days.
struct ForYouListView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                PageHeading(text: "For you")
                ForEach(groupedByDay(m.recommendations, date: { $0.c.start }), id: \.0) { day, list in
                    Text(ForYou.dayLabel(day)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.top, 8)
                    ForEach(list.sorted { $0.c.startTime < $1.c.startTime }) { r in
                        NavigationLink(value: Route.classDetail(r.c.id)) { RecCard(rec: r) }.buttonStyle(.plain)
                    }
                }
                if m.recommendations.isEmpty {
                    EmptyState(system: "sparkles", text: m.recommendationsLoading ? "Finding classes for you…" : "No picks for the next two days yet.")
                }
                Text("Picked on this iPhone from your visits, friends' bookings and travel time from your places.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, 8)
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 30)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .pushedPage("For you")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { m.present(.places) } label: { Image(systemName: "mappin.and.ellipse") }.accessibilityLabel("Places & commute")
            }
        }
        .refreshable { await m.refreshRecommendations(force: true) }
        .task { await m.refreshRecommendations() }
    }
}

/// Pushed pages: the wide uppercase title as the first line of the content (a long title in the bar would be
/// squeezed next to the back button).
struct PageHeading: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.screenTitle(26)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Inline bar with the back button only; pair with `PageHeading` in the content.
    func pushedPage(_ title: String) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }
}
