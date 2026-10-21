import SwiftUI

/// "Book again" (BookAgain.swift): the next class of a series the user went to, with Book and "Book every week".
struct BookAgainSheet: View {
    @Environment(AppModel.self) var m
    let template: BookAgainTemplate
    @State private var match: BookAgain.Match?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Book again", leading: m.sheets.count > 1 ? .back : .close) { if m.sheets.count > 1 { m.popSheet() } else { m.dismissSheets() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(template.title).font(.system(size: 20, weight: .bold))
                    Text("\(m.studioName(template.studioId)) · \(template.label)").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                    if !loaded {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else if let match {
                        let c = match.next
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Next: \(BruceDate.format(c.start, "EEE d MMM")) · \(BruceDate.time(c.start))\(c.durationMinutes.map { " · \($0) min" } ?? "")")
                                .font(.system(size: 17, weight: .semibold))
                            Text(detail(match)).font(.system(size: 15)).foregroundStyle(Theme.secondary)
                            if let opens = match.opens {
                                Label("Booking opens \(BruceDate.format(opens, "EEE d MMM, HH:mm"))", systemImage: "clock")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.waitlistOrange).padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.sectionGrey))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                        if m.booking(forClass: c.id) != nil {
                            LimeButton(title: "Booked · show class") { m.dismissSheets(); m.push(.classDetail(c.id)) }
                        } else if match.opens == nil, (c.availableSpots ?? 1) > 0 {
                            LimeButton(title: "Book \(BruceDate.format(c.start, "EEE d MMM"))") { m.pushSheet(.bookingRules(c.id)) }
                        } else {
                            outlined(match.opens == nil ? "Fully booked · show class" : "Show class") { m.dismissSheets(); m.push(.classDetail(c.id)) }
                        }
                        if m.isLoggedIn {
                            outlined(m.autoBookRule(for: c) == nil ? "Book every week" : "Booked every week · stop") { m.setAutoBook(m.autoBookRule(for: c) == nil, for: c) }
                            Text(match.opens == nil ? Copy.bookEveryWeek : "Not bookable yet. Book every week books it the moment it opens, and every week after.")
                                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("No upcoming \(template.label) class in this series at \(m.studioName(template.studioId)) in the next two weeks.")
                            .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                        outlined("Show studio") { m.dismissSheets(); m.push(.studio(template.studioId)) }
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 12)
            }
        }
        .task { match = await m.bookAgainNext(template); loaded = true }
    }

    func outlined(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 54)
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func detail(_ match: BookAgain.Match) -> String {
        var parts: [String] = []
        if let a = match.next.availableSpots { parts.append(a <= 0 ? "Fully booked" : a > 5 ? "5+ spots left" : "\(a) spot\(a == 1 ? "" : "s") left") }
        if match.sameInstructor { parts.append("same instructor") } else if let i = match.next.instructor, !i.isEmpty { parts.append(i) }
        return parts.joined(separator: " · ")
    }
}
