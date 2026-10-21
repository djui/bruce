import SwiftUI

/// "Book again" (BookAgain.swift): the next class of a series the user went to, with Book and "Book every week".
struct BookAgainSheet: View {
    @Environment(AppModel.self) var m
    let template: BookAgainTemplate
    @State private var match: BookAgain.Match?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title).font(.system(size: 20, weight: .bold))
                    Text("\(m.studioName(template.studioId)) · \(template.label)").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                }
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
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.hoursOrange).padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    if m.booking(forClass: c.id) != nil {
                        LimeButton(title: "Booked · show class", systemImage: "checkmark.circle.fill") { m.dismissSheets(); m.push(.classDetail(c.id)) }
                    } else if match.opens == nil, (c.availableSpots ?? 1) > 0 {
                        LimeButton(title: "Book \(BruceDate.format(c.start, "EEE d MMM"))") { m.pushSheet(.bookingRules(c.id)) }
                    } else if match.opens == nil {
                        Button { m.dismissSheets(); m.push(.classDetail(c.id)) } label: {
                            Text("Fully booked · show class").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    } else {
                        Button { m.dismissSheets(); m.push(.classDetail(c.id)) } label: {
                            Text("Show class").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                    }
                    if m.isLoggedIn {
                        Button {
                            m.setAutoBook(m.autoBookRule(for: c) == nil, for: c)
                        } label: {
                            Label(m.autoBookRule(for: c) == nil ? "Book every week" : "Booked every week · stop", systemImage: "calendar.badge.clock")
                                .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                        Text(match.opens == nil ? Copy.bookEveryWeek : "Not bookable yet. Book every week books it the moment it opens, and every week after.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    }
                } else {
                    EmptyState(system: "calendar.badge.exclamationmark", text: "No upcoming \(template.label) class in this series at \(m.studioName(template.studioId)) in the next two weeks.")
                    Button { m.dismissSheets(); m.push(.studio(template.studioId)) } label: {
                        Text("Show studio").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glass).controlSize(.large)
                }
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Book again")
        .task { match = await m.bookAgainNext(template); loaded = true }
    }

    func detail(_ match: BookAgain.Match) -> String {
        var parts: [String] = []
        if let a = match.next.availableSpots { parts.append(a <= 0 ? "Fully booked" : a > 5 ? "5+ spots left" : "\(a) spot\(a == 1 ? "" : "s") left") }
        if match.sameInstructor { parts.append("same instructor") } else if let i = match.next.instructor, !i.isEmpty { parts.append(i) }
        return parts.joined(separator: " · ")
    }
}

/// Small "Book again" button for visit rows and the rating sheet.
struct BookAgainButton: View {
    @Environment(AppModel.self) var m
    let template: BookAgainTemplate
    var body: some View {
        Button { m.openBookAgain(template) } label: {
            Label("Book again", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold)).labelStyle(.titleOnly)
                .padding(.horizontal, 12).frame(height: 30)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Book \(template.title) again")
    }
}
