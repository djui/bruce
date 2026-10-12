import SwiftUI

extension Theme {
    static let teal = Color(red: 0.16, green: 0.69, blue: 0.60)
    static let barTrack = Color(white: 0.965)
}

struct StudioDetailView: View {
    @Environment(AppModel.self) var m
    let studioId: Int
    @State private var tab = 0
    @State private var hoursOpen = false

    var studio: BruceAPI.Studio? { m.studio(studioId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                IconButton(system: "chevron.left", size: 20) { m.pop() }
                Spacer()
                StudioLimitPill(studioId: studioId)
                ShareButton(url: ShareURL.forStudio(studioId, name: studio?.name ?? ""))
                IconButton(system: m.favorites.contains(studioId) ? "heart.fill" : "heart", size: 22) { m.toggleFavorite(studioId) }
            }
            .padding(.horizontal, Theme.gutter).frame(height: 56)
            UnderlineTabs(titles: hasClasses ? ["Information", "Classes", "Reviews"] : ["Information", "Reviews"], selection: $tab)
            ScrollView {
                if tab == 0 { information }
                else if hasClasses && tab == 1 { classesTab }
                else { StudioReviews(rating: studio?.rating, reviews: m.reviews[studioId]) }
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

    // MARK: Information

    var hasClasses: Bool { studio?.hasClasses == true || !(m.studioClasses[studioId] ?? []).isEmpty }
    var classes: [BruceAPI.BruceClass] { (m.studioClasses[studioId] ?? []).sorted { $0.startTime < $1.startTime } }

    /// Notice banner from studio `alerts[].message` (e.g. door/kiosk instructions).
    @ViewBuilder var notice: some View {
        if let msg = studio?.notice {
            Text(msg).font(.system(size: 15, weight: .light)).multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sectionGrey))
                .padding(.horizontal, Theme.gutter).padding(.vertical, 16)
        }
    }

