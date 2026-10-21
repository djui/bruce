import SwiftUI

// Milestones and "New to you" (Milestones.swift): a Home card for the newest milestone, a badge row under
// Statistics, and a Home row of studios never visited in categories the user does. Own artwork: SF Symbols.

struct MilestoneBadge: View {
    let m: Milestone
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            Circle().fill(Theme.lime)
            Circle().stroke(Theme.ink.opacity(0.08), lineWidth: 1)
            VStack(spacing: -2) {
                Image(systemName: m.symbol).font(.system(size: size * 0.34, weight: .bold))
                if m.kind != .category { Text("\(m.value)").font(.system(size: size * 0.22, weight: .black).width(.expanded)) }
            }
            .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(m.title)
    }
}

/// Home: the newest milestone reached in the last 30 days, until dismissed (demo mode: the newest one).
struct MilestoneCard: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let reached = Milestones.reached(visits: m.visitHistory ?? [], categoryTitle: { m.categoryTitle(forKey: String($0)) }, studioName: { m.studio($0)?.name })
        let fresh = AppModel.demo ? reached.first { !m.milestonesSeen.contains($0.key) } : Milestones.fresh(reached, seen: m.milestonesSeen)
        if let ms = fresh {
            HStack(alignment: .top, spacing: 14) {
                MilestoneBadge(m: ms)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MILESTONE").bruceFont(11, weight: .heavy, width: .expanded).foregroundStyle(Theme.secondary)
                    Text(ms.title).bruceFont(18, weight: .bold)
                    Text(ms.detail).bruceFont(14).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        ShareLink(item: ms.shareText) {
                            Label("Share", systemImage: "square.and.arrow.up").bruceFont(14, weight: .semibold)
                                .padding(.horizontal, 12).frame(height: 32)
                        }
                        .buttonStyle(.glass)
                        Button("Done") { withAnimation { m.markMilestoneSeen(ms.key) } }.bruceFont(14, weight: .semibold).foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 26))
            .padding(.horizontal, Theme.gutter).padding(.top, 18)
        }
    }
}

/// Statistics: every milestone reached, newest first.
struct MilestonesRow: View {
    @Environment(AppModel.self) var m
    let visits: [BruceAPI.Visit]
    var body: some View {
        let reached = Milestones.reached(visits: visits, categoryTitle: { m.categoryTitle(forKey: String($0)) }, studioName: { m.studio($0)?.name })
        if !reached.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("MILESTONES").bruceHeading(18).padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(reached) { ms in
                            VStack(spacing: 6) {
                                MilestoneBadge(m: ms, size: 52)
                                Text(ms.title).bruceFont(12, weight: .semibold).lineLimit(1)
                                Text(BruceDate.format(ms.reachedAt, "d MMM yyyy")).bruceFont(11).foregroundStyle(Theme.secondary)
                            }
                            .frame(width: 92)
                            .contextMenu { ShareLink(item: ms.shareText) }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.top, 12)
        }
    }
}

/// Home: studios never visited, in categories the user does or close by, within the plan.
struct NewToYouSection: View {
    @Environment(AppModel.self) var m
    var body: some View {
        let visited = m.visitedStudioIds ?? []
        let picks = m.visitHistory == nil ? [] : NewToYou.picks(studios: m.studios, visited: visited, profile: VisitProfile(visits: m.visitHistory ?? []), tier: m.tier,
                                                                 distance: { m.distance($0) }, categoryTitle: { m.categoryTitle(forKey: String($0)) })
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("NEW TO YOU").bruceHeading(19).padding(.horizontal, Theme.gutter)
                    Spacer()
                    if let g = m.goals.first(where: { $0.category == "newStudios" }) {
                        let p = m.goalsMonth().progress.first { $0.goal.id == g.id }
                        NavigationLink(value: Route.goals) {
                            Text("Try \(g.target) new studio\(g.target == 1 ? "" : "s") · \(p?.done ?? 0) of \(g.target)")
                                .bruceFont(13, weight: .semibold).padding(.horizontal, 12).frame(height: 30)
                        }
                        .buttonStyle(.glass).padding(.trailing, Theme.gutter)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(picks) { p in
                            NavigationLink(value: Route.studio(p.studio.id)) {
                                ZStack(alignment: .bottomLeading) {
                                    RemotePhoto(fileId: p.studio.photo)
                                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.studio.name).bruceFont(19, weight: .bold).lineLimit(1).minimumScaleFactor(0.7)
                                        Text([p.studio.vicinity, p.distance.map { formatDistance(Int($0)) }, "never visited"].compactMap { $0 }.joined(separator: " · "))
                                            .bruceFont(13, weight: .medium)
                                        Text(p.reason).bruceFont(12).opacity(0.85)
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
}
