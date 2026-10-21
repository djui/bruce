import SwiftUI
import UserNotifications

// MARK: - Auto-book (AutoBook.swift): rules list and server settings

struct AutoBookView: View {
    @Environment(AppModel.self) var m
    @State private var serverURL = AutoBookServer.url
    @State private var server: AutoBookServer.Status?
    @State private var working = false
    @State private var booksForMe = AutoBookServer.booksForMe
    @State private var habitNudges = AutoBookServer.habitNudges
    @State private var habitNudgeDays = AutoBookServer.habitNudgeDays
    @State private var lateSpots = AutoBookServer.lateSpots
    @State private var showServerFields = false

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

            if !m.openingWatches.isEmpty {
                Section {
                    ForEach(m.openingWatches) { w in
                        InfoRow(title: w.title, subtitle: "\(BruceDate.format(w.start, "EEE d MMM, HH:mm")) · \(m.studioName(w.studioId))",
                                footnote: Copy.bookingOpens(w.opens), chevron: false)
                    }
                    .onDelete { idx in idx.map { m.openingWatches[$0] }.forEach(m.removeOpeningWatch) }
                } header: { Text("Waiting for booking to open") } footer: { Text(AutoBookCopy.openings) }
            }

            Section {
                Toggle("Let the server book for me", isOn: Binding(get: { booksForMe }, set: { on in
                    booksForMe = on
                    run { await m.setServerBooksForMe(on); if let n = m.autoBookServerNote { throw ServerError(n) } }
                }))
                if booksForMe, let s = server { serverSummary(s) }
                if booksForMe {
                    Picker(selection: Binding(get: { lateSpots }, set: { v in
                        lateSpots = v
                        AutoBookServer.lateSpots = v
                        run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                    })) {
                        Text("Ask me first").tag(AutoBookServer.LateSpots.ask)
                        Text("Book it").tag(AutoBookServer.LateSpots.book)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spot opens 3–12 h before")
                            Text(AutoBookCopy.lateSpots).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Toggle(isOn: Binding(get: { habitNudges }, set: { on in
                        habitNudges = on
                        AutoBookServer.habitNudges = on
                        run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggest classes when I skip a habit")
                            Text(AutoBookCopy.habitNudges(days: habitNudgeDays)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                    }
                    if habitNudges {
                        Picker("Quiet days before the suggestion", selection: Binding(get: { habitNudgeDays }, set: { d in
                            habitNudgeDays = d
                            AutoBookServer.habitNudgeDays = d
                            run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                        })) {
                            ForEach(AutoBookServer.habitNudgeDayChoices, id: \.self) { Text("\($0) days").tag($0) }
                        }
                    }
                }
                if booksForMe, (server?.devices ?? 0) > 0 {
                    Button("Send a test notification") {
                        guard let s = m.session else { return }
                        run { try await AutoBookServer.testPush(session: s) }
                    }
                }
                if let n = m.autoBookServerNote { Text(n).foregroundStyle(Theme.red).font(.system(size: 14)) }
                DisclosureGroup("Server address", isExpanded: $showServerFields) {
                    TextField(AutoBookServer.defaultURL, text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Save and sync") {
                        AutoBookServer.url = serverURL
                        run { await m.syncAutoBookServer(); if let n = m.autoBookServerNote { throw ServerError(n) } }
                    }
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
            Text(s.hasSession == true ? "The server books for you\((s.devices ?? 0) > 0 ? " and notifies this phone" : "")." : "Not connected yet.")
            if let t = s.lastScan.flatMap(BruceDate.parse) { Text("Last checked \(BruceDate.format(t, "HH:mm"))") }
            ForEach((s.log ?? []).prefix(5), id: \.self) { e in
                Text("\(e.outcome ?? "") · \(e.title ?? "#\(e.classId)")").foregroundStyle(Theme.secondary)
            }
        }
        .font(.system(size: 14))
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
    static let howItWorks = "A class opens for booking a fixed time before it starts, usually 7 days. The server books it at that moment and sends you a notification. Without the server, you get a notification with a Book button instead. Swipe to remove a class. Cancelling an auto-booked class does not rebook it."
    static func habitNudges(days: Int) -> String {
        "Did a class 3 weeks in a row, then skipped it and booked nothing for \(days) days? You get a morning notification with classes picked from your history."
    }
    static let openings = "One-off classes booked once the moment their window opens, with the same retries and late-spot rule as weekly classes. At most \(AutoBook.maxOpenings) at a time. Swipe to stop waiting."
    static let lateSpots = "Cancelling then costs a strike. Ask me first sends a notification with a Book button instead. Under 3 h before, when cancelling costs 2 strikes (3 under 1 h, as much as a no-show), you're always asked; 12 h or more before, it's always booked."
    static let server = "Books even when your phone is locked or offline: the server checks every five minutes, and every minute shortly before a class opens. While this is on, it keeps your Bruce login to book with; switching it off removes your login and classes from the server."
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

/// Class page action bar for a listed class whose booking window has not opened yet: "Book when booking opens"
/// (a one-off watch, AutoBook.swift `OpeningWatch`) in place of the Book button; "Book every week" stays above.
struct OpeningWatchBar: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    let opens: Date
    @State private var working = false
    var watching: Bool { m.isWatchingOpening(c.id) }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: watching ? "checkmark.circle.fill" : "clock").font(.system(size: 12, weight: .semibold))
                Text(watching ? "Watching · \(Copy.openingWatching(opens))" : "\(Copy.bookingOpens(opens)) · \(Copy.oneOffClass)")
                    .font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(watching ? Theme.teal : Theme.secondary)
            if watching {
                HStack(spacing: 10) {
                    Text(Copy.openingUsed(m.openingWatches.count)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button(working ? "Stopping…" : "Stop watching") { toggle(false) }
                        .font(.system(size: 15, weight: .semibold)).buttonStyle(.glass).controlSize(.regular).disabled(working)
                }
            } else {
                LimeButton(title: working ? "Saving…" : "Book when booking opens", systemImage: "bolt.badge.clock") { toggle(true) }
                    .disabled(working)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
    func toggle(_ on: Bool) {
        working = true
        Task { await m.setWatchOpening(on, for: c); working = false }
    }
}

/// Class page toggle on a full class: the server books it as soon as a waitlist spot frees up.
struct WaitlistAutoBookToggle: View {
    @Environment(AppModel.self) var m
    let c: BruceAPI.BruceClass
    var body: some View {
        Toggle(isOn: Binding(get: { m.isWatchingWaitlist(c.id) }, set: { on in Task { await m.setBookWhenSpotOpens(on, classId: c.id) } })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Book when a spot opens").font(.system(size: 16, weight: .semibold))
                    Text(m.isOnWaitlist(c.id) ? "The server books it the moment a waitlist spot is free and notifies you"
                                              : "Joins the waitlist and books it the moment a spot is free")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            } icon: { Image(systemName: "bolt.badge.clock") }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

// MARK: - Notification taps (Book button on the "Booking opens" notification)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by the app so a tap in the foreground can open the class page.
    @MainActor static var openClass: (@MainActor (Int) -> Void)?
    /// Set by the app: sends a new push token to the auto-book server.
    @MainActor static var onDeviceToken: (@MainActor () -> Void)?
    /// Set by the app: opens a challenge or the goals from a push of our server.
    @MainActor static var openTarget: (@MainActor (PushTarget) -> Void)? { didSet { if let t = pendingTarget, let o = openTarget { pendingTarget = nil; o(t) } } }
    /// A push tapped before the app's UI was up (cold launch); opened once `openTarget` is set.
    @MainActor static var pendingTarget: PushTarget?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AutoBook.registerCategory()
        AutoBook.registerForPush = { UIApplication.shared.registerForRemoteNotifications() }
        // Apple recommends registering at every launch; the token can change.
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard hex != AutoBookServer.deviceToken else { return }
        AutoBookServer.deviceToken = hex
        Task { @MainActor in AppDelegate.onDeviceToken?() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Challenge invites and goal reminders from our server.
        if let t = PushTarget(userInfo: response.notification.request.content.userInfo) {
            await MainActor.run {
                if let o = AppDelegate.openTarget { o(t) } else { AppDelegate.pendingTarget = t }
            }
            return
        }
        let content = response.notification.request.content
        if content.categoryIdentifier == CancelReminders.category, let classId = content.userInfo["classId"] as? Int {
            await MainActor.run { AppDelegate.openClass?(classId) }
            return
        }
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
