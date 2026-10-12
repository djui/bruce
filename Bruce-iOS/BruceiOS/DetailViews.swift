import SwiftUI
import MapKit

// MARK: - Class detail

struct ClassDetailView: View {
    @Environment(AppModel.self) var m
    let classId: Int

    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }
    var studio: BruceAPI.Studio? { c.flatMap { m.studio($0.studioId) } }
    var booking: BruceAPI.Booking? { m.booking(forClass: classId) }

    var body: some View {
        Group {
            if let c { content(c) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let c, case .limited = m.studioLimitState(c.studioId) {
                ToolbarItem(placement: .topBarTrailing) { StudioLimitPill(studioId: c.studioId).font(.system(size: 15, weight: .semibold)) }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: ShareURL.forClass(classId, title: c?.title ?? "")) { Image(systemName: "square.and.arrow.up") }
                if booking == nil {
                    Button { m.toggleBookmark(classId) } label: { Image(systemName: m.isBookmarked(classId) ? "bookmark.fill" : "bookmark") }
                }
            }
        }
        .task {
            await m.loadClassDetail(classId)
            if let sid = m.findClass(classId)?.studioId { await m.loadStudioLimits(sid) }
        }
    }

    func content(_ c: BruceAPI.BruceClass) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(c)
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(classDateLine(c)).font(.system(size: 18, weight: .bold))
                            if let i = c.instructor, !i.isEmpty {
                                Label(i, systemImage: "person.fill").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondary)
                            }
                            if let a = c.availableSpots {
                                Label(a > 5 ? "5+ spots left" : a <= 0 ? "Fully booked" : "\(a) spot\(a == 1 ? "" : "s") left",
                                      systemImage: a <= 0 ? "person.crop.circle.badge.xmark" : "person.3.fill")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(a <= 0 ? Theme.red : Theme.secondary)
                            }
                        }
                        if limitReached(c) { limitNotice }
                        if let r = BookingRules(c) {
                            if booking != nil { bookedBox(r) } else { rulesLines(c, r) }
                        }
                        whoIsBooked.padding(.top, 4)
                    }
                    .padding(Theme.gutter)
                    StudioInfoBlock(studio: studio, description: c.description)
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) { actionBar(c) }
            .onAppear {
                if m.demoScrollBottom { m.demoScrollBottom = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    /// Floating glass action bar (Book / Cancel / Waitlist), as in the original's big pill button.
    @ViewBuilder func actionBar(_ c: BruceAPI.BruceClass) -> some View {
        Group {
            if booking != nil {
                RedButton(title: "Cancel booking") { m.present(.bookingRules(c.id)) }
            } else if m.standby(forClass: c.id) != nil {
                RedButton(title: "Leave waitlist") { m.askLeaveWaitlist(c.id) }
            } else if limitReached(c) {
                // Plan's visits at this studio are used up: the original offers a paid drop-in instead of Book.
                // The purchase call was never captured, so the button only explains that.
                if let p = m.dropInPrice(c) {
                    LimeButton(title: "Buy for \(p.currency) \(p.amount)") { m.flash(Copy.dropInUnavailable) }
                } else {
                    Button {} label: {
                        Text("Visit limit reached").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glass).controlSize(.large).disabled(true)
                }
            } else if (c.availableSpots ?? 1) <= 0 {
                Button { Task { await m.joinWaitlist(c.id) } } label: {
                    Text("Join waitlist").font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                }
                .buttonStyle(.glassProminent).tint(Theme.waitlistOrange).controlSize(.large)
            } else {
                LimeButton(title: "Book") { m.present(.bookingRules(c.id)) }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
    }

    func limitReached(_ c: BruceAPI.BruceClass) -> Bool {
        booking == nil && m.standby(forClass: c.id) == nil && m.visitLimitReached(c)
    }

    var limitNotice: some View {
        Label { Text(Copy.visitLimitReached).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true) }
            icon: { Image(systemName: "info.circle") }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    func rulesLines(_ c: BruceAPI.BruceClass, _ r: BookingRules) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = c.bookableLatestTime.flatMap(BruceDate.parse) {
                iconLine("calendar.badge.checkmark", "Book until \(BruceDate.time(t))")
            }
            iconLine("qrcode.viewfinder", "Check-in \(BruceDate.time(r.checkInFrom)) – \(BruceDate.time(r.lateCheckIn))")
            iconLine("calendar.badge.minus", "Cancel until \(BookingRules.long(r.lateCancel))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    func bookedBox(_ r: BookingRules) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Booked", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .heavy).width(.expanded))
                .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.lime))
            RuleRow(icon: "qrcode.viewfinder", title: "Check in",
                    text: "\(BruceDate.format(r.start, "d MMM yyyy")), \(BruceDate.time(r.checkInFrom)) – \(BruceDate.time(r.lateCheckIn))")
            RuleRow(icon: "calendar.badge.minus", title: "Late cancellation", text: "Cancel after \(BookingRules.long(r.lateCancel))")
            RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation", text: "Cancel after \(BookingRules.long(r.shortNotice))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular.tint(Theme.lime.opacity(0.12)), in: .rect(cornerRadius: 24))
    }

    /// Attendees are anonymised by the API; friends come from GET /v52/booking?friends=true.
    var whoIsBooked: some View {
        let friendUsers = m.friendsBookings.filter { $0.classId == classId || $0.class?.id == classId }
            .compactMap { b in m.friends.first { $0.friendUser?.id == b.userId }?.friendUser }
        return HStack(alignment: .center, spacing: 16) {
            Button { m.present(.invite) } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .glassEffect(.regular.tint(Theme.lime).interactive(), in: .circle)
                    Text("Invite").font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            if friendUsers.isEmpty {
                Text("No friends have booked this class yet").font(.system(size: 15)).foregroundStyle(Theme.secondary)
            } else {
                ForEach(friendUsers, id: \.id) { u in
                    VStack(spacing: 6) {
                        Avatar(fileId: u.photo, initials: u.initials, size: 64)
                        Text(u.firstName ?? "").font(.system(size: 13, weight: .medium))
                    }
                }
            }
        }
    }

    func hero(_ c: BruceAPI.BruceClass) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemotePhoto(fileId: c.photo ?? c.studio?.photo ?? studio?.photo, w: 402, h: 287, symbol: "figure.highintensity.intervaltraining")
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                if let cat = categoryTitle(c) {
                    Text(cat).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                }
                Text(c.title.uppercased()).font(.system(size: 28, weight: .black).width(.expanded)).lineLimit(3).minimumScaleFactor(0.7)
                Text([studio?.name ?? c.studio?.name, studio?.vicinity ?? c.studio?.vicinity].compactMap { $0 }.joined(separator: " | "))
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(.white).padding(Theme.gutter)
        }
        .frame(height: 330).clipped()
    }

    func categoryTitle(_ c: BruceAPI.BruceClass) -> String? {
        let cats = c.classCategories ?? []
        guard let id = (cats.first { $0.main == true } ?? cats.first)?.categoryId else { return nil }
        return m.categories.first { $0.id == id }?.title
    }

    func iconLine(_ sym: String, _ text: String) -> some View {
        Label { Text(text).font(.system(size: 16)) } icon: { Image(systemName: sym).foregroundStyle(Theme.limeInk) }
    }
}

