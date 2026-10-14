import SwiftUI

// MARK: - Auto-book (AutoBook.swift): rules list and server settings

struct AutoBookView: View {
    @Environment(AppModel.self) var m
    @State private var serverURL = AutoBookServer.url
    @State private var server: AutoBookServer.Status?
    @State private var working = false
    @State private var booksForMe = AutoBookServer.booksForMe
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
    static let server = "Books even when no device is awake: the server checks every five minutes, and every minute shortly before a class opens. While this is on, it keeps your Bruce login; switching it off removes your login and classes from the server."
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
