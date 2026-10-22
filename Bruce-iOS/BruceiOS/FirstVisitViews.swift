import SwiftUI

/// "First visit here?" (FirstVisit.swift): shown on class and studio pages until the first check-in at the studio.
struct FirstVisitCard: View {
    @Environment(AppModel.self) var m
    let studio: BruceAPI.Studio?
    var c: BruceAPI.BruceClass? = nil

    var body: some View {
        let info = FirstVisitInfo(studio: studio, class: c)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("First visit here?", systemImage: "sparkles").bruceFont(16, weight: .bold)
                Spacer()
                if let c { Text("\(c.title) \(BruceDate.time(c.start))").bruceFont(13).foregroundStyle(Theme.secondary).lineLimit(1) }
            }
            row("qrcode.viewfinder", info.checkIn, info.checkInNote)
            if let door = info.door { row("door.left.hand.open", door, nil) }
            if !info.facilities.isEmpty { row("shower", info.facilities.joined(separator: " · "), nil) }
            row("exclamationmark.triangle", FirstVisitInfo.lateCheckIn, nil, tint: Theme.hoursOrange)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.10)), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    func row(_ icon: String, _ text: String, _ note: String?, tint: Color = Theme.limeInk) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).bruceFont(15).foregroundStyle(tint).frame(width: 22).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).bruceFont(15, weight: .medium).fixedSize(horizontal: false, vertical: true)
                if let note { Text(note).bruceFont(13).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// "All time 4.6 · 312 ratings" next to "Last 90 days 4.1 · 23 with comments" on the Reviews tab.
struct RecentRatingRow: View {
    let rating: BruceAPI.Rating?
    let reviews: [BruceAPI.Review]?

    var body: some View {
        let recent = reviews.flatMap { RecentRating.recent($0) }
        HStack(alignment: .top, spacing: 12) {
            cell("All time", rating?.average.map { String(format: "%.1f", Double($0) / 100) } ?? "–", "\(rating?.total ?? 0) ratings")
            Divider().frame(height: 44)
            cell("Last \(RecentRating.window) days", recent?.text ?? "–", recent.map { "\($0.count) with comments" } ?? (reviews == nil ? "loading…" : "no comments yet"))
        }
        if let t = RecentRating.trend(allTime: rating?.average, recent: recent) {
            Text(t).bruceFont(14, weight: .semibold).foregroundStyle(Theme.hoursOrange)
        }
    }

    func cell(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).bruceFont(12, weight: .semibold).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "star.fill").bruceFont(12).foregroundStyle(Theme.ink)
                Text(value).bruceDisplay(24, weight: .black)
            }
            Text(sub).bruceFont(12).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