    var classesRow: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, Theme.gutter)
            Button { tab = 1 } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show classes").font(.system(size: 17, weight: .medium))
                        Text(m.studioClasses[studioId] == nil ? "Loading…" : "\(classes.count) classes")
                            .font(.system(size: 15, weight: .light)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    var classesTab: some View {
        let groups = Dictionary(grouping: classes) { BruceDate.calendar.startOfDay(for: $0.start ?? Date()) }
        return LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(groups.keys.sorted(), id: \.self) { day in
                Section(header: SectionHeaderBar(text: BruceDate.dayHeader(day))) {
                    ForEach(groups[day]!) { c in
                        Button { m.push(.classDetail(c.id)) } label: {
                            ClassRow(time: BruceDate.time(c.start), duration: c.durationMinutes.map { "\($0) min" } ?? "",
                                     title: c.title, studio: studio?.name ?? "", meta: c.instructor ?? "",
                                     badge: m.standby(forClass: c.id) != nil ? "Waitlist" : nil, classId: c.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if m.studioClasses[studioId] != nil && !m.studioClassesComplete(studioId) {
                ProgressView().padding(20).task(id: m.studioClassDays[studioId] ?? 0) { await m.loadMoreStudioClasses(studioId) }
            }
            if classes.isEmpty && (m.studioClasses[studioId] == nil || m.studioClassesComplete(studioId)) {
                Text(m.studioClasses[studioId] == nil ? "Loading classes…" : "No upcoming classes.")
                    .foregroundStyle(Theme.secondary).padding(.top, 40)
            }
        }
    }

    var information: some View {
        VStack(alignment: .leading, spacing: 0) {
            notice
            photoCarousel
            actionButton.padding(.horizontal, Theme.gutter).padding(.top, 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(studio?.name ?? "").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 4) {
                    if studio?.label?.uppercased() == "WELLNESS" {
                        Text("Wellness").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.cardBorder))
                            .padding(.trailing, 6)
                    }
                    if let a = studio?.rating?.average, a > 0 {
                        Image(systemName: "star.fill").font(.system(size: 11))
                        Text(String(format: "%.1f", Double(a) / 100) + " |")
                    }
                    Text([studio?.vicinity, mainCategory].compactMap { $0 }.joined(separator: " | "))
                }
                .font(.system(size: 15, weight: .light)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 18)
            openingHours.padding(.top, 22)
            if hasClasses { classesRow }
            StudioInfoBlock(studio: studio, showMoreAbout: false)
        }
    }

    @State private var photoPage = 0
    var photos: [String] {
        let ps = (studio?.studioPhotos ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { $0.photo?.fileId }
        return ps.isEmpty ? [studio?.photo ?? ""] : ps
    }
    var photoCarousel: some View {
        ZStack(alignment: .bottom) {
            TabViewLike(count: photos.count, page: $photoPage) { i in RemotePhoto(fileId: photos[i], w: 402, h: 287) }
            if photos.count > 1 {
                HStack(spacing: 7) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        Circle().fill(Color.white.opacity(i == photoPage ? 1 : 0.5)).frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(height: 212).clipped()
    }

    /// Today's paid-ticket info: schedule `studio_user_attendance_info` with admission_access=false and a price [c4:31].
    var ticketPrice: Int? {
        let today = (m.schedules[studioId] ?? []).first { $0.startDate.map { BruceDate.calendar.isDateInToday($0) } ?? false }
        guard let a = today?.attendance, a.admissionAccess == false, let p = a.price, p > 0 else { return nil }
        return p / 100
    }

    /// All studio categories, comma-joined in API order ("Swimming, Gym").
    var mainCategory: String? {
        let cats = (studio?.studioCategories ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }.compactMap { $0.category?.title }
        return cats.isEmpty ? nil : cats.joined(separator: ", ")
    }

    /// Only "Show ticket" (checked in today) or "Buy ticket" (paid access). Open or closed studios otherwise show
    /// no lime button (screenshots 73-80); check-in happens from the Check in tab / Home check-in control.
    @ViewBuilder var actionButton: some View {
        if let b = m.todaysCheckIn(studioId: studioId) {
            LimeButton(title: "Show ticket") { m.present(.ticket(b.id)) }
        } else if let price = ticketPrice {
            LimeButton(title: "Buy ticket for SEK \(price)") { m.present(.checkout(studioId)) }
        }
    }

    // MARK: Opening hours

    var week: [(Date, BruceAPI.ScheduleEntry?)] {
        let cal = BruceDate.calendar
        let entries = m.schedules[studioId] ?? []
        // Monday … Sunday of the current week.
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)            // 1 = Sunday
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            // Schedule only covers today + 6 days; use the same weekday's entry as a stand-in for past days.
            let e = entries.first { $0.startDate.map { cal.isDate($0, inSameDayAs: d) } ?? false }
                ?? entries.first { $0.startDate.map { cal.component(.weekday, from: $0) == cal.component(.weekday, from: d) } ?? false }
            return (d, e)
        }
    }

    var hoursTitle: String {
        guard m.schedules[studioId] != nil else { return "Opening hours" }
        let now = Date()
        let today = (m.schedules[studioId] ?? []).filter { $0.startDate.map { BruceDate.calendar.isDateInToday($0) } ?? false }
        if let e = today.first(where: { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }) {
            if e.isAllDay == true { return "Solo training open all day" }
            return closingSoon ? "Solo training ends at \(BruceDate.time(e.endDate))" : "Solo training until \(BruceDate.time(e.endDate))"
        }
        _ = today
        return "Closed for solo training right now"
    }

    enum HoursState { case open, closingSoon, closed, unknown }
    /// teal "until" = open, orange "ends at" = closing soon, red = closed now.
    /// Threshold 60 min: bounded but unconfirmed (orange seen at 29-38 min left, teal at 2 h 38 min).
    var hoursState: HoursState {
        guard let entries = m.schedules[studioId], !(entries.isEmpty && studio?.hasOpenings != true) else { return .unknown }
        let now = Date()
        guard entries.contains(where: { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }) else { return .closed }
        return closingSoon ? .closingSoon : .open
    }
    var hoursColor: Color {
        switch hoursState {
        case .closingSoon: return Color(red: 0.95, green: 0.6, blue: 0.1)
        case .closed: return Color(red: 0.93, green: 0.22, blue: 0.24)
        default: return Theme.teal
        }
    }
    var closingSoon: Bool {
        let now = Date()
        guard let e = (m.schedules[studioId] ?? []).first(where: { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }),
              e.isAllDay != true, let end = e.endDate else { return false }
        return end.timeIntervalSince(now) <= 60 * 60
    }

    @ViewBuilder var openingHours: some View {
        if studio?.hasOpenings == true || m.schedules[studioId]?.isEmpty == false {
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.2)) { hoursOpen.toggle() } } label: {
                    HStack {
                        Text(hoursTitle).font(.system(size: 17, weight: .light))
                            .foregroundStyle(hoursColor)
                        Spacer()
                        Image(systemName: hoursOpen ? "chevron.up" : "chevron.down").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, Theme.gutter).frame(height: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if hoursOpen {
                    VStack(spacing: 12) {
                        ForEach(week, id: \.0) { d, e in
                            let isToday = BruceDate.calendar.isDateInToday(d)
                            HStack {
                                Text(BruceDate.format(d, "EEEE"))
                                Spacer()
                                Text(e.map { $0.isAllDay == true ? "00:00 - 24:00" : "\(BruceDate.time($0.startDate)) - \(BruceDate.time($0.endDate))" } ?? "Closed")
                            }
                            .font(.system(size: 16, weight: isToday ? .semibold : .light))
                            .foregroundStyle(isToday ? Theme.ink : Theme.tertiary)
                        }
                    }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - Reviews

/// Aggregate from studio `rating`; comments from GET /v52/review (c3:101), loaded at runtime only.
struct StudioReviews: View {
    let rating: BruceAPI.Rating?
    var reviews: [BruceAPI.Review]? = nil

    let emoji = ["😍", "😃", "😐", "🙁", "😠"]

    func percent(_ star: Int) -> Double {
        guard let d = rating?.distribution, let total = rating?.total, total > 0 else { return 0 }
        return Double(d[String(star)] ?? 0) / Double(total) * 100
    }

    func label(_ p: Double) -> String {
        if p > 0 && p < 1 { return "< 1 %" }
        return "\(Int(p.rounded())) %"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "star.fill").font(.system(size: 20))
                Text(rating?.average.map { String(format: "%.1f", Double($0) / 100) } ?? "–").font(.system(size: 26, weight: .semibold))
                Text("\(rating?.total ?? 0) reviews").font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
            }
            .padding(.leading, 50).padding(.top, 22)
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let p = percent(5 - i)
                    HStack(spacing: 14) {
                        Text(emoji[i]).font(.system(size: 18))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.barTrack)
                                Rectangle().fill(Theme.ink).frame(width: max(p > 0 ? 1.5 : 0, g.size.width * p / 100))
                            }
                        }
                        .frame(height: 20)
                        Text(label(p)).font(.system(size: 15, weight: .light)).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 28)
            SectionHeaderBar(text: "Comments")
            if let reviews, !reviews.isEmpty {
                ForEach(reviews.filter { !($0.comment ?? "").isEmpty }) { r in
                    ReviewRow(name: r.booking?.user?.firstName ?? "", photo: r.booking?.user?.photo, stars: r.rating ?? 0,
                              date: r.createdAt.flatMap(BruceDate.parse), activity: r.activity, text: r.comment ?? "")
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble").font(.system(size: 34, weight: .light))
                    Text(reviews == nil ? "Loading comments…" : "No comments yet.").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
    }
}

/// One comment row (layout of the original; used only if a reviews source becomes available).
struct ReviewRow: View {
    let name: String
    let photo: String?
    let stars: Int
    let date: Date?
    let activity: String
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                // Fixed column: long names truncate ("Tuva Elv…") so stars/date/text always start at the same x.
                VStack(spacing: 6) {
                    Avatar(fileId: photo, initials: String(name.prefix(1)), size: 50)
                    Text(name).font(.system(size: 12, weight: .light)).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 68)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: "star.fill").font(.system(size: 11))
                                    .foregroundStyle(i < stars ? Theme.ink : Color(white: 0.93))
                            }
                        }
                        Spacer()
                        Text(BruceDate.format(date, "d MMM yyyy")).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                    }
                    Text(activity).font(.system(size: 16, weight: .semibold))
                    Text(text).font(.system(size: 15, weight: .light))
                }
            }
            .padding(.vertical, 14).padding(.trailing, Theme.gutter)
            Rectangle().fill(Theme.divider).frame(height: 0.5)
        }
        .padding(.leading, Theme.gutter)
    }
}