struct RuleRow: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.limeInk).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 15)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Visit limit (tap on the "n / m" pill)

/// Visits used at a studio this month, what is left and when it resets, and the monthly limit of every
/// tier at the studio with the user's plan marked. Data: `user_visit_limit?studio_id=` (`STUDIO` entry and its
/// per-tier `items`), falling back to the studio list's `visit_limit.items`.
struct VisitLimitSheet: View {
    @Environment(AppModel.self) var m
    let studioId: Int

    var body: some View {
        let tiers = m.tierLimits(studioId)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    Text("Visit limits at this studio").font(.system(size: 24, weight: .bold)).padding(.bottom, 4)
                    if tiers.isEmpty {
                        Text("No plan limits available for this studio.").foregroundStyle(Theme.secondary)
                    }
                    ForEach(tiers, id: \.tier) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t.tier).font(.system(size: 18, weight: .heavy).width(.expanded))
                                Text(VisitLimitSheet.limitText(t.limit)).font(.system(size: 16)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            if t.tier == m.tier {
                                Text("YOUR PLAN").font(.system(size: 11, weight: .bold).width(.expanded)).foregroundStyle(Theme.lime)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.black, in: .rect(cornerRadius: 4))
                            }
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    }
                    NavigationLink(value: SheetRoute.plans) {
                        Text("Change plan").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: 40)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.lime).controlSize(.large).padding(.top, 12)
                }
                .padding(Theme.gutter).padding(.top, 8)
            }
        }
        .sheetChrome("")
        .task {
            await m.loadStudioDetail(studioId)
            await m.loadStudioLimits(studioId)
        }
    }

    static func limitText(_ l: Int) -> String {
        l > 0 ? "\(l) visits / mo" : l == 0 ? "Unlimited visits" : "Not included"
    }

    var header: some View {
        let used = m.studioVisitsThisMonth(studioId)
        let reset = m.visitLimitReset(studioId)
        return VStack(alignment: .leading, spacing: 8) {
            Text(m.studioName(studioId)).font(.system(size: 20, weight: .bold))
            switch m.studioLimitState(studioId) {
            case .limited(let total):
                (Text("\(used)").foregroundStyle(Theme.lime) + Text("/\(total)"))
                    .font(.system(size: 56, weight: .light)).monospacedDigit().padding(.top, 8)
                Text("VISITS USED THIS MONTH").font(.system(size: 13, weight: .semibold).width(.expanded)).foregroundStyle(.white.opacity(0.75))
                Text(Copy.visitsLeft(max(0, (m.studioVisitLimit(studioId)?.remaining) ?? (total - used)),
                                     month: BruceDate.format(Date(), "MMMM"), reset: BruceDate.format(reset, "MMMM d")))
                    .font(.system(size: 16)).padding(.top, 6)
            case .unlimited:
                Image(systemName: "infinity").font(.system(size: 48, weight: .light)).foregroundStyle(Theme.lime).padding(.top, 8)
                Text("UNLIMITED VISITS ON YOUR PLAN").font(.system(size: 13, weight: .semibold).width(.expanded)).foregroundStyle(.white.opacity(0.75))
            case .notIncluded:
                Text("0/0").font(.system(size: 56, weight: .light)).padding(.top, 8)
                Text("NOT INCLUDED IN YOUR PLAN").font(.system(size: 13, weight: .semibold).width(.expanded)).foregroundStyle(.white.opacity(0.75))
            case .unknown:
                ProgressView().tint(.white).padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.gutter).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkBG)
    }
}

