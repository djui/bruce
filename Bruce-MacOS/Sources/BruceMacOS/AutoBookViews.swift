import SwiftUI

// MARK: - Auto-book (AutoBook.swift): rules list and server settings

struct AutoBookView: View {
    @Environment(AppModel.self) var m
    @State private var serverURL = AutoBookServer.url
    @State private var server: AutoBookServer.Status?
    @State private var working = false
    @State private var booksForMe = AutoBookServer.booksForMe
    @State private var lateSpots = AutoBookServer.lateSpots
    @State private var showServerFields = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Auto-book", leading: m.sheets.count > 1 ? .back : .close) {
                if m.sheets.count > 1 { m.popSheet() } else { m.dismissSheets() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header("EVERY WEEK")
                    if m.autoBookRules.isEmpty {
                        Text("No classes yet. Open a class and switch on \"Book every week\".")
                            .font(.system(size: 16, weight: .light)).padding(.horizontal, Theme.gutter).padding(.vertical, 12)
                    }
                    ForEach(m.autoBookRules) { r in
                        InfoRow(title: r.title, subtitle: "\(r.label) · \(m.studioName(r.studioId))", footnote: next(r), chevron: false) {
                            Button { m.removeAutoBook(r) } label: { Image(systemName: "trash").font(.system(size: 17, weight: .light)) }
                                .buttonStyle(.plain).help("Stop booking this class")
                        }
                    }
                    note(AutoBookCopy.howItWorks)

                    header("SERVER")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Let the server book for me").font(.system(size: 17, weight: .medium))
                            Spacer()
                            BlackToggle(isOn: Binding(get: { booksForMe }, set: { on in
                                booksForMe = on
                                run { await m.setServerBooksForMe(on); if let n = m.autoBookServerNote { throw ServerError(n) } }
                            }))
                        }
                        if booksForMe, let s = server { serverSummary(s) }
                        if booksForMe {
                            HStack {
                                Text("Spot opens 3–12 h before").font(.system(size: 17, weight: .medium))
                                Spacer()
                                Picker("", selection: Binding(get: { lateSpots }, set: { v in
                                    lateSpots = v
                                    AutoBookServer.lateSpots = v
                                    run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                                })) {
                                    Text("Ask me first").tag(AutoBookServer.LateSpots.ask)
                                    Text("Book it").tag(AutoBookServer.LateSpots.book)
                                }
                                .labelsHidden().fixedSize()
                            }
                            Text(AutoBookCopy.lateSpots).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let n = m.autoBookServerNote { Text(n).foregroundStyle(.red).font(.system(size: 14)) }
                        DisclosureGroup("Server address", isExpanded: $showServerFields) {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(AutoBookServer.defaultURL, text: $serverURL).textFieldStyle(.roundedBorder)
                                Button("Save and sync") {
                                    AutoBookServer.url = serverURL
                                    run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.system(size: 15, weight: .light))
                    }
                    .padding(.horizontal, Theme.gutter).padding(.top, 12)
                    note(AutoBookCopy.server)
                }
                .padding(.bottom, 30)
            }
            .disabled(working)
        }
        .task { await m.refreshAutoBook(); await loadServer() }
    }

    func header(_ t: String) -> some View {
        Text(t).font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
            .padding(.horizontal, Theme.gutter).padding(.top, 26)
    }

    func note(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.gutter).padding(.top, 12)
    }

    func next(_ r: AutoBookRule) -> String {
        guard let o = m.nextAutoBook(r) else { return "Next class not listed yet" }
        let opens = o.opens <= Date() ? "opened" : "opens \(BruceDate.format(o.opens, "EEE d MMM HH:mm"))"
        return "\(BruceDate.format(o.start, "EEE d MMM")): booking \(opens)"
    }

    @ViewBuilder func serverSummary(_ s: AutoBookServer.Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.hasSession == true ? "The server books for you." : "Not connected yet.")
            if let t = s.lastScan.flatMap(BruceDate.parse) { Text("Last checked \(BruceDate.format(t, "HH:mm"))") }
            ForEach((s.log ?? []).prefix(5), id: \.self) { e in
                Text("\(e.outcome ?? "") · \(e.title ?? "#\(e.classId)")").foregroundStyle(Theme.secondary)
            }
        }
        .font(.system(size: 14, weight: .light))
    }

    func loadServer() async {
        guard AutoBookServer.isConfigured, AutoBookServer.booksForMe, let s = m.session else { server = nil; return }
        server = try? await AutoBookServer.status(session: s)
        // The server's choice may come from another device.
        if let v = server?.lateSpots.flatMap(AutoBookServer.LateSpots.init) { AutoBookServer.lateSpots = v; lateSpots = v }
    }

    func run(_ op: @escaping () async throws -> Void) {
        working = true
        Task {
            do { try await op() } catch { m.flash(error.localizedDescription) }
            await loadServer()
            working = false
        }
    }
}

