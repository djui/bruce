import SwiftUI

@main
struct BruceiOSApp: App {
    @State private var model = AppModel()
    @StateObject private var ui = UIState()
    @StateObject private var location = LocationProvider()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environment(model).environmentObject(ui).environmentObject(location)
                .onAppear { location.model = model }
                .onChange(of: phase) { _, p in if p == .active { location.start() } else if p == .background { location.stop() } }
        }
    }
}

/// iOS-only UI state (Explore search lives in the Explore tab's toolbar).
final class UIState: ObservableObject {
    @Published var searchActive = false
    @Published var query = ""
    /// Tab that started the search (Home search field); dismissing search returns there.
    var returnTab: Tab?
}

extension SheetRoute: Identifiable { public var id: Self { self } }

/// Lets screens push routes onto a stack other than the current tab's (e.g. inside a sheet).
private struct PushRouteKey: EnvironmentKey { static let defaultValue: ((Route) -> Void)? = nil }
extension EnvironmentValues {
    var pushRoute: ((Route) -> Void)? {
        get { self[PushRouteKey.self] }
        set { self[PushRouteKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var ui: UIState

    var selection: Binding<Tab> {
        Binding(get: { m.tab },
                set: { tab in
                    if tab == m.tab { m.stacks[tab] = [] }   // re-tap pops to root
                    m.tab = tab
                })
    }

    func stack(_ t: Tab) -> Binding<[Route]> {
        Binding(get: { m.stacks[t] ?? [] }, set: { m.stacks[t] = $0 })
    }

    var body: some View {
        Group {
            if m.showWelcome {
                WelcomeView().transition(.opacity)
            } else {
                tabs
            }
        }
        .animation(.easeOut(duration: 0.25), value: m.showWelcome)
        .tint(Theme.ink)  // toolbar icons, toggles, links: label colour as in the original
        .task { await m.bootstrap() }
        .sheet(item: Binding(get: { m.sheets.first }, set: { if $0 == nil { m.dismissSheets() } })) { first in
            SheetContainer(root: first)
        }
        .modifier(ModelAlerts(active: m.sheets.isEmpty))
        .overlay(alignment: .bottom) {
            if m.sheets.isEmpty, let t = m.toast { ToastView(text: t).padding(.bottom, 110).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .overlay(alignment: .top) {
            if m.sheets.isEmpty, !m.showWelcome, let e = m.loadError { ErrorBanner(text: e).padding(.top, 54).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .animation(.spring(duration: 0.3), value: m.loadError)
        .animation(.spring(duration: 0.3), value: m.toast)
        .onChange(of: m.sheets) { _, s in
            // macOS shows the scanner and search as sheets; on iPhone they live in the Check in / Explore tabs.
            if s.first == .checkIn { m.sheets = []; m.tab = .checkIn }
            if s.first == .search { m.sheets = []; ui.searchActive = true }   // focuses the bottom search accessory
        }
        .onAppear {
            if AppModel.setting("BRUCE_SCREEN") == "search" { ui.query = "yoga"; ui.searchActive = true }
            // Hidden developer switch for profiling the real public endpoints without taps.
            if AppModel.flag("BRUCE_AUTOSNEAK") && !m.isLoggedIn { Task { await m.startSneakPeek() } }
        }
    }

    var tabs: some View {
        TabView(selection: selection) {
            SwiftUI.Tab("Home", systemImage: "house", value: Tab.home) {
                NavigationStack(path: stack(.home)) { HomeView().routeDestinations() }
            }
            SwiftUI.Tab("Explore", systemImage: "safari", value: Tab.explore) {
                NavigationStack(path: stack(.explore)) { ExploreView().routeDestinations() }
            }
            SwiftUI.Tab("Check in", systemImage: "qrcode.viewfinder", value: Tab.checkIn) {
                NavigationStack(path: stack(.checkIn)) { CheckInTab().routeDestinations() }
            }
            SwiftUI.Tab("Friends", systemImage: "person.2", value: Tab.friends) {
                NavigationStack(path: stack(.friends)) { FriendsView().routeDestinations() }
            }
            SwiftUI.Tab("My classes", systemImage: "calendar.badge.checkmark", value: Tab.myClasses) {
                NavigationStack(path: stack(.myClasses)) { MyClassesView().routeDestinations() }
            }
            .badge(m.bookings.count)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(SearchAccessoryModifier(enabled: (m.tab == .home || m.tab == .explore) && m.stack.isEmpty))
    }
}

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { r in
            switch r {
            case .classDetail(let id): ClassDetailView(classId: id)
            case .studio(let id): StudioDetailView(studioId: id)
            case .categories: CategoriesGridView()
            case .category(let id): CategoryView(categoryId: id)
            }
        }
    }
}

/// One presented sheet; deeper sheet routes (`m.pushSheet`) push inside its navigation stack.
struct SheetContainer: View {
    @Environment(AppModel.self) var m
    let root: SheetRoute

    var path: Binding<[SheetRoute]> {
        Binding(get: { Array(m.sheets.dropFirst()) },
                set: { m.sheets = [root] + $0 })
    }

    var body: some View {
        NavigationStack(path: path) {
            SheetScreen(route: root)
                .environment(\.sheetIsRoot, true)
                .navigationDestination(for: SheetRoute.self) { SheetScreen(route: $0).environment(\.sheetIsRoot, false) }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .modifier(ModelAlerts(active: true))
        .overlay(alignment: .bottom) {
            if let t = m.toast { ToastView(text: t).padding(.bottom, 40).transition(.opacity) }
        }
        .animation(.spring(duration: 0.3), value: m.toast)
    }

    var detents: Set<PresentationDetent> {
        switch root {
        case .menu, .quickCheckIn: return [.medium, .large]
        case .bookingRules: return [.fraction(0.82), .large]
        default: return [.large]
        }
    }
}

/// Close (X) toolbar button for sheet roots.
struct CloseButton: View {
    @Environment(AppModel.self) var m
    var body: some View {
        Button(role: .close) { m.dismissSheets() }
    }
}

private struct SheetIsRootKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var sheetIsRoot: Bool {
        get { self[SheetIsRootKey.self] }
        set { self[SheetIsRootKey.self] = newValue }
    }
}

/// Standard sheet chrome: inline title, X on the leading side when this screen is the sheet root
/// (pushed sheet screens get the system back button instead).
struct SheetChrome: ViewModifier {
    @Environment(\.sheetIsRoot) var isRoot
    let title: String
    func body(content: Content) -> some View {
        content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { if isRoot { ToolbarItem(placement: .topBarLeading) { CloseButton() } } }
    }
}

extension View {
    func sheetChrome(_ title: String) -> some View { modifier(SheetChrome(title: title)) }
}

struct SheetScreen: View {
    @Environment(AppModel.self) var m
    let route: SheetRoute
    var body: some View {
        switch route {
        case .notifications: NotificationsSheet()
        case .menu: MenuSheet()
        case .account: AccountSheet()
        case .membership: MembershipView()
        case .visits: VisitsView()
        case .credits: CreditsView()
        case .strikes: StrikesView()
        case .payment: PaymentMethodsView()
        case .settings: SettingsView()
        case .login: LoginView()
        case .checkIn: CheckInScanner()
        case .info(let title): PlaceholderPage(title: title)
        case .search: EmptyView()
        case .selectCity: SelectCitySheet()
        case .newArea: NewAreaSheet()
        case .createAccount: CreateAccountView()
        case .resetPassword: ResetPasswordView()
        case .bookingRules(let id): BookingRulesSheet(classId: id)
        case .ticket(let id): TicketSheet(bookingId: id)
        case .checkout(let id): CheckoutSheet(studioId: id).darkScreen()
        case .editProfile: EditProfileView().darkScreen()
        case .pause: PauseMembershipView().darkScreen()
        case .plans: MembershipPlansView().darkScreen()
        case .statistics: StatisticsView()
        case .receipts: ReceiptsView()
        case .invite: InviteSheet()
        case .howItWorks: TextInfoSheet(title: "How it works", paragraphs: howItWorksText)
        case .voucher: VoucherSheet()
        case .support: SupportSheet()
        case .help: HelpSheet()
        case .push: PushSettingsView()
        case .pushInfo: TextInfoSheet(title: "Push settings", paragraphs: pushInfoText)
        case .quickCheckIn: QuickCheckInSheet()
        }
    }
}

extension View {
    /// The original renders account sub-pages (checkout, profile, pause, plans) dark in both modes.
    func darkScreen() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.darkBG.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }
}

/// Confirmation for state-changing actions (book/cancel/check-in/leave waitlist) and info alerts.
/// Attached to the root and to every sheet; only the topmost one is active.
struct ModelAlerts: ViewModifier {
    @Environment(AppModel.self) var m
    let active: Bool
    func body(content: Content) -> some View {
        content
            .alert(m.confirm?.title ?? "", isPresented: Binding(get: { active && m.confirm != nil }, set: { if !$0 { m.confirm = nil } }),
                   presenting: m.confirm) { a in
                Button(a.button) { Task { m.confirm = nil; await a.run(); m.dismissSheets() } }
                Button("Cancel", role: .cancel) { m.confirm = nil }
            } message: { a in Text(a.message) }
            .alert(m.infoAlert ?? "", isPresented: Binding(get: { active && m.infoAlert != nil }, set: { if !$0 { m.infoAlert = nil } })) {
                Button("OK") { m.infoAlert = nil }
            }
    }
}

struct PlaceholderPage: View {
    @Environment(AppModel.self) var m
    let title: String
    var body: some View {
        EmptyState(system: "info.circle", text: "Not available in this unofficial client. Use the official Bruce Studios app for this.")
            .sheetChrome(title)
    }
}

/// Glass error banner with retry (failed loads; offline).
struct ErrorBanner: View {
    @Environment(AppModel.self) var m
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hoursOrange)
            Text(text).font(.system(size: 14, weight: .medium)).lineLimit(2)
            Spacer(minLength: 4)
            Button("Retry") { m.loadError = nil; Task { await m.bootstrap() } }
                .buttonStyle(.glassProminent).tint(Theme.lime).foregroundStyle(.black)
            Button { m.loadError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Theme.gutter)
    }
}

/// Search as the tab bar's bottom accessory (iOS 26 glass). iOS 26.1+: only on the Home and Explore roots;
/// iOS 26.0 cannot hide an accessory per tab, so there it stays visible on every tab.
struct SearchAccessoryModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled) { SearchAccessory() }
        } else {
            content.tabViewBottomAccessory { SearchAccessory() }
        }
    }
}

/// Glass search field. Focusing it starts a search on Explore (switching there from Home); results overlay
/// the Explore page; ✕ / Cancel clears and returns to exactly the originating page.
struct SearchAccessory: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var ui: UIState
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Studios, classes, instructors", text: $ui.query)
                .focused($focused).submitLabel(.search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if ui.searchActive {
                Button { cancel() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel search")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .onChange(of: focused) { _, f in if f { begin() } }
        .onChange(of: ui.searchActive) { _, active in
            if active && !focused { focused = true }
            if !active && focused { focused = false }
        }
    }

    func begin() {
        if !ui.searchActive {
            if m.tab != .explore { ui.returnTab = m.tab; m.tab = .explore }
            ui.searchActive = true
        }
    }

    func cancel() {
        ui.query = ""
        ui.searchActive = false
        focused = false
        if let t = ui.returnTab { ui.returnTab = nil; m.tab = t }
    }
}