// MARK: - Booking rules (Book / Cancel confirmation sheet)

struct BookingRulesSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }

    var body: some View {
        ScrollView {
            if let c, let r = BookingRules(c) {
                let booking = m.booking(forClass: classId)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 10) {
                        Text(c.title.uppercased()).font(Theme.heading(22)).multilineTextAlignment(.center)
                        Text("\(classDateLine(c)) at \(m.studioName(c.studioId))").font(.system(size: 16))
                            .foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 22)
                    VStack(alignment: .leading, spacing: 16) {
                        RuleRow(icon: "qrcode.viewfinder", title: "Late check-in", text: "Check-in after \(BookingRules.long(r.lateCheckIn))")
                        RuleRow(icon: "calendar.badge.minus", title: "Late cancellation", text: "Cancel after \(BookingRules.long(r.lateCancel))")
                        RuleRow(icon: "calendar.badge.minus", title: "Short-notice cancellation", text: "Cancel after \(BookingRules.long(r.shortNotice))")
                        RuleRow(icon: "calendar.badge.minus", title: "Last-minute cancellation", text: "Cancel after \(BookingRules.long(r.lastMinute))")
                        RuleRow(icon: "calendar.badge.exclamationmark", title: "No-show", text: Copy.noShow)
                    }
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 26))
                    Group {
                        if let b = booking {
                            RedButton(title: m.loading ? "Cancelling…" : "Cancel booking") { Task { await m.cancel(b); m.dismissSheets() } }
                        } else {
                            LimeButton(title: m.loading ? "Booking…" : "Book") { Task { await m.book(classId: c.id, title: c.title); m.dismissSheets() } }
                        }
                    }
                    .disabled(m.loading).padding(.top, 24)
                    Label(Copy.strikeFooter(unlockPrice: m.unblockPriceKr),
                          systemImage: "info.circle")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondary).padding(.top, 20)
                }
                .padding(Theme.gutter).padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { CloseButton() } }
    }
}