struct ServerError: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

enum AutoBookCopy {
    static let howItWorks = "A class opens for booking a fixed time before it starts, usually 7 days. While this app is running (and the Mac is awake) it books the class the moment it opens. Cancelling an auto-booked class does not rebook it."
    static let openings = "One-off classes booked once the moment their window opens, with the same retries and late-spot rule as weekly classes. At most \(AutoBook.maxOpenings) at a time."
    static let lateSpots = "Cancelling then costs a strike. Ask me first sends a notification with a Book button to your iPhone (and an email) instead. Under 3 h before, when cancelling costs 2 strikes (3 under 1 h, as much as a no-show), you're always asked; 12 h or more before, it's always booked."
    static let server = "Books even when no device is awake: the server checks every five minutes, and every minute shortly before a class opens. While this is on, it keeps your Bruce login; switching it off removes your login and classes from the server."
}

/// Class page: "Book when booking opens" for a listed class whose window has not opened yet (`OpeningWatch`).
struct OpeningWatchBar: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    let opens: Date
    @State private var working = false
    var watching: Bool { m.isWatchingOpening(c.id) }
    var body: some View {
        VStack(spacing: 10) {
            Text(watching ? "Watching · \(Copy.openingWatching(opens))" : "\(Copy.bookingOpens(opens)) · \(Copy.oneOffClass)")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(watching ? Color(red: 0.05, green: 0.5, blue: 0.2) : Theme.secondary)
                .multilineTextAlignment(.center)
            if watching {
                HStack {
                    Text(Copy.openingUsed(m.openingWatches.count)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(working ? "Stopping…" : "Stop watching") { toggle(false) }.disabled(working)
                }
            } else {
                LimeButton(title: working ? "Saving…" : "Book when booking opens") { toggle(true) }
            }
        }
    }
    func toggle(_ on: Bool) { working = true; Task { await m.setWatchOpening(on, for: c); working = false } }
}

/// Class page toggle on a full class: the server books it as soon as a waitlist spot frees up.
struct WaitlistAutoBookToggle: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.badge.clock").font(.system(size: 20, weight: .light))
            VStack(alignment: .leading, spacing: 3) {
                Text("Book when a spot opens").font(.system(size: 17, weight: .medium))
                Text(m.isOnWaitlist(c.id) ? "The server books it the moment a waitlist spot is free"
                                          : "Joins the waitlist and books it the moment a spot is free")
                    .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            BlackToggle(isOn: Binding(get: { m.isWatchingWaitlist(c.id) }, set: { on in Task { await m.setBookWhenSpotOpens(on, classId: c.id) } }))
        }
        .padding(.top, 22)
    }
}

/// Class page toggle.
struct AutoBookToggle: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 20, weight: .light))
            VStack(alignment: .leading, spacing: 3) {
                Text("Book every week").font(.system(size: 17, weight: .medium))
                Text(subtitle).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            BlackToggle(isOn: Binding(get: { m.autoBookRule(for: c) != nil }, set: { m.setAutoBook($0, for: c) }))
        }
        .padding(.top, 22)
    }

    var subtitle: String {
        guard let r = m.autoBookRule(for: c) ?? AutoBookRule(c) else { return "" }
        let days = Int(((c.bookableEarliest.map(Double.init) ?? AutoBook.defaultWindow) / 86_400).rounded())
        return "\(r.label), booked \(days) day\(days == 1 ? "" : "s") ahead when it opens"
    }
}