// MARK: - Ticket

struct TicketSheet: View {
    @Environment(AppModel.self) var m
    let bookingId: Int
    var booking: BruceAPI.Booking? { (m.pastBookings + m.bookings).first { $0.id == bookingId } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Ticket").font(.system(size: 17, weight: .bold))
                HStack {
                    Spacer()
                    Button { m.dismissSheets() } label: { Text("Done").underline().font(.system(size: 16, weight: .medium)) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter).frame(height: 56)
            if let b = booking {
                let checkedIn = b.checkedInAt.flatMap(BruceDate.parse)
                HStack(alignment: .top, spacing: 18) {
                    Text(BruceDate.time(checkedIn)).font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.class?.title ?? "Solo training").font(.system(size: 18, weight: .semibold))
                        Text("#" + String(b.studioId ?? b.class?.studioId ?? 0)).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle").font(.system(size: 30, weight: .light))
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 20)
                Spacer()
                VStack(spacing: 18) {
                    Avatar(fileId: m.user?.photo, initials: m.user?.initials ?? "", size: 180)
                    Text(m.user?.fullName ?? "").font(.system(size: 17, weight: .light))
                    Text(BruceDate.format(checkedIn, "EEEE, MMMM d")).font(.system(size: 17, weight: .light))
                }
                Spacer(); Spacer()
            } else {
                EmptyState(system: "ticket", text: "No check-in today.")
            }
        }
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

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Checkout").font(.system(size: 19, weight: .bold))
                HStack { IconButton(system: "xmark", size: 22) { m.dismissSheets() }; Spacer() }
            }
            .frame(height: 56).padding(.horizontal, Theme.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    card {
                        Text("Checkout").font(.system(size: 26, weight: .heavy).width(.expanded))
                        Text("Membership").font(.system(size: 16, weight: .bold)).padding(.top, 10)
                        Divider().overlay(Color.white.opacity(0.15))
                        HStack { Text("Solo training"); Spacer(); Text("SEK \(price)").fontWeight(.bold) }
                        Text(studio?.name ?? "")
                        HStack { Text("Got a campaign code?").fontWeight(.bold); Spacer(); Image(systemName: "plus") }
                            .padding(.vertical, 8)
                        Divider().overlay(Color.white.opacity(0.15))
                        Text("• \(BruceDate.format(today?.startDate, "EEEE, MMMM d")), \(BruceDate.time(today?.startDate)) - \(BruceDate.time(today?.endDate))")
                        Text(Copy.refundRule)
                        Divider().overlay(Color.white.opacity(0.15))
                        HStack { Text("Total").fontWeight(.bold); Spacer(); Text("SEK \(price)").fontWeight(.bold) }
                    }
                    card {
                        Text("Personal data").font(.system(size: 26, weight: .heavy).width(.expanded))
                        Text("Name").foregroundStyle(Color.white.opacity(0.6))
                        Text(m.user?.fullName ?? "")
                        Text("National identity number").foregroundStyle(Color.white.opacity(0.6)).padding(.top, 6)
                        Text(maskedNationalID(m.user?.nationalIdentity))
                        HStack { Spacer(); Text("Verified with"); Text("BankID").font(.system(size: 13, weight: .heavy)).italic() }
                    }
                    card {
                        Text("Payment method").font(.system(size: 26, weight: .heavy).width(.expanded))
                        if let pm = m.paymentMethods.first(where: { $0.isDefault == true }) ?? m.paymentMethods.first {
                            HStack {
                                Text(pm.type == "APPLE_PAY" ? "Apple Pay" : (pm.type ?? "Card").capitalized).font(.system(size: 17, weight: .medium))
                                Spacer()
                                Text(pm.name ?? "").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.15)))
                            }
                            .padding(16).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 2))
                        }
                        Button { m.flash(noPayments) } label: {
                            Text("New payment method").font(.system(size: 17, weight: .medium)).foregroundStyle(.black)
                                .padding(.horizontal, 22).frame(height: 44).background(Capsule().fill(Color(white: 0.92)))
                        }
                        .buttonStyle(.plain).frame(maxWidth: .infinity)
                    }
                    Text(Copy.noticePeriod(m.membership))
                        .font(.system(size: 14, weight: .light)).foregroundStyle(Color.white.opacity(0.8)).padding(.top, 8)
                }
                .font(.system(size: 16, weight: .light))
                .padding(.horizontal, Theme.gutter).padding(.bottom, 20)
            }
            Button { m.flash(noPayments) } label: {
                Text("Pay SEK \(price)").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(Theme.neonLime))
            }
            .buttonStyle(.plain).padding(.horizontal, Theme.gutter).padding(.bottom, 20)
        }
    }

    let noPayments = "Payments aren't available in this unofficial client."

    func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { c() }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18)))
    }
}