// MARK: - Studio info block (facilities, description, map, address)

struct StudioInfoBlock: View {
    @Environment(AppModel.self) var m
    let studio: BruceAPI.Studio?
    var description: String?
    var showMoreAbout = true
    @Environment(\.openURL) var openURL

    var address: BruceAPI.Address? {
        studio?.studioAddresses?.first { $0.main == true }?.address ?? studio?.studioAddresses?.first?.address
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let facilities = (studio?.studioFacilities ?? []).compactMap { $0.facility }
            if !facilities.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                    ForEach(facilities, id: \.self) { f in
                        Label(f.title ?? "", systemImage: facilityIcon(f.code)).font(.system(size: 15, weight: .medium))
                    }
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
            if let d = description ?? studio?.description, !d.isEmpty {
                Text(d).font(.system(size: 16)).lineSpacing(5)
            }
            if let a = address, let lat = a.latitude, let lon = a.longitude {
                VStack(alignment: .leading, spacing: 0) {
                    MapSnippet(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)).frame(height: 220)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(studio?.name ?? "").font(.system(size: 16, weight: .semibold))
                            Text([a.address, [a.zipCode, a.city].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.joined(separator: ", "))
                                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button { openURL(URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)")!) } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.system(size: 20)).foregroundStyle(.black)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(Theme.lime).controlSize(.large)
                    }
                    .padding(14)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .clipShape(RoundedRectangle(cornerRadius: 26))
            }
            if showMoreAbout, let s = studio {
                NavigationLink(value: Route.studio(s.id)) {
                    InfoRow(title: "More about \(s.name)").padding(16)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
    }

    func facilityIcon(_ code: String?) -> String {
        switch code ?? "" {
        case "shower": return "shower"
        case "locker", "lockers": return "lock"
        case "changing": return "hanger"
        case "sauna": return "thermometer.sun"
        case "towel", "towels": return "rectangle.portrait"
        case "parking": return "parkingsign.circle"
        case "rental", "mat": return "figure.yoga"
        default: return "checkmark.circle"
        }
    }
}

struct MapSnippet: View {
    let coordinate: CLLocationCoordinate2D
    var body: some View {
        if !AppModel.remoteAssets { OfflineMap() } else {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1400, longitudinalMeters: 1400)),
                interactionModes: []) {
                Annotation("", coordinate: coordinate) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 30)).foregroundStyle(.black, Theme.lime)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        }
    }
}

// MARK: - Studio detail

/// Opening-hours state (logic copied from Bruce-MacOS/StudioDetailView.swift).
struct StudioHours {
    let entries: [BruceAPI.ScheduleEntry]?
    let hasOpenings: Bool
    enum State { case open, closingSoon, closed, unknown }

