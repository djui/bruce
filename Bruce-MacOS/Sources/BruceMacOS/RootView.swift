import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) var m

    var body: some View {
        ZStack(alignment: .bottom) {
            if m.showWelcome {
                WelcomeView()
            } else {
            VStack(spacing: 0) {
                ZStack {
                    tabContent(m.tab)
                    if let top = m.stack.last {
                        routeView(top).background(Color.white)
                            .transition(.move(edge: .trailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.22), value: m.stack)
                TabBar()
            }
            }
            if m.filterOpen && !m.showWelcome {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.45).onTapGesture { m.filterOpen = false }
                    FilterPanel().frame(width: 318).padding(.vertical, 12).transition(.move(edge: .trailing))
                }
                .transition(.opacity)
            }
            SheetHost()
            if let id = m.classActions { ClassActionSheet(classId: id).transition(.opacity) }
            if let t = m.toast {
                Text(t).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.2)))
                    .padding(.bottom, 90).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: m.toast)
        .animation(.easeOut(duration: 0.25), value: m.filterOpen)
        .animation(.easeOut(duration: 0.2), value: m.classActions)
        .animation(.easeOut(duration: 0.25), value: m.showWelcome)
        .task { await m.bootstrap() }
        .alert(m.confirm?.title ?? "", isPresented: Binding(get: { m.confirm != nil }, set: { if !$0 { m.confirm = nil } }),
               presenting: m.confirm) { a in
            Button(a.button) { Task { m.confirm = nil; let before = m.sheets; await a.run(); if m.sheets == before { m.dismissSheets() } } }
            Button("Cancel", role: .cancel) { m.confirm = nil }
        } message: { a in Text(a.message) }
        .alert(m.infoAlert ?? "", isPresented: Binding(get: { m.infoAlert != nil }, set: { if !$0 { m.infoAlert = nil } })) {
            Button("OK") { m.infoAlert = nil }
        }
    }

    @ViewBuilder func tabContent(_ t: Tab) -> some View {
        switch t {
        case .home, .checkIn: HomeView()
        case .explore: ExploreView()
        case .friends: FriendsView()
        case .myClasses: MyClassesView()
        }
    }

    @ViewBuilder func routeView(_ r: Route) -> some View {
        switch r {
        case .classDetail(let id): ClassDetailView(classId: id)
        case .studio(let id): StudioDetailView(studioId: id)
        case .categories: CategoriesGridView()
        case .category(let id): CategoryView(categoryId: id)
        }
    }
}

struct TabBar: View {
    @Environment(AppModel.self) var m
    private let items: [(Tab, String, String, String)] = [
        (.home, "Home", "house", "house.fill"),
        (.explore, "Explore", "safari", "safari.fill"),
        (.checkIn, "Check in", "viewfinder", "viewfinder"),
        (.friends, "Friends", "person.2", "person.2.fill"),
        (.myClasses, "My classes", "calendar.badge.checkmark", "calendar.badge.checkmark"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { item in
                    Button { m.select(item.0) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: m.tab == item.0 ? item.3 : item.2)
                                .font(.system(size: 22, weight: m.tab == item.0 ? .semibold : .light))
                                .frame(height: 30)
                                .overlay(alignment: .topTrailing) {
                                    if item.0 == .myClasses && !m.upcomingBookings.isEmpty {
                                        Text("\(m.upcomingBookings.count)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                            .frame(minWidth: 22, minHeight: 22).background(Circle().fill(Color(red: 1, green: 0.22, blue: 0.24)))
                                            .offset(x: 14, y: -8)
                                    }
                                }
                            Text(item.1).font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8).padding(.bottom, 12)
        }
        .background(Color.white)
    }
}

/// Bottom-sheet presentation that mimics iOS page sheets inside the phone-sized window.
struct SheetHost: View {
    @Environment(AppModel.self) var m

    var body: some View {
        ZStack(alignment: .bottom) {
            if !m.sheets.isEmpty {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { m.dismissSheets() }
                    .transition(.opacity)
                let first = m.sheets[0]
                Group {
                    if first == .menu {
                        MenuSheet()
                    } else if case .bookingRules(let id) = first {
                        BookingRulesSheet(classId: id)
                    } else {
                        sheetContent(m.sheets.last!)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Color.white)
                            .clipShape(UnevenRoundedCorners(radius: 12))
                            .padding(.top, first == .checkIn ? 18 : 30)
                    }
                }
                .transition(.move(edge: .bottom))
            }
            if m.wellnessOverlay {
                Color.black.opacity(0.4).onTapGesture { m.wellnessOverlay = false }
                WellnessSheet().transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.25), value: m.sheets)
        .animation(.easeOut(duration: 0.25), value: m.wellnessOverlay)
    }

    @ViewBuilder func sheetContent(_ s: SheetRoute) -> some View {
        switch s {
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
        case .checkIn: CheckInView()
        case .info(let title): PlaceholderPage(title: title)
        case .parakey(let id): ParakeySheet(studioId: id)
        case .search: SearchSheet()
        case .selectCity: SelectCitySheet()
        case .newArea: NewAreaSheet()
        case .createAccount: CreateAccountView()
        case .resetPassword: ResetPasswordView()
        case .bookingRules(let id): BookingRulesSheet(classId: id)
        case .ticket(let id): TicketSheet(bookingId: id)
        case .checkout(let id): dark(CheckoutSheet(studioId: id))
        case .editProfile: dark(EditProfileView())
        case .pause: dark(PauseMembershipView())
        case .plans: dark(MembershipPlansView())
        case .visitLimit(let id): VisitLimitSheet(studioId: id)
        case .statistics: StatisticsView()
        case .receipts: ReceiptsView()
        case .classInvite(let id): ClassInviteSheet(classId: id)
        case .invite: InviteSheet()
        case .howItWorks: TextInfoSheet(title: "How it works", paragraphs: Copy.howItWorks(open: m.openInvites))
        case .voucher: VoucherSheet()
        case .support: SupportSheet()
        case .help: HelpSheet()
        case .push: PushSettingsView()
        case .pushInfo: TextInfoSheet(title: "Push settings", paragraphs: Copy.pushInfo)
        case .quickCheckIn: QuickCheckInSheet()
        case .similarClasses(let id): SimilarClassesSheet(classId: id)
        case .area(let id): AreaMapSheet(areaId: id)
        case .review(let id): ReviewSheet(bookingId: id)
        case .autoBook: AutoBookView()
        }
    }
}

func dark<V: View>(_ v: V) -> some View {
    v.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.darkBG).foregroundStyle(.white).environment(\.colorScheme, .dark)
}

struct UnevenRoundedCorners: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + radius),
             cornerRadius: radius)
    }
}

struct PlaceholderPage: View {
    @Environment(AppModel.self) var m
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: title, leading: m.sheets.count > 1 ? .back : .close) {
                m.sheets.count > 1 ? m.popSheet() : m.dismissSheets()
            }
            EmptyState(system: "info.circle", text: "Not available in this Mac version. Use the Bruce iOS app for this.")
        }
    }
}
