import SwiftUI
import UserNotifications

// MARK: - Auto-book (AutoBook.swift): rules list and server settings

struct AutoBookView: View {
    @Environment(AppModel.self) var m
    @State private var serverURL = AutoBookServer.url
    @State private var serverKey = AutoBookServer.key
    @State private var server: AutoBookServer.Status?
    @State private var working = false
    @State private var booksForMe = AutoBookServer.booksForMe
    @State private var showServerFields = !AutoBookServer.isConfigured

    var body: some View {
        Form {
            Section {
                if m.autoBookRules.isEmpty {
                    Text("No classes yet. Open a class and switch on \"Book every week\".").foregroundStyle(Theme.secondary)
                }
                ForEach(m.autoBookRules) { r in
                    InfoRow(title: r.title, subtitle: "\(r.label) · \(m.studioName(r.studioId))", footnote: next(r), chevron: false)
                }
                .onDelete { idx in idx.map { m.autoBookRules[$0] }.forEach(m.removeAutoBook) }
            } header: { Text("Every week") } footer: { Text(AutoBookCopy.howItWorks) }

            Section {
                if AutoBookServer.isConfigured {
                    Toggle("Let the server book for me", isOn: Binding(get: { booksForMe }, set: { on in
                        booksForMe = on
                        run { await m.setServerBooksForMe(on); if let n = m.autoBookServerNote { throw ServerError(n) } }
                    }))
                    if let s = server { serverSummary(s) }
                }
                if let n = m.autoBookServerNote { Text(n).foregroundStyle(Theme.red).font(.system(size: 14)) }
                DisclosureGroup("Server address and key", isExpanded: $showServerFields) {
                    TextField(AutoBookServer.defaultURL, text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Server key", text: $serverKey)
                    Button("Save and sync") {
                        AutoBookServer.url = serverURL; AutoBookServer.key = serverKey
                        run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                    }
                    .disabled(serverURL.isEmpty || serverKey.isEmpty)
                }
            } header: { Text("Server") } footer: { Text(AutoBookCopy.server) }
        }
        .disabled(working)
        .sheetChrome("Auto-book")
        .task { await m.refreshAutoBook(); await loadServer() }
    }

    func next(_ r: AutoBookRule) -> String {
        guard let o = m.nextAutoBook(r) else { return "Next class not listed yet" }
        let opens = o.opens <= Date() ? "opened" : "opens \(BruceDate.format(o.opens, "EEE d MMM HH:mm"))"
        return "\(BruceDate.format(o.start, "EEE d MMM")): booking \(opens)"
    }

    @ViewBuilder func serverSummary(_ s: AutoBookServer.Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.hasSession == true ? "The server can book for you." : "The server has no login yet.")
            if let t = s.lastScan.flatMap(BruceDate.parse) { Text("Last checked \(BruceDate.format(t, "HH:mm"))") }
            ForEach((s.log ?? []).prefix(5), id: \.self) { e in
                Text("\(e.outcome ?? "") · \(e.title ?? "#\(e.classId)")").foregroundStyle(Theme.secondary)
            }
        }
        .font(.system(size: 14))
    }

    func loadServer() async {
        guard AutoBookServer.isConfigured else { server = nil; return }
        server = try? await AutoBookServer.status()
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
    static let howItWorks = "A class opens for booking a fixed time before it starts, usually 7 days. When it opens you get a notification with a Book button, and the app books by itself while it is open. Swipe to remove a class. Cancelling an auto-booked class does not rebook it."
    static let server = "Books even when your phone is locked or offline: the server checks every five minutes, and every minute shortly before a class opens. While this is on, it keeps your Bruce login; switching it off removes the login from the server."
}

/// Class page toggle.
struct AutoBookToggle: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    var body: some View {
        Toggle(isOn: Binding(get: { m.autoBookRule(for: c) != nil }, set: { m.setAutoBook($0, for: c) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Book every week").font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            } icon: { Image(systemName: "calendar.badge.clock") }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    var subtitle: String {
        guard let r = m.autoBookRule(for: c) ?? AutoBookRule(c) else { return "" }
        let days = Int(((c.bookableEarliest.map(Double.init) ?? AutoBook.defaultWindow) / 86_400).rounded())
        return "\(r.label), booked \(days) day\(days == 1 ? "" : "s") ahead when it opens"
    }
}

// MARK: - Notification taps (Book button on the "Booking opens" notification)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app so a tap in the foreground can open the class page.
    @MainActor static var openClass: (@MainActor (Int) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AutoBook.registerCategory()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let classId = await AutoBook.handle(response) else { return }
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { AppDelegate.openClass?(classId) }
        }
    }

    /// While the app is open it books by itself, so the "Booking opens" prompt is not shown; results are.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == AutoBook.category ? [] : [.banner, .sound]
    }
}