    var current: BruceAPI.ScheduleEntry? {
        let now = Date()
        return (entries ?? []).first { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }
    }
    var closingSoon: Bool {
        guard let e = current, e.isAllDay != true, let end = e.endDate else { return false }
        return end.timeIntervalSince(Date()) <= 60 * 60
    }
    var state: State {
        guard let entries, !(entries.isEmpty && !hasOpenings) else { return .unknown }
        guard current != nil else { return .closed }
        return closingSoon ? .closingSoon : .open
    }
    var title: String {
        guard entries != nil else { return "Opening hours" }
        if let e = current {
            if e.isAllDay == true { return "Solo training open all day" }
            return closingSoon ? "Solo training ends at \(BruceDate.time(e.endDate))" : "Solo training until \(BruceDate.time(e.endDate))"
        }
        return "Closed for solo training right now"
    }
    var color: Color {
        switch state {
        case .closingSoon: return Theme.hoursOrange
        case .closed: return Theme.hoursRed
        default: return Theme.teal
        }
    }
    /// Monday … Sunday of the current week.
    var week: [(Date, BruceAPI.ScheduleEntry?)] {
        let cal = BruceDate.calendar
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            let e = (entries ?? []).first { $0.startDate.map { cal.isDate($0, inSameDayAs: d) } ?? false }
                ?? (entries ?? []).first { $0.startDate.map { cal.component(.weekday, from: $0) == cal.component(.weekday, from: d) } ?? false }
            return (d, e)
        }
    }
}

struct StudioDetailView: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    @State private var tab = 0
    @State private var hoursOpen = false
    @State private var photoPage: Int? = 0

    var studio: BruceAPI.Studio? { m.studio(studioId) }
    var hasClasses: Bool { studio?.hasClasses == true || !(m.studioClasses[studioId] ?? []).isEmpty }
    var classes: [BruceAPI.BruceClass] { (m.studioClasses[studioId] ?? []).sorted { $0.startTime < $1.startTime } }
    var hours: StudioHours { StudioHours(entries: m.schedules[studioId], hasOpenings: studio?.hasOpenings == true) }
    var hasLimit: Bool { if case .unknown = m.studioLimitState(studioId) { return false } else { return true } }
    var tabs: [String] { hasClasses ? ["Information", "Classes", "Reviews"] : ["Information", "Reviews"] }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                // The tab picker is a pinned header (as in the original): it stays under the toolbar while the
                // content scrolls, so nothing large slides beneath the back button.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    photoCarousel.padding(.top, -geo.safeAreaInsets.top)
                    Section {
                        if tab == 0 { information; StudioInfoBlock(studio: studio, showMoreAbout: false) }
                        else if hasClasses && tab == 1 { classesTab }
                        else { StudioReviews(rating: studio?.rating, reviews: m.reviews[studioId], loggedIn: m.isLoggedIn) }
                    } header: {
                        UnderlineTabs(titles: tabs, selection: $tab)
                            .padding(.top, 10)
                            .background(Theme.background)
                            .overlay(alignment: .bottom) { Divider() }
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasLimit {
                ToolbarItem(placement: .topBarTrailing) { StudioLimitPill(studioId: studioId).font(.system(size: 15, weight: .semibold)) }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: ShareURL.forStudio(studioId, name: studio?.name ?? "")) { Image(systemName: "square.and.arrow.up") }
                Button { m.toggleFavorite(studioId) } label: {
                    Image(systemName: m.favorites.contains(studioId) ? "heart.fill" : "heart")
                        .foregroundStyle(m.favorites.contains(studioId) ? Theme.red : Theme.ink)
                }
            }
        }
        .onAppear {
            if m.demoHoursOpen { hoursOpen = true; m.demoHoursOpen = false }
            if m.demoStudioTab != 0 { tab = m.demoStudioTab; m.demoStudioTab = 0 }
        }
        .task {
            await m.loadStudioDetail(studioId)
            await m.loadFavorite(studioId)
            await m.loadStudioLimits(studioId)
            await m.loadSchedule(studioId)
            await m.loadReviews(studioId)
            if studio?.hasClasses == true { await m.loadStudioClasses(studioId) }
        }
    }

    var photos: [String] {
        let ps = (studio?.studioPhotos ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { $0.photo?.fileId }
        return ps.isEmpty ? [studio?.photo ?? "\(studioId)"] : ps.map { "\(studioId)-\($0)" == $0 ? $0 : $0 }
    }

    var photoCarousel: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                        RemotePhoto(fileId: p.count < 3 ? "\(studioId)\(p)" : p, w: 402, h: 287, symbol: "building.2")
                            .containerRelativeFrame(.horizontal).id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $photoPage)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                if studio?.label?.uppercased() == "WELLNESS" {
                    Text("WELLNESS").font(.system(size: 11, weight: .heavy).width(.expanded))
                        .padding(.horizontal, 8).padding(.vertical, 4).glassEffect(.regular, in: .capsule)
                }
                Text((studio?.name ?? "").uppercased()).font(.system(size: 26, weight: .black).width(.expanded)).lineLimit(2).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    if let r = studio?.rating?.average, r > 0 {
                        Image(systemName: "star.fill").font(.system(size: 12))
                        Text(String(format: "%.1f", Double(r) / 100)).fontWeight(.bold)
                        Text("|")
                    }
                    Text([studio?.vicinity, categories].compactMap { $0 }.joined(separator: " | ")).lineLimit(1)
                }
                .font(.system(size: 14, weight: .medium))
                if photos.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<photos.count, id: \.self) { i in
                            Circle().fill(.white.opacity(i == (photoPage ?? 0) ? 1 : 0.45)).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.gutter)
            .allowsHitTesting(false)
        }
        .frame(height: 330).clipped()
    }

    var categories: String? {
        let cats = (studio?.studioCategories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { $0.category?.title }
        return cats.isEmpty ? nil : cats.joined(separator: ", ")
    }

    /// Today's paid-ticket info: schedule attendance info with admission_access=false and a price.
    var ticketPrice: Int? {
        let today = (m.schedules[studioId] ?? []).first { $0.startDate.map { BruceDate.calendar.isDateInToday($0) } ?? false }
        guard let a = today?.attendance, a.admissionAccess == false, let p = a.price, p > 0 else { return nil }
        return p / 100
    }

    @ViewBuilder var notice: some View {
        if let msg = (studio?.alerts ?? []).sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }).compactMap(\.message).first, !msg.isEmpty {
            Label(msg, systemImage: "info.circle.fill").font(.system(size: 14))
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(Theme.lime.opacity(0.15)), in: .rect(cornerRadius: 20))
        }
    }

    var information: some View {
        VStack(alignment: .leading, spacing: 16) {
            notice
            if let b = m.todaysCheckIn(studioId: studioId) {
                LimeButton(title: "Show ticket", systemImage: "ticket") { m.present(.ticket(b.id)) }
            } else if let price = ticketPrice {
                LimeButton(title: "Buy ticket for SEK \(price)") { m.present(.checkout(studioId)) }
            }
            if studio?.hasOpenings == true || m.schedules[studioId]?.isEmpty == false { openingHours }
            if hasClasses {
                Button { withAnimation { tab = 1 } } label: {
                    InfoRow(title: "Show classes", subtitle: m.studioClasses[studioId] == nil ? "Loading…" : "\(classes.count) classes in the next \(m.studioClassDays[studioId] ?? 0) days").padding(16)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
        }
        .padding(Theme.gutter)
    }

    var openingHours: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { hoursOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    Circle().fill(hours.color).frame(width: 10, height: 10)
                    Text(hours.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(hours.color)
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(hoursOpen ? 180 : 0))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .padding(16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hoursOpen {
                VStack(spacing: 10) {
                    ForEach(hours.week, id: \.0) { d, e in
                        let isToday = BruceDate.calendar.isDateInToday(d)
                        HStack {
                            Text(BruceDate.format(d, "EEEE"))
                            Spacer()
                            Text(e.map { $0.isAllDay == true ? "00:00 - 24:00" : "\(BruceDate.time($0.startDate)) - \(BruceDate.time($0.endDate))" } ?? "Closed")
                                .monospacedDigit()
                        }
                        .font(.system(size: 15, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Theme.ink : Theme.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    var classesTab: some View {
        LazyVStack(spacing: 0) {
            ForEach(groupedByDay(classes, date: \.start), id: \.0) { day, list in
                SectionHeaderBar(text: BruceDate.dayHeader(day)).padding(.top, 10)
                ForEach(list) { c in
                    NavigationLink(value: Route.classDetail(c.id)) {
                        ClassRow(c: c, meta: c.instructor ?? "", badge: m.waitlistBadge(c.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Lazy: the next days load when the end of the list scrolls into view (14 days max).
            if m.studioClasses[studioId] != nil && !m.studioClassesComplete(studioId) {
                ProgressView().frame(maxWidth: .infinity).padding(24)
                    .task(id: m.studioClassDays[studioId] ?? 0) { await m.loadMoreStudioClasses(studioId) }
            }
            if classes.isEmpty {
                if m.studioClasses[studioId] == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
                else if m.studioClassesComplete(studioId) { EmptyState(system: "calendar", text: "No upcoming classes.") }
            }
        }
    }
}

// MARK: - Reviews

struct StudioReviews: View {
    let rating: BruceAPI.Rating?
    var reviews: [BruceAPI.Review]? = nil
    var loggedIn = true
    let emoji = ["😍", "😃", "😐", "🙁", "😠"]

    func percent(_ star: Int) -> Double {
        guard let d = rating?.distribution, let total = rating?.total, total > 0 else { return 0 }
        return Double(d[String(star)] ?? 0) / Double(total) * 100
    }
    func label(_ p: Double) -> String { p > 0 && p < 1 ? "< 1 %" : "\(Int(p.rounded())) %" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.ink)
                    Text(rating?.average.map { String(format: "%.1f", Double($0) / 100) } ?? "–").font(.system(size: 30, weight: .black).width(.expanded))
                    Text("\(rating?.total ?? 0) reviews").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
                ForEach(0..<5, id: \.self) { i in
                    let p = percent(5 - i)
                    HStack(spacing: 12) {
                        Text(emoji[i]).font(.system(size: 17))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.chipGrey)
                                Capsule().fill(Theme.ink).frame(width: max(p > 0 ? 6 : 0, g.size.width * p / 100))
                            }
                        }
                        .frame(height: 12)
                        Text(label(p)).font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .padding(Theme.gutter)
            SectionHeaderBar(text: "Comments")
            if let reviews, !reviews.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(reviews.filter { !($0.comment ?? "").isEmpty }) { r in
                        ReviewRow(r: r)
                        Divider().padding(.leading, Theme.gutter)
                    }
                }
            } else if !loggedIn {
                EmptyState(system: "text.bubble", text: "Log in to read comments.")
            } else if reviews == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else {
                EmptyState(system: "text.bubble", text: "No comments yet.")
            }
        }
    }
}

/// One comment: fixed-width avatar/name column (name truncated on one line) so stars, date, title and
/// comment always start at the same x; date right-aligned on the stars row; thin separator below.
struct ReviewRow: View {
    let r: BruceAPI.Review
    static let column: CGFloat = 68
    var body: some View {
        let name = r.booking?.user?.firstName ?? ""
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Avatar(fileId: r.booking?.user?.photo, initials: String(name.prefix(1)), size: 52)
                Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(width: Self.column)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(i < (r.rating ?? 0) ? Theme.ink : Theme.chipGrey)
                        }
                    }
                    Spacer()
                    Text(BruceDate.format(r.createdAt.flatMap(BruceDate.parse), "d MMM yyyy")).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Text(r.activity).font(.system(size: 15, weight: .semibold))
                Text(r.comment ?? "").font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 14)
    }
}

// MARK: - Ticket

struct TicketSheet: View {
    @Environment(AppModel.self) var m
    let bookingId: Int
    var booking: BruceAPI.Booking? { (m.pastBookings + m.bookings).first { $0.id == bookingId } }

    var body: some View {
        Group {
            if let b = booking {
                let checkedIn = b.checkedInAt.flatMap(BruceDate.parse)
                let sid = b.studioId ?? b.class?.studioId ?? 0
                VStack(spacing: 22) {
                    VStack(spacing: 16) {
                        Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 150)
                            .overlay(Circle().stroke(Theme.lime, lineWidth: 5))
                        Text(m.user?.fullName ?? "").font(.system(size: 22, weight: .heavy).width(.expanded))
                        Text(BruceDate.format(checkedIn, "EEEE, d MMMM")).font(.system(size: 16)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 30)
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(.black, Theme.lime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(b.class?.title ?? "Solo training").font(.system(size: 18, weight: .bold))
                            Text(m.studioName(sid)).font(.system(size: 15)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("CHECKED IN").font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(Theme.secondary)
                            Text(BruceDate.time(checkedIn)).font(.system(size: 22, weight: .black)).monospacedDigit()
                        }
                    }
                    .padding(18)
                    .glassEffect(.regular.tint(Theme.lime.opacity(0.18)), in: .rect(cornerRadius: 26))
                    // Animated stripe so staff can tell it is a live screen, not a screenshot.
                    TimelineView(.animation) { t in
                        let x = CGFloat(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2)
                        GeometryReader { g in
                            Capsule().fill(Theme.lime).frame(width: 60).offset(x: x * (g.size.width - 60))
                        }
                        .frame(height: 8)
                    }
                    Spacer()
                }
                .padding(Theme.gutter)
            } else {
                EmptyState(system: "ticket", text: "No check-in today.")
            }
        }
        .navigationTitle("Ticket").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", role: .confirm) { m.dismissSheets() } } }
    }
}

// MARK: - Checkout (display-only: never pays, never adds payment methods)

struct CheckoutSheet: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    var studio: BruceAPI.Studio? { m.studio(studioId) }
    var today: BruceAPI.ScheduleEntry? {
        (m.schedules[studioId] ?? []).first { $0.startDate.map { BruceDate.calendar.isDateInToday($0) } ?? false }
    }
    var price: Int { (today?.attendance?.price ?? 0) / 100 }
    let noPayments = "Payments aren't available in this unofficial client."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                card {
                    Text("Checkout").font(Theme.heading(24))
                    Text("Ticket").font(.system(size: 16, weight: .bold)).padding(.top, 6)
                    HStack { Text("Solo training"); Spacer(); Text("SEK \(price)").fontWeight(.bold) }
                    Text(studio?.name ?? "").foregroundStyle(.white.opacity(0.7))
                    Divider().overlay(.white.opacity(0.2))
                    Text("• \(BruceDate.format(today?.startDate, "EEEE, MMMM d")), \(BruceDate.time(today?.startDate)) - \(BruceDate.time(today?.endDate))")
                    Text(Copy.refundRule)
                    Divider().overlay(.white.opacity(0.2))
                    HStack { Text("Total").fontWeight(.bold); Spacer(); Text("SEK \(price)").fontWeight(.bold) }
                }
                card {
                    Text("Personal data").font(Theme.heading(24))
                    Text("Name").foregroundStyle(.white.opacity(0.6))
                    Text(m.user?.fullName ?? "")
                    Text("National identity number").foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
                    Text(maskedNationalID(m.user?.nationalIdentity))
                }
                card {
                    Text("Payment method").font(Theme.heading(24))
                    if let pm = m.paymentMethods.first(where: { $0.isDefault == true }) ?? m.paymentMethods.first {
                        HStack {
                            Text(pm.type == "APPLE_PAY" ? "Apple Pay" : (pm.type ?? "Card").capitalized).font(.system(size: 17, weight: .medium))
                            Spacer()
                            Text(pm.name ?? "").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.15)))
                        }
                        .padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
                    }
                    Button("New payment method") { m.flash(noPayments) }.buttonStyle(.glass).frame(maxWidth: .infinity)
                }
                Text("Display only: this client never takes payments.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 16))
            .padding(Theme.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            Button { m.flash(noPayments) } label: {
                Text("Pay SEK \(price)").font(.system(size: 17, weight: .bold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent).tint(Theme.neonLime).controlSize(.large).padding(Theme.gutter)
        }
        .sheetChrome("Checkout")
    }

    func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { c() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
